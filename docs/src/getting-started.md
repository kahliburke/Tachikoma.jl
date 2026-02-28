# Getting Started

This guide walks through building your first Tachikoma app — a push-your-luck dice game called **Pig**. The rules: roll a die as many times as you like, accumulating points each turn — but roll a 1 and you lose everything you risked. Bank before you bust to keep your points.

Every Tachikoma app follows the same three steps:

1. **Define a Model** — a mutable struct holding all application state
2. **Implement `update!`** — react to keyboard and mouse events
3. **Implement `view`** — render the UI each frame

## Step 1: The Model

Your model is a `mutable struct` that subtypes `Model`. It holds all application state — the framework never mutates it directly.

```julia
using Tachikoma
@tachikoma_app
using Match

@kwdef mutable struct PigGame <: Model
    quit::Bool = false
    tick::Int = 0
    score::Int = 0              # banked score
    turn_total::Int = 0         # points at risk this turn
    rolls::Vector{Int} = Int[]  # dice rolls this turn
    turns::Vector{Int} = Int[]  # completed turn results (0 = bust)
    busted::Bool = false        # true after rolling a 1
end

should_quit(m::PigGame) = m.quit
```

`@kwdef` generates a keyword constructor with defaults. `should_quit` tells the framework when to exit — return `true` and the event loop stops cleanly.

## Step 2: Game Logic

Business logic lives in plain Julia functions that mutate the model. Keeping it separate from event handling and rendering makes each part easy to reason about:

```julia
function roll!(m::PigGame)
    m.busted = false
    face = rand(1:6)
    push!(m.rolls, face)
    if face == 1
        m.busted = true
        push!(m.turns, 0)  # record bust
        m.turn_total = 0
    else
        m.turn_total += face
    end
end

function bank!(m::PigGame)
    isempty(m.rolls) && return  # nothing to bank
    push!(m.turns, m.turn_total)
    m.score += m.turn_total
    m.turn_total = 0
    empty!(m.rolls)
    m.busted = false
end
```

## Step 3: Handling Events

`update!` is called for every input event. Use `@match` from [Match.jl](https://github.com/JuliaServices/Match.jl) to pattern-match on `(evt.key, evt.char)` pairs:

```julia
function update!(m::PigGame, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 'r') || (:enter, _)  => roll!(m)
        (:char, 'b') || (:char, ' ') => bank!(m)
        _                             => nothing
    end
end
```

`evt.key` is a Symbol (`:char`, `:enter`, `:escape`, `:up`, `:down`, …). For `:char` events, `evt.char` holds the character; for all others it is `'\0'`.

## Step 4: Rendering

`view` is called every frame. It receives a `Frame` (containing a `Buffer` and the terminal area) and draws the full UI.

### Helpers

A few rendering helpers — ASCII die art and a color function based on face value:

```julia
const DIE_ART = Dict(
    1 => ["┌─────┐","│     │","│  ●  │","│     │","└─────┘"],
    2 => ["┌─────┐","│    ●│","│     │","│●    │","└─────┘"],
    3 => ["┌─────┐","│    ●│","│  ●  │","│●    │","└─────┘"],
    4 => ["┌─────┐","│●   ●│","│     │","│●   ●│","└─────┘"],
    5 => ["┌─────┐","│●   ●│","│  ●  │","│●   ●│","└─────┘"],
    6 => ["┌─────┐","│●   ●│","│●   ●│","│●   ●│","└─────┘"],
)

function die_color(face::Int)
    face <= 2 && return tstyle(:accent)
    face <= 4 && return tstyle(:primary, bold=true)
    return tstyle(:success, bold=true)
end
```

`tstyle` creates a `Style` from a named theme slot (`:border`, `:primary`, `:accent`, `:error`, …). The active theme controls the actual colors.

### Layout

Start by drawing the outer border and dividing the inner area into rows:

```julia
function view(m::PigGame, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Border color reflects game state
    border_style = m.busted ? tstyle(:error) :
                   m.turn_total > 20 ? tstyle(:warning) :
                   tstyle(:border)
    inner = render(Block(title="Pig", border_style=border_style), f.area, buf)

    rows = split_layout(
        Layout(Vertical, [Fixed(1), Fixed(1), Fixed(5), Fixed(1), Fill()]),
        inner)
    length(rows) < 5 && return
```

`render(Block(...), area, buf)` draws the border and returns the usable inner `Rect`. `split_layout` divides that rect according to size constraints: `Fixed(n)` claims exactly n rows, `Fill()` takes what remains.

### Scores and progress

```julia
    # Row 1: score labels
    total = m.score + m.turn_total
    set_string!(buf, rows[1].x, rows[1].y,
        "Score: $(m.score)", tstyle(:primary, bold=true))
    turn_style = m.busted ? tstyle(:error, bold=true) :
                 m.turn_total > 15 ? tstyle(:warning, bold=true) :
                 tstyle(:accent)
    turn_label = m.busted ? "BUST!" : "Turn: $(m.turn_total)"
    set_string!(buf, rows[1].x + rows[1].width ÷ 2, rows[1].y,
        turn_label, turn_style)

    # Row 2: progress gauge toward 100
    gauge_style = total >= 100 ? tstyle(:success) :
                  total >= 60  ? tstyle(:warning) :
                  m.busted     ? tstyle(:error) :
                  tstyle(:primary)
    render(Gauge(clamp(total / 100, 0, 1);
        filled_style=gauge_style,
        empty_style=tstyle(:text_dim, dim=true)), rows[2], buf)
```

`set_string!` writes styled text directly to the buffer at a column/row position. Widgets like `Gauge` are constructed fresh each frame with the current data and passed to `render`.

### Die face and history

```julia
    # Row 3: large die face for the most recent roll
    if !isempty(m.rolls)
        face = m.rolls[end]
        art = DIE_ART[face]
        die_rect = center(rows[3], 7, length(art))
        ds = m.busted ? tstyle(:error, bold=true) : die_color(face)
        for (row, line) in enumerate(art)
            set_string!(buf, die_rect.x, die_rect.y + row - 1, line, ds)
        end
    else
        msg = "Press [r] to roll"
        r = center(rows[3], length(msg), 1)
        set_string!(buf, r.x, r.y, msg, tstyle(:text_dim))
    end

    # Row 4: small unicode dice for previous rolls this turn
    die_faces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅']
    if length(m.rolls) > 1
        hist = @view m.rolls[1:end-1]
        origin = center(rows[4], length(hist) * 2 - 1, 1)
        for (i, r) in enumerate(hist)
            set_char!(buf, origin.x + (i - 1) * 2, origin.y, die_faces[r], die_color(r))
        end
    end

    # Row 5: turn history — banked amounts and busts
    if !isempty(m.turns)
        dx = rows[5].x
        for (i, t) in enumerate(m.turns)
            label = t == 0 ? "✗" : "+$t"
            s = t == 0  ? tstyle(:error) :
                t >= 15 ? tstyle(:success, bold=true) :
                tstyle(:accent)
            set_string!(buf, dx, rows[5].y, label, s)
            dx += length(label) + 1
            dx >= rows[5].x + rows[5].width && break
        end
    end

    # Status bar pinned to the bottom edge of the terminal
    render(StatusBar(
        left=[Span("  [r]oll  ", tstyle(:accent)),
              Span("[b]ank  ", tstyle(:success))],
        right=[Span("[q]uit ", tstyle(:text_dim))],
    ), Rect(f.area.x, bottom(f.area), f.area.width, 1), buf)
end
```

`bottom(area)` returns the last row of a `Rect`. Pinning the status bar to `f.area` (rather than `inner`) lets it sit outside the border.

## Step 5: Launch

```julia
app(PigGame())
```

`app` enters the alternate screen, enables raw mode and mouse input, then runs the event loop at the target frame rate (default 60 fps). Press `q` or `Ctrl+C` to exit.

## Complete Source

Here's the full game — copy it into a file and run with `julia --project game.jl`:

<!-- tachi:app pig_game w=50 h=18 frames=240 fps=15 chrome -->
```julia
using Tachikoma
@tachikoma_app
using Match

# 1. Define your model
@kwdef mutable struct PigGame <: Model
    quit::Bool = false
    tick::Int = 0
    score::Int = 0              # banked score
    turn_total::Int = 0         # points at risk this turn
    rolls::Vector{Int} = Int[]  # dice rolls this turn
    turns::Vector{Int} = Int[]  # completed turn results (0 = bust)
    busted::Bool = false        # true after rolling a 1
end

should_quit(m::PigGame) = m.quit

# Game logic
function roll!(m::PigGame)
    m.busted = false
    face = rand(1:6)
    push!(m.rolls, face)
    if face == 1
        m.busted = true
        push!(m.turns, 0)  # record bust
        m.turn_total = 0
    else
        m.turn_total += face
    end
end

function bank!(m::PigGame)
    isempty(m.rolls) && return  # nothing to bank
    push!(m.turns, m.turn_total)  # record banked amount
    m.score += m.turn_total
    m.turn_total = 0
    empty!(m.rolls)
    m.busted = false
end

# 2. Handle events with pattern matching
function update!(m::PigGame, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 'r') || (:enter, _)  => roll!(m)
        (:char, 'b') || (:char, ' ') => bank!(m)
        _                             => nothing
    end
end

# Hand-drawn 7×5 die face using box-drawing and ● dots
const DIE_ART = Dict(
    1 => ["┌─────┐","│     │","│  ●  │","│     │","└─────┘"],
    2 => ["┌─────┐","│    ●│","│     │","│●    │","└─────┘"],
    3 => ["┌─────┐","│    ●│","│  ●  │","│●    │","└─────┘"],
    4 => ["┌─────┐","│●   ●│","│     │","│●   ●│","└─────┘"],
    5 => ["┌─────┐","│●   ●│","│  ●  │","│●   ●│","└─────┘"],
    6 => ["┌─────┐","│●   ●│","│●   ●│","│●   ●│","└─────┘"],
)

# Color a die value — warm colors for high rolls, cool for low
function die_color(face::Int)
    face <= 2 && return tstyle(:accent)
    face <= 4 && return tstyle(:primary, bold=true)
    return tstyle(:success, bold=true)
end

# 3. Render the UI
function view(m::PigGame, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Outer border — color shifts with game state
    border_style = m.busted ? tstyle(:error) :
                   m.turn_total > 20 ? tstyle(:warning) :
                   tstyle(:border)
    inner = render(Block(title="Pig", border_style=border_style),
        f.area, buf)

    # Layout: scores, gauge, big die, roll history, turn history
    rows = split_layout(
        Layout(Vertical, [Fixed(1), Fixed(1), Fixed(5), Fixed(1), Fill()]),
        inner)
    length(rows) < 5 && return

    # Row 1: Score labels
    total = m.score + m.turn_total
    set_string!(buf, rows[1].x, rows[1].y,
        "Score: $(m.score)", tstyle(:primary, bold=true))
    turn_style = m.busted ? tstyle(:error, bold=true) :
                 m.turn_total > 15 ? tstyle(:warning, bold=true) :
                 tstyle(:accent)
    turn_label = m.busted ? "BUST!" : "Turn: $(m.turn_total)"
    set_string!(buf, rows[1].x + rows[1].width ÷ 2, rows[1].y,
        turn_label, turn_style)

    # Row 2: Progress gauge toward 100
    gauge_style = total >= 100 ? tstyle(:success) :
                  total >= 60  ? tstyle(:warning) :
                  m.busted     ? tstyle(:error) :
                  tstyle(:primary)
    render(Gauge(clamp(total / 100, 0, 1);
        filled_style=gauge_style,
        empty_style=tstyle(:text_dim, dim=true)), rows[2], buf)

    # Row 3: Large die face for the current roll
    if !isempty(m.rolls)
        face = m.rolls[end]
        art = DIE_ART[face]
        die_rect = center(rows[3], 7, length(art))
        ds = m.busted ? tstyle(:error, bold=true) : die_color(face)
        for (row, line) in enumerate(art)
            set_string!(buf, die_rect.x, die_rect.y + row - 1, line, ds)
        end
    else
        msg = "Press [r] to roll"
        r = center(rows[3], length(msg), 1)
        set_string!(buf, r.x, r.y, msg, tstyle(:text_dim))
    end

    # Row 4: Roll history — small die faces for previous rolls
    die_faces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅']
    if length(m.rolls) > 1
        hist = @view m.rolls[1:end-1]
        origin = center(rows[4], length(hist) * 2 - 1, 1)
        for (i, r) in enumerate(hist)
            set_char!(buf, origin.x + (i - 1) * 2, origin.y, die_faces[r], die_color(r))
        end
    end

    # Row 5: Turn history — banked amounts and busts
    if !isempty(m.turns)
        dx = rows[5].x
        for (i, t) in enumerate(m.turns)
            label = t == 0 ? "✗" : "+$t"
            s = t == 0    ? tstyle(:error) :
                t >= 15   ? tstyle(:success, bold=true) :
                tstyle(:accent)
            set_string!(buf, dx, rows[5].y, label, s)
            dx += length(label) + 1
            dx >= rows[5].x + rows[5].width && break
        end
    end

    # Status bar
    render(StatusBar(
        left=[Span("  [r]oll  ", tstyle(:accent)),
              Span("[b]ank  ", tstyle(:success))],
        right=[Span("[q]uit ", tstyle(:text_dim))],
    ), Rect(f.area.x, bottom(f.area), f.area.width, 1), buf)
end

app(PigGame())
```

## Built-in Key Bindings

`app()` includes default bindings (disable with `app(m; default_bindings=false)`):

| Key | Action |
|:----|:-------|
| `Ctrl+C` | Quit (always active) |
| `Ctrl+G` | Toggle mouse mode |
| `Ctrl+\` | Open theme selector |
| `Ctrl+A` | Toggle animations on/off |
| `Ctrl+S` | Open settings overlay |
| `Ctrl+?` | Help overlay |
| `Ctrl+Y` | Copy focused pane to clipboard |

## Next Steps

- [Architecture](architecture.md) — Understand the full Elm lifecycle
- [Layout](layout.md) — Build multi-pane interfaces
- [Widgets](widgets.md) — Explore the complete widget catalog
- [Tutorials](tutorials/form-app.md) — Build real applications step by step
