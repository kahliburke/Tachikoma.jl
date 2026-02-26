# ═══════════════════════════════════════════════════════════════════════
# TextArea ── multi-line text editor
# ═══════════════════════════════════════════════════════════════════════

mutable struct TextArea
    lines::Vector{Vector{Char}}
    cursor_row::Int                # 1-based
    cursor_col::Int                # 0-based (0 = before first char)
    scroll_offset::Int             # vertical scroll (0-based)
    label::String
    style::Style
    label_style::Style
    cursor_style::Style
    focused::Bool
    tick::Union{Int, Nothing}
end

"""
    TextArea(; text="", focused=false, tick=nothing, ...)

Multi-line text editor with line-based cursor movement and scrolling.
"""
function TextArea(;
    text::String="",
    label::String="",
    style::Style=tstyle(:text),
    label_style::Style=tstyle(:text_dim),
    cursor_style::Style=Style(; fg=Color256(0), bg=tstyle(:accent).fg),
    focused::Bool=true,
    tick::Union{Int, Nothing}=nothing,
)
    ls = [collect(l) for l in Base.split(text, '\n'; keepempty=true)]
    isempty(ls) && (ls = [Char[]])
    row = length(ls)
    col = length(ls[end])
    TextArea(ls, row, col, 0, label, style, label_style, cursor_style, focused, tick)
end

focusable(::TextArea) = true
value(w::TextArea) = text(w)
set_value!(w::TextArea, s::String) = set_text!(w, s)

# ── Helpers ──

function text(ta::TextArea)
    join(String.(ta.lines), '\n')
end

function clear!(ta::TextArea)
    empty!(ta.lines)
    push!(ta.lines, Char[])
    ta.cursor_row = 1
    ta.cursor_col = 0
    ta.scroll_offset = 0
end

function set_text!(ta::TextArea, s::String)
    ta.lines = [collect(l) for l in Base.split(s, '\n'; keepempty=true)]
    isempty(ta.lines) && push!(ta.lines, Char[])
    ta.cursor_row = length(ta.lines)
    ta.cursor_col = length(ta.lines[end])
    ta.scroll_offset = 0
end

# ── Key handling ──

function handle_key!(ta::TextArea, evt::KeyEvent)::Bool
    ta.focused || return false
    n = length(ta.lines)

    if evt.key == :char
        insert!(ta.lines[ta.cursor_row], ta.cursor_col + 1, evt.char)
        ta.cursor_col += 1
        return true
    elseif evt.key == :enter
        # Split line at cursor
        line = ta.lines[ta.cursor_row]
        left = line[1:ta.cursor_col]
        right_part = line[ta.cursor_col+1:end]
        ta.lines[ta.cursor_row] = left
        insert!(ta.lines, ta.cursor_row + 1, right_part)
        ta.cursor_row += 1
        ta.cursor_col = 0
        return true
    elseif evt.key == :backspace
        if ta.cursor_col > 0
            deleteat!(ta.lines[ta.cursor_row], ta.cursor_col)
            ta.cursor_col -= 1
        elseif ta.cursor_row > 1
            # Join with previous line
            prev_len = length(ta.lines[ta.cursor_row - 1])
            append!(ta.lines[ta.cursor_row - 1], ta.lines[ta.cursor_row])
            deleteat!(ta.lines, ta.cursor_row)
            ta.cursor_row -= 1
            ta.cursor_col = prev_len
        end
        return true
    elseif evt.key == :delete
        line = ta.lines[ta.cursor_row]
        if ta.cursor_col < length(line)
            deleteat!(line, ta.cursor_col + 1)
        elseif ta.cursor_row < length(ta.lines)
            # Join with next line
            append!(ta.lines[ta.cursor_row], ta.lines[ta.cursor_row + 1])
            deleteat!(ta.lines, ta.cursor_row + 1)
        end
        return true
    elseif evt.key == :left
        if ta.cursor_col > 0
            ta.cursor_col -= 1
        elseif ta.cursor_row > 1
            ta.cursor_row -= 1
            ta.cursor_col = length(ta.lines[ta.cursor_row])
        end
        return true
    elseif evt.key == :right
        line = ta.lines[ta.cursor_row]
        if ta.cursor_col < length(line)
            ta.cursor_col += 1
        elseif ta.cursor_row < length(ta.lines)
            ta.cursor_row += 1
            ta.cursor_col = 0
        end
        return true
    elseif evt.key == :up
        if ta.cursor_row > 1
            ta.cursor_row -= 1
            ta.cursor_col = min(ta.cursor_col, length(ta.lines[ta.cursor_row]))
        end
        return true
    elseif evt.key == :down
        if ta.cursor_row < length(ta.lines)
            ta.cursor_row += 1
            ta.cursor_col = min(ta.cursor_col, length(ta.lines[ta.cursor_row]))
        end
        return true
    elseif evt.key == :home
        ta.cursor_col = 0
        return true
    elseif evt.key == :end_key
        ta.cursor_col = length(ta.lines[ta.cursor_row])
        return true
    end
    false
end

# ── Render ──

function render(ta::TextArea, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    y_start = rect.y
    x_start = rect.x
    vis_width = rect.width
    vis_height = rect.height

    # Label takes first row if present
    if !isempty(ta.label)
        set_string!(buf, x_start, y_start, ta.label, ta.label_style;
                    max_x=right(rect))
        y_start += 1
        vis_height -= 1
    end
    vis_height < 1 && return

    # Auto-scroll to keep cursor visible
    if ta.cursor_row - 1 < ta.scroll_offset
        ta.scroll_offset = ta.cursor_row - 1
    elseif ta.cursor_row > ta.scroll_offset + vis_height
        ta.scroll_offset = ta.cursor_row - vis_height
    end

    # Animated cursor
    cur_style = ta.cursor_style
    if ta.focused && ta.tick !== nothing && animations_enabled()
        base_bg = to_rgb(cur_style.bg)
        br = breathe(ta.tick; period=70)
        cur_bg = brighten(base_bg, br * 0.25)
        cur_style = Style(fg=cur_style.fg, bg=cur_bg)
    end

    n = length(ta.lines)
    for vi in 1:vis_height
        li = ta.scroll_offset + vi
        li > n && break
        y = y_start + vi - 1
        line = ta.lines[li]

        # Horizontal scroll per line (keep cursor visible)
        h_offset = 0
        if li == ta.cursor_row && ta.cursor_col >= vis_width
            h_offset = ta.cursor_col - vis_width + 1
        end

        for ci in 1:vis_width
            char_idx = h_offset + ci
            x = x_start + ci - 1
            x > right(rect) && break

            is_cursor = ta.focused && li == ta.cursor_row &&
                        char_idx == ta.cursor_col + 1

            if char_idx >= 1 && char_idx <= length(line)
                ch = line[char_idx]
                set_char!(buf, x, y, ch, is_cursor ? cur_style : ta.style)
            elseif is_cursor
                set_char!(buf, x, y, ' ', cur_style)
            end
        end

        # Cursor at position 0 (before all text on this line)
        if ta.focused && li == ta.cursor_row && ta.cursor_col == 0 && h_offset == 0
            if !isempty(line)
                set_char!(buf, x_start, y, line[1], cur_style)
            else
                set_char!(buf, x_start, y, ' ', cur_style)
            end
        end
    end
end
