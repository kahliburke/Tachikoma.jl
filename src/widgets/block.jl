# ═══════════════════════════════════════════════════════════════════════
# Block ── bordered panel with optional title
# ═══════════════════════════════════════════════════════════════════════

struct Block
    title::String
    title_style::Style
    title_right::String
    title_right_style::Style
    border_style::Style
    box::NamedTuple
    title_padding::Int
end

function Block(;
    title="",
    title_style=tstyle(:title, bold=true),
    title_right="",
    title_right_style=tstyle(:title, bold=true),
    border_style=tstyle(:border),
    box=BOX_ROUNDED,
    title_padding=1,
)
    Block(title, title_style, title_right, title_right_style, border_style, box, title_padding)
end

function inner_area(block::Block, rect::Rect)
    Rect(rect.x + 1, rect.y + 1,
         max(0, rect.width - 2), max(0, rect.height - 2))
end

function render(block::Block, rect::Rect, buf::Buffer)
    (rect.width < 2 || rect.height < 2) && return rect
    s = block.border_style
    b = block.box
    pad = " " ^ block.title_padding

    # Corners
    set_char!(buf, rect.x, rect.y, b.tl, s)
    set_char!(buf, right(rect), rect.y, b.tr, s)
    set_char!(buf, rect.x, bottom(rect), b.bl, s)
    set_char!(buf, right(rect), bottom(rect), b.br, s)

    # Horizontal edges
    for x in (rect.x + 1):(right(rect) - 1)
        set_char!(buf, x, rect.y, b.h, s)
        set_char!(buf, x, bottom(rect), b.h, s)
    end

    # Vertical edges
    for y in (rect.y + 1):(bottom(rect) - 1)
        set_char!(buf, rect.x, y, b.v, s)
        set_char!(buf, right(rect), y, b.v, s)
    end

    # Title — left-aligned (auto-padded for visual separation from border)
    if !isempty(block.title) && rect.width > 4
        tx = rect.x + 1 + block.title_padding
        set_string!(buf, tx, rect.y, pad * block.title * pad,
                    block.title_style)
    end

    # Title — right-aligned (same padding)
    if !isempty(block.title_right) && rect.width > 4
        padded = pad * block.title_right * pad
        tx = right(rect) - block.title_padding - textwidth(padded)
        if tx > rect.x + 2
            set_string!(buf, tx, rect.y, padded, block.title_right_style)
        end
    end

    inner_area(block, rect)
end
