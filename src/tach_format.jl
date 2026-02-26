# ═══════════════════════════════════════════════════════════════════════
# .tach binary format ── native recording format with Zstd compression
#
# Header (uncompressed, 9 bytes):
#   Magic:   "TACH" (4 bytes)
#   Version: UInt8 (1)
#   Width:   UInt16 (little-endian)
#   Height:  UInt16 (little-endian)
#
# Payload (Zstd compressed):
#   Frame count: UInt32
#   Per frame:
#     Timestamp:    Float64
#     Cells:        width*height packed cells (fixed count, no length prefix)
#     Pixel region count: UInt16
#     Per pixel region:
#       Row:    UInt16
#       Col:    UInt16
#       PxH:    UInt16 (pixel height)
#       PxW:    UInt16 (pixel width)
#       Pixels: PxH * PxW * 3 bytes (RGB)
#
# Packed Cell (5-11 bytes):
#   Char:  UInt32
#   Flags: UInt8
#     bits 0-1: fg color type (0=NoColor, 1=Color256, 2=ColorRGB)
#     bits 2-3: bg color type (0=NoColor, 1=Color256, 2=ColorRGB)
#     bit 4: bold
#     bit 5: dim
#     bit 6: italic
#     bit 7: underline
#   FG data: 0 bytes (NoColor) / 1 byte (Color256) / 3 bytes (ColorRGB)
#   BG data: 0 bytes (NoColor) / 1 byte (Color256) / 3 bytes (ColorRGB)
# ═══════════════════════════════════════════════════════════════════════

using CodecZstd

const TACH_MAGIC = UInt8['T', 'A', 'C', 'H']
const TACH_VERSION = 0x01

# ── Color type tags ───────────────────────────────────────────────────

_color_tag(::NoColor)  = 0x00
_color_tag(::Color256) = 0x01
_color_tag(::ColorRGB) = 0x02

# ── Pack / unpack helpers ─────────────────────────────────────────────

function _pack_color(io::IO, ::NoColor)
    nothing
end

function _pack_color(io::IO, c::Color256)
    write(io, c.code)
end

function _pack_color(io::IO, c::ColorRGB)
    write(io, c.r, c.g, c.b)
end

function _unpack_color(io::IO, tag::UInt8)
    if tag == 0x00
        NoColor()
    elseif tag == 0x01
        Color256(read(io, UInt8))
    else  # 0x02
        r = read(io, UInt8)
        g = read(io, UInt8)
        b = read(io, UInt8)
        ColorRGB(r, g, b)
    end
end

function _pack_cell(io::IO, cell::Cell)
    write(io, htol(UInt32(cell.char)))
    fg_tag = _color_tag(cell.style.fg)
    bg_tag = _color_tag(cell.style.bg)
    flags = fg_tag |
            (bg_tag << 2) |
            (UInt8(cell.style.bold)      << 4) |
            (UInt8(cell.style.dim)       << 5) |
            (UInt8(cell.style.italic)    << 6) |
            (UInt8(cell.style.underline) << 7)
    write(io, flags)
    _pack_color(io, cell.style.fg)
    _pack_color(io, cell.style.bg)
end

function _unpack_cell(io::IO)
    ch = Char(ltoh(read(io, UInt32)))
    flags = read(io, UInt8)
    fg_tag = flags & 0x03
    bg_tag = (flags >> 2) & 0x03
    bold      = (flags >> 4) & 0x01 != 0
    dim_flag  = (flags >> 5) & 0x01 != 0
    italic    = (flags >> 6) & 0x01 != 0
    underline = (flags >> 7) & 0x01 != 0
    fg = _unpack_color(io, fg_tag)
    bg = _unpack_color(io, bg_tag)
    Cell(ch, Style(fg, bg, bold, dim_flag, italic, underline, ""))
end

# ── Write .tach file ──────────────────────────────────────────────────

"""
    write_tach(filename, width, height, cell_snapshots, timestamps, pixel_snapshots)

Write a `.tach` recording file. The header is written uncompressed,
then all frame data is Zstd-compressed.
"""
function write_tach(filename::String, width::Int, height::Int,
                    cell_snapshots::Vector{Vector{Cell}},
                    timestamps::Vector{Float64},
                    pixel_snapshots::Vector{Vector{PixelSnapshot}})
    open(filename, "w") do f
        # Header (uncompressed, 9 bytes)
        write(f, TACH_MAGIC)
        write(f, TACH_VERSION)
        write(f, htol(UInt16(width)))
        write(f, htol(UInt16(height)))

        # Compressed payload
        zstream = ZstdCompressorStream(f)
        nframes = length(cell_snapshots)
        write(zstream, htol(UInt32(nframes)))

        ncells = width * height
        for i in 1:nframes
            # Timestamp
            write(zstream, htol(timestamps[i]))

            # Cells (fixed count = width * height)
            cells = cell_snapshots[i]
            for j in 1:ncells
                _pack_cell(zstream, j <= length(cells) ? cells[j] : Cell())
            end

            # Pixel regions
            sixels = i <= length(pixel_snapshots) ? pixel_snapshots[i] : PixelSnapshot[]
            write(zstream, htol(UInt16(length(sixels))))
            for (row, col, px) in sixels
                pxh, pxw = size(px)
                write(zstream, htol(UInt16(row)))
                write(zstream, htol(UInt16(col)))
                write(zstream, htol(UInt16(pxh)))
                write(zstream, htol(UInt16(pxw)))
                # Write RGB pixels row-major
                for r in 1:pxh, c in 1:pxw
                    color = px[r, c]
                    write(zstream, color.r, color.g, color.b)
                end
            end
        end
        close(zstream)
    end
    filename
end

# ── Load .tach file ───────────────────────────────────────────────────

"""
    load_tach(filename) → (width, height, cell_snapshots, timestamps, pixel_snapshots)

Load a `.tach` recording file. Returns the grid dimensions, cell snapshots,
timestamps, and pixel snapshot data — ready for any export function.
"""
function load_tach(filename::String)
    open(filename, "r") do f
        # Read and verify header
        magic = read(f, 4)
        magic == TACH_MAGIC || error("Not a .tach file (bad magic: $(String(magic)))")
        version = read(f, UInt8)
        version == TACH_VERSION || error("Unsupported .tach version: $version")
        width  = Int(ltoh(read(f, UInt16)))
        height = Int(ltoh(read(f, UInt16)))

        # Decompress payload
        zstream = ZstdDecompressorStream(f)
        nframes = Int(ltoh(read(zstream, UInt32)))

        ncells = width * height
        cell_snapshots  = Vector{Vector{Cell}}(undef, nframes)
        timestamps      = Vector{Float64}(undef, nframes)
        pixel_snapshots = Vector{Vector{PixelSnapshot}}(undef, nframes)

        for i in 1:nframes
            timestamps[i] = ltoh(read(zstream, Float64))

            cells = Vector{Cell}(undef, ncells)
            for j in 1:ncells
                cells[j] = _unpack_cell(zstream)
            end
            cell_snapshots[i] = cells

            nsixels = Int(ltoh(read(zstream, UInt16)))
            sixels = Vector{PixelSnapshot}(undef, nsixels)
            for s in 1:nsixels
                row = Int(ltoh(read(zstream, UInt16)))
                col = Int(ltoh(read(zstream, UInt16)))
                pxh = Int(ltoh(read(zstream, UInt16)))
                pxw = Int(ltoh(read(zstream, UInt16)))
                px = Matrix{ColorRGB}(undef, pxh, pxw)
                for r in 1:pxh, c in 1:pxw
                    pr = read(zstream, UInt8)
                    pg = read(zstream, UInt8)
                    pb = read(zstream, UInt8)
                    px[r, c] = ColorRGB(pr, pg, pb)
                end
                sixels[s] = (row, col, px)
            end
            pixel_snapshots[i] = sixels
        end
        close(zstream)

        (width, height, cell_snapshots, timestamps, pixel_snapshots)
    end
end
