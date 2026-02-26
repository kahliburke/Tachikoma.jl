# ═══════════════════════════════════════════════════════════════════════
# FPS Stress Test / Monitor Demo
#
# Interactive frame rate stress test and real-time performance monitor.
# Lets the user crank up rendering workload (more sparklines, more
# particles, higher animation complexity) while showing exactly how
# the frame rate responds. Exercises the rendering pipeline under load
# and provides a practical tool for performance tuning.
#
# Controls:
#   ↑/↓  — increase/decrease stress sparklines (1–8)
#   ←/→  — decrease/increase particle count by 50 (10–2000)
#   1–5  — set animation complexity level
#   t    — toggle tokenizer CPU stress
#   s    — toggle sixel pane rendering
#   z/Tab — cycle pane zoom focus
#   f    — open FPS target selector modal
#   q/Esc — quit
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct FPSModel <: Model
    quit::Bool = false
    tick::Int = 0

    # Timing
    last_time::Float64 = time()
    frame_times::Vector{Float64} = Float64[]   # delta-t history (seconds)
    fps_history::Vector{Float64} = Float64[]   # computed FPS per frame
    max_history::Int = 300                      # ~5s at 60fps

    # Stress controls (user-adjustable with keys)
    num_sparklines::Int = 2          # 1–8, rendered in grid
    num_particles::Int = 50          # 10–2000, Canvas dots
    animation_complexity::Int = 1    # 1–5, more noise/shimmer layers
    enable_tokenizer::Bool = false   # toggle: run tokenizer each frame as CPU stress
    enable_sixel::Bool = true        # toggle: pixel pane rendering (s key)

    # Particle state (for Canvas stress)
    particles_x::Vector{Float64} = Float64[]
    particles_y::Vector{Float64} = Float64[]
    particles_vx::Vector{Float64} = Float64[]
    particles_vy::Vector{Float64} = Float64[]

    # FPS target (changeable at runtime via restart)
    target_fps::Int = 60        # 10–240
    restart::Bool = false       # signal to restart with new fps

    # FPS target modal
    show_fps_modal::Bool = false
    fps_modal_selected::Int = 2         # 1-based index into _FPS_PRESETS (default: 60)
    fps_modal_custom::Bool = false      # true when text input is focused
    fps_modal_input::TextInput = TextInput(
        label="Custom:",
        focused=false,
        validator=s -> begin
            isempty(s) && return "Enter a value"
            v = tryparse(Int, s)
            v === nothing && return "Must be a number"
            (v < 1 || v > 999) && return "1–999"
            nothing
        end,
    )

    # Cached PixelImage for the noise pane — reused every frame to avoid
    # allocating a new Matrix{ColorRGB} at 60fps (tens of MB/sec GC pressure).
    pixel_img::Union{PixelImage,Nothing} = nothing

    # Pane focus zoom (0 = none, 1 = sparklines, 2 = particles, 3 = pixel)
    focused_pane::Int = 0
    pane_springs::Vector{Spring} = [
        Spring(1.0; stiffness=200.0),
        Spring(1.0; stiffness=200.0),
        Spring(1.0; stiffness=200.0),
    ]

    # Per-frame timing breakdown
    update_us::Float64 = 0.0    # microseconds for update phase
    render_us::Float64 = 0.0    # microseconds for render phase

    # Smoothed display value (updated once per second)
    display_fps::Int = 0
    display_update_time::Float64 = 0.0
end

const _FPS_PRESETS = [30, 60, 90, 120, 140, 240]

should_quit(m::FPSModel) = m.quit || m.restart

# ── Sample code for tokenizer stress ─────────────────────────────────

const _FPS_SAMPLE_CODE = [
    "function fibonacci(n::Int)::Int",
    "    n <= 1 && return n",
    "    return fibonacci(n - 1) + fibonacci(n - 2)",
    "end",
    "",
    "# Compute the first 20 Fibonacci numbers",
    "results = [fibonacci(i) for i in 1:20]",
    "println(\"Fibonacci: \", results)",
    "",
    "struct Point{T <: Real}",
    "    x::T",
    "    y::T",
    "end",
    "",
    "distance(a::Point, b::Point) = sqrt((a.x - b.x)^2 + (a.y - b.y)^2)",
    "",
    "const ORIGIN = Point(0.0, 0.0)",
    "points = [Point(rand(), rand()) for _ in 1:100]",
    "dists = map(p -> distance(p, ORIGIN), points)",
    "closest = argmin(dists)",
    "",
    "\"\"\"Multi-line string literal test\"\"\"",
    "macro my_macro(ex)",
    "    return esc(ex)",
    "end",
    "",
    "for (i, val) in enumerate(results)",
    "    @printf(\"%3d: %10d\\n\", i, val)",
    "end",
    "",
    "# Dictionary comprehension",
    "freq = Dict(c => count(==(c), str) for c in unique(str))",
    "filter!(p -> p.second > 1, freq)",
    "",
    "try",
    "    open(\"data.csv\", \"r\") do io",
    "        lines = readlines(io)",
    "        data = split.(lines, ',')",
    "    end",
    "catch e",
    "    @warn \"File not found\" exception=e",
    "end",
    "",
    "abstract type Shape end",
    "struct Circle <: Shape; r::Float64; end",
    "struct Rect <: Shape; w::Float64; h::Float64; end",
    "area(c::Circle) = pi * c.r^2",
    "area(r::Rect) = r.w * r.h",
    "",
    "using LinearAlgebra: norm, dot, cross",
]

# ── Particle management ──────────────────────────────────────────────

function _fps_init_particles!(m::FPSModel, canvas_w::Int, canvas_h::Int)
    n = m.num_particles
    resize!(m.particles_x, n)
    resize!(m.particles_y, n)
    resize!(m.particles_vx, n)
    resize!(m.particles_vy, n)
    dot_w = max(1, canvas_w * 2)
    dot_h = max(1, canvas_h * 4)
    for i in 1:n
        m.particles_x[i] = rand() * dot_w
        m.particles_y[i] = rand() * dot_h
        m.particles_vx[i] = (rand() - 0.5) * 4.0
        m.particles_vy[i] = (rand() - 0.5) * 4.0
    end
end

function _fps_resize_particles!(m::FPSModel, canvas_w::Int, canvas_h::Int)
    old_n = length(m.particles_x)
    new_n = m.num_particles
    dot_w = max(1, canvas_w * 2)
    dot_h = max(1, canvas_h * 4)
    if new_n > old_n
        resize!(m.particles_x, new_n)
        resize!(m.particles_y, new_n)
        resize!(m.particles_vx, new_n)
        resize!(m.particles_vy, new_n)
        for i in (old_n+1):new_n
            m.particles_x[i] = rand() * dot_w
            m.particles_y[i] = rand() * dot_h
            m.particles_vx[i] = (rand() - 0.5) * 4.0
            m.particles_vy[i] = (rand() - 0.5) * 4.0
        end
    elseif new_n < old_n
        resize!(m.particles_x, new_n)
        resize!(m.particles_y, new_n)
        resize!(m.particles_vx, new_n)
        resize!(m.particles_vy, new_n)
    end
end

function _fps_update_particles!(m::FPSModel, canvas_w::Int, canvas_h::Int)
    dot_w = Float64(max(1, canvas_w * 2))
    dot_h = Float64(max(1, canvas_h * 4))
    n = length(m.particles_x)
    @inbounds for i in 1:n
        m.particles_x[i] += m.particles_vx[i]
        m.particles_y[i] += m.particles_vy[i]
        # Bounce off walls
        if m.particles_x[i] < 0.0
            m.particles_x[i] = -m.particles_x[i]
            m.particles_vx[i] = -m.particles_vx[i]
        elseif m.particles_x[i] >= dot_w
            m.particles_x[i] = 2.0 * dot_w - m.particles_x[i] - 1.0
            m.particles_vx[i] = -m.particles_vx[i]
        end
        if m.particles_y[i] < 0.0
            m.particles_y[i] = -m.particles_y[i]
            m.particles_vy[i] = -m.particles_vy[i]
        elseif m.particles_y[i] >= dot_h
            m.particles_y[i] = 2.0 * dot_h - m.particles_y[i] - 1.0
            m.particles_vy[i] = -m.particles_vy[i]
        end
    end
end

# ── Key handling ─────────────────────────────────────────────────────

function update!(m::FPSModel, evt::KeyEvent)
    # FPS target modal consumes all keys when open
    if m.show_fps_modal
        _fps_modal_handle_key!(m, evt)
        return
    end

    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 't') => (m.enable_tokenizer = !m.enable_tokenizer)
        (:char, 's') => (m.enable_sixel = !m.enable_sixel)
        (:char, 'f') => _fps_modal_open!(m)
        (:char, 'z') || (:tab, _) => _fps_cycle_focus!(m)
        (:char, c) where '1' <= c <= '5' => (m.animation_complexity = Int(c) - Int('0'))
        (:up, _) => (m.num_sparklines = min(8, m.num_sparklines + 1))
        (:down, _) => (m.num_sparklines = max(1, m.num_sparklines - 1))
        (:right, _) => (m.num_particles = min(2000, m.num_particles + 50))
        (:left, _) => (m.num_particles = max(10, m.num_particles - 50))
        _ => nothing
    end
end

function _fps_cycle_focus!(m::FPSModel)
    m.focused_pane = m.focused_pane >= 3 ? 0 : m.focused_pane + 1
    _fps_update_pane_targets!(m)
end

function _fps_update_pane_targets!(m::FPSModel)
    for i in 1:3
        if m.focused_pane == 0
            retarget!(m.pane_springs[i], 1.0)
        elseif i == m.focused_pane
            retarget!(m.pane_springs[i], 3.0)
        else
            retarget!(m.pane_springs[i], 0.5)
        end
    end
end

function _fps_modal_open!(m::FPSModel)
    m.show_fps_modal = true
    m.fps_modal_custom = false
    m.fps_modal_input.focused = false
    # Pre-select current target if it matches a preset
    idx = findfirst(==(m.target_fps), _FPS_PRESETS)
    if idx !== nothing
        m.fps_modal_selected = idx
    else
        m.fps_modal_selected = length(_FPS_PRESETS) + 1  # custom
        m.fps_modal_custom = true
        m.fps_modal_input.focused = true
        set_text!(m.fps_modal_input, string(m.target_fps))
    end
end

function _fps_modal_confirm!(m::FPSModel)
    n = length(_FPS_PRESETS)
    if m.fps_modal_selected <= n
        new_fps = _FPS_PRESETS[m.fps_modal_selected]
    else
        # Custom input
        v = tryparse(Int, text(m.fps_modal_input))
        (v === nothing || v < 1 || v > 999) && return
        new_fps = v
    end
    m.show_fps_modal = false
    if new_fps != m.target_fps
        m.target_fps = new_fps
        m.restart = true
    end
end

function _fps_modal_handle_key!(m::FPSModel, evt::KeyEvent)
    n = length(_FPS_PRESETS)
    total = n + 1  # presets + custom

    # Escape always closes
    evt.key == :escape && (m.show_fps_modal = false; return)

    # If text input is focused, delegate most keys there
    if m.fps_modal_custom && m.fps_modal_input.focused
        @match evt.key begin
            :enter => _fps_modal_confirm!(m)
            :up => begin
                m.fps_modal_custom = false
                m.fps_modal_input.focused = false
                m.fps_modal_selected = n
            end
            :tab => begin
                m.fps_modal_custom = false
                m.fps_modal_input.focused = false
                m.fps_modal_selected = 1
            end
            _ => handle_key!(m.fps_modal_input, evt)
        end
        return
    end

    # Navigate presets
    @match evt.key begin
        :up => begin
            m.fps_modal_selected = m.fps_modal_selected > 1 ? m.fps_modal_selected - 1 : total
            m.fps_modal_custom = m.fps_modal_selected > n
            m.fps_modal_input.focused = m.fps_modal_custom
        end
        :down || :tab => begin
            m.fps_modal_selected = m.fps_modal_selected < total ? m.fps_modal_selected + 1 : 1
            m.fps_modal_custom = m.fps_modal_selected > n
            m.fps_modal_input.focused = m.fps_modal_custom
        end
        :enter => _fps_modal_confirm!(m)
        _ => nothing
    end
end

# ── Stress sparkline data generation ─────────────────────────────────

function _fps_sparkline_data(tick::Int, idx::Int, complexity::Int, width::Int)
    data = Vector{Float64}(undef, width)
    t = tick / 30.0
    for i in 1:width
        x = Float64(i)
        val = sin(t * 0.7 + x * 0.15 + idx * 1.3)
        if complexity >= 2
            val += 0.5 * noise(x * 0.1 + t * 0.3 + idx * 7.0)
        end
        if complexity >= 3
            val += 0.3 * fbm(x * 0.05 + t * 0.1 + idx * 13.0)
        end
        if complexity >= 4
            val += 0.2 * shimmer(tick, round(Int, x); speed=0.08, scale=0.15)
        end
        if complexity >= 5
            val += 0.15 * fbm(x * 0.08, t * 0.2 + idx * 3.7; octaves=4)
            val += 0.1 * noise(x * 0.2 + t * 1.5)
        end
        data[i] = (val + 2.0) / 4.0  # normalize to roughly [0, 1]
    end
    data
end

# ── View ─────────────────────────────────────────────────────────────

function view(m::FPSModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # ── Frame timing ──
    now = time()
    delta = clamp(now - m.last_time, 0.0001, 1.0)
    m.last_time = now
    fps = 1.0 / delta

    push!(m.frame_times, delta)
    push!(m.fps_history, fps)
    while length(m.frame_times) > m.max_history
        popfirst!(m.frame_times)
    end
    while length(m.fps_history) > m.max_history
        popfirst!(m.fps_history)
    end

    # ── Tokenizer CPU stress ──
    t_update_start = time()
    if m.enable_tokenizer
        for line in _FPS_SAMPLE_CODE
            tokenize_line(collect(line))
        end
    end
    m.update_us = (time() - t_update_start) * 1_000_000.0

    # ── Outer frame ──
    t_render_start = time()

    outer = Block(
        title="FPS Stress Test",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    main = render(outer, f.area, buf)
    main.width < 20 || main.height < 15 && return

    # ── Five-row layout ──
    rows = split_layout(Layout(Vertical, [
            Fixed(7),   # header: BigText FPS + stats
            Fixed(5),   # FPS/frame-time sparklines
            Fill(),     # stress area: sparklines + particles
            Fixed(3),   # timing breakdown
            Fixed(1),   # footer
        ]), main)
    length(rows) < 5 && return

    header_area = rows[1]
    graph_area = rows[2]
    stress_area = rows[3]
    timing_area = rows[4]
    footer_area = rows[5]

    # ── Row 1: BigText FPS + stats ──
    _fps_draw_header(m, buf, header_area, fps, delta)

    # ── Row 2: FPS history + frame time sparklines ──
    _fps_draw_graphs(m, buf, graph_area)

    # ── Row 3: Stress area (sparklines, particles, sixel) ──
    _fps_draw_stress(m, f, stress_area)

    # ── Row 4: Timing breakdown ──
    m.render_us = (time() - t_render_start) * 1_000_000.0
    _fps_draw_timing(m, buf, timing_area)

    # ── Row 5: Footer ──
    render(StatusBar(
            left=[Span(" [↑↓]sparklines [←→]particles [1-5]complexity [t]tokenizer [s]pixel [z/Tab]zoom [f]fps [q]quit ", tstyle(:text_dim))],
            right=[Span("tick $(m.tick) ", tstyle(:text_dim))],
        ), footer_area, buf)

    # ── FPS target modal overlay ──
    m.show_fps_modal && _fps_draw_modal(m, buf, main)
end

# ── Header panel: BigText FPS + statistics ───────────────────────────

function _fps_draw_header(m::FPSModel, buf::Buffer, area::Rect, fps::Float64, delta::Float64)
    area.height < 5 && return

    # Update displayed FPS 4 times per second.
    now_t = time()
    if now_t - m.display_update_time >= 0.25
        window = 0.0
        n_avg = 0
        for i in length(m.frame_times):-1:1
            window += m.frame_times[i]
            n_avg += 1
            window >= 1.0 && break
        end
        m.display_fps = n_avg > 0 && window > 0.0 ? round(Int, Float64(n_avg) / window) : round(Int, fps)
        m.display_update_time = now_t
    end

    # Split: bigtext left, stats right
    bt_text = string(m.display_fps)
    bt_w = intrinsic_size(BigText(bt_text))[1] + 2
    cols = split_layout(Layout(Horizontal, [Fixed(bt_w), Fill()]), area)
    length(cols) < 2 && return

    # BigText FPS number
    render(BigText(bt_text; style=tstyle(:primary, bold=true)), cols[1], buf)

    # Stats column
    stats_area = cols[2]
    stats_area.width < 10 && return
    sx, sy = stats_area.x + 1, stats_area.y

    if !isempty(m.fps_history)
        sorted = sort(m.fps_history)
        n = length(sorted)
        fps_p1 = sorted[max(1, round(Int, n * 0.01))]
        fps_p99 = sorted[min(n, round(Int, n * 0.99))]
        fps_avg = sum(m.fps_history) / n

        set_string!(buf, sx, sy, "FPS (target: $(m.target_fps))", tstyle(:accent, bold=true))
        sy += 1
        set_string!(buf, sx, sy,
            "p1: $(round(fps_p1; digits=1))  avg: $(round(fps_avg; digits=1))  p99: $(round(fps_p99; digits=1))",
            tstyle(:text_dim))
        sy += 1
        frame_ms = delta * 1000.0
        update_ms = m.update_us / 1000.0
        render_ms = m.render_us / 1000.0
        set_string!(buf, sx, sy,
            "frame: $(round(frame_ms; digits=1))ms  update: $(round(update_ms; digits=1))ms  render: $(round(render_ms; digits=1))ms",
            tstyle(:text_dim))
        sy += 1
        tok_str = m.enable_tokenizer ? "ON" : "off"
        six_str = m.enable_sixel ? "ON" : "off"
        set_string!(buf, sx, sy,
            "particles: $(m.num_particles)  sparklines: $(m.num_sparklines)  complexity: $(m.animation_complexity)  tokenizer: $(tok_str)  pixel: $(six_str)",
            tstyle(:text_dim))
    end
end

# ── FPS/frame-time graphs ────────────────────────────────────────────

function _fps_draw_graphs(m::FPSModel, buf::Buffer, area::Rect)
    cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), area)
    length(cols) < 2 && return

    # FPS history sparkline
    fps_block = Block(title="FPS History",
        border_style=tstyle(:border),
        title_style=tstyle(:text_dim))
    fps_inner = render(fps_block, cols[1], buf)
    if fps_inner.height >= 1 && fps_inner.width >= 4 && !isempty(m.fps_history)
        render(Sparkline(m.fps_history; style=tstyle(:primary)), fps_inner, buf)
    end

    # Frame time (ms) sparkline
    ft_block = Block(title="Frame Time (ms)",
        border_style=tstyle(:border),
        title_style=tstyle(:text_dim))
    ft_inner = render(ft_block, cols[2], buf)
    if ft_inner.height >= 1 && ft_inner.width >= 4 && !isempty(m.frame_times)
        ft_ms = m.frame_times .* 1000.0
        render(Sparkline(ft_ms; style=tstyle(:warning)), ft_inner, buf)
    end
end

# ── Stress area: sparklines + particle canvas ────────────────────────

function _fps_draw_stress(m::FPSModel, f::Frame, area::Rect)
    area.height < 3 && return
    buf = f.buffer

    # Advance pane zoom springs
    dt = 1.0 / max(m.target_fps, 1)
    for s in m.pane_springs
        advance!(s; dt=dt)
    end

    # Use spring values as layout weights
    w1 = max(0.1, m.pane_springs[1].value)
    w2 = max(0.1, m.pane_springs[2].value)
    w3 = max(0.1, m.pane_springs[3].value)
    total = w1 + w2 + w3
    p1 = round(Int, w1 / total * 100)
    p2 = round(Int, w2 / total * 100)

    cols = split_layout(Layout(Horizontal, [Percent(p1), Percent(p2), Fill()]), area)
    length(cols) < 3 && return

    # Left: stacked stress sparklines
    _fps_draw_stress_sparklines(m, buf, cols[1])

    # Center: particle canvas
    _fps_draw_particles(m, buf, cols[2])

    # Right: sixel stress
    _fps_draw_sixel_stress(m, f, cols[3])
end

function _fps_draw_stress_sparklines(m::FPSModel, buf::Buffer, area::Rect)
    focused = m.focused_pane == 1
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    blk = Block(title="Stress Sparklines ($(m.num_sparklines))",
        border_style=bs,
        title_style=ts)
    inner = render(blk, area, buf)
    inner.width < 4 || inner.height < 1 && return

    n = m.num_sparklines
    # Divide inner area evenly among sparklines
    constraints = [Fill() for _ in 1:n]
    spark_rows = split_layout(Layout(Vertical, constraints), inner)
    length(spark_rows) < n && (n = length(spark_rows))

    colors = [:primary, :secondary, :accent, :warning, :primary, :secondary, :accent, :warning]

    for i in 1:n
        sr = spark_rows[i]
        sr.height < 1 && continue
        data = _fps_sparkline_data(m.tick, i, m.animation_complexity, sr.width)
        render(Sparkline(data; style=tstyle(colors[i])), sr, buf)
    end
end

function _fps_draw_particles(m::FPSModel, buf::Buffer, area::Rect)
    focused = m.focused_pane == 2
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    blk = Block(title="Particles ($(m.num_particles))",
        border_style=bs,
        title_style=ts)
    inner = render(blk, area, buf)
    inner.width < 2 || inner.height < 2 && return

    cw, ch = inner.width, inner.height

    # Initialize or resize particles
    if isempty(m.particles_x)
        _fps_init_particles!(m, cw, ch)
    elseif length(m.particles_x) != m.num_particles
        _fps_resize_particles!(m, cw, ch)
    end

    # Update particle positions
    _fps_update_particles!(m, cw, ch)

    # Render via Canvas
    canvas = Canvas(cw, ch; style=tstyle(:accent))
    clear!(canvas)
    n = min(length(m.particles_x), m.num_particles)
    for i in 1:n
        dx = round(Int, m.particles_x[i])
        dy = round(Int, m.particles_y[i])
        set_point!(canvas, dx, dy)
    end
    render(canvas, inner, buf)
end

# ── Sixel stress pane ────────────────────────────────────────────────

function _fps_draw_sixel_stress(m::FPSModel, f::Frame, area::Rect)
    focused = m.focused_pane == 3
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    sixel_label = m.enable_sixel ? " Pixel " : " Half-Block "
    blk = Block(title=sixel_label,
        border_style=bs,
        title_style=ts)
    inner = render(blk, area, f.buffer)
    inner.width < 2 || inner.height < 2 && return

    if m.enable_sixel
        _fps_draw_noise_sixel(m, f, inner)
    else
        _fps_draw_noise_halfblock(m, f.buffer, inner)
    end
end

# Shared noise evaluation: same function for both rendering paths
@inline function _fps_noise_val(nx::Float64, ny::Float64, t::Float64, complexity::Int)
    val = noise(nx * 4.0 + t, ny * 4.0)
    if complexity >= 2
        val += 0.5 * fbm(nx * 6.0 + t * 0.7, ny * 6.0; octaves=2)
    end
    if complexity >= 3
        val += 0.3 * noise(nx * 10.0 - t * 1.2, ny * 10.0 + t * 0.5)
    end
    if complexity >= 4
        val += 0.2 * fbm(nx * 8.0, ny * 8.0 + t * 0.3; octaves=4)
    end
    val
end

# Shared color mapping: blue → cyan → green → yellow → red
@inline function _fps_noise_color(val::Float64)
    v = clamp((val + 1.5) / 3.0, 0.0, 1.0)
    r = clamp(2.0 * v - 1.0, 0.0, 1.0)
    g = v < 0.5 ? 2.0 * v : 2.0 * (1.0 - v)
    b = clamp(1.0 - 2.0 * v, 0.0, 1.0)
    ColorRGB(round(UInt8, r * 255), round(UInt8, g * 255), round(UInt8, b * 255))
end

function _fps_draw_noise_sixel(m::FPSModel, f::Frame, inner::Rect)
    # Reuse cached PixelImage; create only on first call or cell-dimension change.
    # This avoids allocating a new Matrix{ColorRGB} every frame (tens of MB/sec
    # of GC pressure at 60fps for a large pixel buffer).
    if m.pixel_img === nothing ||
       m.pixel_img.cells_w != inner.width ||
       m.pixel_img.cells_h != inner.height
        m.pixel_img = PixelImage(inner.width, inner.height; style=tstyle(:accent))
    end
    img = m.pixel_img
    pw, ph = img.pixel_w, img.pixel_h
    (pw < 2 || ph < 2) && return

    t = m.tick * 0.04
    complexity = m.animation_complexity
    @inbounds for py in 1:ph
        ny = py / ph
        for px in 1:pw
            nx = px / pw
            img.pixels[py, px] = _fps_noise_color(_fps_noise_val(nx, ny, t, complexity))
        end
    end
    render(img, inner, f; tick=m.tick)
end

function _fps_draw_noise_halfblock(m::FPSModel, buf::Buffer, inner::Rect)
    # Half-block rendering: ▀ with fg = top color, bg = bottom color
    # gives 2× vertical resolution (2 "pixels" per cell row).
    t = m.tick * 0.04
    complexity = m.animation_complexity
    cw, ch = inner.width, inner.height
    # Total virtual rows: 2 per cell row
    vh = ch * 2
    @inbounds for row in 0:(ch-1)
        y_top = row * 2
        y_bot = row * 2 + 1
        ny_top = y_top / vh
        ny_bot = y_bot / vh
        for col in 0:(cw-1)
            nx = col / cw
            fg = _fps_noise_color(_fps_noise_val(nx, ny_top, t, complexity))
            bg = _fps_noise_color(_fps_noise_val(nx, ny_bot, t, complexity))
            set_char!(buf, inner.x + col, inner.y + row, '▀',
                Style(fg=fg, bg=bg))
        end
    end
end

# ── Timing breakdown ─────────────────────────────────────────────────

function _fps_draw_timing(m::FPSModel, buf::Buffer, area::Rect)
    cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), area)
    length(cols) < 2 && return

    # Left: bar chart of update vs render time
    bc_area = cols[1]
    if bc_area.width >= 10 && bc_area.height >= 1
        entries = [
            BarEntry("update", m.update_us; style=tstyle(:primary)),
            BarEntry("render", m.render_us; style=tstyle(:warning)),
        ]
        max_us = max(m.update_us, m.render_us, 1000.0)
        render(BarChart(entries; max_val=max_us, show_values=true,
                label_width=8), bc_area, buf)
    end

    # Right: load gauges
    gauge_area = cols[2]
    if gauge_area.width >= 10 && gauge_area.height >= 2
        # Frame budget based on target FPS
        budget_us = 1_000_000.0 / m.target_fps
        budget_ms = round(budget_us / 1000.0; digits=1)
        total_us = m.update_us + m.render_us
        load_ratio = clamp(total_us / budget_us, 0.0, 1.0)

        gauge_rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(1), Fill()]), gauge_area)
        length(gauge_rows) < 2 && return

        # Label
        load_pct = round(Int, load_ratio * 100)
        set_string!(buf, gauge_rows[1].x, gauge_rows[1].y,
            " Load: $(load_pct)% of $(budget_ms)ms budget ($(m.target_fps)fps)",
            load_ratio > 0.8 ? tstyle(:error, bold=true) : tstyle(:text_dim))

        # Gauge bar
        color = load_ratio > 0.8 ? :error : load_ratio > 0.5 ? :warning : :primary
        render(Gauge(load_ratio;
                filled_style=tstyle(color),
                empty_style=tstyle(:text_dim, dim=true),
                tick=m.tick),
            gauge_rows[2], buf)
    end
end

# ── FPS target modal ─────────────────────────────────────────────────

function _fps_draw_modal(m::FPSModel, buf::Buffer, area::Rect)
    n = length(_FPS_PRESETS)
    modal_w = 30
    modal_h = n + 5  # presets + custom + padding
    mx = area.x + max(0, (area.width - modal_w) ÷ 2)
    my = area.y + max(0, (area.height - modal_h) ÷ 2)
    modal_rect = Rect(mx, my, min(modal_w, area.width), min(modal_h, area.height))

    # Dim background
    dim_s = tstyle(:text_dim, dim=true)
    for cy in area.y:(area.y+area.height-1)
        for cx in area.x:(area.x+area.width-1)
            set_char!(buf, cx, cy, ' ', dim_s)
        end
    end

    # Modal border
    blk = Block(title="FPS Target",
        border_style=tstyle(:accent, bold=true),
        title_style=tstyle(:accent, bold=true))
    inner = render(blk, modal_rect, buf)
    inner.width < 10 || inner.height < 4 && return

    y = inner.y
    sel = m.fps_modal_selected

    # Draw preset items
    for i in 1:n
        label = "  $(lpad(_FPS_PRESETS[i], 3)) fps"
        if i == sel
            marker_str = string(MARKER, label)
            set_string!(buf, inner.x, y, marker_str, tstyle(:accent, bold=true))
        else
            set_string!(buf, inner.x + 1, y, label, tstyle(:text))
        end
        y += 1
    end

    # Separator
    for cx in inner.x:(inner.x+inner.width-1)
        set_char!(buf, cx, y, '─', tstyle(:border))
    end
    y += 1

    # Custom input row
    custom_selected = sel > n
    if custom_selected
        set_string!(buf, inner.x, y, string(MARKER), tstyle(:accent, bold=true))
    end
    m.fps_modal_input.tick = m.tick
    input_rect = Rect(inner.x + 2, y, inner.width - 2, 1)
    render(m.fps_modal_input, input_rect, buf)
    y += 1

    # Hint
    if y < inner.y + inner.height
        set_string!(buf, inner.x, y, " ↑↓ select  ⏎ confirm", tstyle(:text_dim))
    end
end

function update!(m::FPSModel, ::MouseEvent) end

# ── Entry point ──────────────────────────────────────────────────────

function fps_demo(; theme_name=nothing, fps=60)
    theme_name !== nothing && set_theme!(theme_name)
    model = FPSModel(target_fps=fps)
    while true
        model.restart = false
        model.quit = false
        model.last_time = time()
        app(model; fps=model.target_fps)
        model.restart || break
    end
end
