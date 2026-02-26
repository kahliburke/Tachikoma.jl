# ═══════════════════════════════════════════════════════════════════════
# Modal ── centered overlay dialog for confirmations
# ═══════════════════════════════════════════════════════════════════════

struct Modal
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
          confirm_style, cancel_style, dim_style, tick)
end

function render(modal::Modal, area::Rect, buf::Buffer)
    (area.width < 10 || area.height < 5) && return

    # Parse message lines
    lines = Base.split(modal.message, '\n')

    # Calculate modal dimensions
    msg_width = maximum(length.(lines); init=10)
    btn_width = length(modal.cancel_label) + length(modal.confirm_label) + 12
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

    cancel_str = "[ $(modal.cancel_label) ]"
    confirm_str = "[ $(modal.confirm_label) ]"
    total_btn_w = length(cancel_str) + 2 + length(confirm_str)
    btn_x = center(content, total_btn_w, 1).x

    # Animated selected button: gentle pulse
    cancel_s = modal.selected == :cancel ? modal.cancel_style : modal.dim_style
    confirm_s = modal.selected == :confirm ? modal.confirm_style : modal.dim_style

    if modal.tick !== nothing && animations_enabled()
        p = pulse(modal.tick; period=60, lo=0.0, hi=0.3)
        if modal.selected == :cancel
            fg = brighten(to_rgb(cancel_s.fg), p)
            cancel_s = Style(fg=fg, bold=true)
        else
            fg = brighten(to_rgb(confirm_s.fg), p)
            confirm_s = Style(fg=fg, bold=true)
        end
    end

    bx = set_string!(buf, btn_x, btn_y, cancel_str, cancel_s)
    set_string!(buf, bx + 2, btn_y, confirm_str, confirm_s)
end
