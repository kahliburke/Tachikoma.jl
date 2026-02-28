# Input & Events

Tachikoma processes keyboard and mouse input through a unified event system. Events are dispatched to your `update!` method, where you pattern-match to handle them.

## KeyEvent

`KeyEvent` represents a keyboard input:

<!-- tachi:noeval -->
```julia
struct KeyEvent <: Event
    key::Symbol      # :char, :up, :down, :left, :right, :enter, :escape, :tab, :ctrl, ...
    char::Char       # the actual character (meaningful for :char and :ctrl)
    action::KeyAction  # key_press, key_repeat, or key_release
end
```

The `action` field defaults to `key_press` — existing code that constructs `KeyEvent(:up)` or `KeyEvent('a')` continues to work unchanged.

### Key Symbols

| Symbol | Keys |
|:-------|:-----|
| `:char` | Regular character — check `evt.char` |
| `:ctrl` | Ctrl+key — check `evt.char` (e.g., `'a'` for Ctrl+A) |
| `:enter` | Enter/Return |
| `:escape` | Escape |
| `:tab` | Tab |
| `:backtab` | Shift+Tab |
| `:backspace` | Backspace |
| `:delete` | Delete |
| `:up` `:down` `:left` `:right` | Arrow keys |
| `:home` `:end` | Home/End |
| `:pageup` `:pagedown` | Page Up/Down |
| `:insert` | Insert |
| `:ctrl_c` | Ctrl+C (handled by framework for quit) |

### Handling Key Events

<!-- tachi:noeval -->
```julia
function update!(m::MyApp, evt::KeyEvent)
    if evt.key == :char
        if evt.char == 'q'
            m.quit = true
        elseif evt.char == '+'
            m.count += 1
        end
    elseif evt.key == :up
        m.selected -= 1
    elseif evt.key == :down
        m.selected += 1
    elseif evt.key == :enter
        do_action!(m)
    elseif evt.key == :escape
        m.quit = true
    end
end
```

!!! tip
    For complex event handlers, [Match.jl](match.md) can replace `if`/`elseif` chains with declarative pattern matching — merging equivalent keys, adding guard clauses, and flattening nested dispatch.

### Ctrl Key Combinations

Ctrl keys arrive as `:ctrl` with the character:

<!-- tachi:noeval -->
```julia
function update!(m::MyApp, evt::KeyEvent)
    if evt.key == :ctrl
        if evt.char == 'r'        # Ctrl+R
            reset!(m)
        elseif evt.char == 'f'    # Ctrl+F
            search!(m)
        end
    end
end
```

!!! note
    Ctrl+C, Ctrl+G, Ctrl+\\, Ctrl+A, Ctrl+S, Ctrl+?, and Ctrl+Y are consumed by the framework's default bindings. Disable with `app(m; default_bindings=false)` to reclaim them.

## MouseEvent

`MouseEvent` represents mouse input (click, drag, scroll, move):

<!-- tachi:noeval -->
```julia
struct MouseEvent <: Event
    x::Int               # 1-based column
    y::Int               # 1-based row
    button::MouseButton  # mouse_left, mouse_right, mouse_scroll_up, ...
    action::MouseAction  # mouse_press, mouse_release, mouse_drag, mouse_move
    shift::Bool
    alt::Bool
    ctrl::Bool
end
```

### Mouse Buttons

```julia
mouse_left, mouse_middle, mouse_right, mouse_none
mouse_scroll_up, mouse_scroll_down
```

### Mouse Actions

```julia
mouse_press, mouse_release, mouse_drag, mouse_move
```

### Handling Mouse Events

Add a method for `MouseEvent` to your `update!`:

<!-- tachi:noeval -->
```julia
function update!(m::MyApp, evt::MouseEvent)
    if evt.action == mouse_press && evt.button == mouse_left
        # Click at (evt.x, evt.y)
        handle_click!(m, evt.x, evt.y)
    elseif evt.button == mouse_scroll_up
        m.scroll_offset = max(0, m.scroll_offset - 3)
    elseif evt.button == mouse_scroll_down
        m.scroll_offset += 3
    end
end
```

### Hit Testing

Check if a mouse event falls within a `Rect`:

<!-- tachi:noeval -->
```julia
if evt.x >= area.x && evt.x <= right(area) &&
   evt.y >= area.y && evt.y <= bottom(area)
    # Mouse is inside area
end
```

For `SelectableList`, use the built-in helper:

<!-- tachi:noeval -->
```julia
idx = list_hit(list, evt.x, evt.y, area)
idx !== nothing && (list.selected = idx)
```

## Widget-Level Input

Many widgets handle their own input through `handle_key!` and `handle_mouse!`:

<!-- tachi:noeval -->
```julia
# Returns true if the event was consumed
handle_key!(widget, evt::KeyEvent) → Bool
handle_mouse!(widget, evt::MouseEvent, area::Rect) → Bool
```

### FocusRing

`FocusRing` manages Tab/Shift-Tab navigation between focusable panes or widgets:

<!-- tachi:app focusring_demo w=50 h=14 frames=120 fps=15 -->

```julia
using Tachikoma
@tachikoma_app

@kwdef mutable struct FocusRingDemo <: Model
    quit::Bool = false
    tick::Int = 0
    ring::FocusRing = FocusRing([:editor, :log, :preview])
end

should_quit(m::FocusRingDemo) = m.quit

function update!(m::FocusRingDemo, evt::KeyEvent)
    if evt.key == :tab
        next!(m.ring)
    elseif evt.key == :backtab
        prev!(m.ring)
    elseif evt.key == :escape
        m.quit = true
    end
end

function view(m::FocusRingDemo, f::Frame)
    m.tick += 1
    buf = f.buffer
    focused = current(m.ring)

    rows = split_layout(Layout(Vertical, [Fill(), Fill()]), f.area)
    top_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[1])
    pane_areas = [top_cols[1], top_cols[2], rows[2]]
    pane_names = [" editor ", " preview ", " log "]
    pane_syms = [:editor, :preview, :log]
    pane_content = [
        ["function greet(name)", "    println(\"Hello, \$name!\")", "end"],
        ["Output:", "", "Hello, World!"],
        ["[info] compiled greet()", "[info] running...", "[info] done (0.02s)"],
    ]

    for (i, (pa, nm, sym)) in enumerate(zip(pane_areas, pane_names, pane_syms))
        is_focused = (sym == focused)
        bs = is_focused ? tstyle(:accent, bold=true) : tstyle(:border)
        ts = is_focused ? tstyle(:accent, bold=true) : tstyle(:text_dim)
        indicator = is_focused ? " ●" : ""
        inner = render(Block(title=nm * indicator, border_style=bs, title_style=ts), pa, buf)
        for (j, line) in enumerate(pane_content[i])
            j > inner.height && break
            s = is_focused ? tstyle(:text) : tstyle(:text_dim)
            set_string!(buf, inner.x, inner.y + j - 1, line, s)
        end
    end
end

app(FocusRingDemo())
```

Use it with panes (symbols, indices) for panel-level navigation, or with widget objects for form-level focus:

<!-- tachi:noeval -->
```julia
# Pane-level: track which pane is active
ring = FocusRing([:editor, :log, :preview])
focused_pane = current(ring)  # → :editor

# Widget-level: auto-forward keys to focused widget
ring = FocusRing([text_input, dropdown, checkbox])
handle_key!(ring, evt)  # Tab cycles, other keys go to focused widget
```

<!-- tachi:noeval -->
```julia
current(ring)        # get the currently focused item
next!(ring)          # move focus forward
prev!(ring)          # move focus backward
```

For widgets, `handle_key!` forwards non-Tab keys to the focused widget via `update!`. For panes, use `current(ring)` to check which pane should receive input and render with a highlighted border.

## Mouse Mode

Mouse input is enabled by default. Toggle with:

- **Ctrl+G** — Toggle mouse mode at runtime
- `toggle_mouse!(terminal)` — Programmatic toggle

When mouse mode is off, the terminal's native text selection works instead.

### Mouse Draw Example

A minimal drawing app showing `MouseEvent` handling — drag to paint cells:

<!-- tachi:app mouse_draw_demo w=50 h=18 frames=120 fps=15 -->

```julia
using Tachikoma
@tachikoma_app

@kwdef mutable struct MouseDraw <: Model
    quit::Bool = false
    tick::Int = 0
    canvas::Matrix{Bool} = zeros(Bool, 18, 50)
    last_pos::Tuple{Int,Int} = (0, 0)
end

should_quit(m::MouseDraw) = m.quit

function update!(m::MouseDraw, evt::KeyEvent)
    evt.key == :escape && (m.quit = true)
    evt.key == :char && evt.char == 'c' && fill!(m.canvas, false)
end

function update!(m::MouseDraw, evt::MouseEvent)
    if evt.action == mouse_press || evt.action == mouse_drag
        if evt.button == mouse_left
            r, c = evt.y, evt.x
            if 1 <= r <= size(m.canvas, 1) && 1 <= c <= size(m.canvas, 2)
                m.canvas[r, c] = true
            end
        end
    end
end

function view(m::MouseDraw, f::Frame)
    m.tick += 1
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), f.area)
    canvas_area = rows[1]

    for r in 1:min(size(m.canvas, 1), canvas_area.height)
        for c in 1:min(size(m.canvas, 2), canvas_area.width)
            if m.canvas[r, c]
                set_char!(buf, canvas_area.x + c - 1, canvas_area.y + r - 1,
                    '█', tstyle(:accent))
            end
        end
    end

    count = sum(m.canvas)
    render(StatusBar(
        left=[Span("  drag to draw  [c]clear  [Esc]quit ", tstyle(:text_dim))],
        right=[Span(" $(count) cells ", count > 0 ? tstyle(:accent) : tstyle(:text_dim))],
    ), rows[2], buf)
end

app(MouseDraw())
```

## Kitty Keyboard Protocol

Tachikoma automatically detects and enables the [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/) on supported terminals. This provides:

- **Disambiguated keycodes** — Every key produces a unique CSI u escape sequence, eliminating ambiguity between Escape and Alt+key, or between function keys and other sequences.
- **Press / repeat / release events** — Each key action is reported separately, enabling hold-to-move, simultaneous key tracking, and proper key-up handling.
- **All keys as escape codes** — Even simple characters like `a` and `Space` arrive as CSI u sequences with full modifier information.

### Supported Terminals

| Terminal | Kitty Protocol |
|:---------|:---------------|
| Kitty | Full support (native) |
| iTerm2 | Supported (enable "Apps can change how keys are reported") |
| Ghostty | Full support |
| WezTerm | Full support |
| foot | Full support |
| Alacritty | Full support |
| Apple Terminal | Not supported (legacy fallback) |

### Detection and Lifecycle

Protocol detection happens automatically in `app()` during TUI startup:

1. Tachikoma sends a Kitty keyboard query (`CSI ? u`) to the terminal
2. If the terminal responds with its current flags, Kitty mode is enabled with flags for disambiguate + event types + all-keys-as-escapes
3. On TUI exit, the protocol is cleanly disabled before restoring the terminal

No configuration is needed. On terminals that don't support the protocol, Tachikoma falls back to legacy byte-based parsing with no behavioral change.

You can check whether Kitty mode is active via `init!`:

<!-- tachi:noeval -->
```julia
function Tachikoma.init!(m::MyModel, t::Tachikoma.Terminal)
    m.kitty_active = t.kitty_keyboard
end
```

### KeyAction

The `KeyAction` enum represents the type of key event:

<!-- tachi:noeval -->
```julia
@enum KeyAction key_press key_repeat key_release
```

| Action | Meaning |
|:-------|:--------|
| `key_press` | Key was pressed down |
| `key_repeat` | Key is being held (auto-repeat) |
| `key_release` | Key was released |

### Filtering: Press-Only by Default

By default, `update!` only receives `key_press` events. This preserves backward compatibility — existing apps work unchanged whether or not the Kitty protocol is active.

Apps that need repeat and release events (games, hold-to-scroll, simultaneous key tracking) opt in by overriding `handle_all_key_actions`:

<!-- tachi:noeval -->
```julia
Tachikoma.handle_all_key_actions(::MyGameModel) = true
```

With this enabled, your `update!` receives all three action types:

<!-- tachi:noeval -->
```julia
function Tachikoma.update!(m::MyGame, evt::KeyEvent)
    if evt.key == :up
        if evt.action == key_press
            m.moving_up = true
        elseif evt.action == key_release
            m.moving_up = false
        end
    end
end
```

### Key State Tracking

On terminals with full Kitty support (like Kitty itself), repeat and release events are reported natively. On terminals that send repeats as raw bytes (like iTerm2), Tachikoma infers repeats automatically by tracking which keys are currently held — if a press arrives for a key that hasn't been released, it's reclassified as `key_repeat`.

This means `handle_all_key_actions` works consistently across terminals, though release events are only available on terminals with full protocol support.

### Legacy Fallback

On terminals without Kitty support (e.g., Apple Terminal):

- All events arrive as `key_press` (the default)
- `handle_all_key_actions` still works but only produces press and inferred repeat — no release events
- All existing key symbols (`:up`, `:ctrl`, `:escape`, etc.) work identically
