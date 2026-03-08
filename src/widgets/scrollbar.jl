# ═══════════════════════════════════════════════════════════════════════
# Scrollbar ── vertical scroll position indicator
# ═══════════════════════════════════════════════════════════════════════

# ── ScrollbarState ── shared mouse-drag tracking ────────────────────

"""
    ScrollbarState()

Tracks scrollbar geometry and drag state for mouse interaction.
Embed in any scrollable widget and call [`handle_scrollbar_mouse!`](@ref)
from your `handle_mouse!` method.

Update `state.rect` during rendering to the scrollbar's bounding `Rect`.
"""
mutable struct ScrollbarState
    rect::Rect        # set during render
    dragging::Bool
end
ScrollbarState() = ScrollbarState(Rect(), false)

"""
    handle_scrollbar_mouse!(state, evt) → Union{Float64, Nothing}

Handle scrollbar click/drag events. Returns a scroll fraction (0.0–1.0)
when the scrollbar was interacted with, or `nothing` if the event was
not a scrollbar interaction. The caller maps the fraction to its own
offset model.

Returns `nothing` (not a fraction) on drag release — the caller should
still return `true` to consume the event.

# Usage

    frac = handle_scrollbar_mouse!(state, evt)
    if frac !== nothing
        my_offset = round(Int, frac * max_offset)
        return true
    elseif state.dragging  # release event
        return false       # already consumed above
    end
"""
function handle_scrollbar_mouse!(state::ScrollbarState, evt::MouseEvent)
    # Drag release
    if evt.action == mouse_release && state.dragging
        state.dragging = false
        return nothing
    end

    # Drag motion
    if (evt.action == mouse_drag || evt.action == mouse_move) && state.dragging
        state.rect.height > 0 || return nothing
        return clamp((evt.y - state.rect.y) / state.rect.height, 0.0, 1.0)
    end

    # Click to start drag
    if evt.button == mouse_left && evt.action == mouse_press &&
       state.rect.width > 0 && Base.contains(state.rect, evt.x, evt.y)
        state.dragging = true
        return clamp((evt.y - state.rect.y) / max(1, state.rect.height), 0.0, 1.0)
    end

    nothing
end

# ── Scrollbar ── rendering ──────────────────────────────────────────

struct Scrollbar
    total::Int                     # total items
    visible::Int                   # visible items
    offset::Int                    # scroll offset (0-based)
    style::Style                   # track style
    thumb_style::Style             # thumb style
end

function Scrollbar(total::Int, visible::Int, offset::Int;
    style=tstyle(:text_dim, dim=true),
    thumb_style=tstyle(:primary),
)
    Scrollbar(total, visible, max(0, offset), style, thumb_style)
end

function render(sb::Scrollbar, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return
    sb.total <= sb.visible && return  # no scroll needed

    h = rect.height
    x = rect.x

    # Thumb size and position
    thumb_h = max(1, round(Int, h * sb.visible / sb.total))
    max_offset = sb.total - sb.visible
    thumb_pos = max_offset > 0 ?
        round(Int, (h - thumb_h) * sb.offset / max_offset) : 0

    for row in 0:(h - 1)
        y = rect.y + row
        if row >= thumb_pos && row < thumb_pos + thumb_h
            set_char!(buf, x, y, '█', sb.thumb_style)
        else
            set_char!(buf, x, y, '│', sb.style)
        end
    end
end
