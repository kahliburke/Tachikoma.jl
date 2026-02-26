module TachikomaTablesExt

using Tachikoma
using Tables

function Tachikoma.DataTable(source; kwargs...)
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

end
