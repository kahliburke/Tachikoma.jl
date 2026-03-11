# Terminal & REPL Widgets

::: warning Experimental (v1.1)

Terminal and REPL widgets are new in Tachikoma v1.1 and still under active development. APIs may change in future releases.

:::

**Platform support:** The terminal widget requires Unix PTY support and **will not work on Windows** until a ConPTY backend is contributed. The REPL widget is more likely to work on Windows but has not been tested there yet.

`TerminalWidget` and `REPLWidget` embed full terminal emulators directly inside a Tachikoma application. `TerminalWidget` spawns an external process (a shell, Julia, or any command) in a pseudo-terminal. `REPLWidget` runs an in-process Julia REPL that shares all loaded modules, variables, and state with the host application.

Both widgets render through the same VT parser and PTY infrastructure. They work standalone or as `content` inside a [`FloatingWindow`](window-manager.md).

<!-- tachi:app repl_widget_demo w=80 h=20 frames=180 fps=15 realtime -->

## How it works

A pseudo-terminal (PTY) is a pair of virtual devices: a **master** and a **slave**. The subprocess (or in-process REPL) reads and writes the slave side as if it were a real terminal. The widget reads from the master side, feeds the bytes through a VT100/xterm escape sequence parser, and renders the resulting screen buffer into the Tachikoma frame. Keyboard input travels the reverse path: the widget encodes keystrokes as ANSI escape sequences and writes them to the master.

<!-- tachi:app pty_flow w=48 h=14 frames=240 fps=30 -->

The VT parser handles:
- **Cursor movement** — absolute, relative, save/restore
- **SGR styling** — bold, italic, underline, 256-color, RGB color
- **Screen operations** — erase line/display, scroll regions, insert/delete lines
- **Alternate screen** — `DECSET 1049` (used by vim, htop, less, etc.)
- **Mouse reporting** — SGR pixel mode for scroll and click forwarding
- **OSC sequences** — window title updates, hyperlinks
- **Scrollback** — lines scrolled off the top are saved and navigable

## TerminalWidget

Spawns a subprocess in a PTY, parses its ANSI output into a screen buffer, and renders it as a widget. Keyboard input is forwarded to the subprocess as escape sequences.

### Creating a terminal

<!-- tachi:noeval -->
```julia
# Default: spawns a Julia REPL (julia --banner=no)
tw = TerminalWidget()

# Spawn a specific shell
tw = TerminalWidget(["/bin/bash"]; rows=24, cols=80)

# Spawn any command
tw = TerminalWidget(["htop"]; rows=40, cols=120)

# Pass environment variables
tw = TerminalWidget(["/bin/zsh"]; env=Dict("TERM" => "xterm-256color"))
```

### Constructor options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cmd` | `Vector{String}` | `["julia", "--banner=no"]` | Command and arguments to spawn |
| `rows` | `Int` | `24` | Initial terminal height |
| `cols` | `Int` | `80` | Initial terminal width |
| `show_scrollbar` | `Bool` | `true` | Show scrollbar when scrolled back |
| `focused` | `Bool` | `true` | Whether the widget starts focused |
| `scrollback_limit` | `Int` | `1000` | Maximum scrollback lines |
| `title_callback` | `Function` or `nothing` | `nothing` | Called when the process sets the terminal title (via OSC escape) |
| `on_exit` | `Function` or `nothing` | `nothing` | Called when the subprocess exits |
| `env` | `Dict{String,String}` or `nothing` | `nothing` | Extra environment variables (merged with current `ENV`) |

### Widget protocol

`TerminalWidget` follows the standard widget protocol:

<!-- tachi:noeval -->
```julia
# In your update!:
handle_key!(tw, evt)     # forward keyboard input to the PTY
handle_mouse!(tw, evt)   # scroll wheel navigates scrollback

# In your view:
render(tw, area, buf)    # drains PTY output, parses VT sequences, renders screen

# Check for pending output (for event-driven apps):
drain!(tw)               # returns true if screen changed

# Cleanup:
close!(tw)               # kills subprocess and closes PTY
```

### Scrollback

When the terminal output exceeds the visible area, older lines are pushed into a scrollback buffer (up to `scrollback_limit` lines). Navigation:

| Input | Action |
|-------|--------|
| Scroll wheel up | Scroll back through history |
| Scroll wheel down | Scroll toward live view |
| Page Up | Jump one page back |
| Page Down | Jump one page forward |
| Any other key | Return to live view and forward keystroke |
| Modifier keys (Shift, Ctrl, etc.) | Stay in scrollback (for copy/paste) |

A scrollbar indicator appears on the right edge when scrolled back, showing your position relative to the full buffer.

### Wake notifications

For event-driven apps that sleep until input arrives, wire `set_wake!` so the widget wakes the app loop when new PTY output arrives:

<!-- tachi:noeval -->
```julia
function Tachikoma.set_wake!(m::MyModel, notify::Function)
    m._wake_fn = notify
    Tachikoma.set_wake!(m.terminal_widget, notify)
end
```

Without this, the app loop won't know to redraw when the terminal has new output. This is critical for apps using `set_wake!` for event-driven rendering (see [Architecture](architecture.md)).

### Resize

When the widget's rendered area changes, `render` automatically detects the size difference and sends a `TIOCSWINSZ` ioctl plus `SIGWINCH` to the subprocess. Programs like bash, vim, and htop respond by reflowing their output to the new dimensions.

You can also resize manually:

<!-- tachi:noeval -->
```julia
pty_resize!(tw.pty, new_rows, new_cols)
```

### Exit detection

When the subprocess exits, `drain!` sets `tw.exited = true` and calls `on_exit` if provided. The widget displays a `[Process exited]` message and stops forwarding input.

## REPLWidget

Runs a full Julia REPL (`LineEditREPL`) inside the current process, connected to a PTY pair. Unlike `TerminalWidget`, no subprocess is spawned — the REPL shares all loaded modules, variables, and state with the host application.

This means you can define a function in your app, then call it from the embedded REPL. Or inspect app state, load packages, and run arbitrary Julia code — all within the TUI.

### Creating a REPL widget

<!-- tachi:noeval -->
```julia
rw = REPLWidget(; rows=24, cols=80)
```

### Constructor options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `rows` | `Int` | `24` | Terminal height |
| `cols` | `Int` | `80` | Terminal width |
| `show_scrollbar` | `Bool` | `true` | Show scrollbar when scrolled back |
| `focused` | `Bool` | `true` | Whether the widget starts focused |
| `scrollback_limit` | `Int` | `1000` | Maximum scrollback lines |
| `on_exit` | `Function` or `nothing` | `nothing` | Called when the REPL exits (e.g., Ctrl+D) |

### REPL features

The embedded REPL supports the same features as the standard Julia REPL:

- **Colored prompts** and syntax highlighting
- **Tab completion** for functions, variables, and file paths
- **Help mode** — press `?` to look up documentation
- **Pkg mode** — press `]` for package management (`status`, `add`, `update`, etc.)
- **Shell mode** — press `;` to run shell commands (output appears immediately)
- **History** — arrow keys navigate command history
- **Reverse search** — `Ctrl+R` searches history
- **Multi-line editing** — incomplete expressions continue on the next line
- **Interactive prompts** — Pkg install prompts ("Install package? (y/n)") work and accept keyboard input from the widget

### Widget protocol

`REPLWidget` delegates to an inner `TerminalWidget` and follows the same protocol:

<!-- tachi:noeval -->
```julia
# In your update!:
handle_key!(rw, evt)
handle_mouse!(rw, evt)

# In your view:
render(rw, area, buf)

# Check for pending output:
drain!(rw)               # also detects REPL exit (Ctrl+D)

# Cleanup:
close!(rw)
```

### Routing captured output

In TUI mode, Tachikoma captures `stdout` and `stderr` to prevent background output from corrupting the screen. This means `println("hello")` from the REPL backend would go to the capture pipe instead of appearing in the widget.

To fix this, route captured output back to the REPL widget using the `on_stdout` / `on_stderr` callbacks:

<!-- tachi:noeval -->
```julia
function _route_output(m::MyModel, text::String)
    isempty(m.repls) && return
    # Route to the focused REPL, falling back to the last one
    fw = Tachikoma.focused_window(m.wm)
    if fw !== nothing && fw.content isa Tachikoma.REPLWidget
        route_output!(fw.content, text)
    else
        route_output!(m.repls[end], text)
    end
end

# Pass the callbacks when launching the app:
Tachikoma.app(model;
    on_stdout = text -> _route_output(model, text),
    on_stderr = text -> _route_output(model, text))
```

`route_output!` writes directly to the PTY output channel rather than through the slave TTY handle. This avoids libuv threading issues when the REPL frontend is concurrently using the same underlying PTY.

### stdin redirect

`REPLWidget` redirects `Base.stdin` to the PTY slave so that interactive prompts (like Pkg's install confirmation) read keystrokes from the widget. The app's event loop reads from a saved copy of the original stdin, so this redirect does not interfere with input handling.

If you have multiple REPL widgets, the most recently created one owns stdin. A future release may add explicit focus-based stdin routing.

## Example: REPL in a floating window

This is a complete, runnable application that places a Julia REPL inside a floating window. It demonstrates the key patterns: creating the widget, routing output, wiring wake notifications, and cleanup.

<!-- tachi:noeval -->
```julia
import Tachikoma

@kwdef mutable struct REPLApp <: Tachikoma.Model
    quit::Bool = false
    wm::Tachikoma.WindowManager = Tachikoma.WindowManager()
    repl::Union{Tachikoma.REPLWidget, Nothing} = nothing
    _wake_fn::Union{Function, Nothing} = nothing
end

Tachikoma.should_quit(m::REPLApp) = m.quit
Tachikoma.recording_enabled(::REPLApp) = false  # free Ctrl+R for reverse search

function Tachikoma.has_pending_output(m::REPLApp)
    m.repl !== nothing && Tachikoma.drain!(m.repl)
end

function Tachikoma.set_wake!(m::REPLApp, notify::Function)
    m._wake_fn = notify
    m.repl !== nothing && Tachikoma.set_wake!(m.repl.tw, notify)
end

function Tachikoma.update!(m::REPLApp, evt::Tachikoma.Event)
    evt isa Tachikoma.KeyEvent && evt.key == :escape && (m.quit = true; return)
    Tachikoma.handle_event!(m.wm, evt)
end

function Tachikoma.view(m::REPLApp, f::Tachikoma.Frame)
    # Spawn the REPL window on first frame
    if m.repl === nothing
        w, h = f.area.width, f.area.height
        rw = Tachikoma.REPLWidget(; rows=h - 4, cols=w - 4)
        m.repl = rw
        m._wake_fn !== nothing && Tachikoma.set_wake!(rw.tw, m._wake_fn)
        push!(m.wm, Tachikoma.FloatingWindow(
            id = :repl,
            title = "Julia REPL",
            x = 2, y = 2, width = w - 2, height = h - 2,
            content = rw,
            border_color = Tachikoma.ColorRGB(0x60, 0xc0, 0x90),
        ))
    end

    Tachikoma.render(m.wm, f.area, f.buffer)
end

function Tachikoma.cleanup!(m::REPLApp)
    m.repl !== nothing && Tachikoma.close!(m.repl)
end

function run_repl_app()
    model = REPLApp()
    Tachikoma.app(model;
        on_stdout = text -> (model.repl !== nothing &&
            Tachikoma.route_output!(model.repl, text)),
        on_stderr = text -> (model.repl !== nothing &&
            Tachikoma.route_output!(model.repl, text)))
end

run_repl_app()
```

Key things to note:

1. **`recording_enabled` returns `false`** — this frees `Ctrl+R` so it passes through to the REPL for reverse history search instead of toggling the Tachikoma recording system.
2. **`has_pending_output` calls `drain!`** — this tells the event-driven app loop that the REPL has new data to render, so the app wakes up and redraws.
3. **`set_wake!` is forwarded** to the inner `TerminalWidget` — this is the push notification that wakes the app loop when PTY data arrives.
4. **Output routing** is wired in the `app()` call via `on_stdout` / `on_stderr`.
5. **`cleanup!` calls `close!`** — this shuts down the REPL task and closes the PTY when the app exits.

## Example: Multi-terminal app

A more complete example with both shell terminals and REPL widgets in floating windows. Users can spawn new windows, tile/cascade them, and interact with each independently.

<!-- tachi:noeval -->
```julia
import Tachikoma

@kwdef mutable struct MultiTermApp <: Tachikoma.Model
    quit::Bool = false
    wm::Tachikoma.WindowManager = Tachikoma.WindowManager()
    terminals::Vector{Tachikoma.TerminalWidget} = Tachikoma.TerminalWidget[]
    repls::Vector{Tachikoma.REPLWidget} = Tachikoma.REPLWidget[]
    count::Int = 0
    layout_mode::Symbol = :tile
    _wake_fn::Union{Function, Nothing} = nothing
end

Tachikoma.should_quit(m::MultiTermApp) = m.quit
Tachikoma.recording_enabled(::MultiTermApp) = false

function Tachikoma.has_pending_output(m::MultiTermApp)
    any(Tachikoma.drain!, m.repls) | any(Tachikoma.drain!, m.terminals)
end

function Tachikoma.set_wake!(m::MultiTermApp, notify::Function)
    m._wake_fn = notify
    for tw in m.terminals; Tachikoma.set_wake!(tw, notify); end
    for rw in m.repls; Tachikoma.set_wake!(rw.tw, notify); end
end

function _spawn_terminal!(m::MultiTermApp, area::Tachikoma.Rect)
    m.count += 1
    shell = get(ENV, "SHELL", "/bin/sh")
    tw = Tachikoma.TerminalWidget([shell]; rows=20, cols=60)
    m._wake_fn !== nothing && Tachikoma.set_wake!(tw, m._wake_fn)
    push!(m.terminals, tw)
    push!(m.wm, Tachikoma.FloatingWindow(
        id = Symbol("term_$(m.count)"),
        title = "Terminal #$(m.count)",
        x = 2, y = 2, width = 64, height = 22,
        content = tw,
        closeable = true,
        on_close = () -> (Tachikoma.close!(tw); filter!(!=(tw), m.terminals)),
        border_color = Tachikoma.ColorRGB(0xc0, 0x90, 0x60),
    ))
    Tachikoma.tile!(m.wm, area)
end

function _spawn_repl!(m::MultiTermApp, area::Tachikoma.Rect)
    m.count += 1
    rw = Tachikoma.REPLWidget(; rows=20, cols=60)
    m._wake_fn !== nothing && Tachikoma.set_wake!(rw.tw, m._wake_fn)
    push!(m.repls, rw)
    push!(m.wm, Tachikoma.FloatingWindow(
        id = Symbol("repl_$(m.count)"),
        title = "Julia REPL #$(m.count)",
        x = 2, y = 2, width = 64, height = 22,
        content = rw,
        closeable = true,
        on_close = () -> (Tachikoma.close!(rw); filter!(!=(rw), m.repls)),
        border_color = Tachikoma.ColorRGB(0x60, 0xc0, 0x90),
    ))
    Tachikoma.tile!(m.wm, area)
end

function Tachikoma.update!(m::MultiTermApp, evt::Tachikoma.Event)
    if evt isa Tachikoma.KeyEvent
        evt.key == :escape && (m.quit = true; return)

        if evt.key == :ctrl
            # Ctrl+N: new terminal, Ctrl+E: new REPL, Ctrl+T: tile/cascade
            evt.char == 'n' && m.wm.last_area.width > 0 &&
                return _spawn_terminal!(m, m.wm.last_area)
            evt.char == 'e' && m.wm.last_area.width > 0 &&
                return _spawn_repl!(m, m.wm.last_area)
            if evt.char == 't'
                if m.layout_mode == :tile
                    Tachikoma.cascade!(m.wm); m.layout_mode = :cascade
                else
                    Tachikoma.tile!(m.wm); m.layout_mode = :tile
                end
                return
            end
        end
    end
    Tachikoma.handle_event!(m.wm, evt)
end

function Tachikoma.view(m::MultiTermApp, f::Tachikoma.Frame)
    # Auto-spawn one terminal on first frame
    if isempty(m.wm.windows)
        _spawn_terminal!(m, f.area)
    end

    Tachikoma.render(m.wm, f.area, f.buffer)

    # Status bar
    n = length(m.wm.windows)
    hint = " [Ctrl+N] terminal │ [Ctrl+E] repl │ [Ctrl+T] layout │ [Esc] quit │ $n window$(n != 1 ? "s" : "") "
    Tachikoma.render(Tachikoma.StatusBar(
        left=[Tachikoma.Span(hint, Tachikoma.tstyle(:text_dim))],
    ), Tachikoma.Rect(f.area.x, Tachikoma.bottom(f.area) - 1,
                      f.area.width, 1), f.buffer)
end

function Tachikoma.cleanup!(m::MultiTermApp)
    for tw in m.terminals; Tachikoma.close!(tw); end
    for rw in m.repls; Tachikoma.close!(rw); end
end

function run_multi_term()
    model = MultiTermApp()
    Tachikoma.app(model;
        on_stdout = text -> begin
            isempty(model.repls) && return
            fw = Tachikoma.focused_window(model.wm)
            if fw !== nothing && fw.content isa Tachikoma.REPLWidget
                Tachikoma.route_output!(fw.content, text)
            else
                Tachikoma.route_output!(model.repls[end], text)
            end
        end,
        on_stderr = text -> begin
            isempty(model.repls) && return
            fw = Tachikoma.focused_window(model.wm)
            if fw !== nothing && fw.content isa Tachikoma.REPLWidget
                Tachikoma.route_output!(fw.content, text)
            else
                Tachikoma.route_output!(model.repls[end], text)
            end
        end)
end

run_multi_term()
```

## PTY internals

Both widgets are built on the `PTY` type, which manages a pseudo-terminal pair using `openpty()` and `posix_spawnp()`. Key design choices:

- **No `fork()`** — uses `posix_spawnp` to avoid deadlocks in Julia's multithreaded runtime. The child process gets `POSIX_SPAWN_SETSID` for a proper session and controlling terminal.
- **Non-blocking reads** — the master fd is set to `O_NONBLOCK` and polled by a background task using `FileWatching.poll_fd`. Data is delivered through a `Channel{Vector{UInt8}}`, decoupling PTY I/O from the render loop.
- **`pty_pair`** — `REPLWidget` uses `pty_pair()` instead of `pty_spawn()` to create a PTY without a subprocess. The in-process REPL reads/writes the slave side directly.

### Low-level PTY API

For advanced use cases, the PTY functions are available directly:

<!-- tachi:noeval -->
```julia
# Spawn a process in a PTY
pty = pty_spawn(["bash"]; rows=24, cols=80)

# Create a PTY pair without a subprocess (used by REPLWidget)
pty, slave_fd = pty_pair(; rows=24, cols=80)

# Write input to the subprocess
pty_write(pty, "ls -la\n")

# Read output (via channel)
data = take!(pty.output)          # blocks until data arrives
text = String(data)

# Resize the terminal
pty_resize!(pty, 40, 120)         # sends TIOCSWINSZ + SIGWINCH

# Check if subprocess is still running
pty_alive(pty)

# Cleanup
pty_close!(pty)                   # closes fds, kills process, stops reader
```

## Platform support

| Platform | TerminalWidget | REPLWidget |
|----------|---------------|------------|
| macOS | Supported | Supported |
| Linux | Supported | Supported |
| Windows | Not supported | Untested |

The PTY layer relies on Unix system calls (`openpty`, `posix_spawnp`, `TIOCSWINSZ`). Windows support for `TerminalWidget` would require a ConPTY backend behind the same `PTY` API surface. Contributions welcome.

The REPL widget does not spawn a subprocess and may work on Windows where `Base.TTY` is available, but this has not been tested. If you have access to a Windows machine and would like to help, please open an issue.

## Known limitations

- **Single stdin owner**: When multiple `REPLWidget`s exist, only the most recently created one receives interactive prompt input (e.g., Pkg's "Install? (y/n)"). Focus-based stdin routing is planned for a future release.
- **Echo on interactive prompts**: The y/n prompt for package installation works but typed characters may not echo visibly. The REPL itself echoes normally.
- **Fixed Pkg display size**: The REPL widget's `Pkg.DEFAULT_IO` uses the initial `rows` and `cols` for display sizing. If the widget is resized significantly after creation, Pkg output formatting may not adapt.
- **No Windows PTY**: `TerminalWidget` requires Unix PTY support. Windows ConPTY is not yet implemented.

## API summary

### TerminalWidget

- `TerminalWidget(cmd; rows, cols, show_scrollbar, focused, scrollback_limit, title_callback, on_exit, env)`
- `TerminalWidget()` — default Julia REPL subprocess
- `TerminalWidget(pty::PTY; ...)` — wrap an existing PTY
- `render(tw, area, buf)`
- `handle_key!(tw, evt)`, `handle_mouse!(tw, evt)`
- `drain!(tw)` — process pending output, returns `true` if changed
- `set_wake!(tw, notify)` — register wake callback
- `close!(tw)` — kill process and clean up

### REPLWidget

- `REPLWidget(; rows, cols, show_scrollbar, focused, scrollback_limit, on_exit)`
- `render(rw, area, buf)`
- `handle_key!(rw, evt)`, `handle_mouse!(rw, evt)`
- `drain!(rw)` — process output + detect REPL exit
- `route_output!(rw, text)` — inject captured stdout/stderr
- `close!(rw)` — shut down REPL and PTY

### PTY

- `pty_spawn(cmd; rows, cols, env)` — spawn process in PTY
- `pty_pair(; rows, cols)` — create PTY pair without subprocess
- `pty_write(pty, data)` — write bytes to master
- `pty_resize!(pty, rows, cols)` — resize terminal
- `pty_alive(pty)` — check if process is running
- `pty_close!(pty)` — close and clean up
