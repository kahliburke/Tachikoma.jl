# ═══════════════════════════════════════════════════════════════════════
# Animation System — easing, tweens, springs, timelines
# ═══════════════════════════════════════════════════════════════════════

# ── Easing functions ─────────────────────────────────────────────────
# All map [0,1] → [0,1]

linear(t::Float64) = t

ease_in_quad(t::Float64) = t * t
ease_out_quad(t::Float64) = t * (2.0 - t)
ease_in_out_quad(t::Float64) = t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t

ease_in_cubic(t::Float64) = t * t * t
ease_out_cubic(t::Float64) = (t -= 1.0; t * t * t + 1.0)
ease_in_out_cubic(t::Float64) =
    t < 0.5 ? 4.0 * t * t * t : (t -= 1.0; 4.0 * t * t * t + 1.0) # Horner-ish

function ease_out_elastic(t::Float64)
    t == 0.0 && return 0.0
    t == 1.0 && return 1.0
    p = 0.3
    s = p / 4.0
    2.0^(-10.0 * t) * sin((t - s) * 2π / p) + 1.0
end

function ease_out_bounce(t::Float64)
    if t < 1.0 / 2.75
        7.5625 * t * t
    elseif t < 2.0 / 2.75
        t -= 1.5 / 2.75
        7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75
        t -= 2.25 / 2.75
        7.5625 * t * t + 0.9375
    else
        t -= 2.625 / 2.75
        7.5625 * t * t + 0.984375
    end
end

function ease_out_back(t::Float64)
    s = 1.70158
    t -= 1.0
    t * t * ((s + 1.0) * t + s) + 1.0
end

# ── Tween ────────────────────────────────────────────────────────────

mutable struct Tween
    from::Float64
    to::Float64
    duration::Int        # total frames
    elapsed::Int         # frames elapsed (starts at 0)
    easing::Function     # easing function
    loop::Symbol         # :none, :loop, :pingpong
end

function tween(from, to; duration::Int=30, easing::Function=ease_out_cubic, loop::Symbol=:none)
    Tween(Float64(from), Float64(to), duration, 0, easing, loop)
end

function value(tw::Tween)
    tw.duration <= 0 && return tw.to
    t = clamp(tw.elapsed / tw.duration, 0.0, 1.0)
    eased = tw.easing(t)
    tw.from + (tw.to - tw.from) * eased
end

function advance!(tw::Tween)
    tw.elapsed += 1
    if tw.elapsed >= tw.duration
        if tw.loop == :loop
            tw.elapsed = 0
        elseif tw.loop == :pingpong
            tw.from, tw.to = tw.to, tw.from
            tw.elapsed = 0
        end
    end
    tw
end

done(tw::Tween) = tw.loop == :none && tw.elapsed >= tw.duration

function reset!(tw::Tween)
    tw.elapsed = 0
    tw
end

# ── Spring ───────────────────────────────────────────────────────────

mutable struct Spring
    target::Float64
    value::Float64
    velocity::Float64
    stiffness::Float64
    damping::Float64
end

"""
    Spring(target; value=target, stiffness=180.0, damping=:critical)

Create a spring animation. `damping` can be a number or a symbol:
- `:critical` — no overshoot, fastest settling (2√stiffness)
- `:over`     — sluggish, no overshoot (2.5√stiffness)
- `:under`    — slight bounce (1.2√stiffness)
"""
function Spring(target::Real; value::Real=target, stiffness::Real=180.0,
                damping::Union{Real,Symbol}=:critical)
    k = Float64(stiffness)
    c = if damping isa Symbol
        base = 2.0 * sqrt(k)
        if damping === :critical
            base
        elseif damping === :over
            2.5 * sqrt(k)
        elseif damping === :under
            1.2 * sqrt(k)
        else
            error("Unknown damping regime: $damping (expected :critical, :over, or :under)")
        end
    else
        Float64(damping)
    end
    Spring(Float64(target), Float64(value), 0.0, k, c)
end

function advance!(s::Spring; dt::Float64=1.0/60.0)
    force = -s.stiffness * (s.value - s.target)
    damping_force = -s.damping * s.velocity
    s.velocity += (force + damping_force) * dt
    s.value += s.velocity * dt
    s
end

function settled(s::Spring; threshold::Float64=0.01)
    abs(s.velocity) < threshold && abs(s.value - s.target) < threshold
end

function retarget!(s::Spring, new_target::Real)
    s.target = Float64(new_target)
    s
end

# ── Timeline ─────────────────────────────────────────────────────────

struct TimelineEntry
    tween::Tween
    start_frame::Int
end

mutable struct Timeline
    entries::Vector{TimelineEntry}
    frame::Int
    loop::Bool
end

Timeline(entries::Vector{TimelineEntry}; loop::Bool=false) =
    Timeline(entries, 0, loop)

function advance!(tl::Timeline)
    tl.frame += 1
    for entry in tl.entries
        if tl.frame > entry.start_frame
            if !done(entry.tween)
                advance!(entry.tween)
            end
        end
    end
    # Handle looping
    if tl.loop && done(tl)
        total = _timeline_total_frames(tl)
        tl.frame = 0
        for entry in tl.entries
            reset!(entry.tween)
        end
    end
    tl
end

function done(tl::Timeline)
    tl.loop && return false
    for entry in tl.entries
        end_frame = entry.start_frame + entry.tween.duration
        tl.frame < end_frame && return false
    end
    true
end

function _timeline_total_frames(tl::Timeline)
    isempty(tl.entries) && return 0
    maximum(e.start_frame + e.tween.duration for e in tl.entries)
end

# Convenience builders

function sequence(tweens::Tween...)
    entries = TimelineEntry[]
    frame = 0
    for tw in tweens
        push!(entries, TimelineEntry(tw, frame))
        frame += tw.duration
    end
    Timeline(entries)
end

function stagger(tweens::Tween...; delay::Int=3)
    entries = TimelineEntry[]
    frame = 0
    for tw in tweens
        push!(entries, TimelineEntry(tw, frame))
        frame += delay
    end
    Timeline(entries)
end

function parallel(tweens::Tween...)
    entries = [TimelineEntry(tw, 0) for tw in tweens]
    Timeline(entries)
end

# ── Animator (per-Model helper) ──────────────────────────────────────

mutable struct Animator
    tweens::Dict{Symbol, Tween}
    springs::Dict{Symbol, Spring}
    timelines::Dict{Symbol, Timeline}
end

Animator() = Animator(Dict{Symbol,Tween}(), Dict{Symbol,Spring}(), Dict{Symbol,Timeline}())

function tick!(a::Animator)
    for tw in values(a.tweens)
        done(tw) || advance!(tw)
    end
    for s in values(a.springs)
        settled(s) || advance!(s)
    end
    for tl in values(a.timelines)
        done(tl) || advance!(tl)
    end
    a
end

function val(a::Animator, name::Symbol)
    haskey(a.tweens, name)    && return value(a.tweens[name])
    haskey(a.springs, name)   && return a.springs[name].value
    error("Animator has no animation named :$name")
end

function animate!(a::Animator, name::Symbol, tw::Tween)
    a.tweens[name] = tw
    a
end

function animate!(a::Animator, name::Symbol, s::Spring)
    a.springs[name] = s
    a
end

function animate!(a::Animator, name::Symbol, tl::Timeline)
    a.timelines[name] = tl
    a
end

# ═══════════════════════════════════════════════════════════════════════
# Organic animation utilities — noise, pulse, shimmer, gradients
#
# All respect animations_enabled(): return neutral values when off.
# Designed for subtle, ambient life in UI elements.
# ═══════════════════════════════════════════════════════════════════════

# ── Value noise (hash-based, no dependencies) ─────────────────────────
# Fast deterministic pseudo-noise for organic wobble. Not crypto — just
# visually smooth randomness seeded by position and time.

@inline function _hash_noise(n::Int)
    # Robert Jenkins' 32-bit integer hash
    n = (n + 0x165667b1) & 0xffffffff
    n = ((n ⊻ (n >> 16)) * 0x45d9f3b) & 0xffffffff
    n = ((n ⊻ (n >> 16)) * 0x45d9f3b) & 0xffffffff
    n = n ⊻ (n >> 16)
    (n & 0xffffffff) / 0xffffffff
end

@inline function _smooth(t::Float64)
    t * t * (3.0 - 2.0 * t)
end

"""
    noise(x::Float64) → Float64 ∈ [0, 1]

1D value noise. Smooth, deterministic, tileable.
"""
@inline function noise(x::Float64)
    xi = floor(Int, x)
    xf = x - xi
    a = _hash_noise(xi)
    b = _hash_noise(xi + 1)
    a + _smooth(xf) * (b - a)
end

"""
    noise(x::Float64, y::Float64) → Float64 ∈ [0, 1]

2D value noise. Smooth, deterministic.
"""
@inline function noise(x::Float64, y::Float64)
    xi = floor(Int, x)
    yi = floor(Int, y)
    xf = x - xi
    yf = y - yi
    a = _hash_noise(xi + yi * 7919)
    b = _hash_noise(xi + 1 + yi * 7919)
    c = _hash_noise(xi + (yi + 1) * 7919)
    d = _hash_noise(xi + 1 + (yi + 1) * 7919)
    u = _smooth(xf)
    v = _smooth(yf)
    top = a + u * (b - a)
    bot = c + u * (d - c)
    top + v * (bot - top)
end

"""
    fbm(x, [y]; octaves=3, lacunarity=2.0, gain=0.5) → Float64 ∈ [0, 1]

Fractal Brownian Motion — layered noise for natural-looking texture.
Higher octaves = more detail. Good for subtle organic variation.
"""
function fbm(x::Float64; octaves::Int=3, lacunarity::Float64=2.0, gain::Float64=0.5)
    octaves < 1 && return 0.5
    val = 0.0
    amp = 1.0
    freq = 1.0
    total_amp = 0.0
    for _ in 1:octaves
        val += amp * noise(x * freq)
        total_amp += amp
        amp *= gain
        freq *= lacunarity
    end
    val / total_amp
end

function fbm(x::Float64, y::Float64; octaves::Int=3, lacunarity::Float64=2.0, gain::Float64=0.5)
    octaves < 1 && return 0.5
    val = 0.0
    amp = 1.0
    freq = 1.0
    total_amp = 0.0
    for _ in 1:octaves
        val += amp * noise(x * freq, y * freq)
        total_amp += amp
        amp *= gain
        freq *= lacunarity
    end
    val / total_amp
end

# ── Tick-driven effects ───────────────────────────────────────────────

"""
    pulse(tick; period=60, lo=0.3, hi=1.0) → Float64

Smooth sinusoidal pulse between `lo` and `hi`.
Returns `hi` when animations are disabled.
"""
function pulse(tick::Int; period::Int=60, lo::Float64=0.3, hi::Float64=1.0)
    animations_enabled() || return hi
    t = (sin(2π * tick / period) + 1.0) / 2.0
    lo + t * (hi - lo)
end

"""
    breathe(tick; period=90) → Float64 ∈ [0, 1]

Asymmetric breathing curve — slow inhale, quick exhale.
More organic than a pure sine. Returns 1.0 when animations disabled.
"""
function breathe(tick::Int; period::Int=90)
    animations_enabled() || return 1.0
    t = mod(tick, period) / period
    # Cubic ease-in on rise, quadratic ease-out on fall
    if t < 0.6
        p = t / 0.6
        p * p * p
    else
        p = (t - 0.6) / 0.4
        1.0 - p * p
    end
end

"""
    shimmer(tick, x; speed=0.08, scale=0.15) → Float64 ∈ [0, 1]

Noise-driven shimmer along a horizontal axis.
Good for subtly varying brightness across a row of characters.
Returns 0.5 when animations disabled.
"""
function shimmer(tick::Int, x::Int; speed::Float64=0.08, scale::Float64=0.15)
    animations_enabled() || return 0.5
    fbm(x * scale, tick * speed)
end

"""
    color_wave(tick, x, colors; speed=0.04, spread=0.08) → ColorRGB

Smooth multi-stop color gradient wave sweeping across x positions.
`colors` should be a tuple/vector of Color256 or ColorRGB.
Returns `colors[1]` (as RGB) when animations disabled.
"""
function color_wave(tick::Int, x::Int, colors; speed::Float64=0.04, spread::Float64=0.08)
    n = length(colors)
    c1_rgb = to_rgb(colors[1])
    n < 2 && return c1_rgb
    animations_enabled() || return c1_rgb
    # Phase: position + time sweep
    phase = mod(x * spread + tick * speed, Float64(n))
    # Which two colors are we between?
    idx = floor(Int, phase)
    frac = phase - idx
    a = to_rgb(colors[mod1(idx + 1, n)])
    b = to_rgb(colors[mod1(idx + 2, n)])
    color_lerp(a, b, frac)
end

"""
    jitter(tick, seed; amount=0.5, speed=0.1) → Float64 ∈ [-amount, amount]

Noise-based jitter for organic wobble. Deterministic per seed.
Returns 0.0 when animations disabled.
"""
function jitter(tick::Int, seed::Int; amount::Float64=0.5, speed::Float64=0.1)
    animations_enabled() || return 0.0
    (noise(tick * speed + seed * 17.31) - 0.5) * 2.0 * amount
end

"""
    flicker(tick, seed; intensity=0.1, speed=0.15) → Float64 ∈ [1-intensity, 1]

Stochastic brightness flicker for CRT/phosphor aesthetics.
Higher `intensity` = more pronounced flicker. Each `seed` gets
its own flicker pattern. Returns 1.0 when animations disabled.
"""
function flicker(tick::Int, seed::Int=0; intensity::Float64=0.1, speed::Float64=0.15)
    animations_enabled() || return 1.0
    n = noise(tick * speed + seed * 31.37)
    1.0 - intensity * n * n   # squared for bias toward bright
end

"""
    drift(tick, seed; speed=0.02) → Float64 ∈ [0, 1]

Slow noise drift for organic color/value wandering. Each `seed`
produces a different drift path. Returns 0.5 when animations disabled.
"""
function drift(tick::Int, seed::Int=0; speed::Float64=0.02)
    animations_enabled() || return 0.5
    noise(tick * speed + seed * 43.71)
end

"""
    glow(x, y, cx, cy; radius=5.0, falloff=2.0) → Float64 ∈ [0, 1]

Radial glow intensity centered at (cx, cy). Returns 1.0 at center,
fades to 0.0 beyond `radius`. `falloff` controls curve sharpness.
Not gated by animations_enabled — purely geometric.
"""
function glow(x::Int, y::Int, cx::Float64, cy::Float64;
              radius::Float64=5.0, falloff::Float64=2.0)
    d = sqrt((x - cx)^2 + (y - cy)^2)
    clamp(1.0 - (d / radius)^falloff, 0.0, 1.0)
end

# ── Color manipulation ────────────────────────────────────────────────

"""
    brighten(c::ColorRGB, amount::Float64) → ColorRGB

Brighten a color by `amount` ∈ [0, 1]. 0 = unchanged, 1 = white.
"""
function brighten(c::ColorRGB, amount::Float64)
    amount = clamp(amount, 0.0, 1.0)
    ColorRGB(
        round(UInt8, c.r + (255 - c.r) * amount),
        round(UInt8, c.g + (255 - c.g) * amount),
        round(UInt8, c.b + (255 - c.b) * amount),
    )
end

function brighten(c::Color256, amount::Float64)
    brighten(to_rgb(c), amount)
end

"""
    dim_color(c::ColorRGB, amount::Float64) → ColorRGB

Dim a color by `amount` ∈ [0, 1]. 0 = unchanged, 1 = black.
"""
function dim_color(c::ColorRGB, amount::Float64)
    amount = clamp(amount, 0.0, 1.0)
    inv = 1.0 - amount
    ColorRGB(
        round(UInt8, c.r * inv),
        round(UInt8, c.g * inv),
        round(UInt8, c.b * inv),
    )
end

function dim_color(c::Color256, amount::Float64)
    dim_color(to_rgb(c), amount)
end

"""
    hue_shift(c::ColorRGB, degrees::Float64) → ColorRGB

Rotate the hue of a color by `degrees`. Preserves saturation and lightness.
"""
function hue_shift(c::ColorRGB, degrees::Float64)
    r, g, b = c.r / 255.0, c.g / 255.0, c.b / 255.0
    h, s, l = _rgb_to_hsl(r, g, b)
    h = mod(h + degrees, 360.0)
    r2, g2, b2 = _hsl_to_rgb(h, s, l)
    ColorRGB(round(UInt8, r2 * 255), round(UInt8, g2 * 255), round(UInt8, b2 * 255))
end

function hue_shift(c::Color256, degrees::Float64)
    hue_shift(to_rgb(c), degrees)
end

function _rgb_to_hsl(r::Float64, g::Float64, b::Float64)
    mx = max(r, g, b)
    mn = min(r, g, b)
    l = (mx + mn) / 2.0
    if mx == mn
        return (0.0, 0.0, l)
    end
    d = mx - mn
    s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
    h = if mx == r
        (g - b) / d + (g < b ? 6.0 : 0.0)
    elseif mx == g
        (b - r) / d + 2.0
    else
        (r - g) / d + 4.0
    end
    (h * 60.0, s, l)
end

function _hsl_to_rgb(h::Float64, s::Float64, l::Float64)
    s == 0.0 && return (l, l, l)
    q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
    p = 2.0 * l - q
    r = _hue_to_rgb(p, q, h / 360.0 + 1.0/3.0)
    g = _hue_to_rgb(p, q, h / 360.0)
    b = _hue_to_rgb(p, q, h / 360.0 - 1.0/3.0)
    (r, g, b)
end

function _hue_to_rgb(p::Float64, q::Float64, t::Float64)
    t < 0.0 && (t += 1.0)
    t > 1.0 && (t -= 1.0)
    t < 1.0/6.0 && return p + (q - p) * 6.0 * t
    t < 1.0/2.0 && return q
    t < 2.0/3.0 && return p + (q - p) * (2.0/3.0 - t) * 6.0
    return p
end

# ── Buffer-level texture fills ────────────────────────────────────────

"""
    fill_gradient!(buf, rect, c1, c2; direction=:horizontal)

Fill a rect with a smooth color gradient between two colors.
`direction` can be `:horizontal`, `:vertical`, or `:diagonal`.
Characters are filled with spaces; only the foreground color varies.
"""
function fill_gradient!(buf::Buffer, rect::Rect,
                        c1::AbstractColor, c2::AbstractColor;
                        direction::Symbol=:horizontal)
    a = to_rgb(c1)
    b = to_rgb(c2)
    w = max(1, rect.width - 1)
    h = max(1, rect.height - 1)
    for row in rect.y:bottom(rect)
        for col in rect.x:right(rect)
            in_bounds(buf, col, row) || continue
            t = if direction == :horizontal
                (col - rect.x) / w
            elseif direction == :vertical
                (row - rect.y) / h
            else  # :diagonal
                ((col - rect.x) / w + (row - rect.y) / h) / 2.0
            end
            c = color_lerp(a, b, clamp(t, 0.0, 1.0))
            set_char!(buf, col, row, ' ', Style(bg=c))
        end
    end
end

"""
    fill_noise!(buf, rect, c1, c2, tick; scale=0.2, speed=0.03)

Fill a rect with animated 2D noise texture blending between two colors.
Creates an organic, slowly shifting background pattern.
Falls back to solid c1 fill when animations disabled.
"""
function fill_noise!(buf::Buffer, rect::Rect,
                     c1::AbstractColor, c2::AbstractColor,
                     tick::Int;
                     scale::Float64=0.2, speed::Float64=0.03)
    a = to_rgb(c1)
    b = to_rgb(c2)
    for row in rect.y:bottom(rect)
        for col in rect.x:right(rect)
            in_bounds(buf, col, row) || continue
            if animations_enabled()
                t = fbm(col * scale, row * scale + tick * speed)
                c = color_lerp(a, b, t)
            else
                c = a
            end
            set_char!(buf, col, row, ' ', Style(bg=c))
        end
    end
end

"""
    border_shimmer!(buf, rect, base_color, tick; box=BOX_ROUNDED, intensity=0.15)

Draw a block border where each border character has subtly varying
brightness driven by noise. Creates an organic, living border effect.
Falls back to uniform `base_color` when animations disabled.
"""
function border_shimmer!(buf::Buffer, rect::Rect, base_color::AbstractColor,
                         tick::Int; box::NamedTuple=BOX_ROUNDED,
                         intensity::Float64=0.15)
    (rect.width < 2 || rect.height < 2) && return
    base_rgb = to_rgb(base_color)

    function _border_style(x::Int, y::Int)
        if animations_enabled()
            n = fbm(x * 0.3 + tick * 0.04, y * 0.5 + tick * 0.02)
            adj = (n - 0.5) * 2.0 * intensity
            c = if adj > 0
                brighten(base_rgb, adj)
            else
                dim_color(base_rgb, -adj)
            end
            Style(fg=c)
        else
            Style(fg=base_rgb)
        end
    end

    # Corners
    set_char!(buf, rect.x, rect.y, box.tl, _border_style(rect.x, rect.y))
    set_char!(buf, right(rect), rect.y, box.tr, _border_style(right(rect), rect.y))
    set_char!(buf, rect.x, bottom(rect), box.bl, _border_style(rect.x, bottom(rect)))
    set_char!(buf, right(rect), bottom(rect), box.br, _border_style(right(rect), bottom(rect)))

    # Horizontal edges
    for x in (rect.x + 1):(right(rect) - 1)
        set_char!(buf, x, rect.y, box.h, _border_style(x, rect.y))
        set_char!(buf, x, bottom(rect), box.h, _border_style(x, bottom(rect)))
    end

    # Vertical edges
    for y in (rect.y + 1):(bottom(rect) - 1)
        set_char!(buf, rect.x, y, box.v, _border_style(rect.x, y))
        set_char!(buf, right(rect), y, box.v, _border_style(right(rect), y))
    end
end
