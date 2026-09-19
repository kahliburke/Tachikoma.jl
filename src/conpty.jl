# ═══════════════════════════════════════════════════════════════════════
# ConPTY ── Windows pseudo-console backend for PTY
#
# Windows has no pty. `CreatePseudoConsole` (Win10 1809+, kernel32) is the
# equivalent: it owns a pair of pipes, renders the child's console output as a
# VT stream on one and feeds the child's console input from the other. The child
# sees a real console, so a REPL line-edits and terminal size changes reach it —
# neither of which a plain pipe can do.
#
# Two things differ from the POSIX path and drive the shape of this file:
#
#   * The child is started with `CreateProcessW` + `STARTUPINFOEXW`, whose
#     attribute list carries PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE. There is no
#     posix_spawn equivalent, and the attribute list has to be sized, allocated
#     and populated by hand.
#   * The output pipe is a HANDLE, not an fd, so `FileWatching.poll_fd` cannot
#     watch it and `ReadFile` blocks. The reader polls `PeekNamedPipe` and only
#     reads what is already buffered; see `_start_conpty_reader` for why neither
#     a bare blocking read nor `@threadcall` works here.
# ═══════════════════════════════════════════════════════════════════════

const _PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = UInt(0x00020016)
const _EXTENDED_STARTUPINFO_PRESENT        = UInt32(0x00080000)
const _CREATE_UNICODE_ENVIRONMENT          = UInt32(0x00000400)
const _STILL_ACTIVE                        = UInt32(259)
const _INVALID_HANDLE_VALUE                = Ptr{Cvoid}(-1)

# x86-64 layouts. STARTUPINFOEXW is STARTUPINFOW (104 bytes) plus lpAttributeList.
const _SIZEOF_STARTUPINFOEXW   = 112
const _OFF_SI_CB               = 0
const _OFF_SI_DWFLAGS          = 60
const _OFF_SI_ATTRLIST         = 104
const _STARTF_USESTDHANDLES    = UInt32(0x00000100)
const _SIZEOF_PROCESS_INFORMATION = 24
const _OFF_PI_HPROCESS         = 0
const _OFF_PI_HTHREAD          = 8
const _OFF_PI_PID              = 16

# COORD is two shorts and is passed by value, which on x64 means a single 32-bit
# register: X in the low half, Y in the high half.
_coord(rows::Integer, cols::Integer) = UInt32(UInt16(cols)) | (UInt32(UInt16(rows)) << 16)

_win_err(what) = error("$what failed: GetLastError=$(Libc.GetLastError())")

"""Null-terminated UTF-16 environment block: `K=V\\0K=V\\0…\\0`."""
function _win_env_block(env_dict)
    buf = UInt16[]
    for (k, v) in env_dict
        append!(buf, Base.cwstring("$k=$v"))   # each already carries its NUL
    end
    push!(buf, UInt16(0))                      # terminating empty string
    return buf
end

"""
    _conpty_create(rows, cols) → (hpcon, hin, hout)

Create a pseudo-console and return its handle plus the two ends this process
keeps: `hin` to write child input, `hout` to read child output. The ends the
console owns are closed here — holding them open would keep the pipe alive
after the child exits and the reader would never see EOF.
"""
function _conpty_create(rows::Int, cols::Int)
    in_read  = Ref{Ptr{Cvoid}}(C_NULL)
    in_write = Ref{Ptr{Cvoid}}(C_NULL)
    out_read = Ref{Ptr{Cvoid}}(C_NULL)
    out_write= Ref{Ptr{Cvoid}}(C_NULL)

    ccall((:CreatePipe, "kernel32"), Cint,
          (Ptr{Ptr{Cvoid}}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, UInt32),
          in_read, in_write, C_NULL, 0) == 0 && _win_err("CreatePipe(input)")
    ccall((:CreatePipe, "kernel32"), Cint,
          (Ptr{Ptr{Cvoid}}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, UInt32),
          out_read, out_write, C_NULL, 0) == 0 && _win_err("CreatePipe(output)")

    hpcon = Ref{Ptr{Cvoid}}(C_NULL)
    hr = ccall((:CreatePseudoConsole, "kernel32"), Int32,
               (UInt32, Ptr{Cvoid}, Ptr{Cvoid}, UInt32, Ptr{Ptr{Cvoid}}),
               _coord(rows, cols), in_read[], out_write[], UInt32(0), hpcon)
    if hr != 0
        for h in (in_read[], in_write[], out_read[], out_write[])
            ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), h)
        end
        error("CreatePseudoConsole failed (HRESULT 0x$(string(reinterpret(UInt32, hr), base=16))) — " *
              "ConPTY needs Windows 10 1809 or newer")
    end

    # The console duplicated what it needs; these ends are ours to drop.
    ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), in_read[])
    ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), out_write[])
    return (hpcon[], in_write[], out_read[])
end

"""
    _conpty_spawn(cmd, hpcon; env, dir) → (hprocess, pid)

Start `cmd` attached to the pseudo-console `hpcon`.
"""
function _conpty_spawn(cmd::Vector{String}, hpcon::Ptr{Cvoid};
                       env::Union{Dict{String,String},Nothing},
                       dir::Union{AbstractString,Nothing})
    # Size, then allocate, then populate the attribute list.
    sz = Ref{Csize_t}(0)
    ccall((:InitializeProcThreadAttributeList, "kernel32"), Cint,
          (Ptr{Cvoid}, UInt32, UInt32, Ptr{Csize_t}), C_NULL, UInt32(1), UInt32(0), sz)
    attrlist = Vector{UInt8}(undef, sz[])

    si = zeros(UInt8, _SIZEOF_STARTUPINFOEXW)
    pi = zeros(UInt8, _SIZEOF_PROCESS_INFORMATION)

    env_dict = copy(ENV)
    if env !== nothing
        for (k, v) in env
            env_dict[k] = v
        end
    end
    haskey(env_dict, "TERM") || (env_dict["TERM"] = "xterm-256color")
    envblock = _win_env_block(env_dict)

    # CreateProcessW may modify the command line in place, so it gets its own buffer.
    cmdline = Base.cwstring(Base.escape_microsoft_c_args(cmd...))
    cwd = dir === nothing ? UInt16[] : Base.cwstring(String(dir))

    GC.@preserve attrlist si pi envblock cmdline cwd begin
        pattr = pointer(attrlist)
        ccall((:InitializeProcThreadAttributeList, "kernel32"), Cint,
              (Ptr{Cvoid}, UInt32, UInt32, Ptr{Csize_t}),
              pattr, UInt32(1), UInt32(0), sz) == 0 &&
            _win_err("InitializeProcThreadAttributeList")

        # lpValue is the HPCON itself, not a pointer to it. Passing a Ref here makes the
        # child inherit a bogus console and it dies during init with STATUS_DLL_INIT_FAILED
        # (0xC0000142) before running a single instruction.
        ccall((:UpdateProcThreadAttribute, "kernel32"), Cint,
              (Ptr{Cvoid}, UInt32, UInt, Ptr{Cvoid}, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
              pattr, UInt32(0), _PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
              hpcon, Csize_t(sizeof(Ptr{Cvoid})),
              C_NULL, C_NULL) == 0 && _win_err("UpdateProcThreadAttribute")

        psi = pointer(si)
        unsafe_store!(Ptr{UInt32}(psi + _OFF_SI_CB), UInt32(_SIZEOF_STARTUPINFOEXW))
        unsafe_store!(Ptr{Ptr{Cvoid}}(psi + _OFF_SI_ATTRLIST), pattr)
        # Without STARTF_USESTDHANDLES the child receives the parent's standard handles
        # through its process parameters. When the parent's stdout is a redirected file or
        # pipe, the child writes there instead of to its console, and the pseudo-console
        # renders nothing but a title and a cleared screen. The three handle fields stay
        # zero, so the child has no inherited stdio and uses the console it is attached to.
        unsafe_store!(Ptr{UInt32}(psi + _OFF_SI_DWFLAGS), _STARTF_USESTDHANDLES)

        ok = ccall((:CreateProcessW, "kernel32"), Cint,
                   (Ptr{UInt16}, Ptr{UInt16}, Ptr{Cvoid}, Ptr{Cvoid}, Cint, UInt32,
                    Ptr{UInt16}, Ptr{UInt16}, Ptr{Cvoid}, Ptr{Cvoid}),
                   C_NULL, pointer(cmdline), C_NULL, C_NULL, 0,
                   _EXTENDED_STARTUPINFO_PRESENT | _CREATE_UNICODE_ENVIRONMENT,
                   pointer(envblock),
                   isempty(cwd) ? Ptr{UInt16}(C_NULL) : pointer(cwd),
                   psi, pointer(pi))

        ccall((:DeleteProcThreadAttributeList, "kernel32"), Cvoid, (Ptr{Cvoid},), pattr)
        ok == 0 && _win_err("CreateProcessW($(first(cmd)))")

        ppi = pointer(pi)
        hprocess = unsafe_load(Ptr{Ptr{Cvoid}}(ppi + _OFF_PI_HPROCESS))
        hthread  = unsafe_load(Ptr{Ptr{Cvoid}}(ppi + _OFF_PI_HTHREAD))
        pid      = unsafe_load(Ptr{UInt32}(ppi + _OFF_PI_PID))
        ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), hthread)  # never waited on
        return (hprocess, Cint(pid))
    end
end

"""
    _start_conpty_reader(pty) → Task

Drain the console's output pipe into `pty.output`.

A HANDLE cannot be watched with `poll_fd`, and `ReadFile` on it blocks until data
arrives. Neither a bare `ccall` nor `@threadcall` is usable: the first blocks the
whole process, and the second parks a libuv threadpool thread for the lifetime of
the session. That pool is small and shared with Julia's file I/O, so parked readers
starve it and unrelated code blocks. `PeekNamedPipe` reports what is buffered without
blocking, so the loop only ever reads bytes already there and sleeps otherwise.
"""
function _start_conpty_reader(pty::PTY)
    @async begin
        buf   = Vector{UInt8}(undef, 8192)
        nread = Ref{UInt32}(0)
        avail = Ref{UInt32}(0)
        try
            while pty.alive
                ok = ccall((:PeekNamedPipe, "kernel32"), Cint,
                           (Ptr{Cvoid}, Ptr{Cvoid}, UInt32, Ptr{UInt32}, Ptr{UInt32}, Ptr{UInt32}),
                           pty.hout, C_NULL, UInt32(0), C_NULL, avail, C_NULL)
                if ok == 0
                    pty.alive = false     # the console or child is gone
                    break
                end
                if avail[] == 0
                    sleep(0.01)
                    continue
                end
                n = min(UInt32(length(buf)), avail[])
                rok = GC.@preserve buf nread ccall((:ReadFile, "kernel32"), Cint,
                        (Ptr{Cvoid}, Ptr{UInt8}, UInt32, Ptr{UInt32}, Ptr{Cvoid}),
                        pty.hout, pointer(buf), n, nread, C_NULL)
                if rok == 0 || nread[] == 0
                    pty.alive = false
                    break
                end
                put!(pty.output, buf[1:Int(nread[])])
                pty.on_data !== nothing && pty.on_data()
            end
        catch e
            e isa InvalidStateException || e isa Base.IOError ||
                (pty.alive && @debug "ConPTY reader error" exception=(e, catch_backtrace()))
        end
        pty.alive = false
    end
end

"""
    _pty_spawn_conpty(cmd; rows, cols, env, dir) → PTY

Windows implementation of `pty_spawn`.
"""
function _pty_spawn_conpty(cmd::Vector{String}; rows::Int, cols::Int,
                           env::Union{Dict{String,String},Nothing},
                           dir::Union{AbstractString,Nothing})
    hpcon, hin, hout = _conpty_create(rows, cols)
    hprocess, pid = try
        _conpty_spawn(cmd, hpcon; env = env, dir = dir)
    catch
        ccall((:ClosePseudoConsole, "kernel32"), Cvoid, (Ptr{Cvoid},), hpcon)
        ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), hin)
        ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), hout)
        rethrow()
    end

    output = Channel{Vector{UInt8}}(64)
    pty = PTY(Cint(-1), pid, rows, cols, true, output, (@async nothing), nothing,
              hpcon, hprocess, hin, hout)
    pty.reader_task = _start_conpty_reader(pty)
    return pty
end

function _conpty_write(pty::PTY, data::Vector{UInt8})
    written = Ref{UInt32}(0)
    GC.@preserve data written ccall((:WriteFile, "kernel32"), Cint,
        (Ptr{Cvoid}, Ptr{UInt8}, UInt32, Ptr{UInt32}, Ptr{Cvoid}),
        pty.hin, pointer(data), UInt32(length(data)), written, C_NULL)
    nothing
end

function _conpty_alive(pty::PTY)
    code = Ref{UInt32}(0)
    ok = ccall((:GetExitCodeProcess, "kernel32"), Cint,
               (Ptr{Cvoid}, Ptr{UInt32}), pty.hproc, code)
    ok == 0 && return false
    return code[] == _STILL_ACTIVE
end

_conpty_resize(pty::PTY, rows::Int, cols::Int) =
    ccall((:ResizePseudoConsole, "kernel32"), Int32,
          (Ptr{Cvoid}, UInt32), pty.hpcon, _coord(rows, cols))

function _conpty_close!(pty::PTY)
    pty.alive = false
    # Closing the console signals the child, which lets the reader's ReadFile return.
    pty.hpcon == C_NULL ||
        ccall((:ClosePseudoConsole, "kernel32"), Cvoid, (Ptr{Cvoid},), pty.hpcon)
    for h in (pty.hin, pty.hout)
        h == C_NULL || ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), h)
    end
    if pty.hproc != C_NULL
        _conpty_alive(pty) &&
            ccall((:TerminateProcess, "kernel32"), Cint, (Ptr{Cvoid}, UInt32), pty.hproc, UInt32(1))
        ccall((:CloseHandle, "kernel32"), Cint, (Ptr{Cvoid},), pty.hproc)
    end
    pty.hpcon = C_NULL; pty.hproc = C_NULL; pty.hin = C_NULL; pty.hout = C_NULL
    nothing
end
