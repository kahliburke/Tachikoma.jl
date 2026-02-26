# ═══════════════════════════════════════════════════════════════════════
# BlockCanvas ── gap-free drawing surface using quadrant block characters
#
# Each terminal cell maps to a 2×2 dot grid using Unicode quadrant
# block characters (U+2596–U+259F plus half/full blocks).
# Effective resolution: width*2 × height*2 dots.
#
# Same API as Canvas (braille) but with solid fills and zero gaps
# between adjacent cells.  Uses universally-supported block elements
# from the U+2580 Unicode block.
# ═══════════════════════════════════════════════════════════════════════

# Quadrant bit layout per cell (2×2 grid):
#   bit 0 (1) = top-left       bit 1 (2) = top-right
#   bit 2 (4) = bottom-left    bit 3 (8) = bottom-right

# Lookup table: 4-bit value (0–15) → Char
const QUADRANT_LUT = (
    ' ',       # 0000 = empty
    '\u2598',  # 0001 = ▘ upper left
    '\u259d',  # 0010 = ▝ upper right
    '\u2580',  # 0011 = ▀ upper half
    '\u2596',  # 0100 = ▖ lower left
    '\u258c',  # 0101 = ▌ left half
    '\u259e',  # 0110 = ▞ upper right + lower left
    '\u259b',  # 0111 = ▛ upper left + upper right + lower left
    '\u2597',  # 1000 = ▗ lower right
    '\u259a',  # 1001 = ▚ upper left + lower right
    '\u2590',  # 1010 = ▐ right half
    '\u259c',  # 1011 = ▜ upper left + upper right + lower right
    '\u2584',  # 1100 = ▄ lower half
    '\u2599',  # 1101 = ▙ upper left + lower left + lower right
    '\u259f',  # 1110 = ▟ upper right + lower left + lower right
    '\u2588',  # 1111 = █ full block
)

mutable struct BlockCanvas
    width::Int               # in terminal columns
    height::Int              # in terminal rows
    dots::Matrix{UInt8}      # width × height grid of 4-bit quadrant masks
    style::Style
end

function BlockCanvas(width::Int, height::Int;
    style=tstyle(:primary),
)
    BlockCanvas(width, height, zeros(UInt8, width, height), style)
end

# Dot-space coordinates → cell + sub-position
# dx: 0..width*2-1,  dy: 0..height*2-1
function set_point!(c::BlockCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1  # terminal column (1-based)
    cy = dy ÷ 2 + 1  # terminal row (1-based)
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2       # sub-x: 0=left, 1=right
    sy = dy % 2       # sub-y: 0=top, 1=bottom
    bit = UInt8(1) << (sy * 2 + sx)
    c.dots[cx, cy] |= bit
    nothing
end

function unset_point!(c::BlockCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1
    cy = dy ÷ 2 + 1
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2
    sy = dy % 2
    bit = UInt8(1) << (sy * 2 + sx)
    c.dots[cx, cy] &= ~bit
    nothing
end

function clear!(c::BlockCanvas)
    fill!(c.dots, 0x00)
end

# Bresenham line drawing in dot-space
function line!(c::BlockCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
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

# ── Shape primitives ──

function rect!(c::BlockCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
    line!(c, x0, y0, x1, y0)
    line!(c, x1, y0, x1, y1)
    line!(c, x1, y1, x0, y1)
    line!(c, x0, y1, x0, y0)
    nothing
end

function circle!(c::BlockCanvas, cx::Int, cy::Int, r::Int)
    r < 0 && return
    x = r
    y = 0
    err = 1 - r
    while x >= y
        set_point!(c, cx + x, cy + y)
        set_point!(c, cx - x, cy + y)
        set_point!(c, cx + x, cy - y)
        set_point!(c, cx - x, cy - y)
        set_point!(c, cx + y, cy + x)
        set_point!(c, cx - y, cy + x)
        set_point!(c, cx + y, cy - x)
        set_point!(c, cx - y, cy - x)
        y += 1
        if err < 0
            err += 2y + 1
        else
            x -= 1
            err += 2(y - x) + 1
        end
    end
    nothing
end

function arc!(c::BlockCanvas, cx::Int, cy::Int, r::Int,
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

function render(c::BlockCanvas, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    for cy in 1:min(c.height, rect.height)
        for cx in 1:min(c.width, rect.width)
            bits = c.dots[cx, cy]
            bits == 0x00 && continue
            bx = rect.x + cx - 1
            by = rect.y + cy - 1
            ch = QUADRANT_LUT[bits + 1]
            set_char!(buf, bx, by, ch, c.style)
        end
    end
end

# Backend-agnostic dispatches (BlockCanvas is defined after sixel_canvas.jl)
canvas_dot_size(c::BlockCanvas) = (c.width * 2, c.height * 2)
render_canvas(c::BlockCanvas, rect::Rect, f::Frame; tick::Int=0) =
    render(c, rect, f.buffer)
