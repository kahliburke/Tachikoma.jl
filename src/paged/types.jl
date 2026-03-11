# ═══════════════════════════════════════════════════════════════════════
# PagedDataTable ── virtual data table with provider-delegated paging
# ═══════════════════════════════════════════════════════════════════════

# ── Provider protocol ─────────────────────────────────────────────────

abstract type PagedDataProvider end

# ── Filter types ─────────────────────────────────────────────────────

@enum FilterOp begin
    filter_contains       # substring match (text default)
    filter_eq             # =
    filter_neq            # !=
    filter_gt             # >
    filter_gte            # >=
    filter_lt             # <
    filter_lte            # <=
    filter_regex          # regex (text, provider declares support)
    filter_wildcard       # glob/LIKE pattern (text, provider declares support)
end

struct ColumnFilter
    op::FilterOp
    value::String
end

struct FilterCapabilities
    text_ops::Vector{FilterOp}
    numeric_ops::Vector{FilterOp}
end

const DEFAULT_TEXT_OPS = [filter_contains, filter_eq, filter_neq]
const DEFAULT_NUMERIC_OPS = [filter_eq, filter_neq, filter_gt, filter_gte, filter_lt, filter_lte]
FilterCapabilities() = FilterCapabilities(DEFAULT_TEXT_OPS, DEFAULT_NUMERIC_OPS)

function filter_op_label(op::FilterOp)
    op == filter_contains && return "contains"
    op == filter_eq       && return "="
    op == filter_neq      && return "≠"
    op == filter_gt       && return ">"
    op == filter_gte      && return "≥"
    op == filter_lt       && return "<"
    op == filter_lte      && return "≤"
    op == filter_regex    && return "regex"
    op == filter_wildcard && return "wildcard"
    string(op)
end

# ── Column & request types ───────────────────────────────────────────

struct PagedColumn
    name::String
    width::Int                          # 0 = auto
    align::ColumnAlign                  # reuse existing enum
    format::Union{Function, Nothing}    # value -> String
    filterable::Bool
    sortable::Bool
    col_type::Symbol                    # :numeric, :text
end

function PagedColumn(name::String;
    width::Int=0,
    align::ColumnAlign=col_left,
    format::Union{Function, Nothing}=nothing,
    filterable::Bool=true,
    sortable::Bool=true,
    col_type::Symbol=:text,
)
    PagedColumn(name, width, align, format, filterable, sortable, col_type)
end

struct PageRequest
    page::Int
    page_size::Int
    sort_col::Int               # 0 = no sort
    sort_dir::SortDir           # reuse existing enum
    filters::Dict{Int,ColumnFilter}   # col_index => typed filter
    search::String
end

struct PageResult
    rows::Vector{Vector{Any}}   # row-major: each inner vector is one row
    total_count::Int
end

"""
    fetch_page(provider::PagedDataProvider, request::PageRequest) -> PageResult

Fetch a page of data. Providers must implement this method.
"""
function fetch_page end

"""
    column_defs(provider::PagedDataProvider) -> Vector{PagedColumn}

Return column definitions. Providers must implement this method.
"""
function column_defs end

"""Return whether the provider supports global text search."""
supports_search(::PagedDataProvider) = false

"""Return whether the provider supports per-column filtering."""
supports_filter(::PagedDataProvider) = false

"""Return filter capabilities (supported operators per column type)."""
filter_capabilities(::PagedDataProvider) = FilterCapabilities()

# SQLite extension hook — set by TachikomaSQLiteExt.__init__
# Signature: (db, table_name; kwargs...) -> PagedDataProvider
const _create_sqlite_provider = Ref{Union{Function, Nothing}}(nothing)

"""
    create_sqlite_provider(db, table_name; kwargs...) -> PagedDataProvider

Create a SQLite-backed paged data provider. Requires the SQLite extension to be loaded
(via `using SQLite` or `enable_sqlite()`).
"""
function create_sqlite_provider(db, table_name::String; kwargs...)
    fn = _create_sqlite_provider[]
    fn === nothing && error("SQLite extension not loaded. Call `using SQLite` or `enable_sqlite()` first.")
    fn(db, table_name; kwargs...)
end

# ── Filter application helper ─────────────────────────────────────────

function apply_filter(op::FilterOp, filter_val::String, cell_val, col_type::Symbol)
    if col_type == :numeric
        num = tryparse(Float64, filter_val)
        num === nothing && return true  # invalid → don't exclude
        cell_num = cell_val isa Number ? Float64(cell_val) : tryparse(Float64, string(cell_val))
        cell_num === nothing && return false
        op == filter_eq  && return cell_num == num
        op == filter_neq && return cell_num != num
        op == filter_gt  && return cell_num > num
        op == filter_gte && return cell_num >= num
        op == filter_lt  && return cell_num < num
        op == filter_lte && return cell_num <= num
        return true
    else  # :text
        s = lowercase(string(cell_val))
        q = lowercase(filter_val)
        op == filter_contains && return occursin(q, s)
        op == filter_eq       && return s == q
        op == filter_neq      && return s != q
        op == filter_regex    && return occursin(Regex(filter_val, "i"), string(cell_val))
        return occursin(q, s)
    end
end

# ── Filter modal state ────────────────────────────────────────────────

mutable struct FilterModalState
    visible::Bool
    section::Int              # 1=column list, 2=operator, 3=value input
    col_cursor::Int           # highlighted column in section 1
    op_cursor::Int            # highlighted operator in section 2
    available_ops::Vector{FilterOp}  # populated when column is chosen
    value_input::TextInput
end

FilterModalState() = FilterModalState(false, 1, 1, 1, FilterOp[], TextInput(; label="Value: ", focused=true))
