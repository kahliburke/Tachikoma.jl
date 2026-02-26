# ═══════════════════════════════════════════════════════════════════════
# CastRecorder struct ── defined early so Terminal can reference it
# GraphicsRegion is also defined here (before terminal.jl) so
# CastRecorder can store raster snapshots.
# ═══════════════════════════════════════════════════════════════════════

@enum GraphicsFormat gfx_fmt_sixel gfx_fmt_kitty

struct GraphicsRegion
    row::Int
    col::Int
    width::Int
    height::Int
    data::Vector{UInt8}
    format::GraphicsFormat
end

# Convenience constructor (defaults to sixel format)
GraphicsRegion(row, col, width, height, data) =
    GraphicsRegion(row, col, width, height, data, gfx_fmt_sixel)

# Pixel snapshot for raster export: (row, col, pixel_matrix)
const PixelSnapshot = Tuple{Int, Int, Matrix{ColorRGB}}

mutable struct CastRecorder
    active::Bool
    timestamps::Vector{Float64}                      # wall-clock timestamp per frame
    cell_snapshots::Vector{Vector{Cell}}             # cell-level snapshots for export
    pixel_snapshots::Vector{Vector{PixelSnapshot}}   # pixel data per frame for raster export
    width::Int
    height::Int
    start_time::Float64
    filename::String                                 # output path (set on start)
    countdown::Float64                               # seconds remaining before capture begins (0 = capturing)
end

CastRecorder() = CastRecorder(false, Float64[], Vector{Cell}[], Vector{PixelSnapshot}[],
                               0, 0, 0.0, "", 0.0)
