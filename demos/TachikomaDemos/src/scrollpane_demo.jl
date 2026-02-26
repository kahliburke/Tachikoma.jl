# ═══════════════════════════════════════════════════════════════════════
# ScrollPane Demo ── live log viewer with auto-follow, reverse mode,
#                    styled lines, and keyboard/mouse scrolling
#
# Left pane:   live log with auto-follow (new lines appear at bottom)
# Right-top:   reverse-mode log (newest at top, scrollable)
# Right-bottom: styled span log with mixed colors
#
# [space] toggle pause  [f] toggle follow  [r] toggle reverse
# [tab] switch focus    [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

const LOG_PREFIXES = [
    "INFO", "WARN", "DEBUG", "ERROR", "TRACE",
]

const LOG_MESSAGES = [
    "Connection established on port 8080",
    "Request processed in 12ms",
    "Cache miss for key user:session:42",
    "Retrying failed operation (attempt 2/3)",
    "Worker pool scaled to 8 threads",
    "Heartbeat received from node-3",
    "GC pause: 4.2ms (gen1)",
    "TLS handshake completed",
    "Query plan optimized: 3 joins eliminated",
    "Rate limit reset for client 10.0.0.5",
    "Snapshot saved (2.1 MB compressed)",
    "Schema migration applied: v42→v43",
    "WebSocket upgrade accepted",
    "Background job enqueued: email_digest",
    "Metric flush: 1,247 points in 0.8ms",
    "Circuit breaker tripped for payment-svc",
    "DNS resolution: api.example.com → 192.168.1.10",
    "Session expired for user admin@corp.io",
    "Compaction completed: 340 MB reclaimed",
    "Health check passed (all 5 probes OK)",
]

@kwdef mutable struct ScrollPaneDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    focus::Int = 1          # 1=left, 2=right-top, 3=right-bottom

    # Left pane: plain string auto-follow log
    log_lines::Vector{String} = String[]
    log_pane::ScrollPane = ScrollPane(String[];
        block=Block(title="Live Log (auto-follow)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Right-top: reverse mode log
    reverse_lines::Vector{String} = String[]
    reverse_pane::ScrollPane = ScrollPane(String[];
        reverse=true,
        block=Block(title="Reverse Log (newest first)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Right-bottom: styled spans
    styled_lines::Vector{Vector{Span}} = Vector{Span}[]
    styled_pane::ScrollPane = ScrollPane(Vector{Span}[];
        block=Block(title="Styled Log",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))
end

should_quit(m::ScrollPaneDemoModel) = m.quit

function _log_style(prefix::String)
    prefix == "ERROR" && return Style(fg=ColorRGB(0xff, 0x55, 0x55), bold=true)
    prefix == "WARN"  && return Style(fg=ColorRGB(0xff, 0xcc, 0x00))
    prefix == "DEBUG" && return Style(fg=ColorRGB(0x88, 0x88, 0xaa))
    prefix == "TRACE" && return Style(fg=ColorRGB(0x66, 0x66, 0x77))
    return tstyle(:text)  # INFO
end

function _generate_log_line(tick::Int)
    prefix = LOG_PREFIXES[mod1(tick * 7 + tick ÷ 3, length(LOG_PREFIXES))]
    msg = LOG_MESSAGES[mod1(tick * 13 + tick ÷ 5, length(LOG_MESSAGES))]
    ts = lpad(tick, 6, '0')
    return prefix, "[$ts] $prefix  $msg"
end

function _pane_for_focus(m::ScrollPaneDemoModel)
    m.focus == 1 && return m.log_pane
    m.focus == 2 && return m.reverse_pane
    return m.styled_pane
end

function update!(m::ScrollPaneDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true; return)
        evt.char == ' ' && (m.paused = !m.paused; return)
        evt.char == 'f' && begin
            pane = _pane_for_focus(m)
            pane.following = !pane.following
            return
        end
    end
    evt.key == :escape && (m.quit = true; return)
    evt.key == :tab && (m.focus = mod1(m.focus + 1, 3); return)
    evt.key == :backtab && (m.focus = mod1(m.focus - 1, 3); return)

    # Delegate to focused pane
    handle_key!(_pane_for_focus(m), evt)
end

function update!(m::ScrollPaneDemoModel, evt::MouseEvent)
    # Try each pane for mouse events
    handle_mouse!(m.log_pane, evt) && return
    handle_mouse!(m.reverse_pane, evt) && return
    handle_mouse!(m.styled_pane, evt) && return
end

function view(m::ScrollPaneDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()

    # Generate log lines periodically (every 3 ticks ≈ 10/sec at 30fps)
    if !m.paused && m.tick % 3 == 0
        prefix, line = _generate_log_line(m.tick)

        # Plain log
        push_line!(m.log_pane, line)
        # Reverse log
        push_line!(m.reverse_pane, line)
        # Styled log — prefix colored, message default
        styled = [
            Span("[$(lpad(m.tick, 6, '0'))] ", tstyle(:text_dim)),
            Span(rpad(prefix, 6), _log_style(prefix)),
            Span(LOG_MESSAGES[mod1(m.tick * 13 + m.tick ÷ 5, length(LOG_MESSAGES))],
                 tstyle(:text)),
        ]
        push_line!(m.styled_pane, styled)
    end

    # Layout: left | right (top / bottom)
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), f.area)
    length(rows) < 2 && return
    main_area = rows[1]
    footer_area = rows[2]

    cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), main_area)
    length(cols) < 2 && return
    left_area = cols[1]
    right_area = cols[2]

    right_rows = split_layout(Layout(Vertical, [Percent(50), Fill()]), right_area)
    length(right_rows) < 2 && return
    rtop_area = right_rows[1]
    rbot_area = right_rows[2]

    # Update block titles with focus indicator
    focus_marker(idx) = m.focus == idx ? "● " : "○ "
    m.log_pane.block = Block(
        title="$(focus_marker(1))Live Log (follow=$(m.log_pane.following))",
        border_style=m.focus == 1 ? tstyle(:accent) : tstyle(:border),
        title_style=m.focus == 1 ? tstyle(:accent, bold=true) : tstyle(:title))
    m.reverse_pane.block = Block(
        title="$(focus_marker(2))Reverse Log",
        border_style=m.focus == 2 ? tstyle(:accent) : tstyle(:border),
        title_style=m.focus == 2 ? tstyle(:accent, bold=true) : tstyle(:title))
    m.styled_pane.block = Block(
        title="$(focus_marker(3))Styled Log",
        border_style=m.focus == 3 ? tstyle(:accent) : tstyle(:border),
        title_style=m.focus == 3 ? tstyle(:accent, bold=true) : tstyle(:title))

    # Render panes
    render(m.log_pane, left_area, buf)
    render(m.reverse_pane, rtop_area, buf)
    render(m.styled_pane, rbot_area, buf)

    # Footer
    n_lines = length(m.log_pane.content::Vector{String})
    status = m.paused ? "PAUSED" : "STREAMING"
    render(StatusBar(
        left=[Span("  [Tab]focus [↑↓/PgUp/PgDn]scroll [Space]$(status) [f]follow ",
                    tstyle(:text_dim))],
        right=[Span("$(n_lines) lines  [q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function scrollpane_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    model = ScrollPaneDemoModel()
    app(model; fps=30)
end
