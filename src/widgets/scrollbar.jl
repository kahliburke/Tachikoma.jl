# ═══════════════════════════════════════════════════════════════════════
# Scrollbar ── vertical scroll position indicator
# ═══════════════════════════════════════════════════════════════════════

struct Scrollbar
    total::Int                     # total items
    visible::Int                   # visible items
    offset::Int                    # scroll offset (0-based)
    style::Style                   # track style
    thumb_style::Style             # thumb style
end

function Scrollbar(total::Int, visible::Int, offset::Int;
    style=tstyle(:text_dim, dim=true),
    thumb_style=tstyle(:primary),
)
    Scrollbar(total, visible, max(0, offset), style, thumb_style)
end

function render(sb::Scrollbar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    sb.total <= sb.visible && return  # no scroll needed

    h = rect.height
    x = rect.x

    # Thumb size and position
    thumb_h = max(1, round(Int, h * sb.visible / sb.total))
    max_offset = sb.total - sb.visible
    thumb_pos = max_offset > 0 ?
        round(Int, (h - thumb_h) * sb.offset / max_offset) : 0

    for row in 0:(h - 1)
        y = rect.y + row
        if row >= thumb_pos && row < thumb_pos + thumb_h
            set_char!(buf, x, y, '█', sb.thumb_style)
        else
            set_char!(buf, x, y, '│', sb.style)
        end
    end
end
