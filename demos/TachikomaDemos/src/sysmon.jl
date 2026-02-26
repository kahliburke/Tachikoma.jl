# ═══════════════════════════════════════════════════════════════════════
# Sysmon ── system monitor demo with braille plots & bar charts
#
# Showcases Canvas (braille line charts), BarChart, TabBar, StatusBar,
# Calendar, and Scrollbar widgets in a realistic dashboard layout.
# All data is simulated.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct SysmonModel <: Model
    quit::Bool = false
    tick::Int = 0
    tab::Int = 1                             # 1=overview, 2=processes, 3=network
    # Simulated metrics
    cpu_cores::Vector{Float64} = [0.3, 0.5, 0.2, 0.7, 0.4, 0.6, 0.35, 0.55]
    mem_used::Float64 = 6.2                  # GB
    mem_total::Float64 = 16.0
    swap_used::Float64 = 0.8
    swap_total::Float64 = 4.0
    # History for line plots
    cpu_history::Vector{Float64} = zeros(200)
    mem_history::Vector{Float64} = zeros(200)
    net_rx_history::Vector{Float64} = zeros(200)
    net_tx_history::Vector{Float64} = zeros(200)
    # Process list
    proc_selected::Int = 1
    proc_offset::Int = 0
end

should_quit(m::SysmonModel) = m.quit

const SYSMON_PROCS = [
    ["motoko_ai"  , "S", "22.4", "512.3", "1024"],
    ["tachikoma"  , "R", "12.1", "148.2", " 847"],
    ["section9_gw", "R", " 8.3", " 96.1", " 423"],
    ["puppet_m"   , "S", " 4.7", " 67.8", " 312"],
    ["batou_srv"  , "R", " 3.2", " 52.4", " 201"],
    ["togusa_db"  , "S", " 2.8", " 31.2", " 156"],
    ["aramaki_ctl", "R", " 1.1", " 19.4", "  89"],
    ["logicoma_01", "R", " 0.9", " 14.1", "  67"],
    ["logicoma_02", "S", " 0.7", " 13.8", "  64"],
    ["laughing_m" , "Z", " 0.0", " 24.0", " 112"],
    ["ishikawa_io", "R", " 1.4", " 28.3", " 143"],
    ["saito_snipe", "S", " 0.3", "  8.1", "  34"],
    ["borma_hw"   , "R", " 0.5", " 11.2", "  56"],
    ["paz_recon"  , "S", " 0.2", "  6.4", "  28"],
]

function update!(m::SysmonModel, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, '1')                 => (m.tab = 1)
        (:char, '2')                 => (m.tab = 2)
        (:char, '3')                 => (m.tab = 3)
        (:tab, _)                    => (m.tab = mod1(m.tab + 1, 3))
        (:up, _)                     => m.tab == 2 && (m.proc_selected = max(1, m.proc_selected - 1))
        (:down, _)                   => m.tab == 2 && (m.proc_selected = min(length(SYSMON_PROCS),
                                                                              m.proc_selected + 1))
        _                            => nothing
    end
end

function simulate_sysmon!(m::SysmonModel)
    t = m.tick / 30.0

    # CPU cores oscillate independently
    for i in eachindex(m.cpu_cores)
        base = 0.15 + 0.1 * i
        m.cpu_cores[i] = clamp(
            base + 0.2 * sin(t * (0.5 + 0.1i)) +
            0.1 * sin(t * (1.7 + 0.3i)) + 0.03 * randn(),
            0.01, 0.99)
    end

    avg_cpu = sum(m.cpu_cores) / length(m.cpu_cores)
    push!(m.cpu_history, avg_cpu)
    length(m.cpu_history) > 200 && popfirst!(m.cpu_history)

    m.mem_used = clamp(6.0 + 1.5 * sin(t * 0.2) + 0.3 * sin(t * 0.7),
                       2.0, 14.0)
    push!(m.mem_history, m.mem_used / m.mem_total)
    length(m.mem_history) > 200 && popfirst!(m.mem_history)

    rx = clamp(50.0 + 30 * sin(t * 0.8) + 15 * sin(t * 2.1) +
               5 * randn(), 0.0, 100.0)
    tx = clamp(20.0 + 10 * sin(t * 0.6) + 8 * sin(t * 1.9) +
               3 * randn(), 0.0, 60.0)
    push!(m.net_rx_history, rx)
    push!(m.net_tx_history, tx)
    length(m.net_rx_history) > 200 && popfirst!(m.net_rx_history)
    length(m.net_tx_history) > 200 && popfirst!(m.net_tx_history)
end

function draw_line_plot!(canvas::Canvas, data::Vector{Float64},
                         max_val::Float64)
    dw = canvas.width * 2
    dh = canvas.height * 4 - 1
    n = length(data)
    n < 2 && return

    # Plot last dw points
    start = max(1, n - dw + 1)
    for i in 1:(min(dw, n - start + 1) - 1)
        x0 = i - 1
        x1 = i
        v0 = clamp(data[start + i - 1] / max_val, 0.0, 1.0)
        v1 = clamp(data[start + i] / max_val, 0.0, 1.0)
        y0 = round(Int, (1.0 - v0) * dh)
        y1 = round(Int, (1.0 - v1) * dh)
        line!(canvas, x0, y0, x1, y1)
    end
end

function view(m::SysmonModel, f::Frame)
    m.tick += 1
    simulate_sysmon!(m)
    buf = f.buffer

    # ── Layout: tab bar | content | status bar ──
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    tab_area = rows[1]
    content_area = rows[2]
    status_area = rows[3]

    # ── Tab bar ──
    render(TabBar(["Overview", "Processes", "Network"]; active=m.tab),
           tab_area, buf)

    # ── Content based on active tab ──
    @match m.tab begin
        1 => view_overview(m, content_area, buf)
        2 => view_processes(m, content_area, buf)
        _ => view_network(m, content_area, buf)
    end

    # ── Status bar ──
    avg = round(sum(m.cpu_cores) / length(m.cpu_cores) * 100; digits=1)
    render(StatusBar(
        left=[
            Span("  CPU: $(avg)%", tstyle(:primary)),
            Span("  MEM: $(round(m.mem_used;digits=1))/$(m.mem_total)G",
                 tstyle(:secondary)),
        ],
        right=[
            Span("[tab/1-3]view [q]quit ", tstyle(:text_dim)),
        ],
    ), status_area, buf)
end

function view_overview(m::SysmonModel, area::Rect, buf::Buffer)
    cols = split_layout(Layout(Horizontal, [Percent(45), Fill()]), area)
    length(cols) < 2 && return

    # Left: CPU per-core bar chart + memory gauges
    left_rows = split_layout(Layout(Vertical,
        [Fixed(1), Fixed(length(m.cpu_cores) + 2), Fixed(1), Fixed(3),
         Fixed(1), Fill()]), cols[1])
    length(left_rows) < 6 && return

    # CPU header
    set_string!(buf, left_rows[1].x + 1, left_rows[1].y,
                "CPU Cores", tstyle(:text, bold=true))

    # CPU bar chart
    bars = [BarEntry("core$(i-1)", v * 100;
            style=v > 0.8 ? tstyle(:error) :
                  v > 0.5 ? tstyle(:warning) : tstyle(:primary))
            for (i, v) in enumerate(m.cpu_cores)]
    render(BarChart(bars; max_val=100.0, label_width=7),
           left_rows[2], buf)

    # Memory header
    set_string!(buf, left_rows[3].x + 1, left_rows[3].y,
                "Memory", tstyle(:text, bold=true))

    # Memory gauges
    if left_rows[4].height >= 3
        gy = left_rows[4].y
        gw = left_rows[4].width - 2
        gx = left_rows[4].x + 1
        set_string!(buf, gx, gy, "RAM", tstyle(:text_dim))
        render(Gauge(m.mem_used / m.mem_total;
            label="$(round(m.mem_used;digits=1))G / $(m.mem_total)G",
            filled_style=tstyle(:secondary),
            tick=m.tick),
            Rect(gx + 4, gy, gw - 4, 1), buf)
        gy += 1
        set_string!(buf, gx, gy, "SWP", tstyle(:text_dim))
        render(Gauge(m.swap_used / m.swap_total;
            label="$(m.swap_used)G / $(m.swap_total)G",
            filled_style=tstyle(:warning),
            tick=m.tick),
            Rect(gx + 4, gy, gw - 4, 1), buf)
    end

    # Calendar in remaining space
    if left_rows[6].height >= 8
        set_string!(buf, left_rows[5].x + 1, left_rows[5].y,
                    "Calendar", tstyle(:text, bold=true))
        render(Calendar(), left_rows[6], buf)
    end

    # Right: CPU history braille plot + memory history
    right_rows = split_layout(Layout(Vertical,
        [Fixed(1), Fill(), Fixed(1), Fill()]), cols[2])
    length(right_rows) < 4 && return

    set_string!(buf, right_rows[1].x + 1, right_rows[1].y,
                "CPU History (avg)", tstyle(:text, bold=true))

    # CPU history canvas
    plot1 = right_rows[2]
    if plot1.width >= 4 && plot1.height >= 2
        canvas1 = Canvas(plot1.width, plot1.height;
                         style=tstyle(:primary))
        draw_line_plot!(canvas1, m.cpu_history, 1.0)
        render(canvas1, plot1, buf)
    end

    set_string!(buf, right_rows[3].x + 1, right_rows[3].y,
                "Memory History", tstyle(:text, bold=true))

    plot2 = right_rows[4]
    if plot2.width >= 4 && plot2.height >= 2
        canvas2 = Canvas(plot2.width, plot2.height;
                         style=tstyle(:secondary))
        draw_line_plot!(canvas2, m.mem_history, 1.0)
        render(canvas2, plot2, buf)
    end
end

function view_processes(m::SysmonModel, area::Rect, buf::Buffer)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(1)]), area)
    length(cols) < 2 && return

    # Determine row_styles based on process state
    rstyles = Style[]
    for row in SYSMON_PROCS
        st = strip(row[2])
        push!(rstyles, if st == "R"
            tstyle(:success)
        elseif st == "Z"
            tstyle(:error)
        else
            tstyle(:text)
        end)
    end

    render(Table(
        ["PROCESS", "S", "CPU%", "MEM(MB)", "FDS"],
        SYSMON_PROCS;
        block=Block(title="processes ($(length(SYSMON_PROCS)))",
                    border_style=tstyle(:border),
                    title_style=tstyle(:text_dim)),
        selected=m.proc_selected,
        row_styles=rstyles,
    ), cols[1], buf)

    # Scrollbar
    render(Scrollbar(length(SYSMON_PROCS),
                     min(area.height - 2, length(SYSMON_PROCS)),
                     max(0, m.proc_selected - 1)),
           cols[2], buf)
end

function view_network(m::SysmonModel, area::Rect, buf::Buffer)
    rows = split_layout(Layout(Vertical,
        [Fixed(1), Fill(), Fixed(1), Fill()]), area)
    length(rows) < 4 && return

    rx_cur = isempty(m.net_rx_history) ? 0.0 : last(m.net_rx_history)
    tx_cur = isempty(m.net_tx_history) ? 0.0 : last(m.net_tx_history)

    # RX plot
    set_string!(buf, rows[1].x + 1, rows[1].y,
        "RX: $(round(rx_cur;digits=1)) MB/s",
        tstyle(:accent, bold=true))
    plot1 = rows[2]
    if plot1.width >= 4 && plot1.height >= 2
        c1 = Canvas(plot1.width, plot1.height; style=tstyle(:accent))
        draw_line_plot!(c1, m.net_rx_history, 100.0)
        render(c1, plot1, buf)
    end

    # TX plot
    set_string!(buf, rows[3].x + 1, rows[3].y,
        "TX: $(round(tx_cur;digits=1)) MB/s",
        tstyle(:primary, bold=true))
    plot2 = rows[4]
    if plot2.width >= 4 && plot2.height >= 2
        c2 = Canvas(plot2.width, plot2.height; style=tstyle(:primary))
        draw_line_plot!(c2, m.net_tx_history, 60.0)
        render(c2, plot2, buf)
    end
end

function sysmon(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(SysmonModel(); fps=30)
end
