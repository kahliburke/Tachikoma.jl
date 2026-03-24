# ═══════════════════════════════════════════════════════════════════════
# Kitty graphics encoder
#
# Converts a ColorRGB pixel matrix to Kitty graphics protocol APC
# sequences (raw RGB, f=24). Uses the same apply_decay! pipeline as
# the sixel encoder for bit-rot effects.
#
# Transmission methods (in order of preference):
#   1. POSIX shared memory (t=s) — ~2ms, ~100 bytes terminal I/O
#   2. Inline base64 (t=d)       — fallback when shm unavailable
#
# Protocol reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
# ═══════════════════════════════════════════════════════════════════════

using Base64: base64encode
using CodecZlib: ZlibCompressor

# Reusable buffer for decay (separate from sixel's to avoid contention)
const _KITTY_ENC_BUF = Ref(Matrix{ColorRGBA}(undef, 0, 0))

# Reusable buffers for encoding (avoid per-frame allocations)
const _KITTY_XPOSE_BUF = Ref(Matrix{ColorRGBA}(undef, 0, 0))  # transposed pixels
const _KITTY_RGB_BUF = Ref(Vector{UInt8}(undef, 0))           # raw RGB bytes
const _KITTY_ZLIB_CODEC = ZlibCompressor(level=1)             # fastest compression
const _KITTY_IO = IOBuffer()                                   # APC output

# ── POSIX shared memory support for t=s Kitty transmission ───────────

# Platform-specific constants (O_CREAT differs between macOS and Linux)
const _O_CREAT = @static Sys.isapple() ? Cint(0x0200) : Cint(0x0040)
const _O_RDWR  = Cint(0x0002)
const _PROT_READ  = Cint(0x01)
const _PROT_WRITE = Cint(0x02)
const _MAP_SHARED  = Cint(0x01)
const _MS_SYNC = @static Sys.isapple() ? Cint(0x0010) : Cint(0x0004)
const _MAP_FAILED = Ptr{Nothing}(-1 % UInt)

const _KITTY_SHM_AVAILABLE = Ref{Union{Nothing, Bool}}(nothing)

# ── Sender-side shm cleanup ───────────────────────────────────────────
# POSIX shm segments created for Kitty t=s transmission are supposed to
# be unlinked by the terminal after reading.  If the terminal doesn't
# support t=s (misdetected) or crashes, segments leak permanently.
#
# Two-generation tracking: segments created this frame go into _CURRENT,
# which is promoted to _PREVIOUS at the start of the next frame (and
# the old _PREVIOUS is unlinked).  This gives the terminal a full frame
# interval (~16ms @60fps) to open each segment before the name is removed.
# POSIX semantics: after shm_unlink the segment stays usable by any
# process that already has it open.
#
# Each generation naturally scales with the number of image widgets —
# no fixed ring size to tune.  Worst-case leak from SIGKILL is one
# frame's worth of segments (typically 1–3).

const _KITTY_SHM_COUNTER = Ref(UInt32(0))

# Two generations of segment names.
const _KITTY_SHM_PREVIOUS = String[]   # from the frame before last — safe to unlink
const _KITTY_SHM_CURRENT  = String[]   # from the most recent frame — terminal may still be reading

"""
    _kitty_shm_cleanup!()

Promote the current generation and unlink the previous one.
Called at the start of each frame: unlinks segments from two frames ago
(the terminal has had a full frame to read them), then moves the last
frame's segments into the "previous" slot.
"""
function _kitty_shm_cleanup!()
    # Unlink the old previous generation
    for name in _KITTY_SHM_PREVIOUS
        ccall(:shm_unlink, Cint, (Cstring,), name)
    end
    empty!(_KITTY_SHM_PREVIOUS)
    # Promote current → previous
    append!(_KITTY_SHM_PREVIOUS, _KITTY_SHM_CURRENT)
    empty!(_KITTY_SHM_CURRENT)
end

"""
    _kitty_shm_cleanup_all!()

Unlink every tracked segment (both generations).
Called on TUI exit, process replacement, and atexit.
"""
function _kitty_shm_cleanup_all!()
    for name in _KITTY_SHM_PREVIOUS
        ccall(:shm_unlink, Cint, (Cstring,), name)
    end
    empty!(_KITTY_SHM_PREVIOUS)
    for name in _KITTY_SHM_CURRENT
        ccall(:shm_unlink, Cint, (Cstring,), name)
    end
    empty!(_KITTY_SHM_CURRENT)
end

atexit(_kitty_shm_cleanup_all!)

"""
    _is_ssh_session() → Bool

Detect if running inside an SSH session. Shared memory requires
the Julia process and Kitty terminal to be on the same machine.
"""
_is_ssh_session() = haskey(ENV, "SSH_CONNECTION") || haskey(ENV, "SSH_TTY")

"""
    _kitty_shm_probe!() → Bool

Test whether POSIX shared memory transmission is available.
Requires local (non-SSH) POSIX session with working shm_open.
"""
function _kitty_shm_probe!()
    cached = _KITTY_SHM_AVAILABLE[]
    cached !== nothing && return cached

    # Env override: "0" disables, "1" force-enables
    env = get(ENV, "TACHIKOMA_KITTY_SHM", "")
    if env == "0"
        _KITTY_SHM_AVAILABLE[] = false
        return false
    elseif env == "1"
        _KITTY_SHM_AVAILABLE[] = true
        return true
    end

    if Sys.iswindows() || _is_ssh_session()
        _KITTY_SHM_AVAILABLE[] = false
        return false
    end

    # Verify shm_open works by creating and immediately unlinking a probe segment
    probe_name = "/tach_probe_$(getpid())"
    # shm_open is variadic on macOS: int shm_open(const char *, int, ...)
    # Cuint... tells Julia the mode arg uses the variadic calling convention
    fd = ccall(:shm_open, Cint, (Cstring, Cint, Cuint...),
               probe_name, _O_CREAT | _O_RDWR, Cuint(0o600))
    if fd < 0
        _KITTY_SHM_AVAILABLE[] = false
        return false
    end
    ccall(:close, Cint, (Cint,), fd)
    ccall(:shm_unlink, Cint, (Cstring,), probe_name)
    _KITTY_SHM_AVAILABLE[] = true
    return true
end

"""
    _kitty_shm_write(rgb::Vector{UInt8}) → Union{String, Nothing}

Write raw RGB bytes to a POSIX shared memory segment for Kitty to read.
Returns the shm name on success, `nothing` on failure.

Each call gets a unique name via a monotonic counter.  The name is
tracked in `_KITTY_SHM_CURRENT` for deferred cleanup (see
`_kitty_shm_cleanup!`).

Uses `ccall(:memcpy, ...)` for the copy — this is opaque to Julia's
compiler and prevents dead store elimination of writes to mmap'd memory.
"""
function _kitty_shm_write(rgb::Vector{UInt8})
    nbytes = length(rgb)
    idx = (_KITTY_SHM_COUNTER[] += UInt32(1))
    name = "/tach_k$(getpid())_$(idx)"

    # shm_open is variadic on macOS: int shm_open(const char *, int, ...)
    fd = ccall(:shm_open, Cint, (Cstring, Cint, Cuint...),
               name, _O_CREAT | _O_RDWR, Cuint(0o600))
    fd < 0 && return nothing

    ret = ccall(:ftruncate, Cint, (Cint, Int64), fd, nbytes)
    if ret != 0
        ccall(:close, Cint, (Cint,), fd)
        ccall(:shm_unlink, Cint, (Cstring,), name)
        return nothing
    end

    ptr = ccall(:mmap, Ptr{Nothing},
                (Ptr{Nothing}, Csize_t, Cint, Cint, Cint, Int64),
                C_NULL, nbytes, _PROT_READ | _PROT_WRITE, _MAP_SHARED, fd, 0)
    if ptr == _MAP_FAILED
        ccall(:close, Cint, (Cint,), fd)
        ccall(:shm_unlink, Cint, (Cstring,), name)
        return nothing
    end

    # Use ccall(:memcpy) — opaque to Julia's compiler, prevents dead store
    # elimination of writes to mmap'd memory (unsafe_copyto! can be optimized away)
    GC.@preserve rgb begin
        ccall(:memcpy, Ptr{Nothing}, (Ptr{Nothing}, Ptr{Nothing}, Csize_t),
              ptr, pointer(rgb), nbytes)
    end

    ccall(:msync, Cint, (Ptr{Nothing}, Csize_t, Cint), ptr, nbytes, _MS_SYNC)
    ccall(:munmap, Cint, (Ptr{Nothing}, Csize_t), ptr, nbytes)
    ccall(:close, Cint, (Cint,), fd)

    push!(_KITTY_SHM_CURRENT, name)
    return name
end

"""
    encode_kitty(pixels::Matrix{ColorRGBA};
                 decay=DecayParams(), tick=0, cols=0, rows=0) → Vector{UInt8}

Encode a pixel matrix as a Kitty graphics protocol APC sequence.

Uses `a=T` (transmit + display), `q=2` (suppress OK). Pixels with `a==0x00`
are transparent (`f=32` RGBA); if all pixels are opaque, uses `f=24` (RGB).
Passes `s=width,v=height` for pixel dimensions and `c=cols,r=rows` for
cell placement when provided.

Returns `UInt8[]` for all-transparent images.
"""
function encode_kitty(pixels::Matrix{ColorRGBA};
                      decay::DecayParams=DecayParams(), tick::Int=0,
                      cols::Int=0, rows::Int=0)
    h, w = size(pixels)
    (h == 0 || w == 0) && return UInt8[]

    needs_decay = decay.decay > 0.0
    if needs_decay
        enc_buf = _KITTY_ENC_BUF[]
        if size(enc_buf) != (h, w)
            enc_buf = Matrix{ColorRGBA}(undef, h, w)
            _KITTY_ENC_BUF[] = enc_buf
        end
        copyto!(enc_buf, pixels)
        npix = h * w
        decay_step = npix > 500_000 ? max(1, round(Int, sqrt(npix / 500_000))) : 1
        apply_decay_subsampled!(enc_buf, decay, tick, decay_step)
        src = enc_buf
    else
        src = pixels
    end

    # Skip all-transparent frames
    any(px -> px.a > 0x00, src) || return UInt8[]

    # Use RGBA (f=32) when any transparent pixels exist, RGB (f=24) otherwise
    has_alpha = any(px -> px.a < 0xff, src)
    bpp = has_alpha ? 4 : 3
    nbytes = h * w * bpp

    # Transpose to row-major layout (Kitty expects top-to-bottom, left-to-right)
    xbuf = _KITTY_XPOSE_BUF[]
    if size(xbuf) != (w, h)
        xbuf = Matrix{ColorRGBA}(undef, w, h)
        _KITTY_XPOSE_BUF[] = xbuf
    end
    permutedims!(xbuf, src, (2, 1))

    # Copy transposed pixels to contiguous Vector{UInt8}
    rgb = _KITTY_RGB_BUF[]
    if length(rgb) < nbytes
        rgb = Vector{UInt8}(undef, nbytes)
        _KITTY_RGB_BUF[] = rgb
    end
    resize!(rgb, nbytes)
    if has_alpha
        idx = 1
        @inbounds for i in eachindex(xbuf)
            px = xbuf[i]
            rgb[idx]     = px.r
            rgb[idx + 1] = px.g
            rgb[idx + 2] = px.b
            rgb[idx + 3] = px.a
            idx += 4
        end
    else
        # All opaque — write RGB only (3 bytes per pixel)
        idx = 1
        @inbounds for i in eachindex(xbuf)
            px = xbuf[i]
            rgb[idx]     = px.r
            rgb[idx + 1] = px.g
            rgb[idx + 2] = px.b
            idx += 3
        end
    end

    # Reuse IOBuffer across frames
    io = _KITTY_IO
    truncate(io, 0)

    fmt = has_alpha ? 32 : 24

    # ── Shared memory path (t=s): write rgb to shm, Kitty reads and unlinks ──
    shm_name = _kitty_shm_probe!() ? _kitty_shm_write(rgb) : nothing

    if shm_name !== nothing
        b64_name = base64encode(shm_name)
        header = "a=T,f=$(fmt),t=s,q=2,s=$(w),v=$(h),S=$(nbytes)"
        if cols > 0
            header *= ",c=$(cols)"
        end
        if rows > 0
            header *= ",r=$(rows)"
        end
        write(io, "\e_G")
        write(io, header, ",m=0;")
        write(io, b64_name)
        write(io, "\e\\")
    else
        # ── Inline fallback (t=d): zlib + base64 + chunking ──
        compressed = transcode(_KITTY_ZLIB_CODEC, rgb)
        b64 = base64encode(compressed)

        header = "a=T,f=$(fmt),o=z,q=2,s=$(w),v=$(h)"
        if cols > 0
            header *= ",c=$(cols)"
        end
        if rows > 0
            header *= ",r=$(rows)"
        end

        chunk_size = 4096
        total = length(b64)
        offset = 1

        while offset <= total
            chunk_end = min(offset + chunk_size - 1, total)
            is_last = chunk_end >= total
            chunk = SubString(b64, offset, chunk_end)

            write(io, "\e_G")
            if offset == 1
                write(io, header, is_last ? ",m=0;" : ",m=1;")
            else
                write(io, is_last ? "m=0;" : "m=1;")
            end
            write(io, chunk)
            write(io, "\e\\")

            offset = chunk_end + 1
        end
    end

    take!(io)
end

"""
    encode_kitty_rgba(rgba::Vector{UInt8}, w::Int, h::Int; cols=0, rows=0) -> Vector{UInt8}

Encode pre-built RGBA pixel data for kitty graphics protocol.
`rgba` must be `w * h * 4` bytes in row-major order (top-to-bottom, left-to-right).
Alpha channel is preserved for transparency compositing.
"""
function encode_kitty_rgba(rgba::Vector{UInt8}, w::Int, h::Int;
                           cols::Int=0, rows::Int=0, z::Int=-1)
    nbytes = w * h * 4
    length(rgba) < nbytes && return UInt8[]
    (w == 0 || h == 0) && return UInt8[]

    io = _KITTY_IO
    truncate(io, 0)

    z_str = ",z=$(z)"
    shm_name = _kitty_shm_probe!() ? _kitty_shm_write(rgba) : nothing

    if shm_name !== nothing
        b64_name = base64encode(shm_name)
        header = "a=T,f=32,t=s,q=2,s=$(w),v=$(h),S=$(nbytes)$(z_str)"
        cols > 0 && (header *= ",c=$(cols)")
        rows > 0 && (header *= ",r=$(rows)")
        write(io, "\e_G")
        write(io, header, ",m=0;")
        write(io, b64_name)
        write(io, "\e\\")
    else
        compressed = transcode(_KITTY_ZLIB_CODEC, rgba)
        b64 = base64encode(compressed)
        header = "a=T,f=32,o=z,q=2,s=$(w),v=$(h)$(z_str)"
        cols > 0 && (header *= ",c=$(cols)")
        rows > 0 && (header *= ",r=$(rows)")

        chunk_size = 4096
        total = length(b64)
        offset = 1
        while offset <= total
            chunk_end = min(offset + chunk_size - 1, total)
            is_last = chunk_end >= total
            chunk = SubString(b64, offset, chunk_end)
            write(io, "\e_G")
            if offset == 1
                write(io, header, is_last ? ",m=0;" : ",m=1;")
            else
                write(io, is_last ? "m=0;" : "m=1;")
            end
            write(io, chunk)
            write(io, "\e\\")
            offset = chunk_end + 1
        end
    end

    take!(io)
end
