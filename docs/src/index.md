```@raw html
---
layout: home

hero:
  text: "Terminal UI Framework for Julia"
  tagline: Build rich, interactive terminal applications with an Elm-inspired architecture, 40+ widgets, constraint layouts, animation, RGBA pixel pipeline, and kitty/sixel graphics.
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: API Reference
      link: /api
    - theme: alt
      text: View on GitHub
      link: https://github.com/kahliburke/Tachikoma.jl

features:
  - icon: 🏗️
    title: Elm Architecture
    details: Declarative Model/update!/view pattern with a 60fps event loop and clean separation of state, logic, and rendering.
    link: /architecture
  - icon: 🧩
    title: 40+ Widgets
    details: Text inputs, tables, charts, forms, tree views, calendars, modals, code editors, and more — all keyboard and mouse accessible.
    link: /widgets
  - icon: 📐
    title: Constraint Layouts
    details: Flexible Fixed, Fill, Percent, Min, Max constraints with draggable resizable pane borders and layout persistence.
    link: /layout
  - icon: 🎞️
    title: Animation System
    details: Tweens with 10 easing functions, physics-based springs, timelines, and organic noise effects like flicker, drift, and glow.
    link: /animation
  - icon: 🖼️
    title: Multi-Backend Graphics
    details: Braille dots (2×4), quadrant blocks (2×2), and pixel rendering (16×32 per cell) with shapes, lines, and arcs.
    link: /canvas
  - icon: 🐈‍⬛
    title: Kitty Protocol Support
    details: For when you want your terminal frames rendered right MEOW! Full Kitty keyboard protocol with press/repeat/release events, plus Kitty graphics for pixel-perfect image rendering. Optimized shared memory rendering for ultra-low latency and high FPS.
    link: /events#kitty-keyboard-protocol
  - icon: ⚡
    title: Performant
    details: Double-buffered differential rendering at 60fps. Only changed cells hit the terminal — sub-millisecond frame budgets even for complex dashboards.
    link: /performance
  - icon: 🎨
    title: 24 Built-in Themes
    details: 11 dark + 13 light palettes — cyberpunk, retro, classic, and more — with hot-swappable theme switching and full persistence via Preferences.jl.
    link: /styling
  - icon: 🖥️
    title: Full RGBA Pixel Pipeline
    details: ColorRGBA-typed pixel pipeline with sixel virtual framebuffer compositor (text mask compositing), and Kitty graphics RGBA with z-index layering.
    link: /canvas
  - icon: 🎛️
    title: Type-Parameterized Widget Styling
    details: TabBarStyle, ButtonStyle, and other typed style structs let you customize widget appearance with full type safety and zero runtime overhead.
    link: /styling
---
```

```@raw html
<div class="hero-showcase">
  <div class="hero-showcase-demo">
    <img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/code_reveal.gif" alt="Julia source code materializing from random characters" />
    <!-- <p class="hero-showcase-caption">
      <em>Random characters resolve into syntax-highlighted Julia source — rendered at 60fps with Tachikoma's <a href="/recording">recording system</a>.</em>
    </p> -->
  </div>
  <div class="hero-showcase-bullets">
    <h3>Why Tachikoma?</h3>
    <ul>
      <li><strong>100% Julia</strong> — No C wrappers, Python, or ncurses. Just <code>Pkg.add</code> and go.</li>
      <li><strong>60–120+ fps</strong> — Double-buffered differential rendering. Only changed cells hit the terminal.</li>
      <li><strong>Compact Code</strong> — Full apps in 25 lines. Complex dashboards under 200.</li>
      <li><strong>Built-in Recording</strong> — Screencast any app to SVG, GIF, or <code>.tach</code> with one function call.</li>
      <li><strong>Virtual Terminal Testing</strong> — Headless rendering and scripted event injection for CI-friendly tests.</li>
    </ul>
  </div>
</div>
```

## Quick Start

Game of Life in 25 lines of code. New to Tachikoma? Start with the [Getting Started guide](getting-started.md), or see the [Game of Life walkthrough](tutorials/game-of-life.md) for a line-by-line breakdown.

<!-- tachi:noeval -->

```@raw html
<div class="quickstart-layout">
<div class="quickstart-code">
```

```julia
using Tachikoma
@tachikoma_app

@kwdef mutable struct Life <: Model
    quit::Bool = false
    grid::Matrix{Bool} = rand(24, 80) .< 0.25
end

should_quit(m::Life) = m.quit
function update!(m::Life, e::KeyEvent)
    e.key == :escape && (m.quit = true)
end

function view(m::Life, f::Frame)
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

```@raw html
</div>
<div class="quickstart-divider"></div>
<div class="quickstart-render">
<img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/quickstart_hello.gif" alt="Conway's Game of Life with color-coded cells evolving in real time" />
</div>
</div>
```

## Documentation

| Section | Description |
|:--------|:------------|
| [Installation](installation.md) | Install Tachikoma and configure your terminal |
| [Getting Started](getting-started.md) | Build your first app in 25 lines |
| [Architecture](architecture.md) | The Elm architecture pattern in depth |
| [Layout](layout.md) | Constraint-based layout system |
| [Styling & Themes](styling.md) | Colors, styles, and the 24 built-in themes |
| [Input & Events](events.md) | Keyboard and mouse event handling |
| [Animation](animation.md) | Tweens, springs, timelines, and organic effects |
| [Graphics & Pixel Rendering](canvas.md) | Canvas, BlockCanvas, PixelImage, PixelCanvas |
| [Widgets](widgets.md) | Complete widget catalog |
| [Backgrounds](backgrounds.md) | Procedural animated backgrounds |
| [Performance](performance.md) | Rendering pipeline, benchmarks, and optimization tips |
| [Preferences](preferences.md) | Configuration and persistence |
| [API Reference](api.md) | Auto-generated API documentation |

### Tutorials

- [Build a Form](tutorials/form-app.md) — Form with validation, focus navigation, and value extraction
- [Build a Dashboard](tutorials/dashboard.md) — Multi-pane dashboard with live data
- [Animation Showcase](tutorials/animation-showcase.md) — Springs, tweens, and organic effects
- [Todo List](tutorials/todo-list.md) — SelectableList with toggle and detail pane
- [GitHub PR Viewer](tutorials/github-prs.md) — Async data fetching, DataTable, and modal overlays
- [Constraint Explorer](tutorials/constraint-explorer.md) — Interactive layout constraint visualization
