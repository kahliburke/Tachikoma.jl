# ── InMemoryPagedProvider ─────────────────────────────────────────────

"""
    InMemoryPagedProvider(columns, data)

Built-in provider that wraps column-major `Vector{Vector{Any}}` data and
implements sorting, substring search, and per-column filtering in-process.
This is the paged equivalent of passing vectors directly to `DataTable`.

# Arguments
- `columns::Vector{PagedColumn}`: column definitions
- `data::Vector{Vector{Any}}`: column-major data (each inner vector is one column)
"""
struct InMemoryPagedProvider <: PagedDataProvider
    columns::Vector{PagedColumn}
    data::Vector{Vector{Any}}   # column-major for efficient sorting/filtering
end

column_defs(p::InMemoryPagedProvider) = p.columns
supports_search(::InMemoryPagedProvider) = true
supports_filter(::InMemoryPagedProvider) = true

function fetch_page(p::InMemoryPagedProvider, req::PageRequest)
    nrows = isempty(p.data) ? 0 : length(p.data[1])
    indices = collect(1:nrows)

    # Search: substring match across all columns
    if !isempty(req.search)
        q = lowercase(req.search)
        indices = filter(indices) do ri
            for ci in 1:length(p.data)
                occursin(q, lowercase(string(p.data[ci][ri]))) && return true
            end
            false
        end
    end

    # Per-column filters
    for (ci, cf) in req.filters
        isempty(cf.value) && continue
        ci > length(p.data) && continue
        col_type = ci <= length(p.columns) ? p.columns[ci].col_type : :text
        indices = filter(ri -> apply_filter(cf.op, cf.value, p.data[ci][ri], col_type), indices)
    end

    total = length(indices)

    # Sort
    if req.sort_col > 0 && req.sort_col <= length(p.data)
        col_data = p.data[req.sort_col]
        sort!(indices; by=i -> col_data[i], rev=(req.sort_dir == sort_desc))
    end

    # Paginate
    start = (req.page - 1) * req.page_size + 1
    stop = min(start + req.page_size - 1, total)
    page_indices = start <= total ? indices[start:stop] : Int[]

    # Build row-major result
    ncols = length(p.data)
    rows = [Any[p.data[ci][ri] for ci in 1:ncols] for ri in page_indices]

    PageResult(rows, total)
end
