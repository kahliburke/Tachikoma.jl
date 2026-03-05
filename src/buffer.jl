# ═══════════════════════════════════════════════════════════════════════
# Cell ── one character + style on the terminal grid
# ═══════════════════════════════════════════════════════════════════════

const EMPTY_CHAR = ' '
const WIDE_CHAR_PAD = '\0'   # sentinel for the trailing cell of a double-width character
const _ANSI_RE = r"\e(?:\[[?=>!]?[0-9;:]*[\x20-\x2f]*[A-Za-z@~]|\][^\x07\e]*(?:\x07|\e\\)|\([A-Za-z0-9]|[P^_][^\e]*\e\\|[A-Za-z0-9=<>])"
_strip_ansi(s::AbstractString) = contains(s, '\e') ? replace(s, _ANSI_RE => "") : s

struct Cell
    char::Char
    style::Style
end

Cell() = Cell(EMPTY_CHAR, RESET)

Base.:(==)(a::Cell, b::Cell) = (
    a.char == b.char && a.style == b.style
)

# ═══════════════════════════════════════════════════════════════════════
# Buffer ── 2D grid of cells, the framebuffer
# ═══════════════════════════════════════════════════════════════════════

mutable struct Buffer
    area::Rect
    content::Vector{Cell}
end

function Buffer(rect::Rect)
    n = max(0, area(rect))
    Buffer(rect, fill(Cell(), n))
end

@inline function buf_index(buf::Buffer, x::Int, y::Int)
    (y - buf.area.y) * buf.area.width + (x - buf.area.x) + 1
end

@inline function in_bounds(buf::Buffer, x::Int, y::Int)
    x >= buf.area.x && x <= right(buf.area) &&
    y >= buf.area.y && y <= bottom(buf.area)
end

function set!(buf::Buffer, x::Int, y::Int, cell::Cell)
    in_bounds(buf, x, y) || return
    @inbounds buf.content[buf_index(buf, x, y)] = cell
end

function set_char!(buf::Buffer, x::Int, y::Int, ch::Char,
                   style::Style=RESET)
    in_bounds(buf, x, y) || return
    # Clean up adjacent wide-char state before overwriting
    @inbounds begin
        i = buf_index(buf, x, y)
        old = buf.content[i]
        if old.char != WIDE_CHAR_PAD && textwidth(old.char) == 2
            # Overwriting the leading cell of a wide char → orphaned pad at x+1
            if in_bounds(buf, x + 1, y)
                j = buf_index(buf, x + 1, y)
                if buf.content[j].char == WIDE_CHAR_PAD
                    buf.content[j] = Cell(EMPTY_CHAR, buf.content[j].style)
                end
            end
        elseif old.char == WIDE_CHAR_PAD
            # Overwriting the pad cell → broken leading char at x-1
            if in_bounds(buf, x - 1, y)
                j = buf_index(buf, x - 1, y)
                buf.content[j] = Cell(EMPTY_CHAR, buf.content[j].style)
            end
        end
        buf.content[i] = Cell(ch, style)
    end
end

function set_string!(buf::Buffer, x::Int, y::Int,
                     str::AbstractString,
                     style::Style=RESET;
                     max_x::Int=right(buf.area))
    clean = _strip_ansi(str)
    col = x
    clip = min(max_x, right(buf.area))
    for ch in clean
        col > clip && break
        w = textwidth(ch)
        if w == 2
            if col + 1 > clip
                # Wide char at boundary — pad won't fit, place space instead
                in_bounds(buf, col, y) && set_char!(buf, col, y, EMPTY_CHAR, style)
                col += 1
                continue
            end
            in_bounds(buf, col, y) && set_char!(buf, col, y, ch, style)
            in_bounds(buf, col + 1, y) && set_char!(buf, col + 1, y, WIDE_CHAR_PAD, style)
        else
            in_bounds(buf, col, y) && set_char!(buf, col, y, ch, style)
        end
        col += max(w, 1)
    end
    col
end

function set_string!(buf::Buffer, x::Int, y::Int,
                     str::AbstractString, style::Style, area::Rect)
    set_string!(buf, x, y, str, style; max_x=right(area))
end

function set_style!(buf::Buffer, rect::Rect, style::Style)
    for row in rect.y:min(bottom(rect), bottom(buf.area))
        for col in rect.x:min(right(rect), right(buf.area))
            i = buf_index(buf, col, row)
            @inbounds buf.content[i] = Cell(
                buf.content[i].char, style,
            )
        end
    end
end

function reset!(buf::Buffer)
    fill!(buf.content, Cell())
end

function resize_buf!(buf::Buffer, new_area::Rect)
    buf.area = new_area
    n = max(0, area(new_area))
    Base.resize!(buf.content, n)
    fill!(buf.content, Cell())
end

"""
    buffer_to_text(buf::Buffer, rect::Rect) → String

Extract the visible text from a rectangular region of the buffer.
Trailing spaces on each line are stripped; trailing blank lines removed.
"""
function buffer_to_text(buf::Buffer, rect::Rect)
    lines = String[]
    for row in rect.y:min(bottom(rect), bottom(buf.area))
        chars = Char[]
        for col in rect.x:min(right(rect), right(buf.area))
            if in_bounds(buf, col, row)
                ch = buf.content[buf_index(buf, col, row)].char
                ch == WIDE_CHAR_PAD && continue   # skip trailing cell of wide chars
                push!(chars, ch)
            end
        end
        push!(lines, rstrip(String(chars)))
    end
    # Remove trailing blank lines
    while !isempty(lines) && isempty(lines[end])
        pop!(lines)
    end
    join(lines, '\n')
end
