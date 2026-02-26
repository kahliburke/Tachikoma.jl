# ═══════════════════════════════════════════════════════════════════════
# Sparkline ── mini bar chart using vertical block elements
# ═══════════════════════════════════════════════════════════════════════

struct Sparkline
    data::Vector{Float64}
    block::Union{Block, Nothing}
    style::Style
    max_val::Union{Float64, Nothing}  # nothing = auto-scale
end

function Sparkline(data::Vector{<:Real};
    block=nothing,
    style=tstyle(:primary),
    max_val=nothing,
)
    Sparkline(Float64.(data), block, style,
              max_val === nothing ? nothing : Float64(max_val))
end

function render(sp::Sparkline, rect::Rect, buf::Buffer)
    content = if sp.block !== nothing
        render(sp.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    isempty(sp.data) && return

    w = content.width
    h = content.height
    n = length(sp.data)

    # Take the last w values (or fewer if data is short)
    start = max(1, n - w + 1)
    visible = sp.data[start:n]

    mx = sp.max_val !== nothing ? sp.max_val :
         maximum(visible; init=1.0)
    mx = mx <= 0.0 ? 1.0 : mx

    for (i, val) in enumerate(visible)
        cx = content.x + i - 1
        cx > right(content) && break

        # Scale to available height * 8 (sub-character precision)
        scaled = clamp(val / mx, 0.0, 1.0) * h * 8
        full_rows = floor(Int, scaled / 8)
        frac = round(Int, scaled % 8)

        # Draw from bottom up
        for row in 0:(h - 1)
            cy = bottom(content) - row
            if row < full_rows
                set_char!(buf, cx, cy, '█', sp.style)
            elseif row == full_rows && frac > 0
                set_char!(buf, cx, cy, BARS_V[frac], sp.style)
            end
        end
    end
end
