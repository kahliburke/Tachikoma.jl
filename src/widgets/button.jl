# ═══════════════════════════════════════════════════════════════════════
# Button ── clickable button with pulse animation
# ═══════════════════════════════════════════════════════════════════════

# ── Decoration types ──────────────────────────────────────────────────

"""
    ButtonDecoration

Abstract type for button rendering styles. Subtype this and implement
`_render_button!` to create custom button appearances.

Built-in decorations:
- `BracketButton()` — `[ Label ]` (default, 1 row)
- `BorderedButton()` — full box border (3 rows)
- `PlainButton()` — just the label text, no decoration
"""
abstract type ButtonDecoration end

"""
    BracketButton()

Default button style: `[ Label ]` with brackets. Single-line rendering.
"""
struct BracketButton <: ButtonDecoration end

"""
    BorderedButton(; box=BOX_ROUNDED)

Full box-bordered button (3 rows):
```
╭──────────╮
│  Label   │
╰──────────╯
```
"""
struct BorderedButton <: ButtonDecoration
    box::NamedTuple{(:tl, :tr, :bl, :br, :h, :v), NTuple{6, Char}}
end
BorderedButton(; box=BOX_ROUNDED) = BorderedButton(box)

"""
    PlainButton()

Plain text button with no bracket or border decoration. Styled text only.
"""
struct PlainButton <: ButtonDecoration end

# ── Button style struct ──────────────────────────────────────────────

"""
    ButtonStyle{D<:ButtonDecoration}

Visual configuration for a `Button`.

# Examples
```julia
ButtonStyle()                                        # default brackets
ButtonStyle(decoration=BorderedButton())             # rounded border
ButtonStyle(decoration=BorderedButton(box=BOX_HEAVY)) # heavy border
ButtonStyle(decoration=PlainButton())                # just text
```
"""
struct ButtonStyle{D<:ButtonDecoration}
    decoration::D
    normal::Style
    focused::Style
end

function ButtonStyle(;
    decoration::ButtonDecoration=BracketButton(),
    normal::Style=tstyle(:text),
    focused::Style=tstyle(:accent, bold=true),
)
    ButtonStyle(decoration, normal, focused)
end

"""How many rows this decoration needs."""
button_height(::ButtonDecoration) = 1
button_height(::BorderedButton) = 3

# ── Button widget ─────────────────────────────────────────────────────

mutable struct Button{D<:ButtonDecoration}
    label::String
    focused::Bool
    tick::Union{Int, Nothing}
    button_style::ButtonStyle{D}
    last_area::Rect
    flash_remaining::Int
    flash_frames::Int
    flash_style::Function
end

"""
    Button(label; focused=false, button_style=ButtonStyle(), flash_frames::Int=8, flash_style::Function=_default_button_flash_style, ...)

Clickable button with optional pulse animation.
Enter/Space or mouse click to activate.
The caller handles the action (Elm architecture pattern).
"""
function Button(label::String;
    focused::Bool=false,
    tick::Union{Int, Nothing}=nothing,
    button_style::ButtonStyle=ButtonStyle(),
    flash_frames::Int=8,
    flash_style::Function=_default_button_flash_style,
)
    Button(
        label,
        focused,
        tick,
        button_style,
        Rect(),
        0,
        flash_frames,
        flash_style
    )
end

focusable(::Button) = true

function intrinsic_size(btn::Button)
    dec = btn.button_style.decoration
    h = button_height(dec)
    w = dec isa BorderedButton ? length(btn.label) + 4 : length(btn.label) + 4
    (w, h)
end

function handle_key!(btn::Button, evt::KeyEvent)::Bool
    btn.focused || return false
    if evt.key == :enter || (evt.key == :char && evt.char == ' ')
        btn.flash_remaining = btn.flash_frames
        return true
    end
    false
end

function handle_mouse!(btn::Button, evt::MouseEvent)::Bool
    if evt.button == mouse_left && evt.action == mouse_press
        r = btn.last_area
        if r.width > 0 && contains(r, evt.x, evt.y)
            btn.focused = true
            btn.flash_remaining = btn.flash_frames
            return true
        end
    end
    false
end

# ── Render dispatch ───────────────────────────────────────────────────

function render(btn::Button, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    bs = btn.button_style
    s = btn.focused ? bs.focused : bs.normal

    # Activation flash
    if btn.flash_remaining > 0
        btn.flash_remaining -= 1
        s = btn.flash_style(btn)
    elseif btn.focused && btn.tick !== nothing && animations_enabled()
        base_fg = to_rgb(s.fg)
        p = pulse(btn.tick; period=60, lo=0.0, hi=0.25)
        anim_fg = brighten(base_fg, p)
        s = Style(fg=anim_fg, bold=s.bold)
    end

    _render_button!(btn, bs.decoration, rect, buf, s)
end

# ── BracketButton rendering (default) ────────────────────────────────

function _render_button!(btn::Button, ::BracketButton, rect::Rect, buf::Buffer, s::Style)
    display = string("[ ", btn.label, " ]")
    dlen = length(display)
    pos = center(rect, dlen, 1)
    btn.last_area = Rect(pos.x, pos.y, min(dlen, rect.width), 1)
    set_string!(buf, pos.x, pos.y, display, s; max_x=right(rect))
end

# ── PlainButton rendering ────────────────────────────────────────────

function _render_button!(btn::Button, ::PlainButton, rect::Rect, buf::Buffer, s::Style)
    label = btn.label
    llen = length(label)
    pos = center(rect, llen, 1)
    btn.last_area = Rect(pos.x, pos.y, min(llen, rect.width), 1)
    set_string!(buf, pos.x, pos.y, label, s; max_x=right(rect))
end

# ── BorderedButton rendering (3 rows) ────────────────────────────────

function _render_button!(btn::Button, dec::BorderedButton, rect::Rect, buf::Buffer, s::Style)
    rect.height < 3 && return _render_button!(btn, BracketButton(), rect, buf, s)

    label = btn.label
    bx = dec.box
    label_len = length(label)
    btn_w = min(label_len + 4, rect.width)
    btn_h = 3

    pos = center(rect, btn_w, btn_h)
    x0 = pos.x
    y0 = pos.y
    x1 = x0 + btn_w - 1
    y1 = y0 + btn_h - 1

    btn.last_area = Rect(x0, y0, btn_w, btn_h)

    border_s = s

    # Read existing blended bg from buffer
    sample_bg = if in_bounds(buf, x0, y0)
        bg = @inbounds buf.content[buf_index(buf, x0, y0)].style.bg
        bg isa ColorRGB ? bg : nothing
    else
        nothing
    end

    # Fill background based on state
    if btn.flash_remaining > 0 && s.bg isa ColorRGB
        bg_s = Style(bg=s.bg)
        for row in y0:y1
            for col in x0:x1
                in_bounds(buf, col, row) && set_char!(buf, col, row, ' ', bg_s)
            end
        end
        border_s = Style(fg=s.bg)
    elseif btn.focused
        accent_fg = to_rgb(tstyle(:accent).fg)
        theme_bg = to_rgb(theme().bg)
        bg_s = Style(bg=accent_fg)
        for col in (x0 + 1):(x1 - 1)
            in_bounds(buf, col, y0 + 1) && set_char!(buf, col, y0 + 1, ' ', bg_s)
        end
        s = Style(fg=theme_bg, bg=accent_fg, bold=true)
        border_s = Style(fg=accent_fg, bold=true)
    elseif sample_bg !== nothing
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

    # Middle row
    in_bounds(buf, x0, y0 + 1) && set_char!(buf, x0, y0 + 1, bx.v, border_s)
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

function _default_button_flash_style(btn::Button)
    intensity = clamp(btn.flash_remaining / btn.flash_frames, 0, 1)
    flash_fg = ColorRGB(0xff, 0xff, 0xff)
    flash_bg = ColorRGB(
        round(UInt8, 0x40 + 0x80 * intensity),
        round(UInt8, 0xc0 * intensity),
        round(UInt8, 0x40 * intensity),
    )
    Style(fg=flash_fg, bg=flash_bg, bold=true)
end
