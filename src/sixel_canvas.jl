# ═══════════════════════════════════════════════════════════════════════
# PixelCanvas ── high-resolution pixel canvas with raster rendering
#
# Same API as Canvas (set_point!, unset_point!, line!, clear!) but
# renders at ~16×32 pixels per terminal cell via sixel or Kitty
# graphics protocol. Falls back to braille sampling when rendered
# to a plain Buffer.
# ═══════════════════════════════════════════════════════════════════════

mutable struct PixelCanvas
    width::Int               # terminal columns
    height::Int              # terminal rows
    pixels::Matrix{ColorRGB} # pixel_h × pixel_w (row-major)
    pixel_w::Int             # total pixel width
    pixel_h::Int             # total pixel height
    dot_w::Int               # braille-compatible: width * 2
    dot_h::Int               # braille-compatible: height * 4
    style::Style
    color::ColorRGB
end


function PixelCanvas(width::Int, height::Int;
                     style::Style=tstyle(:primary))
    sap = SIXEL_AREA_PX[]
    tac = TEXT_AREA_CELLS[]
    if sap.w > 0 && tac.w > 0
        pw = round(Int, width * sap.w / tac.w)
        ph = round(Int, height * sap.h / tac.h)
    else
        tap = TEXT_AREA_PX[]
        if tap.w > 0 && tac.w > 0
            pw = round(Int, width * tap.w / tac.w)
            ph = round(Int, height * tap.h / tac.h)
        else
            cpx = CELL_PX[]
            pw = width * cpx.w
            ph = height * cpx.h
        end
        ss = SIXEL_SCALE[]
        pw = max(1, round(Int, pw * ss.w))
        ph = max(1, round(Int, ph * ss.h))
    end
    color = _style_to_rgb(style)
    PixelCanvas(width, height,
                fill(BLACK, ph, pw),
                pw, ph,
                width * 2, height * 4,
                style, color)
end

function Base.show(io::IO, c::PixelCanvas)
    print(io, "PixelCanvas($(c.width)×$(c.height) cells, $(c.pixel_w)×$(c.pixel_h) px)")
end

function Base.show(io::IO, ::MIME"text/plain", c::PixelCanvas)
    print(io, "PixelCanvas($(c.width)×$(c.height) cells, $(c.pixel_w)×$(c.pixel_h) px)")
end

function _style_to_rgb(s::Style)
    s.fg isa ColorRGB && return s.fg
    s.fg isa Color256 && return to_rgb(s.fg)
    ColorRGB(0xff, 0xff, 0xff)
end

# ── Pixel-level API (native resolution) ──────────────────────────────

"""
    set_pixel!(c::PixelCanvas, px::Int, py::Int)

Set a single pixel at native resolution. 1-based coordinates:
px ∈ [1, c.pixel_w], py ∈ [1, c.pixel_h].
Uses c.color for the pixel color.
"""
function set_pixel!(c::PixelCanvas, px::Int, py::Int)
    (px >= 1 && py >= 1 && px <= c.pixel_w && py <= c.pixel_h) || return
    c.pixels[py, px] = c.color
    nothing
end

"""
    set_pixel!(c::PixelCanvas, px::Int, py::Int, color::ColorRGB)

Set a single pixel with an explicit color.
"""
function set_pixel!(c::PixelCanvas, px::Int, py::Int, color::ColorRGB)
    (px >= 1 && py >= 1 && px <= c.pixel_w && py <= c.pixel_h) || return
    c.pixels[py, px] = color
    nothing
end

"""
    fill_pixel_rect!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int, color::ColorRGB)

Fill a rectangle of pixels with a single color. Coordinates are 1-based
and clamped to canvas bounds. Use this instead of looping `set_pixel!`
for block fills — avoids per-pixel bounds checking overhead.
"""
function fill_pixel_rect!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int, color::ColorRGB)
    px0 = max(1, x0)
    py0 = max(1, y0)
    px1 = min(c.pixel_w, x1)
    py1 = min(c.pixel_h, y1)
    px0 > px1 && return
    py0 > py1 && return
    pixels = c.pixels
    @inbounds for py in py0:py1
        for px in px0:px1
            pixels[py, px] = color
        end
    end
    nothing
end

"""
    pixel_line!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int)

Bresenham line drawing at native pixel resolution (1-based).
"""
function pixel_line!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx - dy
    while true
        set_pixel!(c, x0, y0)
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

# ── Drawing API (dot-space, same as Canvas) ──────────────────────────

"""
    set_point!(c::PixelCanvas, dx::Int, dy::Int)

Set a point in dot-space coordinates (same coord system as Canvas).
Each dot maps to a proportional slice of the pixel buffer, ensuring
full coverage with no gaps at the edges.
"""
function set_point!(c::PixelCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    (dx < c.dot_w && dy < c.dot_h) || return
    # Proportional mapping: dot dx covers pixels [dx*pw/dw+1, (dx+1)*pw/dw]
    # This distributes pixels evenly and covers the full buffer.
    pw, dw = c.pixel_w, c.dot_w
    ph, dh = c.pixel_h, c.dot_h
    px0 = (dx * pw) ÷ dw + 1
    px1 = ((dx + 1) * pw) ÷ dw
    py0 = (dy * ph) ÷ dh + 1
    py1 = ((dy + 1) * ph) ÷ dh
    for py in py0:py1
        for px in px0:px1
            c.pixels[py, px] = c.color
        end
    end
    nothing
end

"""
    unset_point!(c::PixelCanvas, dx::Int, dy::Int)

Clear a point in dot-space coordinates.
"""
function unset_point!(c::PixelCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    (dx < c.dot_w && dy < c.dot_h) || return
    pw, dw = c.pixel_w, c.dot_w
    ph, dh = c.pixel_h, c.dot_h
    px0 = (dx * pw) ÷ dw + 1
    px1 = ((dx + 1) * pw) ÷ dw
    py0 = (dy * ph) ÷ dh + 1
    py1 = ((dy + 1) * ph) ÷ dh
    for py in py0:py1
        for px in px0:px1
            c.pixels[py, px] = BLACK
        end
    end
    nothing
end

"""
    clear!(c::PixelCanvas)

Clear all pixels.
"""
function clear!(c::PixelCanvas)
    fill!(c.pixels, BLACK)
end

"""
    line!(c::PixelCanvas, x0, y0, x1, y1)

Bresenham line drawing in dot-space (same as Canvas).
"""
function line!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx - dy
    while true
        set_point!(c, x0, y0)
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

# ── Rendering ─────────────────────────────────────────────────────────

"""
    render(c::PixelCanvas, rect::Rect, f::Frame; tick::Int=0, decay::DecayParams=DecayParams())

Primary render path: encodes pixels via the detected graphics protocol
and places them into the frame's region list. Decay defaults to off
(clean rendering); pass `decay=decay_params()` for bit-rot effects.
"""
function render(c::PixelCanvas, rect::Rect, f::Frame;
                tick::Int=0, decay::DecayParams=DecayParams())
    (rect.width < 1 || rect.height < 1) && return
    gfx = GRAPHICS_PROTOCOL[]
    if gfx == gfx_kitty
        data = encode_kitty(c.pixels; decay=decay, tick=tick,
                            cols=rect.width, rows=rect.height)
        fmt = gfx_fmt_kitty
    else
        data = encode_sixel(c.pixels; decay=decay, tick=tick)
        fmt = gfx_fmt_sixel
    end
    isempty(data) || render_graphics!(f, data, rect; pixels=c.pixels, format=fmt)
    nothing
end

"""
    render(c::PixelCanvas, rect::Rect, buf::Buffer)

Fallback render path: samples pixel buffer to braille characters,
same visual as Canvas but at pixel resolution.
"""
function render(c::PixelCanvas, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    pw, dw = c.pixel_w, c.dot_w
    ph, dh = c.pixel_h, c.dot_h

    for cy in 1:min(c.height, rect.height)
        for cx in 1:min(c.width, rect.width)
            bits = UInt8(0)
            # Sample 2×4 dot grid using proportional pixel mapping
            for sy in 0:3
                for sx in 0:1
                    dx = (cx - 1) * 2 + sx
                    dy = (cy - 1) * 4 + sy
                    # Sample center of the proportional pixel range
                    px0 = (dx * pw) ÷ dw + 1
                    py0 = (dy * ph) ÷ dh + 1
                    (px0 <= pw && py0 <= ph) || continue
                    if c.pixels[py0, px0] != BLACK
                        bits |= BRAILLE_MAP[sy + 1][sx + 1]
                    end
                end
            end
            bx = rect.x + cx - 1
            by = rect.y + cy - 1
            ch = Char(BRAILLE_OFFSET + bits)
            set_char!(buf, bx, by, ch, c.style)
        end
    end
end

# ── Factory + helpers ─────────────────────────────────────────────────

"""
    create_canvas(width, height; style=tstyle(:primary))

Backend-agnostic canvas factory. Returns BlockCanvas or Canvas
depending on the active render backend preference.
"""
function create_canvas(width::Int, height::Int;
                       style::Style=tstyle(:primary))
    rb = RENDER_BACKEND[]
    if rb == block_backend
        BlockCanvas(width, height; style)
    else
        Canvas(width, height; style)
    end
end

"""
    canvas_dot_size(c) → (w, h)

Return the dot-space dimensions for a canvas (backend-agnostic).
"""
canvas_dot_size(c::Canvas) = (c.width * 2, c.height * 4)
canvas_dot_size(c::PixelCanvas) = (c.dot_w, c.dot_h)

"""
    render_canvas(c, rect, f::Frame; tick=0)

Backend-agnostic render helper. Dispatches to the correct render
method for Canvas, BlockCanvas, or PixelCanvas.
"""
render_canvas(c::Canvas, rect::Rect, f::Frame; tick::Int=0) =
    render(c, rect, f.buffer)
render_canvas(c::PixelCanvas, rect::Rect, f::Frame; tick::Int=0) =
    render(c, rect, f; tick=tick)

# ── Shape primitives (same API as Canvas) ──

function rect!(c::PixelCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
    line!(c, x0, y0, x1, y0)
    line!(c, x1, y0, x1, y1)
    line!(c, x1, y1, x0, y1)
    line!(c, x0, y1, x0, y0)
    nothing
end

function circle!(c::PixelCanvas, cx::Int, cy::Int, r::Int)
    r < 0 && return
    x = r; y = 0; err = 1 - r
    while x >= y
        set_point!(c, cx + x, cy + y); set_point!(c, cx - x, cy + y)
        set_point!(c, cx + x, cy - y); set_point!(c, cx - x, cy - y)
        set_point!(c, cx + y, cy + x); set_point!(c, cx - y, cy + x)
        set_point!(c, cx + y, cy - x); set_point!(c, cx - y, cy - x)
        y += 1
        if err < 0; err += 2y + 1
        else x -= 1; err += 2(y - x) + 1
        end
    end
    nothing
end

function arc!(c::PixelCanvas, cx::Int, cy::Int, r::Int,
              start_deg::Float64, end_deg::Float64; steps::Int=0)
    r < 0 && return
    if steps <= 0
        steps = max(8, round(Int, abs(end_deg - start_deg) / 360.0 * 2π * r))
    end
    steps = max(2, steps)
    for i in 0:steps
        θ = deg2rad(start_deg + (end_deg - start_deg) * i / steps)
        dx = round(Int, cx + r * cos(θ))
        dy = round(Int, cy + r * sin(θ))
        set_point!(c, dx, dy)
        if i > 0
            θ_prev = deg2rad(start_deg + (end_deg - start_deg) * (i - 1) / steps)
            px = round(Int, cx + r * cos(θ_prev))
            py = round(Int, cy + r * sin(θ_prev))
            line!(c, px, py, dx, dy)
        end
    end
    nothing
end
