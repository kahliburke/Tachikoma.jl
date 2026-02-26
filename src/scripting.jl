# ── scripting.jl ─────────────────────────────────────────────────────────────
# EventScript — ergonomic event sequencing for headless app recordings.
#
# Each entry is a (delay_from_previous, event) pair. The timeline cursor starts
# at 0 and advances by each entry's delay in declaration order, so events always
# fire in the order they appear. No absolute times, no sorting surprises.
#
# Subtypes Function so instances store directly in Dict{String,Function}.
#
# Example:
#
#   APP_EVENTS["my_app"] = EventScript(
#       (1.0, key('r')),             # fire 1s from start
#       rep(key('r'), 3),             # 3 more, each 1s later
#       (1.0, key('b')),              # 1s after last roll
#       pause(2.0),                   # wait 2s (no event)
#       seq(key(:down), key(:up)),    # down then up, 1s apart
#       chars("Hello"; pace=0.1),     # type a string
#   )
# ─────────────────────────────────────────────────────────────────────────────

"""
    Wait

Sentinel event type used by `pause()` to advance the EventScript timeline
cursor without firing an event.
"""
struct Wait end

"""
    EventScript(items...) <: Function

Builds a scripted input sequence for headless app recordings.

Each item is either a `(delay, event)` tuple or a vector of such tuples
(returned by `seq`, `rep`, and `chars`). The delay is always relative to
the previous entry, so the declaration order is the firing order.

Call an EventScript with `fps` to get a `Vector{Tuple{Int,Any}}` of
`(frame_number, event)` pairs suitable for passing to `record_app`.

See also: [`seq`](@ref), [`rep`](@ref), [`chars`](@ref), [`pause`](@ref), [`key`](@ref)
"""
struct EventScript <: Function
    entries::Vector{Tuple{Float64,Any}}
end

function EventScript(items...)
    entries = Tuple{Float64,Any}[]
    for item in items
        if item isa AbstractVector
            for entry in item
                push!(entries, entry)
            end
        else
            push!(entries, item)
        end
    end
    EventScript(entries)
end

"""
    (es::EventScript)(fps) → Vector{Tuple{Int,Any}}

Convert the EventScript to frame-indexed events at the given `fps`.
"""
function (es::EventScript)(fps)
    result = Tuple{Int,Any}[]
    cursor = 0.0
    for (delay, evt) in es.entries
        cursor += delay
        evt isa Wait && continue
        push!(result, (round(Int, cursor * fps), evt))
    end
    result
end

"""
    key(k::Symbol) → KeyEvent
    key(c::Char)   → KeyEvent

Shorthand `KeyEvent` constructor for use in event scripts.
"""
key(k::Symbol) = KeyEvent(k)
key(c::Char) = KeyEvent(c)

"""
    pause(seconds) → (delay, Wait())

Advance the EventScript timeline cursor by `seconds` without firing an event.
"""
pause(t::Real) = (Float64(t), Wait())

"""
    seq(events...; gap=1.0) → Vector{Tuple{Float64,Any}}

Return a sequence where each event fires `gap` seconds after the previous one.
The first event fires `gap` seconds after the preceding entry in the EventScript.

    EventScript(
        (2.0, key(:down)),                    # t=2
        seq(key(:down), key(:up); gap=0.5),  # t=2.5, t=3
    )
"""
function seq(evts...; gap::Real = 1.0)
    Tuple{Float64,Any}[(Float64(gap), evt) for evt in evts]
end

"""
    rep(event, n; gap=1.0) → Vector{Tuple{Float64,Any}}

Repeat `event` `n` times, each `gap` seconds after the previous.

    EventScript(rep(key('r'), 4))   # fire 'r' at t=1, 2, 3, 4
"""
function rep(evt, n::Int; gap::Real = 1.0)
    Tuple{Float64,Any}[(Float64(gap), evt) for _ in 1:n]
end

"""
    chars(text; pace=0.08) → Vector{Tuple{Float64,Any}}

Expand `text` into a sequence of `KeyEvent`s, `pace` seconds apart.

    EventScript((1.0, key(:tab)), chars("Alice"; pace=0.1))
"""
function chars(text::AbstractString; pace::Real = 0.08)
    Tuple{Float64,Any}[(Float64(pace), KeyEvent(c)) for c in text]
end
