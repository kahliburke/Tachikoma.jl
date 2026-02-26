# ═══════════════════════════════════════════════════════════════════════
# DropDown ── collapsed select picker
# ═══════════════════════════════════════════════════════════════════════

mutable struct DropDown
    items::Vector{String}
    selected::Int
    focused::Int              # highlighted item in expanded list
    open::Bool
    max_visible::Int
    offset::Int               # scroll offset in expanded list
    style::Style
    selected_style::Style
    focused_style::Style
    tick::Union{Int, Nothing}
end

"""
    DropDown(items; selected=1, max_visible=8, ...)

Collapsed select picker. Enter/Space to open, Up/Down to navigate, Enter to select.
"""
function DropDown(items::Vector{String};
    selected::Int=1,
    max_visible::Int=8,
    style::Style=tstyle(:text),
    selected_style::Style=tstyle(:primary),
    focused_style::Style=tstyle(:accent, bold=true),
    tick::Union{Int, Nothing}=nothing,
)
    sel = clamp(selected, 1, max(1, length(items)))
    DropDown(items, sel, sel, false, max_visible, 0, style, selected_style, focused_style, tick)
end

focusable(::DropDown) = true

function handle_key!(dd::DropDown, evt::KeyEvent)::Bool
    n = length(dd.items)
    n == 0 && return false

    if !dd.open
        if evt.key == :enter || (evt.key == :char && evt.char == ' ')
            dd.open = true
            dd.focused = dd.selected
            return true
        end
        return false
    end

    # Expanded state
    if evt.key == :up
        dd.focused = mod1(dd.focused - 1, n)
        _dd_ensure_visible!(dd)
        return true
    elseif evt.key == :down
        dd.focused = mod1(dd.focused + 1, n)
        _dd_ensure_visible!(dd)
        return true
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        dd.selected = dd.focused
        dd.open = false
        return true
    elseif evt.key == :escape
        dd.open = false
        return true
    end
    false
end

function handle_mouse!(dd::DropDown, evt::MouseEvent)::Bool
    dd.open || return false
    n = length(dd.items)
    vis = min(n, dd.max_visible)
    if evt.button == mouse_scroll_up && evt.action == mouse_press
        dd.offset = max(0, dd.offset - 1)
        return true
    elseif evt.button == mouse_scroll_down && evt.action == mouse_press
        dd.offset = min(max(0, n - vis), dd.offset + 1)
        return true
    end
    false
end

function _dd_ensure_visible!(dd::DropDown)
    vis = min(length(dd.items), dd.max_visible)
    if dd.focused - 1 < dd.offset
        dd.offset = dd.focused - 1
    elseif dd.focused > dd.offset + vis
        dd.offset = dd.focused - vis
    end
end

function render(dd::DropDown, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    n = length(dd.items)

    # Collapsed view: single row showing selected item
    label = n > 0 ? dd.items[dd.selected] : ""
    display = string("▾ ", label)
    s = dd.open ? dd.focused_style : dd.selected_style
    set_string!(buf, rect.x, rect.y, display, s; max_x=right(rect))

    if dd.open && rect.height > 1
        vis = min(n, dd.max_visible, rect.height - 1)
        for i in 1:vis
            idx = dd.offset + i
            idx > n && break
            y = rect.y + i
            y > bottom(rect) && break
            item_s = idx == dd.focused ? dd.focused_style : dd.style
            set_string!(buf, rect.x + 2, y, dd.items[idx], item_s;
                        max_x=right(rect))
        end
    end
end

value(dd::DropDown) = dd.selected > 0 && dd.selected <= length(dd.items) ?
    dd.items[dd.selected] : ""
set_value!(dd::DropDown, idx::Int) = (dd.selected = clamp(idx, 1, length(dd.items)); nothing)
