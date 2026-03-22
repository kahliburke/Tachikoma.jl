# ═══════════════════════════════════════════════════════════════════════
# WindowManager ── z-order, focus, drag/resize, and layout for windows
# ═══════════════════════════════════════════════════════════════════════

# ── WindowManager ─────────────────────────────────────────────────────

"""
    WindowManager(; windows=FloatingWindow[], focus_shortcuts=true)

Manages a stack of `FloatingWindow`s with z-order (last = topmost),
focus cycling, and mouse-based title-bar dragging.

    By default, focus shortcuts are enabled so the manager consumes
    Ctrl+J / Ctrl+K for next/previous focus. Set `focus_shortcuts=false`
    to keep all focus keys in content widgets.
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
    focus_shortcuts::Bool
    _tick::Int
    last_area::Rect
end

function WindowManager(; windows::Vector{FloatingWindow}=FloatingWindow[], focus_shortcuts::Bool=true)
    n = length(windows)
    WindowManager(windows, n > 0 ? n : 0, false, 0, 0, 0,
                  false, 0, :br, 0, 0, 0, 0, 0, 0,
                  NTuple{4, Tween}[], false,
                  false, 0, focus_shortcuts, 0, Rect())
end

"""Current internal tick counter for per-frame/window-manager updates."""
tick(wm::WindowManager) = wm._tick

"""
    step!(wm::WindowManager, area::Union{Rect, Nothing}=nothing;
          layout_interval::Int=0, layout_tile_at::Int=1, layout_cascade_at::Int=23,
          layout_animate::Bool=true, layout_duration::Int=12) -> Int

Advance the WM tick by one and optionally run automatic layout changes.

If `layout_interval > 0`, every frame advances an internal phase from
`1:layout_interval` and:
- at `layout_tile_at`, `tile!(wm, area)`
- at `layout_cascade_at`, `cascade!(wm, area)`

Return the updated tick count.
"""
function step!(wm::WindowManager, area::Union{Rect, Nothing}=nothing;
               layout_interval::Int=0, layout_tile_at::Int=1,
               layout_cascade_at::Int=23, layout_animate::Bool=true,
               layout_duration::Int=12)
    wm._tick += 1
    if layout_interval > 0 && area !== nothing
        phase = mod1(wm._tick, layout_interval)
        if phase == layout_tile_at
            tile!(wm, area; animate=layout_animate, duration=layout_duration)
        elseif phase == layout_cascade_at
            cascade!(wm, area; animate=layout_animate, duration=layout_duration)
        end
    end
    return wm._tick
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
    render(wm::WindowManager, area::Rect, buf::Buffer; tick=nothing)

Render all windows back-to-front within the given area.
If omitted, `tick` defaults to the manager's internal tick counter.
"""
function render(wm::WindowManager, area::Rect, buf::Buffer; tick::Union{Int, Nothing}=nothing, frame=nothing)
    wm.last_area = area
    advance_layout!(wm)
    tick = tick === nothing ? wm._tick : tick
    for (i, w) in enumerate(wm.windows)
        render(w, buf; focused=(i == wm.focus), tick=tick, frame=frame)
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

# Convenience methods using last_area (no-op if render hasn't run yet)
tile!(wm::WindowManager; kwargs...) = wm.last_area.width > 0 && tile!(wm, wm.last_area; kwargs...)
cascade!(wm::WindowManager; kwargs...) = wm.last_area.width > 0 && cascade!(wm, wm.last_area; kwargs...)

# ── Keyboard ──────────────────────────────────────────────────────────

"""
    handle_event!(wm::WindowManager, evt::Event) → Bool

    Dispatch keyboard and mouse events to WindowManager-owned handlers.
"""
function handle_event!(wm::WindowManager, evt::Event)::Bool
    evt isa KeyEvent && return handle_key!(wm, evt)
    evt isa MouseEvent && return handle_mouse!(wm, evt)
    false
end

"""
    handle_key!(wm::WindowManager, evt::KeyEvent) → Bool

    Ctrl+J cycles focus to the next window, Ctrl+K to the previous.
    Works on all terminals — no Kitty protocol required.
    Only consumed when `focus_shortcuts=true`; otherwise passes through.
"""
function handle_key!(wm::WindowManager, evt::KeyEvent)::Bool
    if wm.focus_shortcuts && evt.key == :ctrl && evt.char == 'j'
        focus_next!(wm)
        return true
    end
    if wm.focus_shortcuts && evt.key == :ctrl && evt.char == 'k'
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
        if wm._content_active
            if 0 < wm._content_win <= length(wm.windows)
                w = wm.windows[wm._content_win]
                if w.content !== nothing && applicable(handle_mouse!, w.content, evt)
                    handle_mouse!(w.content, evt)
                end
            end
            wm._content_active = false
            wm._content_win = 0
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

    # ── Scroll wheel: forward to topmost window content under cursor ──
    if evt.action == mouse_press &&
       (evt.button == mouse_scroll_up || evt.button == mouse_scroll_down)
        for i in length(wm.windows):-1:1
            w = wm.windows[i]
            w.visible || continue
            wr = window_rect(w)
            contains(wr, evt.x, evt.y) || continue

            bring_to_front!(wm, i)
            w_now = wm.windows[wm.focus]
            if w_now.content !== nothing && applicable(handle_mouse!, w_now.content, evt)
                return handle_mouse!(w_now.content, evt)
            end
            return true
        end
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
