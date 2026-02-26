# Testing

Tachikoma provides a virtual terminal (`TestBackend`) for headless widget testing. You can render widgets, inspect the output, and simulate keyboard input — all without a real terminal.

## TestBackend

`TestBackend` creates a virtual terminal buffer of a given size:

<!-- tachi:noeval -->
```julia
using Test, Tachikoma
const T = Tachikoma

tb = T.TestBackend(80, 24)  # 80 columns × 24 rows
```

### Rendering Widgets

`render_widget!` renders any widget into the test backend:

<!-- tachi:noeval -->
```julia
p = T.Paragraph("Hello, world!")
T.render_widget!(tb, p)
```

You can specify a custom rendering area:

<!-- tachi:noeval -->
```julia
T.render_widget!(tb, p; rect=T.Rect(1, 1, 40, 10))
```

### Inspecting Output

Four functions let you examine what was rendered:

<!-- tachi:noeval -->
```julia
# Get character at position (1-based x, y)
T.char_at(tb, 1, 1)       # → 'H'
T.char_at(tb, 99, 99)     # → ' '  (out of bounds returns space)

# Get entire row as a string
T.row_text(tb, 1)          # → "Hello, world!            ..."

# Search for text anywhere on screen
T.find_text(tb, "world")   # → (x=8, y=1)  or nothing

# Get style (color, bold, etc.) at position
T.style_at(tb, 1, 1)       # → Style(fg=..., bold=true, ...)
```

### Complete Rendering Test

<!-- tachi:noeval -->
```julia
@testset "Paragraph renders content" begin
    tb = T.TestBackend(30, 5)
    T.render_widget!(tb, T.Paragraph("hello world"))

    @test T.char_at(tb, 1, 1) == 'h'
    @test T.char_at(tb, 7, 1) == 'w'
    @test occursin("hello world", T.row_text(tb, 1))
end
```

## Testing Styles

Verify that widgets apply correct styling:

<!-- tachi:noeval -->
```julia
@testset "Red text has correct foreground" begin
    tb = T.TestBackend(20, 1)
    style = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
    T.render_widget!(tb, T.Paragraph([T.Span("red", style)]))

    @test T.style_at(tb, 1, 1).fg == T.ColorRGB(0xff, 0x00, 0x00)
end

@testset "Bold heading" begin
    tb = T.TestBackend(40, 3)
    T.render_widget!(tb, T.Paragraph([T.Span("Title", T.Style(bold=true))]))

    @test T.style_at(tb, 1, 1).bold == true
end
```

## Simulating Key Events

### KeyEvent Constructors

Create key events to send to widgets:

<!-- tachi:noeval -->
```julia
# Character keys
T.KeyEvent('a')            # letter a
T.KeyEvent('!')            # exclamation mark

# Special keys
T.KeyEvent(:enter)         # Enter/Return
T.KeyEvent(:escape)        # Escape
T.KeyEvent(:backspace)     # Backspace
T.KeyEvent(:tab)           # Tab
T.KeyEvent(:up)            # Up arrow
T.KeyEvent(:down)          # Down arrow
T.KeyEvent(:left)          # Left arrow
T.KeyEvent(:right)         # Right arrow
T.KeyEvent(:home)          # Home
T.KeyEvent(:end_key)       # End
T.KeyEvent(:pageup)        # Page Up
T.KeyEvent(:pagedown)      # Page Down
T.KeyEvent(:delete)        # Delete

# Control keys
T.KeyEvent(:ctrl, 'a')    # Ctrl+A
T.KeyEvent(:ctrl, 'z')    # Ctrl+Z
```

### Sending Events to Widgets

All interactive widgets implement `handle_key!`, which returns `true` if the widget consumed the event:

<!-- tachi:noeval -->
```julia
input = T.TextInput(text="hello", focused=true)

@test T.handle_key!(input, T.KeyEvent('!'))       # type '!'
@test T.text(input) == "hello!"

@test T.handle_key!(input, T.KeyEvent(:backspace)) # delete last char
@test T.text(input) == "hello"
```

### Key Sequences

Test multi-step interactions by sending a sequence of events:

<!-- tachi:noeval -->
```julia
@testset "TextInput cursor movement" begin
    input = T.TextInput(text="hello", focused=true)

    T.handle_key!(input, T.KeyEvent(:home))        # move to start
    @test input.cursor == 0

    T.handle_key!(input, T.KeyEvent('X'))           # insert at start
    @test T.text(input) == "Xhello"

    T.handle_key!(input, T.KeyEvent(:end_key))      # move to end
    @test input.cursor == 6
end
```

### Testing Model update!

Test your app's event handling by calling `update!` directly:

<!-- tachi:noeval -->
```julia
@kwdef mutable struct Counter <: T.Model
    quit::Bool = false
    count::Int = 0
end

T.should_quit(m::Counter) = m.quit

function T.update!(m::Counter, evt::T.KeyEvent)
    if evt.key == :char && evt.char == '+'
        m.count += 1
    end
    evt.key == :escape && (m.quit = true)
end

@testset "Counter model" begin
    m = Counter()

    T.update!(m, T.KeyEvent('+'))
    @test m.count == 1

    T.update!(m, T.KeyEvent('+'))
    @test m.count == 2

    T.update!(m, T.KeyEvent(:escape))
    @test m.quit == true
end
```

## Render-After-Interaction Tests

The most useful pattern: send events, then re-render and verify the visual output:

<!-- tachi:noeval -->
```julia
@testset "ScrollPane scrolls on key" begin
    lines = ["line$i" for i in 1:20]
    sp = T.ScrollPane(lines; following=false)

    # Initial render
    tb = T.TestBackend(30, 5)
    T.render_widget!(tb, sp)
    @test T.find_text(tb, "line1") !== nothing

    # Scroll down
    T.handle_key!(sp, T.KeyEvent(:down))

    # Re-render and verify
    T.render_widget!(tb, sp)
    @test T.find_text(tb, "line2") !== nothing
end
```

### Testing Complex Widgets

<!-- tachi:noeval -->
```julia
@testset "CodeEditor auto-indent" begin
    ce = T.CodeEditor(; text="function foo()", focused=true)
    ce.cursor_col = length(ce.lines[1])

    T.handle_key!(ce, T.KeyEvent(:enter))

    @test ce.cursor_row == 2
    @test ce.cursor_col == ce.tab_width  # indented after function
end

@testset "CodeEditor vim mode" begin
    ce = T.CodeEditor(; text="hello", focused=true)
    ce.cursor_row = 1
    ce.cursor_col = 0

    T.handle_key!(ce, T.KeyEvent(:escape))    # enter vim normal mode
    T.handle_key!(ce, T.KeyEvent('x'))         # delete char under cursor

    @test String(ce.lines[1]) == "ello"
end
```

## Testing Widget State

Many widgets expose their state through accessor functions:

<!-- tachi:noeval -->
```julia
# TextInput / TextArea / CodeEditor
T.text(widget)              # current text content
widget.cursor               # cursor position (TextInput)
widget.cursor_row           # cursor row (CodeEditor)
widget.cursor_col           # cursor column (CodeEditor)

# SelectableList / DataTable
T.value(widget)             # selected index
widget.selected             # same as value() for lists

# DropDown
T.value(widget)             # selected value
T.is_open(widget)           # whether dropdown is expanded

# ScrollPane
widget.offset               # scroll offset
widget.following             # auto-follow mode

# MarkdownPane
widget.source               # raw markdown text
widget.last_width            # width used for last parse
```

## Testing Layouts

Verify that layout constraints produce the expected areas:

<!-- tachi:noeval -->
```julia
@testset "Horizontal split" begin
    area = T.Rect(1, 1, 80, 24)
    cols = T.split_layout(T.Layout(T.Horizontal, [T.Fixed(20), T.Fill()]), area)

    @test length(cols) == 2
    @test cols[1].width == 20
    @test cols[2].width == 60
    @test cols[2].x == 21
end
```

## Testing with Blocks and Borders

When testing widgets inside `Block` containers, account for the border consuming 2 rows and 2 columns:

<!-- tachi:noeval -->
```julia
@testset "Widget inside block" begin
    tb = T.TestBackend(40, 10)
    block = T.Block(title="Panel")
    inner = T.render(block, T.Rect(1, 1, 40, 10), tb.buf)

    # inner is the area inside the border
    @test inner.x == 2
    @test inner.y == 2
    @test inner.width == 38
    @test inner.height == 8
end
```

## Property-Based Testing with Supposition.jl

For exhaustive testing of edge cases (empty strings, zero-width areas, extreme values), consider [Supposition.jl](https://github.com/Seelengrab/Supposition.jl) for property-based testing:

```julia
using Supposition

@testset "Paragraph never crashes" begin
    @check function paragraph_any_string(text=Data.Text(Data.Characters(); max_len=200))
        tb = T.TestBackend(40, 5)
        T.render_widget!(tb, T.Paragraph(text))
        true  # no exception = pass
    end
end

@testset "Layout sum equals total" begin
    @check function layout_widths(
        w=Data.Integers(1, 200),
        split=Data.Integers(1, 100)
    )
        area = T.Rect(1, 1, w, 10)
        cols = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(min(split, w)), T.Fill()]),
            area
        )
        total = sum(c.width for c in cols)
        total == w
    end
end
```

Property-based testing is especially valuable for:

- Layout constraint solvers (do widths always sum correctly?)
- Word wrapping (are all words preserved? no infinite loops?)
- Unicode handling (do multi-byte characters render correctly?)
- Boundary conditions (zero-width areas, empty content, huge inputs)

## Organizing Tests

Follow Tachikoma's own test structure — one file per component:

```
test/
├── runtests.jl          # includes all test files
├── test_core.jl         # TextInput, Buffer, Rect, etc.
├── test_layout.jl       # layout algorithms
├── test_widgets.jl      # widget rendering
├── test_events.jl       # event handling
└── test_mywidget.jl     # your custom widget
```

In `runtests.jl`:

<!-- tachi:noeval -->
```julia
using Test
using Tachikoma
const T = Tachikoma

@testset "My App" begin
    include("test_core.jl")
    include("test_widgets.jl")
    include("test_events.jl")
end
```

## Tips

- **Re-render after events**: Widgets update internal state on `handle_key!` but the visual output only changes after `render`. Always call `render_widget!` again before asserting on `char_at`/`row_text`.
- **Set `focused=true`**: Interactive widgets like `TextInput` and `CodeEditor` ignore key events when not focused.
- **Use `find_text` for loose assertions**: It searches the entire screen, so you don't need to know exact coordinates.
- **Check return values**: `handle_key!` returns `true` if consumed. Use this to test event delegation — e.g., verify that a `FocusRing` forwards unhandled keys.
