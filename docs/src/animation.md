# Animation

Tachikoma includes a full animation system with time-based tweens, physics-based springs, sequenced timelines, and organic noise effects. All animations are frame-driven and integrate naturally with the 60fps render loop.

## Easing Functions

Ten easing functions control the rate of change over time:

| Function | Description |
|:---------|:------------|
| `linear` | Constant speed |
| `ease_in_quad` | Slow start, quadratic |
| `ease_out_quad` | Slow end, quadratic |
| `ease_in_out_quad` | Slow start and end, quadratic |
| `ease_in_cubic` | Slow start, cubic |
| `ease_out_cubic` | Slow end, cubic |
| `ease_in_out_cubic` | Slow start and end, cubic |
| `ease_out_elastic` | Overshoot with elastic bounce |
| `ease_out_bounce` | Multiple bounces at end |
| `ease_out_back` | Slight overshoot then settle |

All easing functions take `t ∈ [0, 1]` and return a value in `[0, 1]` (with overshoot for elastic/bounce/back).

## Tweens

A `Tween` interpolates between two values over a fixed number of frames:

<!-- tachi:widget tween_demo w=50 h=4 frames=120 fps=30
easings = [ease_in_out_cubic, ease_out_elastic, ease_out_bounce]
names = ["in_out_cubic", "out_elastic", "out_bounce"]
for (i, (ef, nm)) in enumerate(zip(easings, names))
    y = area.y + i - 1
    t = mod(frame_idx, 90) / 90.0
    v = ef(t)
    bar_w = round(Int, v * (area.width - 16))
    set_string!(buf, area.x, y, rpad(nm, 13), tstyle(:text_dim))
    for x in 0:bar_w-1
        set_char!(buf, area.x + 13 + x, y, '█', tstyle(:accent))
    end
end
-->
```julia
tw = tween(0.0, 1.0; duration=60, easing=ease_out_cubic, loop=:none)

# In your view function:
advance!(tw)          # progress by 1 frame
v = value(tw)         # get current interpolated value (0.0 → 1.0)
done(tw)              # true when duration is reached
reset!(tw)            # restart from the beginning
```

### Loop Modes

| Mode | Behavior |
|:-----|:---------|
| `:none` | Play once, stop at end |
| `:loop` | Restart from beginning when done |
| `:pingpong` | Reverse direction at each end |

```julia
# Continuous back-and-forth animation
tw = tween(0.0, 1.0; duration=60, easing=ease_in_out_cubic, loop=:pingpong)
```

## Springs

A `Spring` uses physics simulation for natural-feeling motion. Springs don't have a fixed duration — they settle naturally based on stiffness and damping:

<!-- tachi:widget spring_demo w=50 h=4 frames=120 fps=30
modes = [:critical, :over, :under]
names = ["critical", "overdamped", "underdamped"]
for (i, (mode, nm)) in enumerate(zip(modes, names))
    y = area.y + i - 1
    sp = Spring(1.0; value=0.0, stiffness=180.0, damping=mode)
    for _ in 1:mod(frame_idx, 90)
        advance!(sp; dt=1.0/30.0)
    end
    bar_w = round(Int, clamp(sp.value, 0.0, 1.2) * (area.width - 14))
    set_string!(buf, area.x, y, rpad(nm, 12), tstyle(:text_dim))
    for x in 0:bar_w-1
        set_char!(buf, area.x + 12 + x, y, '█', tstyle(:accent))
    end
end
-->
```julia
s = Spring(0.5; value=0.0, stiffness=180.0, damping=:critical)

# In your view function:
advance!(s; dt=1.0/60.0)    # simulate one physics step
v = s.value                  # current position
settled(s; threshold=0.01)   # true when at rest
```

### Damping Modes

| Mode | Behavior |
|:-----|:---------|
| `:critical` | Reaches target as fast as possible without oscillation |
| `:over` | Slower approach, no oscillation (overdamped) |
| `:under` | Oscillates before settling (underdamped, bouncy) |
| `Float64` | Explicit damping coefficient |

### Retargeting

Springs can be smoothly redirected mid-animation:

<!-- tachi:noeval -->
```julia
retarget!(spring, 0.8)    # change target, preserving current velocity
```

This is what makes springs ideal for interactive UI — you can change the target every frame and the spring naturally adjusts.

<!-- tachi:noeval -->
```julia
# Example: spring-animated gauge that tracks changing data
spring = Spring(0.0; stiffness=120.0, damping=:critical)

function view(m::MyApp, f::Frame)
    retarget!(m.spring, m.current_cpu_usage)   # track live data
    advance!(m.spring)
    render(Gauge(m.spring.value; ...), area, buf)
end
```

## Timelines

Timelines compose multiple tweens with timing control:

### `sequence(tweens...)`

Play tweens one after another:

```julia
tl = sequence(
    tween(0.0, 1.0; duration=30),
    tween(1.0, 0.5; duration=20),
    tween(0.5, 0.8; duration=25),
)
```

### `stagger(tweens...; delay=3)`

Play tweens with overlapping starts:

<!-- tachi:widget stagger_demo w=50 h=8 frames=90 fps=30
tweens = [tween(0.0, 1.0; duration=30, easing=ease_out_cubic, loop=:pingpong) for _ in 1:8]
tl = stagger(tweens...; delay=5)
for _ in 1:mod(frame_idx, 90)
    advance!(tl)
end
cs = [:primary, :accent, :secondary, :success, :warning, :error, :primary, :accent]
for (i, tw) in enumerate(tweens)
    y = area.y + i - 1
    bar_w = round(Int, value(tw) * (area.width - 2))
    for x in 0:bar_w-1
        set_char!(buf, area.x + x, y, '█', tstyle(cs[i]))
    end
end
-->
```julia
# 8 bars that animate one after another with a 5-frame delay
tweens = [tween(0.0, 1.0; duration=30, easing=ease_out_cubic) for _ in 1:8]
tl = stagger(tweens...; delay=5)
```

### `parallel(tweens...)`

Play all tweens simultaneously:

```julia
tl = parallel(
    tween(0.0, 1.0; duration=60),   # fade in
    tween(0.0, 20.0; duration=60),  # slide right
)
```

### Timeline API

<!-- tachi:noeval -->
```julia
advance!(tl)       # advance by 1 frame
done(tl)           # true when all entries complete
```

## Animator

The `Animator` is a per-model animation manager that tracks named tweens, springs, and timelines:

```julia
@kwdef mutable struct MyApp <: Model
    animator::Animator = Animator()
end

function init!(m::MyApp, ::Terminal)
    animate!(m.animator, :fade, tween(0.0, 1.0; duration=30))
    animate!(m.animator, :position, Spring(0.0; stiffness=150.0))
end

function view(m::MyApp, f::Frame)
    tick!(m.animator)               # advance all animations
    opacity = val(m.animator, :fade)     # get tween value
    pos = val(m.animator, :position)     # get spring value
    # ... render using animated values
end
```

### Animator API

<!-- tachi:noeval -->
```julia
Animator()
tick!(animator)                          # advance all registered animations
val(animator, name::Symbol) → Float64    # get current value
animate!(animator, name, tween_or_spring_or_timeline)  # register animation
```

## Organic Effects

Noise-based animation functions that add life to UIs. These are gated by `animations_enabled()` — when animations are off, they return static values.

### Value Noise

<!-- tachi:noeval -->
```julia
noise(x::Float64) → Float64               # 1D smooth noise ∈ [0,1]
noise(x::Float64, y::Float64) → Float64    # 2D smooth noise ∈ [0,1]
```

### Fractal Brownian Motion

<!-- tachi:noeval -->
```julia
fbm(x; octaves=3, lacunarity=2.0, gain=0.5) → Float64
fbm(x, y; octaves=3, lacunarity=2.0, gain=0.5) → Float64
```

### Tick-Driven Effects

All take a `tick` (frame counter) and return a value you can use for styling:

<!-- tachi:noeval -->
```julia
pulse(tick; period=60, lo=0.3, hi=1.0) → Float64    # sinusoidal oscillation
breathe(tick; period=90) → Float64                    # asymmetric breathing
shimmer(tick, x; speed=0.08, scale=0.15) → Float64   # noise-based flicker
jitter(tick, seed; amount=0.5, speed=0.1) → Float64  # random wobble
flicker(tick, seed=0; intensity=0.1, speed=0.15) → Float64
drift(tick, seed=0; speed=0.02) → Float64             # slow noise wander
glow(x, y, cx, cy; radius=5.0, falloff=2.0) → Float64  # radial glow
color_wave(tick, x, colors; speed=0.04, spread=0.08) → ColorRGB
```

### Example: Breathing Border

<!-- tachi:widget anim_breathing_border w=40 h=8 frames=90 fps=30 -->
```julia
b = breathe(tick; period=45)
border_color = color_lerp(
    to_rgb(theme().border),
    to_rgb(theme().accent),
    b
)

block = Block(title="Panel", border_style=Style(fg=border_color))
render(block, area, buf)
```

## Buffer Fills

Apply animated textures to buffer regions:

<!-- tachi:widget anim_buffer_fills w=50 h=10 frames=300 fps=15 -->
```julia
rows = split_layout(Layout(Vertical, [Fill(), Fill()]), area)
fill_noise!(buf, rows[1], to_rgb(theme().primary), to_rgb(theme().accent), tick; scale=0.2, speed=0.03)
border_shimmer!(buf, rows[2], to_rgb(theme().accent), tick; box=BOX_ROUNDED, intensity=0.15)
set_string!(buf, rows[2].x + 2, rows[2].y + 1, "border_shimmer!", tstyle(:accent, bold=true))
```

<!-- tachi:noeval -->
```julia
fill_gradient!(buf, rect, color1, color2; direction=:horizontal)
fill_noise!(buf, rect, color1, color2, tick; scale=0.2, speed=0.03)
border_shimmer!(buf, rect, base_color, tick; box=BOX_ROUNDED, intensity=0.15)
```

## Global Animation Toggle

<!-- tachi:noeval -->
```julia
animations_enabled() → Bool     # check if animations are on
toggle_animations!()            # toggle on/off (saved via Preferences)
```

When animations are disabled, organic effects return static/zero values and tweens/springs still work but organic visual effects are suppressed.
