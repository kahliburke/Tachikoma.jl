# ═══════════════════════════════════════════════════════════════════════
# PTY ── pseudo-terminal management for embedded terminal widgets
#
# Platform: Unix only (macOS, Linux, BSD). PTYs are a Unix kernel concept;
# Windows would require a ConPTY backend behind the same API surface.
#
# Uses openpty() + posix_spawnp() instead of forkpty() to avoid fork()
# deadlocks in Julia's multithreaded runtime. POSIX_SPAWN_SETSID gives
# the child a proper session and controlling terminal.
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
    on_data::Union{Function, Nothing}  # called after data push to output
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
        ret == 0 || return
        ccall(:cfmakeraw, Cvoid, (Ptr{UInt8},), pointer(termios))
        ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}),
              fd, _TCSANOW, pointer(termios))
    end
    nothing
end

# ── Non-blocking flag (used by reader after poll_fd confirms readability) ──
const _O_NONBLOCK = @static (Sys.isapple() || Sys.isbsd()) ? Cint(0x0004) : Cint(0x0800)
const _F_SETFL    = Cint(4)
const _F_GETFL    = Cint(3)

function _set_nonblocking(fd::Cint)
    flags = ccall(:fcntl, Cint, (Cint, Cint), fd, _F_GETFL)
    ccall(:fcntl, Cint, (Cint, Cint, Cint), fd, _F_SETFL, flags | _O_NONBLOCK)
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
                    n = GC.@preserve buf ccall(:read, Cssize_t,
                        (Cint, Ptr{UInt8}, Csize_t),
                        pty.master_fd, pointer(buf), Csize_t(length(buf)))
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
            e isa InvalidStateException || e isa Base.IOError || (pty.alive && @debug "PTY reader error" exception=(e, catch_backtrace()))
        end
        pty.alive = false
    end
end

"""
    pty_spawn(cmd::Vector{String}; rows=24, cols=80) → PTY

Create a PTY pair and spawn a child process running `cmd`.
Uses `openpty()` for PTY creation and `posix_spawnp()` for process
spawning (avoids fork() deadlocks in multithreaded Julia).
`POSIX_SPAWN_SETSID` gives the child its own session, and opening
the slave PTY by path makes it the controlling terminal.

A background reader task is started automatically. Read output from
`pty.output` (a Channel).
"""
function pty_spawn(cmd::Vector{String}; rows::Int=24, cols::Int=80,
                   env::Union{Dict{String,String}, Nothing}=nothing)
    @static Sys.iswindows() && error("PTY not supported on Windows")
    isempty(cmd) && error("pty_spawn: cmd must not be empty")

    master_fd = Ref{Cint}(-1)
    slave_fd  = Ref{Cint}(-1)
    slave_name = zeros(UInt8, 256)

    # struct winsize: ws_row, ws_col, ws_xpixel, ws_ypixel (4 × UInt16)
    ws = UInt16[rows, cols, 0, 0]

    # ── Create PTY pair ──
    ret = GC.@preserve ws slave_name ccall(:openpty, Cint,
                (Ptr{Cint}, Ptr{Cint}, Ptr{UInt8}, Ptr{Cvoid}, Ptr{UInt16}),
                master_fd, slave_fd, pointer(slave_name), C_NULL, pointer(ws))
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
        ccall(:posix_spawn_file_actions_init, Cint,
              (Ptr{UInt8},), pointer(file_actions))
        ccall(:posix_spawn_file_actions_addclose, Cint,
              (Ptr{UInt8}, Cint), pointer(file_actions), master_fd[])
        ccall(:posix_spawn_file_actions_addopen, Cint,
              (Ptr{UInt8}, Cint, Cstring, Cint, Cushort),
              pointer(file_actions), Cint(0), slave_path, _O_RDWR, Cushort(0))
        ccall(:posix_spawn_file_actions_adddup2, Cint,
              (Ptr{UInt8}, Cint, Cint), pointer(file_actions), Cint(0), Cint(1))
        ccall(:posix_spawn_file_actions_adddup2, Cint,
              (Ptr{UInt8}, Cint, Cint), pointer(file_actions), Cint(0), Cint(2))
    end

    # ── Set up posix_spawn attributes (new session) ──
    spawn_attr = zeros(UInt8, _SPAWN_ATTR_SIZE)
    GC.@preserve spawn_attr begin
        ccall(:posix_spawnattr_init, Cint, (Ptr{UInt8},), pointer(spawn_attr))
        ccall(:posix_spawnattr_setflags, Cint,
              (Ptr{UInt8}, Cshort), pointer(spawn_attr), _POSIX_SPAWN_SETSID)
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
        :posix_spawnp, Cint,
        (Ptr{Cint}, Cstring, Ptr{UInt8}, Ptr{UInt8}, Ptr{Cstring}, Ptr{Cstring}),
        pid, argv[1], pointer(file_actions), pointer(spawn_attr),
        pointer(argv), pointer(envp))

    # Clean up spawn structs
    GC.@preserve file_actions ccall(:posix_spawn_file_actions_destroy, Cint,
                                     (Ptr{UInt8},), pointer(file_actions))
    GC.@preserve spawn_attr ccall(:posix_spawnattr_destroy, Cint,
                                   (Ptr{UInt8},), pointer(spawn_attr))

    if ret != 0
        ccall(:close, Cint, (Cint,), master_fd[])
        error("posix_spawnp failed: $(Base.Libc.strerror(ret))")
    end

    output = Channel{Vector{UInt8}}(64)
    pty = PTY(master_fd[], pid[], rows, cols, true, output, (@async nothing), nothing)
    pty.reader_task = _start_pty_reader(pty)
    pty
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
    n = GC.@preserve buf ccall(:read, Cssize_t,
                (Cint, Ptr{UInt8}, Csize_t),
                pty.master_fd, pointer(buf), min(max_bytes, length(buf)))
    if n < 0
        errno = Base.Libc.errno()
        errno == _EAGAIN && return 0
        return -1
    end
    Int(n)
end

"""
    pty_write(pty::PTY, data::Vector{UInt8})

Write raw bytes to the PTY master fd (sends input to the subprocess).
"""
function pty_write(pty::PTY, data::Vector{UInt8})
    isempty(data) && return
    GC.@preserve data ccall(:write, Cssize_t,
                (Cint, Ptr{UInt8}, Csize_t),
                pty.master_fd, pointer(data), length(data))
    nothing
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
    GC.@preserve ws ccall(:ioctl, Cint,
                (Cint, Culong, Ptr{Cvoid}...),
                pty.master_fd, _TIOCSWINSZ, pointer(ws))
    # Send SIGWINCH (28) to child process group (skip for in-process PTYs)
    pty.child_pid > 0 && ccall(:kill, Cint, (Cint, Cint), -pty.child_pid, Cint(28))
    nothing
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
    ret = ccall(:waitpid, Cint, (Cint, Ptr{Cint}, Cint),
                pty.child_pid, status, Cint(1))
    if ret == pty.child_pid
        pty.alive = false
        return false
    end
    true
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
    slave_fd  = Ref{Cint}(-1)
    slave_name = zeros(UInt8, 256)
    ws = UInt16[rows, cols, 0, 0]

    ret = GC.@preserve ws slave_name ccall(:openpty, Cint,
                (Ptr{Cint}, Ptr{Cint}, Ptr{UInt8}, Ptr{Cvoid}, Ptr{UInt16}),
                master_fd, slave_fd, pointer(slave_name), C_NULL, pointer(ws))
    ret == -1 && error("openpty failed: $(Base.Libc.strerror(Base.Libc.errno()))")

    _set_nonblocking(master_fd[])

    output = Channel{Vector{UInt8}}(64)
    pty = PTY(master_fd[], Cint(0), rows, cols, true, output, (@async nothing), nothing)
    pty.reader_task = _start_pty_reader(pty)
    (pty, slave_fd[])
end

"""
    pty_close!(pty::PTY)

Close the PTY master fd, stop the reader task, send SIGHUP to the child
(if any), and reap it.
"""
function pty_close!(pty::PTY)
    pty.master_fd == -1 && return
    pty.alive = false
    ccall(:close, Cint, (Cint,), pty.master_fd)
    try close(pty.output) catch end  # unblock reader if waiting on put!
    if !istaskdone(pty.reader_task)
        try wait(pty.reader_task) catch end
    end
    if pty.child_pid > 0
        ccall(:kill, Cint, (Cint, Cint), pty.child_pid, Cint(1))  # SIGHUP
        status = Ref{Cint}(0)
        ccall(:waitpid, Cint, (Cint, Ptr{Cint}, Cint),
              pty.child_pid, status, Cint(0))
    end
    pty.master_fd = Cint(-1)
    nothing
end
