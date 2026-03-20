# ═══════════════════════════════════════════════════════════════════════
# TabBar ── horizontal tab bar with active tab highlight and overflow
# ═══════════════════════════════════════════════════════════════════════

const TabLabel = Union{String, Vector{Span}}

mutable struct TabBar
    labels::Vector{TabLabel}
    active::Int                    # 1-based index of active tab
    focused::Bool                  # receives key events when true
    style::Style                   # inactive tab style
    active_style::Style            # active tab style
    separator::String              # between tabs, e.g. " │ "
    overflow_char::Char            # shown when tabs are clipped (default '…')
    overflow_style::Style          # style for overflow indicator
    # Cached from last render for mouse hit testing
    _visible_range::UnitRange{Int} # which tabs were rendered
    _tab_rects::Vector{Rect}       # bounding rect per visible tab (for mouse clicks)
end

function TabBar(labels::Vector{<:TabLabel};
    active=1,
    focused=false,
    style=tstyle(:text_dim),
    active_style=tstyle(:accent, bold=true),
    separator=" │ ",
    overflow_char='…',
    overflow_style=tstyle(:text_dim),
)
    act = clamp(active, 1, max(1, length(labels)))
    TabBar(convert(Vector{TabLabel}, labels), act, focused, style, active_style,
           separator, overflow_char, overflow_style, 1:length(labels), Rect[])
end

value(bar::TabBar) = bar.active
set_value!(bar::TabBar, v::Int) = (bar.active = clamp(v, 1, max(1, length(bar.labels))))
focusable(::TabBar) = true

function handle_key!(bar::TabBar, evt::KeyEvent)::Bool
    bar.focused || return false
    n = length(bar.labels)
    n == 0 && return false
    if evt.key == :left || evt.key == :backtab
        bar.active = mod1(bar.active - 1, n)
        return true
    elseif evt.key == :right || evt.key == :tab
        bar.active = mod1(bar.active + 1, n)
        return true
    end
    false
end

function handle_mouse!(bar::TabBar, evt::MouseEvent)::Symbol
    isempty(bar._tab_rects) && return :none
    for (vi, rect) in enumerate(bar._tab_rects)
        if Base.contains(rect, evt.x, evt.y) && evt.button == mouse_left
            real_idx = first(bar._visible_range) + vi - 1
            if real_idx != bar.active
                bar.active = real_idx
                return :changed
            end
            return :none
        end
    end
    :none
end

# Plain-string label length
_tab_label_len(s::String) = length(s)
_tab_label_len(spans::Vector{Span}) = sum(length(s.content) for s in spans; init=0)

# Rendered width of a single tab: brackets/spaces + label
_tab_rendered_width(label::TabLabel) = _tab_label_len(label) + 2

# Render a plain-string label with a single style
function _render_tab_label!(buf::Buffer, cx::Int, y::Int, label::String, sty::Style, maxcx::Int)
    for ch in label
        cx > maxcx && break
        set_char!(buf, cx, y, ch, sty)
        cx += 1
    end
    cx
end

# Render a rich (Vector{Span}) label — each span keeps its own style
function _render_tab_label!(buf::Buffer, cx::Int, y::Int, spans::Vector{Span}, ::Style, maxcx::Int)
    for span in spans
        for ch in span.content
            cx > maxcx && break
            set_char!(buf, cx, y, ch, span.style)
            cx += 1
        end
    end
    cx
end

# ── Overflow / visible window ────────────────────────────────────────

"""
    _compute_visible_tabs(bar, avail_width) -> (lo, hi)

Compute the visible tab range that fits within `avail_width`, always
including `bar.active`. Expands outward from the active tab, reserving
1 char for overflow indicators on each clipped side.
"""
function _compute_visible_tabs(bar::TabBar, avail_width::Int)
    n = length(bar.labels)
    n == 0 && return (1, 0)
    sep_w = length(bar.separator)
    tab_widths = [_tab_rendered_width(bar.labels[i]) for i in 1:n]

    # Check if everything fits
    total = sum(tab_widths) + sep_w * max(0, n - 1)
    total <= avail_width && return (1, n)

    # Start with just the active tab, expand outward alternating right then left
    at = bar.active
    lo, hi = at, at

    while true
        expanded = false

        # Try expanding right
        if hi < n
            need_left = lo > 1 ? 1 : 0
            need_right = (hi + 1) < n ? 1 : 0
            test_w = sum(tab_widths[lo:hi+1]) + sep_w * (hi + 1 - lo) + need_left + need_right
            if test_w <= avail_width
                hi += 1
                expanded = true
            end
        end

        # Try expanding left
        if lo > 1
            need_left = (lo - 1) > 1 ? 1 : 0
            need_right = hi < n ? 1 : 0
            test_w = sum(tab_widths[lo-1:hi]) + sep_w * (hi - lo + 1) + need_left + need_right
            if test_w <= avail_width
                lo -= 1
                expanded = true
            end
        end

        !expanded && break
    end

    return (lo, hi)
end

# ── Render ───────────────────────────────────────────────────────────

function render(bar::TabBar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    isempty(bar.labels) && return

    lo, hi = _compute_visible_tabs(bar, rect.width)
    bar._visible_range = lo:hi
    empty!(bar._tab_rects)

    has_left = lo > 1
    has_right = hi < length(bar.labels)

    # Draw overflow indicators
    if has_left
        set_char!(buf, rect.x, rect.y, bar.overflow_char, bar.overflow_style)
    end
    if has_right
        set_char!(buf, right(rect), rect.y, bar.overflow_char, bar.overflow_style)
    end

    # Render area excluding overflow indicators
    rx = rect.x + (has_left ? 1 : 0)
    max_rx = right(rect) - (has_right ? 1 : 0)

    cx = rx
    y = rect.y
    sep_style = tstyle(:border, dim=true)

    for i in lo:hi
        label = bar.labels[i]

        # Separator between tabs (not before first visible)
        if i > lo
            for ch in bar.separator
                cx > max_rx && break
                set_char!(buf, cx, y, ch, sep_style)
                cx += 1
            end
        end
        cx > max_rx && break

        tab_start = cx
        if i == bar.active
            set_char!(buf, cx, y, '[', bar.active_style)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, bar.active_style, max_rx)
            cx <= max_rx && set_char!(buf, cx, y, ']', bar.active_style)
            cx += 1
        else
            set_char!(buf, cx, y, ' ', bar.style)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, bar.style, max_rx)
            cx <= max_rx && set_char!(buf, cx, y, ' ', bar.style)
            cx += 1
        end

        # Record tab rect for mouse hit testing
        tab_end = cx - 1
        push!(bar._tab_rects, Rect(tab_start, y, max(1, tab_end - tab_start + 1), 1))
    end
end
