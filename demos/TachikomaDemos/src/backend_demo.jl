# ═══════════════════════════════════════════════════════════════════════
# Backend Compare Demo ── 2×2 grid: braille, block, octant, pixel
#
# Draws the same animated pattern into a braille Canvas (top-left),
# a BlockCanvas (top-right), an OctantCanvas (bottom-left), and a
# PixelImage (bottom-right) so users can visually compare backends.
# ═══════════════════════════════════════════════════════════════════════

@enum DemoPattern demo_lissajous demo_spiral demo_sine demo_particles

mutable struct Particle
    x::Float64
    y::Float64
    vx::Float64
    vy::Float64
end

@kwdef mutable struct BackendDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    pattern::DemoPattern = demo_lissajous
    phase::Float64 = 0.0
    speed::Float64 = 0.03
    trail_length::Int = 600
    particles::Vector{Particle} = [Particle(rand(), rand(),
                                            (rand() - 0.5) * 0.02,
                                            (rand() - 0.5) * 0.02)
                                   for _ in 1:80]
    # Sixel pixel scale (for empirical tuning)
    scale_w::Float64 = 1.0
    scale_h::Float64 = 1.0
end

should_quit(m::BackendDemoModel) = m.quit

function update!(m::BackendDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        evt.char == '1' && (m.pattern = demo_lissajous)
        evt.char == '2' && (m.pattern = demo_spiral)
        evt.char == '3' && (m.pattern = demo_sine)
        evt.char == '4' && (m.pattern = demo_particles)
    end
    # Arrow keys: adjust sixel pixel scale
    evt.key == :up    && (m.scale_h = round(m.scale_h + 0.05; digits=2))
    evt.key == :down  && (m.scale_h = round(max(0.1, m.scale_h - 0.05); digits=2))
    evt.key == :right && (m.scale_w = round(m.scale_w + 0.05; digits=2))
    evt.key == :left  && (m.scale_w = round(max(0.1, m.scale_w - 0.05); digits=2))
    evt.key == :escape && (m.quit = true)
end

# ── Pattern drawing (works with any canvas via set_point!/line!) ─────

function _draw_compare_pattern!(canvas, m::BackendDemoModel, dw::Int, dh::Int)
    if m.pattern == demo_lissajous
        for i in 0:m.trail_length
            t = m.phase - i * 0.02
            x, y = lissajous_point(t, 3.0, 2.0, π / 4)
            dx = round(Int, (x + 1) * 0.5 * (dw - 1))
            dy = round(Int, (y + 1) * 0.5 * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    elseif m.pattern == demo_spiral
        for i in 0:m.trail_length
            t = m.phase + i * 0.03
            r = 0.1 + 0.9 * (i / m.trail_length)
            x = r * cos(t * 3.0)
            y = r * sin(t * 3.0)
            dx = round(Int, (x + 1) * 0.5 * (dw - 1))
            dy = round(Int, (y + 1) * 0.5 * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    elseif m.pattern == demo_sine
        for wave in 1:5
            prev_dx = -1
            prev_dy = -1
            for px in 0:(dw - 1)
                t = m.phase + px * 0.05
                y = sin(t + wave * 0.3) * 0.3 +
                    sin(2t + wave * 0.7) * 0.2 +
                    sin(3t + wave * 1.1) * 0.1
                dy = round(Int, (y + 0.5) / 1.0 * (dh - 1))
                dy = clamp(dy, 0, dh - 1)
                if prev_dx >= 0
                    line!(canvas, prev_dx, prev_dy, px, dy)
                end
                prev_dx = px
                prev_dy = dy
            end
        end
    else  # particles
        for p in m.particles
            dx = round(Int, clamp(p.x, 0.0, 1.0) * (dw - 1))
            dy = round(Int, clamp(p.y, 0.0, 1.0) * (dh - 1))
            # Draw a small cross for visibility
            set_point!(canvas, dx, dy)
            set_point!(canvas, dx - 1, dy)
            set_point!(canvas, dx + 1, dy)
            set_point!(canvas, dx, dy - 1)
            set_point!(canvas, dx, dy + 1)
        end
    end
end

function _update_particles!(m::BackendDemoModel)
    for p in m.particles
        p.x += p.vx
        p.y += p.vy
        # Bounce off walls
        if p.x < 0.0 || p.x > 1.0
            p.vx = -p.vx
            p.x = clamp(p.x, 0.0, 1.0)
        end
        if p.y < 0.0 || p.y > 1.0
            p.vy = -p.vy
            p.y = clamp(p.y, 0.0, 1.0)
        end
    end
end

# ── View ─────────────────────────────────────────────────────────────

const PATTERN_NAMES = Dict(
    demo_lissajous => "Lissajous",
    demo_spiral    => "Spiral",
    demo_sine      => "Sine Waves",
    demo_particles => "Particles",
)

function view(m::BackendDemoModel, f::Frame)
    m.tick += 1
    if !m.paused
        m.phase += m.speed
        m.pattern == demo_particles && _update_particles!(m)
    end
    buf = f.buffer

    # Layout: header | [left | center | right] | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    content = rows[2]
    footer = rows[3]

    # Header
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header.x + 2, header.y,
                "Backend Compare", tstyle(:primary, bold=true))
    pname = PATTERN_NAMES[m.pattern]
    cpx = cell_pixels()
    sap = sixel_area_pixels()
    tap = text_area_pixels()
    sixel_info = sap.w > 0 ? "sixel=$(sap.w)x$(sap.h)" : "sixel=n/a"
    set_string!(buf, header.x + 18, header.y,
                " $(DOT) $(pname) $(DOT) px=$(cpx.w)x$(cpx.h) text=$(tap.w)x$(tap.h) $(sixel_info)",
                tstyle(:text_dim))

    # 2×2 grid layout
    grid_rows = split_layout(Layout(Vertical, [Percent(50), Fill()]), content)
    length(grid_rows) < 2 && return
    top_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), grid_rows[1])
    bot_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), grid_rows[2])
    (length(top_cols) < 2 || length(bot_cols) < 2) && return

    # ── Top-left: Braille (2×4 dots per cell) ──
    tl_block = Block(title="Braille 2×4",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    tl_inner = render(tl_block, top_cols[1], buf)

    cw = tl_inner.width
    ch = tl_inner.height
    if cw >= 2 && ch >= 1
        braille_canvas = Canvas(cw, ch; style=tstyle(:primary))
        _draw_compare_pattern!(braille_canvas, m, cw * 2, ch * 4)
        render(braille_canvas, tl_inner, buf)
    end

    # ── Top-right: Block / Quadrant (2×2 dots per cell) ──
    tr_block = Block(title="Block 2×2",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    tr_inner = render(tr_block, top_cols[2], buf)

    cw_m = tr_inner.width
    ch_m = tr_inner.height
    if cw_m >= 2 && ch_m >= 1
        block_canvas = BlockCanvas(cw_m, ch_m; style=tstyle(:primary))
        _draw_compare_pattern!(block_canvas, m, cw_m * 2, ch_m * 2)
        render(block_canvas, tr_inner, buf)
    end

    # ── Bottom-left: Octant (2×4 dots per cell, gap-free) ──
    bl_block = Block(title="Octant 2×4",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    bl_inner = render(bl_block, bot_cols[1], buf)

    cw_o = bl_inner.width
    ch_o = bl_inner.height
    if cw_o >= 2 && ch_o >= 1
        octant_canvas = OctantCanvas(cw_o, ch_o; style=tstyle(:primary))
        _draw_compare_pattern!(octant_canvas, m, cw_o * 2, ch_o * 4)
        render(octant_canvas, bl_inner, buf)
    end

    # ── Bottom-right: PixelImage (pixel-native) ──
    br_block = Block(title="PixelImage",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    br_inner = render(br_block, bot_cols[2], buf)

    cw2 = br_inner.width
    ch2 = br_inner.height
    if cw2 >= 2 && ch2 >= 1
        img = PixelImage(cw2, ch2; style=tstyle(:primary))
        pw, ph = img.pixel_w, img.pixel_h

        # Draw pattern via pixel mapping (same coords → pixel space)
        if m.pattern == demo_lissajous
            for i in 0:m.trail_length
                t = m.phase - i * 0.02
                x, y = lissajous_point(t, 3.0, 2.0, π / 4)
                px = round(Int, (x + 1) * 0.5 * (pw - 1)) + 1
                py = round(Int, (y + 1) * 0.5 * (ph - 1)) + 1
                set_pixel!(img, px, py)
            end
        elseif m.pattern == demo_spiral
            for i in 0:m.trail_length
                t = m.phase + i * 0.03
                r = 0.1 + 0.9 * (i / m.trail_length)
                x = r * cos(t * 3.0)
                y = r * sin(t * 3.0)
                px = round(Int, (x + 1) * 0.5 * (pw - 1)) + 1
                py = round(Int, (y + 1) * 0.5 * (ph - 1)) + 1
                set_pixel!(img, px, py)
            end
        elseif m.pattern == demo_sine
            for wave in 1:5
                prev_px = -1
                prev_py = -1
                for col in 1:pw
                    t = m.phase + (col - 1) * (0.05 * cw2 * 2 / pw)
                    y = sin(t + wave * 0.3) * 0.3 +
                        sin(2t + wave * 0.7) * 0.2 +
                        sin(3t + wave * 1.1) * 0.1
                    py = round(Int, (y + 0.5) / 1.0 * (ph - 1)) + 1
                    py = clamp(py, 1, ph)
                    if prev_px >= 1
                        pixel_line!(img, prev_px, prev_py, col, py)
                    end
                    prev_px = col
                    prev_py = py
                end
            end
        else  # particles
            for p in m.particles
                px = round(Int, clamp(p.x, 0.0, 1.0) * (pw - 1)) + 1
                py = round(Int, clamp(p.y, 0.0, 1.0) * (ph - 1)) + 1
                set_pixel!(img, px, py)
                set_pixel!(img, px - 1, py)
                set_pixel!(img, px + 1, py)
                set_pixel!(img, px, py - 1)
                set_pixel!(img, px, py + 1)
            end
        end
        render(img, br_inner, f; tick=m.tick)
    end

    # Footer
    render(StatusBar(
        left=[Span("  [1-4]pattern [p]ause [↑↓]scaleH [←→]scaleW ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function backend_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(BackendDemoModel(); fps=30)
end
