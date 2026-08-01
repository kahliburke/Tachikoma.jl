# ═══════════════════════════════════════════════════════════════════════
# StatusBar ── single-row bar with left/right aligned content
# ═══════════════════════════════════════════════════════════════════════

struct StatusBar
    left::Vector{Span}
    right::Vector{Span}
    style::Style                   # background fill style
end

function StatusBar(; left=Span[], right=Span[], style=tstyle(:text_dim))
    return StatusBar(left, right, style)
end

function render(bar::StatusBar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return nothing
    y = rect.y

    # Fill background
    for cx in rect.x:right(rect)
        set_char!(buf, cx, y, ' ', bar.style)
    end

    # Render left-aligned spans
    cx = rect.x
    rx = right(rect)
    for span in bar.left
        cx > rx && break
        cx = set_string!(buf, cx, y, span.content, span.style; max_x=rx)
    end
    left_end = cx

    # Compute right-aligned content width
    right_width = sum(textwidth(span.content) for span in bar.right; init=0)

    # Render right-aligned spans (only if they don't overlap left)
    rx2 = right(rect) - right_width + 1
    rx2 = max(rx2, left_end)  # left takes priority
    for span in bar.right
        rx2 > rx && break
        rx2 = set_string!(buf, rx2, y, span.content, span.style; max_x=rx)
    end
end
