# Backgrounds

Tachikoma includes procedural animated backgrounds that render behind your UI. These are driven by the animation system and configurable through the settings overlay.

## Background System

All backgrounds subtype the abstract `Background` type and implement `render_background!`:

<!-- tachi:noeval -->
```julia
render_background!(bg, buf, area, tick;
                   brightness=0.3, saturation=0.5, speed=0.5)
```

### BackgroundConfig

Global configuration for background rendering:

<!-- tachi:noeval -->
```julia
mutable struct BackgroundConfig
    brightness::Float64    # 0–1, default 0.3
    saturation::Float64    # 0–1, default 0.5
    speed::Float64         # animation speed, default 0.5
end

bg_config() → BackgroundConfig   # get current (mutable)
```

Adjust via the settings overlay (Ctrl+S) or programmatically. Values persist via Preferences.jl.

## DotWaveBackground

Rolling dot-wave terrain with depth perspective:

<!-- tachi:widget bg_dotwave w=60 h=20 frames=60 fps=15 -->
```julia
bg = DotWaveBackground(; preset=1, amplitude=10.0, cam_height=6.0)
render_background!(bg, buf, area, tick; brightness=0.8, saturation=0.8, speed=1.5)
```

Uses layered wave functions to generate terrain height, rendered as dot characters with depth-based brightness. Multiple presets provide different terrain styles.

### DotWave Internals

<!-- tachi:noeval -->
```julia
struct WaveLayer
    freq::Float64
    amp::Float64
    phase_speed::Float64
end

# Available presets
DOTWAVE_PRESETS    # vector of DotWavePreset

# Low-level API
dotwave_height(x, z, tick, layers)    # compute height at point
render_dotwave_terrain!(buf, area, tick, preset; amplitude, cam_height)
```

## PhyloTreeBackground

Radial phylogenetic tree visualization:

<!-- tachi:widget bg_phylotree w=60 h=20 frames=60 fps=15 -->
```julia
bg = PhyloTreeBackground(; preset=1)
render_background!(bg, buf, area, tick; brightness=0.4, saturation=0.6, speed=0.5)
```

Generates and renders a branching tree structure radiating from the center, with animated growth and color cycling.

### PhyloTree API

<!-- tachi:noeval -->
```julia
struct PhyloBranch
    # branch geometry
end

struct PhyloTree
    branches::Vector{PhyloBranch}
end

# Available presets
PHYLO_PRESETS    # vector of PhyloTreePreset

# Low-level API
generate_phylo_tree(preset) → PhyloTree
render_phylo_tree!(buf, area, tree, tick; brightness, saturation, speed)
```

## CladogramBackground

Fan-layout cladogram (tree of life) visualization:

<!-- tachi:widget bg_cladogram w=60 h=20 frames=60 fps=15 -->
```julia
bg = CladogramBackground(; preset=1)
render_background!(bg, buf, area, tick; brightness=0.4, saturation=0.6, speed=0.5)
```

Similar to PhyloTreeBackground but uses a fan/semicircle layout for the branching structure.

### Cladogram API

<!-- tachi:noeval -->
```julia
struct CladoBranch
    # branch geometry
end

struct CladoTree
    branches::Vector{CladoBranch}
end

# Available presets
CLADO_PRESETS    # vector of CladoPreset

# Low-level API
generate_clado_tree(preset) → CladoTree
render_clado_tree!(buf, area, tree, tick; brightness, saturation, speed)
```

## Using Backgrounds

Render a background as the first step in your `view` function, then draw UI elements on top:

```julia
@kwdef mutable struct MyApp <: Model
    bg::DotWaveBackground = DotWaveBackground(; preset=1)
    tick::Int = 0
end

function view(m::MyApp, f::Frame)
    m.tick += 1
    buf = f.buffer
    cfg = bg_config()

    # Render background first
    render_background!(m.bg, buf, f.area, m.tick;
                       brightness=cfg.brightness,
                       saturation=cfg.saturation,
                       speed=cfg.speed)

    # Then render UI on top
    block = Block(title="Dashboard")
    inner = render(block, f.area, buf)
    # ...
end
```

## Color Utilities

<!-- tachi:noeval -->
```julia
desaturate(c::ColorRGB, amount::Float64) → ColorRGB
```

Reduce color saturation by `amount` (0 = no change, 1 = grayscale). Used internally by the background system to respect the saturation setting.
