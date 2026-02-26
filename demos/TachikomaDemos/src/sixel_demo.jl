# ═══════════════════════════════════════════════════════════════════════
# Sixel Demo ── decay effects showcase using PixelImage widget
#
# Rich visual content (plasma, terrain, mandelbrot) rendered via
# PixelImage with live decay params applied. Ctrl+S opens the
# settings overlay to tweak decay/jitter/rot/noise in real time.
# Falls back to braille sampling on non-sixel terminals.
# ═══════════════════════════════════════════════════════════════════════

@enum SixelScene sixel_plasma sixel_terrain sixel_mandelbrot sixel_rings

@kwdef mutable struct SixelDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    paused::Bool = false
    scene::SixelScene = sixel_plasma
end

should_quit(m::SixelDemoModel) = m.quit

function update!(m::SixelDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        evt.char == '1' && (m.scene = sixel_plasma)
        evt.char == '2' && (m.scene = sixel_terrain)
        evt.char == '3' && (m.scene = sixel_mandelbrot)
        evt.char == '4' && (m.scene = sixel_rings)
    end
    evt.key == :escape && (m.quit = true)
end

# Consume mouse events so they don't propagate and cause terminal artifacts
# over sixel regions.
function update!(::SixelDemoModel, ::MouseEvent) end

# ── Adaptive step size: larger canvas → coarser computation ──────────
# Returns a step size so we compute ~200×150 samples max, then fill blocks.
function _sixel_step(pw::Int, ph::Int)
    max(1, max(pw ÷ 200, ph ÷ 150))
end

# ── Plasma: layered sine plasma with smooth color cycling ────────────

function _draw_plasma!(img::PixelImage, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    step = _sixel_step(pw, ph)
    t = Float64(tick) * 0.04
    inv_pw = 1.0 / Float64(pw)
    inv_ph = 1.0 / Float64(ph)

    for py in 1:step:ph
        ny = Float64(py) * inv_ph
        for px in 1:step:pw
            nx = Float64(px) * inv_pw

            v  = sin(nx * 8.0 + t)
            v += sin(ny * 6.0 - t * 0.7)
            v += sin((nx + ny) * 5.0 + t * 0.5)
            v += sin(sqrt(nx * nx + ny * ny) * 10.0 - t * 1.2)
            v = (v + 4.0) * 0.125  # normalize to 0-1

            h = mod(v * 360.0 + t * 15.0, 360.0)
            r, g, b = _hsv_to_rgb(h, 0.85, 0.6 + 0.4 * sin(v * π))
            color = ColorRGB(r, g, b)
            fill_rect!(img, px, py, px + step - 1, py + step - 1, color)
        end
    end
end

# ── Terrain: elevation map with contour shading ─────────────────────

function _draw_terrain!(img::PixelImage, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    step = _sixel_step(pw, ph)
    t = Float64(tick) * 0.008
    inv_pw = 1.0 / Float64(pw)
    inv_ph = 1.0 / Float64(ph)

    for py in 1:step:ph
        ny = Float64(py) * inv_ph
        for px in 1:step:pw
            nx = Float64(px) * inv_pw

            # Multi-octave terrain heightmap (reduced octaves for speed)
            elev = fbm(nx * 3.0 + t, ny * 3.0; octaves=3, gain=0.45)
            elev += 0.3 * fbm(nx * 6.0 - t * 0.5, ny * 6.0 + t * 0.3; octaves=2)
            elev = clamp((elev + 0.5) * 0.8, 0.0, 1.0)

            # Slope-based shading (approximate gradient via noise offset)
            dx_elev = fbm((nx + 0.003) * 3.0 + t, ny * 3.0; octaves=2, gain=0.45) -
                      fbm((nx - 0.003) * 3.0 + t, ny * 3.0; octaves=2, gain=0.45)
            light = clamp(0.5 + dx_elev * 8.0, 0.2, 1.0)

            # Color by elevation band
            r, g, b = if elev < 0.25
                _scale_rgb(0x0a, 0x1a, 0x50, 0.5 + elev * 2.0)
            elseif elev < 0.4
                frac = (elev - 0.25) / 0.15
                (UInt8(round(0x0a + frac * (0x1a - 0x0a))),
                 UInt8(round(0x3a + frac * (0x6a - 0x3a))),
                 UInt8(round(0x70 + frac * (0x40 - 0x70))))
            elseif elev < 0.55
                frac = (elev - 0.4) / 0.15
                (UInt8(round(0x1a + frac * 0x10)),
                 UInt8(round(0x5a + frac * 0x20)),
                 UInt8(round(0x1a + frac * 0x05)))
            elseif elev < 0.7
                frac = (elev - 0.55) / 0.15
                (UInt8(round(0x4a + frac * 0x20)),
                 UInt8(round(0x3a + frac * 0x10)),
                 UInt8(round(0x1a + frac * 0x05)))
            else
                frac = (elev - 0.7) / 0.3
                v = UInt8(clamp(round(Int, 0x80 + frac * 0x7f), 0, 255))
                (v, v, v)
            end

            # Apply lighting
            r = UInt8(clamp(round(Int, Float64(r) * light), 0, 255))
            g = UInt8(clamp(round(Int, Float64(g) * light), 0, 255))
            b = UInt8(clamp(round(Int, Float64(b) * light), 0, 255))

            fill_rect!(img, px, py, px + step - 1, py + step - 1, ColorRGB(r, g, b))
        end
    end
end

# ── Mandelbrot: classic fractal with smooth coloring ────────────────

function _draw_mandelbrot!(img::PixelImage, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    step = _sixel_step(pw, ph)
    t = Float64(tick) * 0.005

    # Slow zoom into an interesting region
    zoom = 1.5 + 0.5 * sin(t * 0.3)
    cx_center = -0.745 + 0.01 * sin(t * 0.7)
    cy_center = 0.186 + 0.01 * cos(t * 0.5)
    max_iter = 64
    inv_pw = 1.0 / Float64(pw)
    inv_ph = 1.0 / Float64(ph)
    scale = 2.0 / zoom

    for py in 1:step:ph
        ci = cy_center + (Float64(py) * inv_ph - 0.5) * scale
        for px in 1:step:pw
            cr = cx_center + (Float64(px) * inv_pw - 0.5) * scale

            zr, zi = 0.0, 0.0
            iter = 0
            while zr * zr + zi * zi <= 4.0 && iter < max_iter
                zr, zi = zr * zr - zi * zi + cr, 2.0 * zr * zi + ci
                iter += 1
            end

            color = if iter == max_iter
                ColorRGB(0x00, 0x00, 0x00)
            else
                smooth_i = Float64(iter) + 1.0 - log2(max(1.0, log2(zr * zr + zi * zi)))
                h = mod(smooth_i * 7.0 + t * 20.0, 360.0)
                v = clamp(smooth_i / Float64(max_iter) * 3.0, 0.3, 1.0)
                r, g, b = _hsv_to_rgb(h, 0.9, v)
                ColorRGB(r, g, b)
            end
            fill_rect!(img, px, py, px + step - 1, py + step - 1, color)
        end
    end
end

# ── Concentric rings: interference pattern ──────────────────────────

function _draw_rings!(img::PixelImage, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    step = _sixel_step(pw, ph)
    t = Float64(tick) * 0.03
    th = theme()
    c1 = to_rgb(th.primary)
    c2 = to_rgb(th.accent)
    c3 = to_rgb(th.secondary)
    inv_pw = 1.0 / Float64(pw)
    inv_ph = 1.0 / Float64(ph)

    # Multiple wave sources
    s1x = 0.5 + 0.2 * sin(t)
    s1y = 0.5 + 0.2 * cos(t * 0.7)
    s2x = 0.3 + 0.15 * cos(t * 1.3)
    s2y = 0.7 + 0.15 * sin(t * 0.9)
    s3x = 0.7 + 0.1 * sin(t * 0.8)
    s3y = 0.3 + 0.1 * cos(t * 1.1)

    for py in 1:step:ph
        ny = Float64(py) * inv_ph
        for px in 1:step:pw
            nx = Float64(px) * inv_pw

            d1 = sqrt((nx - s1x)^2 + (ny - s1y)^2)
            d2 = sqrt((nx - s2x)^2 + (ny - s2y)^2)
            d3 = sqrt((nx - s3x)^2 + (ny - s3y)^2)
            v = (sin(d1 * 30.0 - t * 2.0) +
                 sin(d2 * 30.0 - t * 2.0) +
                 sin(d3 * 30.0 - t * 2.0)) / 6.0 + 0.5

            fg = if v < 0.5
                color_lerp(c1, c2, v * 2.0)
            else
                color_lerp(c2, c3, (v - 0.5) * 2.0)
            end
            fg = brighten(fg, 0.1 * sin(v * π * 4.0))

            fill_rect!(img, px, py, px + step - 1, py + step - 1, fg)
        end
    end
end

# ── HSV helper ──────────────────────────────────────────────────────

function _hsv_to_rgb(h::Float64, s::Float64, v::Float64)
    c = v * s
    x = c * (1.0 - abs(mod(h / 60.0, 2.0) - 1.0))
    m = v - c
    r1, g1, b1 = if h < 60.0
        (c, x, 0.0)
    elseif h < 120.0
        (x, c, 0.0)
    elseif h < 180.0
        (0.0, c, x)
    elseif h < 240.0
        (0.0, x, c)
    elseif h < 300.0
        (x, 0.0, c)
    else
        (c, 0.0, x)
    end
    UInt8(clamp(round(Int, (r1 + m) * 255), 0, 255)),
    UInt8(clamp(round(Int, (g1 + m) * 255), 0, 255)),
    UInt8(clamp(round(Int, (b1 + m) * 255), 0, 255))
end

function _scale_rgb(r::Int, g::Int, b::Int, s::Float64)
    UInt8(clamp(round(Int, r * s), 0, 255)),
    UInt8(clamp(round(Int, g * s), 0, 255)),
    UInt8(clamp(round(Int, b * s), 0, 255))
end

# ── Scene names ─────────────────────────────────────────────────────

const SIXEL_SCENE_NAMES = Dict(
    sixel_plasma     => "Plasma",
    sixel_terrain    => "Terrain",
    sixel_mandelbrot => "Mandelbrot",
    sixel_rings      => "Interference",
)

# ── View ────────────────────────────────────────────────────────────

function view(m::SixelDemoModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    canvas_area = rows[2]
    footer = rows[3]

    # Header
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    sname = SIXEL_SCENE_NAMES[m.scene]
    dp = decay_params()
    set_string!(buf, header.x + 2, header.y,
                "PixelImage Demo", tstyle(:primary, bold=true))
    set_string!(buf, header.x + 19, header.y,
                " $(DOT) $(sname) $(DOT) decay=$(round(dp.decay; digits=2)) jitter=$(round(dp.jitter; digits=2)) rot=$(round(dp.rot_prob; digits=2)) noise=$(round(dp.noise_scale; digits=2))",
                tstyle(:text_dim))

    # PixelImage widget
    cw = canvas_area.width
    ch = canvas_area.height
    if cw >= 4 && ch >= 2
        img = PixelImage(cw, ch; decay=dp)
        if m.scene == sixel_plasma
            _draw_plasma!(img, m.tick)
        elseif m.scene == sixel_terrain
            _draw_terrain!(img, m.tick)
        elseif m.scene == sixel_mandelbrot
            _draw_mandelbrot!(img, m.tick)
        else
            _draw_rings!(img, m.tick)
        end
        render(img, canvas_area, f; tick=m.tick)
    end

    # Footer
    render(StatusBar(
        left=[Span("  [1-4]scene [p]ause [Ctrl+S]decay settings ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function sixel_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(SixelDemoModel(); fps=20)
end
