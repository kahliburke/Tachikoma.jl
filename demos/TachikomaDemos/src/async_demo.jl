# ═══════════════════════════════════════════════════════════════════════
# Async demo ── background tasks, timers, and cancellation
#
# Demonstrates the async task system: spawn background work that
# completes without blocking the UI, use repeating timers for
# periodic updates, and cancel running tasks on demand.
#
# Layout:
#   ┌─ Task Launcher ──────────┬─ Timer ──────────────┐
#   │  Spawn tasks, see        │  Repeating timer      │
#   │  results arrive async    │  with cancel           │
#   ├─ Results Log ────────────┴──────────────────────-─┤
#   │  Scrollable list of completed task results         │
#   └───────────────────────────────────────────────────-┘
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct AsyncDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    tq::TaskQueue = TaskQueue()
    # Task spawning
    tasks_spawned::Int = 0
    tasks_completed::Int = 0
    tasks_failed::Int = 0
    # Timer
    timer_token::Union{CancelToken, Nothing} = nothing
    timer_ticks::Int = 0
    timer_running::Bool = false
    # Results log
    log::Vector{String} = String[]
    log_offset::Int = 0
    log_selected::Int = 1
    # Busy spinner
    active_count::Int = 0
end

should_quit(m::AsyncDemoModel) = m.quit
task_queue(m::AsyncDemoModel) = m.tq

function update!(m::AsyncDemoModel, evt::Event)
    if evt isa KeyEvent
        _handle_async_key!(m, evt)
    elseif evt isa TaskEvent
        _handle_async_task_event!(m, evt)
    end
end

function _handle_async_key!(m::AsyncDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 's' && _spawn_compute_task!(m)
        evt.char == 'f' && _spawn_failing_task!(m)
        evt.char == 'b' && _spawn_batch_tasks!(m, 5)
        evt.char == 't' && _toggle_timer!(m)
    elseif evt.key == :escape
        m.quit = true
    elseif evt.key == :up
        m.log_selected = max(1, m.log_selected - 1)
    elseif evt.key == :down
        m.log_selected = min(length(m.log), m.log_selected + 1)
    end
end

function _handle_async_task_event!(m::AsyncDemoModel, evt::TaskEvent)
    if evt.id == :compute
        if evt.value isa Exception
            m.tasks_failed += 1
            push!(m.log, "ERR  $(evt.value)")
        else
            m.tasks_completed += 1
            push!(m.log, "OK   $(evt.value)")
        end
    elseif evt.id == :batch
        if evt.value isa Exception
            m.tasks_failed += 1
            push!(m.log, "ERR  batch: $(evt.value)")
        else
            m.tasks_completed += 1
            push!(m.log, "OK   batch #$(evt.value)")
        end
    elseif evt.id == :tick
        m.timer_ticks += 1
        push!(m.log, "TICK #$(m.timer_ticks) @ $(round(evt.value; digits=1))s")
    end
    m.log_selected = length(m.log)
end

function _spawn_compute_task!(m::AsyncDemoModel)
    m.tasks_spawned += 1
    id = m.tasks_spawned
    spawn_task!(m.tq, :compute) do
        # Simulate variable-duration work
        duration = 0.5 + rand() * 2.0
        sleep(duration)
        "Task #$id done in $(round(duration; digits=2))s ($(sum(1:10_000_000)))"
    end
    push!(m.log, ">>>  Spawned task #$id")
    m.log_selected = length(m.log)
end

function _spawn_failing_task!(m::AsyncDemoModel)
    m.tasks_spawned += 1
    id = m.tasks_spawned
    spawn_task!(m.tq, :compute) do
        sleep(0.3 + rand() * 0.5)
        error("Task #$id intentional failure")
    end
    push!(m.log, ">>>  Spawned failing task #$id")
    m.log_selected = length(m.log)
end

function _spawn_batch_tasks!(m::AsyncDemoModel, count::Int)
    base = m.tasks_spawned
    for i in 1:count
        m.tasks_spawned += 1
        id = m.tasks_spawned
        spawn_task!(m.tq, :batch) do
            sleep(0.2 + rand() * 1.5)
            id
        end
    end
    push!(m.log, ">>>  Spawned batch of $count tasks (#$(base+1)-#$(base+count))")
    m.log_selected = length(m.log)
end

function _toggle_timer!(m::AsyncDemoModel)
    if m.timer_running
        m.timer_token !== nothing && cancel!(m.timer_token)
        m.timer_token = nothing
        m.timer_running = false
        push!(m.log, "---  Timer stopped")
    else
        m.timer_ticks = 0
        m.timer_token = spawn_timer!(m.tq, :tick, 1.0; repeat=true)
        m.timer_running = true
        push!(m.log, "---  Timer started (1s interval)")
    end
    m.log_selected = length(m.log)
end

function view(m::AsyncDemoModel, f::Frame)
    m.tick += 1
    m.active_count = m.tq.active[]
    buf = f.buffer

    # Layout: top half split horizontally, bottom half for log
    rows = split_layout(Layout(Vertical,
        [Fixed(10), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return

    top_area = rows[1]
    log_area = rows[2]
    status_area = rows[3]

    cols = split_layout(Layout(Horizontal,
        [Percent(55), Fill()]), top_area)
    length(cols) < 2 && return

    _render_task_panel!(m, buf, cols[1])
    _render_timer_panel!(m, buf, cols[2])
    _render_log_panel!(m, buf, log_area)

    # Status bar
    render(StatusBar(
        left=[Span("  [s]spawn [f]fail [b]batch(5) [t]timer ", tstyle(:text_dim))],
        right=[Span("[↑↓]scroll [q]quit ", tstyle(:text_dim))],
    ), status_area, buf)
end

function _render_task_panel!(m::AsyncDemoModel, buf::Buffer, area::Rect)
    block = Block(
        title="Task Launcher",
        border_style=tstyle(:border),
        title_style=tstyle(:accent, bold=true),
    )
    content = render(block, area, buf)
    rx = right(content)
    y = content.y

    set_string!(buf, content.x + 1, y, "Spawned:   $(m.tasks_spawned)",
                tstyle(:text); max_x=rx)
    y += 1
    set_string!(buf, content.x + 1, y, "Completed: $(m.tasks_completed)",
                tstyle(:success); max_x=rx)
    y += 1
    set_string!(buf, content.x + 1, y, "Failed:    $(m.tasks_failed)",
                m.tasks_failed > 0 ? tstyle(:error) : tstyle(:text_dim); max_x=rx)
    y += 1
    # Active spinner
    if m.active_count > 0
        si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
        set_char!(buf, content.x + 1, y, SPINNER_BRAILLE[si], tstyle(:accent))
        set_string!(buf, content.x + 3, y, "$(m.active_count) active",
                    tstyle(:accent, bold=true); max_x=rx)
    else
        set_string!(buf, content.x + 1, y, "  idle",
                    tstyle(:text_dim); max_x=rx)
    end
    y += 2
    set_string!(buf, content.x + 1, y,
                "[s] spawn   [f] fail   [b] batch(5)",
                tstyle(:text_dim); max_x=rx)
end

function _render_timer_panel!(m::AsyncDemoModel, buf::Buffer, area::Rect)
    block = Block(
        title="Timer",
        border_style=tstyle(:border),
        title_style=tstyle(:accent, bold=true),
    )
    content = render(block, area, buf)
    rx = right(content)
    y = content.y

    status = m.timer_running ? "RUNNING" : "STOPPED"
    style = m.timer_running ? tstyle(:success, bold=true) : tstyle(:text_dim)
    set_string!(buf, content.x + 1, y, "Status: $status", style; max_x=rx)
    y += 1
    set_string!(buf, content.x + 1, y, "Ticks:  $(m.timer_ticks)",
                tstyle(:text); max_x=rx)
    y += 2

    if m.timer_running
        # Show a progress-like bar for visual feedback
        bar_w = max(1, content.width - 2)
        filled = mod(m.tick ÷ 2, bar_w)
        bar = string(repeat('█', filled), repeat('░', bar_w - filled))
        set_string!(buf, content.x + 1, y, bar, tstyle(:accent); max_x=rx)
    end

    y += 2
    set_string!(buf, content.x + 1, y, "[t] toggle timer",
                tstyle(:text_dim); max_x=rx)
end

function _render_log_panel!(m::AsyncDemoModel, buf::Buffer, area::Rect)
    block = Block(
        title="Results Log ($(length(m.log)) entries)",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    content = render(block, area, buf)
    rx = right(content)
    visible_h = content.height

    visible_h <= 0 && return

    # Auto-scroll to keep selected visible
    if m.log_selected > m.log_offset + visible_h
        m.log_offset = m.log_selected - visible_h
    elseif m.log_selected <= m.log_offset
        m.log_offset = max(0, m.log_selected - 1)
    end

    for row in 1:visible_h
        idx = m.log_offset + row
        idx > length(m.log) && break
        y = content.y + row - 1
        entry = m.log[idx]

        style = if startswith(entry, "OK")
            tstyle(:success)
        elseif startswith(entry, "ERR")
            tstyle(:error)
        elseif startswith(entry, "TICK")
            tstyle(:accent)
        elseif startswith(entry, ">>>")
            tstyle(:warning)
        else
            tstyle(:text_dim)
        end

        if idx == m.log_selected
            for cx in content.x:rx
                set_char!(buf, cx, y, ' ', tstyle(:accent))
            end
            set_string!(buf, content.x + 1, y, entry,
                        Style(fg=Color256(0), bg=theme().accent); max_x=rx)
        else
            set_string!(buf, content.x + 1, y, entry, style; max_x=rx)
        end
    end
end

function async_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(AsyncDemoModel(); fps=30)
end
