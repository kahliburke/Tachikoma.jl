# ═══════════════════════════════════════════════════════════════════════
# ResizableLayout ── mouse-dependent methods
# (struct and non-mouse helpers are in layout.jl)
# ═══════════════════════════════════════════════════════════════════════

function _handle_drag!(rl::ResizableLayout, evt::MouseEvent, pos::Int)
    drag = rl.drag

    # Swap-drag: Alt+drag pane onto another to swap
    if drag.status == drag_swap
        if evt.action == mouse_release
            target = _find_pane(rl, evt.x, evt.y)
            if target > 0 && target != drag.source_pane
                _swap_panes!(rl, drag.source_pane, target)
            end
            drag.status = drag_idle
            drag.source_pane = 0
            return true
        end
        evt.action == mouse_drag && return true  # consume drag events
        return false
    end

    # Normal resize drag
    if evt.action == mouse_drag && drag.status == drag_active
        delta = pos - drag.start_pos
        # Restore original constraint types/values from drag start, then apply
        # the absolute delta from start_pos. This avoids accumulating error from
        # stale rl.rects that haven't been re-split yet.
        for i in eachindex(rl.constraints)
            rl.constraints[i] = drag.start_constraints[i]
        end
        _apply_delta!(rl, drag.border_index, delta, drag.start_sizes)
        return true
    end
    if evt.action == mouse_release
        drag.status = drag_idle
        drag.border_index = 0
        return true
    end
    return false
end

function handle_resize!(rl::ResizableLayout, evt::MouseEvent)
    isempty(rl.rects) && return false

    pos = rl.direction == Horizontal ? evt.x : evt.y

    # Check that mouse is within the layout area
    if rl.direction == Horizontal
        (evt.y < rl.last_area.y || evt.y > bottom(rl.last_area)) && return false
    else
        (evt.x < rl.last_area.x || evt.x > right(rl.last_area)) && return false
    end

    # Active drag in progress (resize or swap)
    if rl.drag.status == drag_active || rl.drag.status == drag_swap
        return _handle_drag!(rl, evt, pos)
    end

    # Hover tracking
    if evt.action == mouse_move
        rl.hover_border = _find_border(rl, pos)
        return false  # hover doesn't consume events
    end

    # Right-click border → reset to original layout
    if evt.button == mouse_right && evt.action == mouse_press
        border = _find_border(rl, pos)
        if border > 0
            _reset_layout!(rl)
            return true
        end
    end

    if evt.button == mouse_left && evt.action == mouse_press
        border = _find_border(rl, pos)

        # Alt+click border → rotate direction
        if evt.alt && border > 0
            _rotate_direction!(rl)
            return true
        end

        # Alt+click pane → start swap-drag
        if evt.alt
            pane = _find_pane(rl, evt.x, evt.y)
            if pane > 0
                rl.drag = DragState(drag_swap, 0, pos,
                                    Int[], Constraint[], pane)
                return true
            end
        end

        # Normal drag on border → resize
        if border > 0
            rl.drag = DragState(drag_active, border, pos,
                               _current_sizes(rl), copy(rl.constraints), 0)
            return true
        end
    end

    return false
end

function render_resize_handles!(buf::Buffer, rl::ResizableLayout)
    isempty(rl.rects) && return
    active_idx = rl.drag.status == drag_active ? rl.drag.border_index : 0

    for i in 1:(length(rl.rects) - 1)
        is_active = (i == active_idx)
        is_hover = (i == rl.hover_border)
        (is_active || is_hover) || continue

        style = if is_active
            tstyle(:primary, bold=true)
        else
            tstyle(:accent)
        end

        if rl.direction == Horizontal
            bx = right(rl.rects[i])
            for by in rl.last_area.y:bottom(rl.last_area)
                set_char!(buf, bx, by, '│', style)
            end
        else
            by = bottom(rl.rects[i])
            for bx in rl.last_area.x:right(rl.last_area)
                set_char!(buf, bx, by, '─', style)
            end
        end
    end

    # Highlight source pane during swap-drag
    if rl.drag.status == drag_swap && rl.drag.source_pane > 0
        src = rl.drag.source_pane
        if src <= length(rl.rects)
            r = rl.rects[src]
            style = tstyle(:accent, bold=true)
            for bx in r.x:right(r)
                set_char!(buf, bx, r.y, '─', style)
                set_char!(buf, bx, bottom(r), '─', style)
            end
            for by in r.y:bottom(r)
                set_char!(buf, r.x, by, '│', style)
                set_char!(buf, right(r), by, '│', style)
            end
            set_char!(buf, r.x, r.y, '┌', style)
            set_char!(buf, right(r), r.y, '┐', style)
            set_char!(buf, r.x, bottom(r), '└', style)
            set_char!(buf, right(r), bottom(r), '┘', style)
        end
    end
    nothing
end
