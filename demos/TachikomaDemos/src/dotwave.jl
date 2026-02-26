# ═══════════════════════════════════════════════════════════════════════
# Dot Waves Demo ── interactive rolling hills terrain
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct DotWaveModel <: Model
    quit::Bool = false
    tick::Int = 0
    speed::Float64 = 1.0
    preset_idx::Int = 1
    amplitude::Float64 = 3.0
    cam_height::Float64 = 6.0
    paused::Bool = false
end

should_quit(m::DotWaveModel) = m.quit

function update!(m::DotWaveModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        evt.char == '1' && (m.preset_idx = 1)
        evt.char == '2' && (m.preset_idx = 2)
        evt.char == '3' && (m.preset_idx = 3)
        evt.char == '4' && (m.preset_idx = 4)
        evt.char == 'w' && (m.speed = min(3.0, m.speed + 0.1))
        evt.char == 's' && (m.speed = max(0.1, m.speed - 0.1))
        evt.char == '+' && (m.speed = min(3.0, m.speed + 0.1))
        evt.char == '=' && (m.speed = min(3.0, m.speed + 0.1))
        evt.char == '-' && (m.speed = max(0.1, m.speed - 0.1))
        evt.char == 'd' && (m.amplitude = min(6.0, m.amplitude + 0.3))
        evt.char == 'a' && (m.amplitude = max(0.5, m.amplitude - 0.3))
        evt.char == 'e' && (m.cam_height = min(10.0, m.cam_height + 0.3))
        evt.char == 'r' && (m.cam_height = max(2.0, m.cam_height - 0.3))
    end
    evt.key == :escape && (m.quit = true)
end

function view(m::DotWaveModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    canvas_area = rows[2]
    footer = rows[3]

    preset = DOTWAVE_PRESETS[m.preset_idx]
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    info = "$(preset.name) $(DOT) hills=$(round(m.amplitude; digits=1)) $(DOT) alt=$(round(m.cam_height; digits=1)) $(DOT) speed=$(round(m.speed; digits=1))"
    set_string!(buf, header.x + 2, header.y, info, tstyle(:primary, bold=true))

    render_dotwave_terrain!(buf, canvas_area, m.tick, preset, m.amplitude,
                              m.cam_height, m.speed)

    render(StatusBar(
        left=[Span("  [1-4]preset [w/s]speed [a/d]hills [e/r]altitude [p]pause ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function dotwave(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(DotWaveModel(); fps=30)
end
