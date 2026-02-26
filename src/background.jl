# ═══════════════════════════════════════════════════════════════════════
# Background System ── animated textures behind foreground UI
#
# Composable, opt-in backgrounds.  Any view can render a background
# into any Rect of the buffer — a specific panel, a widget interior,
# or the entire screen.  Foreground widgets draw on top, naturally
# overwriting background cells where they write.
#
# Usage in a view function:
#
#   bg = DotWaveBackground()
#   render_background!(bg, f.buffer, panel_area, m.tick;
#                      brightness=0.25, saturation=0.4, speed=0.5)
#   # … then render foreground widgets on top …
#
# ═══════════════════════════════════════════════════════════════════════

abstract type Background end

# ── Global background config ──────────────────────────────────────────

mutable struct BackgroundConfig
    brightness::Float64    # 0-1, default 0.3
    saturation::Float64    # 0-1, default 0.5
    speed::Float64         # 0-1, default 0.5
end
BackgroundConfig() = BackgroundConfig(0.3, 0.5, 0.5)

const BG_CONFIG = Ref(BackgroundConfig())
bg_config() = BG_CONFIG[]

function save_bg_config!()
    c = BG_CONFIG[]
    @set_preferences!("bg_brightness" => c.brightness,
                       "bg_saturation" => c.saturation,
                       "bg_speed" => c.speed)
end

function load_bg_config!()
    BG_CONFIG[] = BackgroundConfig(
        @load_preference("bg_brightness", 0.3),
        @load_preference("bg_saturation", 0.5),
        @load_preference("bg_speed", 0.5))
end

# ── Color adjustment ─────────────────────────────────────────────────

function desaturate(c::ColorRGB, amount::Float64)
    gray = 0.299 * Float64(c.r) + 0.587 * Float64(c.g) + 0.114 * Float64(c.b)
    t = clamp(amount, 0.0, 1.0)
    ColorRGB(
        round(UInt8, clamp(Float64(c.r) * (1 - t) + gray * t, 0, 255)),
        round(UInt8, clamp(Float64(c.g) * (1 - t) + gray * t, 0, 255)),
        round(UInt8, clamp(Float64(c.b) * (1 - t) + gray * t, 0, 255)),
    )
end

function _apply_bg_adjustments(c::ColorRGB, brightness::Float64, saturation::Float64)
    c = desaturate(c, 1.0 - saturation)
    dim_color(c, 1.0 - brightness)
end

# ── Public API ────────────────────────────────────────────────────────

"""
    render_background!(bg, buf, area, tick; brightness=0.3, saturation=0.5, speed=0.5)

Render an animated background texture into `area` of `buf`.

Call this at the start of your `view()` function, before rendering
foreground widgets.  Foreground writes will naturally overwrite the
background in cells they touch.

- `brightness` (0–1): master brightness of background colors
- `saturation` (0–1): color saturation (0 = grayscale)
- `speed` (>0): animation speed multiplier applied to `tick`
"""
function render_background!(bg::Background, buf::Buffer, area::Rect, tick::Int;
                            brightness::Float64=bg_config().brightness,
                            saturation::Float64=bg_config().saturation,
                            speed::Float64=bg_config().speed)
    scaled_tick = round(Int, Float64(tick) * speed)
    color_fn = c -> _apply_bg_adjustments(c, brightness, saturation)
    _render_bg!(bg, buf, area, scaled_tick, color_fn)
end

# Fallback — subtypes override _render_bg!
function _render_bg!(::Background, ::Buffer, ::Rect, ::Int, ::Function) end

# ═══════════════════════════════════════════════════════════════════════
# DotWave Background ── rolling hills terrain texture
# ═══════════════════════════════════════════════════════════════════════

struct DotWaveBackground <: Background
    preset_idx::Int
    amplitude::Float64
    cam_height::Float64
end

DotWaveBackground(; preset::Int=1, amplitude::Float64=3.0, cam_height::Float64=6.0) =
    DotWaveBackground(preset, amplitude, cam_height)

function _render_bg!(bg::DotWaveBackground, buf::Buffer, area::Rect,
                     tick::Int, color_fn::Function)
    preset = DOTWAVE_PRESETS[clamp(bg.preset_idx, 1, length(DOTWAVE_PRESETS))]
    _render_dotwave_terrain!(buf, area, tick, preset, bg.amplitude,
                              bg.cam_height, 1.0; color_transform=color_fn)
end

# ═══════════════════════════════════════════════════════════════════════
# PhyloTree Background ── radial phylogenetic tree texture
# ═══════════════════════════════════════════════════════════════════════

struct PhyloTreeBackground <: Background
    preset_idx::Int
    tree::PhyloTree   # pre-generated, cached
end

function PhyloTreeBackground(; preset::Int=1)
    idx = clamp(preset, 1, length(PHYLO_PRESETS))
    tree = _generate_phylo_tree(PHYLO_PRESETS[idx])
    PhyloTreeBackground(idx, tree)
end

function _render_bg!(bg::PhyloTreeBackground, buf::Buffer, area::Rect,
                     tick::Int, color_fn::Function)
    preset = PHYLO_PRESETS[clamp(bg.preset_idx, 1, length(PHYLO_PRESETS))]
    _render_phylo_tree!(buf, area, tick, bg.tree, preset;
                         color_transform=color_fn)
end

# ═══════════════════════════════════════════════════════════════════════
# Cladogram Background ── radial fan-layout cladogram texture
# ═══════════════════════════════════════════════════════════════════════

struct CladogramBackground <: Background
    preset_idx::Int
    tree::CladoTree
end

function CladogramBackground(; preset::Int=1)
    idx = clamp(preset, 1, length(CLADO_PRESETS))
    tree = _generate_clado_tree(CLADO_PRESETS[idx])
    CladogramBackground(idx, tree)
end

function _render_bg!(bg::CladogramBackground, buf::Buffer, area::Rect,
                     tick::Int, color_fn::Function)
    preset = CLADO_PRESETS[clamp(bg.preset_idx, 1, length(CLADO_PRESETS))]
    _render_clado_tree!(buf, area, tick, bg.tree, preset;
                         color_transform=color_fn)
end
