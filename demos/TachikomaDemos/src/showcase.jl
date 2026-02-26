# ═══════════════════════════════════════════════════════════════════════
# Showcase ── visual feast: rainbow, terrain, springs, sparklines
#
# A multi-panel demo that exercises every visual subsystem at once:
#   • DotWave terrain background (dimmed)
#   • BigText title with rainbow hue-cycling
#   • Animated rainbow arc in braille
#   • Spring-driven gauges
#   • Live sparkline
#   • Shimmer borders
#   • Color wave signal bars
# ═══════════════════════════════════════════════════════════════════════

const RAINBOW_COLORS = ColorRGB[
    ColorRGB(0xff, 0x33, 0x33),  # Red
    ColorRGB(0xff, 0x99, 0x00),  # Orange
    ColorRGB(0xff, 0xee, 0x00),  # Yellow
    ColorRGB(0x33, 0xff, 0x55),  # Green
    ColorRGB(0x33, 0xbb, 0xff),  # Blue
    ColorRGB(0x77, 0x33, 0xff),  # Indigo
    ColorRGB(0xdd, 0x33, 0xff),  # Violet
]

function rainbow_color(t::Float64)
    n = length(RAINBOW_COLORS)
    t = mod(t, 1.0)
    idx = t * (n - 1)
    i = floor(Int, idx)
    frac = idx - i
    c1 = RAINBOW_COLORS[clamp(i + 1, 1, n)]
    c2 = RAINBOW_COLORS[clamp(i + 2, 1, n)]
    color_lerp(c1, c2, frac)
end

@kwdef mutable struct ShowcaseModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    bg::DotWaveBackground = DotWaveBackground(preset=1, amplitude=3.0, cam_height=6.0)
    gauge_springs::Vector{Spring} = [
        Spring(0.7; value=0.1, stiffness=120.0),
        Spring(0.4; value=0.8, stiffness=160.0),
        Spring(0.9; value=0.3, stiffness=100.0),
    ]
    spark_data::Vector{Float64} = zeros(Float64, 60)
    particles::Vector{NTuple{4, Float64}} = NTuple{4, Float64}[]  # (x, y, vx, life)
end

should_quit(m::ShowcaseModel) = m.quit

function update!(m::ShowcaseModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
    end
    evt.key == :escape && (m.quit = true)
end

# ── Rainbow arc renderer ─────────────────────────────────────────────

function _render_rainbow_arc!(buf::Buffer, area::Rect, tick::Int)
    cw = area.width
    ch = area.height
    (cw < 10 || ch < 4) && return

    dot_w = cw * 2
    dot_h = ch * 4

    dots = zeros(UInt8, cw, ch)
    cell_hue = fill(-1.0, cw, ch)

    # Arc center at bottom-center
    cx = Float64(dot_w) * 0.5
    cy = Float64(dot_h) * 0.92

    # Rainbow band geometry
    n_bands = 7
    arc_scale = Float64(min(dot_w, dot_h))
    min_r = arc_scale * 0.35
    max_r = arc_scale * 0.82
    band_w = (max_r - min_r) / Float64(n_bands)

    # Animated phase — colors slide along the arc
    phase = Float64(tick) * 0.008

    # Angle wobble — arc endpoints breathe gently
    wobble = breathe(tick; period=200) * 0.15
    angle_start = 0.0 + wobble * 0.3
    angle_end = π - wobble * 0.3

    for dx in 0:(dot_w - 1)
        for dy in 0:(dot_h - 1)
            px = Float64(dx) - cx
            py = Float64(dy) - cy
            r = sqrt(px * px + py * py)

            # Only upper semicircle
            py >= 0.0 && continue
            (r < min_r || r > max_r) && continue

            # Check angle range
            θ = atan(-py, px)
            (θ < angle_start || θ > angle_end) && continue

            # Rainbow band position (inner = red, outer = violet)
            band_t = (r - min_r) / (max_r - min_r)

            # Add angular shimmer
            angle_t = (θ - angle_start) / (angle_end - angle_start)
            shimmer_v = shimmer(tick, round(Int, angle_t * 40.0 + band_t * 10.0);
                                speed=0.06, scale=0.08)

            rainbow_t = mod(band_t + phase + shimmer_v * 0.05, 1.0)

            col = dx ÷ 2 + 1
            row = dy ÷ 4 + 1
            (1 <= col <= cw && 1 <= row <= ch) || continue
            sx = dx % 2
            sy = dy % 4
            dots[col, row] |= Tachikoma.BRAILLE_MAP[sy + 1][sx + 1]
            cell_hue[col, row] = rainbow_t
        end
    end

    # Render with rainbow colors + brightness variation
    for cy_i in 1:ch
        for cx_i in 1:cw
            bits = dots[cx_i, cy_i]
            bits == 0x00 && continue
            bx = area.x + cx_i - 1
            by = area.y + cy_i - 1
            ch_char = Char(Tachikoma.BRAILLE_OFFSET + bits)
            fg = rainbow_color(cell_hue[cx_i, cy_i])
            # Gentle glow near the center of each band
            br = pulse(tick; period=90, lo=0.85, hi=1.0)
            fg = ColorRGB(
                round(UInt8, clamp(Float64(fg.r) * br, 0, 255)),
                round(UInt8, clamp(Float64(fg.g) * br, 0, 255)),
                round(UInt8, clamp(Float64(fg.b) * br, 0, 255)),
            )
            set_char!(buf, bx, by, ch_char, Style(fg=fg))
        end
    end
end

# ── Sparkle particles ─────────────────────────────────────────────────

function _spawn_particles!(m::ShowcaseModel, area::Rect)
    if rand() < 0.3
        dot_w = area.width * 2
        dot_h = area.height * 4
        cx = Float64(dot_w) * 0.5
        cy = Float64(dot_h) * 0.92
        arc_r = Float64(min(dot_w, dot_h)) * 0.58
        θ = rand() * π
        px = cx + arc_r * cos(θ) + (rand() - 0.5) * 6.0
        py = cy - arc_r * sin(θ) + (rand() - 0.5) * 6.0
        # Convert to cell coords
        cell_x = px / 2.0 + Float64(area.x)
        cell_y = py / 4.0 + Float64(area.y)
        vx = (rand() - 0.5) * 0.3
        push!(m.particles, (cell_x, cell_y, vx, 1.0))
    end
end

function _update_particles!(m::ShowcaseModel)
    filter!(m.particles) do (x, y, vx, life)
        life > 0.05
    end
    m.particles = map(m.particles) do (x, y, vx, life)
        (x + vx, y - 0.08, vx, life * 0.93)
    end
end

function _render_particles!(buf::Buffer, area::Rect, particles, tick::Int)
    sparkle_chars = ('✦', '✧', '·', '⁺', '*')
    for (x, y, _, life) in particles
        ix = round(Int, x)
        iy = round(Int, y)
        in_bounds(buf, ix, iy) || continue
        hue_t = mod(Float64(tick) * 0.02 + x * 0.05, 1.0)
        fg = rainbow_color(hue_t)
        fg = ColorRGB(
            round(UInt8, clamp(Float64(fg.r) * life, 0, 255)),
            round(UInt8, clamp(Float64(fg.g) * life, 0, 255)),
            round(UInt8, clamp(Float64(fg.b) * life, 0, 255)),
        )
        ch = sparkle_chars[mod1(round(Int, life * 20), length(sparkle_chars))]
        set_char!(buf, ix, iy, ch, Style(fg=fg))
    end
end

# ── Main view ─────────────────────────────────────────────────────────

function view(m::ShowcaseModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer
    tick = m.tick

    # ── Background: dimmed terrain (uses global BG config from settings) ──
    render_background!(m.bg, buf, f.area, tick)

    # ── Layout ──
    rows = split_layout(Layout(Vertical, [Fixed(7), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    content_area = rows[2]
    footer_area = rows[3]

    # ── BigText title with rainbow cycling ──
    title_str = "RAINBOW"
    tw = intrinsic_size(BigText(title_str))[1]
    tx = header_area.x + max(0, (header_area.width - tw) ÷ 2)
    title_rect = Rect(tx, header_area.y,
                      min(tw, header_area.width), Tachikoma.BIGTEXT_GLYPH_H)

    title_style_fn = function(x, y)
        # Rainbow hue sweep + time animation
        hue_t = mod(Float64(x) / max(1.0, Float64(tw)) + Float64(tick) * 0.012, 1.0)
        fg = rainbow_color(hue_t)
        # Vertical brightness: center row brightest
        vy = 1.0 - 0.12 * abs(Float64(y) - 2.0) / 2.0
        sh = shimmer(tick, x + y * 31; speed=0.05, scale=0.15)
        brightness = clamp(vy + (sh - 0.5) * 0.25, 0.6, 1.0)
        fg = ColorRGB(
            round(UInt8, clamp(Float64(fg.r) * brightness, 0, 255)),
            round(UInt8, clamp(Float64(fg.g) * brightness, 0, 255)),
            round(UInt8, clamp(Float64(fg.b) * brightness, 0, 255)),
        )
        Style(fg=fg, bold=true)
    end
    render(BigText(title_str; style=tstyle(:primary, bold=true),
                   style_fn=title_style_fn), title_rect, buf)

    # Subtitle
    sub_y = header_area.y + Tachikoma.BIGTEXT_GLYPH_H
    if sub_y <= bottom(header_area)
        subtitle = "Animation $(DOT) Textures $(DOT) Backgrounds $(DOT) Braille"
        sx = header_area.x + max(0, (header_area.width - length(subtitle)) ÷ 2)
        br = breathe(tick; period=100)
        sub_fg = rainbow_color(mod(Float64(tick) * 0.005, 1.0))
        sub_fg = dim_color(sub_fg, 1.0 - (0.5 + br * 0.5))
        set_string!(buf, sx, sub_y, subtitle, Style(fg=sub_fg))
    end

    # ── Content: rainbow arc | info panel ──
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(32)]), content_area)
    length(cols) < 2 && return
    arc_outer = cols[1]
    info_outer = cols[2]

    # Arc panel with shimmer border
    border_shimmer!(buf, arc_outer,
                    rainbow_color(mod(Float64(tick) * 0.01, 1.0)), tick;
                    box=BOX_ROUNDED, intensity=0.2)
    arc_inner = inner(arc_outer)

    _render_rainbow_arc!(buf, arc_inner, tick)
    _spawn_particles!(m, arc_inner)
    _update_particles!(m)
    _render_particles!(buf, arc_inner, m.particles, tick)

    # ── Info panel ──
    info_block = Block(title="Showcase",
                       border_style=tstyle(:border),
                       title_style=tstyle(:title, bold=true),
                       box=BOX_HEAVY)
    info_inner = render(info_block, info_outer, buf)

    iy = info_inner.y
    ix = info_inner.x
    iw = info_inner.width
    ir = right(info_inner)

    # ── Spring-driven gauges ──
    if tick % 120 == 1
        for s in m.gauge_springs
            retarget!(s, rand() * 0.8 + 0.1)
        end
    end
    gauge_labels = ["CPU", "MEM", "NET"]
    gauge_colors = [
        rainbow_color(0.0),   # red
        rainbow_color(0.33),  # green
        rainbow_color(0.66),  # blue
    ]
    for (gi, (spring, label, gc)) in enumerate(zip(m.gauge_springs, gauge_labels, gauge_colors))
        advance!(spring; dt=1.0 / 30.0)
        v = clamp(spring.value, 0.0, 1.0)
        gy = iy + (gi - 1) * 2
        gy > bottom(info_inner) - 1 && break

        set_string!(buf, ix, gy, label, Style(fg=gc, bold=true))

        bar_x = ix + 4
        bar_w = iw - 5
        filled = round(Int, v * bar_w)
        for bx in 0:(bar_w - 1)
            ch_char = bx < filled ? '█' : '░'
            t_bar = Float64(bx) / max(1.0, Float64(bar_w))
            fg = bx < filled ? rainbow_color(mod(t_bar + Float64(tick) * 0.01, 1.0)) : Color256(238)
            set_char!(buf, bar_x + bx, gy, ch_char, Style(fg=fg))
        end
        pct = string(round(Int, v * 100))
        set_string!(buf, bar_x + bar_w - length(pct), gy + 1,
                    "$(pct)%", Style(fg=gc, dim=true))
    end

    # ── Sparkline ──
    spark_y = iy + 7
    if spark_y + 3 <= bottom(info_inner)
        set_string!(buf, ix, spark_y, "Activity", tstyle(:text, bold=true))

        # Update data with animated sine + noise
        if !m.paused
            new_val = 0.5 + 0.3 * sin(Float64(tick) * 0.07) +
                      0.2 * sin(Float64(tick) * 0.13 + 1.0) +
                      0.1 * (2.0 * noise(Float64(tick) * 0.05) - 1.0)
            push!(m.spark_data, clamp(new_val, 0.0, 1.0))
            length(m.spark_data) > iw && popfirst!(m.spark_data)
        end

        spark_area = Rect(ix, spark_y + 1, iw, 3)
        # Draw sparkline manually with rainbow colors
        data = m.spark_data
        nd = length(data)
        for (si, sv) in enumerate(data)
            sx_pos = ix + si - 1
            sx_pos > ir && break
            nn = round(Int, sv * 8)
            ch_char = nn > 0 ? BARS_V[min(nn, 8)] : ' '
            hue = mod(Float64(si) / max(1.0, Float64(nd)) + Float64(tick) * 0.008, 1.0)
            fg = rainbow_color(hue)
            set_char!(buf, sx_pos, spark_y + 3, ch_char, Style(fg=fg, bold=true))
        end
    end

    # ── Signal bars with rainbow ──
    sig_y = iy + 12
    if sig_y + 1 <= bottom(info_inner)
        set_string!(buf, ix, sig_y, "Signal", tstyle(:text, bold=true))
        sig_y += 1
        n_bars = min(iw, 24)
        for bi in 1:n_bars
            phase_v = sin(Float64(tick) / 12.0 + Float64(bi) * 0.6)
            base_v = 0.3 + 0.2 * Float64(bi) / Float64(n_bars)
            val = clamp(base_v + phase_v * 0.25, 0.0, 1.0)
            nn = round(Int, val * 8)
            ch_char = nn > 0 ? BARS_V[min(nn, 8)] : ' '
            hue = mod(Float64(bi) / Float64(n_bars) + Float64(tick) * 0.01, 1.0)
            fg = rainbow_color(hue)
            set_char!(buf, ix + bi - 1, sig_y, ch_char, Style(fg=fg, bold=true))
        end
    end

    # ── Color palette ──
    pal_y = sig_y + 2
    if pal_y + 1 <= bottom(info_inner)
        set_string!(buf, ix, pal_y, "Palette", tstyle(:text, bold=true))
        pal_y += 1
        n_pal = min(iw, 28)
        for pi in 1:n_pal
            hue = mod(Float64(pi - 1) / Float64(n_pal) + Float64(tick) * 0.005, 1.0)
            fg = rainbow_color(hue)
            ch_char = BLOCKS[1]  # █
            set_char!(buf, ix + pi - 1, pal_y, ch_char, Style(fg=fg))
        end
    end

    # ── Spinner + theme info ──
    spin_y = pal_y + 2
    if spin_y <= bottom(info_inner)
        si = mod1(tick ÷ 3, length(SPINNER_BRAILLE))
        hue = mod(Float64(tick) * 0.015, 1.0)
        set_char!(buf, ix, spin_y, SPINNER_BRAILLE[si],
                  Style(fg=rainbow_color(hue)))
        set_string!(buf, ix + 2, spin_y,
                    "$(theme().name) theme", tstyle(:text_dim))
    end

    # ── Footer ──
    si = mod1(tick ÷ 3, length(SPINNER_DOTS))
    set_char!(buf, footer_area.x, footer_area.y,
              SPINNER_DOTS[si], Style(fg=rainbow_color(mod(Float64(tick) * 0.02, 1.0))))

    render(StatusBar(
        left=[Span("  [p]pause [Ctrl+\\]theme [Ctrl+?]help ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function showcase(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(ShowcaseModel(); fps=30)
end
