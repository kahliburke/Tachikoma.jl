# Styling & Themes

Tachikoma provides a comprehensive styling system with ANSI 256 colors, true RGB colors, text attributes, and a theme engine with 11 built-in palettes.

## Style

`Style` controls how text and backgrounds appear:

<!-- tachi:noeval -->
```julia
Style(; fg=NoColor(), bg=NoColor(), bold=false, dim=false,
        italic=false, underline=false)
```

<!-- tachi:widget style_demo w=40 h=2
set_string!(buf, area.x, area.y, "Explicit Style ", Style(fg=Color256(196), bg=Color256(0), bold=true))
set_string!(buf, area.x, area.y + 1, "Theme Style ", tstyle(:primary, bold=true))
-->
```julia
# Explicit style
s = Style(fg=Color256(196), bg=Color256(0), bold=false, italic=true)

# Theme-aware style (preferred)
s = tstyle(:primary, bold=true)
```

## Color Types

### Color256

ANSI 256-color palette (0–255):

<!-- tachi:widget color256_swatches w=40 h=4
set_string!(buf, area.x, area.y,     "████", Style(fg=Color256(196)))
set_string!(buf, area.x + 5, area.y,     "196  bright red", tstyle(:text))
set_string!(buf, area.x, area.y + 1, "████", Style(fg=Color256(46)))
set_string!(buf, area.x + 5, area.y + 1, "46   green", tstyle(:text))
set_string!(buf, area.x, area.y + 2, "████", Style(fg=Color256(0)))
set_string!(buf, area.x + 5, area.y + 2, "0    black", tstyle(:text))
set_string!(buf, area.x, area.y + 3, "████", Style(fg=Color256(255)))
set_string!(buf, area.x + 5, area.y + 3, "255  white", tstyle(:text))
-->
```julia
Color256(196)     # bright red
Color256(46)      # green
Color256(0)       # black
Color256(255)     # white
```

### ColorRGB

True 24-bit RGB color:

<!-- tachi:widget colorrgb_swatches w=44 h=2
set_string!(buf, area.x, area.y,     "████", Style(fg=ColorRGB(255, 100, 50)))
set_string!(buf, area.x + 5, area.y,     "rgb(255,100,50)  orange", tstyle(:text))
set_string!(buf, area.x, area.y + 1, "████", Style(fg=ColorRGB(0x1a, 0x1b, 0x2e)))
set_string!(buf, area.x + 5, area.y + 1, "rgb(26,27,46)    dark blue", tstyle(:text))
-->
```julia
ColorRGB(255, 100, 50)   # orange
ColorRGB(0x1a, 0x1b, 0x2e)  # dark blue
```

### NoColor

Transparent / terminal default:

<!-- tachi:noeval -->
```julia
NoColor()   # inherits terminal default
```

## Theme-Aware Styles with `tstyle`

The [`tstyle`](api.md#Tachikoma.tstyle) function creates styles from the current theme's color fields:

<!-- tachi:widget tstyle_demo w=44 h=4
set_string!(buf, area.x, area.y,     "■ primary    ", tstyle(:primary, bold=true))
set_string!(buf, area.x + 22, area.y,     "■ accent ", tstyle(:accent))
set_string!(buf, area.x, area.y + 1, "■ secondary  ", tstyle(:secondary))
set_string!(buf, area.x + 22, area.y + 1, "■ success", tstyle(:success))
set_string!(buf, area.x, area.y + 2, "■ warning    ", tstyle(:warning))
set_string!(buf, area.x + 22, area.y + 2, "■ error  ", tstyle(:error))
set_string!(buf, area.x, area.y + 3, "■ text       ", tstyle(:text))
set_string!(buf, area.x + 22, area.y + 3, "■ text_dim", tstyle(:text_dim))
-->
```julia
tstyle(:primary)                  # theme's primary color as fg
tstyle(:primary, bold=true)       # primary fg, bold
tstyle(:accent, dim=true)         # accent fg, dimmed
tstyle(:error, underline=true)    # error fg, underlined
```

Available theme fields:

| Field | Usage |
|:------|:------|
| `:border` | Normal border color |
| `:border_focus` | Focused border color |
| `:text` | Standard text |
| `:text_dim` | Subdued text |
| `:text_bright` | Emphasized text |
| `:primary` | Primary accent |
| `:secondary` | Secondary accent |
| `:accent` | Highlight / interactive elements |
| `:success` | Success indicators |
| `:warning` | Warning indicators |
| `:error` | Error indicators |
| `:title` | Title text |

Always prefer `tstyle` over hardcoded colors — your app automatically adapts when the user switches themes.

## Themes

Tachikoma ships with 11 built-in themes:

| Theme | Constant | Description |
|:------|:---------|:------------|
| Kokaku | `KOKAKU` | Deep teal cyberpunk (default) |
| Esper | `ESPER` | Cool blue noir |
| Motoko | `MOTOKO` | Warm purple cyborg |
| Kaneda | `KANEDA` | Hot red/orange Neo-Tokyo |
| Neuromancer | `NEUROMANCER` | Green-on-dark hacker |
| Catppuccin | `CATPPUCCIN` | Warm pastel |
| Solarized | `SOLARIZED` | Ethan Schoonover's palette |
| Dracula | `DRACULA` | Dark purple classic |
| Outrun | `OUTRUN` | Neon synthwave |
| Zenburn | `ZENBURN` | Low-contrast warm |
| Iceberg | `ICEBERG` | Cool blue minimal |

### Theme API

```julia
theme()                    # get current Theme
set_theme!(KANEDA)         # set by Theme value
set_theme!(:kaneda)        # set by Symbol name
ALL_THEMES                 # tuple of all 11 themes
```

Theme changes take effect immediately — the next `view` call uses the new colors.

<!-- tachi:app theme_demo w=50 h=12 frames=240 fps=15 -->

### Theme Struct

Each [`Theme`](styling.md#themes) contains:

```julia
struct Theme
    name::String
    border::Color256
    border_focus::Color256
    text::Color256
    text_dim::Color256
    text_bright::Color256
    primary::Color256
    secondary::Color256
    accent::Color256
    success::Color256
    warning::Color256
    error::Color256
    title::Color256
end
```

## Color Utilities

### Interpolation and Manipulation

<!-- tachi:noeval -->
```julia
color_lerp(a::ColorRGB, b::ColorRGB, t)    # interpolate, t ∈ [0,1]
to_rgb(c::Color256) → ColorRGB              # convert palette → RGB
brighten(c::ColorRGB, amount) → ColorRGB    # brighten by 0–1
dim_color(c::ColorRGB, amount) → ColorRGB   # dim by 0–1
hue_shift(c::ColorRGB, degrees) → ColorRGB  # rotate hue
desaturate(c::ColorRGB, amount) → ColorRGB  # reduce saturation
```

### Animated Color

<!-- tachi:widget colorwave_demo w=50 h=2 frames=90 fps=15
th = theme()
colors = (th.primary, th.accent, th.secondary, th.success, th.warning, th.error)
for x in 0:(area.width - 1)
    c = color_wave(frame_idx, x, colors; speed=0.08, spread=0.15)
    set_char!(buf, area.x + x, area.y, '█', Style(fg=c))
    set_char!(buf, area.x + x, area.y + 1, '▓', Style(fg=c))
end
-->
<!-- tachi:noeval -->
```julia
# Smooth color cycling (see Animation section)
color_wave(tick, x, colors; speed=0.04, spread=0.08) → ColorRGB
```

## Render Backends

Tachikoma supports three rendering backends that affect how canvases and visual effects are drawn:

<!-- tachi:noeval -->
```julia
@enum RenderBackend braille_backend block_backend sixel_backend

render_backend()                    # get current
set_render_backend!(braille_backend)  # set + save
cycle_render_backend!(1)            # cycle forward
cycle_render_backend!(-1)           # cycle backward
```

| Backend | Resolution | Description |
|:--------|:-----------|:------------|
| `braille_backend` | 2×4 per cell | Unicode braille dots, works everywhere |
| `block_backend` | 2×2 per cell | Quadrant block characters, gap-free |
| `sixel_backend` | ~16×32 per cell | Pixel-perfect raster, Kitty or sixel |

## Decay Parameters

The decay system adds a "bit-rot" aesthetic — noise, jitter, and corruption effects:

<!-- tachi:noeval -->
```julia
mutable struct DecayParams
    decay::Float64        # 0–1 master intensity
    jitter::Float64       # 0–1 RGB noise
    rot_prob::Float64     # 0–1 corruption probability
    noise_scale::Float64  # spatial noise scale
end

decay_params() → DecayParams   # get current (mutable)
```

Adjust via the settings overlay (Ctrl+S) or programmatically. Values are saved via Preferences.jl.

## Box Styles

Four border box styles for `Block`:

```julia
BOX_ROUNDED    # ╭─╮╰─╯  (default)
BOX_HEAVY      # ┏━┓┗━┛
BOX_DOUBLE     # ╔═╗╚═╝
BOX_PLAIN      # ┌─┐└─┘
```

```julia
Block(title="Panel", box=BOX_HEAVY)
```

## Visual Constants

```julia
DOT = '·'                              # separator dot
BARS_V = ('▁','▂','▃','▄','▅','▆','▇','█')  # vertical bar chars
BARS_H = ('▏','▎','▍','▌','▋','▊','▉','█')  # horizontal bar chars
BLOCKS = ('█','▓','▒','░')             # density blocks
SCANLINE = '╌'                         # interlace separator
MARKER = '▸'                           # list selection marker
SPINNER_BRAILLE = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']
SPINNER_DOTS = ['⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷']
```
