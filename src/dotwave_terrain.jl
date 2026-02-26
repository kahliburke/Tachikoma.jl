# ═══════════════════════════════════════════════════════════════════════
# Dot Waves ── rolling hills terrain rendered in braille
#
# Layered mountain ridgelines receding into the distance.  Each layer
# is a terrain profile at a different depth, drawn as a band of braille
# dots.  Near layers are thick and bright; far layers are thin and dim.
# The wave heightmap undulates over time → rolling hills.
# ═══════════════════════════════════════════════════════════════════════

# ── Backend-aware dot-space helpers (used by dotwave, phylo, clado) ────
# These let terrain/tree renderers produce braille OR block output
# depending on render_backend().

@inline _use_block_backend() = render_backend() == block_backend
@inline _dots_per_h(ub::Bool) = ub ? 2 : 4
@inline _dot_cy(y::Int, ub::Bool) = ub ? (y ÷ 2 + 1) : (y ÷ 4 + 1)
@inline _dot_sub_y(y::Int, ub::Bool) = ub ? (y % 2) : (y % 4)
@inline _dot_bit(sub_x::Int, sub_y::Int, ub::Bool) =
    ub ? (UInt8(1) << (sub_y * 2 + sub_x)) : BRAILLE_MAP[sub_y + 1][sub_x + 1]
@inline _dot_char(bits::UInt8, ub::Bool) =
    ub ? QUADRANT_LUT[bits + 1] : Char(BRAILLE_OFFSET + bits)

struct WaveLayer
    angle::Float64
    freq::Float64
    amp::Float64
    speed::Float64
end

struct DotWavePreset
    name::String
    layers::Vector{WaveLayer}
    noise_amt::Float64
    noise_drift::Float64
end

# angle ≈ π/2 → ridges perpendicular to depth (multiple hills front-to-back)
# angle ≈ 0   → ridges along depth (lateral variation along each ridge)
const DOTWAVE_PRESETS = DotWavePreset[
    DotWavePreset("Gentle", [
        WaveLayer(π/2,   4.0, 0.5, 0.025),
        WaveLayer(π/3,   2.5, 0.3, 0.018),
        WaveLayer(0.0,   2.0, 0.2, 0.012),
    ], 0.12, 0.005),
    DotWavePreset("Turbulent", [
        WaveLayer(π/2,   6.0, 0.35, 0.05),
        WaveLayer(π/3,   5.0, 0.3, 0.04),
        WaveLayer(0.0,   7.0, 0.2, 0.06),
        WaveLayer(π/6,   4.0, 0.15, 0.035),
    ], 0.2, 0.01),
    DotWavePreset("Ridges", [
        WaveLayer(π/2,   5.0, 0.55, 0.03),
        WaveLayer(π/2.3, 3.5, 0.3, 0.02),
        WaveLayer(0.0,   3.0, 0.15, 0.025),
    ], 0.08, 0.006),
    DotWavePreset("Vortex", [
        WaveLayer(π/4,   5.0, 0.35, 0.04),
        WaveLayer(3π/4,  5.0, 0.35, 0.04),
        WaveLayer(π/2,   3.0, 0.2, 0.025),
        WaveLayer(0.0,   3.0, 0.2, 0.025),
    ], 0.15, 0.008),
]

function _dotwave_height(wx::Float64, wz::Float64, t::Float64, preset::DotWavePreset)
    val = 0.0
    for layer in preset.layers
        ca = cos(layer.angle)
        sa = sin(layer.angle)
        rx = wx * ca - wz * sa
        val += layer.amp * sin(rx * layer.freq + t * layer.speed)
    end
    val += preset.noise_amt * (2.0 * fbm(wx * 2.0, wz * 2.0 + t * preset.noise_drift) - 1.0)
    val
end

"""
    _render_dotwave_terrain!(buf, area, tick, preset, amplitude, cam_height, speed;
                             color_transform=identity)

Parallax mountain silhouette renderer.  Draws `n_ridges` layered
mountain profiles in braille using painter's algorithm (far → near).
Each layer is a wave-modulated band whose top contour creates the
ridgeline.  Near ridges are tall, bright, and near the bottom of the
screen; far ridges are thin, dim, and near the horizon.

`color_transform(::ColorRGB) → ColorRGB` is applied to each cell's
final color (used by the background system to dim/desaturate).
"""
function _render_dotwave_terrain!(buf::Buffer, canvas_area::Rect, tick::Int,
                                  preset::DotWavePreset, amplitude::Float64,
                                  cam_height::Float64, speed::Float64;
                                  color_transform::Function=identity)
    t = Float64(tick) * speed

    cw = canvas_area.width
    ch = canvas_area.height
    (cw < 4 || ch < 2) && return

    ub = _use_block_backend()
    dot_w = cw * 2
    dot_h = ch * _dots_per_h(ub)

    dots = zeros(UInt8, cw, ch)
    cell_depth = fill(1.0, cw, ch)  # 1=far, 0=near; nearest layer wins
    cell_light = fill(0.5, cw, ch)

    horizon_frac = 0.10
    horizon_dot = round(Int, Float64(dot_h) * horizon_frac)
    terrain_span = Float64(dot_h - horizon_dot)
    world_scale = 0.15
    n_ridges = 14

    # Displacement scale: how many dots a unit of height moves the contour
    disp_scale = cam_height * 0.014 * Float64(dot_h)

    col_heights = Vector{Float64}(undef, cw)

    # ── Far → near (painter's algorithm): near layers paint over far ──
    for ridge_i in 1:n_ridges
        # near_frac: 0 = farthest, 1 = nearest
        near_frac = Float64(ridge_i) / Float64(n_ridges + 1)
        depth_frac = 1.0 - near_frac  # for coloring: 1=far, 0=near

        # Vertical base: gentle perspective compression
        # Power < 1 clusters ridges slightly near horizon; linear = 1.0
        base_dot_y = horizon_dot + round(Int, (near_frac ^ 1.15) * terrain_span)

        # Depth for wave function — far ridges at large z, near at small z
        z = 25.0 * (1.0 - near_frac) + 3.0 * near_frac

        # Near ridges have larger wave amplitude
        wave_amp = amplitude * (0.25 + 0.75 * near_frac)

        for col in 1:cw
            nx = (Float64(col) - 0.5) / Float64(cw)
            wx = (nx - 0.5) * z * 1.2  # spread laterally with depth
            col_heights[col] = _dotwave_height(wx * world_scale, z * world_scale, t, preset)
        end

        for col in 1:cw
            h = col_heights[col] * wave_amp

            # Slope shading
            hl = col > 1  ? col_heights[col - 1] : col_heights[col]
            hr = col < cw ? col_heights[col + 1] : col_heights[col]
            slope = (hr - hl) * wave_amp
            light = clamp(0.65 - slope * 1.5, 0.1, 1.0)

            # Ridge contour: displacement above base line
            top_y = base_dot_y - round(Int, h * disp_scale)
            top_y = clamp(top_y, 0, dot_h - 1)
            bot_y = min(base_dot_y, dot_h - 1)
            top_y > bot_y && continue

            for sub_x in 0:1
                dx = (col - 1) * 2 + sub_x
                (0 <= dx < dot_w) || continue

                for dy in top_y:bot_y
                    cy = _dot_cy(dy, ub)
                    (1 <= cy <= ch) || continue
                    sy = _dot_sub_y(dy, ub)
                    dots[col, cy] |= _dot_bit(sub_x, sy, ub)
                    # Near layer overwrites depth/light (painter's algorithm)
                    cell_depth[col, cy] = depth_frac
                    cell_light[col, cy] = light
                end
            end
        end
    end

    # ── Render with depth coloring ──
    th = theme()
    colors = (th.primary, th.accent, th.secondary)
    for cy in 1:ch
        for cx in 1:cw
            bx = canvas_area.x + cx - 1
            by = canvas_area.y + cy - 1
            bits = dots[cx, cy]
            bits == 0x00 && continue
            ch_char = _dot_char(bits, ub)

            z_n = cell_depth[cx, cy]
            light = cell_light[cx, cy]

            base_fg = color_wave(tick, cx, colors; speed=0.04, spread=0.1)
            fg = dim_color(base_fg, 1.0 - light)
            fg = dim_color(fg, z_n * 0.7)
            fg = color_transform(fg)

            set_char!(buf, bx, by, ch_char, Style(fg=fg))
        end
    end
end

const dotwave_height = _dotwave_height
const render_dotwave_terrain! = _render_dotwave_terrain!
