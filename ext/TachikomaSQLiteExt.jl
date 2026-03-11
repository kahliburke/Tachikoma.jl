module TachikomaSQLiteExt

using Tachikoma
using SQLite
using DBInterface

# ── SQLitePagedProvider ──────────────────────────────────────────────

mutable struct SQLitePagedProvider <: PagedDataProvider
    db::SQLite.DB
    table_name::String
    columns::Vector{PagedColumn}
    db_col_names::Vector{String}   # actual DB column names
    _caps::FilterCapabilities
end

"""
    SQLitePagedProvider(db::SQLite.DB, table_name::String; kwargs...)

Create a paged data provider backed by a SQLite table. Introspects the schema
via `PRAGMA table_info` to determine column names and types.

# Keyword Arguments
- `columns::Vector{PagedColumn}`: override column definitions (default: auto from schema)
- `filterable::Bool=true`: whether columns are filterable by default
- `sortable::Bool=true`: whether columns are sortable by default
"""
function SQLitePagedProvider(db::SQLite.DB, table_name::String;
    columns::Union{Vector{PagedColumn}, Nothing}=nothing,
    filterable::Bool=true,
    sortable::Bool=true,
)
    # Introspect schema
    info = DBInterface.execute(db, "PRAGMA table_info(\"$table_name\")")
    db_col_names = String[]
    auto_columns = PagedColumn[]

    for row in info
        col_name = string(row[2])  # name
        col_type_str = uppercase(string(row[3]))  # type
        push!(db_col_names, col_name)

        col_type = if occursin(r"INT|REAL|FLOAT|DOUBLE|NUMERIC|DECIMAL", col_type_str)
            :numeric
        else
            :text
        end
        align = col_type == :numeric ? Tachikoma.col_right : Tachikoma.col_left
        push!(auto_columns, PagedColumn(col_name; align, filterable, sortable, col_type))
    end

    cols = columns !== nothing ? columns : auto_columns

    # Register REGEXP function for regex support
    SQLite.register(db, (pat, val) -> begin
        val === missing && return false
        try
            occursin(Regex(string(pat), "i"), string(val))
        catch
            false
        end
    end, nargs=2, name="REGEXP")

    # Capabilities: include regex since REGEXP is registered
    text_ops = [filter_contains, filter_eq, filter_neq, filter_regex]
    numeric_ops = [filter_eq, filter_neq, filter_gt, filter_gte, filter_lt, filter_lte]
    caps = FilterCapabilities(text_ops, numeric_ops)

    SQLitePagedProvider(db, table_name, cols, db_col_names, caps)
end

Tachikoma.column_defs(p::SQLitePagedProvider) = p.columns
Tachikoma.supports_search(::SQLitePagedProvider) = true
Tachikoma.supports_filter(::SQLitePagedProvider) = true
Tachikoma.filter_capabilities(p::SQLitePagedProvider) = p._caps

# ── SQL filter translation ───────────────────────────────────────────

function _filter_to_sql(cf::ColumnFilter, col_name::String)
    op = cf.op
    val = cf.value

    if op == filter_contains
        return "CAST(\"$col_name\" AS TEXT) LIKE ?", "%$val%"
    elseif op == filter_eq
        return "\"$col_name\" = ?", val
    elseif op == filter_neq
        return "\"$col_name\" != ?", val
    elseif op == filter_gt
        return "CAST(\"$col_name\" AS REAL) > ?", val
    elseif op == filter_gte
        return "CAST(\"$col_name\" AS REAL) >= ?", val
    elseif op == filter_lt
        return "CAST(\"$col_name\" AS REAL) < ?", val
    elseif op == filter_lte
        return "CAST(\"$col_name\" AS REAL) <= ?", val
    elseif op == filter_regex
        return "\"$col_name\" REGEXP ?", val
    elseif op == filter_wildcard
        return "CAST(\"$col_name\" AS TEXT) LIKE ?", val
    else
        return "1=1", ""
    end
end

# ── fetch_page ───────────────────────────────────────────────────────

function Tachikoma.fetch_page(p::SQLitePagedProvider, req::PageRequest)
    where_clauses = String[]
    params = Any[]

    # Global search: OR across all text-castable columns
    if !isempty(req.search)
        parts = ["CAST(\"$c\" AS TEXT) LIKE ?" for c in p.db_col_names]
        push!(where_clauses, "(" * join(parts, " OR ") * ")")
        append!(params, ["%$(req.search)%" for _ in p.db_col_names])
    end

    # Per-column filters → SQL operators
    for (ci, cf) in req.filters
        ci > length(p.db_col_names) && continue
        isempty(cf.value) && continue
        sql_clause, sql_param = _filter_to_sql(cf, p.db_col_names[ci])
        push!(where_clauses, sql_clause)
        push!(params, sql_param)
    end

    where_sql = isempty(where_clauses) ? "" : " WHERE " * join(where_clauses, " AND ")

    # COUNT query
    count_params = copy(params)
    total = first(DBInterface.execute(p.db,
        "SELECT COUNT(*) FROM \"$(p.table_name)\"$where_sql", count_params))[1]

    # ORDER BY
    order_sql = ""
    if req.sort_col > 0 && req.sort_col <= length(p.db_col_names) && req.sort_dir != Tachikoma.sort_none
        dir = req.sort_dir == Tachikoma.sort_asc ? "ASC" : "DESC"
        order_sql = " ORDER BY \"$(p.db_col_names[req.sort_col])\" $dir"
    end

    # LIMIT/OFFSET
    offset = (req.page - 1) * req.page_size
    data_sql = "SELECT * FROM \"$(p.table_name)\"$where_sql$order_sql LIMIT ? OFFSET ?"

    data_params = copy(params)
    push!(data_params, req.page_size)
    push!(data_params, offset)

    ncols = length(p.db_col_names)
    rows = Vector{Any}[]
    for r in DBInterface.execute(p.db, data_sql, data_params)
        row = Any[r[i] for i in 1:ncols]
        push!(rows, row)
    end

    PageResult(rows, total)
end

function __init__()
    Tachikoma._create_sqlite_provider[] = (db, table_name; kwargs...) ->
        SQLitePagedProvider(db, table_name; kwargs...)
    @info "Tachikoma: SQLite database provider enabled"
end

end # module
