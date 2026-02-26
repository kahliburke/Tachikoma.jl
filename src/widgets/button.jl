# ═══════════════════════════════════════════════════════════════════════
# Button ── clickable button with pulse animation
# ═══════════════════════════════════════════════════════════════════════

mutable struct Button
    label::String
    focused::Bool
    tick::Union{Int, Nothing}
    style::Style
    focused_style::Style
end

"""
    Button(label; focused=false, tick=nothing, ...)

Clickable button with optional pulse animation. Enter/Space to activate.
The caller handles the action (Elm architecture pattern).
"""
function Button(label::String;
    focused::Bool=false,
    tick::Union{Int, Nothing}=nothing,
    style::Style=tstyle(:text),
    focused_style::Style=tstyle(:accent, bold=true),
)
    Button(label, focused, tick, style, focused_style)
end

focusable(::Button) = true
intrinsic_size(btn::Button) = (length(btn.label) + 4, 1)

function handle_key!(btn::Button, evt::KeyEvent)::Bool
    btn.focused || return false
    if evt.key == :enter || (evt.key == :char && evt.char == ' ')
        return true  # caller handles the action (Elm pattern)
    end
    false
end

function render(btn::Button, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    display = string("[ ", btn.label, " ]")
    dlen = length(display)

    # Center horizontally and vertically
    pos = center(rect, dlen, 1)
    x, y = pos.x, pos.y

    s = btn.focused ? btn.focused_style : btn.style

    # Animated pulse when focused
    if btn.focused && btn.tick !== nothing && animations_enabled()
        base_fg = to_rgb(s.fg)
        p = pulse(btn.tick; period=60, lo=0.0, hi=0.25)
        anim_fg = brighten(base_fg, p)
        s = Style(fg=anim_fg, bold=s.bold)
    end

    set_string!(buf, x, y, display, s; max_x=right(rect))
end
