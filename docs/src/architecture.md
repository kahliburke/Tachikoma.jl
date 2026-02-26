# Architecture

Tachikoma uses an **Elm-inspired architecture**: your application state lives in a single `Model`, events flow through `update!`, and the UI is rebuilt each frame in `view`. The framework manages the terminal, event loop, and double-buffered rendering.

## The Model/Update/View Pattern

<!-- tachi:app event_loop w=48 h=16 frames=240 fps=30 -->

Every frame, the framework polls for input, dispatches events to `update!`, calls `view` to render the UI into a buffer, then diffs the buffer against the previous frame and writes only the changed cells to the terminal.

### 1. Define Your Model

`Model` is an abstract type that your application state must subtype. It serves as the dispatch anchor for the framework — the event loop calls `update!(model, event)` and `view(model, frame)` on your concrete type. The framework never mutates your model directly; you control all state changes in `update!`.

```julia
@kwdef mutable struct MyApp <: Model
    quit::Bool = false
    tick::Int = 0
    # ... your state fields ...
end
```

### 2. Implement the Protocol

| Method | Required | Description |
|:-------|:---------|:------------|
| `view(model, frame)` | **Yes** | Render the UI into the frame's buffer |
| `update!(model, event)` | No | Handle keyboard/mouse events |
| `should_quit(model)` | No | Return `true` to exit (default: `false`) |
| `init!(model, terminal)` | No | One-time setup when app starts |
| `cleanup!(model)` | No | Teardown when app exits |
| `copy_rect(model)` | No | `Rect` of focused pane for Ctrl+Y copy |
| `task_queue(model)` | No | Return a `TaskQueue` for async integration |

### 3. Run the App

```julia
app(MyApp(); fps=60, default_bindings=true)
```

## Lifecycle

<!-- tachi:widget lifecycle_tree w=58 h=13
root = TreeNode("app(model) called", [
    TreeNode("Enter alternate screen, raw mode + mouse"),
    TreeNode("init!(model, terminal)"),
    TreeNode("Load saved layout preferences"),
    TreeNode("Event Loop (repeats at fps rate)", [
        TreeNode("poll_event() → KeyEvent / MouseEvent / nothing"),
        TreeNode("Handle default bindings (theme, help, settings)"),
        TreeNode("update!(model, event)"),
        TreeNode("view(model, frame)"),
        TreeNode("Diff buffers → write changes to terminal"),
    ]),
    TreeNode("Save layout preferences"),
    TreeNode("cleanup!(model)"),
    TreeNode("Restore terminal (alt screen off, mouse off)"),
])
render(TreeView(root; indent=2, connector_style=tstyle(:border)), area, buf)
-->

## Stdout Protection

During TUI mode, `stdout` and `stderr` are automatically redirected to pipes so that background `println()` calls (from async tasks, test runners, etc.) cannot corrupt the display. Rendering goes to `/dev/tty` directly, bypassing the redirected file descriptors.

By default, captured output is silently discarded. Pass `on_stdout` / `on_stderr` callbacks to receive captured lines — for example, to display them in an activity log:

<!-- tachi:noeval -->
```julia
app(model; on_stdout=line -> push!(my_log, line))
```

This also works with `with_terminal` directly:

<!-- tachi:noeval -->
```julia
with_terminal(on_stdout=line -> push!(log, line)) do t
    # background println() calls are captured, TUI is clean
end
```

The `terminal_size()` function automatically falls back to `stdin` for size queries when `stdout` is not a TTY, so window resize detection works regardless of redirection.

## Frame vs Buffer

The `view` function receives a `Frame`:

```julia
function view(m::MyApp, f::Frame)
    buf = f.buffer    # Buffer — the 2D cell grid you write into
    area = f.area     # Rect — the full terminal area
    # f.gfx_regions — for pixel data (advanced)
end
```

- **`Buffer`** — A 2D grid of styled characters. Use `set_char!`, `set_string!`, and widget `render` calls to fill it.
- **`Frame`** — Wraps the buffer plus the terminal area and graphics regions. Passed to `view` and to `render(widget, rect, frame)` for widgets that produce raster output.

Most widgets render to the buffer:

<!-- tachi:noeval -->
```julia
render(widget, rect, buf)      # buffer-based (most widgets)
render(widget, rect, frame)    # frame-based (pixel widgets use this)
```

## The Render Dispatch

All widgets implement `render(widget, area::Rect, buf::Buffer)`. Some widgets (like `Block`) return the inner `Rect` after drawing borders:

<!-- tachi:widget render_dispatch_demo w=40 h=7 -->
```julia
inner = render(Block(title="Panel"), area, buf)
set_string!(buf, inner.x, inner.y, "Content here", tstyle(:primary, bold=true))
set_string!(buf, inner.x, inner.y + 1, "rendered inside inner Rect", tstyle(:text_dim))
```

## AppOverlay and Default Bindings

When `default_bindings=true` (the default), the framework intercepts certain key combinations before they reach your `update!`:

- `Ctrl+G` — Toggle mouse mode
- `Ctrl+\` — Theme selector overlay
- `Ctrl+A` — Toggle animations
- `Ctrl+S` — Settings overlay (render backend, decay, background)
- `Ctrl+?` — Help overlay
- `Ctrl+Y` — Copy focused pane to clipboard

These overlays render on top of your view. When an overlay is open, it consumes all key events until dismissed.

Override `copy_rect(model)` to return the `Rect` of a specific pane for Ctrl+Y:

```julia
function copy_rect(m::MyApp)
    m.pane_rects[m.focused_pane]  # copy just this pane
end
```

Return `nothing` (the default) to copy the full screen.

## Clipboard Support

<!-- tachi:noeval -->
```julia
clipboard_copy!(text::String)
```

Copies text to the system clipboard. Uses `pbcopy` on macOS and `xclip` on Linux.

<!-- tachi:noeval -->
```julia
buffer_to_text(buf::Buffer, rect::Rect) → String
```

Extracts visible text from a buffer region — used internally by Ctrl+Y but available for custom clipboard operations.
