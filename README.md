<p align="center">
  <img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_hero_logo.gif" alt="Tachikoma.jl" width="480">
</p>

<p align="center">
  <img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_hero_demo.gif" alt="Tachikoma.jl demo" width="720">
</p>

<h1 align="center">Tachikoma.jl</h1>

<p align="center">
  <strong>A terminal UI framework for Julia</strong>
</p>

<p align="center">
  <a href="https://github.com/kahliburke/Tachikoma.jl/actions/workflows/CI.yml"><img src="https://github.com/kahliburke/Tachikoma.jl/actions/workflows/CI.yml/badge.svg" alt="CI"></a>
  <a href="https://kahliburke.github.io/Tachikoma.jl/dev/"><img src="https://img.shields.io/badge/docs-dev-blue.svg" alt="Dev Docs"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/julia-%E2%89%A5%201.10-9558B2?logo=julia&logoColor=white" alt="Julia 1.10+">
</p>

---

Tachikoma is a pure-Julia framework for building rich, interactive terminal applications. It provides an Elm-inspired `Model`/`update!`/`view` architecture, a 60fps event loop with double-buffered rendering, 30+ composable widgets, constraint-based layouts, animation primitives, kitty/sixel pixel graphics, and built-in recording and export to SVG/GIF.

## Features

**Architecture** — Declarative Elm pattern with clean separation of state, logic, and rendering. 60fps event loop with automatic frame pacing and double-buffered output.

**30+ Widgets** — Text inputs, text areas, code editor with syntax highlighting, data tables with column resize and sort, forms with validation and Tab navigation, tree views, charts, bar charts, sparklines, calendars, modals, dropdowns, radio groups, checkboxes, progress indicators, scrollable panes, markdown viewer, and more.

**Constraint Layouts** — `Fixed`, `Fill`, `Percent`, `Min`, `Max`, and `Ratio` constraints. Draggable resizable pane borders with layout persistence via Preferences.jl.

**Animation** — Tweens with 10 easing functions, physics-based springs, timelines for sequencing, and organic effects: `noise`, `fbm`, `pulse`, `breathe`, `shimmer`, `jitter`, `flicker`, `drift`, `glow`.

**Graphics** — Three rendering backends: Braille dots (2x4), quadrant blocks (2x2), and pixel rendering (16x32 per cell, Kitty or sixel). Vector drawing API with lines, arcs, circles, and shapes.

**11 Themes** — Cyberpunk, retro, and classic palettes (KOKAKU, ESPER, MOTOKO, KANEDA, NEUROMANCER, CATPPUCCIN, SOLARIZED, DRACULA, OUTRUN, ZENBURN, ICEBERG) with hot-swappable switching.

**Recording & Export** — Live recording via `Ctrl+R`, headless `record_app()`/`record_widget()` for CI, native `.tach` format with Zstd compression, export to SVG and GIF.

**Async Tasks** — Channel-based background work that preserves the single-threaded Elm architecture. Cancel tokens, timers, and repeat scheduling.

**Testing** — `TestBackend` for headless widget rendering with `char_at()`, `style_at()`, `row_text()`, `find_text()` inspection APIs. Property-based testing with Supposition.jl.

## Quick Start

```julia
using Pkg
Pkg.add("Tachikoma")
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

See the [Getting Started](https://kahliburke.github.io/Tachikoma.jl/dev/getting-started) guide for a more complete walkthrough with layouts, widgets, and input handling.

## Demos

The `demos/TachikomaDemos` package includes 25+ interactive demos with a launcher menu:

```julia
using Pkg
Pkg.activate("demos/TachikomaDemos")
Pkg.instantiate()

using TachikomaDemos
launcher()  # interactive menu
```

Or run individual demos directly: `dashboard()`, `snake()`, `life()`, `sysmon()`, `anim_demo()`, `chart_demo()`, `form_demo()`, `effects_demo()`, and more.

## Gallery

<table>
<tr>
<td align="center"><strong>Dashboard</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_dashboard_app.gif" width="360"></td>
<td align="center"><strong>Form with Validation</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_form_app.gif" width="360"></td>
</tr>
<tr>
<td align="center"><strong>Animation Showcase</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_anim_showcase_app.gif" width="360"></td>
<td align="center"><strong>Todo List</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_todo_app.gif" width="360"></td>
</tr>
<tr>
<td align="center"><strong>GitHub PR Viewer</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_github_prs_app.gif" width="360"></td>
<td align="center"><strong>Constraint Explorer</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_constraint_explorer_app.gif" width="360"></td>
</tr>
<tr>
<td align="center"><strong>Dotwave Background</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_bg_dotwave.gif" width="360"></td>
<td align="center"><strong>Phylogenetic Tree</strong><br><img src="https://github.com/kahliburke/Tachikoma.jl/releases/download/docs-assets/readme_bg_phylotree.gif" width="360"></td>
</tr>
</table>

## Widget Catalog

| Category | Widgets |
|:---------|:--------|
| **Text & Display** | `Block`, `Paragraph`, `BigText`, `StatusBar`, `Span`, `Separator`, `MarkdownPane` |
| **Input** | `TextInput`, `TextArea`, `CodeEditor`, `Checkbox`, `RadioGroup`, `DropDown`, `Button` |
| **Selection & Lists** | `SelectableList`, `TabBar`, `TreeView`, `Calendar` |
| **Data** | `DataTable`, `Chart`, `BarChart`, `Sparkline`, `Gauge`, `ProgressList` |
| **Layout** | `Container`, `ScrollPane`, `Scrollbar`, `Modal`, `Form` |
| **Graphics** | `Canvas`, `BlockCanvas`, `PixelImage` |

## Backgrounds

Procedural animated backgrounds that composite behind your UI:

| Preset | Description |
|:-------|:------------|
| **DotWave** | Undulating dot-matrix terrain with configurable wave layers |
| **PhyloTree** | Animated phylogenetic branching structures |
| **Cladogram** | Hierarchical cladogram tree visualizations |

## Optional Extensions

```julia
# Markdown rendering
using CommonMark
# GIF export
using FreeTypeAbstraction, ColorTypes
# Tables.jl integration for DataTable
using Tables
```

## Documentation

Full documentation is available at **[kahliburke.github.io/Tachikoma.jl](https://kahliburke.github.io/Tachikoma.jl/dev/)**.

| Section | Description |
|:--------|:------------|
| [Getting Started](https://kahliburke.github.io/Tachikoma.jl/dev/getting-started) | Build your first app in 30 lines |
| [Architecture](https://kahliburke.github.io/Tachikoma.jl/dev/architecture) | The Elm architecture pattern in depth |
| [Layout](https://kahliburke.github.io/Tachikoma.jl/dev/layout) | Constraint-based layout system |
| [Widgets](https://kahliburke.github.io/Tachikoma.jl/dev/widgets) | Complete catalog of all widgets |
| [Animation](https://kahliburke.github.io/Tachikoma.jl/dev/animation) | Tweens, springs, timelines, and organic effects |
| [Graphics](https://kahliburke.github.io/Tachikoma.jl/dev/canvas) | Canvas, BlockCanvas, and pixel rendering |
| [Themes](https://kahliburke.github.io/Tachikoma.jl/dev/styling) | 11 built-in themes with hot-swap switching |
| [Recording](https://kahliburke.github.io/Tachikoma.jl/dev/recording) | Recording and export to SVG/GIF |
| [Testing](https://kahliburke.github.io/Tachikoma.jl/dev/testing) | TestBackend for headless widget testing |
| [API Reference](https://kahliburke.github.io/Tachikoma.jl/dev/api) | Auto-generated API documentation |

## Requirements

- Julia 1.10+
- A terminal with ANSI color support (most modern terminals)
- Kitty or sixel-capable terminal for pixel graphics (kitty, iTerm2, WezTerm, foot, etc.)

## Contributing

Contributions are welcome. Please open an issue to discuss proposed changes before submitting a pull request.

## License

MIT — see [LICENSE](LICENSE) for details.
