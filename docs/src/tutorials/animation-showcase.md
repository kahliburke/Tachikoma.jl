# Animation Showcase

This tutorial demonstrates Tachikoma's animation primitives: easing tweens, physics springs, staggered timelines, and organic noise effects.

## What We'll Build

A four-panel showcase:
1. **Easing gallery** — horizontal bars comparing all 10 easing functions
2. **Spring physics** — interactive spring with retarget on keypress
3. **Staggered timeline** — cascade of bars with delayed starts
4. **Organic effects** — shimmer borders and noise textures

<!-- tachi:begin anim_showcase_app -->

## Step 1: Model with Animations

```julia
using Tachikoma

@kwdef mutable struct AnimShowcase <: Model
    quit::Bool = false
    tick::Int = 0
    # Easing gallery — one pingpong tween per easing function
    easing_tweens::Vector{Tween} = [
        tween(0.0, 1.0; duration=60, easing=fn, loop=:pingpong)
        for fn in [linear, ease_in_quad, ease_out_quad, ease_in_out_quad,
                   ease_in_cubic, ease_out_cubic, ease_in_out_cubic,
                   ease_out_elastic, ease_out_bounce, ease_out_back]
    ]
    # Spring — interactive target
    spring::Spring = Spring(0.5; value=0.0, stiffness=180.0, damping=:critical)
    spring_targets::Vector{Float64} = [0.0, 0.25, 0.5, 0.75, 1.0]
    spring_idx::Int = 1
    spring_trail::Vector{Float64} = Float64[]
    # Staggered timeline
    cascade::Vector{Tween} = [tween(0.0, 1.0; duration=30, easing=ease_out_cubic)
                               for _ in 1:8]
    timeline::Union{Timeline, Nothing} = nothing
end

should_quit(m::AnimShowcase) = m.quit

function init!(m::AnimShowcase, ::Terminal)
    m.timeline = stagger(m.cascade...; delay=5)
end
```

## Step 2: Handle Input

```julia
function update!(m::AnimShowcase, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        # Space: cycle spring target
        if evt.char == ' '
            m.spring_idx = mod1(m.spring_idx + 1, length(m.spring_targets))
            retarget!(m.spring, m.spring_targets[m.spring_idx])
        end
        # R: restart cascade
        if evt.char == 'r'
            for tw in m.cascade; reset!(tw); end
            m.timeline !== nothing && (m.timeline.frame = 0)
        end
    elseif evt.key == :up
        m.spring_idx = mod1(m.spring_idx + 1, length(m.spring_targets))
        retarget!(m.spring, m.spring_targets[m.spring_idx])
    elseif evt.key == :down
        m.spring_idx = mod1(m.spring_idx - 1, length(m.spring_targets))
        retarget!(m.spring, m.spring_targets[m.spring_idx])
    elseif evt.key == :escape
        m.quit = true
    end
end
```

The key technique here is `retarget!` — when you press space or arrow keys, the spring smoothly redirects toward the new target while preserving its current velocity.

## Step 3: Advance Animations in View

```julia
function view(m::AnimShowcase, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Advance all animations every frame
    for tw in m.easing_tweens; advance!(tw); end
    advance!(m.spring)
    push!(m.spring_trail, m.spring.value)
    length(m.spring_trail) > 120 && popfirst!(m.spring_trail)
    if m.timeline !== nothing && !done(m.timeline)
        advance!(m.timeline)
    end

    # Outer frame
    outer = Block(title="animation showcase",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    main = render(outer, f.area, buf)

    # 2×2 grid layout
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fill(), Fixed(1)]), main)
    length(rows) < 4 && return

    top_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[2])
    bot_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[3])

    # Render panels
    render_easing_gallery!(buf, top_cols[1], m)
    render_spring_panel!(buf, top_cols[2], m)
    render_cascade!(buf, bot_cols[1], m)
    render_organic!(buf, bot_cols[2], m)

    # Status bar
    render(StatusBar(
        left=[Span("  [Space/↑↓] spring  [r] restart cascade ", tstyle(:text_dim))],
        right=[Span("[q] quit ", tstyle(:text_dim))],
    ), rows[4], buf)
end
```

## Step 4: Easing Gallery Panel

```julia
 EASING_NAMES = [
    "linear", "ease_in_quad", "ease_out_quad", "ease_in_out_quad",
    "ease_in_cubic", "ease_out_cubic", "ease_in_out_cubic",
    "ease_out_elastic", "ease_out_bounce", "ease_out_back",
]

function render_easing_gallery!(buf, area, m)
    block = Block(title="easing functions", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)

    label_w = 16
    bar_w = inner.width - label_w - 1

    for (i, tw) in enumerate(m.easing_tweens)
        y = inner.y + i - 1
        y > bottom(inner) && break

        # Label
        name = i <= length(EASING_NAMES) ? EASING_NAMES[i] : "?"
        set_string!(buf, inner.x, y, rpad(name, label_w), tstyle(:text_dim))

        # Animated bar
        v = value(tw)
        filled = round(Int, v * bar_w)
        for cx in 0:(bar_w - 1)
            ch = cx < filled ? '█' : '·'
            s = cx < filled ? tstyle(:primary) : tstyle(:text_dim, dim=true)
            set_char!(buf, inner.x + label_w + cx, y, ch, s)
        end

        # Position marker
        mx = inner.x + label_w + clamp(filled, 0, bar_w - 1)
        set_char!(buf, mx, y, '▸', tstyle(:accent, bold=true))
    end
end
```

## Step 5: Spring Panel

```julia
function render_spring_panel!(buf, area, m)
    block = Block(title="spring physics", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)
    inner.width < 10 && return

    # Info line
    tv = m.spring_targets[m.spring_idx]
    info = "target=$(round(tv; digits=2))  value=$(round(m.spring.value; digits=3))"
    set_string!(buf, inner.x, inner.y, info, tstyle(:text_dim))

    # Spring trail as sparkline
    spark_area = Rect(inner.x, inner.y + 2, inner.width, max(1, inner.height - 4))
    if !isempty(m.spring_trail)
        render(Sparkline(m.spring_trail; style=tstyle(:accent)), spark_area, buf)
    end

    # Position indicator bar at bottom
    bar_y = bottom(inner)
    bar_y > inner.y + 2 || return
    bar_w = inner.width
    pos = round(Int, clamp(m.spring.value, 0.0, 1.0) * (bar_w - 1))
    target_pos = round(Int, clamp(tv, 0.0, 1.0) * (bar_w - 1))

    for cx in 0:(bar_w - 1)
        ch = cx == target_pos ? '┃' : '─'
        s = cx == target_pos ? tstyle(:warning) : tstyle(:text_dim, dim=true)
        set_char!(buf, inner.x + cx, bar_y, ch, s)
    end
    set_char!(buf, inner.x + pos, bar_y, '●', tstyle(:primary, bold=true))
end
```

## Step 6: Staggered Timeline

```julia
function render_cascade!(buf, area, m)
    block = Block(title="staggered timeline", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)
    m.timeline === nothing && return

    # Frame counter
    frame_info = "frame $(m.timeline.frame)"
    done(m.timeline) && (frame_info *= " [done — press r]")
    set_string!(buf, inner.x, inner.y, frame_info, tstyle(:text_dim))

    bar_w = inner.width - 6
    for (i, tw) in enumerate(m.cascade)
        y = inner.y + i
        y > bottom(inner) && break

        v = value(tw)
        filled = round(Int, v * bar_w)
        set_string!(buf, inner.x, y, lpad(string(i), 2) * "│ ", tstyle(:text_dim))

        for cx in 0:(bar_w - 1)
            if cx < filled
                set_char!(buf, inner.x + 4 + cx, y, '█', tstyle(:primary))
            else
                set_char!(buf, inner.x + 4 + cx, y, '·', tstyle(:text_dim, dim=true))
            end
        end
    end
end
```

## Step 7: Organic Effects Panel

```julia
function render_organic!(buf, area, m)
    block = Block(title="organic effects", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)
    inner.height < 4 && return

    y = inner.y

    # Pulse
    p = pulse(m.tick; period=60, lo=0.2, hi=1.0)
    set_string!(buf, inner.x, y, "pulse:   ", tstyle(:text_dim))
    bar_w = inner.width - 10
    filled = round(Int, p * bar_w)
    for cx in 0:(bar_w - 1)
        ch = cx < filled ? '█' : '░'
        set_char!(buf, inner.x + 10 + cx, y, ch, tstyle(:primary))
    end

    # Breathe
    y += 2
    b = breathe(m.tick; period=90)
    set_string!(buf, inner.x, y, "breathe: ", tstyle(:text_dim))
    filled = round(Int, b * bar_w)
    for cx in 0:(bar_w - 1)
        ch = cx < filled ? '█' : '░'
        set_char!(buf, inner.x + 10 + cx, y, ch, tstyle(:secondary))
    end

    # Shimmer border on a sub-panel
    y += 2
    if y + 3 <= bottom(inner)
        shimmer_rect = Rect(inner.x, y, inner.width, bottom(inner) - y + 1)
        border_shimmer!(buf, shimmer_rect, to_rgb(theme().accent), m.tick;
                        intensity=0.3)
        set_string!(buf, inner.x + 2, y + 1, "border_shimmer!",
                    tstyle(:accent, bold=true))
    end
end
```

## Step 8: Run It

<!-- tachi:app anim_showcase_app w=80 h=24 frames=240 fps=15 chrome -->
```julia
app(AnimShowcase())
```

## Key Concepts

### Tweens vs Springs

- **Tweens** have a fixed duration and easing curve — use for UI transitions with known timing
- **Springs** settle naturally based on physics — use for interactive elements that respond to user input

### Timeline Composition

- `sequence(tweens...)` — play one after another
- `stagger(tweens...; delay=n)` — overlapping starts
- `parallel(tweens...)` — all at once

### Organic Effects

The `pulse`, `breathe`, `shimmer`, `jitter`, `flicker`, and `drift` functions produce natural-looking variation driven by the tick counter. They're automatically disabled when `animations_enabled()` returns false.

### Buffer Fills

`fill_gradient!`, `fill_noise!`, and `border_shimmer!` apply animated textures to rectangular regions of the buffer.

## Exercises

- Add an underdamped spring (`:under`) to see oscillation
- Create a `parallel` timeline that animates width and color simultaneously
- Use `fill_noise!` as a background texture behind one of the panels
- Add `color_wave` to cycle through theme colors on the cascade bars
