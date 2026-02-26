# ═══════════════════════════════════════════════════════════════════════
# Waves ── animated parametric curves on Canvas braille
#
# Multiple modes: Lissajous, spirograph, sine superposition,
# oscilloscope. Keyboard controls for parameters.
# Showcases Canvas line-drawing at high frame rates.
# ═══════════════════════════════════════════════════════════════════════

@enum WaveMode wave_lissajous wave_spirograph wave_sine wave_scope

@kwdef mutable struct WavesModel <: Model
    quit::Bool = false
    tick::Int = 0
    mode::WaveMode = wave_lissajous
    # Lissajous parameters
    freq_a::Float64 = 3.0
    freq_b::Float64 = 2.0
    phase::Float64 = 0.0
    # Spirograph parameters
    R::Float64 = 5.0
    r::Float64 = 3.0
    d::Float64 = 2.0
    # General
    trail_length::Int = 600
    speed::Float64 = 0.03
    paused::Bool = false
end

should_quit(m::WavesModel) = m.quit

function update!(m::WavesModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        # Mode switching
        evt.char == '1' && (m.mode = wave_lissajous)
        evt.char == '2' && (m.mode = wave_spirograph)
        evt.char == '3' && (m.mode = wave_sine)
        evt.char == '4' && (m.mode = wave_scope)
        # Parameter adjustment
        evt.char == 'w' && (m.freq_a += 0.1; m.R += 0.2)
        evt.char == 's' && (m.freq_a = max(0.1, m.freq_a - 0.1);
                            m.R = max(0.5, m.R - 0.2))
        evt.char == 'd' && (m.freq_b += 0.1; m.r += 0.1)
        evt.char == 'a' && (m.freq_b = max(0.1, m.freq_b - 0.1);
                            m.r = max(0.1, m.r - 0.1))
        evt.char == '+' && (m.speed = min(0.15, m.speed + 0.005))
        evt.char == '=' && (m.speed = min(0.15, m.speed + 0.005))
        evt.char == '-' && (m.speed = max(0.005, m.speed - 0.005))
    elseif evt.key == :up
        m.trail_length = min(2000, m.trail_length + 50)
    elseif evt.key == :down
        m.trail_length = max(50, m.trail_length - 50)
    end
    evt.key == :escape && (m.quit = true)
end

function lissajous_point(t, a, b, delta)
    (sin(a * t + delta), sin(b * t))
end

function spirograph_point(t, R, r, d)
    diff = R - r
    ratio = diff / r
    x = diff * cos(t) + d * cos(ratio * t)
    y = diff * sin(t) - d * sin(ratio * t)
    scale = R + d
    (x / scale, y / scale)
end

function sine_point(t, idx)
    x = t
    y = sin(t + idx * 0.3) * 0.3 +
        sin(2t + idx * 0.7) * 0.2 +
        sin(3t + idx * 1.1) * 0.1
    (x, y)
end

function scope_point(t)
    x = sin(t)
    y = sin(t * 1.5) * cos(t * 0.7)
    (x, y)
end

function view(m::WavesModel, f::Frame)
    m.tick += 1
    if !m.paused
        m.phase += m.speed
    end
    buf = f.buffer

    # Layout
    rows = split_layout(Layout(Vertical,
        [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    canvas_area = rows[2]
    footer = rows[3]

    # Header with mode info
    mode_names = Dict(
        wave_lissajous => "Lissajous (a=$(round(m.freq_a;digits=1)), b=$(round(m.freq_b;digits=1)))",
        wave_spirograph => "Spirograph (R=$(round(m.R;digits=1)), r=$(round(m.r;digits=1)), d=$(round(m.d;digits=1)))",
        wave_sine => "Sine Superposition",
        wave_scope => "Oscilloscope",
    )
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header.x + 2, header.y,
                mode_names[m.mode], tstyle(:primary, bold=true))
    trail_info = " $(DOT) trail=$(m.trail_length)"
    set_string!(buf, header.x + 2 + length(mode_names[m.mode]),
                header.y, trail_info, tstyle(:text_dim))

    # Canvas
    cw = canvas_area.width
    ch = canvas_area.height
    (cw < 4 || ch < 2) && return

    canvas = create_canvas(cw, ch; style=tstyle(:primary))
    dw, dh = canvas_dot_size(canvas)

    if m.mode == wave_lissajous
        for i in 0:m.trail_length
            t = m.phase - i * 0.02
            x, y = lissajous_point(t, m.freq_a, m.freq_b, π / 4)
            dx = round(Int, (x + 1) * 0.5 * (dw - 1))
            dy = round(Int, (y + 1) * 0.5 * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    elseif m.mode == wave_spirograph
        for i in 0:m.trail_length
            t = m.phase + i * 0.03
            x, y = spirograph_point(t, m.R, m.r, m.d)
            dx = round(Int, (x + 1) * 0.5 * (dw - 1))
            dy = round(Int, (y + 1) * 0.5 * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    elseif m.mode == wave_sine
        for wave in 1:5
            prev_dx = -1
            prev_dy = -1
            for px in 0:(dw - 1)
                t = m.phase + px * 0.05
                _, y = sine_point(t, wave)
                dy = round(Int, (y + 0.5) / 1.0 * (dh - 1))
                dy = clamp(dy, 0, dh - 1)
                if prev_dx >= 0
                    line!(canvas, prev_dx, prev_dy, px, dy)
                end
                prev_dx = px
                prev_dy = dy
            end
        end
    else  # scope
        for i in 0:m.trail_length
            t = m.phase + i * 0.01
            x, y = scope_point(t)
            dx = round(Int, (x + 1) * 0.5 * (dw - 1))
            dy = round(Int, (y + 1) * 0.5 * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    end

    render_canvas(canvas, canvas_area, f)

    # Footer
    render(StatusBar(
        left=[Span("  [1-4]mode [w/s]p1 [a/d]p2 [+-]speed [↑↓]trail [p]ause ", tstyle(:text_dim))],
        right=[Span("[q]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function waves(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(WavesModel(); fps=30)
end
