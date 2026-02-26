# Pattern Matching with Match.jl

[Match.jl](https://github.com/JuliaServices/Match.jl) provides declarative pattern matching that can replace verbose `if`/`elseif` chains in event handlers. It pairs especially well with Tachikoma's `KeyEvent` tuple `(evt.key, evt.char)`.

## Before and After

A typical event handler without Match.jl:

<!-- tachi:noeval -->
```julia
function update!(m::MyModel, evt::KeyEvent)
    if evt.key == :char
        if evt.char == 'q'
            m.quit = true
        elseif evt.char == 'j'
            m.selected += 1
        elseif evt.char == 'k'
            m.selected -= 1
        end
    elseif evt.key == :up
        m.selected -= 1
    elseif evt.key == :down
        m.selected += 1
    elseif evt.key == :enter
        activate!(m)
    elseif evt.key == :escape
        m.quit = true
    end
end
```

With Match.jl:

<!-- tachi:noeval -->
```julia
using Match

function update!(m::MyModel, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:up, _) || (:char, 'k')     => (m.selected -= 1)
        (:down, _) || (:char, 'j')   => (m.selected += 1)
        (:enter, _)                   => activate!(m)
        _                             => nothing
    end
end
```

The match version is flatter, merges equivalent keys with OR patterns, and eliminates the nested `if evt.key == :char` block.

## Core Patterns

### Tuple Destructuring

Match on `(evt.key, evt.char)` to handle both the key type and character in one arm:

<!-- tachi:noeval -->
```julia
@match (evt.key, evt.char) begin
    (:char, 'q') => (m.quit = true)    # specific character
    (:enter, _)  => activate!(m)       # special key (ignore char)
    _            => nothing            # catch-all
end
```

The wildcard `_` ignores values you don't need. For special keys like `:enter`, the char field is irrelevant — `_` makes that explicit.

### OR Patterns

Merge multiple keys that do the same thing:

<!-- tachi:noeval -->
```julia
(:char, 'q') || (:escape, _) => (m.quit = true)
(:up, _) || (:char, 'k')     => scroll_up!(m)
(:down, _) || (:char, 'j')   => scroll_down!(m)
```

This naturally expresses Vim-style `j`/`k` alongside arrow keys without duplicate code.

### Guard Clauses

Use `where` to add conditions to a match arm:

<!-- tachi:noeval -->
```julia
(:char, c) where '1' <= c <= '5' => (m.level = Int(c) - Int('0'))
(:char, c) where '1' <= c <= '9' => begin
    col = Int(c) - Int('0')
    col <= length(dt.columns) && sort_by!(dt, col)
end
```

Guards replace range-checking boilerplate. The captured variable `c` is available in both the guard and the body.

### Block Bodies

When an arm needs multiple statements, use `begin ... end`:

<!-- tachi:noeval -->
```julia
(:char, 'm') => begin
    idx = findfirst(==(m.mode), MODES)
    m.mode = MODES[mod1(idx + 1, length(MODES))]
    m.mode == :scatter && regenerate!(m)
end
```

## Value-Returning Match

`@match` is an expression — use it on the right side of assignment or as a return value:

<!-- tachi:noeval -->
```julia
function update!(m::MyModel, evt::KeyEvent)
    evt.key == :escape && (m.quit = true; return)

    # Mode switching returns true if handled
    handled = @match evt.key begin
        :f1 => (m.mode = 1; true)
        :f2 => (m.mode = 2; true)
        :f3 => (m.mode = 3; true)
        _   => false
    end
    handled && return

    # Delegate to mode-specific handler
    @match m.mode begin
        1 => handle_mode1!(m, evt)
        2 => handle_mode2!(m, evt)
        _ => handle_mode3!(m, evt)
    end
end
```

This pattern cleanly separates global key handling from mode-specific dispatch.

## State and Mode Dispatch

Match on model state — not just events — to simplify view rendering:

<!-- tachi:noeval -->
```julia
function view(m::MyModel, f::Frame)
    # ...
    @match m.tab begin
        1 => view_overview(m, area, buf)
        2 => view_details(m, area, buf)
        _ => view_settings(m, area, buf)
    end

    footer = @match m.tab begin
        1 => "  [↑↓]navigate [Enter]select "
        2 => "  [←→]scroll [d]detail "
        _ => "  [1-4]preset [Enter]apply "
    end
    render(StatusBar(left=[Span(footer, tstyle(:text_dim))]), footer_area, buf)
end
```

### Enum-Style Matching

For symbol or enum values, match directly:

<!-- tachi:noeval -->
```julia
@match m.mode begin
    :dual    => render_dual(m)
    :scatter => render_scatter(m)
    _        => render_live(m)
end
```

## Modal Handlers

Match simplifies modal UIs where behavior depends on internal state:

<!-- tachi:noeval -->
```julia
function update!(m::MyModel, evt::KeyEvent)
    # Modal consumes all keys when open
    if m.show_modal
        @match evt.key begin
            :escape      => (m.show_modal = false)
            :enter       => confirm!(m)
            :up          => (m.modal_idx -= 1)
            :down || :tab => (m.modal_idx += 1)
            _            => nothing
        end
        return
    end

    # Normal key handling
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 'f')                 => (m.show_modal = true)
        _                            => nothing
    end
end
```

## Delegation with Catch-All

Use the `_` catch-all to delegate unhandled keys to a widget:

<!-- tachi:noeval -->
```julia
@match (evt.key, evt.char) begin
    (:char, 'q') || (:escape, _) => (m.quit = true)
    (:char, 'm')                 => toggle_mode!(m)
    _                            => handle_key!(m.widget, evt)
end
```

The widget only sees keys that the match didn't consume.

## Setup

Add Match.jl to your project:

```julia
using Pkg
Pkg.add("Match")
```

Then import it in your module:

```julia
using Match
```

The `@match` macro is the only export you'll use.
