# ═══════════════════════════════════════════════════════════════════════
# Gauge ── horizontal progress bar with percentage label
# ═══════════════════════════════════════════════════════════════════════

struct Gauge
    ratio::Float64           # 0.0 – 1.0
    label::String
    block::Union{Block, Nothing}
    filled_style::Style
    empty_style::Style
    label_style::Style
    tick::Union{Int, Nothing}
end

function Gauge(ratio::Real;
    label="",
    block=nothing,
    filled_style=tstyle(:primary),
    empty_style=tstyle(:text_dim, dim=true),
    label_style=tstyle(:text_bright, bold=true),
    tick=nothing,
)
    r = clamp(Float64(ratio), 0.0, 1.0)
    lbl = isempty(label) ? string(round(Int, r * 100)) * "%" : label
    Gauge(r, lbl, block, filled_style, empty_style, label_style, tick)
end

function render(g::Gauge, rect::Rect, buf::Buffer)
    content = if g.block !== nothing
        render(g.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    w = content.width
    filled_w = round(Int, g.ratio * w)
    y = content.y

    # Draw filled portion with sub-character precision
    full_cells = floor(Int, g.ratio * w)
    frac = g.ratio * w - full_cells

    for col in 0:(w - 1)
        cx = content.x + col
        if col < full_cells
            s = g.filled_style
            # Shimmer along filled portion
            if g.tick !== nothing && animations_enabled()
                base_fg = to_rgb(s.fg)
                sh = shimmer(g.tick, col; speed=0.06, scale=0.25)
                adj = (sh - 0.5) * 0.2
                c = adj > 0 ? brighten(base_fg, adj) : dim_color(base_fg, -adj)
                s = Style(fg=c, bold=s.bold)
            end
            set_char!(buf, cx, y, '█', s)
        elseif col == full_cells && frac > 0.0
            idx = clamp(round(Int, frac * 8), 1, 8)
            set_char!(buf, cx, y, BARS_H[idx], g.filled_style)
        else
            set_char!(buf, cx, y, '░', g.empty_style)
        end
    end

    # Center the label on the bar
    if !isempty(g.label) && w >= length(g.label)
        lx = center(content, length(g.label), 1).x
        set_string!(buf, lx, y, g.label, g.label_style)
    end
end
