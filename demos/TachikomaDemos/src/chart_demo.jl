# ═══════════════════════════════════════════════════════════════════════
# Chart Demo ── interactive chart with animated data
#
# Three modes: dual (sine+cosine), scatter (noisy circle), live (streaming).
# [m] cycles mode, [b] toggles braille/sixel backend, [q/Esc] quits.
# ═══════════════════════════════════════════════════════════════════════

const CHART_MODES = (:dual, :scatter, :live)
const CHART_MODE_LABELS = Dict(
    :dual    => "Dual: Sine + Cosine",
    :scatter => "Scatter: Noisy Circle",
    :live    => "Live: Streaming Data",
)

@kwdef mutable struct ChartModel <: Model
    quit::Bool = false
    tick::Int = 0
    mode::Symbol = :dual
    live_data::Vector{Float64} = Float64[]
    scatter_data::Vector{Tuple{Float64, Float64}} = _gen_scatter()
end

should_quit(m::ChartModel) = m.quit

function _gen_scatter()
    pts = Tuple{Float64, Float64}[]
    for i in 1:100
        θ = rand() * 2π
        r = 1.0 + 0.3 * randn()
        push!(pts, (r * cos(θ), r * sin(θ)))
    end
    pts
end

function update!(m::ChartModel, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 'm')                 => begin
            idx = findfirst(==(m.mode), CHART_MODES)
            m.mode = CHART_MODES[mod1(idx + 1, length(CHART_MODES))]
            m.mode == :scatter && (m.scatter_data = _gen_scatter())
        end
        (:char, 'b')                 => set_render_backend!(render_backend() == braille_backend ?
                                                             sixel_backend : braille_backend)
        _                            => nothing
    end
end

function view(m::ChartModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Layout: header | chart | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    chart_area  = rows[2]
    footer_area = rows[3]

    # ── Header ──
    mode_label = CHART_MODE_LABELS[m.mode]
    hx = header_area.x + max(0, (header_area.width - length(mode_label)) ÷ 2)
    set_string!(buf, hx, header_area.y, mode_label, tstyle(:title, bold=true))

    # ── Chart ──
    chart = _build_chart(m)
    render(chart, chart_area, buf)

    # ── Footer ──
    backend_label = render_backend() == sixel_backend ? "sixel" : "braille"
    render(StatusBar(
        left=[Span("  [m]mode [b]backend:$(backend_label) ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function _build_chart(m::ChartModel)
    @match m.mode begin
        :dual    => _chart_dual(m)
        :scatter => _chart_scatter(m)
        _        => _chart_live(m)
    end
end

function _chart_dual(m::ChartModel)
    xs = range(0.0, 2π; length=80)
    t = m.tick
    sin_data = [(Float64(x), sin(x + t * 0.05)) for x in xs]
    cos_data = [(Float64(x), cos(x + t * 0.03)) for x in xs]

    Chart([
        DataSeries(sin_data; label=" sin ", style=tstyle(:primary), chart_type=chart_line),
        DataSeries(cos_data; label=" cos ", style=tstyle(:secondary), chart_type=chart_line),
    ];
        block=Block(title="$(CHART_MODE_LABELS[m.mode])",
                    border_style=tstyle(:border)),
        x_label="x",
        y_label="y",
        y_bounds=(-1.5, 1.5),
    )
end

function _chart_scatter(m::ChartModel)
    Chart([
        DataSeries(m.scatter_data; label=" points ", style=tstyle(:secondary),
                   chart_type=chart_scatter),
    ];
        block=Block(title="$(CHART_MODE_LABELS[m.mode])",
                    border_style=tstyle(:border)),
        x_bounds=(-2.0, 2.0),
        y_bounds=(-2.0, 2.0),
    )
end

function _chart_live(m::ChartModel)
    # Push new value each tick
    t = m.tick * 0.08
    push!(m.live_data, 0.5 + 0.3 * sin(t) + 0.1 * randn())
    length(m.live_data) > 120 && popfirst!(m.live_data)

    Chart([
        DataSeries(Float64.(m.live_data); label=" signal ", style=tstyle(:accent),
                   chart_type=chart_line),
    ];
        block=Block(title="$(CHART_MODE_LABELS[m.mode])",
                    border_style=tstyle(:border)),
        y_bounds=(0.0, 1.2),
        show_legend=true,
    )
end

function chart_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(ChartModel(); fps=30)
end
