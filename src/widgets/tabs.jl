# ═══════════════════════════════════════════════════════════════════════
# TabBar ── horizontal tab bar with active tab highlight and overflow
# ═══════════════════════════════════════════════════════════════════════

const TabLabel = Union{String, Vector{Span}}

# ── Decoration types (dispatch for rendering) ─────────────────────────

"""
    TabDecoration

Abstract type for tab rendering styles. Subtype this and implement
`_render_tabs!` to create custom tab appearances.

Built-in decorations:
- `BracketTabs()` — `[Active]  Inactive ` (default)
- `BoxTabs()` — box-drawn borders around each tab (3 rows)
- `PlainTabs()` — plain text, no decoration
"""
abstract type TabDecoration end

"""
    BracketTabs()

Default tab style: active tab wrapped in `[brackets]`, inactive tabs
with spaces. Single-line rendering.
"""
struct BracketTabs <: TabDecoration end

"""
    BoxTabs(; box=BOX_PLAIN)

Box-drawn borders around each tab. Requires 3 rows of height
(top border, label, bottom border). The active tab's bottom border
is removed to create a connected appearance.
"""
struct BoxTabs <: TabDecoration
    box::NamedTuple{(:tl, :tr, :bl, :br, :h, :v), NTuple{6, Char}}
end
BoxTabs(; box=BOX_PLAIN) = BoxTabs(box)

"""
    PlainTabs()

Plain text tabs with no bracket or border decoration. Active tab
uses `active` style, inactive uses `inactive` style.
"""
struct PlainTabs <: TabDecoration end

# ── Tab style struct ──────────────────────────────────────────────────

"""
    TabBarStyle{D<:TabDecoration}

Visual configuration for a `TabBar`. Controls decoration style,
colors, separator, and overflow appearance.

# Examples
```julia
# Default bracket style
TabBarStyle()

# Box-drawn tabs
TabBarStyle(decoration=BoxTabs())

# Heavy box tabs with custom colors
TabBarStyle(decoration=BoxTabs(box=BOX_HEAVY),
            active=tstyle(:primary, bold=true))

# Plain text, no decoration
TabBarStyle(decoration=PlainTabs(), separator=" · ")
```
"""
struct TabBarStyle{D<:TabDecoration}
    decoration::D
    active::Style
    inactive::Style
    separator::String
    overflow_char::Char
    overflow_style::Style
    tab_colors::Vector{Style}  # per-tab color overrides (empty = use active/inactive)
end

function TabBarStyle(;
    decoration::TabDecoration=BracketTabs(),
    active::Style=tstyle(:accent, bold=true),
    inactive::Style=tstyle(:text_dim),
    separator::String=" │ ",
    overflow_char::Char='…',
    overflow_style::Style=tstyle(:text_dim),
    tab_colors::Vector{Style}=Style[],
)
    TabBarStyle(decoration, active, inactive, separator, overflow_char, overflow_style, tab_colors)
end

"""Get the style for tab `i`, using per-tab color if available, otherwise active/inactive."""
function _tab_style(ts::TabBarStyle, i::Int, is_active::Bool)
    base = is_active ? ts.active : ts.inactive
    if !isempty(ts.tab_colors) && i <= length(ts.tab_colors)
        tc = ts.tab_colors[i]
        # Merge: use per-tab fg color with active/inactive bold/dim
        Style(fg=tc.fg, bg=tc.bg isa NoColor ? base.bg : tc.bg,
              bold=base.bold, dim=base.dim, italic=base.italic, underline=base.underline)
    else
        base
    end
end

# ── Height query (box tabs need 3 rows) ──────────────────────────────

"""How many rows this decoration needs."""
tab_height(::TabDecoration) = 1
tab_height(::BoxTabs) = 3

# ── TabBar widget ─────────────────────────────────────────────────────

mutable struct TabBar{D<:TabDecoration}
    labels::Vector{TabLabel}
    active::Int
    focused::Bool
    tab_style::TabBarStyle{D}
    # Cached from last render for mouse hit testing
    _visible_range::UnitRange{Int}
    _tab_rects::Vector{Rect}
end

function TabBar(labels::Vector{<:TabLabel};
    active=1,
    focused=false,
    tab_style::TabBarStyle=TabBarStyle(),
    # Deprecated kwargs — kept for backwards compatibility
    style=nothing,
    active_style=nothing,
    separator=nothing,
    overflow_char=nothing,
    overflow_style=nothing,
)
    # Handle deprecated kwargs by building a TabBarStyle from them
    if any(!isnothing, (style, active_style, separator, overflow_char, overflow_style))
        Base.depwarn(
            "Passing style kwargs directly to TabBar is deprecated. " *
            "Use `tab_style=TabBarStyle(...)` instead.",
            :TabBar)
        ts = tab_style
        tab_style = TabBarStyle(
            decoration=ts.decoration,
            active=something(active_style, ts.active),
            inactive=something(style, ts.inactive),
            separator=something(separator, ts.separator),
            overflow_char=something(overflow_char, ts.overflow_char),
            overflow_style=something(overflow_style, ts.overflow_style),
        )
    end
    act = clamp(active, 1, max(1, length(labels)))
    TabBar(convert(Vector{TabLabel}, labels), act, focused, tab_style,
           1:length(labels), Rect[])
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
        empty!(bar._tab_rects)
        return true
    elseif evt.key == :right || evt.key == :tab
        bar.active = mod1(bar.active + 1, n)
        empty!(bar._tab_rects)
        return true
    end
    false
end

function handle_mouse!(bar::TabBar, evt::MouseEvent)::Symbol
    (evt.button == mouse_left && evt.action == mouse_press) || return :none
    isempty(bar._tab_rects) && return :none
    for (vi, rect) in enumerate(bar._tab_rects)
        if Base.contains(rect, evt.x, evt.y)
            real_idx = first(bar._visible_range) + vi - 1
            real_idx = clamp(real_idx, 1, length(bar.labels))
            if real_idx != bar.active
                bar.active = real_idx
                empty!(bar._tab_rects)
                return :changed
            end
            return :none
        end
    end
    :none
end

# ── Label utilities ───────────────────────────────────────────────────

_tab_label_len(s::String) = length(s)
_tab_label_len(spans::Vector{Span}) = sum(length(s.content) for s in spans; init=0)

"""Rendered width of a single tab including decoration."""
_tab_rendered_width(label::TabLabel, ::TabDecoration) = _tab_label_len(label) + 2
_tab_rendered_width(label::TabLabel, ::PlainTabs) = _tab_label_len(label)
_tab_rendered_width(label::TabLabel, ::BoxTabs) = _tab_label_len(label) + 2  # │ + label + │

function _render_tab_label!(buf::Buffer, cx::Int, y::Int, label::String, sty::Style, maxcx::Int)
    for ch in label
        cx > maxcx && break
        set_char!(buf, cx, y, ch, sty)
        cx += 1
    end
    cx
end

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

# ── Overflow computation ──────────────────────────────────────────────

function _compute_visible_tabs(bar::TabBar, avail_width::Int)
    n = length(bar.labels)
    dec = bar.tab_style.decoration
    n == 0 && return (1, 0)
    sep_w = length(bar.tab_style.separator)
    tab_widths = [_tab_rendered_width(bar.labels[i], dec) for i in 1:n]

    total = sum(tab_widths) + sep_w * max(0, n - 1)
    total <= avail_width && return (1, n)

    # If the active tab is already visible in the current range, keep it stable
    # to avoid jarring scrolls on mouse click. Only recompute when needed.
    prev = bar._visible_range
    if bar.active in prev && first(prev) >= 1 && last(prev) <= n
        need_left = first(prev) > 1 ? 1 : 0
        need_right = last(prev) < n ? 1 : 0
        test_w = sum(tab_widths[first(prev):last(prev)]) + sep_w * max(0, length(prev) - 1) + need_left + need_right
        if test_w <= avail_width
            return (first(prev), last(prev))
        end
    end

    at = bar.active
    lo, hi = at, at

    while true
        expanded = false
        if hi < n
            need_left = lo > 1 ? 1 : 0
            need_right = (hi + 1) < n ? 1 : 0
            test_w = sum(tab_widths[lo:hi+1]) + sep_w * (hi + 1 - lo) + need_left + need_right
            if test_w <= avail_width
                hi += 1
                expanded = true
            end
        end
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

# ── Render dispatch ───────────────────────────────────────────────────

function render(bar::TabBar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    isempty(bar.labels) && return
    _render_tabs!(bar, bar.tab_style.decoration, rect, buf)
end

# ── BracketTabs rendering (default) ──────────────────────────────────

function _render_tabs!(bar::TabBar, ::BracketTabs, rect::Rect, buf::Buffer)
    ts = bar.tab_style

    lo, hi = _compute_visible_tabs(bar, rect.width)
    bar._visible_range = lo:hi
    empty!(bar._tab_rects)

    has_left = lo > 1
    has_right = hi < length(bar.labels)

    if has_left
        set_char!(buf, rect.x, rect.y, ts.overflow_char, ts.overflow_style)
    end
    if has_right
        set_char!(buf, right(rect), rect.y, ts.overflow_char, ts.overflow_style)
    end

    rx = rect.x + (has_left ? 1 : 0)
    max_rx = right(rect) - (has_right ? 1 : 0)
    cx = rx
    y = rect.y
    sep_style = tstyle(:border, dim=true)

    for i in lo:hi
        label = bar.labels[i]
        if i > lo
            for ch in ts.separator
                cx > max_rx && break
                set_char!(buf, cx, y, ch, sep_style)
                cx += 1
            end
        end
        cx > max_rx && break

        tab_start = cx
        is_active = i == bar.active
        sty = _tab_style(ts, i, is_active)
        if is_active
            set_char!(buf, cx, y, '[', sty)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, sty, max_rx)
            cx <= max_rx && set_char!(buf, cx, y, ']', sty)
            cx += 1
        else
            set_char!(buf, cx, y, ' ', sty)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, sty, max_rx)
            cx <= max_rx && set_char!(buf, cx, y, ' ', sty)
            cx += 1
        end

        tab_end = cx - 1
        push!(bar._tab_rects, Rect(tab_start, y, max(1, tab_end - tab_start + 1), 1))
    end
end

# ── PlainTabs rendering ──────────────────────────────────────────────

function _render_tabs!(bar::TabBar, ::PlainTabs, rect::Rect, buf::Buffer)
    ts = bar.tab_style

    lo, hi = _compute_visible_tabs(bar, rect.width)
    bar._visible_range = lo:hi
    empty!(bar._tab_rects)

    has_left = lo > 1
    has_right = hi < length(bar.labels)

    if has_left
        set_char!(buf, rect.x, rect.y, ts.overflow_char, ts.overflow_style)
    end
    if has_right
        set_char!(buf, right(rect), rect.y, ts.overflow_char, ts.overflow_style)
    end

    rx = rect.x + (has_left ? 1 : 0)
    max_rx = right(rect) - (has_right ? 1 : 0)
    cx = rx
    y = rect.y
    sep_style = tstyle(:border, dim=true)

    for i in lo:hi
        label = bar.labels[i]
        if i > lo
            for ch in ts.separator
                cx > max_rx && break
                set_char!(buf, cx, y, ch, sep_style)
                cx += 1
            end
        end
        cx > max_rx && break

        tab_start = cx
        sty = _tab_style(ts, i, i == bar.active)
        cx = _render_tab_label!(buf, cx, y, label, sty, max_rx)

        tab_end = cx - 1
        push!(bar._tab_rects, Rect(tab_start, y, max(1, tab_end - tab_start + 1), 1))
    end
end

# ── BoxTabs rendering (3 rows) ───────────────────────────────────────

function _render_tabs!(bar::TabBar, dec::BoxTabs, rect::Rect, buf::Buffer)
    ts = bar.tab_style
    box = dec.box

    # Box tabs need at least 3 rows
    rect.height < 3 && return _render_tabs!(bar, BracketTabs(), rect, buf)

    lo, hi = _compute_visible_tabs(bar, rect.width)
    bar._visible_range = lo:hi
    empty!(bar._tab_rects)

    has_left = lo > 1
    has_right = hi < length(bar.labels)

    if has_left
        set_char!(buf, rect.x, rect.y + 1, ts.overflow_char, ts.overflow_style)
    end
    if has_right
        set_char!(buf, right(rect), rect.y + 1, ts.overflow_char, ts.overflow_style)
    end

    rx = rect.x + (has_left ? 1 : 0)
    max_rx = right(rect) - (has_right ? 1 : 0)
    cx = rx
    y_top = rect.y
    y_mid = rect.y + 1
    y_bot = rect.y + 2

    for i in lo:hi
        label = bar.labels[i]
        tw = _tab_label_len(label)
        tab_w = tw + 2  # v + label + v

        # Check if this tab fits
        cx + tab_w - 1 > max_rx && break

        tab_start = cx
        is_active = i == bar.active
        sty = _tab_style(ts, i, is_active)
        border_style = sty

        # Top border: ┌──┐
        set_char!(buf, cx, y_top, box.tl, border_style)
        for j in 1:tw
            set_char!(buf, cx + j, y_top, box.h, border_style)
        end
        set_char!(buf, cx + tw + 1, y_top, box.tr, border_style)

        # Middle: │label│
        set_char!(buf, cx, y_mid, box.v, border_style)
        _render_tab_label!(buf, cx + 1, y_mid, label, sty, cx + tw)
        set_char!(buf, cx + tw + 1, y_mid, box.v, border_style)

        # Bottom border: └──┘ for inactive, spaces for active (connected)
        if is_active
            set_char!(buf, cx, y_bot, box.br, border_style)
            for j in 1:tw
                set_char!(buf, cx + j, y_bot, ' ', sty)
            end
            set_char!(buf, cx + tw + 1, y_bot, box.bl, border_style)
        else
            set_char!(buf, cx, y_bot, box.bl, border_style)
            for j in 1:tw
                set_char!(buf, cx + j, y_bot, box.h, border_style)
            end
            set_char!(buf, cx + tw + 1, y_bot, box.br, border_style)
        end

        push!(bar._tab_rects, Rect(tab_start, y_top, tab_w, 3))
        cx += tab_w
    end

    # Draw bottom border line across remaining width
    for x in cx:right(rect)
        set_char!(buf, x, y_bot, box.h, tstyle(:border, dim=true))
    end
end
