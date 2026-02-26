# ═══════════════════════════════════════════════════════════════════════
# ProgressList ── task list with status indicators
#
# Each item has a status: :pending, :running, :done, :error, :skipped.
# Running items show animated spinners. Done shows ✓, error shows ✗.
# ═══════════════════════════════════════════════════════════════════════

@enum TaskStatus task_pending task_running task_done task_error task_skipped

struct ProgressItem
    label::String
    status::TaskStatus
    detail::String             # optional right-aligned detail text
end

ProgressItem(label; status=task_pending, detail="") =
    ProgressItem(label, status, detail)

struct ProgressList
    items::Vector{ProgressItem}
    tick::Union{Int, Nothing}  # for spinner animation
    block::Union{Block, Nothing}
    pending_style::Style
    running_style::Style
    done_style::Style
    error_style::Style
    skipped_style::Style
    label_style::Style
    detail_style::Style
end

function ProgressList(items::Vector{ProgressItem};
    tick=nothing,
    block=nothing,
    pending_style=tstyle(:text_dim),
    running_style=tstyle(:accent),
    done_style=tstyle(:success),
    error_style=tstyle(:error),
    skipped_style=tstyle(:text_dim, dim=true),
    label_style=tstyle(:text),
    detail_style=tstyle(:text_dim),
)
    ProgressList(items, tick, block, pending_style, running_style,
                 done_style, error_style, skipped_style,
                 label_style, detail_style)
end

function status_icon(status::TaskStatus, tick::Union{Int, Nothing})
    if status == task_pending
        return ('○', :pending_style)
    elseif status == task_running
        t = tick === nothing ? 0 : tick
        idx = mod1(t ÷ 3, length(SPINNER_BRAILLE))
        return (SPINNER_BRAILLE[idx], :running_style)
    elseif status == task_done
        return ('✓', :done_style)
    elseif status == task_error
        return ('✗', :error_style)
    else  # skipped
        return ('–', :skipped_style)
    end
end

function render(pl::ProgressList, rect::Rect, buf::Buffer)
    content = if pl.block !== nothing
        render(pl.block, rect, buf)
    else
        rect
    end
    (content.width < 4 || content.height < 1) && return

    for (i, item) in enumerate(pl.items)
        y = content.y + i - 1
        y > bottom(content) && break

        icon, style_field = status_icon(item.status, pl.tick)
        icon_style = getfield(pl, style_field)

        # Status icon
        set_char!(buf, content.x, y, icon, icon_style)

        # Label
        label_style = if item.status == task_done
            pl.done_style
        elseif item.status == task_error
            pl.error_style
        elseif item.status == task_skipped
            pl.skipped_style
        else
            pl.label_style
        end
        set_string!(buf, content.x + 2, y, item.label, label_style)

        # Detail text (right-aligned)
        if !isempty(item.detail)
            dx = right(content) - length(item.detail)
            if dx > content.x + 2 + length(item.label)
                set_string!(buf, dx, y, item.detail, pl.detail_style)
            end
        end
    end
end
