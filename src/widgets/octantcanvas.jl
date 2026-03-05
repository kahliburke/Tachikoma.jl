# ═══════════════════════════════════════════════════════════════════════
# OctantCanvas ── gap-free drawing surface using octant block characters
#
# Each terminal cell maps to a 4×2 dot grid using Unicode 16 octant
# block characters.
# Effective resolution: width*2 × height*4 dots.
#
# Same API as Canvas (braille) but with solid fills and zero gaps
# between adjacent cells.
# ═══════════════════════════════════════════════════════════════════════

# Octant bit layout per cell (4×2 grid):
#
#     ╭───┬───╮
#     │ 0 │ 1 │
#     ├───┼───┤
#     │ 2 │ 3 │
#     ├───┼───┤
#     │ 4 │ 5 │
#     ├───┼───┤
#     │ 6 │ 7 │
#     ╰───┴───╯
#
#   bit 0 (1)  = top-left      bit 1 (2)   = top-right
#   bit 2 (4)  =               bit 3 (8)
#   bit 4 (16) =               bit 5 (32)
#   bit 6 (64) = bottom-left   bit 7 (128) = bottom-right

# Lookup table: 8-bit value (0–255) → Char
const OCTANT_LUT = Char[
    '\U000000A0',  # NO-BREAK SPACE
    '\U0001CEA8',  # LEFT HALF UPPER ONE QUARTER BLOCK
    '\U0001CEAB',  # RIGHT HALF UPPER ONE QUARTER BLOCK
    '\U0001FB82',  # UPPER ONE QUARTER BLOCK
    '\U0001CD00',  # BLOCK OCTANT-3
    '\U00002598',  # QUADRANT UPPER LEFT
    '\U0001CD01',  # BLOCK OCTANT-23
    '\U0001CD02',  # BLOCK OCTANT-123
    '\U0001CD03',  # BLOCK OCTANT-4
    '\U0001CD04',  # BLOCK OCTANT-14
    '\U0000259D',  # QUADRANT UPPER RIGHT
    '\U0001CD05',  # BLOCK OCTANT-124
    '\U0001CD06',  # BLOCK OCTANT-34
    '\U0001CD07',  # BLOCK OCTANT-134
    '\U0001CD08',  # BLOCK OCTANT-234
    '\U00002580',  # UPPER HALF BLOCK
    '\U0001CD09',  # BLOCK OCTANT-5
    '\U0001CD0A',  # BLOCK OCTANT-15
    '\U0001CD0B',  # BLOCK OCTANT-25
    '\U0001CD0C',  # BLOCK OCTANT-125
    '\U0001FBE6',  # MIDDLE LEFT ONE QUARTER BLOCK
    '\U0001CD0D',  # BLOCK OCTANT-135
    '\U0001CD0E',  # BLOCK OCTANT-235
    '\U0001CD0F',  # BLOCK OCTANT-1235
    '\U0001CD10',  # BLOCK OCTANT-45
    '\U0001CD11',  # BLOCK OCTANT-145
    '\U0001CD12',  # BLOCK OCTANT-245
    '\U0001CD13',  # BLOCK OCTANT-1245
    '\U0001CD14',  # BLOCK OCTANT-345
    '\U0001CD15',  # BLOCK OCTANT-1345
    '\U0001CD16',  # BLOCK OCTANT-2345
    '\U0001CD17',  # BLOCK OCTANT-12345
    '\U0001CD18',  # BLOCK OCTANT-6
    '\U0001CD19',  # BLOCK OCTANT-16
    '\U0001CD1A',  # BLOCK OCTANT-26
    '\U0001CD1B',  # BLOCK OCTANT-126
    '\U0001CD1C',  # BLOCK OCTANT-36
    '\U0001CD1D',  # BLOCK OCTANT-136
    '\U0001CD1E',  # BLOCK OCTANT-236
    '\U0001CD1F',  # BLOCK OCTANT-1236
    '\U0001FBE7',  # MIDDLE RIGHT ONE QUARTER BLOCK
    '\U0001CD20',  # BLOCK OCTANT-146
    '\U0001CD21',  # BLOCK OCTANT-246
    '\U0001CD22',  # BLOCK OCTANT-1246
    '\U0001CD23',  # BLOCK OCTANT-346
    '\U0001CD24',  # BLOCK OCTANT-1346
    '\U0001CD25',  # BLOCK OCTANT-2346
    '\U0001CD26',  # BLOCK OCTANT-12346
    '\U0001CD27',  # BLOCK OCTANT-56
    '\U0001CD28',  # BLOCK OCTANT-156
    '\U0001CD29',  # BLOCK OCTANT-256
    '\U0001CD2A',  # BLOCK OCTANT-1256
    '\U0001CD2B',  # BLOCK OCTANT-356
    '\U0001CD2C',  # BLOCK OCTANT-1356
    '\U0001CD2D',  # BLOCK OCTANT-2356
    '\U0001CD2E',  # BLOCK OCTANT-12356
    '\U0001CD2F',  # BLOCK OCTANT-456
    '\U0001CD30',  # BLOCK OCTANT-1456
    '\U0001CD31',  # BLOCK OCTANT-2456
    '\U0001CD32',  # BLOCK OCTANT-12456
    '\U0001CD33',  # BLOCK OCTANT-3456
    '\U0001CD34',  # BLOCK OCTANT-13456
    '\U0001CD35',  # BLOCK OCTANT-23456
    '\U0001FB85',  # UPPER THREE QUARTERS BLOCK
    '\U0001CEA3',  # LEFT HALF LOWER ONE QUARTER BLOCK
    '\U0001CD36',  # BLOCK OCTANT-17
    '\U0001CD37',  # BLOCK OCTANT-27
    '\U0001CD38',  # BLOCK OCTANT-127
    '\U0001CD39',  # BLOCK OCTANT-37
    '\U0001CD3A',  # BLOCK OCTANT-137
    '\U0001CD3B',  # BLOCK OCTANT-237
    '\U0001CD3C',  # BLOCK OCTANT-1237
    '\U0001CD3D',  # BLOCK OCTANT-47
    '\U0001CD3E',  # BLOCK OCTANT-147
    '\U0001CD3F',  # BLOCK OCTANT-247
    '\U0001CD40',  # BLOCK OCTANT-1247
    '\U0001CD41',  # BLOCK OCTANT-347
    '\U0001CD42',  # BLOCK OCTANT-1347
    '\U0001CD43',  # BLOCK OCTANT-2347
    '\U0001CD44',  # BLOCK OCTANT-12347
    '\U00002596',  # QUADRANT LOWER LEFT
    '\U0001CD45',  # BLOCK OCTANT-157
    '\U0001CD46',  # BLOCK OCTANT-257
    '\U0001CD47',  # BLOCK OCTANT-1257
    '\U0001CD48',  # BLOCK OCTANT-357
    '\U0000258C',  # LEFT HALF BLOCK
    '\U0001CD49',  # BLOCK OCTANT-2357
    '\U0001CD4A',  # BLOCK OCTANT-12357
    '\U0001CD4B',  # BLOCK OCTANT-457
    '\U0001CD4C',  # BLOCK OCTANT-1457
    '\U0000259E',  # QUADRANT UPPER RIGHT AND LOWER LEFT
    '\U0001CD4D',  # BLOCK OCTANT-12457
    '\U0001CD4E',  # BLOCK OCTANT-3457
    '\U0001CD4F',  # BLOCK OCTANT-13457
    '\U0001CD50',  # BLOCK OCTANT-23457
    '\U0000259B',  # QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER LEFT
    '\U0001CD51',  # BLOCK OCTANT-67
    '\U0001CD52',  # BLOCK OCTANT-167
    '\U0001CD53',  # BLOCK OCTANT-267
    '\U0001CD54',  # BLOCK OCTANT-1267
    '\U0001CD55',  # BLOCK OCTANT-367
    '\U0001CD56',  # BLOCK OCTANT-1367
    '\U0001CD57',  # BLOCK OCTANT-2367
    '\U0001CD58',  # BLOCK OCTANT-12367
    '\U0001CD59',  # BLOCK OCTANT-467
    '\U0001CD5A',  # BLOCK OCTANT-1467
    '\U0001CD5B',  # BLOCK OCTANT-2467
    '\U0001CD5C',  # BLOCK OCTANT-12467
    '\U0001CD5D',  # BLOCK OCTANT-3467
    '\U0001CD5E',  # BLOCK OCTANT-13467
    '\U0001CD5F',  # BLOCK OCTANT-23467
    '\U0001CD60',  # BLOCK OCTANT-123467
    '\U0001CD61',  # BLOCK OCTANT-567
    '\U0001CD62',  # BLOCK OCTANT-1567
    '\U0001CD63',  # BLOCK OCTANT-2567
    '\U0001CD64',  # BLOCK OCTANT-12567
    '\U0001CD65',  # BLOCK OCTANT-3567
    '\U0001CD66',  # BLOCK OCTANT-13567
    '\U0001CD67',  # BLOCK OCTANT-23567
    '\U0001CD68',  # BLOCK OCTANT-123567
    '\U0001CD69',  # BLOCK OCTANT-4567
    '\U0001CD6A',  # BLOCK OCTANT-14567
    '\U0001CD6B',  # BLOCK OCTANT-24567
    '\U0001CD6C',  # BLOCK OCTANT-124567
    '\U0001CD6D',  # BLOCK OCTANT-34567
    '\U0001CD6E',  # BLOCK OCTANT-134567
    '\U0001CD6F',  # BLOCK OCTANT-234567
    '\U0001CD70',  # BLOCK OCTANT-1234567
    '\U0001CEA0',  # RIGHT HALF LOWER ONE QUARTER BLOCK
    '\U0001CD71',  # BLOCK OCTANT-18
    '\U0001CD72',  # BLOCK OCTANT-28
    '\U0001CD73',  # BLOCK OCTANT-128
    '\U0001CD74',  # BLOCK OCTANT-38
    '\U0001CD75',  # BLOCK OCTANT-138
    '\U0001CD76',  # BLOCK OCTANT-238
    '\U0001CD77',  # BLOCK OCTANT-1238
    '\U0001CD78',  # BLOCK OCTANT-48
    '\U0001CD79',  # BLOCK OCTANT-148
    '\U0001CD7A',  # BLOCK OCTANT-248
    '\U0001CD7B',  # BLOCK OCTANT-1248
    '\U0001CD7C',  # BLOCK OCTANT-348
    '\U0001CD7D',  # BLOCK OCTANT-1348
    '\U0001CD7E',  # BLOCK OCTANT-2348
    '\U0001CD7F',  # BLOCK OCTANT-12348
    '\U0001CD80',  # BLOCK OCTANT-58
    '\U0001CD81',  # BLOCK OCTANT-158
    '\U0001CD82',  # BLOCK OCTANT-258
    '\U0001CD83',  # BLOCK OCTANT-1258
    '\U0001CD84',  # BLOCK OCTANT-358
    '\U0001CD85',  # BLOCK OCTANT-1358
    '\U0001CD86',  # BLOCK OCTANT-2358
    '\U0001CD87',  # BLOCK OCTANT-12358
    '\U0001CD88',  # BLOCK OCTANT-458
    '\U0001CD89',  # BLOCK OCTANT-1458
    '\U0001CD8A',  # BLOCK OCTANT-2458
    '\U0001CD8B',  # BLOCK OCTANT-12458
    '\U0001CD8C',  # BLOCK OCTANT-3458
    '\U0001CD8D',  # BLOCK OCTANT-13458
    '\U0001CD8E',  # BLOCK OCTANT-23458
    '\U0001CD8F',  # BLOCK OCTANT-123458
    '\U00002597',  # QUADRANT LOWER RIGHT
    '\U0001CD90',  # BLOCK OCTANT-168
    '\U0001CD91',  # BLOCK OCTANT-268
    '\U0001CD92',  # BLOCK OCTANT-1268
    '\U0001CD93',  # BLOCK OCTANT-368
    '\U0000259A',  # QUADRANT UPPER LEFT AND LOWER RIGHT
    '\U0001CD94',  # BLOCK OCTANT-2368
    '\U0001CD95',  # BLOCK OCTANT-12368
    '\U0001CD96',  # BLOCK OCTANT-468
    '\U0001CD97',  # BLOCK OCTANT-1468
    '\U00002590',  # RIGHT HALF BLOCK
    '\U0001CD98',  # BLOCK OCTANT-12468
    '\U0001CD99',  # BLOCK OCTANT-3468
    '\U0001CD9A',  # BLOCK OCTANT-13468
    '\U0001CD9B',  # BLOCK OCTANT-23468
    '\U0000259C',  # QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER RIGHT
    '\U0001CD9C',  # BLOCK OCTANT-568
    '\U0001CD9D',  # BLOCK OCTANT-1568
    '\U0001CD9E',  # BLOCK OCTANT-2568
    '\U0001CD9F',  # BLOCK OCTANT-12568
    '\U0001CDA0',  # BLOCK OCTANT-3568
    '\U0001CDA1',  # BLOCK OCTANT-13568
    '\U0001CDA2',  # BLOCK OCTANT-23568
    '\U0001CDA3',  # BLOCK OCTANT-123568
    '\U0001CDA4',  # BLOCK OCTANT-4568
    '\U0001CDA5',  # BLOCK OCTANT-14568
    '\U0001CDA6',  # BLOCK OCTANT-24568
    '\U0001CDA7',  # BLOCK OCTANT-124568
    '\U0001CDA8',  # BLOCK OCTANT-34568
    '\U0001CDA9',  # BLOCK OCTANT-134568
    '\U0001CDAA',  # BLOCK OCTANT-234568
    '\U0001CDAB',  # BLOCK OCTANT-1234568
    '\U00002582',  # LOWER ONE QUARTER BLOCK
    '\U0001CDAC',  # BLOCK OCTANT-178
    '\U0001CDAD',  # BLOCK OCTANT-278
    '\U0001CDAE',  # BLOCK OCTANT-1278
    '\U0001CDAF',  # BLOCK OCTANT-378
    '\U0001CDB0',  # BLOCK OCTANT-1378
    '\U0001CDB1',  # BLOCK OCTANT-2378
    '\U0001CDB2',  # BLOCK OCTANT-12378
    '\U0001CDB3',  # BLOCK OCTANT-478
    '\U0001CDB4',  # BLOCK OCTANT-1478
    '\U0001CDB5',  # BLOCK OCTANT-2478
    '\U0001CDB6',  # BLOCK OCTANT-12478
    '\U0001CDB7',  # BLOCK OCTANT-3478
    '\U0001CDB8',  # BLOCK OCTANT-13478
    '\U0001CDB9',  # BLOCK OCTANT-23478
    '\U0001CDBA',  # BLOCK OCTANT-123478
    '\U0001CDBB',  # BLOCK OCTANT-578
    '\U0001CDBC',  # BLOCK OCTANT-1578
    '\U0001CDBD',  # BLOCK OCTANT-2578
    '\U0001CDBE',  # BLOCK OCTANT-12578
    '\U0001CDBF',  # BLOCK OCTANT-3578
    '\U0001CDC0',  # BLOCK OCTANT-13578
    '\U0001CDC1',  # BLOCK OCTANT-23578
    '\U0001CDC2',  # BLOCK OCTANT-123578
    '\U0001CDC3',  # BLOCK OCTANT-4578
    '\U0001CDC4',  # BLOCK OCTANT-14578
    '\U0001CDC5',  # BLOCK OCTANT-24578
    '\U0001CDC6',  # BLOCK OCTANT-124578
    '\U0001CDC7',  # BLOCK OCTANT-34578
    '\U0001CDC8',  # BLOCK OCTANT-134578
    '\U0001CDC9',  # BLOCK OCTANT-234578
    '\U0001CDCA',  # BLOCK OCTANT-1234578
    '\U0001CDCB',  # BLOCK OCTANT-678
    '\U0001CDCC',  # BLOCK OCTANT-1678
    '\U0001CDCD',  # BLOCK OCTANT-2678
    '\U0001CDCE',  # BLOCK OCTANT-12678
    '\U0001CDCF',  # BLOCK OCTANT-3678
    '\U0001CDD0',  # BLOCK OCTANT-13678
    '\U0001CDD1',  # BLOCK OCTANT-23678
    '\U0001CDD2',  # BLOCK OCTANT-123678
    '\U0001CDD3',  # BLOCK OCTANT-4678
    '\U0001CDD4',  # BLOCK OCTANT-14678
    '\U0001CDD5',  # BLOCK OCTANT-24678
    '\U0001CDD6',  # BLOCK OCTANT-124678
    '\U0001CDD7',  # BLOCK OCTANT-34678
    '\U0001CDD8',  # BLOCK OCTANT-134678
    '\U0001CDD9',  # BLOCK OCTANT-234678
    '\U0001CDDA',  # BLOCK OCTANT-1234678
    '\U00002584',  # LOWER HALF BLOCK
    '\U0001CDDB',  # BLOCK OCTANT-15678
    '\U0001CDDC',  # BLOCK OCTANT-25678
    '\U0001CDDD',  # BLOCK OCTANT-125678
    '\U0001CDDE',  # BLOCK OCTANT-35678
    '\U00002599',  # QUADRANT UPPER LEFT AND LOWER LEFT AND LOWER RIGHT
    '\U0001CDDF',  # BLOCK OCTANT-235678
    '\U0001CDE0',  # BLOCK OCTANT-1235678
    '\U0001CDE1',  # BLOCK OCTANT-45678
    '\U0001CDE2',  # BLOCK OCTANT-145678
    '\U0000259F',  # QUADRANT UPPER RIGHT AND LOWER LEFT AND LOWER RIGHT
    '\U0001CDE3',  # BLOCK OCTANT-1245678
    '\U00002586',  # LOWER THREE QUARTERS BLOCK
    '\U0001CDE4',  # BLOCK OCTANT-1345678
    '\U0001CDE5',  # BLOCK OCTANT-2345678
    '\U00002588',  # FULL BLOCK
]
@assert length(OCTANT_LUT) == 256

mutable struct OctantCanvas
    width::Int               # in terminal columns
    height::Int              # in terminal rows
    dots::Matrix{UInt8}      # width × height grid of 8-bit octant masks
    style::Style
end

function OctantCanvas(width::Int, height::Int;
    style=tstyle(:primary),
)
    OctantCanvas(width, height, zeros(UInt8, width, height), style)
end

# Dot-space coordinates → cell + sub-position
# dx: 0..width*2-1,  dy: 0..height*4-1
function set_point!(c::OctantCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1  # terminal column (1-based)
    cy = dy ÷ 4 + 1  # terminal row (1-based)
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2       # sub-x: 0=left, 1=right
    sy = dy % 4       # sub-y: 0=top, 3=bottom
    bit = UInt8(1) << (sy * 2 + sx)
    c.dots[cx, cy] |= bit
    nothing
end

function unset_point!(c::OctantCanvas, dx::Int, dy::Int)
    (dx >= 0 && dy >= 0) || return
    cx = dx ÷ 2 + 1
    cy = dy ÷ 4 + 1
    (cx <= c.width && cy <= c.height) || return
    sx = dx % 2
    sy = dy % 4
    bit = UInt8(1) << (sy * 2 + sx)
    c.dots[cx, cy] &= ~bit
    nothing
end

function clear!(c::OctantCanvas)
    fill!(c.dots, 0x00)
end

# Bresenham line drawing in dot-space
function line!(c::OctantCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
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

function rect!(c::OctantCanvas, x0::Int, y0::Int, x1::Int, y1::Int)
    line!(c, x0, y0, x1, y0)
    line!(c, x1, y0, x1, y1)
    line!(c, x1, y1, x0, y1)
    line!(c, x0, y1, x0, y0)
    nothing
end

function circle!(c::OctantCanvas, cx::Int, cy::Int, r::Int)
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

function arc!(c::OctantCanvas, cx::Int, cy::Int, r::Int,
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

function render(c::OctantCanvas, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    for cy in 1:min(c.height, rect.height)
        for cx in 1:min(c.width, rect.width)
            bits = c.dots[cx, cy]
            bits == 0x00 && continue
            bx = rect.x + cx - 1
            by = rect.y + cy - 1
            ch = OCTANT_LUT[bits + 1]
            set_char!(buf, bx, by, ch, c.style)
        end
    end
end

# Backend-agnostic dispatches (OctantCanvas is defined after sixel_canvas.jl)
canvas_dot_size(c::OctantCanvas) = (c.width * 2, c.height * 4)
render_canvas(c::OctantCanvas, rect::Rect, f::Frame; tick::Int=0) =
    render(c, rect, f.buffer)
