# ═══════════════════════════════════════════════════════════════════════
# BigText ── large block-character font renderer
#
# Each glyph is 3 columns wide × 5 rows tall, using █ and spaces.
# Glyphs are packed as 5-element tuples of 3-char strings.
# Supports 0-9, A-Z, colon, period, dash, space.
# ═══════════════════════════════════════════════════════════════════════

const BIGTEXT_GLYPHS = Dict{Char, NTuple{5, String}}(
    '0' => ("███", "█ █", "█ █", "█ █", "███"),
    '1' => (" █ ", "██ ", " █ ", " █ ", "███"),
    '2' => ("███", "  █", "███", "█  ", "███"),
    '3' => ("███", "  █", "███", "  █", "███"),
    '4' => ("█ █", "█ █", "███", "  █", "  █"),
    '5' => ("███", "█  ", "███", "  █", "███"),
    '6' => ("███", "█  ", "███", "█ █", "███"),
    '7' => ("███", "  █", "  █", "  █", "  █"),
    '8' => ("███", "█ █", "███", "█ █", "███"),
    '9' => ("███", "█ █", "███", "  █", "███"),
    ':' => ("   ", " █ ", "   ", " █ ", "   "),
    '.' => ("   ", "   ", "   ", "   ", " █ "),
    '-' => ("   ", "   ", "███", "   ", "   "),
    ' ' => ("   ", "   ", "   ", "   ", "   "),
    'A' => ("███", "█ █", "███", "█ █", "█ █"),
    'B' => ("██ ", "█ █", "██ ", "█ █", "██ "),
    'C' => ("███", "█  ", "█  ", "█  ", "███"),
    'D' => ("██ ", "█ █", "█ █", "█ █", "██ "),
    'E' => ("███", "█  ", "███", "█  ", "███"),
    'F' => ("███", "█  ", "██ ", "█  ", "█  "),
    'G' => ("███", "█  ", "█ █", "█ █", "███"),
    'H' => ("█ █", "█ █", "███", "█ █", "█ █"),
    'I' => ("███", " █ ", " █ ", " █ ", "███"),
    'J' => ("███", "  █", "  █", "█ █", "███"),
    'K' => ("█ █", "██ ", "█  ", "██ ", "█ █"),
    'L' => ("█  ", "█  ", "█  ", "█  ", "███"),
    'M' => ("█ █", "███", "███", "█ █", "█ █"),
    'N' => ("█ █", "███", "███", "█ █", "█ █"),
    'O' => ("███", "█ █", "█ █", "█ █", "███"),
    'P' => ("███", "█ █", "███", "█  ", "█  "),
    'Q' => ("███", "█ █", "█ █", "███", "  █"),
    'R' => ("███", "█ █", "██ ", "█ █", "█ █"),
    'S' => ("███", "█  ", "███", "  █", "███"),
    'T' => ("███", " █ ", " █ ", " █ ", " █ "),
    'U' => ("█ █", "█ █", "█ █", "█ █", "███"),
    'V' => ("█ █", "█ █", "█ █", "█ █", " █ "),
    'W' => ("█ █", "█ █", "███", "███", "█ █"),
    'X' => ("█ █", "█ █", " █ ", "█ █", "█ █"),
    'Y' => ("█ █", "█ █", "███", " █ ", " █ "),
    'Z' => ("███", "  █", " █ ", "█  ", "███"),
)

const BIGTEXT_GLYPH_W = 3   # chars per glyph column
const BIGTEXT_GLYPH_H = 5   # rows per glyph
const BIGTEXT_GAP = 1        # gap between glyphs

struct BigText
    text::String
    style::Style
    fill_char::Char            # character used for filled pixels
    style_fn::Union{Nothing, Function}  # (x, y) -> Style, overrides style if set
end

function BigText(text::String;
    style=tstyle(:primary, bold=true),
    fill_char='█',
    style_fn=nothing,
)
    BigText(uppercase(text), style, fill_char, style_fn)
end

"""Return (width, height) in terminal cells for this BigText widget."""
function intrinsic_size(bt::BigText)
    n = length(bt.text)
    w = n == 0 ? 0 : n * (BIGTEXT_GLYPH_W + BIGTEXT_GAP) - BIGTEXT_GAP
    (w, BIGTEXT_GLYPH_H)
end

function render(bt::BigText, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < BIGTEXT_GLYPH_H) && return

    cx = rect.x
    for ch in bt.text
        glyph = get(BIGTEXT_GLYPHS, ch, nothing)
        glyph === nothing && continue

        cx + BIGTEXT_GLYPH_W - 1 > right(rect) && break

        for row in 1:BIGTEXT_GLYPH_H
            y = rect.y + row - 1
            y > bottom(rect) && break
            chars = collect(glyph[row])
            for col in 1:min(BIGTEXT_GLYPH_W, length(chars))
                x = cx + col - 1
                if chars[col] == '█'
                    s = bt.style_fn !== nothing ? bt.style_fn(x - rect.x, y - rect.y) : bt.style
                    set_char!(buf, x, y, bt.fill_char, s)
                end
            end
        end
        cx += BIGTEXT_GLYPH_W + BIGTEXT_GAP
    end
end
