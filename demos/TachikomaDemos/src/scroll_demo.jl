# ═══════════════════════════════════════════════════════════════════════
# Scroll Demo ── 2D pannable widget canvas
#
# A massive virtual space filled with widgets, viewed through a
# scrollable viewport. Click-drag to pan, scroll wheel to move,
# arrow keys for fine control, Home to reset.
#
# [←→↑↓] scroll  [drag] pan  [scroll] vertical  [Home] reset  [q] quit
# ═══════════════════════════════════════════════════════════════════════

mutable struct ScrollCanvas
    tick::Int
    spark_data::Vector{Vector{Float64}}
end

function ScrollCanvas()
    sparks = [Float64[0.5 + 0.3 * sin(i * 0.1 + j * 0.5) for j in 1:60] for i in 1:24]
    ScrollCanvas(0, sparks)
end

const _SCROLL_SERVICES = [
    ["api-gateway",   "● UP",   "14d 3h",  "1.2M",  "12ms",  "us-east-1"],
    ["auth-service",  "● UP",   "14d 3h",  "890K",  "8ms",   "us-east-1"],
    ["db-primary",    "● UP",   "30d 1h",  "2.1M",  "3ms",   "us-east-1"],
    ["db-replica",    "● UP",   "30d 1h",  "1.8M",  "4ms",   "eu-west-1"],
    ["cache-redis",   "● UP",   "7d 12h",  "5.4M",  "1ms",   "us-east-1"],
    ["queue-worker",  "● WARN", "2d 8h",   "340K",  "45ms",  "us-east-1"],
    ["cdn-edge",      "● UP",   "60d",     "12.3M", "2ms",   "global"],
    ["log-collector", "● UP",   "14d 3h",  "3.1M",  "6ms",   "us-east-1"],
    ["metrics-agg",   "● DOWN", "0h 5m",   "0",     "---",   "us-east-1"],
    ["scheduler",     "● UP",   "14d 3h",  "120K",  "15ms",  "us-east-1"],
    ["ml-inference",  "● UP",   "5d 2h",   "45K",   "120ms", "us-west-2"],
    ["ml-training",   "● WARN", "1d 8h",   "12K",   "800ms", "us-west-2"],
    ["billing-svc",   "● UP",   "14d 3h",  "230K",  "22ms",  "us-east-1"],
    ["notify-push",   "● UP",   "14d 3h",  "1.5M",  "5ms",   "us-east-1"],
    ["search-index",  "● UP",   "7d 0h",   "890K",  "35ms",  "eu-west-1"],
    ["file-storage",  "● UP",   "30d 0h",  "2.8M",  "18ms",  "us-east-1"],
]

const _SCROLL_DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

function Tachikoma.render(sc::ScrollCanvas, rect::Rect, buf::Buffer)
    sc.tick += 1
    t = sc.tick

    # Update spark data
    for (i, data) in enumerate(sc.spark_data)
        push!(data, clamp(data[end] + (sin(t * 0.03 + i) * 0.1) + (rand() - 0.5) * 0.08, 0.0, 1.0))
        length(data) > 60 && popfirst!(data)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 0: Title banner (full width)
    # ═══════════════════════════════════════════════════════════════
    bw = min(rect.width, 200)
    render(Block(title="Widget Scroll Demo — $(rect.width)×$(rect.height) virtual cells",
                 border_style=tstyle(:accent),
                 title_style=tstyle(:accent, bold=true)),
           Rect(rect.x, rect.y, bw, 3), buf)
    set_string!(buf, rect.x + 2, rect.y + 1,
                "Click-drag to pan around. This space is much larger than your terminal.",
                tstyle(:text_dim))

    # ═══════════════════════════════════════════════════════════════
    # ROW 1 (y+4): 6 sparklines across
    # ═══════════════════════════════════════════════════════════════
    y = rect.y + 4
    spark_w = 32
    labels1 = ["CPU Core 0", "CPU Core 1", "CPU Core 2", "CPU Core 3", "Memory", "Swap"]
    colors1 = [:primary, :primary, :primary, :primary, :accent, :warning]
    for (i, (label, color)) in enumerate(zip(labels1, colors1))
        x = rect.x + (i - 1) * (spark_w + 1)
        pct = round(Int, sc.spark_data[i][end] * 100)
        render(Sparkline(sc.spark_data[i];
            block=Block(title="$label ($pct%)", border_style=tstyle(:border)),
            style=tstyle(color)), Rect(x, y, spark_w, 5), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 2 (y+10): Bar charts + Gauges side by side
    # ═══════════════════════════════════════════════════════════════
    y += 7

    # Bar chart 1: weekly traffic
    bars1 = [BarEntry(d, 10 + round(Int, 15 * sin(t * 0.04 + i * 0.9)))
             for (i, d) in enumerate(_SCROLL_DAYS)]
    render(BarChart(bars1;
        block=Block(title="Weekly Requests", border_style=tstyle(:border)),
        value_style=tstyle(:accent)),
        Rect(rect.x, y, 45, 12), buf)

    # Bar chart 2: regional load
    bars2 = [BarEntry("US-E", 35 + round(Int, 10 * sin(t * 0.03))),
             BarEntry("US-W", 20 + round(Int, 8 * cos(t * 0.04))),
             BarEntry("EU-W", 25 + round(Int, 7 * sin(t * 0.05))),
             BarEntry("AP-SE", 15 + round(Int, 5 * cos(t * 0.06))),
             BarEntry("SA-E", 8 + round(Int, 4 * sin(t * 0.07)))]
    render(BarChart(bars2;
        block=Block(title="Regional Load", border_style=tstyle(:border)),
        value_style=tstyle(:primary)),
        Rect(rect.x + 48, y, 45, 12), buf)

    # Gauges column
    gx = rect.x + 96
    gauge_items = [
        ("Disk /",       0.72 + 0.05 * sin(t * 0.02)),
        ("Disk /data",   0.58 + 0.08 * cos(t * 0.03)),
        ("Battery",      0.45 + 0.10 * cos(t * 0.03)),
        ("Upload BW",    0.30 + 0.20 * sin(t * 0.05)),
        ("Download BW",  0.65 + 0.15 * cos(t * 0.04)),
        ("Cache Hit",    0.88 + 0.05 * cos(t * 0.04)),
        ("CDN Offload",  0.92 + 0.03 * sin(t * 0.02)),
        ("Queue Depth",  0.15 + 0.10 * sin(t * 0.06)),
    ]
    for (j, (label, val)) in enumerate(gauge_items)
        gy = y + (j - 1) * 3
        j > 4 && (gy -= 12; gx == rect.x + 96 && (gx = rect.x + 140))
        render(Gauge(clamp(val, 0, 1);
            label=label,
            block=Block(border_style=tstyle(:border)),
            filled_style=tstyle(val > 0.8 ? :warning : :primary)),
            Rect(gx, gy, 42, 3), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 3 (y+14): Service health table (wide)
    # ═══════════════════════════════════════════════════════════════
    y += 14
    headers = ["Service", "Status", "Uptime", "Requests/day", "P99 Latency", "Region"]
    render(Table(headers, _SCROLL_SERVICES;
        block=Block(title="Service Health Dashboard ($(length(_SCROLL_SERVICES)) services)",
                    border_style=tstyle(:border)),
        header_style=tstyle(:title, bold=true)),
        Rect(rect.x, y, 90, length(_SCROLL_SERVICES) + 4), buf)

    # Calendars to the right
    for (ci, (yr, mo, title)) in enumerate([
        (2026, 3, "March 2026"), (2026, 4, "April 2026"), (2026, 5, "May 2026")])
        cx = rect.x + 95 + (ci - 1) * 26
        render(Calendar(yr, mo;
            block=Block(title=title, border_style=tstyle(:border))),
            Rect(cx, y, 24, 10), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 4: Another row of 6 sparklines (network metrics)
    # ═══════════════════════════════════════════════════════════════
    y += length(_SCROLL_SERVICES) + 6
    labels2 = ["TCP In", "TCP Out", "UDP In", "UDP Out", "HTTP 2xx", "HTTP 5xx"]
    colors2 = [:primary, :accent, :primary, :accent, :success, :error]
    for (i, (label, color)) in enumerate(zip(labels2, colors2))
        x = rect.x + (i - 1) * (spark_w + 1)
        idx = 6 + i
        pct = round(Int, sc.spark_data[idx][end] * 100)
        render(Sparkline(sc.spark_data[idx];
            block=Block(title="$label ($pct%)", border_style=tstyle(:border)),
            style=tstyle(color)), Rect(x, y, spark_w, 5), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 5: More bar charts
    # ═══════════════════════════════════════════════════════════════
    y += 7
    for (bi, (title, offset)) in enumerate([
        ("Latency Distribution", 0.0),
        ("Error Breakdown", 2.0),
        ("Throughput by Endpoint", 4.0),
        ("Response Codes", 6.0)])
        bx = rect.x + (bi - 1) * 48
        entries = [BarEntry("B$j", 5 + round(Int, 20 * sin(t * 0.03 + j + offset)))
                   for j in 1:7]
        render(BarChart(entries;
            block=Block(title=title, border_style=tstyle(:border)),
            value_style=tstyle(bi <= 2 ? :primary : :accent)),
            Rect(bx, y, 46, 12), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 6: Yet more sparklines (storage metrics)
    # ═══════════════════════════════════════════════════════════════
    y += 14
    labels3 = ["IOPS Read", "IOPS Write", "Throughput MB/s", "Queue Depth",
               "Latency µs", "Utilization"]
    for (i, label) in enumerate(labels3)
        x = rect.x + (i - 1) * (spark_w + 1)
        idx = 12 + i
        idx > length(sc.spark_data) && continue
        pct = round(Int, sc.spark_data[idx][end] * 100)
        render(Sparkline(sc.spark_data[idx];
            block=Block(title="$label ($pct%)", border_style=tstyle(:border)),
            style=tstyle(i <= 3 ? :primary : :accent)),
            Rect(x, y, spark_w, 5), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 7: Second service table + more gauges
    # ═══════════════════════════════════════════════════════════════
    y += 7
    headers2 = ["Endpoint", "Method", "Calls/min", "Avg ms", "P95 ms", "Errors"]
    endpoints = [
        ["/api/v2/users",     "GET",    "12.4K", "8",   "25",  "0.01%"],
        ["/api/v2/users",     "POST",   "3.2K",  "15",  "45",  "0.05%"],
        ["/api/v2/orders",    "GET",    "8.7K",  "12",  "38",  "0.02%"],
        ["/api/v2/orders",    "POST",   "1.1K",  "22",  "65",  "0.08%"],
        ["/api/v2/products",  "GET",    "15.3K", "5",   "18",  "0.00%"],
        ["/api/v2/search",    "POST",   "6.8K",  "35",  "120", "0.12%"],
        ["/api/v2/auth",      "POST",   "4.5K",  "18",  "55",  "0.03%"],
        ["/api/v2/upload",    "PUT",    "890",   "120", "450", "0.15%"],
        ["/api/v2/webhooks",  "POST",   "2.3K",  "8",   "22",  "0.01%"],
        ["/api/v2/analytics", "GET",    "950",   "85",  "280", "0.04%"],
        ["/health",           "GET",    "60K",   "1",   "3",   "0.00%"],
        ["/metrics",          "GET",    "1.2K",  "2",   "8",   "0.00%"],
    ]
    render(Table(headers2, endpoints;
        block=Block(title="Endpoint Performance ($(length(endpoints)) endpoints)",
                    border_style=tstyle(:border)),
        header_style=tstyle(:title, bold=true)),
        Rect(rect.x, y, 85, length(endpoints) + 4), buf)

    # More gauges to the right
    gx2 = rect.x + 90
    gauge_items2 = [
        ("Redis Mem",     0.62 + 0.08 * sin(t * 0.03)),
        ("Postgres Conn", 0.35 + 0.15 * cos(t * 0.04)),
        ("Worker Pool",   0.78 + 0.10 * sin(t * 0.05)),
        ("Rate Limit",    0.12 + 0.08 * cos(t * 0.06)),
        ("SSL Certs",     0.95 + 0.02 * sin(t * 0.01)),
        ("DNS Cache",     0.88 + 0.05 * cos(t * 0.03)),
    ]
    for (j, (label, val)) in enumerate(gauge_items2)
        gy = y + (j - 1) * 3
        render(Gauge(clamp(val, 0, 1);
            label=label,
            block=Block(border_style=tstyle(:border)),
            filled_style=tstyle(val > 0.8 ? :warning : :primary)),
            Rect(gx2, gy, 42, 3), buf)
    end

    # ═══════════════════════════════════════════════════════════════
    # ROW 8: Final row of sparklines + footer
    # ═══════════════════════════════════════════════════════════════
    y += length(endpoints) + 6
    labels4 = ["GC Pause ms", "Alloc Rate", "Thread Count", "Goroutines",
               "Open Files", "TCP Connections"]
    for (i, label) in enumerate(labels4)
        x = rect.x + (i - 1) * (spark_w + 1)
        idx = 18 + i
        idx > length(sc.spark_data) && continue
        pct = round(Int, sc.spark_data[idx][end] * 100)
        render(Sparkline(sc.spark_data[idx];
            block=Block(title="$label ($pct%)", border_style=tstyle(:border)),
            style=tstyle(i <= 3 ? :primary : :accent)),
            Rect(x, y, spark_w, 5), buf)
    end

    # Footer
    y += 7
    set_string!(buf, rect.x + 2, y,
                "End of virtual space — $(rect.width)×$(rect.height) cells, ~10 screens of content.",
                tstyle(:success, bold=true))
    set_string!(buf, rect.x + 2, y + 1,
                "Press [Home] to return to the top.",
                tstyle(:text_dim))
end

# ── Demo model ───────────────────────────────────────────────────────

@kwdef mutable struct ScrollDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    scroll::WidgetScroll = WidgetScroll(ScrollCanvas();
        virtual_width=200, virtual_height=120,
        block=Block(title="Viewport — drag to pan, scroll wheel, arrow keys, Home to reset",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        show_vertical_scrollbar=true)
end

should_quit(m::ScrollDemoModel) = m.quit

function update!(m::ScrollDemoModel, evt::KeyEvent)
    (evt.key == :escape || (evt.key == :char && evt.char == 'q')) && (m.quit = true; return)
    handle_key!(m.scroll, evt)
end

function update!(m::ScrollDemoModel, evt::MouseEvent)
    handle_mouse!(m.scroll, evt)
end

function view(m::ScrollDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    rows = split_layout(Layout(Vertical, [Fill(1), Fixed(1)]), area)
    length(rows) < 2 && return

    m.scroll.widget.tick = m.tick
    render(m.scroll, rows[1], buf)

    ox, oy = value(m.scroll)
    drag_indicator = m.scroll.dragging ? " [dragging]" : ""
    render(StatusBar(
        left=[Span("  offset: ($ox,$oy) virtual: 200×120$drag_indicator  [←→↑↓]scroll [drag]pan [Home]reset ", tstyle(:text_dim))],
        right=[Span("[q]quit ", tstyle(:text_dim))],
    ), rows[2], buf)
end

scroll_demo() = app(ScrollDemoModel(); fps=30)
