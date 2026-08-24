# ═══════════════════════════════════════════════════════════════════════
# Clipboard ── copying text out of a TUI
# ═══════════════════════════════════════════════════════════════════════
#
# Two independent ways to reach a clipboard, because neither covers every
# environment:
#
#   :native — pipe to a helper program (pbcopy / wl-copy / xclip / xsel).
#             Writes to the clipboard of the machine Julia runs on.
#   :osc52  — the OSC 52 escape sequence, handled by the terminal emulator
#             itself. Needs no helper program and crosses SSH, but not every
#             terminal implements it and there is no way to confirm it landed.
#
# `:auto` picks native first locally and OSC 52 first when the frames are
# going to another machine's terminal, falling back to the other on failure.

using Base64: base64encode

const CLIPBOARD_BACKENDS = (:auto, :native, :osc52, :none)
const CLIPBOARD_BACKEND = Ref{Symbol}(:auto)

# Terminals cap the length of an OSC 52 sequence; xterm's default limit is the
# strictest in common use. Beyond it the sequence is dropped or truncated, so
# refuse rather than silently copying half a screen.
const OSC52_MAX_BASE64 = 74_994

"""
    clipboard_backend() -> Symbol

The active clipboard backend: `:auto`, `:native`, `:osc52`, or `:none`.
"""
clipboard_backend() = CLIPBOARD_BACKEND[]

"""
    set_clipboard_backend!(backend::Symbol) -> Symbol

Force a clipboard backend for this session.

- `:auto` — native first locally, OSC 52 first over SSH; falls back either way.
- `:native` — helper program only (`pbcopy`, `wl-copy`, `xclip`, `xsel`).
- `:osc52` — terminal escape sequence only. Works over SSH and in Wayland
  sessions with no clipboard helper installed, if the terminal supports it.
- `:none` — disable clipboard writes.

Can also be set at startup with the `TACHIKOMA_CLIPBOARD` environment variable.
"""
function set_clipboard_backend!(backend::Symbol)
    backend in CLIPBOARD_BACKENDS ||
        throw(ArgumentError("unknown clipboard backend $(repr(backend)); expected one of $(CLIPBOARD_BACKENDS)"))
    CLIPBOARD_BACKEND[] = backend
end

function load_clipboard_backend!()
    v = get(ENV, "TACHIKOMA_CLIPBOARD", "")
    isempty(v) && return CLIPBOARD_BACKEND[]
    b = Symbol(lowercase(strip(v)))
    b in CLIPBOARD_BACKENDS || return CLIPBOARD_BACKEND[]
    CLIPBOARD_BACKEND[] = b
end

# ── Native backend ──────────────────────────────────────────────────────

"""
    clipboard_commands() -> Vector{Cmd}

Candidate copy programs for this platform, best first. Wayland sessions get
`wl-copy` ahead of the X11 tools; an X11 session gets the reverse. Both lists
are kept because a session may have either (or a working XWayland bridge), and
which one is installed is not knowable from the environment alone.
"""
function clipboard_commands()
    if Sys.isapple()
        cmds = Cmd[]
        # Under tmux/screen a plain pbcopy can be detached from the user's
        # namespace; this shim reattaches it.
        Sys.which("reattach-to-user-namespace") === nothing ||
            push!(cmds, `reattach-to-user-namespace pbcopy`)
        push!(cmds, `pbcopy`)
        return cmds
    elseif Sys.iswindows()
        return Cmd[`powershell -NoProfile -NonInteractive -Command "\$input | Set-Clipboard"`]
    else
        wayland = Cmd[`wl-copy`]
        x11 = Cmd[`xclip -selection clipboard -in`, `xsel --input --clipboard`]
        return haskey(ENV, "WAYLAND_DISPLAY") ? vcat(wayland, x11) : vcat(x11, wayland)
    end
end

"""
    _run_clipboard_cmd(cmd::Cmd, text::AbstractString; timeout=1.0) -> Bool

Pipe `text` into `cmd`, returning whether it exited cleanly. A helper that is
installed but cannot reach a display server (xclip in a Wayland-only session,
say) exits non-zero, which is what lets the caller move on to the next
candidate. Output is discarded so a failing helper cannot scribble over the
alternate screen, and a helper that never drains stdin is killed rather than
wedging the event loop.
"""
function _run_clipboard_cmd(cmd::Cmd, text::AbstractString; timeout::Float64 = 1.0)
    Sys.which(first(cmd.exec)) === nothing && return false
    proc = try
        open(pipeline(cmd, stdout = devnull, stderr = devnull), "w")
    catch
        return false
    end
    writer = @async try
        write(proc, text)
        close(proc)
    catch
        # Helper exited before reading everything — the exit code below decides.
    end
    deadline = time() + timeout
    while process_running(proc) && time() < deadline
        sleep(0.005)
    end
    if process_running(proc)
        try
            kill(proc)
        catch
        end
        return false
    end
    try
        wait(writer)
    catch
    end
    return success(proc)
end

function _clipboard_copy_native(text::AbstractString)
    for cmd in clipboard_commands()
        _run_clipboard_cmd(cmd, text) && return true
    end
    return false
end

# ── OSC 52 backend ──────────────────────────────────────────────────────

"""
    osc52_sequence(text::AbstractString; selection='c') -> Union{String,Nothing}

The OSC 52 escape sequence that asks the terminal to put `text` on its
clipboard, or `nothing` if the encoded payload exceeds what terminals accept.

No tmux DCS wrapper: tmux's default `set-clipboard external` already forwards
an application's OSC 52 to the outer terminal, and wrapping would instead
require `allow-passthrough on`, which is *not* the default.
"""
function osc52_sequence(text::AbstractString; selection::Char = 'c')
    b64 = base64encode(text)
    length(b64) > OSC52_MAX_BASE64 && return nothing
    return string("\e]52;", selection, ";", b64, "\a")
end

function _clipboard_copy_osc52(text::AbstractString, io::IO)
    seq = osc52_sequence(text)
    seq === nothing && return false
    try
        write(io, seq)
        Base.flush(io)
        return true
    catch
        return false
    end
end

# ── Public entry point ──────────────────────────────────────────────────

"""
    clipboard_copy!(text::AbstractString; io=stdout, backend=clipboard_backend(),
                    remote=_is_ssh_session()) -> Symbol

Copy `text` to the system clipboard. Returns the backend that took it —
`:native`, `:osc52`, or `:none` if nothing worked. Never throws.

A `:osc52` result means the sequence was written, not that the terminal acted
on it; terminals give no acknowledgement. `io` is where that sequence goes and
should be the terminal the app is drawing to.

Set `TACHIKOMA_CLIPBOARD=osc52` (or call [`set_clipboard_backend!`](@ref)) in
environments with no clipboard helper installed — a Wayland session without
`wl-clipboard`, for instance.
"""
function clipboard_copy!(text::AbstractString; io::IO = stdout,
                         backend::Symbol = clipboard_backend(),
                         remote::Bool = _is_ssh_session())
    backend === :none && return :none
    isempty(text) && return :none
    if backend === :native
        return _clipboard_copy_native(text) ? :native : :none
    elseif backend === :osc52
        return _clipboard_copy_osc52(text, io) ? :osc52 : :none
    end
    # :auto — a helper program writes to the clipboard of the machine Julia is
    # on, which is the wrong one when the terminal is somewhere else.
    if remote
        _clipboard_copy_osc52(text, io) && return :osc52
        _clipboard_copy_native(text) && return :native
    else
        _clipboard_copy_native(text) && return :native
        _clipboard_copy_osc52(text, io) && return :osc52
    end
    return :none
end

"""
    clipboard_copy!(t::Terminal, text::AbstractString) -> Symbol

Copy `text`, routing OSC 52 to the terminal `t` renders into and preferring it
when `t`'s frames go to another machine.
"""
clipboard_copy!(t::Terminal, text::AbstractString) =
    clipboard_copy!(text; io = t.io, remote = _is_remote_terminal(t) || _is_ssh_session())
