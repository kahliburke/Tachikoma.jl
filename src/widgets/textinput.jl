# ═══════════════════════════════════════════════════════════════════════
# TextInput ── single-line text input with cursor and editing
# ═══════════════════════════════════════════════════════════════════════

mutable struct TextInput
    buffer::Vector{Char}           # current text content
    cursor::Int                    # 0 = before first char, length = after last
    label::String
    style::Style
    label_style::Style
    cursor_style::Style
    focused::Bool
    tick::Union{Int, Nothing}      # enables cursor breathing when set
    validator::Union{Function, Nothing}  # (String) -> Union{String, Nothing}
    error_msg::String
    error_style::Style
    last_area::Rect               # cached from last render for mouse hit testing
end

"""
    TextInput(; text="", focused=false, tick=nothing, validator=nothing, ...)

Single-line text input with cursor movement, clipboard, and optional validation.
The `validator` is a function `String → Union{String, Nothing}` — return an error
message or `nothing` if valid.
"""
function TextInput(;
    text="",
    label="",
    style=tstyle(:text),
    label_style=tstyle(:text_dim),
    cursor_style=Style(; fg=Color256(0), bg=tstyle(:accent).fg),
    focused=true,
    tick=nothing,
    validator=nothing,
    error_style=tstyle(:error),
)
    chars = collect(text)
    TextInput(chars, length(chars), label, style, label_style,
              cursor_style, focused, tick, validator, "", error_style, Rect())
end

# ── Helpers ──

# Display columns a single char occupies. Clamped to at least 1 so control or
# zero-width chars still advance the cursor by one cell instead of collapsing.
@inline _cw(ch::Char) = max(1, textwidth(ch))

text(input::TextInput) = String(input.buffer)

function clear!(input::TextInput)
    empty!(input.buffer)
    input.cursor = 0
end

function set_text!(input::TextInput, s::String)
    input.buffer = collect(s)
    input.cursor = length(input.buffer)
end

# ── Key handling ──

function _run_validator!(input::TextInput)
    if input.validator !== nothing
        result = input.validator(text(input))
        input.error_msg = result === nothing ? "" : result
    end
end

function handle_key!(input::TextInput, evt::KeyEvent)::Bool
    input.focused || return false

    if evt.key == :char
        input.cursor += 1
        insert!(input.buffer, input.cursor, evt.char)
        _run_validator!(input)
        return true
    elseif evt.key == :backspace
        if input.cursor > 0
            deleteat!(input.buffer, input.cursor)
            input.cursor -= 1
        end
        _run_validator!(input)
        return true
    elseif evt.key == :delete
        if input.cursor < length(input.buffer)
            deleteat!(input.buffer, input.cursor + 1)
        end
        _run_validator!(input)
        return true
    elseif evt.key == :left
        input.cursor = max(0, input.cursor - 1)
        return true
    elseif evt.key == :right
        input.cursor = min(length(input.buffer), input.cursor + 1)
        return true
    elseif evt.key == :home
        input.cursor = 0
        return true
    elseif evt.key == :end_key
        input.cursor = length(input.buffer)
        return true
    end
    return false
end

value(w::TextInput) = text(w)
set_value!(w::TextInput, s::String) = set_text!(w, s)
valid(w::TextInput) = isempty(w.error_msg)

function handle_mouse!(input::TextInput, evt::MouseEvent)::Bool
    if evt.button == mouse_left && evt.action == mouse_press
        r = input.last_area
        if r.width > 0 && contains(r, evt.x, evt.y)
            input.focused = true
            # Map the click column to a char index in display-column space,
            # accounting for the label and wide glyphs. Best-effort: horizontal
            # scroll isn't persisted, so this assumes the text starts unscrolled.
            target_col = evt.x - r.x - textwidth(input.label)
            cursor = 0
            col = 0
            for ch in input.buffer
                w = _cw(ch)
                target_col < col + w && break  # click lands on this glyph
                col += w
                cursor += 1
            end
            input.cursor = clamp(cursor, 0, length(input.buffer))
            return true
        end
    end
    false
end

# ── Render ──

function render(input::TextInput, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    input.last_area = rect
    y = rect.y

    # Render label
    cx = rect.x
    if !isempty(input.label)
        cx = set_string!(buf, cx, y, input.label, input.label_style)
    end

    # Available width for text area
    text_start = cx
    text_width = right(rect) - text_start + 1
    text_width < 1 && return

    # Animated cursor: breathe effect when focused and waiting
    cur_style = input.cursor_style
    if input.focused && input.tick !== nothing && animations_enabled()
        base_bg = to_rgb(cur_style.bg)
        br = breathe(input.tick; period=70)
        cur_bg = brighten(base_bg, br * 0.25)
        cur_style = Style(fg=cur_style.fg, bg=cur_bg)
    end

    # Horizontal scroll to keep the cursor visible. All measurements are in
    # DISPLAY COLUMNS (wide/CJK chars occupy 2), not character counts, so a
    # two-column glyph is never crammed into one cell.
    n = length(input.buffer)

    # Column at which the cursor sits (0-based, before any scrolling) and the
    # width of the cell it covers (the char to its right, or a trailing space).
    cursor_col = 0
    for i in 1:input.cursor
        cursor_col += _cw(input.buffer[i])
    end
    cursor_cell_w = input.cursor < n ? _cw(input.buffer[input.cursor + 1]) : 1

    # scroll_col: first visible display column (0-based). Scroll only as far as
    # needed to reveal the cursor cell at the right edge.
    scroll_col = 0
    if cursor_col + cursor_cell_w > text_width
        scroll_col = cursor_col + cursor_cell_w - text_width
    end

    # Render visible text, char by char, advancing by each glyph's width.
    col = 0  # display column of the current char (0-based, before scroll)
    for idx in 1:n
        ch = input.buffer[idx]
        w = _cw(ch)
        scol = col - scroll_col           # column within the text area (0-based)
        col += w
        # Fully scrolled off, on either side
        (scol + w <= 0 || scol >= text_width) && continue

        cx_pos = text_start + scol
        style = (input.focused && idx == input.cursor + 1) ? cur_style : input.style

        if w == 2 && scol >= 0 && scol + 2 <= text_width && cx_pos + 1 <= right(rect)
            # Wide glyph fully in view: lead cell + pad cell
            set_char!(buf, cx_pos, y, ch, style)
            set_char!(buf, cx_pos + 1, y, WIDE_CHAR_PAD, style)
        else
            # Width-1 char, or a wide glyph clipped by a scroll/area boundary:
            # draw a blank so the half-glyph doesn't corrupt the row.
            draw_x = max(cx_pos, text_start)
            draw_x <= right(rect) &&
                set_char!(buf, draw_x, y, w == 2 ? ' ' : ch, style)
        end
    end

    # Cursor sitting past the last char: block cursor on the trailing space.
    if input.focused && input.cursor == n
        scol = col - scroll_col
        if scol >= 0 && scol < text_width
            set_char!(buf, text_start + scol, y, ' ', cur_style)
        end
    end

    # Render validation error below if there's room
    if !isempty(input.error_msg) && rect.height > 1
        err_y = rect.y + 1
        set_string!(buf, rect.x, err_y, input.error_msg, input.error_style;
                    max_x=right(rect))
    end
end
