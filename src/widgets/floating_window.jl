# ═══════════════════════════════════════════════════════════════════════
# FloatingWindow ── positioned bordered panel
#
# FloatingWindow is a positioned panel with a title bar, border, and
# arbitrary child content rendered via a user-supplied callback.
#
# Usage:
#   win = FloatingWindow(title="Editor", x=5, y=3, width=40, height=15)
#   render(win, buf; focused=true, tick=42)
# ═══════════════════════════════════════════════════════════════════════

# ── FloatingWindow ────────────────────────────────────────────────────

"""
    FloatingWindow(; title, x, y, width, height, content=nothing, ...)

A positioned, bordered panel that can be rendered at arbitrary coordinates.
Supports animated borders, semi-transparency, and custom content via
either a `content` widget or an `on_render` callback.

- `content`: any widget with `render(widget, rect, buf)`
- `on_render`: `(inner::Rect, buf::Buffer, focused::Bool, frame) -> nothing`
- `opacity`: 0.0 (fully transparent) to 1.0 (fully opaque); defaults to `WINDOW_OPACITY[]` (0.95)
- `border_color`: override border color (ColorRGB); `nothing` uses theme
- `bg_color`: override background color; `nothing` uses theme
"""
mutable struct FloatingWindow
    id::Symbol                         # unique identifier (stable across reordering)
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
    content::Any                       # widget with render(w, rect, buf), or nothing
    on_render::Union{Function,Nothing} # (inner, buf, focused[, frame]) callback
    box::NamedTuple
    visible::Bool
    minimized::Bool
    opacity::Float64                   # 0.0–1.0, blends bg with what's behind
    border_color::Union{ColorRGB,Nothing}
    bg_color::Union{ColorRGB,Nothing}
    resizable::Bool
    min_width::Int
    min_height::Int
    closeable::Bool                    # show ✕ button in title bar
    on_close::Union{Function,Nothing}  # () -> nothing, called when ✕ clicked
end

# Auto-incrementing ID counter for default IDs
const _FLOATING_WIN_COUNTER = Ref(0)

# ── Global window opacity preference ─────────────────────────────────

"""Global default opacity for new FloatingWindows (0.0–1.0)."""
const WINDOW_OPACITY = Ref(0.95)

function save_window_opacity!()
    @set_preferences!("window_opacity" => WINDOW_OPACITY[])
end

function load_window_opacity!()
    WINDOW_OPACITY[] = clamp(@load_preference("window_opacity", 0.95), 0.0, 1.0)
end

"""
    window_opacity() → Float64

Current global window opacity (0.0–1.0). New FloatingWindows use this as their default.
"""
window_opacity() = WINDOW_OPACITY[]

"""
    set_window_opacity!(v::Float64)

Set and persist the global window opacity.
"""
function set_window_opacity!(v::Float64)
    WINDOW_OPACITY[] = clamp(v, 0.0, 1.0)
    save_window_opacity!()
end

function FloatingWindow(;
    id::Symbol=Symbol("win_", _FLOATING_WIN_COUNTER[] += 1),
    title::String="",
    x::Int=1, y::Int=1,
    width::Int=30, height::Int=10,
    content=nothing,
    on_render::Union{Function,Nothing}=nothing,
    box::NamedTuple=BOX_ROUNDED,
    visible::Bool=true,
    minimized::Bool=false,
    opacity::Float64=WINDOW_OPACITY[],
    border_color::Union{ColorRGB,Nothing}=nothing,
    bg_color::Union{ColorRGB,Nothing}=nothing,
    resizable::Bool=true,
    min_width::Int=10,
    min_height::Int=5,
    closeable::Bool=false,
    on_close::Union{Function,Nothing}=nothing,
)
    FloatingWindow(id, title, x, y, width, height, content, on_render, box,
                   visible, minimized, clamp(opacity, 0.0, 1.0),
                   border_color, bg_color, resizable, min_width, min_height,
                   closeable, on_close)
end

focusable(::FloatingWindow) = true

"""Return the bounding Rect for this window."""
window_rect(w::FloatingWindow) = Rect(w.x, w.y, w.width, w.height)

"""
    _apply_window_opacity!(buf, rect, window_bg, opacity)

Apply semi-transparent window compositing to a buffer region.

Blends each cell's existing colors with the window's background color
according to `opacity` (0.0 = fully transparent, 1.0 = fully opaque):

- **Background**: lerps from existing bg toward `window_bg` by `opacity`.
  At 0.95, the result is 95% window bg + 5% existing (barely see-through).
- **Foreground**: lerps from existing fg toward the blended bg by `opacity`,
  fading underlying text proportionally so it doesn't float at full brightness
  against the composited background.

Only called when `opacity < 1.0`; at full opacity the caller does a solid fill.
"""
function _apply_window_opacity!(buf::Buffer, rect::Rect, window_bg::ColorRGB, opacity::Float64)
    for row in rect.y:bottom(rect)
        for col in rect.x:right(rect)
            in_bounds(buf, col, row) || continue
            i = buf_index(buf, col, row)
            cell = @inbounds buf.content[i]
            old_s = cell.style

            # Composite background: blend existing → window_bg by opacity
            existing_bg = old_s.bg
            composited_bg = if existing_bg isa ColorRGB
                color_lerp(existing_bg, window_bg, opacity)
            elseif existing_bg isa Color256
                color_lerp(to_rgb(existing_bg), window_bg, opacity)
            else
                window_bg  # NoColor — just use window bg
            end

            # Fade foreground: dim underlying text toward composited bg
            composited_fg = if old_s.fg isa ColorRGB
                color_lerp(old_s.fg, composited_bg, opacity)
            elseif old_s.fg isa Color256
                color_lerp(to_rgb(old_s.fg), composited_bg, opacity)
            else
                old_s.fg
            end

            new_s = Style(fg=composited_fg, bg=composited_bg)
            @inbounds buf.content[i] = Cell(' ', new_s)
        end
    end
end

function render(w::FloatingWindow, buf::Buffer;
                focused::Bool=false, tick::Int=0, frame=nothing)
    w.visible || return
    wr = window_rect(w)

    # ── Background: opacity-blended or solid clear ──
    theme_bg = to_rgb(theme().bg)
    bg = something(w.bg_color, theme_bg)
    if w.opacity < 1.0
        _apply_window_opacity!(buf, wr, bg, w.opacity)
    else
        bg_s = Style(bg=bg)
        for row in wr.y:bottom(wr)
            for col in wr.x:right(wr)
                set_char!(buf, col, row, ' ', bg_s)
            end
        end
    end

    # ── Border: shimmer when focused, static otherwise ──
    bc = something(w.border_color, to_rgb(tstyle(focused ? :accent : :border).fg))
    if focused && tick > 0 && animations_enabled()
        border_shimmer!(buf, wr, bc, tick; box=w.box, intensity=0.2)
    else
        block = Block(title="", border_style=Style(fg=bc), box=w.box)
        render(block, wr, buf)
    end

    # ── Title ──
    if !isempty(w.title) && wr.width > 4
        title_fg = focused ? brighten(bc, 0.3) : bc
        tx = wr.x + 2
        # Title decoration: ├ TITLE ┤
        in_bounds(buf, tx - 1, wr.y) && set_char!(buf, tx - 1, wr.y, '┤', Style(fg=bc))
        title_end = set_string!(buf, tx, wr.y, " $(w.title) ", Style(fg=title_fg, bold=focused))
        in_bounds(buf, title_end, wr.y) && set_char!(buf, title_end, wr.y, '├', Style(fg=bc))
    end

    # ── Close button ──
    if w.closeable && wr.width > 6
        cx = right(wr) - 2
        close_fg = focused ? ColorRGB(0xf0, 0x60, 0x60) : dim_color(ColorRGB(0xf0, 0x60, 0x60), 0.5)
        in_bounds(buf, cx, wr.y) && set_char!(buf, cx, wr.y, '✕', Style(fg=close_fg, bold=true))
    end

    inner = Rect(wr.x + 1, wr.y + 1, max(0, wr.width - 2), max(0, wr.height - 2))
    (inner.width < 1 || inner.height < 1) && return

    # ── Content ──
    if w.on_render !== nothing
        # on_render receives (inner, buf, focused, frame) where frame may be nothing
        w.on_render(inner, buf, focused, frame)
    elseif w.content !== nothing
        render(w.content, inner, buf)
    end
    nothing
end
