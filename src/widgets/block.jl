# ═══════════════════════════════════════════════════════════════════════
# Block ── bordered panel with optional title
# ═══════════════════════════════════════════════════════════════════════

struct Block
    title::String
    title_style::Style
    border_style::Style
    box::NamedTuple
end

function Block(;
    title="",
    title_style=tstyle(:title, bold=true),
    border_style=tstyle(:border),
    box=BOX_ROUNDED,
)
    Block(title, title_style, border_style, box)
end

function inner_area(block::Block, rect::Rect)
    Rect(rect.x + 1, rect.y + 1,
         max(0, rect.width - 2), max(0, rect.height - 2))
end

function render(block::Block, rect::Rect, buf::Buffer)
    (rect.width < 2 || rect.height < 2) && return rect
    s = block.border_style
    b = block.box

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

    # Title (auto-padded with spaces for visual separation from border)
    if !isempty(block.title) && rect.width > 4
        tx = rect.x + 2
        set_string!(buf, tx, rect.y, " " * block.title * " ",
                    block.title_style)
    end

    inner_area(block, rect)
end
