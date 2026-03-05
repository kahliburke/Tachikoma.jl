# ═══════════════════════════════════════════════════════════════════════
# FloatingWindow + WindowManager ── overlapping draggable windows
#
# FloatingWindow is a positioned panel with a title bar, border, and
# arbitrary child content rendered via a user-supplied callback.
#
# WindowManager tracks a stack of FloatingWindows with z-order,
# focus cycling, and title-bar dragging.
#
# Usage:
#   wm = WindowManager()
#   push!(wm, FloatingWindow(title="Editor", x=5, y=3, width=40, height=15))
#   push!(wm, FloatingWindow(title="Log",    x=20, y=8, width=35, height=12))
#
#   # In view():
#   render(wm, area, buf)
#
#   # In update!():
#   handle_key!(wm, evt)   # F2/Tab to cycle, delegates to focused window
#   handle_mouse!(wm, evt) # click to focus, drag title bar to move
# ═══════════════════════════════════════════════════════════════════════

# ── FloatingWindow ────────────────────────────────────────────────────

"""
    FloatingWindow(; title, x, y, width, height, content=nothing, ...)

A positioned, bordered panel that can be rendered at arbitrary coordinates.
Supports animated borders, semi-transparency, and custom content via
either a `content` widget or an `on_render` callback.

- `content`: any widget with `render(widget, rect, buf)`
- `on_render`: `(inner::Rect, buf::Buffer, focused::Bool) -> nothing`
- `opacity`: 0.0 (fully transparent) to 1.0 (fully opaque, default)
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
    on_render::Union{Function,Nothing} # (inner, buf, focused) callback
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
    opacity::Float64=1.0,
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
    _blend_bg!(buf, rect, bg_color, opacity)

Blend background color with existing buffer content for transparency.
"""
function _blend_bg!(buf::Buffer, rect::Rect, bg::ColorRGB, opacity::Float64)
    for row in rect.y:bottom(rect)
        for col in rect.x:right(rect)
            in_bounds(buf, col, row) || continue
            i = buf_index(buf, col, row)
            cell = @inbounds buf.content[i]
            old_s = cell.style
            existing_bg = old_s.bg
            blended_bg = if existing_bg isa ColorRGB
                color_lerp(existing_bg, bg, opacity)
            elseif existing_bg isa Color256
                color_lerp(to_rgb(existing_bg), bg, opacity)
            else
                bg  # NoColor — just use our bg
            end
            # Dim foreground toward blended bg so underlying content fades
            blended_fg = if old_s.fg isa ColorRGB
                color_lerp(old_s.fg, blended_bg, opacity)
            elseif old_s.fg isa Color256
                color_lerp(to_rgb(old_s.fg), blended_bg, opacity)
            else
                old_s.fg
            end
            new_s = Style(fg=blended_fg, bg=blended_bg, bold=old_s.bold, dim=old_s.dim,
                          italic=old_s.italic, underline=old_s.underline)
            @inbounds buf.content[i] = Cell(cell.char, new_s)
        end
    end
end

function render(w::FloatingWindow, buf::Buffer;
                focused::Bool=false, tick::Int=0)
    w.visible || return
    wr = window_rect(w)

    # ── Background: opacity-blended or solid clear ──
    theme_bg = to_rgb(theme().bg)
    bg = something(w.bg_color, theme_bg)
    if w.opacity < 1.0
        _blend_bg!(buf, wr, bg, w.opacity)
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
        w.on_render(inner, buf, focused)
    elseif w.content !== nothing
        render(w.content, inner, buf)
    end
    nothing
end

# ── WindowManager ─────────────────────────────────────────────────────

"""
    WindowManager(; windows=FloatingWindow[])

Manages a stack of `FloatingWindow`s with z-order (last = topmost),
focus cycling, and mouse-based title-bar dragging.
"""
mutable struct WindowManager
    windows::Vector{FloatingWindow}
    focus::Int                     # index into windows (topmost = focused)
    # Drag state
    _dragging::Bool
    _drag_win::Int
    _drag_ox::Int
    _drag_oy::Int
    # Resize state
    _resizing::Bool
    _resize_win::Int
    _resize_corner::Symbol         # :br, :bl, :tr, :tl
    _resize_start_x::Int
    _resize_start_y::Int
    _resize_orig_x::Int
    _resize_orig_y::Int
    _resize_orig_w::Int
    _resize_orig_h::Int
    # Layout animation state
    _anim_tweens::Vector{NTuple{4, Tween}}  # per-window (x, y, w, h)
    _animating::Bool
    # Content mouse delegation state (for drag/move/release forwarding)
    _content_active::Bool
    _content_win::Int
end

function WindowManager(; windows::Vector{FloatingWindow}=FloatingWindow[])
    n = length(windows)
    WindowManager(windows, n > 0 ? n : 0, false, 0, 0, 0,
                  false, 0, :br, 0, 0, 0, 0, 0, 0,
                  NTuple{4, Tween}[], false,
                  false, 0)
end

focusable(::WindowManager) = true

"""Add a window to the top of the stack."""
function Base.push!(wm::WindowManager, w::FloatingWindow)
    push!(wm.windows, w)
    wm.focus = length(wm.windows)
    wm
end

"""Remove a window by index."""
function Base.deleteat!(wm::WindowManager, idx::Int)
    deleteat!(wm.windows, idx)
    wm.focus = clamp(wm.focus, 0, length(wm.windows))
    wm
end

"""Number of windows."""
Base.length(wm::WindowManager) = length(wm.windows)

"""Get the focused window, or nothing."""
focused_window(wm::WindowManager) = 0 < wm.focus <= length(wm.windows) ? wm.windows[wm.focus] : nothing

"""Bring window at `idx` to the front (top of z-order) and focus it."""
function bring_to_front!(wm::WindowManager, idx::Int)
    (idx < 1 || idx > length(wm.windows)) && return
    w = wm.windows[idx]
    deleteat!(wm.windows, idx)
    push!(wm.windows, w)
    wm.focus = length(wm.windows)
    nothing
end

"""Cycle focus to the next window and bring it to front."""
function focus_next!(wm::WindowManager)
    n = length(wm.windows)
    n == 0 && return
    # The focused window is always last (top of z-order).
    # "Next" means the bottom-most window (index 1) comes to front.
    n > 1 && bring_to_front!(wm, 1)
end

"""Cycle focus to the previous window and bring it to front."""
function focus_prev!(wm::WindowManager)
    n = length(wm.windows)
    n == 0 && return
    # "Previous" means the second-from-top (index n-1) comes to front.
    n > 1 && bring_to_front!(wm, n - 1)
end

# ── Render ────────────────────────────────────────────────────────────

"""
    render(wm::WindowManager, area::Rect, buf::Buffer; tick::Int=0)

Render all windows back-to-front within the given area.
Pass `tick` for animated borders on the focused window.
"""
function render(wm::WindowManager, area::Rect, buf::Buffer; tick::Int=0)
    advance_layout!(wm)
    for (i, w) in enumerate(wm.windows)
        render(w, buf; focused=(i == wm.focus), tick=tick)
    end
end

# ── Layout animation ─────────────────────────────────────────────────

"""Advance layout animation tweens, applying current values to windows."""
function advance_layout!(wm::WindowManager)
    wm._animating || return
    all_done = true
    for (i, tw4) in enumerate(wm._anim_tweens)
        i > length(wm.windows) && break
        w = wm.windows[i]
        w.x      = round(Int, value(tw4[1]))
        w.y      = round(Int, value(tw4[2]))
        w.width  = round(Int, value(tw4[3]))
        w.height = round(Int, value(tw4[4]))
        for tw in tw4
            advance!(tw)
            done(tw) || (all_done = false)
        end
    end
    if all_done
        wm._animating = false
        empty!(wm._anim_tweens)
    end
end

"""
    tile!(wm, area; animate=true, duration=15)

Arrange windows in a tiled grid layout. Animates smoothly when `animate=true`.
"""
function tile!(wm::WindowManager, area::Rect; animate::Bool=true, duration::Int=15)
    n = length(wm.windows)
    n == 0 && return
    cols = ceil(Int, sqrt(n))
    rows = ceil(Int, n / cols)
    cw = max(10, area.width ÷ cols)
    rh = max(5, (area.height - 1) ÷ rows)  # -1 for footer

    targets = NTuple{4, Int}[]
    for (i, _w) in enumerate(wm.windows)
        ci = mod(i - 1, cols)
        ri = (i - 1) ÷ cols
        tx = area.x + ci * cw
        ty = area.y + ri * rh
        tw = (ci == cols - 1) ? (area.width - ci * cw) : cw
        th = (ri == rows - 1) ? (area.height - 1 - ri * rh) : rh
        push!(targets, (tx, ty, tw, th))
    end

    if animate
        wm._anim_tweens = NTuple{4, Tween}[]
        for (i, w) in enumerate(wm.windows)
            t = targets[i]
            push!(wm._anim_tweens, (
                tween(w.x, t[1]; duration, easing=ease_out_cubic),
                tween(w.y, t[2]; duration, easing=ease_out_cubic),
                tween(w.width, t[3]; duration, easing=ease_out_cubic),
                tween(w.height, t[4]; duration, easing=ease_out_cubic),
            ))
        end
        wm._animating = true
    else
        for (i, w) in enumerate(wm.windows)
            t = targets[i]
            w.x, w.y, w.width, w.height = t
        end
    end
end

"""
    cascade!(wm, area; animate=true, duration=15)

Arrange windows in a cascading stack. Animates smoothly when `animate=true`.
"""
function cascade!(wm::WindowManager, area::Rect; animate::Bool=true, duration::Int=15)
    n = length(wm.windows)
    n == 0 && return
    step_x = 3
    step_y = 2
    max_w = max(10, area.width - step_x * (n - 1))
    max_h = max(5, (area.height - 1) - step_y * (n - 1))  # -1 for footer

    targets = NTuple{4, Int}[]
    for (i, _w) in enumerate(wm.windows)
        tx = area.x + (i - 1) * step_x
        ty = area.y + (i - 1) * step_y
        push!(targets, (tx, ty, max_w, max_h))
    end

    if animate
        wm._anim_tweens = NTuple{4, Tween}[]
        for (i, w) in enumerate(wm.windows)
            t = targets[i]
            push!(wm._anim_tweens, (
                tween(w.x, t[1]; duration, easing=ease_out_cubic),
                tween(w.y, t[2]; duration, easing=ease_out_cubic),
                tween(w.width, t[3]; duration, easing=ease_out_cubic),
                tween(w.height, t[4]; duration, easing=ease_out_cubic),
            ))
        end
        wm._animating = true
    else
        for (i, w) in enumerate(wm.windows)
            t = targets[i]
            w.x, w.y, w.width, w.height = t
        end
    end
end

# ── Keyboard ──────────────────────────────────────────────────────────

"""
    handle_key!(wm::WindowManager, evt::KeyEvent) → Bool

F2 → next window, F3 → previous. Tab/Shift+Tab pass through to content.
"""
function handle_key!(wm::WindowManager, evt::KeyEvent)::Bool
    if evt.key == :f2
        focus_next!(wm)
        return true
    elseif evt.key == :f3
        focus_prev!(wm)
        return true
    end
    w = focused_window(wm)
    w === nothing && return false
    if w.content !== nothing && applicable(handle_key!, w.content, evt)
        return handle_key!(w.content, evt)
    end
    false
end

# ── Mouse ─────────────────────────────────────────────────────────────

# Detect which corner of the window rect a point is on, or :none.
function _corner_at(wr::Rect, x::Int, y::Int)::Symbol
    rx = right(wr)
    by = bottom(wr)
    x == rx  && y == by  && return :br
    x == wr.x && y == by  && return :bl
    x == rx  && y == wr.y && return :tr
    x == wr.x && y == wr.y && return :tl
    return :none
end

function handle_mouse!(wm::WindowManager, evt::MouseEvent)::Bool
    if evt.action == mouse_release
        if wm._dragging
            wm._dragging = false
            return true
        end
        if wm._resizing
            wm._resizing = false
            return true
        end
        if wm._content_active && 0 < wm._content_win <= length(wm.windows)
            w = wm.windows[wm._content_win]
            wm._content_active = false
            if w.content !== nothing && applicable(handle_mouse!, w.content, evt)
                handle_mouse!(w.content, evt)
            end
            return true
        end
        return false
    end

    # ── Content drag/move forwarding ──
    if (evt.action == mouse_drag || evt.action == mouse_move) && wm._content_active && 0 < wm._content_win <= length(wm.windows)
        w = wm.windows[wm._content_win]
        if w.content !== nothing && applicable(handle_mouse!, w.content, evt)
            return handle_mouse!(w.content, evt)
        end
        return true
    end

    # ── Resize drag ──
    if evt.action == mouse_drag && wm._resizing && 0 < wm._resize_win <= length(wm.windows)
        w = wm.windows[wm._resize_win]
        dx = evt.x - wm._resize_start_x
        dy = evt.y - wm._resize_start_y
        c = wm._resize_corner
        if c == :br
            w.width  = max(w.min_width,  wm._resize_orig_w + dx)
            w.height = max(w.min_height, wm._resize_orig_h + dy)
        elseif c == :bl
            new_w = max(w.min_width, wm._resize_orig_w - dx)
            w.x = wm._resize_orig_x + (wm._resize_orig_w - new_w)
            w.width = new_w
            w.height = max(w.min_height, wm._resize_orig_h + dy)
        elseif c == :tr
            w.width  = max(w.min_width, wm._resize_orig_w + dx)
            new_h = max(w.min_height, wm._resize_orig_h - dy)
            w.y = wm._resize_orig_y + (wm._resize_orig_h - new_h)
            w.height = new_h
        elseif c == :tl
            new_w = max(w.min_width, wm._resize_orig_w - dx)
            new_h = max(w.min_height, wm._resize_orig_h - dy)
            w.x = wm._resize_orig_x + (wm._resize_orig_w - new_w)
            w.y = wm._resize_orig_y + (wm._resize_orig_h - new_h)
            w.width = new_w
            w.height = new_h
        end
        return true
    end

    # ── Move drag ──
    if evt.action == mouse_drag && wm._dragging && 0 < wm._drag_win <= length(wm.windows)
        w = wm.windows[wm._drag_win]
        w.x = max(1, evt.x - wm._drag_ox)
        w.y = max(1, evt.y - wm._drag_oy)
        return true
    end

    if evt.button == mouse_left && evt.action == mouse_press
        for i in length(wm.windows):-1:1
            w = wm.windows[i]
            w.visible || continue
            wr = window_rect(w)
            contains(wr, evt.x, evt.y) || continue

            bring_to_front!(wm, i)
            w_now = wm.windows[wm.focus]
            wr_now = window_rect(w_now)

            # ── Corner resize ──
            if w_now.resizable
                corner = _corner_at(wr_now, evt.x, evt.y)
                if corner != :none
                    wm._resizing = true
                    wm._resize_win = wm.focus
                    wm._resize_corner = corner
                    wm._resize_start_x = evt.x
                    wm._resize_start_y = evt.y
                    wm._resize_orig_x = w_now.x
                    wm._resize_orig_y = w_now.y
                    wm._resize_orig_w = w_now.width
                    wm._resize_orig_h = w_now.height
                    return true
                end
            end

            # ── Close button click ──
            if w_now.closeable && evt.y == w_now.y && evt.x == right(wr_now) - 2
                if w_now.on_close !== nothing
                    w_now.on_close()
                end
                return true
            end

            # ── Title bar drag ──
            if evt.y == w_now.y
                wm._dragging = true
                wm._drag_win = wm.focus
                wm._drag_ox = evt.x - w_now.x
                wm._drag_oy = evt.y - w_now.y
                return true
            end

            if w_now.content !== nothing && applicable(handle_mouse!, w_now.content, evt)
                if handle_mouse!(w_now.content, evt)
                    # Track content mouse state for drag/move/release forwarding
                    wm._content_active = true
                    wm._content_win = wm.focus
                    return true
                end
            end
            return true
        end
    end

    # ── Mouse move: forward to focused window's content for hover effects ──
    if evt.action == mouse_move && !wm._content_active
        w = focused_window(wm)
        if w !== nothing && w.content !== nothing && applicable(handle_mouse!, w.content, evt)
            wr = window_rect(w)
            if contains(wr, evt.x, evt.y)
                handle_mouse!(w.content, evt)
            end
        end
    end

    false
end
