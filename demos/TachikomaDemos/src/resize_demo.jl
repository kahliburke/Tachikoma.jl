# ═══════════════════════════════════════════════════════════════════════
# Resize Demo ── drag pane borders to resize + click-to-select list
#
# Three-pane layout with horizontal + vertical splits:
#   Top-left (Fixed)  │  Top-right (Fill)
#   ──────────────────┼──────────────────
#   Bottom (Fixed) — instructions + status
#
# Drag borders to resize. [r] resets, [q] quits.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct ResizeDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Outer layout: top row + bottom pane (vertical split)
    vlayout::ResizableLayout = ResizableLayout(Vertical, [Fill(), Fixed(8)])
    # Inner layout: left + right (horizontal split within top row)
    hlayout::ResizableLayout = ResizableLayout(Horizontal, [Fixed(30), Fill()])
    # List for click-to-select demo in pane 1
    list_items::Vector{String} = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon",
                                   "Zeta", "Eta", "Theta", "Iota", "Kappa"]
    list_selected::Int = 1
    list_offset::Int = 0
    list_area::Rect = Rect()
    list_visible_h::Int = 0
    drag_count::Int = 0
    # Pane rects for focus tracking (Ctrl+Y copy)
    pane_rects::Vector{Rect} = Rect[]
    focused_pane::Int = 1
end

should_quit(m::ResizeDemoModel) = m.quit

function update!(m::ResizeDemoModel, evt::KeyEvent)
    n = length(m.list_items)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'r' && begin
            reset_layout!(m.vlayout)
            reset_layout!(m.hlayout)
            m.drag_count = 0
        end
        evt.char == 'j' && (m.list_selected = min(m.list_selected + 1, n))
        evt.char == 'k' && (m.list_selected = max(m.list_selected - 1, 1))
    end
    evt.key == :escape && (m.quit = true)
    evt.key == :up && (m.list_selected = max(m.list_selected - 1, 1))
    evt.key == :down && (m.list_selected = min(m.list_selected + 1, n))
end

function update!(m::ResizeDemoModel, evt::MouseEvent)
    # Try resize on both layouts
    if handle_resize!(m.vlayout, evt)
        m.drag_count += 1
        return
    end
    if handle_resize!(m.hlayout, evt)
        m.drag_count += 1
        return
    end

    # Track which pane was clicked for focus
    if evt.action == mouse_press
        for (i, r) in enumerate(m.pane_rects)
            # Hit test uses a generous 1-cell border around the inner rect
            if evt.x >= r.x - 1 && evt.x <= right(r) + 1 &&
               evt.y >= r.y - 1 && evt.y <= bottom(r) + 1
                m.focused_pane = i
                break
            end
        end
    end

    # Click-to-select in list
    idx = list_hit(evt, m.list_area, m.list_offset, length(m.list_items))
    idx > 0 && (m.list_selected = idx)

    # Scroll
    m.list_offset = list_scroll(evt, m.list_offset, length(m.list_items),
                                m.list_visible_h)
end

function copy_rect(m::ResizeDemoModel)
    isempty(m.pane_rects) && return nothing
    m.pane_rects[clamp(m.focused_pane, 1, length(m.pane_rects))]
end

function _constraint_label(c)
    c isa Fixed   && return "Fixed($(c.size))"
    c isa Fill     && return "Fill($(c.weight))"
    c isa Percent  && return "Percent($(c.pct))"
    c isa Min      && return "Min($(c.size))"
    c isa Max      && return "Max($(c.size))"
    return "?"
end

function view(m::ResizeDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()

    # Outer vertical split: top area + bottom status pane
    vrows = split_layout(m.vlayout, f.area)
    length(vrows) < 2 && return
    top_area = vrows[1]
    bot_area = vrows[2]

    # Inner horizontal split in top area
    hcols = split_layout(m.hlayout, top_area)
    length(hcols) < 2 && return
    left_area = hcols[1]
    right_area = hcols[2]

    # ── Pane 1: list with click-to-select ──
    p1_border = m.focused_pane == 1 ? tstyle(:border_focus) : tstyle(:border)
    p1_block = Block(title="Pane 1: List (click to select)",
                     border_style=p1_border,
                     title_style=tstyle(:title))
    p1_inner = render(p1_block, left_area, buf)

    m.list_area = p1_inner
    m.list_visible_h = p1_inner.height

    # Auto-scroll to keep selection visible
    if m.list_selected - 1 < m.list_offset
        m.list_offset = m.list_selected - 1
    elseif m.list_selected > m.list_offset + m.list_visible_h
        m.list_offset = m.list_selected - m.list_visible_h
    end

    for i in 1:m.list_visible_h
        idx = m.list_offset + i
        idx > length(m.list_items) && break
        y = p1_inner.y + i - 1
        if idx == m.list_selected
            set_char!(buf, p1_inner.x, y, MARKER, tstyle(:accent, bold=true))
            set_string!(buf, p1_inner.x + 2, y, m.list_items[idx],
                        tstyle(:accent, bold=true))
        else
            set_string!(buf, p1_inner.x + 2, y, m.list_items[idx],
                        tstyle(:text))
        end
    end

    # ── Pane 2: info ──
    p2_border = m.focused_pane == 2 ? tstyle(:border_focus) : tstyle(:border)
    p2_block = Block(title="Pane 2: Info",
                     border_style=p2_border,
                     title_style=tstyle(:title))
    p2_inner = render(p2_block, right_area, buf)

    info_lines = [
        "H-Layout constraints:",
        "  Left:  $(_constraint_label(m.hlayout.constraints[1]))",
        "  Right: $(_constraint_label(m.hlayout.constraints[2]))",
        "",
        "V-Layout constraints:",
        "  Top:    $(_constraint_label(m.vlayout.constraints[1]))",
        "  Bottom: $(_constraint_label(m.vlayout.constraints[2]))",
        "",
        "Pane sizes:",
        "  Left:  $(left_area.width)x$(left_area.height)",
        "  Right: $(right_area.width)x$(right_area.height)",
        "  Bottom: $(bot_area.width)x$(bot_area.height)",
        "",
        "H-Direction: $(m.hlayout.direction)",
        "V-Direction: $(m.vlayout.direction)",
        "",
        "Drag events: $(m.drag_count)",
        "Selected: $(m.list_selected)",
    ]
    for (i, line) in enumerate(info_lines)
        y = p2_inner.y + i - 1
        y > bottom(p2_inner) && break
        set_string!(buf, p2_inner.x, y, line, tstyle(:text))
    end

    # ── Pane 3: instructions ──
    p3_border = m.focused_pane == 3 ? tstyle(:border_focus) : tstyle(:border)
    p3_block = Block(title="Instructions",
                     border_style=p3_border,
                     title_style=tstyle(:title))
    p3_inner = render(p3_block, bot_area, buf)

    # Store inner rects (content only, no borders) for Ctrl+Y copy
    m.pane_rects = [p1_inner, p2_inner, p3_inner]

    instructions = [
        "Drag borders to resize. Borders highlight on hover.",
        "[Alt+click border] rotate direction (H/V)",
        "[Alt+drag pane] swap with another pane",
        "[↑↓/jk] navigate list  [click] select/focus  [scroll] scroll",
        "[Ctrl+Y] copy focused pane  [r] reset  [q/Esc] quit",
    ]
    for (i, line) in enumerate(instructions)
        y = p3_inner.y + i - 1
        y > bottom(p3_inner) && break
        style = i <= 2 ? tstyle(:text) : tstyle(:text_dim)
        set_string!(buf, p3_inner.x, y, line, style)
    end

    # ── Render resize handles (visual feedback) ──
    render_resize_handles!(buf, m.vlayout)
    render_resize_handles!(buf, m.hlayout)
end

function resize_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    model = ResizeDemoModel()
    app(model; fps=30)
end
