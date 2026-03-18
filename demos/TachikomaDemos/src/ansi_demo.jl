# ═══════════════════════════════════════════════════════════════════════
# ANSI Text Demo ── showcase parse_ansi, Paragraph, and ScrollPane
#                   with ANSI escape sequences and per-widget override
#
# Layout:
#   Top-left:     Paragraph with parsed ANSI (colors, styles)
#   Top-right:    Same text with ansi=false (raw, escapes stripped)
#   Bottom-left:  ScrollPane with ANSI log lines (auto-follow)
#   Bottom-right: ScrollPane with ansi=false (same lines, plain)
#
# [tab] cycle focus   [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

const ANSI_SAMPLE = string(
    "\e[1;38;2;100;200;255m╔══ ANSI Escape Sequences ══╗\e[0m\n",
    "\n",
    "\e[1mBold\e[0m  \e[2mDim\e[0m  \e[3mItalic\e[0m  \e[4mUnderline\e[0m  \e[9mStrike\e[0m\n",
    "\n",
    "\e[31m● Red\e[0m  \e[32m● Green\e[0m  \e[33m● Yellow\e[0m  \e[34m● Blue\e[0m\n",
    "\e[35m● Magenta\e[0m  \e[36m● Cyan\e[0m  \e[37m● White\e[0m\n",
    "\n",
    "\e[91m● Bright Red\e[0m  \e[92m● Bright Green\e[0m  \e[93m● Bright Yellow\e[0m\n",
    "\e[94m● Bright Blue\e[0m  \e[95m● Bright Magenta\e[0m  \e[96m● Bright Cyan\e[0m\n",
    "\n",
    "\e[38;5;208m● 256-color (208)\e[0m  \e[38;5;99m● 256-color (99)\e[0m\n",
    "\e[38;2;255;100;50m● RGB (255,100,50)\e[0m  \e[38;2;50;200;150m● RGB (50,200,150)\e[0m\n",
    "\n",
    "\e[1;3;31mBold Italic Red\e[0m  \e[4;38;5;75mUnderline 256-Blue\e[0m\n",
    "\e[1;38;2;100;200;255m╚══════════════════════════╝\e[0m",
)

const ANSI_LOG_COLORS = [
    "\e[32m",   # green
    "\e[33m",   # yellow
    "\e[31m",   # red
    "\e[36m",   # cyan
    "\e[35m",   # magenta
    "\e[38;5;208m",  # orange 256
    "\e[38;2;100;200;255m",  # light blue RGB
]

const ANSI_LOG_LEVELS = ["INFO", "WARN", "ERROR", "DEBUG", "TRACE"]

const ANSI_LOG_MESSAGES = [
    "Connection established on port 8080",
    "Cache miss for key user:42",
    "Request failed: timeout after 30s",
    "Worker thread pool scaled to 8",
    "Heartbeat from node-3 received",
    "GC pause: 4.2ms (gen1 collection)",
    "TLS handshake completed successfully",
    "Rate limit reset for 10.0.0.5",
    "Schema migration applied: v42→v43",
    "Circuit breaker tripped for payment-svc",
]

function _make_ansi_log_line(tick::Int)
    level = ANSI_LOG_LEVELS[mod1(tick, length(ANSI_LOG_LEVELS))]
    color = ANSI_LOG_COLORS[mod1(tick, length(ANSI_LOG_COLORS))]
    msg = ANSI_LOG_MESSAGES[mod1(tick, length(ANSI_LOG_MESSAGES))]
    ts = lpad(tick, 4, '0')
    "$(color)[$ts]\e[0m \e[1m$level\e[0m $msg"
end

@kwdef mutable struct AnsiDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    focus::Int = 1   # 1-4 for the four panes

    # Top-left: Paragraph with ANSI parsed (default)
    para_on::Paragraph = Paragraph(ANSI_SAMPLE;
        wrap=char_wrap,
        block=Block(title="Paragraph (ansi=true)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Top-right: Paragraph with ANSI disabled
    para_off::Paragraph = Paragraph(ANSI_SAMPLE;
        ansi=false,
        wrap=char_wrap,
        block=Block(title="Paragraph (ansi=false)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Bottom-left: ScrollPane with ANSI (default for String content)
    log_lines::Vector{String} = String[]
    scroll_on::ScrollPane = ScrollPane(String[];
        block=Block(title="ScrollPane (ansi=true)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))

    # Bottom-right: ScrollPane with ANSI disabled
    scroll_off::ScrollPane = ScrollPane(String[];
        ansi=false,
        block=Block(title="ScrollPane (ansi=false)",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)))
end

should_quit(m::AnsiDemoModel) = m.quit

function _ansi_pane_for_focus(m::AnsiDemoModel)
    m.focus == 1 && return m.para_on
    m.focus == 2 && return m.para_off
    m.focus == 3 && return m.scroll_on
    return m.scroll_off
end

function update!(m::AnsiDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true; return)
    end
    evt.key == :escape && (m.quit = true; return)
    evt.key == :tab && (m.focus = mod1(m.focus + 1, 4); return)
    evt.key == :backtab && (m.focus = mod1(m.focus - 1, 4); return)

    focused = _ansi_pane_for_focus(m)
    if applicable(handle_key!, focused, evt)
        handle_key!(focused, evt)
    end
end

function update!(m::AnsiDemoModel, evt::MouseEvent)
    for pane in (m.scroll_on, m.scroll_off)
        handle_mouse!(pane, evt) && return
    end
    for pane in (m.para_on, m.para_off)
        handle_mouse!(pane, evt) && return
    end
end

function view(m::AnsiDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Auto-generate log lines every 3 ticks
    if m.tick % 3 == 0
        line = _make_ansi_log_line(m.tick)
        push!(m.log_lines, line)
    end

    # Update block titles with focus indicator
    focus_marker(idx) = m.focus == idx ? "● " : "○ "
    focus_border(idx) = m.focus == idx ? tstyle(:accent) : tstyle(:border)
    focus_title(idx) = m.focus == idx ? tstyle(:accent, bold=true) : tstyle(:title)

    m.para_on.block = Block(
        title="$(focus_marker(1))Paragraph (ansi=true)",
        border_style=focus_border(1), title_style=focus_title(1))
    m.para_off.block = Block(
        title="$(focus_marker(2))Paragraph (ansi=false)",
        border_style=focus_border(2), title_style=focus_title(2))
    m.scroll_on.block = Block(
        title="$(focus_marker(3))ScrollPane (ansi=true)",
        border_style=focus_border(3), title_style=focus_title(3))
    m.scroll_off.block = Block(
        title="$(focus_marker(4))ScrollPane (ansi=false)",
        border_style=focus_border(4), title_style=focus_title(4))

    # Layout: 2x2 grid with footer
    rows = split_layout(Layout(Vertical, [Fill(1), Fill(1), Fixed(1)]), f.area)
    length(rows) < 3 && return
    top_cols = split_layout(Layout(Horizontal, [Fill(1), Fill(1)]), rows[1])
    bot_cols = split_layout(Layout(Horizontal, [Fill(1), Fill(1)]), rows[2])

    render(m.para_on, top_cols[1], buf)
    render(m.para_off, top_cols[2], buf)
    render(m.scroll_on, bot_cols[1], buf)
    render(m.scroll_off, bot_cols[2], buf)

    # Footer
    render(StatusBar(
        left=[Span("  [Tab]focus [↑↓/PgUp/PgDn]scroll ", tstyle(:text_dim))],
        right=[Span("$(length(m.log_lines)) lines  [q/Esc]quit ", tstyle(:text_dim))],
    ), rows[3], buf)
end

function ansi_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    model = AnsiDemoModel()

    # Seed some initial log lines
    for i in 1:8
        push!(model.log_lines, _make_ansi_log_line(i))
    end
    model.scroll_on.content = model.log_lines
    model.scroll_off.content = model.log_lines
    model.tick = 0

    app(model; fps=30)
end
