# Scripting App Interactions

`EventScript` lets you write scripted input sequences for headless app recordings. Instead of calculating frame numbers by hand, you describe events in terms of time relative to what came before.

## The Sequential Model

Every delay in an `EventScript` is relative to the previous event — there are no absolute timestamps. Events always fire in the order they appear, which makes the script easy to read top-to-bottom:

<!-- tachi:noeval -->
```julia
APP_EVENTS["my_app"] = EventScript(
    (1.0, key('r')),       # fire 1s from start
    rep(key('r'), 3),       # 3 more rolls, each 1s later  → t=2, 3, 4
    (1.0, key('b')),        # bank 1s after the last roll  → t=5
    pause(2.0),             # wait 2s with no event        → cursor at t=7
    seq(key(:down), key(:up)),  # two nav events, 1s apart → t=8, 9
)
```

The `EventScript` is called with `fps` at render time to produce frame-indexed events:

<!-- tachi:noeval -->
```julia
es = EventScript((1.0, key('r')), rep(key('r'), 2))
es(30)   # → [(30, KeyEvent('r')), (60, KeyEvent('r')), (90, KeyEvent('r'))]
```

## Helpers

### `key`

Shorthand `KeyEvent` constructor:

<!-- tachi:noeval -->
```julia
key('r')       # KeyEvent for character 'r'
key(:enter)    # KeyEvent for the Enter key
key(:tab)      # KeyEvent for Tab
key(:escape)   # KeyEvent for Escape
```

Any symbol accepted by `KeyEvent` works: `:up`, `:down`, `:left`, `:right`, `:backspace`, `:tab`, `:backtab`, `:enter`, `:escape`, `:home`, `:end_key`, `:page_up`, `:page_down`, etc.

### `seq`

A sequence of events, each fired `gap` seconds after the previous:

<!-- tachi:noeval -->
```julia
# Navigate a menu then confirm — 1s between each step
seq(key(:down), key(:down), key(:enter))

# Faster navigation
seq(key(:down), key(:down), key(:up); gap=0.5)
```

The first event in `seq` fires `gap` seconds after whatever preceded it in the `EventScript`.

### `rep`

Repeat one event `n` times, each `gap` seconds apart:

<!-- tachi:noeval -->
```julia
rep(key('s'), 3)              # press 's' three times, 1s apart
rep(key(:down), 5; gap=0.4)   # rapid navigation
rep(key(:tab), 4; gap=2.0)    # slow focus cycling
```

### `chars`

Expand a string into per-character `KeyEvent`s, `pace` seconds apart:

<!-- tachi:noeval -->
```julia
chars("Alice")               # type "Alice" at 0.08s per character
chars("Hello"; pace=0.15)    # slower typing
```

`chars` is typically used after a `pause` or navigation to position focus first:

<!-- tachi:noeval -->
```julia
EventScript(
    (1.0, key(:tab)),        # focus the name field
    chars("Alice"),           # type the name
    (0.5, key(:tab)),         # move to next field
    chars("alice@example.com"),
)
```

### `pause`

Advance the timeline cursor without firing any event:

<!-- tachi:noeval -->
```julia
EventScript(
    rep(key('s'), 3),         # trigger 3 tasks
    pause(5.0),               # wait for them to finish
    (0.0, key(:enter)),       # confirm result
)
```

## Passing Scripts to `record_app`

Set the `events` keyword on `record_app` to drive a scripted recording:

<!-- tachi:noeval -->
```julia
script = EventScript(
    (1.0, key(:down)),
    rep(key(:down), 3),
    (1.0, key(:enter)),
)

record_app(MyApp(), "demo.tach"; width=80, height=24, frames=120, fps=15,
           events=script(15))
```

Or register in `APP_EVENTS` for use with the docs asset pipeline:

<!-- tachi:noeval -->
```julia
APP_EVENTS["my_app"] = EventScript(
    (1.0, key(:down)),
    rep(key(:down), 3),
    (1.0, key(:enter)),
)
```

## Mixing Raw Tuples

You can mix `EventScript` helpers with plain `(delay, event)` tuples for one-off events at specific delays:

<!-- tachi:noeval -->
```julia
EventScript(
    (2.0, key(:down)),                           # first nav after 2s
    seq(key(:down), key(:down), key(:enter)),     # continue sequence
    (2.0, key(:escape)),                          # dismiss after a gap
)
```

## Reference

| Function | Returns | Description |
|:---------|:--------|:------------|
| `EventScript(items...)` | `EventScript` | Build a script from tuples and helper vectors |
| `key(c::Char)` | `KeyEvent` | Character key event |
| `key(k::Symbol)` | `KeyEvent` | Named key event |
| `seq(evts...; gap=1.0)` | `Vector` | Evenly-spaced event sequence |
| `rep(evt, n; gap=1.0)` | `Vector` | Repeated event |
| `chars(text; pace=0.08)` | `Vector` | String → per-character key events |
| `pause(t)` | `(t, Wait())` | Advance cursor, no event |
