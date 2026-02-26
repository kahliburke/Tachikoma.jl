# ═══════════════════════════════════════════════════════════════════════
# hero_assets.jl ── Hero logo + sysmon demo renders
#
# Included by generate_assets.jl. All caching/export logic lives there.
# ═══════════════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "logo_preview.jl"))

# ─── Logo ─────────────────────────────────────────────────────────────

const LOGO_RENDER_W = 100
const LOGO_RENDER_H = 14
const LOGO_RENDER_FRAMES = LOOP_PERIOD  # 180 = 6s at 30fps

function render_logo_frame!(buf::Buffer, area::Rect, frame_idx::Int)
    th = theme()
    τ = LOOP_TAU
    t = Float64(frame_idx)

    # Background
    bg_dark = dim_color(to_rgb(th.primary), 0.82)
    bg_mid = dim_color(to_rgb(th.accent), 0.72)
    for row in area.y:bottom(area)
        for col in area.x:right(area)
            in_bounds(buf, col, row) || continue
            v = 0.5 + 0.25 * sin(τ * t * 0.5 + col * 0.08 + row * 0.15) +
                0.15 * cos(τ * t + col * 0.05 - row * 0.1)
            c = color_lerp(bg_dark, bg_mid, clamp(v, 0.0, 1.0))
            set_char!(buf, col, row, ' ', Style(bg=c))
        end
    end

    # Decorative edges
    accent_rgb = to_rgb(th.accent)
    for col in area.x:right(area)
        t_top = 0.5 + 0.4 * sin(τ * t + col * 0.1)
        edge_color = color_lerp(dim_color(accent_rgb, 0.6),
            brighten(accent_rgb, 0.1), clamp(t_top, 0.0, 1.0))
        set_char!(buf, col, area.y, '▁', Style(fg=edge_color))
        t_bot = 0.5 + 0.4 * sin(τ * t * 0.8 + col * 0.08 + 2.0)
        sep_color = color_lerp(dim_color(accent_rgb, 0.7), accent_rgb, clamp(t_bot, 0.0, 1.0))
        set_char!(buf, col, bottom(area), '▔', Style(fg=sep_color))
    end

    # Centering
    jl_vis_w = 14
    total_w = _LP_LOGO_W + 1 + jl_vis_w
    total_h = length(_LP_JL_FINAL6)
    start_x = area.x + max(0, (area.width - total_w) ÷ 2)
    logo_y = area.y + max(1, (area.height - total_h) ÷ 2)

    # TACHIKOMA
    _render_logo_v3!(buf, start_x, logo_y, frame_idx, bottom(area), right(area))

    # .jl suffix
    jl_data = _LP_JL_FINAL6
    jl_x = start_x + _LP_LOGO_W + 1
    jl_y = logo_y
    accent_rgb2 = to_rgb(th.accent)
    amber = ColorRGB(UInt8(255), UInt8(180), UInt8(80))
    c1 = to_rgb(th.primary)

    jl_phase = 7.1
    jl_float = clamp(0.5 +
                     0.25 * sin(τ * t + jl_phase) +
                     0.15 * sin(2τ * t + jl_phase * 0.7) +
                     0.10 * cos(3τ * t + jl_phase * 1.3), 0.0, 1.0)

    for row in 1:length(jl_data)
        for col in 1:length(jl_data[row])
            jl_data[row][col] == '#' || continue
            sx, sy = jl_x + col, jl_y + row
            if in_bounds(buf, sx, sy) && sy <= bottom(area) && sx <= right(area)
                shadow_rgb = dim_color(c1, 0.55 + 0.35 * jl_float)
                set_char!(buf, sx, sy, '░', Style(fg=shadow_rgb))
            end
        end
    end
    for row in 1:length(jl_data)
        for col in 1:length(jl_data[row])
            jl_data[row][col] == '#' || continue
            sx = jl_x + col - 1
            sy = jl_y + row - 1
            if in_bounds(buf, sx, sy) && sx <= right(area) && sy <= bottom(area)
                base_color = color_lerp(accent_rgb2, amber, 0.6)
                c = brighten(base_color, 0.10 + 0.25 * jl_float + 0.05 * sin(τ * t + Float64(col) * 0.3))
                set_char!(buf, sx, sy, '█', Style(fg=c))
            end
        end
    end
end

function generate_logo(cache::Dict{String,String}; force::Bool=false)
    tach_file = joinpath(ASSETS_DIR, "hero_logo.tach")
    src_files = [joinpath(@__DIR__, "logo_preview.jl"),
        joinpath(@__DIR__, "jl_char_data.jl")]
    src_hash = bytes2hex(sha256(join(read(f, String) for f in src_files if isfile(f))))

    if !force && !should_render(cache, "hero_logo", src_hash, tach_file)
        println("  hero_logo: up to date (skipped)")
        return
    end

    println("  hero_logo: rendering $(LOGO_RENDER_FRAMES) frames $(LOGO_RENDER_W)×$(LOGO_RENDER_H)...")
    record_widget(tach_file, LOGO_RENDER_W, LOGO_RENDER_H, LOGO_RENDER_FRAMES; fps=30) do buf, area, frame_idx
        render_logo_frame!(buf, area, frame_idx)
    end
    println("    → $(basename(tach_file))")
    export_formats(tach_file)
    update_cache!(cache, "hero_logo", src_hash, tach_file)
end

# ─── Sysmon Demo ──────────────────────────────────────────────────────

const DEMO_W = 100
const DEMO_H = 30
const DEMO_FPS = 15
const DEMO_DURATION = 6  # seconds
const DEMO_FRAMES = DEMO_FPS * DEMO_DURATION  # 90

const TAB_SWITCH_FRAME = DEMO_FPS * 3  # switch to Processes at 3s

const HERO_PROCS = [
    ["motoko_ai", "S", "22.4", "512.3", "1024"],
    ["tachikoma", "R", "12.1", "148.2", " 847"],
    ["section9_gw", "R", " 8.3", " 96.1", " 423"],
    ["puppet_m", "S", " 4.7", " 67.8", " 312"],
    ["batou_srv", "R", " 3.2", " 52.4", " 201"],
    ["togusa_db", "S", " 2.8", " 31.2", " 156"],
    ["aramaki_ctl", "R", " 1.1", " 19.4", "  89"],
    ["logicoma_01", "R", " 0.9", " 14.1", "  67"],
    ["logicoma_02", "S", " 0.7", " 13.8", "  64"],
    ["laughing_m", "Z", " 0.0", " 24.0", " 112"],
    ["ishikawa_io", "R", " 1.4", " 28.3", " 143"],
    ["saito_snipe", "S", " 0.3", "  8.1", "  34"],
    ["borma_hw", "R", " 0.5", " 11.2", "  56"],
    ["paz_recon", "S", " 0.2", "  6.4", "  28"],
]

function simulate_periodic(frame::Int, fps::Int)
    period = Float64(DEMO_DURATION)
    t = Float64(frame) / fps
    tau = 2pi / period

    cpu_cores = Float64[clamp(
        0.15 + 0.1i + 0.2sin(tau * t + i * 0.8) +
        0.1sin(2tau * t + i * 1.3) + 0.05cos(3tau * t + i * 0.5),
        0.01, 0.99) for i in 1:8]

    avg_cpu = sum(cpu_cores) / 8
    mem_used = clamp(6.0 + 1.5sin(tau * t * 0.5) + 0.5sin(2tau * t * 0.3), 2.0, 14.0)
    swap_used = round(0.8 + 0.3sin(tau * t * 0.7); digits=1)
    rx = clamp(50.0 + 30sin(tau * t) + 10sin(3tau * t + 1.0), 0.0, 100.0)
    tx = clamp(20.0 + 10sin(tau * t * 0.8 + 0.5) + 5sin(2tau * t + 2.0), 0.0, 60.0)

    (; cpu_cores, avg_cpu, mem_used, mem_total=16.0, swap_used, swap_total=4.0, rx, tx)
end

function _draw_line_plot!(canvas::Canvas, data::Vector{Float64}, max_val::Float64)
    dw = canvas.width * 2
    dh = canvas.height * 4 - 1
    n = length(data)
    n < 2 && return
    start = max(1, n - dw + 1)
    for i in 1:(min(dw, n - start + 1)-1)
        v0 = clamp(data[start+i-1] / max_val, 0.0, 1.0)
        v1 = clamp(data[start+i] / max_val, 0.0, 1.0)
        Tachikoma.line!(canvas, i - 1, round(Int, (1.0 - v0) * dh),
            i, round(Int, (1.0 - v1) * dh))
    end
end

function _render_overview!(buf, area, sim, cpu_hist, mem_hist, tick)
    cols = split_layout(Layout(Horizontal, [Percent(45), Fill()]), area)
    length(cols) < 2 && return
    lr = split_layout(Layout(Vertical,
            [Fixed(1), Fixed(length(sim.cpu_cores) + 2), Fixed(1), Fixed(3), Fixed(1), Fill()]), cols[1])
    length(lr) < 6 && return

    set_string!(buf, lr[1].x + 1, lr[1].y, "CPU Cores", tstyle(:text, bold=true))
    bars = [BarEntry("core$(i-1)", v * 100;
        style=v > 0.8 ? tstyle(:error) : v > 0.5 ? tstyle(:warning) : tstyle(:primary))
            for (i, v) in enumerate(sim.cpu_cores)]
    render(BarChart(bars; max_val=100.0, label_width=7), lr[2], buf)

    set_string!(buf, lr[3].x + 1, lr[3].y, "Memory", tstyle(:text, bold=true))
    if lr[4].height >= 2
        gy, gx, gw = lr[4].y, lr[4].x + 1, lr[4].width - 2
        set_string!(buf, gx, gy, "RAM", tstyle(:text_dim))
        render(Gauge(sim.mem_used / sim.mem_total;
                label="$(round(sim.mem_used;digits=1))G / $(sim.mem_total)G",
                filled_style=tstyle(:secondary), tick=tick), Rect(gx + 4, gy, gw - 4, 1), buf)
        set_string!(buf, gx, gy + 1, "SWP", tstyle(:text_dim))
        render(Gauge(sim.swap_used / sim.swap_total;
                label="$(sim.swap_used)G / $(sim.swap_total)G",
                filled_style=tstyle(:warning), tick=tick), Rect(gx + 4, gy + 1, gw - 4, 1), buf)
    end
    if lr[6].height >= 8
        set_string!(buf, lr[5].x + 1, lr[5].y, "Calendar", tstyle(:text, bold=true))
        render(Calendar(2026, 2; today=19), lr[6], buf)
    end

    rr = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1), Fill()]), cols[2])
    length(rr) < 4 && return
    set_string!(buf, rr[1].x + 1, rr[1].y, "CPU History (avg)", tstyle(:text, bold=true))
    if rr[2].width >= 4 && rr[2].height >= 2
        c = Canvas(rr[2].width, rr[2].height; style=tstyle(:primary))
        _draw_line_plot!(c, cpu_hist, 1.0)
        render(c, rr[2], buf)
    end
    set_string!(buf, rr[3].x + 1, rr[3].y, "Memory History", tstyle(:text, bold=true))
    if rr[4].width >= 4 && rr[4].height >= 2
        c = Canvas(rr[4].width, rr[4].height; style=tstyle(:secondary))
        _draw_line_plot!(c, mem_hist, 1.0)
        render(c, rr[4], buf)
    end
end

function _render_processes!(buf, area, selected)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(1)]), area)
    length(cols) < 2 && return
    rstyles = [strip(r[2]) == "R" ? tstyle(:success) :
               strip(r[2]) == "Z" ? tstyle(:error) : tstyle(:text) for r in HERO_PROCS]
    render(Table(["PROCESS", "S", "CPU%", "MEM(MB)", "FDS"], HERO_PROCS;
            block=Block(title="processes ($(length(HERO_PROCS)))",
                border_style=tstyle(:border), title_style=tstyle(:text_dim)),
            selected=selected, row_styles=rstyles), cols[1], buf)
    render(Scrollbar(length(HERO_PROCS),
            min(area.height - 2, length(HERO_PROCS)),
            max(0, selected - 1)), cols[2], buf)
end

function _render_network!(buf, area, rx_hist, tx_hist, rx_cur, tx_cur)
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1), Fill()]), area)
    length(rows) < 4 && return
    set_string!(buf, rows[1].x + 1, rows[1].y, "RX: $(round(rx_cur;digits=1)) MB/s", tstyle(:accent, bold=true))
    if rows[2].width >= 4 && rows[2].height >= 2
        c = Canvas(rows[2].width, rows[2].height; style=tstyle(:accent))
        _draw_line_plot!(c, rx_hist, 100.0)
        render(c, rows[2], buf)
    end
    set_string!(buf, rows[3].x + 1, rows[3].y, "TX: $(round(tx_cur;digits=1)) MB/s", tstyle(:primary, bold=true))
    if rows[4].width >= 4 && rows[4].height >= 2
        c = Canvas(rows[4].width, rows[4].height; style=tstyle(:primary))
        _draw_line_plot!(c, tx_hist, 60.0)
        render(c, rows[4], buf)
    end
end

function generate_demo(cache::Dict{String,String}; force::Bool=false)
    tach_file = joinpath(ASSETS_DIR, "hero_demo.tach")
    src_hash = bytes2hex(sha256(read(joinpath(@__DIR__, "hero_assets.jl"), String)))

    if !force && !should_render(cache, "hero_demo", src_hash, tach_file)
        println("  hero_demo: up to date (skipped)")
        return
    end

    println("  hero_demo: rendering $(DEMO_FRAMES) frames $(DEMO_W)×$(DEMO_H) ($(DEMO_DURATION)s)...")

    cpu_hist = Float64[]
    mem_hist = Float64[]
    rx_hist = Float64[]
    tx_hist = Float64[]
    tab = Ref(1)
    proc_sel = Ref(1)

    record_widget(tach_file, DEMO_W, DEMO_H, DEMO_FRAMES; fps=DEMO_FPS) do buf, area, fi
        fi == TAB_SWITCH_FRAME && (tab[] = 2)
        # Scroll through process table every 3 frames (~5 rows/sec at 15fps)
        tab[] == 2 && fi % 3 == 0 && (proc_sel[] = mod1(proc_sel[] + 1, length(HERO_PROCS)))

        sim = simulate_periodic(fi, DEMO_FPS)
        push!(cpu_hist, sim.avg_cpu)
        length(cpu_hist) > 200 && popfirst!(cpu_hist)
        push!(mem_hist, sim.mem_used / sim.mem_total)
        length(mem_hist) > 200 && popfirst!(mem_hist)
        push!(rx_hist, sim.rx)
        length(rx_hist) > 200 && popfirst!(rx_hist)
        push!(tx_hist, sim.tx)
        length(tx_hist) > 200 && popfirst!(tx_hist)

        rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), area)
        length(rows) < 3 && return
        render(TabBar(["Overview", "Processes", "Network"]; active=tab[]), rows[1], buf)

        if tab[] == 1
            _render_overview!(buf, rows[2], sim, cpu_hist, mem_hist, fi)
        else
            _render_processes!(buf, rows[2], proc_sel[])
        end

        avg = round(sim.avg_cpu * 100; digits=1)
        render(StatusBar(
                left=[Span("  CPU: $(avg)%", tstyle(:primary)),
                    Span("  MEM: $(round(sim.mem_used;digits=1))/$(sim.mem_total)G", tstyle(:secondary))],
                right=[Span("[tab/1-3]view [q]quit ", tstyle(:text_dim))],
            ), rows[3], buf)
    end

    println("    → $(basename(tach_file))")
    export_formats(tach_file)
    update_cache!(cache, "hero_demo", src_hash, tach_file)
end

# ─── Code Reveal Demo ─────────────────────────────────────────────────
#
# Random characters cycle and gradually resolve into syntax-highlighted
# Julia source code, sweeping from top-left to bottom-right.

const REVEAL_W = 80
const REVEAL_H = 25
const REVEAL_FPS = 60
const REVEAL_DURATION_S = 5
const REVEAL_FRAMES = REVEAL_FPS * REVEAL_DURATION_S  # 600

const REVEAL_CODE_LINES = [
    "using Tachikoma",
    "",
    "@kwdef mutable struct Dashboard <: Model",
    "    quit::Bool = false",
    "    cpu::Vector{Float64} = Float64[]",
    "    mem::Vector{Float64} = Float64[]",
    "    tick::Int = 0",
    "end",
    "",
    "Tachikoma.should_quit(m::Dashboard) = m.quit",
    "",
    "function Tachikoma.update!(m::Dashboard, msg)",
    "    msg isa KeyEvent && msg.key == :escape &&",
    "        (m.quit = true)",
    "    m.tick += 1",
    "    push!(m.cpu, 0.3 + 0.2sin(m.tick * 0.05))",
    "    push!(m.mem, 0.5 + 0.1cos(m.tick * 0.03))",
    "end",
    "",
    "function Tachikoma.view(m::Dashboard, f::Frame)",
    "    rows = split_layout(",
    "        Layout(Vertical, [Fixed(1), Fill(), Fixed(3)]),",
    "        f.area)",
    "    render(TabBar([\"CPU\", \"Memory\"]; active=1),",
    "        rows[1], f.buffer)",
    "    render(Sparkline(m.cpu; style=tstyle(:primary)),",
    "        rows[2], f.buffer)",
    "    render(Gauge(last(m.mem, 0.5);",
    "        filled_style=tstyle(:accent)), rows[3], f.buffer)",
    "end",
    "",
    "app(Dashboard(); fps=60)",
]

const _REVEAL_KEYWORDS = Set(["using", "function", "end", "if", "for", "return",
    "true", "false", "struct", "mutable", "const", "isa", "nothing"])

const _SCRAMBLE_CHARS = collect(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" *
    "!@#\$%^&*(){}[]|;:<>,./~`+-=_" *
    "░▒▓█▄▀▐▌╔╗╚╝║═╬╠╣╦╩┃━┏┓┗┛" *
    "λΔΣΩπθαβγδ∞∂∇∫≈≠±×÷√∑∏" *
    "←→↑↓↔⇒⇐⟶⟵" *
    "⌘⌥⎇⌈⌉⌊⌋⟨⟩∀∃∈∉⊂⊃∪∩")

function _classify_reveal_line(line::String)
    styles = Symbol[]
    chars = collect(line)
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        if c == '#'
            append!(styles, fill(:text_dim, n - i + 1))
            break
        elseif c == '"'
            push!(styles, :success)
            i += 1
            while i <= n && chars[i] != '"'
                chars[i] == '\\' && i < n && (push!(styles, :success); i += 1)
                push!(styles, :success)
                i += 1
            end
            i <= n && (push!(styles, :success); i += 1)
            continue
        elseif c == ':' && i < n && (isletter(chars[i+1]) || chars[i+1] == '_')
            push!(styles, :accent)
            i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                push!(styles, :accent)
                i += 1
            end
            continue
        elseif isdigit(c) || (c == '.' && i < n && isdigit(chars[i+1]))
            while i <= n && (isdigit(chars[i]) || chars[i] == '.' || chars[i] == 'e')
                push!(styles, :warning)
                i += 1
            end
            continue
        elseif isletter(c) || c == '_' || c == '@'
            ws = i
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] in ('_', '!', '@'))
                i += 1
            end
            word = String(chars[ws:i-1])
            style = if word in _REVEAL_KEYWORDS || startswith(word, "@")
                :accent
            elseif !isempty(word) && isuppercase(first(word))
                :primary
            else
                :text
            end
            append!(styles, fill(style, i - ws))
            continue
        else
            push!(styles, :text)
            i += 1
            continue
        end
    end
    return styles
end

function _compute_reveal_times()
    reveal_start = REVEAL_FPS * 0.4      # 0.4 second in
    reveal_end = 2 * REVEAL_FPS    # 2 seconds in
    max_dist = 0.0
    for (row, line) in enumerate(REVEAL_CODE_LINES)
        for col in 1:length(line)
            line[col] == ' ' && continue
            d = Float64(row) * 2.0 + Float64(col) * 0.5
            max_dist = max(max_dist, d)
        end
    end
    frames = Dict{Tuple{Int,Int},Int}()
    for (row, line) in enumerate(REVEAL_CODE_LINES)
        for col in 1:length(line)
            line[col] == ' ' && continue
            d = Float64(row) * 2.0 + Float64(col) * 0.5
            t = d / max(max_dist, 1.0)
            jitter = noise(Float64(row) * 0.7 + Float64(col) * 0.3) * 0.12
            t = clamp(t + jitter, 0.0, 1.0)
            frames[(row, col)] = reveal_start + round(Int, t * (reveal_end - reveal_start))
        end
    end
    return frames
end

function _render_code_reveal!(buf, area, fi, char_styles, reveal_frames)
    n_sc = length(_SCRAMBLE_CHARS)
    for (row, line) in enumerate(REVEAL_CODE_LINES)
        row > area.height && break
        styles = char_styles[row]
        for col in 1:min(length(line), area.width)
            c = line[col]
            c == ' ' && continue
            sx = area.x + col - 1
            sy = area.y + row - 1
            rf = get(reveal_frames, (row, col), 1)
            if fi >= rf + 12
                # Fully revealed — syntax highlighted
                s = col <= length(styles) ? styles[col] : :text
                set_char!(buf, sx, sy, c, tstyle(s))
            elseif fi >= rf + 4
                # Settling — correct char, bold flash
                s = col <= length(styles) ? styles[col] : :text
                set_char!(buf, sx, sy, c, tstyle(s, bold=true))
            elseif fi >= rf
                # Pop — bright white
                set_char!(buf, sx, sy, c, Style(fg=ColorRGB(UInt8(255), UInt8(255), UInt8(255)), bold=true))
            else
                # Scramble — cycling random chars with varied colors
                phase = fi ÷ 2
                idx = 1 + abs((phase * 7 + row * 13 + col * 31) % n_sc)
                rc = _SCRAMBLE_CHARS[idx]
                v = noise(Float64(fi) * 0.03 + Float64(row) * 0.7 + Float64(col) * 0.3)
                v2 = noise(Float64(fi) * 0.05 + Float64(col) * 0.9 + Float64(row) * 0.4)
                style = if v > 0.8
                    tstyle(:accent, bold=true)
                elseif v > 0.6
                    tstyle(:primary)
                elseif v2 > 0.7
                    tstyle(:secondary)
                elseif v > 0.3
                    tstyle(:border)
                else
                    tstyle(:text_dim, dim=true)
                end
                set_char!(buf, sx, sy, rc, style)
            end
        end
    end
end

function generate_code_reveal(cache::Dict{String,String}; force::Bool=false)
    tach_file = joinpath(ASSETS_DIR, "code_reveal.tach")
    src_hash = bytes2hex(sha256(read(joinpath(@__DIR__, "hero_assets.jl"), String)))

    if !force && !should_render(cache, "code_reveal", src_hash, tach_file)
        println("  code_reveal: up to date (skipped)")
        return
    end

    println("  code_reveal: rendering $(REVEAL_FRAMES) frames $(REVEAL_W)×$(REVEAL_H) ($(REVEAL_DURATION_S)s)...")

    char_styles = [_classify_reveal_line(line) for line in REVEAL_CODE_LINES]
    reveal_frames = _compute_reveal_times()

    record_widget(tach_file, REVEAL_W, REVEAL_H, REVEAL_FRAMES; fps=REVEAL_FPS) do buf, area, fi
        _render_code_reveal!(buf, area, fi, char_styles, reveal_frames)
    end

    println("    → $(basename(tach_file))")
    export_formats(tach_file)
    update_cache!(cache, "code_reveal", src_hash, tach_file)
end

# ─── Quick Start App (index.md side-by-side, no tachi annotation) ────

function _generate_quickstart(cache::Dict{String,String}; force::Bool=false)
    tach_file = joinpath(EXAMPLES_DIR, "quickstart_hello.tach")
    src_hash = bytes2hex(sha256(read(joinpath(@__DIR__, "example_apps.jl"), String)))

    if !force && !should_render(cache, "quickstart_hello", src_hash, tach_file)
        println("  quickstart_hello: up to date (skipped)")
        return
    end

    render_fn = get(APP_REGISTRY, "quickstart_hello", nothing)
    if render_fn === nothing
        @warn "No app registered for quickstart_hello"
        return
    end

    w, h, frames, fps = 60, 25, 300, 30
    println("  quickstart_hello: rendering $(frames) frames $(w)×$(h)...")
    Base.invokelatest(render_fn, tach_file, w, h, frames, fps)
    println("    → $(basename(tach_file))")
    export_formats(tach_file)
    update_cache!(cache, "quickstart_hello", src_hash, tach_file)
end
