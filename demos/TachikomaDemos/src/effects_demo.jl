# ═══════════════════════════════════════════════════════════════════════
# Effects Gallery ── showcase all animation effects
#
# 4-quadrant grid demonstrating every unused animation effect:
#   • fill_gradient! / fill_noise! texture fills
#   • Gauge shimmer, TextInput cursor breathing
#   • glow() radial field with drift() + flicker()
#   • Modal with shimmer border + button pulse
# ═══════════════════════════════════════════════════════════════════════

const GRADIENT_DIRS = (:horizontal, :vertical, :diagonal)

@kwdef mutable struct EffectsModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    gradient_idx::Int = 1          # cycles through GRADIENT_DIRS
    modal_selected::Symbol = :confirm
    gauge_spring::Spring = Spring(0.7; value=0.1, stiffness=120.0)
end

should_quit(m::EffectsModel) = m.quit

function update!(m::EffectsModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'g' && (m.gradient_idx = mod1(m.gradient_idx + 1, length(GRADIENT_DIRS)))
        evt.char == ' ' && (m.paused = !m.paused)
    elseif evt.key == :tab
        m.modal_selected = m.modal_selected == :confirm ? :cancel : :confirm
    elseif evt.key == :escape
        m.quit = true
    end
end

# ── Top-left: Texture fills ──────────────────────────────────────────

function _render_textures!(buf::Buffer, area::Rect, m::EffectsModel)
    th = theme()
    block = Block(title="Texture Fills",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    inner_area = render(block, area, buf)
    inner_area.height < 4 && return

    # Split into upper (gradient) and lower (noise) halves
    half_h = inner_area.height ÷ 2
    grad_rect = Rect(inner_area.x, inner_area.y, inner_area.width, half_h)
    noise_rect = Rect(inner_area.x, inner_area.y + half_h,
                      inner_area.width, inner_area.height - half_h)

    # Gradient fill
    dir = GRADIENT_DIRS[m.gradient_idx]
    fill_gradient!(buf, grad_rect,
                   to_rgb(th.primary), to_rgb(th.accent); direction=dir)

    # Label overlay on gradient
    dir_label = "fill_gradient! :$(dir)"
    lx = grad_rect.x + max(0, (grad_rect.width - length(dir_label)) ÷ 2)
    ly = grad_rect.y + grad_rect.height ÷ 2
    if in_bounds(buf, lx, ly)
        set_string!(buf, lx, ly, dir_label,
                    Style(fg=Color256(0), bg=th.primary, bold=true))
    end

    # Noise fill
    fill_noise!(buf, noise_rect,
                to_rgb(th.secondary), to_rgb(th.accent), m.tick;
                scale=0.2, speed=0.03)

    # Label overlay on noise
    noise_label = "fill_noise!"
    nx = noise_rect.x + max(0, (noise_rect.width - length(noise_label)) ÷ 2)
    ny = noise_rect.y + noise_rect.height ÷ 2
    if in_bounds(buf, nx, ny)
        set_string!(buf, nx, ny, noise_label,
                    Style(fg=Color256(0), bg=th.secondary, bold=true))
    end
end

# ── Top-right: Widget effects ────────────────────────────────────────

function _render_widgets!(buf::Buffer, area::Rect, m::EffectsModel)
    th = theme()
    block = Block(title="Widget Effects",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    inner_area = render(block, area, buf)
    inner_area.height < 6 && return

    ix = inner_area.x
    iw = inner_area.width
    y = inner_area.y

    # ── Gauge with shimmer ──
    set_string!(buf, ix, y, "Gauge (tick=animated):", tstyle(:text, bold=true))
    y += 1

    # Retarget spring every ~60 ticks
    if m.tick % 60 == 1
        retarget!(m.gauge_spring, rand() * 0.8 + 0.1)
    end
    advance!(m.gauge_spring; dt=1.0 / 30.0)
    v = clamp(m.gauge_spring.value, 0.0, 1.0)

    gauge_rect = Rect(ix, y, iw, 1)
    render(Gauge(v; tick=m.tick,
                 block=nothing,
                 label="$(round(Int, v * 100))%"),
           gauge_rect, buf)
    y += 2

    # ── TextInput with breathing cursor ──
    if y + 1 <= bottom(inner_area)
        set_string!(buf, ix, y, "TextInput (tick=animated):", tstyle(:text, bold=true))
        y += 1
        ti_rect = Rect(ix, y, iw, 1)
        render(TextInput(text="cursor breathes", tick=m.tick, focused=true),
               ti_rect, buf)
        y += 2
    end

    # ── Static TextInput for comparison ──
    if y + 1 <= bottom(inner_area)
        set_string!(buf, ix, y, "TextInput (tick=nothing):", tstyle(:text_dim, bold=true))
        y += 1
        ti2_rect = Rect(ix, y, iw, 1)
        render(TextInput(text="static cursor", tick=nothing, focused=true),
               ti2_rect, buf)
    end
end

# ── Bottom-left: Glow, flicker, drift ────────────────────────────────

function _render_glow!(buf::Buffer, area::Rect, m::EffectsModel)
    th = theme()
    block = Block(title="Glow & Flicker",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    inner_area = render(block, area, buf)
    inner_area.width < 4 && return
    inner_area.height < 4 && return

    w = inner_area.width
    h = inner_area.height

    # Drift-driven center point — maps [0,1] to panel bounds
    dx = drift(m.tick, 1; speed=0.02)
    dy = drift(m.tick, 2; speed=0.015)
    cx = Float64(inner_area.x) + dx * (w - 1)
    cy = Float64(inner_area.y) + dy * (h - 1)

    # Flicker multiplier
    fl = flicker(m.tick, 42; intensity=0.15, speed=0.15)

    base_color = to_rgb(th.accent)
    shade_chars = (' ', '░', '▒', '▓', '█')

    for row in inner_area.y:bottom(inner_area)
        for col in inner_area.x:right(inner_area)
            in_bounds(buf, col, row) || continue
            g = glow(col, row, cx, cy;
                     radius=Float64(max(w, h)) * 0.6, falloff=2.0)
            brightness = clamp(g * fl, 0.0, 1.0)

            # Map brightness to shade character
            ci = clamp(round(Int, brightness * (length(shade_chars) - 1)) + 1,
                       1, length(shade_chars))
            ch = shade_chars[ci]
            fg = brighten(base_color, brightness * 0.5)
            fg = dim_color(fg, 1.0 - brightness)
            set_char!(buf, col, row, ch, Style(fg=fg))
        end
    end

    # Corner labels with live values
    dx_str = "drift=$(round(dx; digits=2))"
    fl_str = "flicker=$(round(fl; digits=2))"
    lx = inner_area.x
    ly = bottom(inner_area)
    if in_bounds(buf, lx, ly)
        set_string!(buf, lx, ly, dx_str, Style(fg=th.text_dim))
    end
    rx = inner_area.x + max(0, w - length(fl_str))
    if in_bounds(buf, rx, ly)
        set_string!(buf, rx, ly, fl_str, Style(fg=th.text_dim))
    end
end

# ── Bottom-right: Modal preview ──────────────────────────────────────

function _render_modal!(buf::Buffer, area::Rect, m::EffectsModel)
    th = theme()
    block = Block(title="Modal",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    inner_area = render(block, area, buf)
    inner_area.width < 12 && return
    inner_area.height < 6 && return

    render(Modal(title="Effects Demo",
                 message="Modal with shimmer border\nand pulsing buttons.",
                 confirm_label="Accept",
                 cancel_label="Decline",
                 selected=m.modal_selected,
                 tick=m.tick),
           inner_area, buf)
end

# ── Main view ─────────────────────────────────────────────────────────

function view(m::EffectsModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer

    # Layout: 2×2 grid + footer
    rows = split_layout(Layout(Vertical, [Fill(), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    top_row = rows[1]
    bot_row = rows[2]
    footer_area = rows[3]

    # Top columns
    top_cols = split_layout(Layout(Horizontal, [Fill(), Fill()]), top_row)
    length(top_cols) >= 2 && _render_textures!(buf, top_cols[1], m)
    length(top_cols) >= 2 && _render_widgets!(buf, top_cols[2], m)

    # Bottom columns
    bot_cols = split_layout(Layout(Horizontal, [Fill(), Fill()]), bot_row)
    length(bot_cols) >= 2 && _render_glow!(buf, bot_cols[1], m)
    length(bot_cols) >= 2 && _render_modal!(buf, bot_cols[2], m)

    # Footer status bar
    dir_name = string(GRADIENT_DIRS[m.gradient_idx])
    pause_label = m.paused ? "resume" : "pause"
    sel_label = string(m.modal_selected)
    render(StatusBar(
        left=[Span("  [g]gradient:$(dir_name) [space]$(pause_label) [tab]modal:$(sel_label) ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function effects_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(EffectsModel(); fps=30)
end
