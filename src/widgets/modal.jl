# ═══════════════════════════════════════════════════════════════════════
# Modal ── centered overlay dialog for confirmations
# ═══════════════════════════════════════════════════════════════════════

mutable struct Modal
    title::String
    message::String                # can contain newlines
    confirm_label::String
    cancel_label::String
    selected::Symbol               # :confirm or :cancel
    border_style::Style
    title_style::Style
    text_style::Style
    confirm_style::Style           # when selected
    cancel_style::Style            # when selected
    dim_style::Style               # unselected button
    tick::Union{Int, Nothing}
    # Cached button hit areas (set during render)
    _cancel_rect::Rect
    _confirm_rect::Rect
end

function Modal(;
    title="Confirm",
    message="Are you sure?",
    confirm_label="OK",
    cancel_label="Cancel",
    selected=:cancel,
    border_style=tstyle(:warning, bold=true),
    title_style=tstyle(:warning, bold=true),
    text_style=tstyle(:text),
    confirm_style=tstyle(:error, bold=true),
    cancel_style=tstyle(:text_bright, bold=true),
    dim_style=tstyle(:text_dim),
    tick=nothing,
)
    Modal(title, message, confirm_label, cancel_label, selected,
          border_style, title_style, text_style,
          confirm_style, cancel_style, dim_style, tick,
          Rect(), Rect())
end

focusable(::Modal) = true

function render(modal::Modal, area::Rect, buf::Buffer)
    (area.width < 10 || area.height < 5) && return

    # Parse message lines
    lines = Base.split(modal.message, '\n')

    # Calculate modal dimensions
    msg_width = maximum(length.(lines); init=10)
    cancel_w = isempty(modal.cancel_label) ? 0 : length(modal.cancel_label) + 6  # "[ label ]"
    confirm_w = isempty(modal.confirm_label) ? 0 : length(modal.confirm_label) + 6
    btn_gap = (cancel_w > 0 && confirm_w > 0) ? 2 : 0
    btn_width = cancel_w + btn_gap + confirm_w
    inner_w = max(msg_width, btn_width, length(modal.title) + 4) + 4
    inner_h = length(lines) + 4  # title row + padding + message lines + padding + button row
    modal_w = min(inner_w + 2, area.width)  # +2 for border
    modal_h = min(inner_h + 2, area.height)

    # Center within area
    modal_rect = center(area, modal_w, modal_h)

    # Dim the background
    for row in area.y:bottom(area)
        for col in area.x:right(area)
            set_char!(buf, col, row, ' ', modal.dim_style)
        end
    end

    # Draw border — shimmer if tick is provided
    if modal.tick !== nothing && animations_enabled()
        border_shimmer!(buf, modal_rect, modal.border_style.fg,
                        modal.tick; box=BOX_HEAVY, intensity=0.12)
        # Title
        if !isempty(modal.title) && modal_rect.width > 4
            set_string!(buf, modal_rect.x + 2, modal_rect.y,
                        " $(modal.title) ", modal.title_style)
        end
        content = inner_area(Block(box=BOX_HEAVY), modal_rect)
    else
        block = Block(
            title="$(modal.title)",
            border_style=modal.border_style,
            title_style=modal.title_style,
            box=BOX_HEAVY,
        )
        content = render(block, modal_rect, buf)
    end
    (content.width < 1 || content.height < 1) && return

    # Clear interior
    for row in content.y:bottom(content)
        for col in content.x:right(content)
            set_char!(buf, col, row, ' ', RESET)
        end
    end

    # Render message lines
    msg_y = content.y + 1
    for (i, line) in enumerate(lines)
        y = msg_y + i - 1
        y > bottom(content) - 2 && break
        lx = center(content, length(line), 1).x
        set_string!(buf, lx, y, String(line), modal.text_style)
    end

    # Render buttons at bottom
    btn_y = bottom(content) - 1
    btn_y <= msg_y && return

    has_cancel = !isempty(modal.cancel_label)
    has_confirm = !isempty(modal.confirm_label)
    (!has_cancel && !has_confirm) && return

    cancel_str = has_cancel ? "[ $(modal.cancel_label) ]" : ""
    confirm_str = has_confirm ? "[ $(modal.confirm_label) ]" : ""
    gap = (has_cancel && has_confirm) ? 2 : 0
    total_btn_w = length(cancel_str) + gap + length(confirm_str)
    btn_x = center(content, total_btn_w, 1).x

    # Animated selected button: gentle pulse
    cancel_s = modal.selected == :cancel ? modal.cancel_style : modal.dim_style
    confirm_s = modal.selected == :confirm ? modal.confirm_style : modal.dim_style

    if modal.tick !== nothing && animations_enabled()
        p = pulse(modal.tick; period=60, lo=0.0, hi=0.3)
        if modal.selected == :cancel && has_cancel
            fg = brighten(to_rgb(cancel_s.fg), p)
            cancel_s = Style(fg=fg, bold=true)
        elseif modal.selected == :confirm && has_confirm
            fg = brighten(to_rgb(confirm_s.fg), p)
            confirm_s = Style(fg=fg, bold=true)
        end
    end

    bx = btn_x
    if has_cancel
        bx = set_string!(buf, btn_x, btn_y, cancel_str, cancel_s)
        modal._cancel_rect = Rect(btn_x, btn_y, length(cancel_str), 1)
    else
        modal._cancel_rect = Rect()
    end

    confirm_x = bx + gap
    if has_confirm
        set_string!(buf, confirm_x, btn_y, confirm_str, confirm_s)
        modal._confirm_rect = Rect(confirm_x, btn_y, length(confirm_str), 1)
    else
        modal._confirm_rect = Rect()
    end
end

# ── Key handling ─────────────────────────────────────────────────────

"""
    handle_key!(modal, evt) → Symbol

Handle key events for the modal. Returns:
- `:confirm` — user confirmed (Enter on confirm, or right-hand shortcut)
- `:cancel` — user cancelled (Escape, Enter on cancel)
- `:none` — key was handled but no decision yet (navigation)
- `false` — key was not handled
"""
function handle_key!(modal::Modal, evt::KeyEvent)
    if evt.key in (:left, :right, :tab, :backtab)
        modal.selected = modal.selected == :cancel ? :confirm : :cancel
        return :none
    elseif evt.key == :enter
        return modal.selected
    elseif evt.key == :escape
        return :cancel
    end
    false
end

# ── Mouse handling ───────────────────────────────────────────────────

"""
    handle_mouse!(modal, evt) → Symbol

Handle mouse events. Returns `:confirm`, `:cancel`, `:none`, or `false`.
Click on a button to select+confirm. Hover to highlight.
"""
function handle_mouse!(modal::Modal, evt::MouseEvent)
    on_cancel = Base.contains(modal._cancel_rect, evt.x, evt.y)
    on_confirm = Base.contains(modal._confirm_rect, evt.x, evt.y)

    if evt.button == mouse_left && evt.action == mouse_press
        if on_cancel
            modal.selected = :cancel
            return :cancel
        elseif on_confirm
            modal.selected = :confirm
            return :confirm
        end
    elseif evt.action == mouse_move
        if on_cancel
            modal.selected = :cancel
            return :none
        elseif on_confirm
            modal.selected = :confirm
            return :none
        end
    end
    false
end
