# ═══════════════════════════════════════════════════════════════════════
# Sixel Gallery ── performance monitor dashboard using PixelImage
#
# Showcases PixelImage widgets for dense data visualization in bounded
# sub-panes alongside normal text widgets.  All data is simulated with
# noise-driven patterns — no real system calls.
#
# On sixel-capable terminals, renders at pixel resolution.
# On plain terminals, falls back to braille sampling (degraded but functional).
#
# Controls:
#   0–5   — focus pane (0 = all, 1–5 = individual)
#   z/Tab — cycle pane focus
#   p     — pause simulation
#   q/Esc — quit
# ═══════════════════════════════════════════════════════════════════════

# Resting weights that reproduce original layout:
#   Row heights 35/35/30, Row 1 columns 65/35, Row 2 columns 50/50.
# Row height = avg(pane springs in row); col width = ratio of springs.
const _SIXEL_REST = (1.857, 1.0, 1.429, 1.429, 1.224)
const _SIXEL_FOCUS_HI = 8.0
const _SIXEL_FOCUS_LO = 0.3

@kwdef mutable struct SixelGalleryModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    focus::Int = 0              # 0 = all, 1-5 = focus pane
    pane_springs::Vector{Spring} = [
        Spring(_SIXEL_REST[i]; stiffness=180.0) for i in 1:5
    ]
    # Simulated data state
    cpu_history::Vector{Vector{Float64}} = [Float64[] for _ in 1:100]  # 100 cores
    latency_history::Vector{Vector{Float64}} = [Float64[] for _ in 1:32]  # 32 buckets
    mem_pages::Matrix{Float64} = zeros(64, 64)   # page ages (0=free, >0=allocated)
    avg_load::Vector{Float64} = Float64[]
end

should_quit(m::SixelGalleryModel) = m.quit

function init!(m::SixelGalleryModel, ::Terminal)
    # Initialize memory pages with some allocations
    for i in eachindex(m.mem_pages)
        m.mem_pages[i] = rand() < 0.4 ? rand() * 100.0 : 0.0
    end
end

function update!(m::SixelGalleryModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        if evt.char == 'z'
            _sixel_cycle_focus!(m)
            return
        end
        for c in ('0', '1', '2', '3', '4', '5')
            if evt.char == c
                m.focus = Int(c) - Int('0')
                _sixel_update_targets!(m)
                return
            end
        end
    end
    if evt.key == :tab
        _sixel_cycle_focus!(m)
        return
    end
    evt.key == :escape && (m.quit = true)
end

function _sixel_cycle_focus!(m::SixelGalleryModel)
    m.focus = m.focus >= 5 ? 0 : m.focus + 1
    _sixel_update_targets!(m)
end

function _sixel_update_targets!(m::SixelGalleryModel)
    for i in 1:5
        if m.focus == 0
            retarget!(m.pane_springs[i], _SIXEL_REST[i])
        elseif i == m.focus
            retarget!(m.pane_springs[i], _SIXEL_FOCUS_HI)
        else
            retarget!(m.pane_springs[i], _SIXEL_FOCUS_LO)
        end
    end
end

# Consume mouse events so they don't propagate and cause terminal artifacts
# over sixel regions.
function update!(::SixelGalleryModel, ::MouseEvent) end

# ── Simulated data generators ────────────────────────────────────────

function _sim_cpu_tick!(m::SixelGalleryModel)
    t = Float64(m.tick) * 0.02
    for core in 1:100
        # Layered noise: base load + correlated bursts
        base = 0.15 + 0.1 * noise(Float64(core) * 0.1 + t)
        burst = max(0.0, noise(Float64(core) * 0.05 + t * 0.5 + 10.0) - 0.3) * 2.0
        spike = max(0.0, noise(Float64(core) * 0.3 + t * 2.0 + 50.0) - 0.7) * 3.0
        util = clamp(base + burst + spike, 0.0, 1.0)
        push!(m.cpu_history[core], util)
        # Keep last 200 samples
        length(m.cpu_history[core]) > 200 && popfirst!(m.cpu_history[core])
    end
    # Average load
    avg = sum(last(h) for h in m.cpu_history if !isempty(h)) / 100.0
    push!(m.avg_load, avg)
    length(m.avg_load) > 60 && popfirst!(m.avg_load)
end

function _sim_latency_tick!(m::SixelGalleryModel)
    t = Float64(m.tick) * 0.03
    for bucket in 1:32
        # Bimodal: fast path peak at bucket 4-6, slow path peak at 20-24
        center1 = 5.0 + noise(t * 0.5) * 2.0
        center2 = 22.0 + noise(t * 0.3 + 100.0) * 3.0
        d1 = exp(-(Float64(bucket) - center1)^2 / 8.0)
        d2 = exp(-(Float64(bucket) - center2)^2 / 12.0) * (0.15 + 0.1 * noise(t))
        freq = clamp(d1 + d2 + noise(Float64(bucket) * 0.2 + t) * 0.05, 0.0, 1.0)
        push!(m.latency_history[bucket], freq)
        length(m.latency_history[bucket]) > 200 && popfirst!(m.latency_history[bucket])
    end
end

function _sim_memory_tick!(m::SixelGalleryModel)
    pages = m.mem_pages
    n = length(pages)
    t = Float64(m.tick)
    # Age existing allocations
    for i in eachindex(pages)
        pages[i] > 0.0 && (pages[i] += 1.0)
    end
    # Random allocations/frees
    for _ in 1:8
        idx = rand(1:n)
        if pages[idx] == 0.0
            pages[idx] = 1.0  # new allocation
        end
    end
    for _ in 1:6
        idx = rand(1:n)
        if pages[idx] > 0.0 && rand() < 0.4
            pages[idx] = 0.0  # free
        end
    end
end

# ── Drawing helpers ──────────────────────────────────────────────────

function _draw_cpu_heatmap!(img::PixelImage, m::SixelGalleryModel)
    pw, ph = img.pixel_w, img.pixel_h
    (pw < 2 || ph < 2) && return
    n_cores = 100
    pixels = img.pixels

    @inbounds for py in 1:ph
        # Map pixel row to core index
        core = clamp(round(Int, (py - 0.5) / ph * n_cores) + 1, 1, n_cores)
        hist = m.cpu_history[core]
        n_samples = length(hist)
        n_samples == 0 && continue
        for px in 1:pw
            # Map pixel column to time sample
            si = clamp(round(Int, (px - 0.5) / pw * n_samples) + 1, 1, n_samples)
            util = hist[si]
            # Color: blue (idle) → yellow (moderate) → red (saturated)
            r, g, b = if util < 0.4
                t = util / 0.4
                (UInt8(round(0x10 * t)), UInt8(round(0x40 + 0x80 * t)), UInt8(round(0xa0 + 0x5f * (1.0 - t))))
            elseif util < 0.7
                t = (util - 0.4) / 0.3
                (UInt8(round(0x10 + 0xd0 * t)), UInt8(round(0xc0 + 0x20 * t)), UInt8(round(0x20 * (1.0 - t))))
            else
                t = (util - 0.7) / 0.3
                (UInt8(round(0xe0 + 0x1f * t)), UInt8(round(0xe0 * (1.0 - t * 0.7))), UInt8(0x00))
            end
            pixels[py, px] = ColorRGB(r, g, b)
        end
    end
end

function _draw_latency_heatmap!(img::PixelImage, m::SixelGalleryModel)
    pw, ph = img.pixel_w, img.pixel_h
    (pw < 2 || ph < 2) && return
    n_buckets = 32
    pixels = img.pixels

    @inbounds for py in 1:ph
        # Map pixel row to latency bucket (inverted: high latency at top)
        bucket = clamp(n_buckets + 1 - round(Int, (py - 0.5) / ph * n_buckets + 0.5), 1, n_buckets)
        hist = m.latency_history[bucket]
        n_samples = length(hist)
        n_samples == 0 && continue
        for px in 1:pw
            si = clamp(round(Int, (px - 0.5) / pw * n_samples) + 1, 1, n_samples)
            freq = hist[si]
            # Color: dark → bright cyan/white for frequency
            v = clamp(freq, 0.0, 1.0)
            r = UInt8(round(0x10 + 0x40 * v))
            g = UInt8(round(0x20 + 0xd0 * v))
            b = UInt8(round(0x30 + 0xcf * v))
            if v > 0.05
                pixels[py, px] = ColorRGB(r, g, b)
            end
        end
    end
end

function _draw_memory_map!(img::PixelImage, m::SixelGalleryModel)
    pw, ph = img.pixel_w, img.pixel_h
    (pw < 2 || ph < 2) && return
    pages = m.mem_pages
    gh, gw = size(pages)
    pixels = img.pixels

    @inbounds for py in 1:ph
        gy = clamp(round(Int, (py - 0.5) / ph * gh) + 1, 1, gh)
        for px in 1:pw
            gx = clamp(round(Int, (px - 0.5) / pw * gw) + 1, 1, gw)
            age = pages[gy, gx]
            if age == 0.0
                # Free: very dark
                pixels[py, px] = ColorRGB(0x08, 0x08, 0x08)
            else
                # Allocated: green (fresh) → blue (old)
                t = clamp(age / 200.0, 0.0, 1.0)
                r = UInt8(round(0x20 * (1.0 - t)))
                g = UInt8(round(0xc0 * (1.0 - t) + 0x30 * t))
                b = UInt8(round(0x30 * (1.0 - t) + 0xc0 * t))
                pixels[py, px] = ColorRGB(r, g, b)
            end
        end
    end
end

function _draw_flame_graph!(img::PixelImage, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    (pw < 2 || ph < 2) && return
    pixels = img.pixels
    t = Float64(tick) * 0.01

    # Simulated flame graph: 8 stack depth levels
    n_levels = min(8, ph ÷ 2)
    n_levels < 1 && return
    level_h = ph ÷ n_levels

    # Predefined "function" widths per level (simulate call stacks)
    for level in 1:n_levels
        py_start = (level - 1) * level_h + 1
        py_end = min(level * level_h, ph)

        # Number of functions at this level increases with depth
        n_funcs = level + 1
        # Stable function boundaries from noise
        boundaries = Float64[0.0]
        for fi in 1:(n_funcs - 1)
            b = noise(Float64(fi) * 3.7 + Float64(level) * 7.1) * 0.3 + Float64(fi) / n_funcs
            push!(boundaries, clamp(b, boundaries[end] + 0.02, 1.0 - 0.02 * (n_funcs - fi)))
        end
        push!(boundaries, 1.0)

        for fi in 1:n_funcs
            x0 = round(Int, boundaries[fi] * pw) + 1
            x1 = round(Int, boundaries[fi + 1] * pw)
            x0 > x1 && continue

            # Color per "function" (stable, based on function index + level)
            seed = Float64(fi * 17 + level * 31)
            hue = mod(seed * 37.0, 360.0)
            sat = 0.6 + 0.2 * noise(seed * 0.1)
            val = 0.4 + 0.3 * noise(seed * 0.2)

            # Hot-path shimmer
            is_hot = noise(seed * 0.05 + t * 0.5) > 0.6
            if is_hot
                val += 0.15 * (0.5 + 0.5 * sin(t * 4.0 + seed))
            end
            val = clamp(val, 0.0, 1.0)

            c = hue / 60.0
            x_hsv = val * sat * (1.0 - abs(mod(c, 2.0) - 1.0))
            m_hsv = val * (1.0 - sat)
            r1, g1, b1 = if c < 1.0
                (val * sat + m_hsv, x_hsv + m_hsv, m_hsv)
            elseif c < 2.0
                (x_hsv + m_hsv, val * sat + m_hsv, m_hsv)
            elseif c < 3.0
                (m_hsv, val * sat + m_hsv, x_hsv + m_hsv)
            elseif c < 4.0
                (m_hsv, x_hsv + m_hsv, val * sat + m_hsv)
            elseif c < 5.0
                (x_hsv + m_hsv, m_hsv, val * sat + m_hsv)
            else
                (val * sat + m_hsv, m_hsv, x_hsv + m_hsv)
            end
            color = ColorRGB(UInt8(round(r1 * 255)), UInt8(round(g1 * 255)), UInt8(round(b1 * 255)))

            @inbounds for py in py_start:py_end
                for px in x0:min(x1, pw)
                    pixels[py, px] = color
                end
            end

            # 1px border between functions
            if x1 < pw
                @inbounds for py in py_start:py_end
                    pixels[py, min(x1 + 1, pw)] = ColorRGB(0x10, 0x10, 0x10)
                end
            end
        end
    end
end

# ── Pane renderers ────────────────────────────────────────────────────

function _render_cpu_pane!(area::Rect, buf::Buffer, f::Frame, m::SixelGalleryModel)
    focused = m.focus == 1
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:title)
    blk = Block(title="CPU Cores (100)",
                border_style=bs, title_style=ts)
    inner = render(blk, area, buf)
    if inner.width >= 2 && inner.height >= 2
        img = PixelImage(inner.width, inner.height)
        _draw_cpu_heatmap!(img, m)
        render(img, inner, f; tick=m.tick)
    end
end

function _render_summary_pane!(area::Rect, buf::Buffer, m::SixelGalleryModel)
    focused = m.focus == 2
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:title)
    blk = Block(title="Summary",
                border_style=bs, title_style=ts)
    inner = render(blk, area, buf)
    (inner.width >= 4 && inner.height >= 4) || return
    iy = inner.y
    avg = isempty(m.avg_load) ? 0.0 : last(m.avg_load)
    peak = isempty(m.avg_load) ? 0.0 : maximum(m.avg_load)
    set_string!(buf, inner.x, iy, "Avg: $(round(Int, avg * 100))%", tstyle(:text))
    iy += 1
    set_string!(buf, inner.x, iy, "Peak: $(round(Int, peak * 100))%", tstyle(:accent))
    iy += 2
    if iy + 1 <= bottom(inner)
        gauge_w = inner.width
        filled = round(Int, avg * gauge_w)
        bar = repeat("█", filled) * repeat("░", max(0, gauge_w - filled))
        length(bar) > gauge_w && (bar = bar[1:gauge_w])
        set_string!(buf, inner.x, iy, bar, tstyle(:accent))
        iy += 2
    end
    if iy <= bottom(inner) && length(m.avg_load) >= 2
        spark_w = min(inner.width, length(m.avg_load))
        vals = m.avg_load[end-spark_w+1:end]
        for (si_x, v) in enumerate(vals)
            bar_idx = clamp(round(Int, v * 8), 1, 8)
            bx = inner.x + si_x - 1
            bx > right(inner) && break
            set_char!(buf, bx, iy, BARS_V[bar_idx], tstyle(:primary))
        end
        iy += 1
    end
    if iy + 1 <= bottom(inner)
        iy += 1
        n_alloc = count(>(0.0), m.mem_pages)
        n_total = length(m.mem_pages)
        set_string!(buf, inner.x, iy, "Mem: $(n_alloc)/$(n_total)", tstyle(:text_dim))
    end
end

function _render_latency_pane!(area::Rect, buf::Buffer, f::Frame, m::SixelGalleryModel)
    focused = m.focus == 3
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:title)
    blk = Block(title="Latency Heatmap",
                border_style=bs, title_style=ts)
    inner = render(blk, area, buf)
    if inner.width >= 2 && inner.height >= 2
        img = PixelImage(inner.width, inner.height)
        _draw_latency_heatmap!(img, m)
        render(img, inner, f; tick=m.tick)
    end
end

function _render_memory_pane!(area::Rect, buf::Buffer, f::Frame, m::SixelGalleryModel)
    focused = m.focus == 4
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:title)
    blk = Block(title="Memory Map",
                border_style=bs, title_style=ts)
    inner = render(blk, area, buf)
    if inner.width >= 2 && inner.height >= 2
        img = PixelImage(inner.width, inner.height)
        _draw_memory_map!(img, m)
        render(img, inner, f; tick=m.tick)
    end
end

function _render_flame_pane!(area::Rect, buf::Buffer, f::Frame, m::SixelGalleryModel)
    focused = m.focus == 5
    bs = focused ? tstyle(:accent, bold=true) : tstyle(:border)
    ts = focused ? tstyle(:accent, bold=true) : tstyle(:title)
    blk = Block(title="Flame Graph",
                border_style=bs, title_style=ts)
    inner = render(blk, area, buf)
    if inner.width >= 4 && inner.height >= 2
        img = PixelImage(inner.width, inner.height)
        _draw_flame_graph!(img, m.tick)
        render(img, inner, f; tick=m.tick)
    end
end

# ── View ─────────────────────────────────────────────────────────────

function view(m::SixelGalleryModel, f::Frame)
    if !m.paused
        m.tick += 1
        _sim_cpu_tick!(m)
        _sim_latency_tick!(m)
        _sim_memory_tick!(m)
    end
    buf = f.buffer

    # Advance pane springs
    dt = 1.0 / 20.0
    for s in m.pane_springs
        advance!(s; dt=dt)
    end

    # Main layout
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    content = rows[2]
    footer = rows[3]

    # Header
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header.x + 2, header.y,
                "Sixel Gallery", tstyle(:primary, bold=true))
    focus_label = m.focus == 0 ? "all" : string(m.focus)
    set_string!(buf, header.x + 16, header.y,
                " $(DOT) Performance Monitor $(DOT) focus=$(focus_label)", tstyle(:text_dim))

    # ── Spring-driven layout ──
    # Pane mapping: 1=CPU, 2=Summary (row 1); 3=Latency, 4=Memory (row 2); 5=Flame (row 3)
    w = ntuple(i -> max(0.05, m.pane_springs[i].value), 5)

    # Row heights from average of pane springs in each row
    row1_h = (w[1] + w[2]) / 2.0
    row2_h = (w[3] + w[4]) / 2.0
    row3_h = w[5]
    total_h = row1_h + row2_h + row3_h
    p_row1 = round(Int, row1_h / total_h * 100)
    p_row2 = round(Int, row2_h / total_h * 100)

    vert_rows = split_layout(Layout(Vertical, [Percent(p_row1), Percent(p_row2), Fill()]), content)
    length(vert_rows) < 3 && return

    # Row 1: CPU heatmap + Summary
    p_col1_r1 = round(Int, w[1] / (w[1] + w[2]) * 100)
    top_cols = split_layout(Layout(Horizontal, [Percent(p_col1_r1), Fill()]), vert_rows[1])
    if length(top_cols) >= 2
        _render_cpu_pane!(top_cols[1], buf, f, m)
        _render_summary_pane!(top_cols[2], buf, m)
    end

    # Row 2: Latency heatmap + Memory map
    p_col1_r2 = round(Int, w[3] / (w[3] + w[4]) * 100)
    mid_cols = split_layout(Layout(Horizontal, [Percent(p_col1_r2), Fill()]), vert_rows[2])
    if length(mid_cols) >= 2
        _render_latency_pane!(mid_cols[1], buf, f, m)
        _render_memory_pane!(mid_cols[2], buf, f, m)
    end

    # Row 3: Flame graph
    _render_flame_pane!(vert_rows[3], buf, f, m)

    # Footer
    render(StatusBar(
        left=[Span("  [0-5]focus [z/Tab]cycle [p]ause ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function sixel_gallery(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(SixelGalleryModel(); fps=20)
end
