# ═══════════════════════════════════════════════════════════════════════
# TabBar Demo ── tab styles, overflow, per-tab colors, mouse support
#
# Demonstrates all TabBar decoration styles with live switching:
#   [d] cycle decoration: Bracket → Box (Rounded) → Box (Heavy) →
#       Box (Double) → Plain → ...
#   [c] toggle per-tab colors
#   [←→/Tab] switch tabs  [F2] focus overflow bar  [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

const _TABBAR_DEMO_COLORS = [
    Style(fg=ColorRGB(0x5b, 0x9b, 0xd5)),  # steel blue
    Style(fg=ColorRGB(0x6b, 0xb5, 0x8a)),  # sage green
    Style(fg=ColorRGB(0xd4, 0x9a, 0x6a)),  # warm amber
    Style(fg=ColorRGB(0x9b, 0x85, 0xc8)),  # soft purple
    Style(fg=ColorRGB(0x5e, 0xb8, 0xb8)),  # teal
    Style(fg=ColorRGB(0xc4, 0x7d, 0x7d)),  # muted rose
    Style(fg=ColorRGB(0xd1, 0x8e, 0x54)),  # burnt orange
    Style(fg=ColorRGB(0x7e, 0xa8, 0xd4)),  # sky blue
    Style(fg=ColorRGB(0x8b, 0xb0, 0x6e)),  # olive green
    Style(fg=ColorRGB(0xcc, 0x88, 0xaa)),  # dusty pink
    Style(fg=ColorRGB(0x88, 0xcc, 0x99)),  # mint
    Style(fg=ColorRGB(0xbb, 0x99, 0x55)),  # gold
]

const _DEMO_DECORATIONS = [
    ("Bracket", BracketTabs()),
    ("Box (Rounded)", BoxTabs(box=BOX_ROUNDED)),
    ("Box (Heavy)", BoxTabs(box=BOX_HEAVY)),
    ("Box (Double)", BoxTabs(box=BOX_DOUBLE)),
    ("Box (Plain)", BoxTabs(box=BOX_PLAIN)),
    ("Plain", PlainTabs()),
]

@kwdef mutable struct TabBarDemoModel <: Model
    quit::Bool = false
    tick::Int = 0

    # Main tabs
    tabs::TabBar = TabBar(["Overview", "Activity", "Settings"]; active=1, focused=true)

    # Overflow demo: many tabs
    many_tabs::TabBar = TabBar(
        ["Server", "Database", "Cache", "Network", "Auth", "Logs",
         "Metrics", "Config", "Deploy", "Monitor", "Alerts", "Storage"];
        active=1, focused=false)

    # Style cycling
    decoration_idx::Int = 2  # start with Box (Rounded)
    colors_enabled::Bool = true

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
    settings_focus::Int = 1
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

function _apply_tab_style!(m::TabBarDemoModel)
    _, dec = _DEMO_DECORATIONS[m.decoration_idx]
    colors = m.colors_enabled ? _TABBAR_DEMO_COLORS : Style[]
    style = TabBarStyle(decoration=dec, tab_colors=colors)
    # Recreate tab bars with new style (preserving active tab and focus)
    active1, focused1 = m.tabs.active, m.tabs.focused
    active2, focused2 = m.many_tabs.active, m.many_tabs.focused
    m.tabs = TabBar(m.tabs.labels; active=active1, focused=focused1, tab_style=style)
    m.many_tabs = TabBar(m.many_tabs.labels; active=active2, focused=focused2, tab_style=style)
end

function update!(m::TabBarDemoModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    # [d] cycle decoration style
    if evt.key == :char && evt.char == 'd'
        m.decoration_idx = mod1(m.decoration_idx + 1, length(_DEMO_DECORATIONS))
        _apply_tab_style!(m)
        return
    end

    # [c] toggle per-tab colors
    if evt.key == :char && evt.char == 'c'
        m.colors_enabled = !m.colors_enabled
        _apply_tab_style!(m)
        return
    end

    # [F2] toggle focus between tab bars
    if evt.key == :f2
        m.tabs.focused = !m.tabs.focused
        m.many_tabs.focused = !m.many_tabs.focused
        return
    end

    # TabBar key handling
    handle_key!(m.tabs, evt) && return
    handle_key!(m.many_tabs, evt) && return

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
    handle_mouse!(m.many_tabs, evt)
end

function view(m::TabBarDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Apply initial style on first frame
    if m.tick == 1
        _apply_tab_style!(m)
    end

    # Add log entries periodically
    if mod(m.tick, 8) == 0
        line = _random_log_line(m.tick)
        push!(m.log_lines, line)
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

    # Layout: overflow label+tabs | main tabs | content | footer
    dec = m.tabs.tab_style.decoration
    tab_h = tab_height(dec)
    rows = split_layout(Layout(Vertical,
        [Fixed(tab_h), Fixed(tab_h), Fill(), Fixed(1)]), f.area)
    length(rows) < 4 && return
    overflow_area = rows[1]
    tab_area = rows[2]
    content_area = rows[3]
    footer_area = rows[4]

    # Overflow tab bar (top) — shows many tabs with scrolling
    overflow_label = "Overflow ($(value(m.many_tabs))/$(length(m.many_tabs.labels)))"
    ov_style = m.many_tabs.focused ? tstyle(:accent) : tstyle(:text_dim)
    label_w = length(overflow_label) + 1
    set_string!(buf, overflow_area.x, overflow_area.y + (tab_h > 1 ? 1 : 0),
                overflow_label, ov_style)
    render(m.many_tabs, Rect(overflow_area.x + label_w, overflow_area.y,
                             overflow_area.width - label_w, tab_h), buf)

    # Main tab bar
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

    # Footer with style info
    dec_name, _ = _DEMO_DECORATIONS[m.decoration_idx]
    colors_str = m.colors_enabled ? "on" : "off"
    render(StatusBar(
        left=[Span("  [d]ecoration: $dec_name  [c]olors: $colors_str  [F2]focus  [←→]tabs ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function _view_overview(m::TabBarDemoModel, area::Rect, buf::Buffer)
    block = Block(title="System Overview",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title))
    inner = render(block, area, buf)
    inner.height < 8 && return

    rows = split_layout(Layout(Vertical, [Fixed(4), Fixed(1), Fixed(4), Fill()]), inner)
    length(rows) < 3 && return

    cpu_pct = round(Int, m.cpu_data[end] * 100)
    render(Sparkline(m.cpu_data;
        block=Block(title="CPU ($cpu_pct%)", border_style=tstyle(:border)),
        style=tstyle(:primary),
    ), rows[1], buf)

    mem_pct = round(Int, m.mem_data[end] * 100)
    render(Sparkline(m.mem_data;
        block=Block(title="Memory ($mem_pct%)", border_style=tstyle(:border)),
        style=tstyle(:accent),
    ), rows[3], buf)

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

function tabbar_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(TabBarDemoModel(); fps=30)
end
