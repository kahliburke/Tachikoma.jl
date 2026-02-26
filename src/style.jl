# ═══════════════════════════════════════════════════════════════════════
# Geometry
# ═══════════════════════════════════════════════════════════════════════

struct Rect
    x::Int
    y::Int
    width::Int
    height::Int
end

Rect() = Rect(1, 1, 0, 0)
right(r::Rect) = r.x + r.width - 1
bottom(r::Rect) = r.y + r.height - 1
area(r::Rect) = r.width * r.height

function inner(r::Rect)
    (r.width < 2 || r.height < 2) && return Rect(r.x, r.y, 0, 0)
    Rect(r.x + 1, r.y + 1, r.width - 2, r.height - 2)
end

function margin(r::Rect; top::Int=0, right::Int=0, bottom::Int=0, left::Int=0)
    Rect(r.x + left, r.y + top,
         max(0, r.width - left - right),
         max(0, r.height - top - bottom))
end

shrink(r::Rect, n::Int) = margin(r; top=n, right=n, bottom=n, left=n)

function center(parent::Rect, width::Int, height::Int)
    w = min(width, parent.width)
    h = min(height, parent.height)
    x = parent.x + max(0, (parent.width - w) ÷ 2)
    y = parent.y + max(0, (parent.height - h) ÷ 2)
    Rect(x, y, w, h)
end

"""Center a widget within a parent rect using the widget's `intrinsic_size`."""
center(parent::Rect, widget) = center(parent, intrinsic_size(widget)...)

Base.contains(r::Rect, x::Int, y::Int) =
    x >= r.x && x <= right(r) && y >= r.y && y <= bottom(r)

function anchor(parent::Rect, width::Int, height::Int;
                h::Symbol=:center, v::Symbol=:center)
    w = min(width, parent.width)
    ht = min(height, parent.height)
    x = if h == :left
        parent.x
    elseif h == :right
        parent.x + parent.width - w
    else  # :center
        parent.x + max(0, (parent.width - w) ÷ 2)
    end
    y = if v == :top
        parent.y
    elseif v == :bottom
        parent.y + parent.height - ht
    else  # :center
        parent.y + max(0, (parent.height - ht) ÷ 2)
    end
    Rect(x, y, w, ht)
end

"""Anchor a widget within a parent rect using the widget's `intrinsic_size`."""
function anchor(parent::Rect, widget; h::Symbol=:center, v::Symbol=:center)
    sz = intrinsic_size(widget)
    sz === nothing && throw(ArgumentError(
        "Cannot anchor $(typeof(widget)): no intrinsic_size defined"))
    anchor(parent, sz[1], sz[2]; h=h, v=v)
end

# ═══════════════════════════════════════════════════════════════════════
# Colors
# ═══════════════════════════════════════════════════════════════════════

abstract type AbstractColor end
struct NoColor  <: AbstractColor end
struct Color256 <: AbstractColor; code::UInt8; end
struct ColorRGB <: AbstractColor; r::UInt8; g::UInt8; b::UInt8; end

Color256(n::Int) = Color256(UInt8(n))

Base.:(==)(::NoColor, ::NoColor) = true
Base.:(==)(a::Color256, b::Color256) = a.code == b.code
Base.:(==)(a::ColorRGB, b::ColorRGB) = (
    a.r == b.r && a.g == b.g && a.b == b.b
)
Base.:(==)(::AbstractColor, ::AbstractColor) = false

# Standard ANSI 16 colors (approximate RGB values)
const ANSI16_RGB = (
    (0x00,0x00,0x00), (0x80,0x00,0x00), (0x00,0x80,0x00), (0x80,0x80,0x00),
    (0x00,0x00,0x80), (0x80,0x00,0x80), (0x00,0x80,0x80), (0xc0,0xc0,0xc0),
    (0x80,0x80,0x80), (0xff,0x00,0x00), (0x00,0xff,0x00), (0xff,0xff,0x00),
    (0x00,0x00,0xff), (0xff,0x00,0xff), (0x00,0xff,0xff), (0xff,0xff,0xff),
)

const _XTERM_CUBE_STEPS = UInt8[0, 95, 135, 175, 215, 255]

function to_rgb(c::Color256)
    n = Int(c.code)
    if n < 16
        r, g, b = ANSI16_RGB[n + 1]
        return ColorRGB(UInt8(r), UInt8(g), UInt8(b))
    elseif n < 232
        idx = n - 16
        r = _XTERM_CUBE_STEPS[(idx ÷ 36) + 1]
        g = _XTERM_CUBE_STEPS[((idx % 36) ÷ 6) + 1]
        b = _XTERM_CUBE_STEPS[(idx % 6) + 1]
        return ColorRGB(r, g, b)
    else
        v = UInt8((n - 232) * 10 + 8)
        return ColorRGB(v, v, v)
    end
end
to_rgb(c::ColorRGB) = c

function color_lerp(a::ColorRGB, b::ColorRGB, t::Float64)
    t = clamp(t, 0.0, 1.0)
    ColorRGB(
        round(UInt8, a.r * (1 - t) + b.r * t),
        round(UInt8, a.g * (1 - t) + b.g * t),
        round(UInt8, a.b * (1 - t) + b.b * t),
    )
end

function color_lerp(a::Color256, b::Color256, t::Float64)
    color_lerp(to_rgb(a), to_rgb(b), t)
end

# ═══════════════════════════════════════════════════════════════════════
# Style
# ═══════════════════════════════════════════════════════════════════════

struct Style
    fg::AbstractColor
    bg::AbstractColor
    bold::Bool
    dim::Bool
    italic::Bool
    underline::Bool
    hyperlink::String
end

function Style(;
    fg::AbstractColor=NoColor(), bg::AbstractColor=NoColor(),
    bold=false, dim=false, italic=false, underline=false,
    hyperlink::String="",
)
    Style(fg, bg, bold, dim, italic, underline, hyperlink)
end

const RESET = Style()

Base.:(==)(a::Style, b::Style) = (
    a.fg == b.fg && a.bg == b.bg && a.bold == b.bold &&
    a.dim == b.dim && a.italic == b.italic &&
    a.underline == b.underline && a.hyperlink == b.hyperlink
)

# ═══════════════════════════════════════════════════════════════════════
# Themes
# ═══════════════════════════════════════════════════════════════════════

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

#  Kokaku  ── Ghost in the Shell / Tachikoma blue
#  Cool, electric, precise. Digital rain on glass.
const KOKAKU = Theme(
    "kokaku",
    Color256(66),   # border: dark cyan
    Color256(75),   # border_focus: steel blue
    Color256(252),  # text: light gray
    Color256(242),  # text_dim: medium gray
    Color256(159),  # text_bright: pale cyan
    Color256(75),   # primary: tachikoma blue
    Color256(68),   # secondary: muted blue
    Color256(117),  # accent: bright cyan
    Color256(114),  # success: sage green
    Color256(221),  # warning: yellow
    Color256(168),  # error: rose
    Color256(81),   # title: sky blue
)

#  Esper  ── Blade Runner / old phosphor terminal
#  Warm, worn, atmospheric. Amber glow in the rain.
const ESPER = Theme(
    "esper",
    Color256(94),   # border: dark amber
    Color256(136),  # border_focus: amber
    Color256(223),  # text: warm white
    Color256(137),  # text_dim: faded brown
    Color256(222),  # text_bright: bright amber
    Color256(179),  # primary: gold
    Color256(130),  # secondary: dark orange
    Color256(215),  # accent: pale orange
    Color256(143),  # success: olive
    Color256(208),  # warning: orange
    Color256(131),  # error: brick red
    Color256(179),  # title: gold
)

#  Motoko  ── Major Kusanagi / purple neon
#  Deep, confident, electric. Neon signs in the rain.
const MOTOKO = Theme(
    "motoko",
    Color256(97),   # border: dusty violet
    Color256(135),  # border_focus: medium purple
    Color256(253),  # text: near-white
    Color256(243),  # text_dim: gray
    Color256(183),  # text_bright: light lavender
    Color256(135),  # primary: purple
    Color256(96),   # secondary: dark magenta
    Color256(171),  # accent: orchid pink
    Color256(114),  # success: sage green
    Color256(215),  # warning: pale orange
    Color256(204),  # error: hot pink
    Color256(141),  # title: lavender
)

#  Kaneda  ── Akira / Neo-Tokyo neon
#  Aggressive, fast, loud. Motorcycle tail-lights at 200mph.
const KANEDA = Theme(
    "kaneda",
    Color256(88),   # border: dark red
    Color256(196),  # border_focus: bright red
    Color256(224),  # text: warm pink-white
    Color256(240),  # text_dim: gray
    Color256(217),  # text_bright: salmon
    Color256(196),  # primary: red
    Color256(202),  # secondary: orange-red
    Color256(213),  # accent: hot pink
    Color256(156),  # success: light green
    Color256(220),  # warning: gold
    Color256(196),  # error: pure red
    Color256(209),  # title: salmon
)

#  Neuromancer  ── Gibson / green phosphor terminal
#  The original. Monochrome green on black. The matrix before The Matrix.
const NEUROMANCER = Theme(
    "neuromancer",
    Color256(22),   # border: dark green
    Color256(34),   # border_focus: green
    Color256(120),  # text: light green
    Color256(238),  # text_dim: dark gray (barely visible)
    Color256(156),  # text_bright: bright green-white
    Color256(40),   # primary: green
    Color256(28),   # secondary: forest green
    Color256(46),   # accent: neon green
    Color256(82),   # success: lime
    Color256(178),  # warning: dark yellow
    Color256(160),  # error: dark red
    Color256(48),   # title: cyan-green
)

#  Catppuccin  ── modern pastel / easy on the eyes
#  Soft, cozy, readable. Late-night coding without the strain.
const CATPPUCCIN = Theme(
    "catppuccin",
    Color256(60),   # border: muted mauve
    Color256(103),  # border_focus: light mauve
    Color256(189),  # text: lavender
    Color256(244),  # text_dim: overlay
    Color256(195),  # text_bright: sky
    Color256(110),  # primary: blue
    Color256(103),  # secondary: mauve
    Color256(174),  # accent: pink
    Color256(150),  # success: green
    Color256(222),  # warning: yellow
    Color256(167),  # error: red
    Color256(152),  # title: teal
)

#  Solarized  ── Ethan Schoonover / precision-crafted color science
#  Balanced, deliberate, timeless. Lab-tuned for readability.
const SOLARIZED = Theme(
    "solarized",
    Color256(66),   # border: cyan-ish base
    Color256(37),   # border_focus: cyan
    Color256(254),  # text: base3
    Color256(245),  # text_dim: base1
    Color256(230),  # text_bright: base3 bright
    Color256(33),   # primary: blue
    Color256(37),   # secondary: cyan
    Color256(136),  # accent: yellow
    Color256(64),   # success: green
    Color256(166),  # warning: orange
    Color256(160),  # error: red
    Color256(125),  # title: magenta
)

#  Dracula  ── dark elegant / high-contrast pastels on charcoal
#  Night owl. Velvet darkness with candy-colored highlights.
const DRACULA = Theme(
    "dracula",
    Color256(61),   # border: comment purple
    Color256(141),  # border_focus: purple
    Color256(253),  # text: foreground
    Color256(243),  # text_dim: comment
    Color256(231),  # text_bright: bright white
    Color256(141),  # primary: purple
    Color256(61),   # secondary: dark purple
    Color256(84),   # accent: green
    Color256(84),   # success: green
    Color256(228),  # warning: yellow
    Color256(210),  # error: red/pink
    Color256(117),  # title: cyan
)

#  Outrun  ── synthwave / retrowave sunset gradient
#  Chrome, neon, sunset. VHS tracking lines on a Miami highway.
const OUTRUN = Theme(
    "outrun",
    Color256(54),   # border: deep purple
    Color256(129),  # border_focus: bright magenta
    Color256(225),  # text: light pink
    Color256(243),  # text_dim: gray
    Color256(231),  # text_bright: white
    Color256(199),  # primary: hot magenta
    Color256(57),   # secondary: blue-violet
    Color256(51),   # accent: electric cyan
    Color256(48),   # success: cyan-green
    Color256(214),  # warning: orange
    Color256(196),  # error: red
    Color256(213),  # title: pink
)

#  Zenburn  ── low-contrast / dark warm / easy fatigue-free palette
#  Quiet, earthy, restful. A fireplace in a cabin at midnight.
const ZENBURN = Theme(
    "zenburn",
    Color256(239),  # border: dark gray-brown
    Color256(108),  # border_focus: sage
    Color256(187),  # text: warm beige
    Color256(241),  # text_dim: dark gray
    Color256(230),  # text_bright: pale cream
    Color256(108),  # primary: sage green
    Color256(66),   # secondary: teal
    Color256(174),  # accent: dusty rose
    Color256(108),  # success: sage
    Color256(180),  # warning: tan-yellow
    Color256(167),  # error: muted red
    Color256(116),  # title: aqua
)

#  Iceberg  ── cold blue monochrome / arctic clarity
#  Still, frozen, sharp. Blue light on snow at 4 AM.
const ICEBERG = Theme(
    "iceberg",
    Color256(60),   # border: slate blue
    Color256(110),  # border_focus: steel blue
    Color256(189),  # text: pale blue-white
    Color256(103),  # text_dim: muted blue
    Color256(195),  # text_bright: ice white
    Color256(110),  # primary: steel blue
    Color256(67),   # secondary: dark slate
    Color256(150),  # accent: frost green
    Color256(150),  # success: frost green
    Color256(186),  # warning: pale gold
    Color256(168),  # error: muted rose
    Color256(117),  # title: light blue
)

# All themes for iteration
const ALL_THEMES = (KOKAKU, ESPER, MOTOKO, KANEDA, NEUROMANCER, CATPPUCCIN,
                    SOLARIZED, DRACULA, OUTRUN, ZENBURN, ICEBERG)

# Active theme
const THEME = Ref{Theme}(KOKAKU)
"""
    theme() → Theme

Return the currently active theme.
"""
theme() = THEME[]

"""
    set_theme!(t::Theme)
    set_theme!(name::Symbol)

Set the active theme by value or by name (e.g., `:kokaku`, `:motoko`).
"""
set_theme!(t::Theme) = (THEME[] = t)

function set_theme!(name::Symbol)
    for t in ALL_THEMES
        t.name == string(name) && (THEME[] = t; return t)
    end
    error("Unknown theme: $name")
end

# ── Persistence via Preferences.jl ────────────────────────────────────

function save_theme(name::String)
    @set_preferences!("theme" => name)
end

function load_theme!()
    name = @load_preference("theme", "kokaku")
    set_theme!(Symbol(name))
end

# Animations preference
const ANIMATIONS_ENABLED = Ref(true)
animations_enabled() = ANIMATIONS_ENABLED[]

function toggle_animations!()
    ANIMATIONS_ENABLED[] = !ANIMATIONS_ENABLED[]
    @set_preferences!("animations" => ANIMATIONS_ENABLED[])
end

function load_animations!()
    ANIMATIONS_ENABLED[] = @load_preference("animations", true)
end

# ── Render backend preference ─────────────────────────────────────────

@enum RenderBackend braille_backend block_backend sixel_backend
const RENDER_BACKEND = Ref(braille_backend)
render_backend() = RENDER_BACKEND[]

# Cycle order for settings toggle (sixel is now a dedicated widget, not a global backend)
const _BACKEND_CYCLE = (braille_backend, block_backend)

function set_render_backend!(b::RenderBackend)
    RENDER_BACKEND[] = b
    @set_preferences!("render_backend" => string(b))
end

function cycle_render_backend!(dir::Int=1)
    cur = RENDER_BACKEND[]
    idx = findfirst(==(cur), _BACKEND_CYCLE)
    next = _BACKEND_CYCLE[mod1(idx + dir, length(_BACKEND_CYCLE))]
    set_render_backend!(next)
end

function load_render_backend!()
    name = @load_preference("render_backend", "braille_backend")
    RENDER_BACKEND[] = if name == "block_backend"
        block_backend
    else
        # "sixel_backend" gracefully migrates to braille (sixel is now a widget)
        braille_backend
    end
end

# ── Graphics protocol (sixel vs kitty) ───────────────────────────────

@enum GraphicsProtocol gfx_none gfx_sixel gfx_kitty
const GRAPHICS_PROTOCOL = Ref(gfx_none)
graphics_protocol() = GRAPHICS_PROTOCOL[]

# ── Decay parameters (bit-rot aesthetic) ──────────────────────────────

mutable struct DecayParams
    decay::Float64       # 0.0-1.0 master intensity
    jitter::Float64      # 0.0-1.0 RGB noise per pixel
    rot_prob::Float64    # 0.0-1.0 pixel corruption probability
    noise_scale::Float64 # spatial fbm scale for desaturation
end
DecayParams() = DecayParams(0.0, 0.0, 0.0, 0.15)

const DECAY = Ref(DecayParams())
decay_params() = DECAY[]

function save_decay_params!()
    d = DECAY[]
    @set_preferences!("decay" => d.decay, "decay_jitter" => d.jitter,
                       "decay_rot_prob" => d.rot_prob, "decay_noise_scale" => d.noise_scale)
end

function load_decay_params!()
    DECAY[] = DecayParams(
        @load_preference("decay", 0.0), @load_preference("decay_jitter", 0.0),
        @load_preference("decay_rot_prob", 0.0), @load_preference("decay_noise_scale", 0.15))
end

"""
    tstyle(field::Symbol; bold=false, dim=false, italic=false, underline=false)

Create a `Style` using a color from the current theme. `field` is a theme color name
like `:primary`, `:accent`, `:text`, `:error`, etc.

# Example
```julia
tstyle(:primary, bold=true)  # bold text in the theme's primary color
```
"""
function tstyle(field::Symbol; bold=false, dim=false,
                italic=false, underline=false, hyperlink::String="")
    color = getfield(theme(), field)
    Style(; fg=color, bold, dim, italic, underline, hyperlink)
end

# ═══════════════════════════════════════════════════════════════════════
# ANSI output
# ═══════════════════════════════════════════════════════════════════════

write_fg(io::IO, ::NoColor) = nothing
function write_fg(io::IO, c::Color256)
    write(io, "\e[38;5;", string(Int(c.code)), 'm')
end
function write_fg(io::IO, c::ColorRGB)
    write(io, "\e[38;2;", string(Int(c.r)), ';',
          string(Int(c.g)), ';', string(Int(c.b)), 'm')
end

write_bg(io::IO, ::NoColor) = nothing
function write_bg(io::IO, c::Color256)
    write(io, "\e[48;5;", string(Int(c.code)), 'm')
end
function write_bg(io::IO, c::ColorRGB)
    write(io, "\e[48;2;", string(Int(c.r)), ';',
          string(Int(c.g)), ';', string(Int(c.b)), 'm')
end

function write_style(io::IO, s::Style)
    write(io, "\e[0m")
    write_fg(io, s.fg)
    write_bg(io, s.bg)
    s.bold && write(io, "\e[1m")
    s.dim && write(io, "\e[2m")
    s.italic && write(io, "\e[3m")
    s.underline && write(io, "\e[4m")
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Visual constants ── the bling
# ═══════════════════════════════════════════════════════════════════════

# Box drawing sets
const BOX_ROUNDED = (
    tl='╭', tr='╮', bl='╰', br='╯', h='─', v='│',
)
const BOX_HEAVY = (
    tl='┏', tr='┓', bl='┗', br='┛', h='━', v='┃',
)
const BOX_DOUBLE = (
    tl='╔', tr='╗', bl='╚', br='╝', h='═', v='║',
)
const BOX_PLAIN = (
    tl='┌', tr='┐', bl='└', br='┘', h='─', v='│',
)

# Block elements for bars and gradients (Tuples for safe indexing)
const BLOCKS = ('█', '▓', '▒', '░')
const BARS_H = ('▏', '▎', '▍', '▌', '▋', '▊', '▉', '█')
const BARS_V = ('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')

# Braille spinners ── the demo scene is alive
const SPINNER_BRAILLE = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']
const SPINNER_DOTS    = ['⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷']
const SPINNER_PIPE    = ['┤','┘','┴','└','├','┌','┬','┐']

# Markers
const BULLET = '›'
const MARKER = '▸'
const DOT    = '·'

# Scan-line separator ── subtle interlace effect
const SCANLINE = '╌'

# ═══════════════════════════════════════════════════════════════════════
# Tailwind CSS color palettes ── semantic named colors
# ═══════════════════════════════════════════════════════════════════════

# 256-color cube: codes 16–231 map to 6×6×6 RGB with xterm levels [0,95,135,175,215,255].
# Grayscale ramp: codes 232–255 map to grays 8,18,…,238.
# We find the closest Color256 to any hex color by brute-force RGB distance.

function hex_to_color256(hex::UInt32)
    tr = (hex >> 16) & 0xFF
    tg = (hex >> 8) & 0xFF
    tb = hex & 0xFF
    best_code = 0
    best_dist = typemax(Int)
    # Search the 6×6×6 color cube (codes 16–231)
    for code in 16:231
        idx = code - 16
        r = Int(_XTERM_CUBE_STEPS[(idx ÷ 36) + 1])
        g = Int(_XTERM_CUBE_STEPS[((idx % 36) ÷ 6) + 1])
        b = Int(_XTERM_CUBE_STEPS[(idx % 6) + 1])
        d = (Int(tr) - r)^2 + (Int(tg) - g)^2 + (Int(tb) - b)^2
        if d < best_dist
            best_dist = d
            best_code = code
        end
    end
    # Search the grayscale ramp (codes 232–255)
    for code in 232:255
        v = (code - 232) * 10 + 8
        d = (Int(tr) - v)^2 + (Int(tg) - v)^2 + (Int(tb) - v)^2
        if d < best_dist
            best_dist = d
            best_code = code
        end
    end
    Color256(best_code)
end

const TailwindPalette = NamedTuple{
    (:c50,:c100,:c200,:c300,:c400,:c500,:c600,:c700,:c800,:c900,:c950),
    NTuple{11, Color256}
}

function _tw(hexes::NTuple{11, UInt32})::TailwindPalette
    (c50=hex_to_color256(hexes[1]),  c100=hex_to_color256(hexes[2]),
     c200=hex_to_color256(hexes[3]), c300=hex_to_color256(hexes[4]),
     c400=hex_to_color256(hexes[5]), c500=hex_to_color256(hexes[6]),
     c600=hex_to_color256(hexes[7]), c700=hex_to_color256(hexes[8]),
     c800=hex_to_color256(hexes[9]), c900=hex_to_color256(hexes[10]),
     c950=hex_to_color256(hexes[11]))
end

const SLATE   = _tw((0xf8fafc, 0xf1f5f9, 0xe2e8f0, 0xcbd5e1, 0x94a3b8, 0x64748b, 0x475569, 0x334155, 0x1e293b, 0x0f172a, 0x020617))
const GRAY    = _tw((0xf9fafb, 0xf3f4f6, 0xe5e7eb, 0xd1d5db, 0x9ca3af, 0x6b7280, 0x4b5563, 0x374151, 0x1f2937, 0x111827, 0x030712))
const ZINC    = _tw((0xfafafa, 0xf4f4f5, 0xe4e4e7, 0xd4d4d8, 0xa1a1aa, 0x71717a, 0x52525b, 0x3f3f46, 0x27272a, 0x18181b, 0x09090b))
const NEUTRAL = _tw((0xfafafa, 0xf5f5f5, 0xe5e5e5, 0xd4d4d4, 0xa3a3a3, 0x737373, 0x525252, 0x404040, 0x262626, 0x171717, 0x0a0a0a))
const STONE   = _tw((0xfafaf9, 0xf5f5f4, 0xe7e5e4, 0xd6d3d1, 0xa8a29e, 0x78716c, 0x57534e, 0x44403c, 0x292524, 0x1c1917, 0x0c0a09))
const RED     = _tw((0xfef2f2, 0xfee2e2, 0xfecaca, 0xfca5a5, 0xf87171, 0xef4444, 0xdc2626, 0xb91c1c, 0x991b1b, 0x7f1d1d, 0x450a0a))
const ORANGE  = _tw((0xfff7ed, 0xffedd5, 0xfed7aa, 0xfdba74, 0xfb923c, 0xf97316, 0xea580c, 0xc2410c, 0x9a3412, 0x7c2d12, 0x431407))
const AMBER   = _tw((0xfffbeb, 0xfef3c7, 0xfde68a, 0xfcd34d, 0xfbbf24, 0xf59e0b, 0xd97706, 0xb45309, 0x92400e, 0x78350f, 0x451a03))
const YELLOW  = _tw((0xfefce8, 0xfef9c3, 0xfef08a, 0xfde047, 0xfacc15, 0xeab308, 0xca8a04, 0xa16207, 0x854d0e, 0x713f12, 0x422006))
const LIME    = _tw((0xf7fee7, 0xecfccb, 0xd9f99d, 0xbef264, 0xa3e635, 0x84cc16, 0x65a30d, 0x4d7c0f, 0x3f6212, 0x365314, 0x1a2e05))
const GREEN   = _tw((0xf0fdf4, 0xdcfce7, 0xbbf7d0, 0x86efac, 0x4ade80, 0x22c55e, 0x16a34a, 0x15803d, 0x166534, 0x14532d, 0x052e16))
const EMERALD = _tw((0xecfdf5, 0xd1fae5, 0xa7f3d0, 0x6ee7b7, 0x34d399, 0x10b981, 0x059669, 0x047857, 0x065f46, 0x064e3b, 0x022c22))
const TEAL    = _tw((0xf0fdfa, 0xccfbf1, 0x99f6e4, 0x5eead4, 0x2dd4bf, 0x14b8a6, 0x0d9488, 0x0f766e, 0x115e59, 0x134e4a, 0x042f2e))
const CYAN    = _tw((0xecfeff, 0xcffafe, 0xa5f3fc, 0x67e8f9, 0x22d3ee, 0x06b6d4, 0x0891b2, 0x0e7490, 0x155e75, 0x164e63, 0x083344))
const SKY     = _tw((0xf0f9ff, 0xe0f2fe, 0xbae6fd, 0x7dd3fc, 0x38bdf8, 0x0ea5e9, 0x0284c7, 0x0369a1, 0x075985, 0x0c4a6e, 0x082f49))
const BLUE    = _tw((0xeff6ff, 0xdbeafe, 0xbfdbfe, 0x93c5fd, 0x60a5fa, 0x3b82f6, 0x2563eb, 0x1d4ed8, 0x1e40af, 0x1e3a8a, 0x172554))
const INDIGO  = _tw((0xeef2ff, 0xe0e7ff, 0xc7d2fe, 0xa5b4fc, 0x818cf8, 0x6366f1, 0x4f46e5, 0x4338ca, 0x3730a3, 0x312e81, 0x1e1b4b))
const VIOLET  = _tw((0xf5f3ff, 0xede9fe, 0xddd6fe, 0xc4b5fd, 0xa78bfa, 0x8b5cf6, 0x7c3aed, 0x6d28d9, 0x5b21b6, 0x4c1d95, 0x2e1065))
const PURPLE  = _tw((0xfaf5ff, 0xf3e8ff, 0xe9d5ff, 0xd8b4fe, 0xc084fc, 0xa855f7, 0x9333ea, 0x7e22ce, 0x6b21a8, 0x581c87, 0x3b0764))
const FUCHSIA = _tw((0xfdf4ff, 0xfae8ff, 0xf5d0fe, 0xf0abfc, 0xe879f9, 0xd946ef, 0xc026d3, 0xa21caf, 0x86198f, 0x701a75, 0x4a044e))
const PINK    = _tw((0xfdf2f8, 0xfce7f3, 0xfbcfe8, 0xf9a8d4, 0xf472b6, 0xec4899, 0xdb2777, 0xbe185d, 0x9d174d, 0x831843, 0x500724))
const ROSE    = _tw((0xfff1f2, 0xffe4e6, 0xfecdd3, 0xfda4af, 0xfb7185, 0xf43f5e, 0xe11d48, 0xbe123c, 0x9f1239, 0x881337, 0x4c0519))
