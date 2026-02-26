# ═══════════════════════════════════════════════════════════════════════
# Dashboard demo ── showcases all widgets + layout + themes
#
# A fake system monitor: CPU/memory gauges, network sparkline,
# process table, log list. Everything is simulated with sin/rand
# so it looks alive without needing real system data.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct DashboardModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Simulated data
    cpu::Float64 = 0.45
    mem::Float64 = 0.62
    disk::Float64 = 0.78
    net_history::Vector{Float64} = zeros(60)
    cpu_history::Vector{Float64} = zeros(60)
    # List state
    log_selected::Int = 1
    log_offset::Int = 0
end

should_quit(m::DashboardModel) = m.quit

const DASHBOARD_LOGS = [
    "system    boot sequence complete",
    "net       interface eth0 up (1000Mbps)",
    "auth      session opened for user tachikoma",
    "kernel    loaded module tachikoma_core",
    "firewall  rule ACCEPT tcp/443 applied",
    "cron      scheduled job: diagnostics",
    "monitor   cpu governor: performance",
    "storage   /dev/sda1 mounted at /",
    "net       DNS resolver configured",
    "auth      public key accepted",
    "system    watchdog timer started",
    "kernel    entropy pool initialized",
    "net       route table updated (3 entries)",
    "monitor   thermal zone 0: 42°C",
    "system    all services nominal",
]

const DASHBOARD_PROCS = [
    ["tachikoma"  , "running", "12.3%", "148 MB"],
    ["section9"   , "running", " 8.1%", " 96 MB"],
    ["laughing_man", "idle"  , " 0.2%", " 24 MB"],
    ["puppet_m"   , "running", " 4.7%", " 67 MB"],
    ["batou_srv"  , "running", " 3.2%", " 52 MB"],
    ["togusa_db"  , "idle"   , " 1.1%", " 31 MB"],
    ["motoko_ai"  , "running", "22.8%", "512 MB"],
    ["aramaki_ctl", "running", " 0.8%", " 19 MB"],
]

function update!(m::DashboardModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
    elseif evt.key == :up
        m.log_selected = max(1, m.log_selected - 1)
    elseif evt.key == :down
        m.log_selected = min(length(DASHBOARD_LOGS),
                             m.log_selected + 1)
    end
    evt.key == :escape && (m.quit = true)
end

function view(m::DashboardModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()

    # ── Simulate data ──
    t = m.tick / 30.0
    m.cpu = clamp(0.35 + 0.25 * sin(t * 0.7) +
                  0.1 * sin(t * 2.3), 0.05, 0.95)
    m.mem = clamp(0.60 + 0.08 * sin(t * 0.3), 0.4, 0.85)
    net_val = clamp(0.4 + 0.35 * sin(t * 1.1) +
                    0.15 * sin(t * 3.7) +
                    0.05 * randn(), 0.0, 1.0)
    push!(m.net_history, net_val)
    length(m.net_history) > 120 && popfirst!(m.net_history)
    push!(m.cpu_history, m.cpu)
    length(m.cpu_history) > 120 && popfirst!(m.cpu_history)

    # ── Outer frame ──
    outer = Block(
        title="tachikoma dashboard",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    main = render(outer, f.area, buf)

    # ── Layout: top row (gauges + sparklines) | bottom row (table + list) ──
    rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(8), Fixed(1), Fill()]), main)
    length(rows) < 4 && return

    header_area = rows[1]
    top_area = rows[2]
    sep_area = rows[3]
    bot_area = rows[4]

    # ── Header ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header_area.x, header_area.y,
              SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header_area.x + 2, header_area.y,
                "$(th.name)", tstyle(:primary, bold=true))
    set_string!(buf, header_area.x + 2 + length(th.name) + 1,
                header_area.y,
                "$(DOT) $(f.area.width)×$(f.area.height) $(DOT) tick $(m.tick)",
                tstyle(:text_dim, dim=true))

    # ── Top: gauges left, sparklines right ──
    top_cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), top_area)
    length(top_cols) < 2 && return

    # Gauge panel
    gauge_block = Block(title="system",
                        border_style=tstyle(:border),
                        title_style=tstyle(:text_dim))
    gauge_inner = render(gauge_block, top_cols[1], buf)

    if gauge_inner.height >= 6 && gauge_inner.width >= 10
        gw = gauge_inner.width
        gy = gauge_inner.y

        set_string!(buf, gauge_inner.x, gy, "CPU", tstyle(:text, bold=true))
        gy += 1
        render(Gauge(m.cpu;
            filled_style=tstyle(:primary),
            empty_style=tstyle(:text_dim, dim=true),
            tick=m.tick),
            Rect(gauge_inner.x, gy, gw, 1), buf)

        gy += 2
        set_string!(buf, gauge_inner.x, gy, "MEM", tstyle(:text, bold=true))
        gy += 1
        render(Gauge(m.mem;
            filled_style=tstyle(:secondary),
            empty_style=tstyle(:text_dim, dim=true),
            tick=m.tick),
            Rect(gauge_inner.x, gy, gw, 1), buf)
    end

    # Sparkline panel
    spark_block = Block(title="network",
                        border_style=tstyle(:border),
                        title_style=tstyle(:text_dim))
    spark_inner = render(spark_block, top_cols[2], buf)

    if spark_inner.height >= 2 && spark_inner.width >= 4
        # Split sparkline area into two stacked charts
        spark_rows = split_layout(Layout(Vertical,
            [Fixed(1), Fill(), Fixed(1), Fill()]), spark_inner)
        if length(spark_rows) >= 4
            set_string!(buf, spark_rows[1].x, spark_rows[1].y,
                        "throughput", tstyle(:text_dim))
            render(Sparkline(m.net_history;
                style=tstyle(:accent)),
                spark_rows[2], buf)

            set_string!(buf, spark_rows[3].x, spark_rows[3].y,
                        "cpu load", tstyle(:text_dim))
            render(Sparkline(m.cpu_history;
                style=tstyle(:primary)),
                spark_rows[4], buf)
        end
    end

    # ── Separator ──
    for cx in main.x:right(main)
        set_char!(buf, cx, sep_area.y, SCANLINE,
                  tstyle(:border, dim=true))
    end

    # ── Bottom: table left, log list right ──
    bot_cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), bot_area)
    length(bot_cols) < 2 && return

    # Process table
    render(Table(
        ["NAME", "STATUS", "CPU", "MEM"],
        DASHBOARD_PROCS;
        block=Block(title="processes",
                    border_style=tstyle(:border),
                    title_style=tstyle(:text_dim)),
        header_style=tstyle(:title, bold=true),
        row_style=tstyle(:text),
        alt_row_style=tstyle(:text_dim),
    ), bot_cols[1], buf)

    # Log list
    render(SelectableList(
        [ListItem(l, tstyle(:text)) for l in DASHBOARD_LOGS];
        selected=m.log_selected,
        offset=m.log_offset,
        block=Block(title="logs",
                    border_style=tstyle(:border),
                    title_style=tstyle(:text_dim)),
        highlight_style=tstyle(:accent, bold=true),
        tick=m.tick,
    ), bot_cols[2], buf)

    # ── Footer ──
    fy = bottom(f.area)
    if fy > bottom(main)
        fy = bottom(main)
    end
    inst = "[↑↓]scroll [q]quit"
    ix = main.x + 1
    if fy >= main.y
        set_string!(buf, ix, fy, inst, tstyle(:text_dim, dim=true))
    end
end

function dashboard(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(DashboardModel(); fps=30)
end
