# Demos

The `demos/TachikomaDemos` package includes 35+ interactive demos covering every major feature. Run the launcher to browse them all, or launch individual demos directly.

## Running the Demos

```julia
using Pkg
Pkg.activate("demos/TachikomaDemos")
Pkg.instantiate()

using TachikomaDemos
launcher()
```

The launcher presents a categorized tree of all available demos. Use arrow keys to navigate, Left/Right to collapse/expand categories, Enter to launch. Mouse click and scroll wheel are also supported.

## Running in a browser

Every demo can run in a web browser instead of the terminal. Nothing about
the demo changes: it still emits the same terminal output, and
The web backend tunnels that output to an `xterm.js` terminal in the browser 
over a WebSocket, sending keystrokes back. It requires the `HTTP.jl` package. 
Install it via the package manager (`] add HTTP`). Then load `HTTP` and choose a backend:

```julia
using TachikomaDemos, HTTP

run_demo(snake; backend = :webterminal)        # serves http://127.0.0.1:8000
browser(life)                          # shorthand for backend = :webterminal
run_demo(fps_demo; backend = :webterminal, port = 9000)

launcher(backend = :webterminal)               # navigate the menu in the terminal,
                                       # each demo you pick opens in the browser
```

`run_demo` is what every demo ends on, so the switch is uniform:
`backend = :console` (the default) hands the model to [`app`](@ref) in the
terminal; `backend = :webterminal` serves it over HTTP/WebSockets.
The web backend lives in a package extension, so it costs nothing and is
unavailable until `HTTP` is loaded -- `:webterminal` without it fails with a
message telling you to load it.

One property follows from the web backend: it is
**single-session** -- one browser at a time. It resizes live with the
browser window, and pixel panes render as SIXEL graphics through xterm.js's
image addon, so a demo looks the same in the browser as in the terminal.

To run a specific demo directly:

<!-- tachi:noeval -->
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
| **Overlapping Windows** | `windows_demo()` | Draggable/resizable floating windows with z-order, opacity, and wheel-driven content scrolling |
| **Effects Gallery** | `effects_demo()` | fill_gradient!, fill_noise!, glow, flicker, drift, shimmer, breathing, pulse |
| **Chart** | `chart_demo()` | Interactive chart with dual sine, scatter cloud, and live streaming modes |
| **DataTable** | `datatable_demo()` | Sortable, scrollable data table with column sort |
| **Paged DataTable** | `paged_datatable_demo()` | Virtual data table with 1M rows, provider interface, sort/filter/search/pagination |
| **Form** | `form_demo()` | TextInput, TextArea, Checkbox, RadioGroup, DropDown with live preview |
| **Code Editor** | `editor_demo()` | Julia syntax highlighting, auto-indentation, Tab/Shift-Tab indent |
| **FPS Stress Test** | `fps_demo()` | Interactive frame rate stress test with tunable complexity |
| **Phylo Tree** | `phylo_demo()` | Radial phylogenetic tree background with animated branches |
| **Cladogram** | `clado_demo()` | Fan-layout cladogram with right-angle polar routing |
| **PixelImage Demo** | `sixel_demo()` | Plasma, terrain, Mandelbrot, interference via sixel or braille fallback |
| **Sixel Gallery** | `sixel_gallery()` | CPU heatmap, latency distribution, memory page map, flame graph |
| **Async Tasks** | `async_demo()` | Background task system: spawn tasks, trigger failures, repeating timers |
| **Markdown Viewer** | `markdown_demo()` | README viewer, live split-pane editor, style preset picker |
| **ANSI Text** | `ansi_demo()` | ANSI escape sequence showcase: parsed colors/styles vs raw text, auto-follow log |
| **TabBar** | `tabbar_demo()` | Tab bar styles, overflow, per-tab colors, mouse support |
| **Widget Styles** | `widget_styles_demo()` | BracketTabs, BoxTabs, PlainTabs, button decoration comparison |
| **Floating Windows** | `windows_demo()` | Overlapping windows with z-order, transparency, drag/resize, sparklines and forms inside |
| **Terminal Emulator** | `terminal_demo()` | Embedded shell in a FloatingWindow with PTY, ANSI colors, Ctrl+N for multiple terminals |
| **Julia REPL** | `repl_demo()` | In-process Julia REPL in a FloatingWindow, shared state, tab completion, Pkg mode |
| **Widget Scroll** | `scroll_demo()` | 2D pannable viewport: sparklines, tables, bar charts, gauges across a large virtual space |
| **Unicode & Graphemes** | `unicode_demo()` | Zero-width combining marks, CJK wide characters, mixed-width text across widgets |
| **ColorTypes Interop** | `colortypes_demo()` | ColorTypes.jl extension: roundtrip conversions between Tachikoma and ColorTypes colors |
