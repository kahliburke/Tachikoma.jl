# ═══════════════════════════════════════════════════════════════════════
# StatusBar ── single-row bar with left/right aligned content
# ═══════════════════════════════════════════════════════════════════════

struct StatusBar
    left::Vector{Span}
    right::Vector{Span}
    style::Style                   # background fill style
end

function StatusBar(;
    left=Span[],
    right=Span[],
    style=tstyle(:text_dim),
)
    StatusBar(left, right, style)
end

function render(bar::StatusBar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    y = rect.y

    # Fill background
    for cx in rect.x:right(rect)
        set_char!(buf, cx, y, ' ', bar.style)
    end

    # Render left-aligned spans
    cx = rect.x
    for span in bar.left
        for ch in span.content
            cx > right(rect) && break
            set_char!(buf, cx, y, ch, span.style)
            cx += 1
        end
    end
    left_end = cx

    # Compute right-aligned content width
    right_width = sum(length(span.content) for span in bar.right; init=0)

    # Render right-aligned spans (only if they don't overlap left)
    rx = right(rect) - right_width + 1
    rx = max(rx, left_end)  # left takes priority
    for span in bar.right
        for ch in span.content
            rx > right(rect) && break
            set_char!(buf, rx, y, ch, span.style)
            rx += 1
        end
    end
end
