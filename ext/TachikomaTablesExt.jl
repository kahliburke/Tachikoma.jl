module TachikomaTablesExt

using Tachikoma
using Tachikoma.Paged
using Tables

function _datatable_from_table(source; kwargs...)
    Tables.istable(source) || throw(ArgumentError("source is not a Tables.jl-compatible table"))
    cols = Tables.columns(source)
    names = Tables.columnnames(cols)
    datacols = Tachikoma.DataColumn[]
    for name in names
        col = Tables.getcolumn(cols, name)
        vals = collect(Any, col)
        et = eltype(col)
        al = et <: Number ? Tachikoma.col_right : Tachikoma.col_left
        push!(datacols, Tachikoma.DataColumn(string(name), vals; align=al))
    end
    Tachikoma.DataTable(datacols; kwargs...)
end

function _paged_provider_from_table(source)
    Tables.istable(source) || throw(ArgumentError("source is not a Tables.jl-compatible table"))
    tcols = Tables.columns(source)
    names = Tables.columnnames(tcols)
    paged_cols = PagedColumn[]
    data = Vector{Any}[]
    for name in names
        col = Tables.getcolumn(tcols, name)
        vals = collect(Any, col)
        et = eltype(col)
        push!(paged_cols, PagedColumn(string(name); col_type=et <: Number ? :numeric : :text))
        push!(data, vals)
    end
    InMemoryPagedProvider(paged_cols, data)
end

function Tachikoma.DataTable(source; kwargs...)
    _datatable_from_table(source; kwargs...)
end

function Tachikoma.Paged.PagedDataTable(source; kwargs...)
    provider = _paged_provider_from_table(source)
    PagedDataTable(provider; kwargs...)
end

function __init__()
    Tachikoma._datatable_from_table[] = _datatable_from_table
    Tachikoma._paged_provider_from_table[] = _paged_provider_from_table
    @info "Tachikoma: Tables.jl integration enabled"
end

end
