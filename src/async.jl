# ═══════════════════════════════════════════════════════════════════════
# Async task system ── channel-based background work for the app loop
#
# Preserves the single-threaded Elm architecture: background tasks
# communicate results back via TaskEvent on a Channel, drained each
# frame on the main thread.
# ═══════════════════════════════════════════════════════════════════════

# ── CancelToken ──────────────────────────────────────────────────────

struct CancelToken
    cancelled::Threads.Atomic{Bool}
end
CancelToken() = CancelToken(Threads.Atomic{Bool}(false))
cancel!(t::CancelToken) = Threads.atomic_xchg!(t.cancelled, true)
is_cancelled(t::CancelToken) = t.cancelled[]

# ── TaskQueue ────────────────────────────────────────────────────────

mutable struct TaskQueue
    channel::Channel{Event}
    active::Threads.Atomic{Int}
end
TaskQueue(; capacity::Int=256) = TaskQueue(Channel{Event}(capacity), Threads.Atomic{Int}(0))

# ── spawn_task! ──────────────────────────────────────────────────────

function spawn_task!(f::Function, queue::TaskQueue, id::Symbol)
    Threads.atomic_add!(queue.active, 1)
    Threads.@spawn begin
        try
            result = f()
            put!(queue.channel, TaskEvent(id, result))
        catch e
            put!(queue.channel, TaskEvent(id, e))
        finally
            Threads.atomic_sub!(queue.active, 1)
        end
    end
end

# ── spawn_timer! ─────────────────────────────────────────────────────

function spawn_timer!(queue::TaskQueue, id::Symbol, interval_s::Float64;
                      repeat::Bool=false)
    token = CancelToken()
    Threads.atomic_add!(queue.active, 1)
    Threads.@spawn begin
        try
            while !is_cancelled(token)
                sleep(interval_s)
                is_cancelled(token) && break
                put!(queue.channel, TaskEvent(id, time()))
                repeat || break
            end
        finally
            Threads.atomic_sub!(queue.active, 1)
        end
    end
    token
end

# ── drain_tasks! ─────────────────────────────────────────────────────

function drain_tasks!(callback::Function, queue::TaskQueue)
    count = 0
    while isready(queue.channel)
        evt = take!(queue.channel)
        callback(evt)
        count += 1
    end
    count
end
