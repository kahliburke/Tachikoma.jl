# ═══════════════════════════════════════════════════════════════════════
# Chart ── line/scatter chart rendered on braille canvas
# ═══════════════════════════════════════════════════════════════════════

@enum ChartType chart_line chart_scatter

struct DataSeries
    data::Vector{Tuple{Float64, Float64}}
    label::String
    style::Style
    chart_type::ChartType
end

function DataSeries(data::Vector{Tuple{Float64, Float64}};
    label::String="",
    style::Style=tstyle(:primary),
    chart_type::ChartType=chart_line,
)
    DataSeries(data, label, style, chart_type)
end

# Convenience: Vector{Float64} → implicit x=1,2,...
function DataSeries(ys::Vector{Float64}; kwargs...)
    DataSeries([(Float64(i), y) for (i, y) in enumerate(ys)]; kwargs...)
end

struct Chart
    series::Vector{DataSeries}
    block::Union{Block, Nothing}
    x_label::String
    y_label::String
    x_bounds::Union{Nothing, Tuple{Float64, Float64}}
    y_bounds::Union{Nothing, Tuple{Float64, Float64}}
    show_axes::Bool
    show_legend::Bool
    tick::Union{Int, Nothing}
end

function Chart(series::Vector{DataSeries};
    block::Union{Block, Nothing}=nothing,
    x_label::String="",
    y_label::String="",
    x_bounds=nothing,
    y_bounds=nothing,
    show_axes::Bool=true,
    show_legend::Bool=true,
    tick::Union{Int, Nothing}=nothing,
)
    Chart(series, block, x_label, y_label, x_bounds, y_bounds, show_axes, show_legend, tick)
end

# Single series convenience
function Chart(data; kwargs...)
    if data isa DataSeries
        Chart([data]; kwargs...)
    else
        Chart([DataSeries(data)]; kwargs...)
    end
end

# ── Shared helpers (used by both Buffer and Frame render paths) ──

function _chart_compute_layout(chart::Chart, content_area::Rect,
                               x_min::Float64, x_max::Float64,
                               y_min::Float64, y_max::Float64)
    y_label_w = chart.show_axes ? _y_label_width(y_min, y_max) : 0
    legend_h = chart.show_legend && length(chart.series) > 0 ? 1 : 0
    x_label_h = chart.show_axes ? 1 : 0
    canvas_x = content_area.x + y_label_w + (chart.show_axes ? 1 : 0)
    canvas_y = content_area.y
    canvas_w = max(1, right(content_area) - canvas_x + 1)
    canvas_h = max(1, content_area.height - x_label_h - legend_h)
    (; canvas_x, canvas_y, canvas_w, canvas_h, x_label_h)
end

function _chart_plot_series!(c, ds::DataSeries,
                             x_min::Float64, x_max::Float64,
                             y_min::Float64, y_max::Float64,
                             dot_w::Int, dot_h::Int)
    for (i, (px, py)) in enumerate(ds.data)
        dx = _map_range(px, x_min, x_max, 0, dot_w - 1)
        dy = _map_range(py, y_min, y_max, dot_h - 1, 0)  # flip Y
        set_point!(c, dx, dy)
        if ds.chart_type == chart_line && i > 1
            prev_x, prev_y = ds.data[i - 1]
            pdx = _map_range(prev_x, x_min, x_max, 0, dot_w - 1)
            pdy = _map_range(prev_y, y_min, y_max, dot_h - 1, 0)
            line!(c, pdx, pdy, dx, dy)
        end
    end
end

function _chart_render_axes!(buf::Buffer, chart::Chart, content_area::Rect,
                             canvas_x::Int, canvas_y::Int,
                             canvas_w::Int, canvas_h::Int,
                             x_min::Float64, x_max::Float64,
                             y_min::Float64, y_max::Float64,
                             x_label_h::Int)
    chart.show_axes || return
    axis_style = tstyle(:text_dim)
    # Y axis
    ax = canvas_x - 1
    for y in canvas_y:(canvas_y + canvas_h - 1)
        set_char!(buf, ax, y, '│', axis_style)
    end
    # X axis
    ay = canvas_y + canvas_h
    if ay <= bottom(content_area)
        for x in canvas_x:right(content_area)
            set_char!(buf, x, ay, '─', axis_style)
        end
        set_char!(buf, ax, ay, '└', axis_style)
    end

    # Y axis labels
    if canvas_h >= 2
        top_label = _format_num(y_max)
        bot_label = _format_num(y_min)
        lx = content_area.x
        set_string!(buf, lx, canvas_y, top_label, axis_style;
                    max_x=ax - 1)
        set_string!(buf, lx, canvas_y + canvas_h - 1, bot_label, axis_style;
                    max_x=ax - 1)
    end

    # X axis labels
    if x_label_h > 0 && ay <= bottom(content_area)
        left_label = _format_num(x_min)
        right_label = _format_num(x_max)
        set_string!(buf, canvas_x, ay, left_label, axis_style)
        rl_x = right(content_area) - length(right_label) + 1
        set_string!(buf, max(canvas_x, rl_x), ay, right_label, axis_style)
    end

    # Axis labels
    if !isempty(chart.x_label) && ay <= bottom(content_area)
        lx = canvas_x + max(0, (canvas_w - length(chart.x_label)) ÷ 2)
        set_string!(buf, lx, ay, chart.x_label, axis_style)
    end
    if !isempty(chart.y_label)
        for (i, ch) in enumerate(chart.y_label)
            vy = canvas_y + i - 1
            vy > canvas_y + canvas_h - 1 && break
            set_char!(buf, content_area.x, vy, ch, axis_style)
        end
    end
end

function _chart_render_legend!(buf::Buffer, chart::Chart, content_area::Rect,
                               canvas_y::Int, canvas_h::Int, x_label_h::Int)
    chart.show_legend && !isempty(chart.series) || return
    ly = canvas_y + canvas_h + x_label_h
    ly > bottom(content_area) && return
    lx = content_area.x
    for ds in chart.series
        isempty(ds.label) && continue
        lx > right(content_area) && break
        set_char!(buf, lx, ly, '■', ds.style)
        lx += 1
        lx = set_string!(buf, lx, ly, ds.label, tstyle(:text_dim);
                         max_x=right(content_area))
        lx += 2  # spacing between legend entries
    end
end

# ── Buffer render (braille-only, backward compatible) ──

function render(chart::Chart, rect::Rect, buf::Buffer)
    content_area = if chart.block !== nothing
        render(chart.block, rect, buf)
    else
        rect
    end
    (content_area.width < 4 || content_area.height < 3) && return

    # Compute data bounds
    x_min, x_max, y_min, y_max = _chart_bounds(chart)
    x_min == x_max && (x_max = x_min + 1.0)
    y_min == y_max && (y_max = y_min + 1.0)

    layout = _chart_compute_layout(chart, content_area, x_min, x_max, y_min, y_max)
    (; canvas_x, canvas_y, canvas_w, canvas_h, x_label_h) = layout

    _chart_render_axes!(buf, chart, content_area, canvas_x, canvas_y, canvas_w, canvas_h,
                        x_min, x_max, y_min, y_max, x_label_h)

    # Create canvas and plot each series
    c = Canvas(canvas_w, canvas_h)
    dot_w = canvas_w * 2
    dot_h = canvas_h * 4
    canvas_rect = Rect(canvas_x, canvas_y, canvas_w, canvas_h)

    for ds in chart.series
        c.style = ds.style
        _chart_plot_series!(c, ds, x_min, x_max, y_min, y_max, dot_w, dot_h)
        render(c, canvas_rect, buf)
        clear!(c)
    end

    _chart_render_legend!(buf, chart, content_area, canvas_y, canvas_h, x_label_h)
end

# ── Helpers ──

function _chart_bounds(chart::Chart)
    if isempty(chart.series) || all(isempty(ds.data) for ds in chart.series)
        return (0.0, 1.0, 0.0, 1.0)
    end

    all_x = Float64[]
    all_y = Float64[]
    for ds in chart.series
        for (x, y) in ds.data
            push!(all_x, x)
            push!(all_y, y)
        end
    end

    x_min, x_max = if chart.x_bounds !== nothing
        chart.x_bounds
    else
        (minimum(all_x), maximum(all_x))
    end

    y_min, y_max = if chart.y_bounds !== nothing
        chart.y_bounds
    else
        (minimum(all_y), maximum(all_y))
    end

    (x_min, x_max, y_min, y_max)
end

function _map_range(v::Float64, from_lo::Float64, from_hi::Float64,
                    to_lo::Int, to_hi::Int)
    span = from_hi - from_lo
    span == 0.0 && return to_lo
    t = (v - from_lo) / span
    round(Int, to_lo + t * (to_hi - to_lo))
end

function _format_num(v::Float64)
    if abs(v) >= 1000
        string(round(Int, v))
    elseif abs(v) >= 1
        string(round(v; digits=1))
    else
        string(round(v; digits=2))
    end
end

function _y_label_width(y_min::Float64, y_max::Float64)
    max(length(_format_num(y_min)), length(_format_num(y_max)), 3)
end
