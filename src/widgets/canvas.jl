# ═══════════════════════════════════════════════════════════════════════
# Canvas ── braille-dot drawing surface for inline charts
#
# Each terminal cell maps to a 2×4 dot grid (Unicode braille U+2800).
# Effective resolution: width*2 × height*4 dots.
# Lightweight alternative to PixelCanvas for simple line/scatter plots
# that need to live in the character buffer with ANSI styling.
# ═══════════════════════════════════════════════════════════════════════

# Braille dot positions (col, row) → bit index
# ⠁(0,0)=0  ⠈(1,0)=3
# ⠂(0,1)=1  ⠐(1,1)=4
# ⠄(0,2)=2  ⠠(1,2)=5
# ⡀(0,3)=6  ⢀(1,3)=7
const BRAILLE_OFFSET = 0x2800
const BRAILLE_MAP = (
    (0x01, 0x08),  # row 0: left=bit0, right=bit3
    (0x02, 0x10),  # row 1: left=bit1, right=bit4
    (0x04, 0x20),  # row 2: left=bit2, right=bit5
    (0x40, 0x80),  # row 3: left=bit6, right=bit7
)

mutable struct Canvas
    width::Int               # in terminal columns
    height::Int              # in terminal rows
    dots::Matrix{UInt8}      # width × height grid of braille bitmasks
    style::Style
end

function Canvas(width::Int, height::Int;
    style=tstyle(:primary),
)
    Canvas(width, height, zeros(UInt8, width, height), style)
end

# Dot-space coordinates → cell + sub-position
# dx: 0..width*2-1, dy: 0..height*4-1
function set_point!(c::Canvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1  # terminal column (1-based)
    cy = dy ÷ 4 + 1  # terminal row (1-based)
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2       # sub-x: 0=left, 1=right
    sy = dy % 4       # sub-y: 0-3
    c.dots[cx, cy] |= BRAILLE_MAP[sy + 1][sx + 1]
    nothing
end

function unset_point!(c::Canvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1
    cy = dy ÷ 4 + 1
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2
    sy = dy % 4
    c.dots[cx, cy] &= ~BRAILLE_MAP[sy + 1][sx + 1]
    nothing
end

function clear!(c::Canvas)
    fill!(c.dots, 0x00)
end

# Bresenham line drawing in dot-space
function line!(c::Canvas, x0::Int, y0::Int, x1::Int, y1::Int)
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

function rect!(c::Canvas, x0::Int, y0::Int, x1::Int, y1::Int)
    line!(c, x0, y0, x1, y0)  # top
    line!(c, x1, y0, x1, y1)  # right
    line!(c, x1, y1, x0, y1)  # bottom
    line!(c, x0, y1, x0, y0)  # left
    nothing
end

function circle!(c::Canvas, cx::Int, cy::Int, r::Int)
    r < 0 && return
    # Midpoint circle algorithm
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

function arc!(c::Canvas, cx::Int, cy::Int, r::Int,
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

function render(c::Canvas, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    for cy in 1:min(c.height, rect.height)
        for cx in 1:min(c.width, rect.width)
            bits = c.dots[cx, cy]
            bits == 0x00 && continue   # skip empty cells to preserve earlier series
            bx = rect.x + cx - 1
            by = rect.y + cy - 1
            ch = Char(BRAILLE_OFFSET + bits)
            set_char!(buf, bx, by, ch, c.style)
        end
    end
end
