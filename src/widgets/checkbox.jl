# ═══════════════════════════════════════════════════════════════════════
# Checkbox ── togglable checkbox with label
# ═══════════════════════════════════════════════════════════════════════

mutable struct Checkbox
    label::String
    checked::Bool
    focused::Bool
    style::Style
    focused_style::Style
    check_char::Char
    uncheck_char::Char
    tick::Union{Int, Nothing}
end

"""
    Checkbox(label; checked=false, focused=false, ...)

Togglable checkbox. Press Enter or Space to toggle.
"""
function Checkbox(label::String;
    checked::Bool=false,
    focused::Bool=false,
    style::Style=tstyle(:text),
    focused_style::Style=tstyle(:accent, bold=true),
    check_char::Char='☑',
    uncheck_char::Char='☐',
    tick::Union{Int, Nothing}=nothing,
)
    Checkbox(label, checked, focused, style, focused_style, check_char, uncheck_char, tick)
end

focusable(::Checkbox) = true
intrinsic_size(cb::Checkbox) = (length(cb.label) + 4, 1)

function handle_key!(cb::Checkbox, evt::KeyEvent)::Bool
    cb.focused || return false
    if evt.key == :enter || (evt.key == :char && evt.char == ' ')
        cb.checked = !cb.checked
        return true
    end
    false
end

function render(cb::Checkbox, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    y = rect.y
    s = cb.focused ? cb.focused_style : cb.style
    mark = cb.checked ? cb.check_char : cb.uncheck_char
    set_char!(buf, rect.x, y, mark, s)
    if rect.width >= 3
        set_string!(buf, rect.x + 2, y, cb.label, s; max_x=right(rect))
    end
end

value(cb::Checkbox) = cb.checked
set_value!(cb::Checkbox, v::Bool) = (cb.checked = v; nothing)

# ═══════════════════════════════════════════════════════════════════════
# RadioGroup ── mutually exclusive selection from a list of labels
# ═══════════════════════════════════════════════════════════════════════

mutable struct RadioGroup
    labels::Vector{String}
    selected::Int
    focused::Bool
    cursor::Int              # highlighted item position within the list
    style::Style
    focused_style::Style
    selected_char::Char
    unselected_char::Char
    tick::Union{Int, Nothing}
end

"""
    RadioGroup(labels; selected=1, focused=false, cursor=1, ...)

Mutually exclusive selection from a list. Up/Down to navigate, Enter/Space to select.
"""
function RadioGroup(labels::Vector{String};
    selected::Int=1,
    focused::Bool=false,
    cursor::Int=1,
    style::Style=tstyle(:text),
    focused_style::Style=tstyle(:accent, bold=true),
    selected_char::Char='◉',
    unselected_char::Char='○',
    tick::Union{Int, Nothing}=nothing,
)
    sel = clamp(selected, 1, max(1, length(labels)))
    cur = clamp(cursor, 1, max(1, length(labels)))
    RadioGroup(labels, sel, focused, cur, style, focused_style,
               selected_char, unselected_char, tick)
end

focusable(::RadioGroup) = true
intrinsic_size(rg::RadioGroup) = (maximum(length.(rg.labels); init=0) + 2, length(rg.labels))

function handle_key!(rg::RadioGroup, evt::KeyEvent)::Bool
    rg.focused || return false
    n = length(rg.labels)
    n == 0 && return false
    if evt.key == :up
        rg.cursor = mod1(rg.cursor - 1, n)
        return true
    elseif evt.key == :down
        rg.cursor = mod1(rg.cursor + 1, n)
        return true
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        rg.selected = rg.cursor
        return true
    end
    false
end

function render(rg::RadioGroup, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    for (i, label) in enumerate(rg.labels)
        i > rect.height && break
        y = rect.y + i - 1
        is_sel = i == rg.selected
        is_foc = rg.focused && i == rg.cursor
        mark = is_sel ? rg.selected_char : rg.unselected_char
        s = is_foc ? rg.focused_style : rg.style
        set_char!(buf, rect.x, y, mark, s)
        if rect.width >= 3
            set_string!(buf, rect.x + 2, y, label, s; max_x=right(rect))
        end
    end
end

value(rg::RadioGroup) = rg.selected
set_value!(rg::RadioGroup, idx::Int) = (rg.selected = clamp(idx, 1, length(rg.labels)); nothing)
