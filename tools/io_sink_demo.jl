# ═══════════════════════════════════════════════════════════════════════
# io_sink_demo.jl ── manual harness for `app(io = ...)` (PR #39)
#
# Runs a Tachikoma app whose frames go into a TCP socket instead of a
# terminal, and whose keystrokes come back off that same socket. Nothing
# in this process is attached to a tty, which is the whole claim under
# test. A second port accepts resize messages so `set_size!` can be
# exercised without a SIGWINCH.
#
# ── Run it ────────────────────────────────────────────────────────────
#
#   Terminal A (ideally a live Julia REPL — see "what to check" below):
#       julia --project=. -e 'include("tools/io_sink_demo.jl"); serve()'
#
#   Terminal B — the "remote display". nc is the whole client: it pipes
#   your keystrokes into the socket and the frames back out to the screen.
#       stty raw -echo; nc localhost 9000; stty sane
#
#   Terminal C — declare a new viewport size at any time:
#       echo "30 100" | nc localhost 9001
#
#   Press q or Esc in terminal B to quit the app.
#
# ── What to check ─────────────────────────────────────────────────────
#
#  1. Frames appear in B, driven by a process with no terminal of its own.
#  2. Keys typed in B reach the app (the counter moves, q quits).
#  3. A resize from C reflows the UI *and* wipes the old frame — no stale
#     glyphs outside the new, smaller region.
#  4. THE REGRESSION THIS PR NEARLY SHIPPED: run serve() from a live REPL
#     in A. After the app exits, A's REPL must still be usable — arrow
#     keys, history, the works. Before the teardown fix, leave_tui! called
#     set_raw_mode!(false) on A's stdin even though setup never touched
#     it, dropping the REPL out of raw mode.
#  5. Nothing the app prints leaks into A's stdout: the injected path
#     deliberately does not redirect the process's streams.
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
using Sockets

const T = Tachikoma

@kwdef mutable struct SinkModel <: Tachikoma.Model
    quit::Bool = false
    tick::Int = 0
    keys::Vector{String} = String[]
    resizes::Int = 0
    size_note::String = ""
end

Tachikoma.should_quit(m::SinkModel) = m.quit

function Tachikoma.update!(m::SinkModel, evt::KeyEvent)
    label = evt.key == :char ? string(evt.char) : string(evt.key)
    pushfirst!(m.keys, label)
    length(m.keys) > 8 && pop!(m.keys)
    evt.key == :escape && (m.quit = true)
    return evt.key == :char && evt.char == 'q' && (m.quit = true)
end

function Tachikoma.view(m::SinkModel, f::Frame)
    m.tick += 1
    outer = Block(;
        title=" rendering into a socket ", box=BOX_ROUNDED, border_style=tstyle(:border_focus)
    )
    inner = render(outer, f.area, f.buffer)

    lines = [
        "frame        $(m.tick)",
        "viewport     $(f.area.width)×$(f.area.height)",
        "resizes      $(m.resizes)  $(m.size_note)",
        "",
        "recent keys  " * (isempty(m.keys) ? "(none yet)" : join(m.keys, " ")),
        "",
        "This process owns no terminal. Frames are bytes on a socket;",
        "keystrokes arrive the same way. Send a resize with:",
        "    echo \"30 100\" | nc localhost 9001",
        "",
        "q or Esc to quit.",
    ]
    return render(Paragraph(join(lines, "\n"); style=tstyle(:text)), inner, f.buffer)
end

"""
    serve(; port = 9000, rows = 24, cols = 80)

Wait for a display client on `port`, then run the app with its frames and
input bound to that socket. Resize messages ("<rows> <cols>\\n") are read
from `port + 1`.
"""
function serve(; port::Int=9000, rows::Int=24, cols::Int=80)
    server = listen(port)
    ctl_server = listen(port + 1)
    @info "io_sink_demo: waiting for a display client" connect = "stty raw -echo; nc localhost $port; stty sane" resize = "echo \"30 100\" | nc localhost $(port + 1)"
    sock = accept(server)
    @info "io_sink_demo: client attached — frames now going to the socket"

    model = SinkModel()
    term = Ref{Union{Tachikoma.Terminal,Nothing}}(nothing)

    # Resize listener. A socket has no SIGWINCH, so the caller that owns the
    # sink is the only one who can say how big the viewport is — that is
    # exactly what set_size! exists for.
    ctl = @async begin
        while !model.quit
            c = try
                accept(ctl_server)
            catch
                break
            end
            @async begin
                for line in eachline(c)
                    parts = split(strip(line))
                    length(parts) == 2 || continue
                    r, cl = tryparse(Int, parts[1]), tryparse(Int, parts[2])
                    (r === nothing || cl === nothing) && continue
                    t = term[]
                    t === nothing && continue
                    if Tachikoma.set_size!(t, (rows=r, cols=cl))
                        model.resizes += 1
                        model.size_note = "← last: $(r)×$(cl)"
                    end
                end
                close(c)
            end
        end
    end

    try
        app(
            model;
            io=sock,                       # frames go here
            input=sock,                    # ...and keystrokes come back off it
            tty_size=(rows=rows, cols=cols),
            on_terminal=t -> (term[] = t), # the handle set_size! needs
            fps=30,
        )
    finally
        model.quit = true
        for s in (sock, server, ctl_server)
            try
                close(s)
            catch
            end
        end
    end
    @info "io_sink_demo: app exited" frames = model.tick resizes = model.resizes
    @info "Now check this REPL is still usable — arrow keys, history, Ctrl-R."
    return model
end
