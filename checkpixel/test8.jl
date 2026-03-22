module MakieWindows

using TachiMakie
using Makie

using Tachikoma
import Tachikoma: view, update!, should_quit, init!
const Rect = Tachikoma.Rect
const MouseEvent = Tachikoma.MouseEvent
const KeyEvent = Tachikoma.KeyEvent

mutable struct PlotState
    fig::Figure
    t::Observable{Float64}
end

function render_into!(ps::PlotState, inner::Rect, win_rect::Rect,
                      buf::Tachikoma.Buffer, focused::Bool, frame, tick::Int;
                      z::Int=-1, border_color::Tachikoma.ColorRGB=Tachikoma.to_rgb(tstyle(:border).fg),
                      accent_color::Tachikoma.ColorRGB=Tachikoma.to_rgb(tstyle(:accent).fg))
    frame === nothing && return
    (inner.width < 4 || inner.height < 2) && return
    ps.t[] = tick * 0.03
    rgba, pw, ph = render_to_rgba(ps.fig)

    gfx = Tachikoma.GRAPHICS_PROTOCOL[]
    if gfx == Tachikoma.gfx_kitty
        # Kitty: render full window with pixel borders (z-index puts under text)
        cp = Tachikoma.CELL_PX[]
        cpw = max(1, cp.w)
        cph = max(1, cp.h)
        full_pw = win_rect.width * cpw
        full_ph = win_rect.height * cph
        full_rgba = Vector{UInt8}(undef, full_pw * full_ph * 4)

        border_left = (inner.x - win_rect.x) * cpw
        border_top = (inner.y - win_rect.y) * cph
        border_right = (win_rect.x + win_rect.width - inner.x - inner.width) * cpw
        border_bottom = (win_rect.y + win_rect.height - inner.y - inner.height) * cph
        bc = focused ? accent_color : border_color

        idx = 1
        @inbounds for y in 1:full_ph
            for x in 1:full_pw
                in_border = x <= border_left || x > full_pw - border_right ||
                            y <= border_top || y > full_ph - border_bottom
                if in_border
                    is_edge = (x == border_left || x == full_pw - border_right + 1 ||
                               y == border_top || y == full_ph - border_bottom + 1)
                    if is_edge
                        full_rgba[idx] = bc.r; full_rgba[idx+1] = bc.g
                        full_rgba[idx+2] = bc.b; full_rgba[idx+3] = 0xff
                    else
                        full_rgba[idx] = UInt8(bc.r >> 2); full_rgba[idx+1] = UInt8(bc.g >> 2)
                        full_rgba[idx+2] = UInt8(bc.b >> 2); full_rgba[idx+3] = 0xd0
                    end
                else
                    px = x - border_left; py = y - border_top
                    inner_pw = full_pw - border_left - border_right
                    inner_ph = full_ph - border_top - border_bottom
                    src_x = clamp(round(Int, (px-1) / inner_pw * pw) + 1, 1, pw)
                    src_y = clamp(round(Int, (py-1) / inner_ph * ph) + 1, 1, ph)
                    si = ((src_y-1) * pw + (src_x-1)) * 4
                    full_rgba[idx] = rgba[si+1]; full_rgba[idx+1] = rgba[si+2]
                    full_rgba[idx+2] = rgba[si+3]; full_rgba[idx+3] = rgba[si+4]
                end
                idx += 4
            end
        end
        render_rgba!(frame, full_rgba, full_pw, full_ph, win_rect; z=z, scale_to_cells=true)
    else
        # Sixel: render inner content only (text borders handled by Tachikoma)
        render_rgba!(frame, rgba, pw, ph, inner)
    end
end

@kwdef mutable struct M <: Model
    quit::Bool = false
    tick::Int = 0
    wm::WindowManager = WindowManager()
    plots::Vector{PlotState} = PlotState[]
    tiled::Bool = false
    last_time::Float64 = time()
    frame_times::Vector{Float64} = Float64[]
end

should_quit(m::M) = m.quit

function update!(m::M, e::KeyEvent)
    e.key == :escape && (m.quit = true; return)
    if e.key == :char && e.char == 't' && !isempty(m.wm.windows)
        tile!(m.wm, m.wm.last_area)
        return
    end
    handle_key!(m.wm, e)
end

function update!(m::M, e::MouseEvent)
    handle_mouse!(m.wm, e)
end

function init!(m::M, ::Terminal)
    Makie.set_theme!(Makie.theme_dark(), fontsize=18)
    clear = Makie.RGBAf(0, 0, 0, 0)
    semi = Makie.RGBAf(0.1, 0.1, 0.15, 0.6)

    configs = [
        ("Waves (transparent)", clear, clear, (fig, t) -> begin
            ax = Axis(fig[1,1], backgroundcolor=clear)
            x = range(0, 4pi, length=100)
            lines!(ax, x, @lift(sin.(x .+ $t)), color=:dodgerblue, linewidth=3)
            lines!(ax, x, @lift(cos.(x .+ $t * 0.7)), color=:tomato, linewidth=3)
        end),
        ("Heatmap", :black, :black, (fig, t) -> begin
            ax = Axis(fig[1,1])
            data = @lift([
                sin(i*0.15 + $t) * cos(j*0.15 + $t*0.5) +
                0.5 * sin(i*0.3 - j*0.2 + $t*1.3) +
                0.3 * cos(sqrt(Float64(i)^2 + Float64(j)^2) * 0.2 - $t)
                for i in 1:40, j in 1:40
            ])
            heatmap!(ax, data, colormap=:inferno)
        end),
        ("Lissajous (semi)", semi, semi, (fig, t) -> begin
            ax = Axis(fig[1,1], backgroundcolor=semi)
            lx = @lift([sin(3*i*0.05 + $t) for i in 1:120])
            ly = @lift([cos(2*i*0.05 + $t*0.7) for i in 1:120])
            lines!(ax, lx, ly, color=:lime, linewidth=2)
            lines!(ax, @lift([sin(5*i*0.04 + $t*1.2) for i in 1:100]),
                       @lift([cos(4*i*0.04 + $t*0.8) for i in 1:100]),
                       color=:magenta, linewidth=2)
        end),
        ("Spiral (opaque)", :black, :black, (fig, t) -> begin
            ax = Axis(fig[1,1])
            sx = @lift([(0.1 + i*0.02) * cos(i*0.15 + $t) for i in 1:80])
            sy = @lift([(0.1 + i*0.02) * sin(i*0.15 + $t) for i in 1:80])
            lines!(ax, sx, sy, color=:orange, linewidth=2)
            lines!(ax, @lift([-(0.1 + i*0.02) * cos(i*0.15 + $t*1.1) for i in 1:80]),
                       @lift([-(0.1 + i*0.02) * sin(i*0.15 + $t*1.1) for i in 1:80]),
                       color=:cyan, linewidth=2)
        end),
    ]

    for (i, (title, fig_bg, ax_bg, setup)) in enumerate(configs)
        t = Observable(0.0)
        fig = Figure(size=(400, 280), backgroundcolor=fig_bg)
        setup(fig, t)
        local plot_state = PlotState(fig, t)
        push!(m.plots, plot_state)
        local model = m
        local my_win = FloatingWindow(
            title=title,
            x=5+(i-1)*25, y=2+(i-1)*3,
            width=45, height=18,
            on_render=(inner, buf, focused, frame) -> begin
                if frame !== nothing && inner.width >= 4 && inner.height >= 2
                    n = length(model.wm.windows)
                    my_pos = findfirst(==(my_win), model.wm.windows)
                    z = my_pos !== nothing ? -(n - my_pos + 1) : -1
                    win_rect = Rect(my_win.x, my_win.y, my_win.width, my_win.height)
                    render_into!(plot_state, inner, win_rect, buf, focused, frame, model.tick;
                                z=z)
                end
            end
        )
        push!(m.wm, my_win)
    end
end

function view(m::M, f::Tachikoma.Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    content_area = Rect(area.x, area.y, area.width, area.height - 1)
    footer = Rect(area.x, area.y + area.height - 1, area.width, 1)

    if !m.tiled && !isempty(m.wm.windows)
        tile!(m.wm, content_area)
        m.tiled = true
    end

    step!(m.wm)
    render(m.wm, content_area, buf; frame=f)

    now = time()
    dt = now - m.last_time
    m.last_time = now
    push!(m.frame_times, dt)
    length(m.frame_times) > 60 && popfirst!(m.frame_times)
    avg = sum(m.frame_times) / length(m.frame_times)
    fps = avg > 0 ? round(Int, 1.0 / avg) : 0

    render(StatusBar(
        left=[Span("  $(fps)fps  4 Makie plots  [t]tile  [Esc]quit ", tstyle(:accent, bold=true))],
        right=[Span("f$(m.tick) ", tstyle(:text_dim))],
    ), footer, buf)
end

app(M(); fps=120)

end
