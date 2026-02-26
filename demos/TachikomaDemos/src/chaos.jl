# ═══════════════════════════════════════════════════════════════════════
# Chaos ── logistic map bifurcation diagram on braille canvas
#
# Plots x(n+1) = r·x·(1-x) bifurcation using Canvas braille dots.
# Animated cursor scans r from 2.5→4.0, showing the orbit at each r.
# No external dependencies.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct ChaosModel <: Model
    quit::Bool = false
    tick::Int = 0
    r::Float64 = 2.5
    paused::Bool = false
    speed::Float64 = 0.008
    orbit::Vector{Float64} = Float64[]
end

should_quit(m::ChaosModel) = m.quit

function chaos_compute_orbit!(m::ChaosModel)
    x = 0.5
    for _ in 1:200; x = m.r * x * (1 - x); end
    orbit = Float64[]
    for _ in 1:64
        x = m.r * x * (1 - x)
        push!(orbit, x)
    end
    m.orbit = orbit
end

function init!(m::ChaosModel, ::Terminal)
    chaos_compute_orbit!(m)
end

function update!(m::ChaosModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == ' ' && (m.paused = !m.paused)
        evt.char == 'r' && (m.r = 2.5; m.paused = false)
        evt.char == '+' && (m.speed = min(0.1, m.speed * 1.5))
        evt.char == '=' && (m.speed = min(0.1, m.speed * 1.5))
        evt.char == '-' && (m.speed = max(0.001, m.speed / 1.5))
    elseif evt.key == :right
        m.r = min(4.0, m.r + 0.02)
    elseif evt.key == :left
        m.r = max(2.5, m.r - 0.02)
    elseif evt.key == :up
        m.speed = min(0.1, m.speed * 1.5)
    elseif evt.key == :down
        m.speed = max(0.001, m.speed / 1.5)
    end
    evt.key == :escape && (m.quit = true)
    chaos_compute_orbit!(m)
end

function view(m::ChaosModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Advance r if not paused
    if !m.paused
        m.r += m.speed
        if m.r >= 4.0
            m.r = 4.0
            m.paused = true
        end
        chaos_compute_orbit!(m)
    end

    # Layout: border → plot area + status bar
    block = Block(
        title="logistic map x(n+1) = rx(1-x)",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    content = render(block, f.area, buf)
    x0 = content.x
    status_y = bottom(content)
    plot_area = Rect(x0, content.y, content.width,
                     max(1, content.height - 1))

    cw = plot_area.width
    ch = plot_area.height
    (cw < 4 || ch < 2) && return

    # r range [2.5, 4.0], x range [0, 1]
    r_min, r_max = 2.5, 4.0

    canvas = create_canvas(cw, ch; style=tstyle(:primary))
    dw, dh = canvas_dot_size(canvas)

    # Scale r-step so each dot column gets ~2 samples
    r_step = (r_max - r_min) / dw * 0.5
    # Scale iterations with vertical resolution
    warmup = max(200, dh ÷ 2)
    orbit_iters = max(40, dh ÷ 4)
    for r_i in r_min:r_step:min(m.r, r_max)
        x = 0.5
        for _ in 1:warmup; x = r_i * x * (1 - x); end
        for _ in 1:orbit_iters
            x = r_i * x * (1 - x)
            dx = round(Int, (r_i - r_min) / (r_max - r_min) * (dw - 1))
            dy = round(Int, (1.0 - x) * (dh - 1))
            set_point!(canvas, dx, dy)
        end
    end

    # Cursor vertical line
    cursor_dx = round(Int, (m.r - r_min) / (r_max - r_min) * (dw - 1))
    for dy in 0:(dh - 1)
        set_point!(canvas, cursor_dx, dy)
    end

    # Orbit dots (larger markers)
    for x in m.orbit
        dy = round(Int, (1.0 - x) * (dh - 1))
        for ddx in -1:1, ddy in -1:1
            set_point!(canvas, cursor_dx + ddx, dy + ddy)
        end
    end

    render_canvas(canvas, plot_area, f)

    # Color the cursor column in accent
    cursor_col = cursor_dx ÷ 2 + plot_area.x
    if plot_area.x <= cursor_col <= right(plot_area)
        for row in plot_area.y:bottom(plot_area)
            if in_bounds(buf, cursor_col, row)
                idx = Tachikoma.buf_index(buf, cursor_col, row)
                c = buf.content[idx].char
                set_char!(buf, cursor_col, row, c, tstyle(:accent, bold=true))
            end
        end
    end

    # Status bar
    if status_y <= bottom(f.area) && !isempty(m.orbit)
        n_spark = min(20, length(m.orbit))
        spark_vals = m.orbit[end-n_spark+1:end]
        spark_str = String([BARS_V[clamp(
            round(Int, v * 8), 1, 8)] for v in spark_vals])
        set_string!(buf, x0, status_y, "r=",
                    tstyle(:text_dim))
        set_string!(buf, x0 + 2, status_y,
                    string(round(m.r; digits=4)),
                    tstyle(:primary, bold=true))
        spd_x = x0 + 9
        spd_label = m.paused ? "paused" :
            "v=" * string(round(m.speed; digits=3))
        spd_x = set_string!(buf, spd_x, status_y, spd_label,
                    tstyle(:text_dim))
        set_string!(buf, spd_x + 1, status_y, spark_str,
                    tstyle(:accent))
        inst = " [←→]r [↑↓+-]speed [space]pause [r]eset [q]uit"
        ix = right(content) - length(inst)
        if ix > x0 + 30
            set_string!(buf, ix, status_y, inst,
                        tstyle(:text_dim, dim=true))
        end
    end
end

function chaos(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(ChaosModel(); fps=30)
end
