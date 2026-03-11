# ═══════════════════════════════════════════════════════════════════════
# REPLWidget ── in-process Julia REPL embedded in a widget
#
# Runs a full Julia REPL (LineEditREPL) inside the current process,
# connected to a PTY pair. The REPL writes ANSI output to the PTY
# slave; the widget reads from the PTY master and renders via the
# same VT parser used by TerminalWidget. Keyboard input is forwarded
# from the widget through the master to the REPL.
#
# Because the REPL runs in-process, it shares all loaded modules,
# variables, and state with the host application.
# ═══════════════════════════════════════════════════════════════════════

using REPL
using REPL.Terminals: TTYTerminal
import Pkg

"""
    REPLWidget(; rows=24, cols=80, ...)

An embedded Julia REPL that runs in the current process. The REPL
shares the host's module space — any loaded packages and variables
are accessible.

Renders identically to the standard Julia REPL: colored prompts,
tab completion, help mode (`?`), pkg mode (`]`), shell mode (`;`),
history, and multi-line editing all work.

# Example

    rw = REPLWidget(; rows=20, cols=80)

    # In your view:
    render(rw, area, buf)

    # In your update!:
    handle_key!(rw, evt)

    # Cleanup:
    close!(rw)
"""
mutable struct REPLWidget
    tw::TerminalWidget        # rendering + VT parsing via PTY master
    slave_in::Base.TTY        # REPL reads input from here
    slave_out::Base.TTY       # REPL writes output here
    slave_err::Base.TTY       # REPL writes errors here
    repl_task::Task            # background task running the REPL frontend
    exited::Bool              # true after REPL task finishes (e.g. Ctrl+D)
    on_exit::Union{Function,Nothing}  # called once when REPL exits
    saved_stdin::IO           # original stdin before redirect (restored on close!)
end

function REPLWidget(;
        rows::Int=24, cols::Int=80,
        show_scrollbar::Bool=true,
        focused::Bool=true,
        scrollback_limit::Int=1000,
        on_exit::Union{Function,Nothing}=nothing)

    # Create PTY pair (no subprocess)
    pty, slave_fd = pty_pair(; rows, cols)

    # Create Julia TTY objects BEFORE cfmakeraw so libuv saves the
    # default terminal state (ECHO + ICANON on). This way LineEdit's
    # raw!(term, false) restores ECHO, letting interactive prompts
    # (e.g., Pkg's "y/n") echo typed characters.
    # dup() so each stream has its own fd (libuv takes ownership).
    slave_in  = Base.TTY(RawFD(slave_fd))
    slave_out = Base.TTY(RawFD(ccall(:dup, Cint, (Cint,), slave_fd)))
    slave_err = Base.TTY(RawFD(ccall(:dup, Cint, (Cint,), slave_fd)))

    # Now set raw mode — LineEdit expects raw mode for single-keypress
    # input. cfmakeraw after TTY creation means libuv's "normal" state
    # has ECHO enabled (good for prompts).
    _cfmakeraw!(slave_fd)

    # Save original stdin so we can restore it on close!.
    saved_stdin = stdin
    # Redirect global stdin to this REPL's slave input so that
    # interactive prompts (e.g., Pkg's "Install package? (y/n)")
    # read keystrokes from the widget instead of the app's event loop.
    # The app loop reads from INPUT_IO[] (saved in app()), not Base.stdin.
    redirect_stdin(slave_in)

    # Build the terminal and REPL
    term = TTYTerminal("xterm-256color", slave_in, slave_out, slave_err)
    # onlcr: cfmakeraw disables OPOST on the PTY slave, so the kernel
    # won't translate \n → \r\n. The VT parser must do it instead,
    # otherwise LF only moves the cursor down without resetting to col 1.
    tw = TerminalWidget(pty; show_scrollbar, focused, scrollback_limit, onlcr=true, enter_as_lf=true)

    repl_task = Threads.@spawn begin
        try
            repl = REPL.LineEditREPL(term, true)  # hascolor=true
            # Use specialdisplay so each REPL displays results through its
            # own output stream instead of the global display stack. Without
            # this, the last-created REPL's pushdisplay wins and all result
            # output routes to a single widget.
            repl.specialdisplay = REPL.REPLDisplay(repl)
            repl.interface = REPL.setup_interface(repl)
            # Initialize Pkg REPL mode on this widget's REPL.
            # Pkg's REPLExt.__init__ calls repl_init on Base.active_repl
            # (the main REPL) and never registers an atreplinit hook.
            # We must call repl_init directly for our embedded REPL.
            let ext = Base.get_extension(Pkg, :REPLExt)
                ext !== nothing && ext.repl_init(repl)
            end

            # Route Pkg output to the REPL's PTY instead of captured stdout.
            # Without this, Pkg writes to the broken capture pipe (EPIPE).
            Pkg.DEFAULT_IO[] = IOContext(slave_out, :color => true,
                                        :displaysize => (rows, cols))

            REPL.run_repl(repl; backend_on_current_task=false)
        catch e
            e isa EOFError || e isa Base.IOError ||
                @error "REPL task error" exception=(e, catch_backtrace())
        end
    end

    REPLWidget(tw, slave_in, slave_out, slave_err, repl_task, false, on_exit, saved_stdin)
end

"""
    route_output!(rw::REPLWidget, text::String)

Inject text into the REPL widget's display. Used by the
`on_stdout`/`on_stderr` callbacks to route captured process output
(e.g., from shell mode or Pkg operations) into the widget.

Writes directly to the PTY output channel rather than through the
slave TTY handle. This avoids libuv threading issues when the REPL
frontend is concurrently using the same underlying PTY (e.g., during
Pkg operations triggered by `using SomePackage`).
"""
function route_output!(rw::REPLWidget, text::String)
    try
        data = Vector{UInt8}(codeunits(text))
        put!(rw.tw.pty.output, data)
    catch
    end
end

# ── Delegate widget protocol to inner TerminalWidget ─────────────────

focusable(::REPLWidget) = true

function render(rw::REPLWidget, rect::Rect, buf::Buffer)
    render(rw.tw, rect, buf)
end

function handle_key!(rw::REPLWidget, evt::KeyEvent)::Bool
    handle_key!(rw.tw, evt)
end

function handle_mouse!(rw::REPLWidget, evt::MouseEvent)::Bool
    handle_mouse!(rw.tw, evt)
end

function drain!(rw::REPLWidget)::Bool
    changed = drain!(rw.tw)
    if !rw.exited && istaskdone(rw.repl_task)
        rw.exited = true
        rw.tw.exited = true  # prevent TerminalWidget's own exit detection
        try
            write(rw.slave_out, "\r\n\x1b[90m[Session ended]\x1b[0m\r\n")
        catch
        end
        changed = true
        rw.on_exit !== nothing && rw.on_exit()
    end
    changed
end

"""
    close!(rw::REPLWidget)

Shut down the in-process REPL and clean up the PTY.
"""
function close!(rw::REPLWidget)
    # Restore original stdin before closing slave streams — redirect_stdin
    # overwrote fd 0 via dup2, so the next app() call would dup a dead fd.
    try redirect_stdin(rw.saved_stdin) catch end
    # Close slave streams (causes REPL reads/writes to fail → task exits)
    for io in (rw.slave_in, rw.slave_out, rw.slave_err)
        try close(io) catch end
    end
    # Close PTY master side + reader task
    pty_close!(rw.tw.pty)
    # Wait for REPL task with timeout to avoid hanging on blocked I/O
    if !istaskdone(rw.repl_task)
        deadline = time() + 2.0
        while !istaskdone(rw.repl_task) && time() < deadline
            sleep(0.05)
        end
    end
    nothing
end
