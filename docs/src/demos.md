# Demos

The `demos/TachikomaDemos` package includes 25+ interactive demos covering every major feature. Run the launcher to browse them all, or launch individual demos directly.

## Running the Demos

```julia
using Pkg
Pkg.activate("demos/TachikomaDemos")
Pkg.instantiate()

using TachikomaDemos
launcher()
```

The launcher presents a menu of all available demos. Use arrow keys to navigate and Enter to launch.

To run a specific demo directly:

```julia
using TachikomaDemos
dashboard()
```

## Available Demos

| Demo | Function | Description |
|:-----|:---------|:------------|
| **Theme Gallery** | `demo()` | Color palettes, box styles, block characters, signal bars |
| **Dashboard** | `dashboard()` | Simulated system monitor with CPU/memory gauges, network sparkline, process table |
| **Matrix Rain** | `rain()` | Falling katakana and latin characters with brightness falloff |
| **System Monitor** | `sysmon()` | 3-tab monitor: overview with bar charts, process table, network canvas plots |
| **Clock** | `clock()` | Real-time BigText clock with stopwatch and calendar widget |
| **Snake** | `snake()` | Classic snake game with arrow key controls |
| **Waves** | `waves()` | Animated parametric curves on braille canvas: Lissajous, spirograph, sine, oscilloscope |
| **Game of Life** | `life()` | Conway's cellular automaton on braille canvas with interactive cursor |
| **Animation System** | `anim_demo()` | Tween, Spring, Timeline, and easing functions across four live panels |
| **Mouse Draw** | `mouse_demo()` | Interactive braille canvas drawing with left-click, right-click erase, scroll brush resize |
| **Chaos** | `chaos()` | Logistic map bifurcation diagram on braille canvas |
| **Dot Waves** | `dotwave()` | Halftone dot field modulated by layered sine waves and noise |
| **Showcase** | `showcase()` | Rainbow arc, terrain background, spring gauges, sparklines, particles |
| **Backend Compare** | `backend_demo()` | Split-screen: same animation in braille, block, and PixelImage rendering |
| **Resize Panes** | `resize_demo()` | Drag pane borders to resize, demonstrating ResizableLayout |
| **ScrollPane Log** | `scrollpane_demo()` | Live log viewer with auto-follow, reverse mode, mouse wheel scrolling |
| **Effects Gallery** | `effects_demo()` | fill_gradient!, fill_noise!, glow, flicker, drift, shimmer, breathing, pulse |
| **Chart** | `chart_demo()` | Interactive chart with dual sine, scatter cloud, and live streaming modes |
| **DataTable** | `datatable_demo()` | Sortable, scrollable data table with column sort |
| **Form** | `form_demo()` | TextInput, TextArea, Checkbox, RadioGroup, DropDown with live preview |
| **Code Editor** | `editor_demo()` | Julia syntax highlighting, auto-indentation, Tab/Shift-Tab indent |
| **FPS Stress Test** | `fps_demo()` | Interactive frame rate stress test with tunable complexity |
| **Phylo Tree** | `phylo_demo()` | Radial phylogenetic tree background with animated branches |
| **Cladogram** | `clado_demo()` | Fan-layout cladogram with right-angle polar routing |
| **PixelImage Demo** | `sixel_demo()` | Plasma, terrain, Mandelbrot, interference via sixel or braille fallback |
| **Sixel Gallery** | `sixel_gallery()` | CPU heatmap, latency distribution, memory page map, flame graph |
| **Async Tasks** | `async_demo()` | Background task system: spawn tasks, trigger failures, repeating timers |
| **Markdown Viewer** | `markdown_demo()` | README viewer, live split-pane editor, style preset picker |
