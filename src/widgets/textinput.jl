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
              cursor_style, focused, tick, validator, "", error_style)
end

# ── Helpers ──

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

# ── Render ──

function render(input::TextInput, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
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

    # Horizontal scroll to keep cursor visible
    n = length(input.buffer)
    # scroll_offset: first visible char index (0-based)
    scroll_offset = 0
    if input.cursor > text_width
        scroll_offset = input.cursor - text_width + 1
    end

    # Render visible text
    for i in 1:text_width
        char_idx = scroll_offset + i
        cx_pos = text_start + i - 1
        cx_pos > right(rect) && break

        if char_idx >= 1 && char_idx <= n
            ch = input.buffer[char_idx]
            if input.focused && char_idx == input.cursor + 1
                set_char!(buf, cx_pos, y, ch, cur_style)
            else
                set_char!(buf, cx_pos, y, ch, input.style)
            end
        elseif input.focused && char_idx == n + 1 &&
               input.cursor == n
            # Cursor at end of text: show block cursor on empty space
            set_char!(buf, cx_pos, y, ' ', cur_style)
        end
    end

    # Handle cursor at position 0 (before all text)
    if input.focused && input.cursor == 0 && scroll_offset == 0
        if n > 0
            set_char!(buf, text_start, y, input.buffer[1], cur_style)
        else
            set_char!(buf, text_start, y, ' ', cur_style)
        end
    end

    # Render validation error below if there's room
    if !isempty(input.error_msg) && rect.height > 1
        err_y = rect.y + 1
        set_string!(buf, rect.x, err_y, input.error_msg, input.error_style;
                    max_x=right(rect))
    end
end
