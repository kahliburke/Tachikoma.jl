#!/usr/bin/env julia
# Terminal rendering benchmark — measures actual end-to-end frame time
# including terminal output. Run directly in the terminal you want to test:
#
#   julia --project bench/canvas_terminal_bench.jl
#

using Tachikoma
import Tachikoma as T

const W = 80
const H = 40
const FRAMES = 20_000

function render_frame!(buf, canvas, w, h, phase)
    T.reset!(buf)
    T.clear!(canvas)
    dw, dh = T.canvas_dot_size(canvas)
    # Lissajous pattern
    for i in 0:600
        t = phase - i * 0.02
        x = (sin(3.0 * t + π/4) + 1) * 0.5 * (dw - 1)
        y = (sin(2.0 * t) + 1) * 0.5 * (dh - 1)
        T.set_point!(canvas, round(Int, x), round(Int, y))
    end
    T.render(canvas, T.Rect(1, 1, w, h), buf)
end

function frame_to_string(buf, w, h)
    io = IOBuffer()
    print(io, "\e[H")  # cursor home
    for row in 0:(h - 1)
        for col in 0:(w - 1)
            cell = buf.content[row * w + col + 1]
            print(io, cell.char)
        end
        row < h - 1 && print(io, "\r\n")
    end
    String(take!(io))
end

function bench(name, make_canvas)
    buf = T.Buffer(T.Rect(1, 1, W, H))
    canvas = make_canvas(W, H)

    # Warmup (5 frames)
    for i in 1:5
        render_frame!(buf, canvas, W, H, i * 0.03)
        s = frame_to_string(buf, W, H)
        write(stdout, s)
        flush(stdout)
    end

    # Timed
    t0 = time_ns()
    for i in 1:FRAMES
        render_frame!(buf, canvas, W, H, i * 0.03)
        s = frame_to_string(buf, W, H)
        write(stdout, s)
        flush(stdout)
    end
    elapsed_ms = (time_ns() - t0) / 1e6

    fps = FRAMES / (elapsed_ms / 1000)
    ms_per = elapsed_ms / FRAMES
    (name, elapsed_ms, ms_per, fps)
end

# Hide cursor, clear screen
print("\e[?25l\e[2J")

results = []
for (name, factory) in [
    ("Braille 2×4", (w, h) -> T.Canvas(w, h; style=T.tstyle(:primary))),
    ("Block   2×2", (w, h) -> T.BlockCanvas(w, h; style=T.tstyle(:primary))),
    ("Octant  2×4", (w, h) -> T.OctantCanvas(w, h; style=T.tstyle(:primary))),
]
    push!(results, bench(name, factory))
end

# Clear and show results
print("\e[2J\e[H\e[?25h")
println("Canvas Terminal Benchmark  ($(W)×$(H), $(FRAMES) frames)")
println("=" ^ 58)
println(rpad("Backend", 14), rpad("Total", 12), rpad("ms/frame", 12), "FPS")
println("-" ^ 58)
for (name, total, ms_per, fps) in results
    println(rpad(name, 14),
            rpad("$(round(total, digits=1))ms", 12),
            rpad("$(round(ms_per, digits=2))ms", 12),
            round(fps, digits=1))
end
println()
