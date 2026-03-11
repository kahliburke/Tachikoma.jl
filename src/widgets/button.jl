# ═══════════════════════════════════════════════════════════════════════
# Button ── clickable button with pulse animation
# ═══════════════════════════════════════════════════════════════════════

mutable struct Button
    label::String
    focused::Bool
    tick::Union{Int, Nothing}
    style::Style
    focused_style::Style
    last_area::Rect               # cached from last render for mouse hit testing
    bordered::Bool                # render with full box border (3 rows)
    box::NamedTuple               # border style (BOX_ROUNDED, BOX_HEAVY, etc.)
    flash_remaining::Int          # frames of activation flash remaining (0 = none)
end

"""
    Button(label; focused=false, bordered=false, box=BOX_ROUNDED, ...)

Clickable button with optional pulse animation and optional box border.
Enter/Space or mouse click to activate.
The caller handles the action (Elm architecture pattern).

Set `bordered=true` for a full-border button (3 rows tall):
```
╭──────────╮
│  Label   │
╰──────────╯
```
"""
function Button(label::String;
    focused::Bool=false,
    tick::Union{Int, Nothing}=nothing,
    style::Style=tstyle(:text),
    focused_style::Style=tstyle(:accent, bold=true),
    bordered::Bool=false,
    box::NamedTuple=BOX_ROUNDED,
)
    Button(label, focused, tick, style, focused_style, Rect(), bordered, box, 0)
end

focusable(::Button) = true
intrinsic_size(btn::Button) = btn.bordered ? (length(btn.label) + 4, 3) : (length(btn.label) + 4, 1)

function handle_key!(btn::Button, evt::KeyEvent)::Bool
    btn.focused || return false
    if evt.key == :enter || (evt.key == :char && evt.char == ' ')
        btn.flash_remaining = 8
        return true  # caller handles the action (Elm pattern)
    end
    false
end

function handle_mouse!(btn::Button, evt::MouseEvent)::Bool
    if evt.button == mouse_left && evt.action == mouse_press
        r = btn.last_area
        if r.width > 0 && contains(r, evt.x, evt.y)
            btn.focused = true
            btn.flash_remaining = 8
            return true  # caller handles the action (Elm pattern)
        end
    end
    false
end

function render(btn::Button, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    s = btn.focused ? btn.focused_style : btn.style

    # Activation flash — bright inversion that fades out
    if btn.flash_remaining > 0
        btn.flash_remaining -= 1
        intensity = btn.flash_remaining / 8.0
        flash_fg = ColorRGB(0xff, 0xff, 0xff)
        flash_bg = ColorRGB(
            round(UInt8, 0x40 + 0x80 * intensity),
            round(UInt8, 0xc0 * intensity),
            round(UInt8, 0x40 * intensity),
        )
        s = Style(fg=flash_fg, bg=flash_bg, bold=true)
    elseif btn.focused && btn.tick !== nothing && animations_enabled()
        # Animated pulse when focused (no flash active)
        base_fg = to_rgb(s.fg)
        p = pulse(btn.tick; period=60, lo=0.0, hi=0.25)
        anim_fg = brighten(base_fg, p)
        s = Style(fg=anim_fg, bold=s.bold)
    end

    if btn.bordered && rect.height >= 3
        _render_bordered_button(btn, rect, buf, s)
    else
        _render_inline_button(btn, rect, buf, s)
    end
end

function _render_inline_button(btn::Button, rect::Rect, buf::Buffer, s::Style)
    display = string("[ ", btn.label, " ]")
    dlen = length(display)
    pos = center(rect, dlen, 1)
    btn.last_area = Rect(pos.x, pos.y, min(dlen, rect.width), 1)
    set_string!(buf, pos.x, pos.y, display, s; max_x=right(rect))
end

function _render_bordered_button(btn::Button, rect::Rect, buf::Buffer, s::Style)
    label = btn.label
    bx = btn.box
    label_len = length(label)
    # Button width: label + 2 padding + 2 border chars
    btn_w = min(label_len + 4, rect.width)
    btn_h = 3

    # Center the button in the rect
    pos = center(rect, btn_w, btn_h)
    x0 = pos.x
    y0 = pos.y
    x1 = x0 + btn_w - 1
    y1 = y0 + btn_h - 1

    # Update hit area to actual rendered button bounds (not the full layout rect)
    btn.last_area = Rect(x0, y0, btn_w, btn_h)

    border_s = s  # use same style for border as text

    # Read the existing (window-blended) bg from the buffer. This was set by
    # _blend_bg! before content renders, and is the correct bg for this cell.
    # We use it to explicitly fill the button area, which both clears any stale
    # flash/focus bg AND ensures seamless blending with the window.
    sample_bg = if in_bounds(buf, x0, y0)
        bg = @inbounds buf.content[buf_index(buf, x0, y0)].style.bg
        bg isa ColorRGB ? bg : nothing
    else
        nothing
    end

    # Fill background based on state
    if btn.flash_remaining > 0 && s.bg isa ColorRGB
        # Flash: fill entire button with flash bg
        bg_s = Style(bg=s.bg)
        for row in y0:y1
            for col in x0:x1
                in_bounds(buf, col, row) && set_char!(buf, col, row, ' ', bg_s)
            end
        end
        border_s = Style(fg=s.bg)
    elseif btn.focused
        # Focused: fill interior only, keep border in accent color
        accent_fg = to_rgb(tstyle(:accent).fg)
        theme_bg = to_rgb(theme().bg)
        bg_s = Style(bg=accent_fg)
        # Fill only the interior (inside the border)
        for col in (x0 + 1):(x1 - 1)
            in_bounds(buf, col, y0 + 1) && set_char!(buf, col, y0 + 1, ' ', bg_s)
        end
        # Label text: contrasting fg on accent bg
        s = Style(fg=theme_bg, bg=accent_fg, bold=true)
        # Border: accent fg, preserve existing bg for seamless blending
        border_s = Style(fg=accent_fg, bold=true)
    elseif sample_bg !== nothing
        # Unfocused: clear area with the window's blended bg to remove stale flash/focus fills
        bg_s = Style(bg=sample_bg)
        for row in y0:y1
            for col in x0:x1
                in_bounds(buf, col, row) && set_char!(buf, col, row, ' ', bg_s)
            end
        end
    end

    # Top border
    in_bounds(buf, x0, y0) && set_char!(buf, x0, y0, bx.tl, border_s)
    for col in (x0 + 1):(x1 - 1)
        in_bounds(buf, col, y0) && set_char!(buf, col, y0, bx.h, border_s)
    end
    in_bounds(buf, x1, y0) && set_char!(buf, x1, y0, bx.tr, border_s)

    # Middle row: │ label │
    in_bounds(buf, x0, y0 + 1) && set_char!(buf, x0, y0 + 1, bx.v, border_s)
    # Center label within the button
    label_x = x0 + max(1, (btn_w - label_len) ÷ 2)
    set_string!(buf, label_x, y0 + 1, label, s; max_x=x1 - 1)
    in_bounds(buf, x1, y0 + 1) && set_char!(buf, x1, y0 + 1, bx.v, border_s)

    # Bottom border
    in_bounds(buf, x0, y1) && set_char!(buf, x0, y1, bx.bl, border_s)
    for col in (x0 + 1):(x1 - 1)
        in_bounds(buf, col, y1) && set_char!(buf, col, y1, bx.h, border_s)
    end
    in_bounds(buf, x1, y1) && set_char!(buf, x1, y1, bx.br, border_s)
end
