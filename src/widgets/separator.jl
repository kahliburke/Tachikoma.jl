# ═══════════════════════════════════════════════════════════════════════
# Separator ── horizontal or vertical divider with optional label
# ═══════════════════════════════════════════════════════════════════════

struct Separator
    direction::Direction
    label::String
    style::Style
    label_style::Style
    char_h::Char
    char_v::Char
end

function Separator(;
    direction::Direction=Horizontal,
    label::String="",
    style::Style=tstyle(:border),
    label_style::Style=tstyle(:text_dim),
    char_h::Char='─',
    char_v::Char='│',
)
    Separator(direction, label, style, label_style, char_h, char_v)
end

function render(sep::Separator, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    if sep.direction == Horizontal
        y = rect.y
        for x in rect.x:right(rect)
            set_char!(buf, x, y, sep.char_h, sep.style)
        end
        # Centered label
        if !isempty(sep.label) && rect.width >= length(sep.label) + 2
            lx = center(rect, length(sep.label), 1).x
            set_string!(buf, lx, y, sep.label, sep.label_style)
        end
    else  # Vertical
        x = rect.x
        for y in rect.y:bottom(rect)
            set_char!(buf, x, y, sep.char_v, sep.style)
        end
        # Centered label (vertical)
        if !isempty(sep.label) && rect.height >= 1
            ly = center(rect, 1, 1).y
            set_char!(buf, x, ly, length(sep.label) > 0 ? sep.label[1] : sep.char_v,
                      sep.label_style)
        end
    end
end
