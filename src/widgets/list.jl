# ═══════════════════════════════════════════════════════════════════════
# List ── selectable list with highlight and scrolling
# ═══════════════════════════════════════════════════════════════════════

struct ListItem
    content::String
    style::Style
end

ListItem(s::AbstractString) = ListItem(s, tstyle(:text))

mutable struct SelectableList
    items::Vector{ListItem}
    selected::Int
    offset::Int                    # scroll offset (0-based)
    focused::Bool
    block::Union{Block, Nothing}
    highlight_style::Style
    marker::Char
    tick::Union{Int, Nothing}      # enables subtle animation when set
    show_scrollbar::Bool
    last_area::Rect                # cached content area for mouse hit-testing
end

"""
    SelectableList(items; selected=1, focused=false, tick=nothing, show_scrollbar=true, ...)

Scrollable list with keyboard navigation and mouse support.
Keyboard: Up/Down to move, Home/End for first/last, PageUp/PageDown for jumps.
Mouse: click to select, scroll wheel to scroll.
"""
function SelectableList(items::Vector{ListItem};
    selected=1,
    offset=0,
    focused=false,
    block=nothing,
    highlight_style=tstyle(:accent, bold=true),
    marker=MARKER,
    tick=nothing,
    show_scrollbar=true,
)
    sel = clamp(selected, 1, max(1, length(items)))
    SelectableList(items, sel, offset, focused, block, highlight_style, marker, tick,
                   show_scrollbar, Rect())
end

function SelectableList(items::Vector{String}; kwargs...)
    SelectableList([ListItem(s) for s in items]; kwargs...)
end

value(lst::SelectableList) = lst.selected
set_value!(lst::SelectableList, idx::Int) = (lst.selected = clamp(idx, 1, max(1, length(lst.items))); nothing)

focusable(::SelectableList) = true

function handle_key!(lst::SelectableList, evt::KeyEvent)::Bool
    n = length(lst.items)
    n == 0 && return false
    if evt.key == :up
        lst.selected = lst.selected > 1 ? lst.selected - 1 : n
    elseif evt.key == :down
        lst.selected = lst.selected < n ? lst.selected + 1 : 1
    elseif evt.key == :home
        lst.selected = 1
    elseif evt.key == :end_key
        lst.selected = n
    elseif evt.key == :pageup
        lst.selected = max(1, lst.selected - 10)
    elseif evt.key == :pagedown
        lst.selected = min(n, lst.selected + 10)
    else
        return false
    end
    true
end

function render(lst::SelectableList, rect::Rect, buf::Buffer)
    content = if lst.block !== nothing
        render(lst.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    visible_h = content.height
    n = length(lst.items)

    # Reserve scrollbar column
    needs_scrollbar = lst.show_scrollbar && n > visible_h
    text_area = if needs_scrollbar && content.width > 1
        Rect(content.x, content.y, content.width - 1, content.height)
    else
        content
    end

    # Cache content area for mouse hit-testing
    lst.last_area = content

    # Auto-scroll to keep selection visible
    if lst.selected - 1 < lst.offset
        lst.offset = lst.selected - 1
    elseif lst.selected > lst.offset + visible_h
        lst.offset = lst.selected - visible_h
    end

    # Animated highlight: gentle pulse on the selected row's accent
    hl_style = lst.highlight_style
    if lst.tick !== nothing && animations_enabled()
        base_fg = hl_style.fg
        p = pulse(lst.tick; period=80, lo=0.0, hi=0.2)
        anim_fg = brighten(to_rgb(base_fg), p * 0.3)
        hl_style = Style(fg=anim_fg, bold=hl_style.bold)
    end

    max_cx = right(text_area)
    for i in 1:visible_h
        idx = lst.offset + i
        idx > n && break
        y = text_area.y + i - 1
        item = lst.items[idx]

        if idx == lst.selected
            # Highlighted row
            text_area.x <= max_cx && set_char!(buf, text_area.x, y, lst.marker, hl_style)
            set_string!(buf, text_area.x + 2, y,
                        item.content, hl_style; max_x=max_cx)
        else
            set_string!(buf, text_area.x + 2, y,
                        item.content, item.style; max_x=max_cx)
        end
    end

    # Scrollbar or scroll indicators
    if needs_scrollbar && content.width > 1
        sb_rect = Rect(right(content), content.y, 1, content.height)
        sb = Scrollbar(n, visible_h, lst.offset)
        render(sb, sb_rect, buf)
    else
        if lst.offset > 0
            set_char!(buf, right(content), content.y, '▲',
                      tstyle(:text_dim))
        end
        if lst.offset + visible_h < n
            set_char!(buf, right(content), bottom(content), '▼',
                      tstyle(:text_dim))
        end
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Native mouse handling for SelectableList
# ═══════════════════════════════════════════════════════════════════════

"""
    handle_mouse!(lst::SelectableList, evt::MouseEvent) → Bool

Handle mouse events: left-click to select, scroll wheel to scroll.
Uses `last_area` cached during the most recent `render` call.
"""
function handle_mouse!(lst::SelectableList, evt::MouseEvent)::Bool
    lst.last_area.width == 0 && return false
    area = lst.last_area
    Base.contains(area, evt.x, evt.y) || return false
    n = length(lst.items)
    n == 0 && return false

    # Click to select
    if evt.button == mouse_left && evt.action == mouse_press
        idx = lst.offset + (evt.y - area.y + 1)
        if idx >= 1 && idx <= n
            lst.selected = idx
            return true
        end
        return false
    end

    # Scroll wheel
    visible_h = area.height
    new_off = list_scroll(evt, lst.offset, n, visible_h)
    if new_off != lst.offset
        lst.offset = new_off
        return true
    end
    false
end

# ═══════════════════════════════════════════════════════════════════════
# Standalone mouse helpers (for callers managing their own areas)
# ═══════════════════════════════════════════════════════════════════════

"""
    list_hit(evt::MouseEvent, content_area::Rect, offset::Int, n_items::Int) → Int

Returns 1-based item index clicked, or 0 if outside list area or not a left press.
"""
function list_hit(evt::MouseEvent, content_area::Rect, offset::Int, n_items::Int)
    evt.button == mouse_left && evt.action == mouse_press || return 0
    Base.contains(content_area, evt.x, evt.y) || return 0
    idx = offset + (evt.y - content_area.y + 1)
    (idx >= 1 && idx <= n_items) ? idx : 0
end

"""
    list_scroll(evt::MouseEvent, offset::Int, n_items::Int, visible_h::Int) → Int

Returns new offset for scroll wheel events, or current offset if not a scroll.
"""
function list_scroll(evt::MouseEvent, offset::Int, n_items::Int, visible_h::Int)
    max_off = max(0, n_items - visible_h)
    if evt.button == mouse_scroll_up && evt.action == mouse_press
        return max(0, offset - 1)
    elseif evt.button == mouse_scroll_down && evt.action == mouse_press
        return min(max_off, offset + 1)
    end
    offset
end
