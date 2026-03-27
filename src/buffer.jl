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
    suffix::String
end

Cell() = Cell(EMPTY_CHAR, RESET, "")
Cell(ch::Char, style::Style=RESET) = Cell(ch, style, "")
Cell(ch::Char, style::Style, suffix::AbstractString) = Cell(ch, style, String(suffix))

Base.:(==)(a::Cell, b::Cell) = (
    a.char == b.char && a.suffix == b.suffix && a.style == b.style
)

@inline function cell_glyph(c::Cell)
    return isempty(c.suffix) ? string(c.char) : string(c.char, c.suffix)
end

@inline function cell_width(c::Cell)
    return textwidth(cell_glyph(c))
end

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
    @inbounds begin
        i = buf_index(buf, x, y)
        old = buf.content[i]
        # Preserve existing cell bg when new style has no bg (NoColor).
        # Prevents "black fringe" inside semi-transparent FloatingWindows.
        if style.bg isa NoColor && !(old.style.bg isa NoColor)
            style = Style(fg=style.fg, bg=old.style.bg, bold=style.bold, dim=style.dim,
                          italic=style.italic, underline=style.underline)
        end
        # Clean up adjacent wide-char state before overwriting
        if old.char != WIDE_CHAR_PAD && cell_width(old) == 2
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

# Split a rendered glyph into its base character and any remaining suffix bytes.
#
# Returns `(EMPTY_CHAR, "")` for an empty input. For non-empty input, returns
# `(first_char, suffix)`, where `suffix` is the remaining substring after the
# first character, or `""` when no suffix is present.
@inline function _split_glyph(glyph::AbstractString)
    isempty(glyph) && return (EMPTY_CHAR, "")

    i  = firstindex(glyph)
    ch = glyph[i]
    ni = nextind(glyph, i)

    if ni <= lastindex(glyph)
        return (ch, String(SubString(glyph, ni, lastindex(glyph))))
    end

    return (ch, "")
end

# Write `glyph` at `(x, y)`, splitting it into a base char and suffix metadata.
#
# Does nothing when out of bounds. Preserves the existing background color when
# `style.bg` is `NoColor`, and clears neighboring wide-character pad/lead cells
# to keep buffer state consistent before writing the new cell.
function _set_glyph!(buf::Buffer, x::Int, y::Int, glyph::AbstractString,
                     style::Style=RESET)
    ch, suffix = _split_glyph(glyph)
    in_bounds(buf, x, y) || return
    @inbounds begin
        i = buf_index(buf, x, y)
        old = buf.content[i]
        if style.bg isa NoColor && !(old.style.bg isa NoColor)
            style = Style(fg=style.fg, bg=old.style.bg, bold=style.bold,
                          dim=style.dim, italic=style.italic,
                          underline=style.underline)
        end
        if old.char != WIDE_CHAR_PAD && cell_width(old) == 2
            if in_bounds(buf, x + 1, y)
                j = buf_index(buf, x + 1, y)
                if buf.content[j].char == WIDE_CHAR_PAD
                    buf.content[j] = Cell(EMPTY_CHAR, buf.content[j].style)
                end
            end
        elseif old.char == WIDE_CHAR_PAD
            if in_bounds(buf, x - 1, y)
                j = buf_index(buf, x - 1, y)
                buf.content[j] = Cell(EMPTY_CHAR, buf.content[j].style)
            end
        end
        buf.content[i] = Cell(ch, style, suffix)
    end
end

# Append `glyph` to the suffix of the cell at `(x, y)`.
#
# Used for zero-width/combining graphemes. If `(x, y)` points to a wide-char pad
# cell, this rewrites the wide-char lead cell instead; if no lead is available,
# the append is ignored.
function _append_glyph!(buf::Buffer, x::Int, y::Int, glyph::AbstractString)
    in_bounds(buf, x, y) || return
    @inbounds begin
        i = buf_index(buf, x, y)
        cell = buf.content[i]
        if cell.char == WIDE_CHAR_PAD && in_bounds(buf, x - 1, y)
            i = buf_index(buf, x - 1, y)
            cell = buf.content[i]
        end
        cell.char == WIDE_CHAR_PAD && return
        buf.content[i] = Cell(cell.char, cell.style, string(cell.suffix, glyph))
    end
end

function set_string!(buf::Buffer, x::Int, y::Int,
                     str::AbstractString,
                     style::Style=RESET;
                     max_x::Int=right(buf.area))
    clean = _strip_ansi(str)
    col = x
    last_drawn_col = x - 1
    clip = min(max_x, right(buf.area))
    for grapheme in Base.Unicode.graphemes(clean)
        glyph = String(grapheme)
        col > clip && break
        w = textwidth(glyph)
        if w == 0
            last_drawn_col >= x && _append_glyph!(buf, last_drawn_col, y, glyph)
            continue
        end
        if w == 2
            if col + 1 > clip
                # Wide char at boundary — pad won't fit, place space instead
                in_bounds(buf, col, y) && set_char!(buf, col, y, EMPTY_CHAR, style)
                col += 1
                continue
            end
            in_bounds(buf, col, y) && _set_glyph!(buf, col, y, glyph, style)
            in_bounds(buf, col + 1, y) && set_char!(buf, col + 1, y, WIDE_CHAR_PAD, style)
        else
            in_bounds(buf, col, y) && _set_glyph!(buf, col, y, glyph, style)
        end
        last_drawn_col = col
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
                buf.content[i].char, style, buf.content[i].suffix,
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
        chunks = String[]
        for col in rect.x:min(right(rect), right(buf.area))
            if in_bounds(buf, col, row)
                cell = buf.content[buf_index(buf, col, row)]
                ch = cell.char
                ch == WIDE_CHAR_PAD && continue   # skip trailing cell of wide chars
                push!(chunks, cell_glyph(cell))
            end
        end
        push!(lines, rstrip(join(chunks)))
    end
    # Remove trailing blank lines
    while !isempty(lines) && isempty(lines[end])
        pop!(lines)
    end
    join(lines, '\n')
end
