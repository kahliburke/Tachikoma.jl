# ═══════════════════════════════════════════════════════════════════════
# WidgetScroll ── scrollable 2D viewport for any widget
# ═══════════════════════════════════════════════════════════════════════

mutable struct WidgetScroll
    widget::Any
    virtual_width::Int       # total width of the widget content
    virtual_height::Int      # total height of the widget content
    offset_x::Int            # horizontal scroll offset (0-based)
    offset_y::Int            # vertical scroll offset (0-based)
    block::Union{Block, Nothing}
    show_vertical_scrollbar::Bool
    show_horizontal_scrollbar::Bool
    dragging::Bool           # currently drag-panning
    drag_start_x::Int        # mouse x at drag start
    drag_start_y::Int        # mouse y at drag start
    drag_start_ox::Int       # offset_x at drag start
    drag_start_oy::Int       # offset_y at drag start
    _last_area::Rect         # cached for mouse hit testing
end

function WidgetScroll(widget; virtual_width::Int=0, virtual_height::Int=100,
                      block=nothing, show_vertical_scrollbar::Bool=true,
                      show_horizontal_scrollbar::Bool=false)
    WidgetScroll(widget, virtual_width, virtual_height, 0, 0,
                 block, show_vertical_scrollbar, show_horizontal_scrollbar,
                 false, 0, 0, 0, 0, Rect())
end

focusable(::WidgetScroll) = true
value(ws::WidgetScroll) = (ws.offset_x, ws.offset_y)

# Decide which scrollbars are actually needed given the viewport area.
function _scroll_needs(ws::WidgetScroll, area::Rect)
    vw = ws.virtual_width > 0 ? ws.virtual_width : area.width
    need_v = ws.show_vertical_scrollbar && (ws.virtual_height > area.height)
    need_h = ws.show_horizontal_scrollbar && (vw > area.width)
    content_h = area.height - (need_h ? 1 : 0)
    content_w = area.width  - (need_v ? 1 : 0)
    max_oy = max(0, ws.virtual_height - content_h)
    max_ox = max(0, vw - content_w)
    return need_v, need_h, content_h, content_w, max_oy, max_ox, vw
end

function handle_key!(ws::WidgetScroll, evt::KeyEvent)::Bool
    _, _, _, _, max_oy, max_ox, _ = _scroll_needs(ws, ws._last_area)
    if evt.key == :up
        ws.offset_y = max(0, ws.offset_y - 1); return true
    elseif evt.key == :down
        ws.offset_y = min(max_oy, ws.offset_y + 1); return true
    elseif evt.key == :left
        ws.offset_x = max(0, ws.offset_x - 2); return true
    elseif evt.key == :right
        ws.offset_x = min(max_ox, ws.offset_x + 2); return true
    elseif evt.key == :pageup
        ws.offset_y = max(0, ws.offset_y - 10); return true
    elseif evt.key == :pagedown
        ws.offset_y = min(max_oy, ws.offset_y + 10); return true
    elseif evt.key == :home
        ws.offset_x = 0; ws.offset_y = 0; return true
    elseif evt.key == :end_key
        ws.offset_y = max_oy; return true
    end
    # Forward to inner widget
    focusable(ws.widget) && return handle_key!(ws.widget, evt)
    return false
end

function handle_mouse!(ws::WidgetScroll, evt::MouseEvent)::Symbol
    area = ws._last_area
    inside = Base.contains(area, evt.x, evt.y)
    _, _, _, _, max_oy, max_ox, _ = _scroll_needs(ws, area)

    if inside && evt.button == mouse_scroll_up
        ws.offset_y = max(0, ws.offset_y - 3)
        return :scrolled
    elseif inside && evt.button == mouse_scroll_down
        ws.offset_y = min(max_oy, ws.offset_y + 3)
        return :scrolled
    elseif inside && evt.button == mouse_scroll_left
        ws.offset_x = max(0, ws.offset_x - 3)
        return :scrolled
    elseif inside && evt.button == mouse_scroll_right
        ws.offset_x = min(max_ox, ws.offset_x + 3)
        return :scrolled
    end

    # Click-drag panning
    if evt.button == mouse_left
        if evt.action == mouse_press && inside
            ws.dragging = true
            ws.drag_start_x = evt.x
            ws.drag_start_y = evt.y
            ws.drag_start_ox = ws.offset_x
            ws.drag_start_oy = ws.offset_y
            return :drag_start
        elseif evt.action == mouse_drag && ws.dragging
            dx = ws.drag_start_x - evt.x
            dy = ws.drag_start_y - evt.y
            ws.offset_x = clamp(ws.drag_start_ox + dx, 0, max_ox)
            ws.offset_y = clamp(ws.drag_start_oy + dy, 0, max_oy)
            return :dragging
        elseif evt.action == mouse_release && ws.dragging
            ws.dragging = false
            return :drag_end
        end
    end

    :none
end


function render(ws::WidgetScroll, rect::Rect, buf::Buffer)
    inner = if ws.block !== nothing
        render(ws.block, rect, buf)
    else
        rect
    end
    inner.width < 2 && return
    ws._last_area = inner

    # Virtual dimensions
    vh = max(ws.virtual_height, inner.height)
    vw = ws.virtual_width > 0 ? max(ws.virtual_width, inner.width) : inner.width

    need_v, need_h, content_h, content_w, max_oy, max_ox, _ =
        _scroll_needs(ws, inner)

    virt_rect = Rect(1, 1, vw, vh)
    virt_buf = Buffer(virt_rect)

    # Render widget into virtual buffer
    render(ws.widget, virt_rect, virt_buf)

    # Clamp offsets
    ws.offset_y = clamp(ws.offset_y, 0, max_oy)
    ws.offset_x = clamp(ws.offset_x, 0, max_ox)

    # Copy visible portion to real buffer
    for dy in 0:(content_h - 1)
        src_y = ws.offset_y + dy + 1
        dst_y = inner.y + dy
        src_y > vh && break
        for dx in 0:(content_w - 1)
            src_x = ws.offset_x + dx + 1
            dst_x = inner.x + dx
            src_x > vw && break
            si = buf_index(virt_buf, src_x, src_y)
            @inbounds cell = virt_buf.content[si]
            di = buf_index(buf, dst_x, dst_y)
            @inbounds buf.content[di] = cell
        end
    end

    # Vertical scrollbar (rightmost column, content rows only)
    if need_v && inner.width >= 2
        sb_x = right(inner)
        visible_ratio = content_h / vh
        bar_h = max(1, round(Int, visible_ratio * content_h))
        bar_pos = round(Int, (ws.offset_y / max(1, max_oy)) * (content_h - bar_h))
        for dy in 0:(content_h - 1)
            y = inner.y + dy
            in_thumb = dy >= bar_pos && dy < bar_pos + bar_h
            st = in_thumb ? tstyle(:border) : tstyle(:border, dim=true)
            set_char!(buf, sb_x, y, '█', st)
        end
    end

    # Horizontal scrollbar (last row, content columns only)
    if need_h && inner.height >= 2
        sb_y = inner.y + inner.height - 1
        bar_w = max(1, round(Int, (content_w / vw) * content_w))
        bar_pos = round(Int, (ws.offset_x / max(1, max_ox)) * (content_w - bar_w))
        for dx in 0:(content_w - 1)
            x = inner.x + dx
            in_thumb = dx >= bar_pos && dx < bar_pos + bar_w
            st = in_thumb ? tstyle(:border) : tstyle(:border, dim=true)
            set_char!(buf, x, sb_y, '🬋', st)
        end
    end
end
