# Installation

## Requirements

- **Julia 1.10** or later (LTS supported)
- A terminal emulator with Unicode support (virtually all modern terminals)

## Install

Install Tachikoma from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/kahliburke/Tachikoma.jl")
```

Or in the Pkg REPL (press `]`):

```
pkg> add https://github.com/kahliburke/Tachikoma.jl
```

For development:

```julia
Pkg.develop(url="https://github.com/kahliburke/Tachikoma.jl")
```

## Terminal Recommendations

Tachikoma works in any terminal that supports VT100 escape sequences (basically everything). For the best experience:

### Pixel Graphics Support

For pixel-perfect rendering with `PixelImage` and `PixelCanvas`, use a terminal with Kitty or sixel graphics support:

| Terminal | Platform | Pixel Graphics |
|:---------|:---------|:---------------|
| **kitty** | Cross-platform | Kitty graphics (fastest) |
| **iTerm2** | macOS | Sixel |
| **WezTerm** | Cross-platform | Sixel |
| **foot** | Linux (Wayland) | Sixel |
| **mlterm** | Cross-platform | Sixel |

### Standard Terminals

Braille and block rendering work everywhere. These terminals are well-tested:

- **Terminal.app** (macOS) — braille and block backends
- **GNOME Terminal** / **Konsole** — full support, no pixel graphics
- **Windows Terminal** — full support, no pixel graphics
- **Alacritty** — fast, no pixel graphics

## Optional Extensions

Tachikoma uses Julia's package extension system for optional features. Each extension loads automatically when its dependencies are imported, or you can activate it explicitly with a helper function.

### GIF Export

Record and export animated GIF files from app recordings and widget demos. Requires `FreeTypeAbstraction` and `ColorTypes`:

```julia
using Pkg
Pkg.add(["FreeTypeAbstraction", "ColorTypes"])
```

Activate with:

```julia
using Tachikoma
enable_gif()

# Then use export_gif, export_gif_from_snapshots, etc.
```

### Tables.jl Integration

Enables `DataTable` to accept any [Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible source (DataFrames, CSV, etc.):

```julia
using Pkg
Pkg.add("Tables")
```

Activate with:

```julia
using Tachikoma
enable_tables()

# Then pass any Tables.jl source to DataTable
using Tables
dt = DataTable(my_dataframe)
```

[`DataTable`](widgets.md#datatable) supports sorting, selection, column resize, and horizontal scrolling:

<!-- tachi:widget datatable_install w=60 h=10
dt = DataTable(
    [DataColumn("Package", Any["Tachikoma", "Makie", "Plots", "Genie", "HTTP"]; align=col_left),
     DataColumn("Stars", Any["120", "4.8k", "3.2k", "2.1k", "850"]; align=col_right),
     DataColumn("Type", Any["TUI", "Plotting", "Plotting", "Web", "HTTP"]; align=col_center)];
    selected=2,
    block=Block(title="Julia Packages", border_style=tstyle(:border_focus)),
)
render(dt, area, buf)
-->

```julia
dt = DataTable(
    [DataColumn("Package", Any["Tachikoma", "Makie", "Plots", "Genie", "HTTP"]),
     DataColumn("Stars", Any["120", "4.8k", "3.2k", "2.1k", "850"]; align=col_right),
     DataColumn("Type", Any["TUI", "Plotting", "Plotting", "Web", "HTTP"])];
    selected=2,
    block=Block(title="Julia Packages"),
)
```

### Markdown Rendering

Enables the `MarkdownPane` widget for rendering CommonMark content in the terminal. Requires `CommonMark`:

```julia
using Pkg
Pkg.add("CommonMark")
```

Activate with:

```julia
using Tachikoma
enable_markdown()

# Then use MarkdownPane
pane = MarkdownPane("# Hello\n\nSome **bold** text")
```

[`MarkdownPane`](widgets.md#markdownpane) renders CommonMark with styled headings, lists, code blocks with syntax highlighting, and more:

<!-- tachi:widget markdown_install w=60 h=16
pane = MarkdownPane("# Welcome\n\nTachikoma renders **CommonMark** with:\n\n- **Bold** and *italic* text\n- `inline code` highlights\n- Syntax-highlighted code fences\n\n> The future is already here.\n\n```julia\napp(Life())\n```"; width=58, block=Block(title="Markdown", border_style=tstyle(:border_focus)))
render(pane, area, buf)
-->

```julia
enable_markdown()
pane = MarkdownPane("# Hello\n\n**Bold**, *italic*, and `code`.")
```

All extensions can also be activated by directly importing their dependencies (`using FreeTypeAbstraction, ColorTypes`, `using Tables`, or `using CommonMark`) before or after `using Tachikoma`.

## Verify Installation

```julia
using Tachikoma

# Check that the module loads and themes are available
println("Tachikoma v", pkgversion(Tachikoma))
println("Active theme: ", theme().name)
println("Themes: ", join([t.name for t in ALL_THEMES], ", "))
```
