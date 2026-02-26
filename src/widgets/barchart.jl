# ═══════════════════════════════════════════════════════════════════════
# BarChart ── horizontal bar chart with labels and values
# ═══════════════════════════════════════════════════════════════════════

struct BarEntry
    label::String
    value::Float64
    style::Style
end

BarEntry(label::String, value::Real; style=tstyle(:primary)) =
    BarEntry(label, Float64(value), style)

struct BarChart
    bars::Vector{BarEntry}
    max_val::Union{Float64, Nothing}  # nothing = auto
    block::Union{Block, Nothing}
    label_width::Int                   # 0 = auto
    show_values::Bool
    value_style::Style
    label_style::Style
    empty_char::Char
end

function BarChart(bars::Vector{BarEntry};
    max_val=nothing,
    block=nothing,
    label_width=0,
    show_values=true,
    value_style=tstyle(:text_bright),
    label_style=tstyle(:text_dim),
    empty_char='░',
)
    BarChart(bars, max_val === nothing ? nothing : Float64(max_val),
             block, label_width, show_values, value_style,
             label_style, empty_char)
end

function render(bc::BarChart, rect::Rect, buf::Buffer)
    content = if bc.block !== nothing
        render(bc.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return
    isempty(bc.bars) && return

    # Determine label width
    lw = bc.label_width > 0 ? bc.label_width :
         maximum(length(b.label) for b in bc.bars; init=4) + 1

    # Determine value display width
    mx = bc.max_val !== nothing ? bc.max_val :
         maximum(b.value for b in bc.bars; init=1.0)
    mx = mx <= 0.0 ? 1.0 : mx
    vw = bc.show_values ? max(6, length(string(round(mx; digits=1))) + 2) : 0

    # Bar area width
    bar_w = content.width - lw - vw - 1  # -1 for separator
    bar_w < 2 && return

    for (i, entry) in enumerate(bc.bars)
        y = content.y + i - 1
        y > bottom(content) && break

        # Label (right-aligned)
        label = length(entry.label) > lw - 1 ?
            entry.label[1:lw-2] * "…" : entry.label
        lx = content.x + lw - length(label) - 1
        set_string!(buf, lx, y, label, bc.label_style)

        # Separator
        set_char!(buf, content.x + lw, y, '│',
                  tstyle(:border, dim=true))

        # Bar
        bar_x = content.x + lw + 1
        ratio = clamp(entry.value / mx, 0.0, 1.0)
        filled = floor(Int, ratio * bar_w)
        frac = ratio * bar_w - filled

        for col in 0:(bar_w - 1)
            bx = bar_x + col
            if col < filled
                set_char!(buf, bx, y, '█', entry.style)
            elseif col == filled && frac > 0.0
                idx = clamp(round(Int, frac * 8), 1, 8)
                set_char!(buf, bx, y, BARS_H[idx], entry.style)
            else
                set_char!(buf, bx, y, bc.empty_char,
                          tstyle(:text_dim, dim=true))
            end
        end

        # Value
        if bc.show_values
            val_str = string(round(entry.value; digits=1))
            vx = bar_x + bar_w + 1
            set_string!(buf, vx, y, val_str, bc.value_style)
        end
    end
end
