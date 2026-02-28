# ═══════════════════════════════════════════════════════════════════════
# PixelImage ── dedicated widget for high-resolution pixel data
#
# Owns a pixel buffer, renders via sixel or Kitty graphics on capable
# terminals, falls back to braille sampling on plain terminals.
# Guarantees no overflow: pixel dimensions are computed from cell
# metrics and resize on layout changes.
# ═══════════════════════════════════════════════════════════════════════

mutable struct PixelImage
    pixels::Matrix{ColorRGB}        # pixel_h × pixel_w (row-major)
    pixel_w::Int
    pixel_h::Int
    cells_w::Int                    # cell dims this buffer was sized for
    cells_h::Int
    block::Union{Block, Nothing}
    style::Style                    # braille fallback style
    color::ColorRGB                 # current drawing color
    decay::DecayParams              # per-widget decay (default: off)
end


"""
    _pixelimage_pixel_dims(cells_w, cells_h)

Compute pixel dimensions that exactly tile with cell boundaries.

Prefers SIXEL_AREA_PX (from XTSMGRAPHICS query) which gives the actual
sixel rendering pixel dimensions. Falls back to TEXT_AREA_PX with
SIXEL_SCALE multiplier, then CELL_PX.
"""
function _pixelimage_pixel_dims(cells_w::Int, cells_h::Int)
    sap = SIXEL_AREA_PX[]
    tac = TEXT_AREA_CELLS[]
    if sap.w > 0 && tac.w > 0
        # Best path: use actual sixel pixel geometry from XTSMGRAPHICS.
        # On retina displays this reports physical pixels, which is correct
        # because sixel rendering maps 1 sixel pixel = 1 device pixel.
        pw = round(Int, cells_w * sap.w / tac.w)
        ph = round(Int, cells_h * sap.h / tac.h)
    else
        # Fallback: use text area pixels (may be in different coordinate
        # space than sixel), with SIXEL_SCALE as manual correction.
        tap = TEXT_AREA_PX[]
        if tap.w > 0 && tac.w > 0
            pw = round(Int, cells_w * tap.w / tac.w)
            ph = round(Int, cells_h * tap.h / tac.h)
        else
            cpx = CELL_PX[]
            pw = cells_w * cpx.w
            ph = cells_h * cpx.h
        end
        ss = SIXEL_SCALE[]
        pw = max(1, round(Int, pw * ss.w))
        ph = max(1, round(Int, ph * ss.h))
    end
    (pw, ph)
end

"""
    PixelImage(cells_w, cells_h; block=nothing, style=tstyle(:primary),
               decay=DecayParams())

Create a PixelImage widget sized for `cells_w × cells_h` terminal cells.
Pixel dimensions are computed from terminal cell metrics.
"""
function PixelImage(cells_w::Int, cells_h::Int;
                    block::Union{Block, Nothing}=nothing,
                    style::Style=tstyle(:primary),
                    decay::DecayParams=DecayParams())
    pw, ph = _pixelimage_pixel_dims(cells_w, cells_h)
    color = _style_to_rgb(style)
    PixelImage(fill(BLACK, ph, pw), pw, ph, cells_w, cells_h,
               block, style, color, decay)
end

# ── Drawing API (pixel-native, 1-based coordinates) ──────────────────

"""
    set_pixel!(img::PixelImage, x, y, color)

Set a single pixel at 1-based coordinates. Bounds-checked.
"""
function set_pixel!(img::PixelImage, px::Int, py::Int, color::ColorRGB)
    (px >= 1 && py >= 1 && px <= img.pixel_w && py <= img.pixel_h) || return
    img.pixels[py, px] = color
    nothing
end

"""
    set_pixel!(img::PixelImage, x, y)

Set a single pixel using `img.color`.
"""
function set_pixel!(img::PixelImage, px::Int, py::Int)
    (px >= 1 && py >= 1 && px <= img.pixel_w && py <= img.pixel_h) || return
    img.pixels[py, px] = img.color
    nothing
end

"""
    fill_rect!(img::PixelImage, x0, y0, x1, y1, color)

Fill a rectangle of pixels. Coordinates are 1-based and clamped.
"""
function fill_rect!(img::PixelImage, x0::Int, y0::Int, x1::Int, y1::Int, color::ColorRGB)
    px0 = max(1, x0)
    py0 = max(1, y0)
    px1 = min(img.pixel_w, x1)
    py1 = min(img.pixel_h, y1)
    px0 > px1 && return
    py0 > py1 && return
    pixels = img.pixels
    @inbounds for py in py0:py1
        for px in px0:px1
            pixels[py, px] = color
        end
    end
    nothing
end

"""
    pixel_line!(img::PixelImage, x0, y0, x1, y1, color)

Bresenham line drawing at pixel resolution (1-based).
"""
function pixel_line!(img::PixelImage, x0::Int, y0::Int, x1::Int, y1::Int, color::ColorRGB)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx - dy
    while true
        set_pixel!(img, x0, y0, color)
        (x0 == x1 && y0 == y1) && break
        e2 = 2 * err
        if e2 > -dy
            err -= dy
            x0 += sx
        end
        if e2 < dx
            err += dx
            y0 += sy
        end
    end
end

"""
    pixel_line!(img::PixelImage, x0, y0, x1, y1)

Bresenham line using `img.color`.
"""
function pixel_line!(img::PixelImage, x0::Int, y0::Int, x1::Int, y1::Int)
    pixel_line!(img, x0, y0, x1, y1, img.color)
end

"""
    clear!(img::PixelImage)

Clear all pixels to black.
"""
function clear!(img::PixelImage)
    fill!(img.pixels, BLACK)
end

"""
    load_pixels!(img::PixelImage, src::Matrix{ColorRGB})

Nearest-neighbor scale source matrix to fill widget pixel buffer.
Source is indexed [row, col].
"""
function load_pixels!(img::PixelImage, src::Matrix{ColorRGB})
    sh, sw = size(src)
    (sh == 0 || sw == 0) && return
    ph, pw = img.pixel_h, img.pixel_w
    pixels = img.pixels
    @inbounds for py in 1:ph
        sy = clamp(round(Int, (py - 0.5) / ph * sh + 0.5), 1, sh)
        for px in 1:pw
            sx = clamp(round(Int, (px - 0.5) / pw * sw + 0.5), 1, sw)
            pixels[py, px] = src[sy, sx]
        end
    end
    nothing
end

# ── Internal: resize pixel buffer if cell dims changed ───────────────

function _pixelimage_resize!(si::PixelImage, cells_w::Int, cells_h::Int)
    (cells_w == si.cells_w && cells_h == si.cells_h) && return
    pw, ph = _pixelimage_pixel_dims(cells_w, cells_h)
    si.pixels = fill(BLACK, ph, pw)
    si.pixel_w = pw
    si.pixel_h = ph
    si.cells_w = cells_w
    si.cells_h = cells_h
    nothing
end

# ── Render: Frame path (raster output) ────────────────────────────────

"""
    render(si::PixelImage, rect::Rect, f::Frame; tick::Int=0)

Render PixelImage to a Frame via the detected graphics protocol.
"""
function render(si::PixelImage, rect::Rect, f::Frame; tick::Int=0)
    buf = f.buffer
    content = if si.block !== nothing
        render(si.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    _pixelimage_resize!(si, content.width, content.height)
    gfx = GRAPHICS_PROTOCOL[]
    if gfx == gfx_none
        render(si, content, buf)
        return
    end
    if gfx == gfx_kitty
        data = encode_kitty(si.pixels; decay=si.decay, tick=tick,
                            cols=content.width, rows=content.height)
        fmt = gfx_fmt_kitty
    else
        data = encode_sixel(si.pixels; decay=si.decay, tick=tick)
        fmt = gfx_fmt_sixel
    end
    isempty(data) || render_graphics!(f, data, content; pixels=si.pixels, format=fmt)
    nothing
end

# ── Render: Buffer path (braille fallback) ───────────────────────────

"""
    render(si::PixelImage, rect::Rect, buf::Buffer)

Render PixelImage to a Buffer by sampling pixels to braille characters.
"""
function render(si::PixelImage, rect::Rect, buf::Buffer)
    content = if si.block !== nothing
        render(si.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    _pixelimage_resize!(si, content.width, content.height)

    pw = si.pixel_w
    ph = si.pixel_h
    cw = content.width
    ch = content.height

    for cy in 1:ch
        for cx in 1:cw
            bits = UInt8(0)
            # Sample 2×4 braille grid from pixel buffer
            for sy in 0:3
                for sx in 0:1
                    # Map cell sub-position to pixel coordinate
                    dx = (cx - 1) * 2 + sx
                    dy = (cy - 1) * 4 + sy
                    dot_w = cw * 2
                    dot_h = ch * 4
                    px0 = (dx * pw) ÷ dot_w + 1
                    py0 = (dy * ph) ÷ dot_h + 1
                    (px0 <= pw && py0 <= ph) || continue
                    if si.pixels[py0, px0] != BLACK
                        bits |= BRAILLE_MAP[sy + 1][sx + 1]
                    end
                end
            end
            bits == 0x00 && continue
            bx = content.x + cx - 1
            by = content.y + cy - 1
            ch_char = Char(BRAILLE_OFFSET + bits)
            set_char!(buf, bx, by, ch_char, si.style)
        end
    end
end
