# ═══════════════════════════════════════════════════════════════════════
# PTY ── pseudo-terminal management for embedded terminal widgets
#
# Platform: Unix only (macOS, Linux, BSD). PTYs are a Unix kernel concept;
# Windows would require a ConPTY backend behind the same API surface.
#
# Linux: openpty() + posix_spawnp() (avoids fork() deadlocks in Julia's
# multithreaded runtime); POSIX_SPAWN_SETSID + opening the slave assigns
# the controlling terminal. macOS: posix_spawn can't assign a ctty (BSD
# needs an explicit TIOCSCTTY), so we use forkpty()/login_tty() there,
# execing immediately in the child so the fork is safe.
#
# PTY output is read by a background task using FileWatching.poll_fd
# and delivered via a Channel{Vector{UInt8}}. This decouples PTY I/O
# from the rendering loop and avoids blocking the main thread.
# ═══════════════════════════════════════════════════════════════════════

"""
    PTY

Manages a pseudo-terminal pair: a master fd (parent reads/writes) connected
to a child process running in its own terminal session.

Read subprocess output from `pty.output` (a `Channel{Vector{UInt8}}`).
Write input via `pty_write(pty, data)`.
"""
mutable struct PTY
    master_fd::Cint          # master side fd (parent reads/writes here)
    child_pid::Cint          # child process PID
    rows::Int                # current terminal size
    cols::Int
    alive::Bool              # false after child exits
    output::Channel{Vector{UInt8}}   # child → parent data
    reader_task::Task                # background reader
    on_data::Union{Function,Nothing}  # called after data push to output
end

# ── TIOCSWINSZ ioctl constant (set terminal size) ────────────────────
const _TIOCSWINSZ = @static (Sys.isapple() || Sys.isbsd()) ? Culong(0x80087467) : Culong(0x5414)

# TCSANOW constant for tcsetattr (apply immediately)
const _TCSANOW = Cint(0)

"""
    _cfmakeraw!(fd::Cint)

Set a file descriptor to raw mode via cfmakeraw + tcsetattr. Used to
pre-configure the PTY slave before wrapping it in Base.TTY, so that
LineEdit's later `raw!()` call is a no-op (preventing any possible
blocking on tcsetattr).
"""
function _cfmakeraw!(fd::Cint)
    termios = zeros(UInt8, 128)  # generous; macOS ≈72 bytes, Linux ≈60
    GC.@preserve termios begin
        ret = ccall(:tcgetattr, Cint, (Cint, Ptr{UInt8}), fd, pointer(termios))
        ret == 0 || return nothing
        ccall(:cfmakeraw, Cvoid, (Ptr{UInt8},), pointer(termios))
        ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}), fd, _TCSANOW, pointer(termios))
    end
    return nothing
end

# ── Non-blocking flag (used by reader after poll_fd confirms readability) ──
const _O_NONBLOCK = @static (Sys.isapple() || Sys.isbsd()) ? Cint(0x0004) : Cint(0x0800)
const _F_SETFL = Cint(4)
const _F_GETFL = Cint(3)

function _set_nonblocking(fd::Cint)
    flags = ccall(:fcntl, Cint, (Cint, Cint), fd, _F_GETFL)
    return ccall(:fcntl, Cint, (Cint, Cint, Cint), fd, _F_SETFL, flags | _O_NONBLOCK)
end

# EAGAIN / EWOULDBLOCK — non-blocking read returns this when no data available
const _EAGAIN = @static Sys.isapple() ? Cint(35) : Cint(11)

# ── posix_spawn constants ────────────────────────────────────────────
const _POSIX_SPAWN_SETSID = @static Sys.isapple() ? Cshort(0x0400) : Cshort(0x0080)
const _O_RDWR = Cint(2)

# posix_spawn_file_actions_t is opaque; on macOS it's a pointer (8 bytes),
# on Linux/glibc it's a struct (up to 80 bytes). Allocate enough space.
const _SPAWN_FA_SIZE = @static Sys.isapple() ? 8 : 80
const _SPAWN_ATTR_SIZE = @static Sys.isapple() ? 8 : 336

# ── Background PTY reader ───────────────────────────────────────────

"""
    _start_pty_reader(pty::PTY) → Task

Spawn an @async task that uses `FileWatching.poll_fd` to efficiently
wait for data on the PTY master fd, then reads it and pushes chunks
to `pty.output`. This integrates with Julia's event loop via libuv
so it never blocks the main thread.
"""
function _start_pty_reader(pty::PTY)
    @async begin
        buf = Vector{UInt8}(undef, 8192)
        fd = RawFD(pty.master_fd)
        try
            while pty.alive
                # Wait for the fd to become readable (yields to event loop)
                result = poll_fd(fd, 1.0; readable=true, writable=false)
                result.readable || continue
                # Drain all available data
                while true
                    n = GC.@preserve buf ccall(
                        :read,
                        Cssize_t,
                        (Cint, Ptr{UInt8}, Csize_t),
                        pty.master_fd,
                        pointer(buf),
                        Csize_t(length(buf)),
                    )
                    if n > 0
                        put!(pty.output, buf[1:n])
                        pty.on_data !== nothing && pty.on_data()
                    elseif n < 0
                        errno = Base.Libc.errno()
                        errno == _EAGAIN && break  # no more data right now
                        pty.alive = false
                        break
                    else
                        # EOF — child closed its end
                        pty.alive = false
                        break
                    end
                end
            end
        catch e
            # Channel closed, fd closed, or other shutdown — normal
            e isa InvalidStateException ||
                e isa Base.IOError ||
                (pty.alive && @debug "PTY reader error" exception=(e, catch_backtrace()))
        end
        pty.alive = false
    end
end

# macOS: posix_spawn can't make the slave the controlling terminal — BSD doesn't assign a ctty
# on open the way Linux does (it needs an explicit TIOCSCTTY), so a child that opens /dev/tty
# fails ("Device not configured") and never receives SIGWINCH. forkpty does login_tty (setsid +
# TIOCSCTTY + dup the slave to 0/1/2) in the child, giving it a real controlling terminal. argv
# and envp are built BEFORE the fork; the forked child only execs — no Julia allocation between
# fork and exec.
@static if Sys.isapple()
    function _pty_spawn_forkpty(
        cmd::Vector{String}; rows::Int, cols::Int, env, dir::Union{AbstractString,Nothing}=nothing
    )
        prog = Sys.which(cmd[1])
        prog === nothing && error("pty_spawn: command not found in PATH: $(cmd[1])")
        ws = UInt16[rows, cols, 0, 0]
        master = Ref{Cint}(-1)
        c_strs = [Base.cconvert(Cstring, s) for s in cmd]
        argv = Cstring[Base.unsafe_convert(Cstring, c) for c in c_strs]
        push!(argv, C_NULL)
        env_dict = copy(ENV)
        if env !== nothing
            for (k, v) in env
                env_dict[k] = v
            end
        end
        haskey(env_dict, "TERM") || (env_dict["TERM"] = "xterm-256color")
        env_c = [Base.cconvert(Cstring, "$k=$v") for (k, v) in env_dict]
        envp = Cstring[Base.unsafe_convert(Cstring, c) for c in env_c]
        push!(envp, C_NULL)
        prog_c = Base.cconvert(Cstring, prog)
        # Optional working directory for the child, chdir'd after fork, before exec. The Cstring is
        # built here (pre-fork) so the child only does the allocation-free ccall.
        dir_c = dir === nothing ? nothing : Base.cconvert(Cstring, String(dir))
        pid = GC.@preserve c_strs argv env_c envp prog_c dir_c ws begin
            p = ccall(
                :forkpty,
                Cint,
                (Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt16}),
                master,
                C_NULL,
                C_NULL,
                pointer(ws),
            )
            if p == 0
                # CHILD — login_tty already done by forkpty; chdir (if asked) then exec (no allocation).
                # Fail loudly on a bad dir: exec'ing in the inherited cwd would silently run the child
                # in the wrong place. Matches the posix_spawn path, where addchdir_np fails the spawn.
                if dir_c !== nothing &&
                    ccall(:chdir, Cint, (Cstring,), Base.unsafe_convert(Cstring, dir_c)) != 0
                    ccall(:_exit, Cvoid, (Cint,), Cint(127))
                end
                ccall(
                    :execve,
                    Cint,
                    (Cstring, Ptr{Cstring}, Ptr{Cstring}),
                    Base.unsafe_convert(Cstring, prog_c),
                    pointer(argv),
                    pointer(envp),
                )
                ccall(:_exit, Cvoid, (Cint,), Cint(127))
            end
            p
        end
        pid == -1 && error("forkpty failed: $(Base.Libc.strerror(Base.Libc.errno()))")
        _set_nonblocking(master[])
        output = Channel{Vector{UInt8}}(64)
        pty = PTY(master[], pid, rows, cols, true, output, (@async nothing), nothing)
        pty.reader_task = _start_pty_reader(pty)
        return pty
    end
end  # @static Sys.isapple()

# `openpty` lives in a different library depending on the platform/libc, and a bare-symbol ccall only
# finds it where it's in the default image:
#   • macOS/BSD  → libSystem (default image) — bare symbol resolves.
#   • Linux glibc <2.34 → libutil.so.1 (the versioned SONAME; bare `libutil` needs the -dev symlink).
#   • Linux glibc ≥2.34 → merged into libc; libutil.so.1 usually persists as a compat stub.
#   • musl (Alpine) → in libc directly; there is no libutil.
# So rather than hardcode one name (fragile), probe a candidate list at first use, resolve the symbol
# via dlopen/dlsym, cache the pointer, and fail LOUDLY (listing what was tried) if none work.
@static if Sys.isapple()
    _openpty(master, slave, name_ptr, ws_ptr) = ccall(
        :openpty,
        Cint,
        (Ptr{Cint}, Ptr{Cint}, Ptr{UInt8}, Ptr{Cvoid}, Ptr{UInt16}),
        master,
        slave,
        name_ptr,
        C_NULL,
        ws_ptr,
    )
else
    const _OPENPTY = Ref{Ptr{Cvoid}}(C_NULL)                  # resolved lazily at runtime, never baked in
    const _OPENPTY_LIBS = ("libutil.so.1", "libc.so.6", "libutil.so", "libc.so", "libutil")
    function _resolve_openpty()
        _OPENPTY[] == C_NULL || return _OPENPTY[]
        Libdl = Base.Libc.Libdl
        tried = String[]
        for lib in _OPENPTY_LIBS
            h = Libdl.dlopen_e(lib)
            h == C_NULL && (push!(tried, "$lib (not loadable)"); continue)
            p = Libdl.dlsym_e(h, :openpty)
            p == C_NULL && (push!(tried, "$lib (no openpty symbol)"); continue)
            return (_OPENPTY[] = p)
        end
        error(
            "Tachikoma: could not locate the C `openpty` symbol needed to create a PTY. " *
            "Tried: " *
            join(tried, ", ") *
            ". On glibc install the libutil runtime; " *
            "otherwise ensure a libc providing openpty is on the loader path.",
        )
    end
    _openpty(master, slave, name_ptr, ws_ptr) = ccall(
        _resolve_openpty(),
        Cint,
        (Ptr{Cint}, Ptr{Cint}, Ptr{UInt8}, Ptr{Cvoid}, Ptr{UInt16}),
        master,
        slave,
        name_ptr,
        C_NULL,
        ws_ptr,
    )
end

"""
    pty_spawn(cmd::Vector{String}; rows=24, cols=80, env=nothing, dir=nothing) → PTY

Create a PTY pair and spawn a child process running `cmd`.
Uses `openpty()` for PTY creation and `posix_spawnp()` for process
spawning (avoids fork() deadlocks in multithreaded Julia).
`POSIX_SPAWN_SETSID` gives the child its own session, and opening
the slave PTY by path makes it the controlling terminal.

`env` replaces the child's environment (a name→value `Dict`); `dir`,
if given, is the child's working directory — the spawn fails loudly
rather than silently running in the inherited cwd if it can't be entered.

A background reader task is started automatically. Read output from
`pty.output` (a Channel).
"""
function pty_spawn(
    cmd::Vector{String};
    rows::Int=24,
    cols::Int=80,
    env::Union{Dict{String,String},Nothing}=nothing,
    dir::Union{AbstractString,Nothing}=nothing,
)
    @static Sys.iswindows() && error("PTY not supported on Windows")
    isempty(cmd) && error("pty_spawn: cmd must not be empty")

    # macOS needs forkpty/login_tty to get a controlling terminal (see _pty_spawn_forkpty).
    @static if Sys.isapple()
        return _pty_spawn_forkpty(cmd; rows=rows, cols=cols, env=env, dir=dir)
    end

    master_fd = Ref{Cint}(-1)
    slave_fd = Ref{Cint}(-1)
    slave_name = zeros(UInt8, 256)

    # struct winsize: ws_row, ws_col, ws_xpixel, ws_ypixel (4 × UInt16)
    ws = UInt16[rows, cols, 0, 0]

    # ── Create PTY pair ──
    ret = GC.@preserve ws slave_name _openpty(master_fd, slave_fd, pointer(slave_name), pointer(ws))
    ret == -1 && error("openpty failed: $(Base.Libc.strerror(Base.Libc.errno()))")

    slave_path = GC.@preserve slave_name unsafe_string(pointer(slave_name))

    # Close slave fd in parent — child will re-open it by path
    # (opening by path in a new session makes it the controlling terminal)
    ccall(:close, Cint, (Cint,), slave_fd[])

    # Set non-blocking so the reader can drain without blocking after poll_fd
    _set_nonblocking(master_fd[])

    # ── Set up posix_spawn file actions ──
    # Child: close master fd, open slave by path → fd 0, dup2 to 1 and 2
    file_actions = zeros(UInt8, _SPAWN_FA_SIZE)
    GC.@preserve file_actions begin
        ccall(:posix_spawn_file_actions_init, Cint, (Ptr{UInt8},), pointer(file_actions))
        ccall(
            :posix_spawn_file_actions_addclose,
            Cint,
            (Ptr{UInt8}, Cint),
            pointer(file_actions),
            master_fd[],
        )
        ccall(
            :posix_spawn_file_actions_addopen,
            Cint,
            (Ptr{UInt8}, Cint, Cstring, Cint, Cushort),
            pointer(file_actions),
            Cint(0),
            slave_path,
            _O_RDWR,
            Cushort(0),
        )
        ccall(
            :posix_spawn_file_actions_adddup2,
            Cint,
            (Ptr{UInt8}, Cint, Cint),
            pointer(file_actions),
            Cint(0),
            Cint(1),
        )
        ccall(
            :posix_spawn_file_actions_adddup2,
            Cint,
            (Ptr{UInt8}, Cint, Cint),
            pointer(file_actions),
            Cint(0),
            Cint(2),
        )
        # Optional working directory: chdir the child before exec (glibc 2.29+ file action).
        dir === nothing || ccall(
            :posix_spawn_file_actions_addchdir_np,
            Cint,
            (Ptr{UInt8}, Cstring),
            pointer(file_actions),
            String(dir),
        )
    end

    # ── Set up posix_spawn attributes (new session) ──
    spawn_attr = zeros(UInt8, _SPAWN_ATTR_SIZE)
    GC.@preserve spawn_attr begin
        ccall(:posix_spawnattr_init, Cint, (Ptr{UInt8},), pointer(spawn_attr))
        ccall(
            :posix_spawnattr_setflags,
            Cint,
            (Ptr{UInt8}, Cshort),
            pointer(spawn_attr),
            _POSIX_SPAWN_SETSID,
        )
    end

    # ── Build argv and spawn ──
    c_strs = [Base.cconvert(Cstring, s) for s in cmd]
    argv = Cstring[Base.unsafe_convert(Cstring, c) for c in c_strs]
    push!(argv, C_NULL)

    # Build envp from current process environment, ensuring TERM is set
    env_dict = copy(ENV)
    if env !== nothing
        for (k, v) in env
            env_dict[k] = v
        end
    end
    haskey(env_dict, "TERM") || (env_dict["TERM"] = "xterm-256color")
    env_strings = ["$k=$v" for (k, v) in env_dict]
    env_c_strs = [Base.cconvert(Cstring, s) for s in env_strings]
    envp = Cstring[Base.unsafe_convert(Cstring, c) for c in env_c_strs]
    push!(envp, C_NULL)

    pid = Ref{Cint}(0)
    ret = GC.@preserve file_actions spawn_attr c_strs argv env_c_strs envp ccall(
        :posix_spawnp,
        Cint,
        (Ptr{Cint}, Cstring, Ptr{UInt8}, Ptr{UInt8}, Ptr{Cstring}, Ptr{Cstring}),
        pid,
        argv[1],
        pointer(file_actions),
        pointer(spawn_attr),
        pointer(argv),
        pointer(envp),
    )

    # Clean up spawn structs
    GC.@preserve file_actions ccall(
        :posix_spawn_file_actions_destroy, Cint, (Ptr{UInt8},), pointer(file_actions)
    )
    GC.@preserve spawn_attr ccall(
        :posix_spawnattr_destroy, Cint, (Ptr{UInt8},), pointer(spawn_attr)
    )

    if ret != 0
        ccall(:close, Cint, (Cint,), master_fd[])
        error("posix_spawnp failed: $(Base.Libc.strerror(ret))")
    end

    output = Channel{Vector{UInt8}}(64)
    pty = PTY(master_fd[], pid[], rows, cols, true, output, (@async nothing), nothing)
    pty.reader_task = _start_pty_reader(pty)
    return pty
end

"""
    pty_read(pty::PTY, buf::Vector{UInt8}, max_bytes::Int) → Int

Non-blocking read from the PTY master fd. Returns the number of bytes
read into `buf`, or 0 if no data is available. Returns -1 on error
(other than EAGAIN).

Note: Prefer reading from `pty.output` (Channel) instead of calling
this directly. The background reader task handles reading automatically.
"""
function pty_read(pty::PTY, buf::Vector{UInt8}, max_bytes::Int)
    n = GC.@preserve buf ccall(
        :read,
        Cssize_t,
        (Cint, Ptr{UInt8}, Csize_t),
        pty.master_fd,
        pointer(buf),
        min(max_bytes, length(buf)),
    )
    if n < 0
        errno = Base.Libc.errno()
        errno == _EAGAIN && return 0
        return -1
    end
    return Int(n)
end

"""
    pty_write(pty::PTY, data::Vector{UInt8})

Write raw bytes to the PTY master fd (sends input to the subprocess).
"""
function pty_write(pty::PTY, data::Vector{UInt8})
    isempty(data) && return nothing
    GC.@preserve data ccall(
        :write, Cssize_t, (Cint, Ptr{UInt8}, Csize_t), pty.master_fd, pointer(data), length(data)
    )
    return nothing
end

pty_write(pty::PTY, s::String) = pty_write(pty, Vector{UInt8}(codeunits(s)))

"""
    pty_resize!(pty::PTY, rows::Int, cols::Int)

Update the PTY's terminal size. Sends TIOCSWINSZ ioctl and SIGWINCH
to the child process group so it can reflow its output.
"""
function pty_resize!(pty::PTY, rows::Int, cols::Int)
    pty.rows = rows
    pty.cols = cols
    ws = UInt16[rows, cols, 0, 0]
    GC.@preserve ws ccall(
        :ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), pty.master_fd, _TIOCSWINSZ, pointer(ws)
    )
    # Send SIGWINCH (28) to child process group (skip for in-process PTYs)
    pty.child_pid > 0 && ccall(:kill, Cint, (Cint, Cint), -pty.child_pid, Cint(28))
    return nothing
end

"""
    pty_alive(pty::PTY) → Bool

Check if the child process is still running (non-blocking waitpid).
"""
function pty_alive(pty::PTY)
    pty.alive || return false
    # In-process PTYs (child_pid == 0) have no child to wait on;
    # waitpid(0) would reap unrelated process-group children.
    pty.child_pid <= 0 && return pty.alive
    status = Ref{Cint}(0)
    # WNOHANG = 1
    ret = ccall(:waitpid, Cint, (Cint, Ptr{Cint}, Cint), pty.child_pid, status, Cint(1))
    if ret == pty.child_pid
        pty.alive = false
        return false
    end
    return true
end

"""
    pty_pair(; rows=24, cols=80) → (pty::PTY, slave_fd::Cint)

Create a PTY pair without spawning a subprocess. Returns the PTY
(master side with reader task) and the raw slave fd. The caller is
responsible for the slave fd (e.g., wrapping it in Julia IO for an
in-process REPL). The PTY has `child_pid = 0`.
"""
function pty_pair(; rows::Int=24, cols::Int=80)
    @static Sys.iswindows() && error("PTY not supported on Windows")

    master_fd = Ref{Cint}(-1)
    slave_fd = Ref{Cint}(-1)
    slave_name = zeros(UInt8, 256)
    ws = UInt16[rows, cols, 0, 0]

    ret = GC.@preserve ws slave_name _openpty(master_fd, slave_fd, pointer(slave_name), pointer(ws))
    ret == -1 && error("openpty failed: $(Base.Libc.strerror(Base.Libc.errno()))")

    _set_nonblocking(master_fd[])

    output = Channel{Vector{UInt8}}(64)
    pty = PTY(master_fd[], Cint(0), rows, cols, true, output, (@async nothing), nothing)
    pty.reader_task = _start_pty_reader(pty)
    return (pty, slave_fd[])
end

"""
    pty_close!(pty::PTY)

Close the PTY master fd, stop the reader task, send SIGHUP to the child
(if any), and reap it.
"""
function pty_close!(pty::PTY)
    pty.master_fd == -1 && return nothing
    pty.alive = false
    ccall(:close, Cint, (Cint,), pty.master_fd)
    try
        close(pty.output)
    catch
    end  # unblock reader if waiting on put!
    if !istaskdone(pty.reader_task)
        try
            wait(pty.reader_task)
        catch
        end
    end
    if pty.child_pid > 0
        ccall(:kill, Cint, (Cint, Cint), pty.child_pid, Cint(1))  # SIGHUP
        status = Ref{Cint}(0)
        ccall(:waitpid, Cint, (Cint, Ptr{Cint}, Cint), pty.child_pid, status, Cint(0))
    end
    pty.master_fd = Cint(-1)
    return nothing
end
