# Tachikoma vs Ratatui

Tachikoma.jl and [Ratatui](https://ratatui.rs/) share the immediate-mode rendering model and constraint-based layouts. This page highlights similarities and differences.

## Architecture

| Feature | Tachikoma.jl | Ratatui |
|:--------|:-------------|:--------|
| Language | Julia | Rust |
| Rendering model | Immediate mode | Immediate mode |
| App pattern | Elm architecture (Model → update! → view) | User-managed event loop |
| State management | Mutable model struct | User-managed |
| Event loop | Built-in `app()` with configurable FPS | Manual (crossterm/termion) |
| Default bindings | Built-in (theme, settings, help overlays) | None |

## Layout System

| Feature | Tachikoma.jl | Ratatui |
|:--------|:-------------|:--------|
| Constraint types | `Fixed`, `Fill`, `Percent`, `Min`, `Max`, `Ratio` | `Length`, `Fill`, `Percentage`, `Min`, `Max`, `Ratio` |
| Flex alignment | `layout_start`, `layout_center`, `layout_end`, `layout_space_between`, `layout_space_around`, `layout_space_evenly` | `Flex::Start`, `Flex::Center`, `Flex::End`, `Flex::SpaceBetween`, `Flex::SpaceAround`, `Flex::SpaceEvenly` |
| Spacing | `Layout(dir, constraints; spacing=n)` | `Layout::default().spacing(n)` |
| Resizable panes | `ResizableLayout` with mouse drag | Not built-in |

## Widgets

| Widget | Tachikoma.jl | Ratatui |
|:-------|:-------------|:--------|
| Block (borders) | `Block` with `BOX_ROUNDED`, `BOX_HEAVY`, etc. | `Block` with `BorderType` |
| Paragraph | `Paragraph` with `Span` | `Paragraph` with `Span` |
| List | `SelectableList` with mouse support | `List` |
| Table | `Table`, `DataTable` (sortable, filterable) | `Table` |
| Tabs | `TabBar` | `Tabs` |
| Gauge | `Gauge` with animation tick | `Gauge`, `LineGauge` |
| Sparkline | `Sparkline` | `Sparkline` |
| BarChart | `BarChart` with `BarEntry` | `BarChart` with `Bar` |
| Chart | `Chart` with `DataSeries` (line/scatter) | `Chart` with `Dataset` |
| Calendar | `Calendar` | `Monthly` (ratatui-widgets) |
| Canvas | `Canvas`, `BlockCanvas`, `PixelCanvas` | `Canvas` |
| Scrollbar | `Scrollbar`, `ScrollPane` | `Scrollbar` |
| BigText | `BigText` | `BigText` (ratatui-widgets) |
| Modal | `Modal` | Not built-in |
| Form | `Form` with `FormField` | Not built-in |
| TreeView | `TreeView` with `TreeNode` | `Tree` (tui-tree-widget) |

## Tachikoma-Only Features

| Feature | Description |
|:--------|:------------|
| **Input widgets** | `TextInput`, `TextArea`, `CodeEditor`, `Checkbox`, `RadioGroup`, `DropDown` |
| **Form system** | `Form` / `FormField` with focus navigation and validation |
| **FocusRing** | Automatic Tab/Shift-Tab navigation between widgets |
| **Animation system** | `Tween`, `Spring`, `Timeline` (`sequence`, `stagger`, `parallel`) |
| **Organic effects** | `pulse`, `breathe`, `shimmer`, `noise`, `fbm`, `color_wave` |
| **Buffer fills** | `fill_gradient!`, `fill_noise!`, `border_shimmer!` |
| **Backgrounds** | `DotWaveBackground`, `PhyloTreeBackground`, `CladogramBackground` |
| **Pixel graphics** | `PixelImage`, `PixelCanvas` for pixel-perfect raster rendering (Kitty or sixel) |
| **Theme system** | 11 built-in themes (`kokaku`, `esper`, `motoko`, etc.) with live switching |
| **Settings overlay** | Ctrl+S opens in-app settings (theme, animations, backgrounds) |
| **Async tasks** | `TaskQueue` / `spawn_task!` for non-blocking background work |
| **MarkdownPane** | CommonMark rendering with scroll support |
| **Pattern matching** | `@match` integration for event handling |
| **Recording & export** | `record_app`, `record_widget` → `.tach`, `.svg`, `.gif` |
| **ProgressList** | Task status list with `task_done`, `task_running`, `task_pending` |
| **Container** | Automatic widget layout positioning |
| **StatusBar** | Full-width bar with left/right aligned spans |

## Ratatui-Only Features

| Feature | Description |
|:--------|:------------|
| **Rust ecosystem** | Access to the full Rust crate ecosystem |
| **Performance** | Zero-cost abstractions, no GC pauses |
| **Backend choice** | Crossterm, termion, or termwiz backends |
| **Widget crates** | Large ecosystem of community widgets |
| **Color types** | `Color::Rgb`, `Color::Indexed`, `Color::Reset` |
| **Modifiers** | Fine-grained text modifiers (`BOLD`, `ITALIC`, `UNDERLINED`, etc.) |
| **Masked input** | Built-in password/masked text input |

## Migration Guide

If you're coming from Ratatui to Tachikoma:

| Ratatui | Tachikoma.jl |
|:--------|:-------------|
| `Frame::render_widget(w, area)` | `render(widget, area, buf)` |
| `Layout::default().constraints([...]).split(area)` | `split_layout(Layout(dir, [...]), area)` |
| `Paragraph::new(vec![Span::styled(...)])` | `Paragraph([Span("...", style)])` |
| `Block::default().title("...").borders(Borders::ALL)` | `Block(title="...", border_style=tstyle(:border))` |
| `ListState { selected: Some(i) }` | `SelectableList(...; selected=i)` |
| `event::read()?` | `update!(model, evt)` callback |
| `Terminal::draw(\|f\| { ... })?` | `view(model, frame)` callback |
