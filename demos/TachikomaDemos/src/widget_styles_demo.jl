# ═══════════════════════════════════════════════════════════════════════
# Widget Styles Demo ── showcases different decoration styles for
#                       TabBar and Button widgets
#
# Demonstrates BracketTabs, BoxTabs, PlainTabs, BracketButton,
# BorderedButton, and PlainButton with various box styles.
#
# [←→] switch top tabs  [1-3] switch style tabs  [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct WidgetStylesModel <: Model
    quit::Bool = false
    tick::Int = 0

    # Top-level tabs cycle through tab styles
    style_idx::Int = 1  # 1=bracket, 2=box, 3=plain

    # Per-style demo tabs
    bracket_tabs::TabBar = TabBar(["Overview", "Details", "Settings", "Help"];
        active=1, focused=true, tab_style=TabBarStyle(decoration=BracketTabs()))
    box_tabs::TabBar = TabBar(["Overview", "Details", "Settings", "Help"];
        active=1, focused=true, tab_style=TabBarStyle(decoration=BoxTabs()))
    box_heavy_tabs::TabBar = TabBar(["Server", "Database", "Network"];
        active=1, tab_style=TabBarStyle(decoration=BoxTabs(box=BOX_HEAVY)))
    plain_tabs::TabBar = TabBar(["Home", "Search", "Profile", "Settings"];
        active=1, focused=true, tab_style=TabBarStyle(decoration=PlainTabs(), separator=" · "))

    # Buttons
    btn_bracket::Button = Button("Submit"; button_style=ButtonStyle())
    btn_bordered::Button = Button("Submit"; button_style=ButtonStyle(decoration=BorderedButton()))
    btn_heavy::Button = Button("Cancel"; button_style=ButtonStyle(decoration=BorderedButton(box=BOX_HEAVY)))
    btn_plain::Button = Button("Skip"; button_style=ButtonStyle(decoration=PlainButton()))
    btn_focus::Int = 1
end

should_quit(m::WidgetStylesModel) = m.quit

function update!(m::WidgetStylesModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    # Number keys switch style section
    if evt.key == :char && evt.char in ('1', '2', '3')
        m.style_idx = Int(evt.char) - Int('0')
        return
    end

    # Forward keys to the active tab bar
    tabs = _active_tabs(m)
    if tabs !== nothing
        handle_key!(tabs, evt)
    end

    # Tab to cycle button focus
    if evt.key == :down
        m.btn_focus = mod1(m.btn_focus + 1, 4)
    elseif evt.key == :up
        m.btn_focus = mod1(m.btn_focus - 1, 4)
    end
end

function _active_tabs(m::WidgetStylesModel)
    if m.style_idx == 1
        m.bracket_tabs
    elseif m.style_idx == 2
        m.box_tabs
    else
        m.plain_tabs
    end
end

function view(m::WidgetStylesModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Update button focus
    for (i, btn) in enumerate((m.btn_bracket, m.btn_bordered, m.btn_heavy, m.btn_plain))
        btn.focused = (i == m.btn_focus)
        btn.tick = m.tick
    end

    # Layout: header | tabs section | buttons section | footer
    rows = split_layout(Layout(Vertical, [
        Fixed(1), Fixed(1),  # title + gap
        Fixed(4),            # tab demos
        Fixed(1),            # gap
        Fixed(5),            # button demos
        Fill(),              # description
        Fixed(1),            # footer
    ]), f.area)
    length(rows) < 7 && return

    # Title
    set_string!(buf, rows[1].x + 1, rows[1].y,
                "Widget Styles Demo", tstyle(:title, bold=true))

    # Style selector (inline)
    styles_label = [
        m.style_idx == 1 ? "[1:Bracket]" : " 1:Bracket ",
        m.style_idx == 2 ? "[2:Box]" : " 2:Box ",
        m.style_idx == 3 ? "[3:Plain]" : " 3:Plain ",
    ]
    sx = rows[1].x + 22
    for (i, lbl) in enumerate(styles_label)
        sty = m.style_idx == i ? tstyle(:accent, bold=true) : tstyle(:text_dim)
        set_string!(buf, sx, rows[1].y, lbl, sty)
        sx += length(lbl) + 1
    end

    # Tab demos
    tab_area = rows[3]
    tab_cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), tab_area)
    length(tab_cols) >= 2 || return

    if m.style_idx == 1
        # Bracket tabs
        set_string!(buf, tab_cols[1].x, tab_cols[1].y, "BracketTabs:", tstyle(:text_dim))
        render(m.bracket_tabs, Rect(tab_cols[1].x, tab_cols[1].y + 1, tab_cols[1].width, 1), buf)
    elseif m.style_idx == 2
        # Box tabs (plain + heavy)
        set_string!(buf, tab_cols[1].x, tab_cols[1].y, "BoxTabs (plain):", tstyle(:text_dim))
        render(m.box_tabs, Rect(tab_cols[1].x, tab_cols[1].y + 1, tab_cols[1].width, 3), buf)
        if tab_cols[2].width > 10
            set_string!(buf, tab_cols[2].x, tab_cols[2].y, "BoxTabs (heavy):", tstyle(:text_dim))
            render(m.box_heavy_tabs, Rect(tab_cols[2].x, tab_cols[2].y + 1, tab_cols[2].width, 3), buf)
        end
    else
        # Plain tabs
        set_string!(buf, tab_cols[1].x, tab_cols[1].y, "PlainTabs:", tstyle(:text_dim))
        render(m.plain_tabs, Rect(tab_cols[1].x, tab_cols[1].y + 1, tab_cols[1].width, 1), buf)
    end

    # Button demos
    btn_area = rows[5]
    set_string!(buf, btn_area.x, btn_area.y, "Buttons:", tstyle(:text_dim))
    btn_row = Rect(btn_area.x, btn_area.y + 1, btn_area.width, btn_area.height - 1)
    btn_cols = split_layout(Layout(Horizontal, [
        Fixed(14), Fixed(14), Fixed(14), Fixed(14),
    ]), btn_row)
    length(btn_cols) >= 4 || return

    render(m.btn_bracket, btn_cols[1], buf)
    render(m.btn_bordered, Rect(btn_cols[2].x, btn_cols[2].y, btn_cols[2].width, 3), buf)
    render(m.btn_heavy, Rect(btn_cols[3].x, btn_cols[3].y, btn_cols[3].width, 3), buf)
    render(m.btn_plain, btn_cols[4], buf)

    # Labels under buttons
    label_y = btn_row.y + 3
    if label_y <= bottom(f.area) - 1
        for (i, lbl) in enumerate(["Bracket", "Bordered", "Heavy", "Plain"])
            i <= length(btn_cols) || break
            set_string!(buf, btn_cols[i].x + 1, label_y, lbl, tstyle(:text_dim))
        end
    end

    # Description
    desc_area = rows[6]
    if desc_area.height >= 2
        set_string!(buf, desc_area.x + 1, desc_area.y + 1,
            "Widget styles use type-parameterized dispatch: TabBarStyle{D<:TabDecoration}",
            tstyle(:text_dim))
        if desc_area.height >= 3
            set_string!(buf, desc_area.x + 1, desc_area.y + 2,
                "Define your own struct MyStyle <: TabDecoration and _render_tabs! method",
                tstyle(:text_dim))
        end
    end

    # Footer
    render(StatusBar(
        left=[Span("  [1-3]style [←→]tabs [↑↓]buttons [Space]press ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), rows[7], buf)
end

function widget_styles_demo()
    app(WidgetStylesModel(); fps=30)
end
