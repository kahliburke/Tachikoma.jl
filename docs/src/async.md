# Async Tasks

Tachikoma's async task system runs background work in separate threads while preserving the single-threaded Elm architecture. Results flow back through the normal event system as `TaskEvent`s, so your `update!` stays the only place state changes happen.

## Architecture

<!-- tachi:widget async_arch w=52 h=14
top = Rect(area.x, area.y, area.width, 7)
inner = render(Block(title="Main Thread (app loop @ fps)", title_style=tstyle(:title, bold=true)), top, buf)
set_string!(buf, inner.x + 1, inner.y, "poll_event() → update!(model, event)", tstyle(:text))
set_string!(buf, inner.x + 5, inner.y + 1, "│", tstyle(:border))
set_string!(buf, inner.x + 1, inner.y + 2, "drain_tasks!() → update!(TaskEvent)", tstyle(:text))
set_string!(buf, inner.x + 5, inner.y + 3, "│", tstyle(:border))
set_string!(buf, inner.x + 1, inner.y + 4, "view(model, frame) → render", tstyle(:text))
set_string!(buf, area.x + 8, area.y + 7, "▲ TaskEvent(:id, result)", tstyle(:accent))
set_string!(buf, area.x + 8, area.y + 8, "│", tstyle(:accent))
bot = Rect(area.x, area.y + 9, area.width, 5)
ib = render(Block(title="Background Threads", title_style=tstyle(:title, bold=true)), bot, buf)
set_string!(buf, ib.x + 1, ib.y, "spawn_task!(queue, :id) do", tstyle(:text))
set_string!(buf, ib.x + 5, ib.y + 1, "expensive_computation()", tstyle(:text_dim))
set_string!(buf, ib.x + 1, ib.y + 2, "end", tstyle(:text))
-->

Background threads send results into a `Channel`. The app loop drains the channel every frame (non-blocking) and dispatches each result as a `TaskEvent` to your `update!` — just like keyboard and mouse events.

## Setting Up

### 1. Add a TaskQueue to Your Model

```julia
@kwdef mutable struct MyModel <: Model
    quit::Bool = false
    tick::Int = 0
    tq::TaskQueue = TaskQueue()
    results::Vector{String} = String[]
end
```

### 2. Tell the Framework About It

Override `task_queue` so the app loop knows to drain your queue:

```julia
task_queue(m::MyModel) = m.tq
```

Without this, task results will accumulate in the channel but never reach `update!`.

## Spawning Tasks

### spawn_task!

Run a function in a background thread:

<!-- tachi:noeval -->
```julia
spawn_task!(m.tq, :compute) do
    sleep(2.0)  # simulate work
    sum(1:1_000_000)
end
```

- First argument: the `TaskQueue`
- Second argument: a `Symbol` id for routing the result
- The closure runs in `Threads.@spawn` and can capture variables
- When the closure returns, its result is sent as `TaskEvent(:compute, result)`
- If the closure throws, the exception is caught and sent as `TaskEvent(:compute, exception)`

### spawn_timer!

Fire events at regular intervals:

<!-- tachi:noeval -->
```julia
token = spawn_timer!(m.tq, :tick, 1.0; repeat=true)
```

- Returns a `CancelToken` for stopping the timer later
- `repeat=false` (default) fires once then stops
- `repeat=true` keeps firing until cancelled
- Each tick sends `TaskEvent(:tick, time())` with the current timestamp

Stop a timer with:

<!-- tachi:noeval -->
```julia
cancel!(token)
```

Check if a timer has been cancelled:

<!-- tachi:noeval -->
```julia
is_cancelled(token)  # → Bool
```

## Handling Results

Task results arrive in `update!` as `TaskEvent`s. Add a method that dispatches on the event's `id`:

```julia
function update!(m::MyModel, evt::TaskEvent)
    if evt.id == :compute
        if evt.value isa Exception
            push!(m.results, "Error: $(evt.value)")
        else
            push!(m.results, "Result: $(evt.value)")
        end
    elseif evt.id == :tick
        m.timer_count += 1
    end
end
```

!!! note
    `TaskEvent` has two fields: `id::Symbol` and `value::T` (generic). The value is whatever your closure returned, or the `Exception` if it threw.

### With Match.jl

Pattern matching works well for routing task results:

<!-- tachi:noeval -->
```julia
function update!(m::MyModel, evt::TaskEvent)
    @match evt.id begin
        :compute => evt.value isa Exception ?
            push!(m.errors, evt.value) :
            push!(m.results, evt.value)
        :tick    => (m.timer_count += 1)
        _        => nothing
    end
end
```

## Active Task Count

`TaskQueue` tracks how many tasks are currently running via an atomic counter. Use this for spinners or status indicators:

```julia
function view(m::MyModel, f::Frame)
    active = m.tq.active[]  # atomic read, lock-free

    if active > 0
        si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
        set_char!(buf, x, y, SPINNER_BRAILLE[si], tstyle(:accent))
        set_string!(buf, x + 2, y, "$active running", tstyle(:accent))
    else
        set_string!(buf, x, y, "idle", tstyle(:text_dim))
    end
end
```

## Complete Example

A minimal app that spawns background computations:

<!-- tachi:app compute_demo w=60 h=14 frames=120 fps=15 realtime -->

```julia
using Tachikoma

@kwdef mutable struct ComputeModel <: Model
    quit::Bool = false
    tick::Int = 0
    tq::TaskQueue = TaskQueue()
    log::Vector{String} = ["Press [s] to spawn a task"]
    task_count::Int = 0
end

should_quit(m::ComputeModel) = m.quit
task_queue(m::ComputeModel) = m.tq

function update!(m::ComputeModel, evt::KeyEvent)
    if evt.key == :char && evt.char == 's'
        m.task_count += 1
        id = m.task_count
        spawn_task!(m.tq, :work) do
            sleep(0.5 + rand() * 2.0)
            "Task #$id: result = $(sum(1:rand(1:1_000_000)))"
        end
        push!(m.log, "Spawned task #$id")
    end
    evt.key == :escape && (m.quit = true)
end

function update!(m::ComputeModel, evt::TaskEvent)
    if evt.id == :work
        if evt.value isa Exception
            push!(m.log, "Failed: $(evt.value)")
        else
            push!(m.log, evt.value)
        end
    end
end

function view(m::ComputeModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), f.area)

    # Log pane
    sp = ScrollPane(m.log; block=Block(title="Log"), following=true)
    render(sp, rows[1], buf)

    # Status bar with active task count
    active = m.tq.active[]
    status = active > 0 ? "$(active) running" : "idle"
    render(StatusBar(
        left=[Span("  [s]spawn [Esc]quit ", tstyle(:text_dim))],
        right=[Span(status * " ", active > 0 ? tstyle(:accent) : tstyle(:text_dim))],
    ), rows[2], buf)
end

app(ComputeModel())
```

## Error Handling

Exceptions in spawned tasks are caught automatically and delivered as the `TaskEvent` value. They are never rethrown — your `update!` is responsible for handling them:

<!-- tachi:noeval -->
```julia
spawn_task!(m.tq, :risky) do
    error("something went wrong")
end

# In update!:
function update!(m::MyModel, evt::TaskEvent)
    if evt.id == :risky && evt.value isa Exception
        push!(m.errors, string(evt.value))
    end
end
```

This prevents background failures from crashing the app while giving you full control over error reporting.

## Thread Safety Notes

- `TaskQueue` internals are thread-safe: `Channel` for message passing, `Threads.Atomic{Int}` for the active counter, `Threads.Atomic{Bool}` for cancel tokens.
- Your closures run on background threads — avoid mutating model state directly. Return results and let `update!` apply them on the main thread.
- Julia requires `julia -t auto` (or `-t N`) to actually run tasks in parallel. With a single thread, tasks still work but run cooperatively during `yield` points (like `sleep`).
