# ═══════════════════════════════════════════════════════════════════════
# Recording ── .tach file generation from buffer snapshots
#
# CastRecorder struct is defined in cast_recorder.jl (included before
# terminal.jl so Terminal can hold a recorder field).
#
# Two modes:
# 1. Live recording: Ctrl+R hotkey captures each frame after draw!.
# 2. Headless: record_app() / record_widget() for docs/CI.
#
# All recordings use the .tach binary format (cell snapshots + Zstd).
# Export to SVG/GIF/APNG from the snapshots via export_svg(), etc.
# ═══════════════════════════════════════════════════════════════════════

using Dates


# ── Live recording control ───────────────────────────────────────────

const RECORDING_COUNTDOWN = 5.0  # seconds before capture begins

"""
    start_recording!(rec::CastRecorder, width::Int, height::Int;
                     filename::String="")

Begin a live recording session. A 5-second countdown runs first so the
"Recording in N..." notification disappears before frames are captured.
"""
function start_recording!(rec::CastRecorder, width::Int, height::Int;
                          filename::String="")
    if isempty(filename)
        # Default: timestamped file in current directory
        ts = Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
        filename = "tachikoma_$(ts).tach"
    end
    rec.active = true
    rec.width = width
    rec.height = height
    rec.start_time = time()
    rec.countdown = RECORDING_COUNTDOWN
    rec.filename = filename
    empty!(rec.timestamps)
    empty!(rec.cell_snapshots)
    empty!(rec.pixel_snapshots)
    nothing
end

"""
    stop_recording!(rec::CastRecorder) → String

Stop recording and write the .tach file. Returns the filename written.
Cell snapshots are preserved for the export modal; call `clear_recording!`
after export is complete to free memory.
"""
function stop_recording!(rec::CastRecorder)
    rec.active = false
    isempty(rec.cell_snapshots) && return rec.filename
    write_tach(rec.filename, rec.width, rec.height,
               rec.cell_snapshots, rec.timestamps, rec.pixel_snapshots)
    rec.filename
end

"""
    clear_recording!(rec::CastRecorder)

Free all recording data (timestamps, cell snapshots, pixel snapshots).
Call after export is complete or when dismissing the export modal.
"""
function clear_recording!(rec::CastRecorder)
    empty!(rec.timestamps)
    empty!(rec.cell_snapshots)
    empty!(rec.pixel_snapshots)
    nothing
end

"""
    capture_frame!(rec::CastRecorder, buf::Buffer, width::Int, height::Int;
                   gfx_regions, pixel_snapshots)

Snapshot the current buffer as cell-level data and pixel snapshots.
Called from `draw!`. No ANSI encoding is done during recording —
the .tach format stores cell snapshots directly, and export formats
(.gif, .svg, .apng) are generated on demand from the snapshots.

During the countdown period, frames are skipped so UI notifications
(like the countdown itself) don't appear in the recording.
"""
function capture_frame!(rec::CastRecorder, buf::Buffer, width::Int, height::Int;
                        gfx_regions::Vector{GraphicsRegion}=GraphicsRegion[],
                        pixel_snapshots::Vector{PixelSnapshot}=PixelSnapshot[])
    rec.active || return
    # During countdown, tick elapsed time but don't capture
    if rec.countdown > 0.0
        rec.countdown = max(0.0, RECORDING_COUNTDOWN - (time() - rec.start_time))
        if rec.countdown <= 0.0
            # Countdown just finished — reset start_time so timestamps begin at 0
            rec.start_time = time()
        end
        return
    end
    push!(rec.timestamps, time() - rec.start_time)
    push!(rec.cell_snapshots, copy(buf.content))
    # Pixel data for graphics regions (copy matrices so originals can mutate)
    push!(rec.pixel_snapshots, isempty(pixel_snapshots) ? PixelSnapshot[] :
        [(r, c, copy(px)) for (r, c, px) in pixel_snapshots])
    nothing
end


# ── Headless recording ───────────────────────────────────────────────

"""
    record_app(model::Model, filename::String;
               width=80, height=24, frames=120, fps=30,
               events=Event[])

Record a Model headlessly into a `.tach` file. Runs for `frames` frames
at the given `fps`, optionally injecting events from the `events` list.

The `events` argument is a vector of `(frame_number, event)` pairs.
Events are dispatched to `update!` when their frame number is reached.

# Example
```julia
record_app(DashboardModel(), "dashboard.tach";
           width=80, height=24, frames=180, fps=15)
```
"""
function record_app(model::Model, filename::String;
                    width::Int=80, height::Int=24,
                    frames::Int=120, fps::Int=30,
                    events::Vector{<:Tuple}=Tuple{Int,Event}[],
                    realtime::Bool=false,
                    warmup::Int=0)
    tb = TestBackend(width, height)
    buf = tb.buf
    area = Rect(1, 1, width, height)

    sorted_events = sort(collect(events); by=first)
    evt_idx = 1

    cell_snapshots = Vector{Cell}[]
    pixel_snapshots = Vector{PixelSnapshot}[]
    dt = 1.0 / fps
    timestamps = Float64[]
    t = 0.0
    total_frames = warmup + frames

    # Frame pacing (same tiered wait as poll_event in the real app loop)
    next_frame = realtime ? time() : 0.0

    for frame_num in 1:total_frames
        if realtime
            while true
                remaining = next_frame - time()
                remaining <= 0.0 && break
                if remaining > 0.004
                    sleep(0.002)
                elseif remaining > 0.001
                    yield()
                else
                    break
                end
            end
            next_frame += dt
            if next_frame < time()
                next_frame = time()
            end
        end

        # Events are numbered relative to capture start (after warmup)
        capture_num = frame_num - warmup
        if capture_num > 0
            while evt_idx <= length(sorted_events) && sorted_events[evt_idx][1] <= capture_num
                update!(model, sorted_events[evt_idx][2])
                evt_idx += 1
            end
        end

        reset!(buf)
        f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
        view(model, f)

        # Drain task queue if present (for async apps)
        tq = task_queue(model)
        if tq !== nothing
            drain_tasks!(tq) do tevt
                update!(model, tevt)
            end
        end

        # Only capture after warmup
        if capture_num > 0
            push!(cell_snapshots, copy(buf.content))
            push!(pixel_snapshots, isempty(f.pixel_snapshots) ? PixelSnapshot[] :
                [(r, c, copy(px)) for (r, c, px) in f.pixel_snapshots])
            push!(timestamps, t)
            t += dt

            should_quit(model) && break
        end
    end

    write_tach(filename, width, height, cell_snapshots, timestamps, pixel_snapshots)
    filename
end

"""
    record_widget(filename::String, width::Int, height::Int,
                  num_frames::Int; fps::Int=10) do buf, area, frame_idx
        # render widgets here
    end

Record arbitrary widget rendering into a `.tach` file. The callback
receives (Buffer, Rect, frame_index) and should render into the buffer.
Pixel content is supported: use `render_graphics!(frame, data, rect)` by
accepting a Frame from the 4-argument callback form.

For single-frame static screenshots, use `num_frames=1`.

# Example
```julia
record_widget("gauge.tach", 60, 3, 1) do buf, area, frame
    render(Gauge(0.75, block=Block(title="CPU")), area, buf)
end
```
"""
function record_gif end

function record_widget(func::Function, filename::String,
                       width::Int, height::Int, num_frames::Int;
                       fps::Int=10)
    tb = TestBackend(width, height)
    buf = tb.buf
    area = Rect(1, 1, width, height)

    cell_snapshots = Vector{Cell}[]
    pixel_snapshots = Vector{PixelSnapshot}[]
    dt = 1.0 / fps
    timestamps = Float64[]
    t = 0.0

    for i in 1:num_frames
        reset!(buf)
        f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
        if applicable(func, buf, area, i, f)
            func(buf, area, i, f)
        else
            func(buf, area, i)
        end
        push!(cell_snapshots, copy(buf.content))
        push!(pixel_snapshots, isempty(f.pixel_snapshots) ? PixelSnapshot[] :
            [(r, c, copy(px)) for (r, c, px) in f.pixel_snapshots])
        push!(timestamps, t)
        t += dt
    end

    write_tach(filename, width, height, cell_snapshots, timestamps, pixel_snapshots)
    filename
end
