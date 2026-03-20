# ═══════════════════════════════════════════════════════════════════════
# TabBar Demo ── stateful tab bar with per-tab content panels
#
# Demonstrates TabBar with handle_key!, value(), and focused state.
# Each tab shows different content: overview with sparklines,
# a live log, and a settings panel with checkboxes.
#
# [←→/Tab] switch tabs  [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct TabBarDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    tabs::TabBar = TabBar(["Overview", "Activity", "Settings"]; active=1, focused=true)

    # Overview tab data
    cpu_data::Vector{Float64} = Float64[rand() * 0.3 + 0.1 for _ in 1:40]
    mem_data::Vector{Float64} = Float64[rand() * 0.2 + 0.4 for _ in 1:40]

    # Activity tab data
    log_lines::Vector{String} = String[]
    log_pane::ScrollPane = ScrollPane(String[];
        block=Block(title="Activity Log",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Settings tab data
    cb_notifications::Checkbox = Checkbox("Enable notifications"; checked=true)
    cb_autosave::Checkbox = Checkbox("Auto-save on exit"; checked=true)
    cb_animations::Checkbox = Checkbox("Smooth animations"; checked=false)
    settings_focus::Int = 1  # which checkbox is focused
end

should_quit(m::TabBarDemoModel) = m.quit

const _LOG_SOURCES = [
    "Server", "Database", "Cache", "Worker", "Scheduler", "Monitor",
]
const _LOG_ACTIONS = [
    "request processed", "connection opened", "query completed",
    "cache invalidated", "task dispatched", "heartbeat received",
    "checkpoint saved", "config reloaded", "metric flushed",
    "session renewed", "index rebuilt", "lock acquired",
]

function _random_log_line(tick::Int)
    src = _LOG_SOURCES[mod1(tick * 7 + 3, length(_LOG_SOURCES))]
    act = _LOG_ACTIONS[mod1(tick * 13 + 5, length(_LOG_ACTIONS))]
    ts = lpad(string(tick), 5, '0')
    "[$ts] $src: $act"
end

function update!(m::TabBarDemoModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    # TabBar consumes left/right/tab when focused
    if handle_key!(m.tabs, evt)
        return
    end

    # Per-tab key handling
    tab = value(m.tabs)
    if tab == 2
        handle_key!(m.log_pane, evt)
    elseif tab == 3
        if evt.key == :up
            m.settings_focus = mod1(m.settings_focus - 1, 3)
        elseif evt.key == :down
            m.settings_focus = mod1(m.settings_focus + 1, 3)
        else
            cb = (m.cb_notifications, m.cb_autosave, m.cb_animations)[m.settings_focus]
            cb.focused = true
            handle_key!(cb, evt)
        end
    end
end

function update!(m::TabBarDemoModel, evt::MouseEvent)
    handle_mouse!(m.tabs, evt)
end

function view(m::TabBarDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()

    # Add log entries periodically
    if mod(m.tick, 8) == 0
        line = _random_log_line(m.tick)
        push!(m.log_lines, line)
        # Keep last 200 lines
        length(m.log_lines) > 200 && popfirst!(m.log_lines)
        m.log_pane = ScrollPane(m.log_lines;
            block=Block(title="Activity Log ($(length(m.log_lines)) entries)",
                        border_style=tstyle(:border),
                        title_style=tstyle(:title)))
    end

    # Update sparkline data
    if mod(m.tick, 4) == 0
        push!(m.cpu_data, clamp(m.cpu_data[end] + (rand() - 0.48) * 0.15, 0.05, 0.95))
        push!(m.mem_data, clamp(m.mem_data[end] + (rand() - 0.5) * 0.05, 0.3, 0.8))
        length(m.cpu_data) > 60 && popfirst!(m.cpu_data)
        length(m.mem_data) > 60 && popfirst!(m.mem_data)
    end

    # Layout: tab bar | content | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    tab_area = rows[1]
    content_area = rows[2]
    footer_area = rows[3]

    # Render tab bar
    render(m.tabs, tab_area, buf)

    # Content by active tab
    tab = value(m.tabs)
    if tab == 1
        _view_overview(m, content_area, buf)
    elseif tab == 2
        render(m.log_pane, content_area, buf)
    elseif tab == 3
        _view_settings(m, content_area, buf)
    end

    # Footer
    render(StatusBar(
        left=[Span("  [←→/Tab]switch tabs ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function _view_overview(m::TabBarDemoModel, area::Rect, buf::Buffer)
    th = theme()
    block = Block(title="System Overview",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title))
    inner = render(block, area, buf)
    inner.height < 8 && return

    rows = split_layout(Layout(Vertical, [Fixed(4), Fixed(1), Fixed(4), Fill()]), inner)
    length(rows) < 3 && return

    # CPU sparkline
    cpu_pct = round(Int, m.cpu_data[end] * 100)
    render(Sparkline(m.cpu_data;
        block=Block(title="CPU ($cpu_pct%)", border_style=tstyle(:border)),
        style=tstyle(:primary),
    ), rows[1], buf)

    # Memory sparkline
    mem_pct = round(Int, m.mem_data[end] * 100)
    render(Sparkline(m.mem_data;
        block=Block(title="Memory ($mem_pct%)", border_style=tstyle(:border)),
        style=tstyle(:accent),
    ), rows[3], buf)

    # Summary text
    if length(rows) >= 4 && rows[4].height >= 1
        summary_y = rows[4].y
        uptime_secs = m.tick ÷ 30
        set_string!(buf, inner.x + 1, summary_y,
                    "Uptime: $(uptime_secs)s  │  Logs: $(length(m.log_lines))  │  Tabs: $(length(m.tabs.labels))",
                    tstyle(:text_dim))
    end
end

function _view_settings(m::TabBarDemoModel, area::Rect, buf::Buffer)
    block = Block(title="Settings",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title))
    inner = render(block, area, buf)
    inner.height < 6 && return

    cbs = (m.cb_notifications, m.cb_autosave, m.cb_animations)
    for (i, cb) in enumerate(cbs)
        cb.focused = (i == m.settings_focus)
    end

    y = inner.y
    for (i, cb) in enumerate(cbs)
        row_rect = Rect(inner.x, y, inner.width, 1)
        render(cb, row_rect, buf)
        y += 2
    end

    # Show current values
    y += 1
    if y <= bottom(inner)
        vals = join([
            "notifications=$(value(m.cb_notifications))",
            "autosave=$(value(m.cb_autosave))",
            "animations=$(value(m.cb_animations))",
        ], "  ")
        set_string!(buf, inner.x, y, vals, tstyle(:text_dim))
    end
end

function tabbar_demo()
    app(TabBarDemoModel(); fps=30)
end
