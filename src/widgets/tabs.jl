# ═══════════════════════════════════════════════════════════════════════
# TabBar ── horizontal tab bar with active tab highlight
# ═══════════════════════════════════════════════════════════════════════

const TabLabel = Union{String, Vector{Span}}

struct TabBar
    labels::Vector{TabLabel}
    active::Int                    # 1-based index of active tab
    style::Style                   # inactive tab style
    active_style::Style            # active tab style
    separator::String              # between tabs, e.g. " │ "
end

function TabBar(labels::Vector{<:TabLabel};
    active=1,
    style=tstyle(:text_dim),
    active_style=tstyle(:accent, bold=true),
    separator=" │ ",
)
    act = clamp(active, 1, max(1, length(labels)))
    TabBar(convert(Vector{TabLabel}, labels), act, style, active_style, separator)
end

# Plain-string label length
_tab_label_len(s::String) = length(s)
_tab_label_len(spans::Vector{Span}) = sum(length(s.content) for s in spans; init=0)

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

function render(bar::TabBar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    isempty(bar.labels) && return

    cx = rect.x
    y = rect.y
    sep_style = tstyle(:border, dim=true)

    for (i, label) in enumerate(bar.labels)
        # Separator between tabs (not before first)
        if i > 1
            for ch in bar.separator
                cx > right(rect) && break
                set_char!(buf, cx, y, ch, sep_style)
                cx += 1
            end
        end
        cx > right(rect) && break

        if i == bar.active
            # Active: [Label]
            set_char!(buf, cx, y, '[', bar.active_style)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, bar.active_style, right(rect))
            cx <= right(rect) && set_char!(buf, cx, y, ']', bar.active_style)
            cx += 1
        else
            # Inactive:  Label
            set_char!(buf, cx, y, ' ', bar.style)
            cx += 1
            cx = _render_tab_label!(buf, cx, y, label, bar.style, right(rect))
            cx <= right(rect) && set_char!(buf, cx, y, ' ', bar.style)
            cx += 1
        end
    end
end
