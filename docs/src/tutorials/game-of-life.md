# Game of Life

This tutorial walks through the 25-line Conway's Game of Life shown on the front page. It demonstrates the core Tachikoma pattern — `Model`/`update!`/`view` — with a cellular automaton that runs at interactive frame rates.

## The Complete Code

<!-- tachi:noeval -->
```julia
using Tachikoma

@kwdef mutable struct Life <: Model
    quit::Bool = false
    grid::Matrix{Bool} = rand(24, 80) .< 0.25
end

Tachikoma.should_quit(m::Life) = m.quit
function Tachikoma.update!(m::Life, e::KeyEvent)
    e.key == :escape && (m.quit = true)
end

function Tachikoma.view(m::Life, f::Frame)
    h, w = size(m.grid)
    g = m.grid
    nc = [sum(g[mod1(i+di,h), mod1(j+dj,w)]
          for di in -1:1, dj in -1:1) - g[i,j]
          for i in 1:h, j in 1:w]
    g .= (nc .== 3) .| (g .& (nc .== 2))
    a, buf = f.area, f.buffer
    cs = [:primary, :accent, :success,
          :warning, :error]
    for i in 1:min(h, a.height),
        j in 1:min(w, a.width)
        g[i,j] || continue
        set_char!(buf, a.x+j-1, a.y+i-1,
            '█', tstyle(cs[clamp(nc[i,j],1,5)]))
    end
end

app(Life())
```

## Step by Step

### 1. Define the Model

```julia
@kwdef mutable struct Life <: Model
    quit::Bool = false
    grid::Matrix{Bool} = rand(24, 80) .< 0.25
end
```

Every Tachikoma app starts with a `mutable struct` that subtypes `Model`. The `@kwdef` macro gives us keyword constructors so we can write `Life()` and get sensible defaults.

The `grid` field is a 24×80 Boolean matrix — matching a standard terminal size. The initial state is random: roughly 25% of cells start alive (`rand(...) .< 0.25`).

### 2. Handle Input

```julia
Tachikoma.should_quit(m::Life) = m.quit
function Tachikoma.update!(m::Life, e::KeyEvent)
    e.key == :escape && (m.quit = true)
end
```

`should_quit` tells the framework when to exit. The `update!` function handles keyboard events — here just Escape to quit. Julia's short-circuit `&&` makes it a one-liner. The `update!` function is called once per keyboard event, not once per frame.

### 3. Render the View

```julia
function Tachikoma.view(m::Life, f::Frame)
    h, w = size(m.grid)
    g = m.grid
    nc = [sum(g[mod1(i+di,h), mod1(j+dj,w)]
          for di in -1:1, dj in -1:1) - g[i,j]
          for i in 1:h, j in 1:w]
    g .= (nc .== 3) .| (g .& (nc .== 2))
    a, buf = f.area, f.buffer
    cs = [:primary, :accent, :success,
          :warning, :error]
    for i in 1:min(h, a.height),
        j in 1:min(w, a.width)
        g[i,j] || continue
        set_char!(buf, a.x+j-1, a.y+i-1,
            '█', tstyle(cs[clamp(nc[i,j],1,5)]))
    end
end
```

The `view` function is called every frame. It does three things:

**Compute neighbor counts.** The `nc` matrix counts the 8 neighbors of each cell using `mod1` for toroidal (wrapping) boundaries. The cell itself is subtracted so `nc[i,j]` is the count of live neighbors only.

**Apply the Game of Life rules.** Each cell updates according to the classic rules:
- A dead cell with exactly 3 neighbors comes alive (`nc .== 3`)
- A live cell with 2 or 3 neighbors survives (`g .& (nc .== 2)`)
- All other cells die

**Draw live cells.** Each live cell is rendered as a `'█'` character. The color is based on the neighbor count — cells with more neighbors are drawn in warmer colors (`:primary` through `:error`), creating a visual density map.

The `set_char!` function writes directly to the frame buffer at the correct screen coordinates. The `tstyle` function resolves theme-aware colors, so the Game of Life looks different under each of the 11 built-in themes.

### 4. Run It

```julia
app(Life())
```

The `app` function starts the event loop at the default frame rate. Pass `fps=N` to control the simulation speed — higher values mean faster evolution.

## Variations

**Pause and randomize.** Add Space to toggle pause and `r` to reset:

<!-- tachi:noeval -->
```julia
@kwdef mutable struct Life <: Model
    quit::Bool = false
    paused::Bool = false
    grid::Matrix{Bool} = rand(24, 80) .< 0.25
end

function Tachikoma.update!(m::Life, e::KeyEvent)
    e.key == :escape && (m.quit = true)
    e.key == :char && e.char == ' ' && (m.paused = !m.paused)
    e.key == :char && e.char == 'r' &&
        (m.grid .= rand(size(m.grid)...) .< 0.25)
end
```

Then guard the rule application with `m.paused ||` in `view`.

**Larger grid.** Replace `rand(24, 80)` with `rand(size...) .< 0.25` and let the grid auto-size to the terminal:

<!-- tachi:noeval -->
```julia
function Tachikoma.view(m::Life, f::Frame)
    if size(m.grid) != (f.area.height, f.area.width)
        m.grid = rand(f.area.height, f.area.width) .< 0.25
    end
    # ... rest of view
end
```

**Mouse interaction.** Toggle cells on click by adding a `MouseEvent` handler:

<!-- tachi:noeval -->
```julia
function Tachikoma.update!(m::Life, e::MouseEvent)
    if e.kind == :press && e.button == :left
        i, j = e.y, e.x
        if 1 <= i <= size(m.grid, 1) && 1 <= j <= size(m.grid, 2)
            m.grid[i, j] = !m.grid[i, j]
        end
    end
end
```

**Higher resolution.** Use a `Canvas` with braille dots (2×4 sub-cell resolution) for 8× more cells per terminal character. See the [Graphics & Pixel Rendering](../canvas.md) guide.

## Next Steps

- [Getting Started](../getting-started.md) — The Counter app, covering blocks, big text, and gauges
- [Architecture](../architecture.md) — How the `Model`/`update!`/`view` loop works in detail
- [Input & Events](../events.md) — Full keyboard and mouse event reference
- [Styling & Themes](../styling.md) — Customize colors and switch between the 11 built-in themes
