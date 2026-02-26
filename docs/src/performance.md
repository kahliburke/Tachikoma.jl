# Performance

Tachikoma is built for sustained 60fps rendering with sub-millisecond frame budgets. The framework uses double-buffered differential rendering — only changed cells are written to the terminal each frame — making it practical to build complex, animated UIs that stay smooth under load.

## FPS Stress Test

The built-in FPS stress test lets you crank up rendering workload while monitoring frame rate in real time. Six subsystems run simultaneously — sparklines, braille canvas particle physics, bar charts, live gauges, a process table, and a progress list — each independently adjustable to quantify rendering cost.

Run it from the [TachikomaDemos](https://github.com/kahliburke/Tachikoma.jl/tree/main/demos) package:

<!-- tachi:noeval -->
```julia
using TachikomaDemos
fps_demo(; fps=60)
```

<!-- tachi:app fps_demo w=80 h=35 frames=360 fps=60 chrome realtime warmup=360 -->

Controls: `↑↓` sparklines, `←→` particles, `1-5` complexity, `t` tokenizer stress, `f` FPS target, `q` quit.

The demo tracks actual wall-clock frame time rather than the target rate, so the displayed FPS reflects real rendering cost. This timing pattern is easy to add to any app:

<!-- tachi:noeval -->
```julia
@kwdef mutable struct MyApp <: Model
    last_time::Float64 = time()
    fps_history::Vector{Float64} = Float64[]
end

function Tachikoma.view(m::MyApp, f::Frame)
    now = time()
    fps = 1.0 / max(now - m.last_time, 0.0001)
    m.last_time = now
    push!(m.fps_history, fps)
    while length(m.fps_history) > 200; popfirst!(m.fps_history); end
    render(Sparkline(m.fps_history; style=tstyle(:primary)), f.area, f.buffer)
end
```

## Rendering Pipeline

Every frame follows the same efficient path:

1. **Event poll** — non-blocking `poll_event()` reads keyboard/mouse input
2. **Update** — your `update!(model, event)` mutates state
3. **View** — your `view(model, frame)` renders into a fresh `Buffer`
4. **Diff** — the framework compares the new buffer against the previous frame
5. **Flush** — only changed cells are written to the terminal via ANSI escape sequences

This diff-and-flush approach means that a mostly-static UI (e.g., a form with a blinking cursor) writes only a few bytes per frame, even at 60fps.

## Double Buffering

Tachikoma maintains two `Buffer` instances. Each frame, your `view` function writes into the "back" buffer. After rendering, the framework diffs back vs. front, emits the minimal escape sequences, then swaps the buffers. This eliminates flicker and keeps write volume proportional to what actually changed.

## Performance Characteristics

| Metric | Typical | Notes |
|:-------|:--------|:------|
| Frame budget at 60fps | 16.6ms | Time available per frame |
| View render (simple app) | 0.1–0.5ms | Block + Paragraph + StatusBar |
| View render (dashboard) | 1–3ms | Multiple widgets, sparklines, gauges |
| View render (stress test) | 5–12ms | 8 sparklines + 500 particles + noise |
| Terminal diff + flush | 0.05–0.2ms | Proportional to changed cells |
| Memory per Buffer | ~0.5 MB | 200×50 cells × ~50 bytes/cell |

## Tips for Smooth Rendering

### Minimize allocations in `view`

The `view` function runs every frame. Avoid allocating vectors, strings, or other heap objects in the hot path. Pre-allocate data buffers in your `Model` and mutate them:

```julia
@kwdef mutable struct MyApp <: Model
    data::Vector{Float64} = zeros(100)  # pre-allocated
    quit::Bool = false
    tick::Int = 0
end

function Tachikoma.view(m::MyApp, f::Frame)
    m.tick += 1
    # Update data in-place instead of creating a new vector
    for i in eachindex(m.data)
        m.data[i] = sin(m.tick * 0.1 + i * 0.2)
    end
    render(Sparkline(m.data; style=tstyle(:primary)), f.area, f.buffer)
end
```

### Use `@inbounds` for pixel loops

When writing custom canvas or sixel rendering with tight pixel loops, `@inbounds` eliminates bounds-check overhead:

<!-- tachi:noeval -->
```julia
@inbounds for py in 1:pixel_h
    for px in 1:pixel_w
        set_pixel!(img, px, py, compute_color(px, py))
    end
end
```

### Choose the right rendering backend

Braille rendering (`Canvas`) is significantly faster than sixel (`PixelImage`) because it operates on terminal cells rather than individual pixels. Use sixel only when you need pixel-level fidelity:

```julia
# Fast: braille canvas — 2×4 dots per cell
canvas = Canvas(40, 20)

# Slower: sixel — ~8×16 pixels per cell
img = PixelImage(40, 20)
```

### Reduce widget count in tight layouts

Each `render()` call has a small fixed cost. For maximum FPS under heavy load, combine related information into fewer widgets rather than rendering many small ones.
