# ═══════════════════════════════════════════════════════════════════════
# ANSI escape sequences
# ═══════════════════════════════════════════════════════════════════════

const ALT_SCREEN_ON  = "\e[?1049h"
const ALT_SCREEN_OFF = "\e[?1049l"
const CURSOR_HIDE    = "\e[?25l"
const CURSOR_SHOW    = "\e[?25h"
const CLEAR_SCREEN   = "\e[2J"
const CLEAR_SCROLLBACK = "\e[2J\e[3J"  # clear screen + scrollback (frees iTerm2 sixel memory)
const SYNC_START     = "\e[?2026h"     # begin synchronized update (terminal buffers output)
const SYNC_END       = "\e[?2026l"     # end synchronized update (terminal renders atomically)
const MOUSE_ON       = "\e[?1000h\e[?1002h\e[?1006h"   # basic + button-event + SGR
const MOUSE_OFF      = "\e[?1000l\e[?1002l\e[?1006l"

# Kitty keyboard protocol: push mode with flags
# Bit 0 (1): Disambiguate escape codes
# Bit 1 (2): Report event types (press/repeat/release)
# Bit 3 (8): Report all keys as escape codes
const KITTY_FLAGS           = 11   # 1 + 2 + 8
const KITTY_KEYBOARD_ON     = "\e[>$(KITTY_FLAGS)u"
const KITTY_KEYBOARD_OFF    = "\e[<u"
const KITTY_KEYBOARD_QUERY  = "\e[?u"

# ═══════════════════════════════════════════════════════════════════════
# Raw mode ── direct POSIX via libuv
# ═══════════════════════════════════════════════════════════════════════

function set_raw_mode!(raw::Bool)
    stdin isa Base.TTY || return
    ccall(:uv_tty_set_mode, Cint,
          (Ptr{Cvoid}, Cint), stdin.handle, raw ? 1 : 0)
end


function terminal_size()
    # Use stdout if it's a real TTY, otherwise fall back to the saved
    # INPUT_IO (real stdin before any redirects), then current stdin.
    # This handles TUI mode where stdout is a capture pipe and stdin
    # may be redirected to a REPL widget's PTY slave.
    io = if stdout isa Base.TTY
        stdout
    elseif INPUT_IO[] isa Base.TTY
        INPUT_IO[]
    elseif stdin isa Base.TTY
        stdin
    else
        stdin  # last resort — displaysize will use fallback
    end
    sz = displaysize(io)
    (rows=sz[1], cols=sz[2])
end

# ═══════════════════════════════════════════════════════════════════════
# Terminal ── double-buffered rendering engine
# ═══════════════════════════════════════════════════════════════════════

mutable struct Terminal
    buffers::Vector{Buffer}
    current::Int
    size::Rect
    mouse_enabled::Bool
    had_gfx::Bool
    prev_gfx_bounds::Vector{NTuple{4,Int}}   # (row, col, width, height) from last frame
    frame_count::Int                            # monotonic frame counter
    clear_interval::Int                         # frames between periodic clears (e.g. 300 ≈ 5s @60fps)
    recorder::CastRecorder                      # .cast recording (Ctrl+R toggle)
    io::IO                                      # output IO (default stdout; set to saved fd when stdout is redirected)
    kitty_keyboard::Bool                        # true if Kitty keyboard protocol is active
    graphics_protocol::GraphicsProtocol         # detected graphics protocol (sixel/kitty/none)
    remote_tty_path::Union{String,Nothing}      # path to remote TTY (nothing = local); enables periodic size polling
end

function Terminal(; io::IO = stdout, size = nothing, remote_tty_path::Union{String,Nothing} = nothing)
    sz = something(size, terminal_size())
    rect = Rect(1, 1, sz.cols, sz.rows)
    Terminal([Buffer(rect), Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, CastRecorder(), io, false, gfx_none, remote_tty_path)
end

# Query terminal dimensions from an arbitrary TTY path using `stty size`.
function _tty_size(path::String)
    try
        out = readchomp(pipeline(`stty size`, stdin = open(path, "r")))
        parts = Base.split(out)
        length(parts) == 2 || return (rows = 24, cols = 80)
        rows = parse(Int, parts[1])
        cols = parse(Int, parts[2])
        rows > 0 && cols > 0 ? (rows = rows, cols = cols) : (rows = 24, cols = 80)
    catch
        (rows = 24, cols = 80)
    end
end

function toggle_mouse!(t::Terminal)
    t.mouse_enabled = !t.mouse_enabled
    print(t.io, t.mouse_enabled ? MOUSE_ON : MOUSE_OFF)
    Base.flush(t.io)
end

current_buf(t::Terminal) = t.buffers[t.current]
previous_buf(t::Terminal) = t.buffers[3 - t.current]

# ── Graphics regions ── raster data overlaid on character grid ────────
# (GraphicsRegion struct is defined in cast_recorder.jl, included before this file)

# ── Frame ── render target for one draw cycle ─────────────────────────

# PixelSnapshot type alias is defined in cast_recorder.jl (included before this file)

struct Frame
    buffer::Buffer
    area::Rect
    gfx_regions::Vector{GraphicsRegion}
    pixel_snapshots::Vector{PixelSnapshot}
end

frame_area(f::Frame) = f.area

function render!(f::Frame, widget, rect::Rect)
    render(widget, rect, f.buffer)
end

# ── Pixel helpers (no heavy deps) ─────────────────────────────────────

# Pixels per terminal cell (w × h). Auto-detected at TUI startup, fallback 8×16.
const CELL_PX = Ref((w=8, h=16))

# Total text area pixel dimensions and the cell grid at detection time.
# Used by PixelCanvas for proportional pixel sizing (avoids per-cell rounding).
const TEXT_AREA_PX = Ref((w=0, h=0))
const TEXT_AREA_CELLS = Ref((w=0, h=0))

# Sixel pixel scale factors. Manual fallback when XTSMGRAPHICS is unavailable.
# Set via LocalPreferences.toml: sixel_scale_w, sixel_scale_h.
const SIXEL_SCALE = Ref((w=1.0, h=1.0))

# Actual sixel rendering pixel dimensions (from XTSMGRAPHICS query).
# When (w=0, h=0), XTSMGRAPHICS was not available and we fall back to
# TEXT_AREA_PX (possibly scaled by SIXEL_SCALE).
const SIXEL_AREA_PX = Ref((w=0, h=0))

"""
    detect_cell_pixels!()

Detect terminal cell pixel dimensions. Tries in order:
1. LocalPreferences.toml override (`cell_pixel_w`, `cell_pixel_h`)
2. TIOCGWINSZ ioctl (no terminal I/O needed)
3. `\\e[16t` escape sequence (cell size report)
4. `\\e[14t` escape sequence (text area report)

Then queries XTSMGRAPHICS (`\\e[?2;1;0S`) for the actual sixel
rendering pixel dimensions. This is critical because many terminals
report logical pixels via ioctl/escape sequences but render sixel
at device pixel resolution (e.g. macOS Retina).

Updates `CELL_PX[]`, `TEXT_AREA_PX[]`, `TEXT_AREA_CELLS[]`, and
`SIXEL_AREA_PX[]`.
Falls back to defaults `(w=8, h=16)` if all methods fail.
"""
function detect_cell_pixels!()
    _load_sixel_scale!()
    _detect_cell_pixels_prefs!() && (_detect_sixel_geometry!(); return)
    _detect_cell_pixels_ioctl!() && (_detect_sixel_geometry!(); return)
    _detect_cell_pixels_escape!()
    _detect_sixel_geometry!()
end

"""
    _load_sixel_scale!()

Load sixel pixel scale factors from LocalPreferences.toml.
Set via: `sixel_scale_w` and `sixel_scale_h` keys (Float64, default 1.0).

Compensates for terminals that report logical pixel dimensions via
escape sequences / ioctl but render sixel graphics at device-pixel
resolution (common on macOS Retina displays).
"""
function _load_sixel_scale!()
    sw = Float64(@load_preference("sixel_scale_w", 1.0))
    sh = Float64(@load_preference("sixel_scale_h", 1.0))
    SIXEL_SCALE[] = (w=sw, h=sh)
end

"""
    _detect_sixel_geometry!()

Query the actual sixel rendering pixel dimensions via XTSMGRAPHICS
(`\\e[?2;1;0S`). This is the definitive way to determine sixel pixel
geometry — it returns the real rendering dimensions regardless of
DPI scaling, font size, or terminal coordinate system quirks.

Supported by WezTerm, xterm, foot, mlterm, and other sixel-capable
terminals. Falls back gracefully (SIXEL_AREA_PX stays at (0,0)) on
terminals that don't respond.

Updates `SIXEL_AREA_PX[]`.
"""
function _detect_sixel_geometry!()
    @static Sys.iswindows() && return
    # Try via /dev/tty (works even when stdin/stdout are redirected)
    # O_RDWR=2, O_NONBLOCK=4 on macOS (0x800 on Linux)
    o_nonblock = @static (Sys.isapple() || Sys.isbsd()) ? 0x0004 : 0x0800
    tty_fd = ccall(:open, Cint, (Cstring, Cint), "/dev/tty", 2 | o_nonblock)
    tty_fd == -1 && return

    try
        # Save terminal settings
        old_termios = zeros(UInt8, 64)
        ccall(:tcgetattr, Cint, (Cint, Ptr{UInt8}), tty_fd, old_termios)

        # Set raw mode
        raw_termios = copy(old_termios)
        ccall(:cfmakeraw, Cvoid, (Ptr{UInt8},), raw_termios)
        ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}), tty_fd, 0, raw_termios)

        # Drain stale input (non-blocking, so won't hang)
        drain_buf = zeros(UInt8, 256)
        while ccall(:read, Cssize_t, (Cint, Ptr{UInt8}, Csize_t),
                     tty_fd, drain_buf, 256) > 0
        end

        # Send XTSMGRAPHICS query: Pi=2 (sixel geometry), Pa=1 (read)
        query = Vector{UInt8}(codeunits("\e[?2;1;0S"))
        ccall(:write, Cssize_t, (Cint, Ptr{UInt8}, Csize_t),
               tty_fd, query, length(query))

        # Read response: \e[?2;0;W;HS (poll with non-blocking reads)
        response = UInt8[]
        deadline = time() + 0.5
        buf = zeros(UInt8, 1)
        while time() < deadline
            n = ccall(:read, Cssize_t, (Cint, Ptr{UInt8}, Csize_t),
                       tty_fd, buf, 1)
            if n > 0
                push!(response, buf[1])
                buf[1] == UInt8('S') && break
            else
                sleep(0.002)
            end
        end

        # Restore terminal settings
        ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}), tty_fd, 0, old_termios)

        # Parse response
        str = String(response)
        m = match(r"\e\[\?2;0;(\d+);(\d+)S", str)
        m === nothing && return
        sw = parse(Int, m.captures[1])
        sh = parse(Int, m.captures[2])
        (sw > 0 && sh > 0) || return
        SIXEL_AREA_PX[] = (w=sw, h=sh)
    catch
        # Non-fatal: SIXEL_AREA_PX stays at (0,0)
    finally
        ccall(:close, Cint, (Cint,), tty_fd)
    end
end

function _set_cell_pixel_info!(pixel_w::Int, pixel_h::Int,
                                cols::Int, rows::Int)
    (pixel_w > 0 && pixel_h > 0 && cols > 0 && rows > 0) || return false
    TEXT_AREA_PX[] = (w=pixel_w, h=pixel_h)
    TEXT_AREA_CELLS[] = (w=cols, h=rows)
    cw = clamp(pixel_w ÷ cols, 1, 64)
    ch = clamp(pixel_h ÷ rows, 1, 64)
    CELL_PX[] = (w=cw, h=ch)
    true
end

function _set_cell_pixel_direct!(cw::Int, ch::Int)
    (cw > 0 && ch > 0) || return false
    sz = terminal_size()
    (sz.rows > 0 && sz.cols > 0) || return false
    CELL_PX[] = (w=cw, h=ch)
    TEXT_AREA_PX[] = (w=cw * sz.cols, h=ch * sz.rows)
    TEXT_AREA_CELLS[] = (w=sz.cols, h=sz.rows)
    true
end

"""
    _detect_cell_pixels_prefs!() → Bool

Check LocalPreferences.toml for manual cell pixel dimensions.
Set via: `cell_pixel_w` and `cell_pixel_h` keys.
"""
function _detect_cell_pixels_prefs!()
    cw = @load_preference("cell_pixel_w", 0)
    ch = @load_preference("cell_pixel_h", 0)
    (cw > 0 && ch > 0) || return false
    _set_cell_pixel_direct!(cw, ch)
end

"""
    _detect_cell_pixels_ioctl!() → Bool

Use TIOCGWINSZ ioctl to get pixel dimensions from the kernel.
Tries stdin, stdout, and /dev/tty.
"""
function _detect_cell_pixels_ioctl!()
    @static Sys.iswindows() && return false
    tiocgwinsz = @static (Sys.isapple() || Sys.isbsd()) ? 0x40087468 : 0x5413
    # ioctl is variadic on macOS/BSD — the third arg must use `...` in the ccall
    # signature so ARM64 passes it in the correct register (stack vs register ABI).
    for fd_source in (:stdin, :stdout, :devtty)
        try
            buf = zeros(UInt16, 4)
            GC.@preserve buf begin
                p = pointer(buf)
                if fd_source === :devtty
                    tty_fd = ccall(:open, Cint, (Cstring, Cint), "/dev/tty", 0)
                    tty_fd == -1 && continue
                    ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...),
                                 tty_fd, tiocgwinsz, p)
                    ccall(:close, Cint, (Cint,), tty_fd)
                    ret == -1 && continue
                else
                    fd = fd_source === :stdin ? 0 : 1
                    ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...),
                                 fd, tiocgwinsz, p)
                    ret == -1 && continue
                end
            end
            rows, cols, xpixel, ypixel = Int(buf[1]), Int(buf[2]), Int(buf[3]), Int(buf[4])
            (xpixel == 0 || ypixel == 0) && continue
            return _set_cell_pixel_info!(xpixel, ypixel, cols, rows)
        catch
            continue
        end
    end
    false
end

"""
    _detect_cell_pixels_escape!()

Query terminal via escape sequences. Tries:
- `\\e[16t` → cell size (ESC [ 6 ; h ; w t) — most direct
- `\\e[14t` → text area pixels (ESC [ 4 ; h ; w t) — fallback

Temporarily enters raw mode to read responses.
"""
function _detect_cell_pixels_escape!()
    stdin isa Base.TTY || return

    set_raw_mode!(true)
    Base.start_reading(stdin)

    # Drain stale bytes
    while bytesavailable(stdin) > 0
        read(stdin, UInt8)
    end

    # Send both queries — terminal will respond to whichever it supports.
    # \e[16t → ESC[6;h;w t  (cell pixel size)
    # \e[14t → ESC[4;h;w t  (text area pixel size)
    print(stdout, "\e[16t\e[14t")
    Base.flush(stdout)

    # Collect all responses
    deadline = time() + 0.5
    response = UInt8[]
    t_count = 0
    while time() < deadline
        if bytesavailable(stdin) > 0
            b = read(stdin, UInt8)
            push!(response, b)
            if b == UInt8('t')
                t_count += 1
                t_count >= 2 && break  # got both responses
            end
        else
            sleep(0.002)
        end
    end

    Base.stop_reading(stdin)

    while bytesavailable(stdin) > 0
        read(stdin, UInt8)
    end

    set_raw_mode!(false)

    str = String(response)

    # Try \e[16t response first (cell size — most direct)
    m16 = match(r"\e\[6;(\d+);(\d+)t", str)
    if m16 !== nothing
        ch = parse(Int, m16.captures[1])
        cw = parse(Int, m16.captures[2])
        if _set_cell_pixel_direct!(cw, ch)
            return
        end
    end

    # Fall back to \e[14t response (text area)
    m14 = match(r"\e\[4;(\d+);(\d+)t", str)
    m14 === nothing && return

    pixel_h = parse(Int, m14.captures[1])
    pixel_w = parse(Int, m14.captures[2])

    sz = terminal_size()
    _set_cell_pixel_info!(pixel_w, pixel_h, sz.cols, sz.rows)
end

# ── Kitty keyboard protocol detection ────────────────────────────────

"""
    _detect_kitty_keyboard!(io::IO) -> Bool

Query terminal for Kitty keyboard protocol support via `CSI ? u`.
Writes query to `io` (should be the terminal output, e.g. /dev/tty),
reads response from the input stream. Returns true if terminal responds
with `CSI ? flags u`. Must be called after raw mode and start_input!().
"""
function _detect_kitty_keyboard!(io::IO)
    inp = _input_io()
    # Drain stale bytes
    while bytesavailable(inp) > 0
        read(inp, UInt8)
    end

    print(io, KITTY_KEYBOARD_QUERY)
    Base.flush(io)

    # Collect response with 100ms timeout
    response = UInt8[]
    deadline = time() + 0.1
    while time() < deadline
        if bytesavailable(inp) > 0
            b = read(inp, UInt8)
            push!(response, b)
            b == UInt8('u') && break
        else
            sleep(0.002)
        end
    end

    # Drain any remaining response bytes
    while bytesavailable(inp) > 0
        read(inp, UInt8)
    end

    str = String(response)
    return occursin(r"\e\[\?\d*u", str)
end

# ── Kitty graphics protocol detection ─────────────────────────────────

"""
    _detect_kitty_graphics!(io::IO) -> Bool

Query terminal for Kitty graphics protocol support by sending a
minimal 1×1 query image (`a=q,t=d,f=24`) with a unique id (`i=31`).
Returns true if the terminal responds with `_G` and `i=31`.
Must be called after raw mode and start_input!().
"""
function _detect_kitty_graphics!(io::IO)
    inp = _input_io()
    # Drain stale bytes
    while bytesavailable(inp) > 0
        read(inp, UInt8)
    end

    # Send query: 1×1 pixel, direct data, query action, suppress display
    # AAAA = base64 of a single black pixel (3 bytes RGB → 4 bytes base64)
    print(io, "\e_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\e\\")
    Base.flush(io)

    # Collect response with 100ms timeout
    response = UInt8[]
    deadline = time() + 0.1
    while time() < deadline
        if bytesavailable(inp) > 0
            b = read(inp, UInt8)
            push!(response, b)
            # Response ends with ESC \ (ST)
            if length(response) >= 2 &&
               response[end-1] == UInt8('\e') && b == UInt8('\\')
                break
            end
        else
            sleep(0.002)
        end
    end

    # Drain any remaining response bytes — some terminals (e.g. iTerm)
    # send multiple responses; wait briefly for stragglers to arrive
    drain_deadline = time() + 0.05
    while time() < drain_deadline
        if bytesavailable(inp) > 0
            read(inp, UInt8)
        else
            sleep(0.002)
        end
    end

    str = String(response)
    return occursin("_G", str) && occursin("i=31", str)
end

"""
    pixel_size(area::Rect) → (w, h)

Estimate pixel dimensions for a character Rect.
"""
pixel_size(area::Rect) = (area.width * CELL_PX[].w, area.height * CELL_PX[].h)

"""
    cell_pixels() → (w, h)

Return the pixel dimensions of a single terminal cell.
"""
cell_pixels() = CELL_PX[]

"""
    text_area_pixels() → (w, h)

Return the total text area pixel dimensions detected at TUI startup.
"""
text_area_pixels() = TEXT_AREA_PX[]

"""
    text_area_cells() → (w, h)

Return the cell grid dimensions detected at TUI startup.
"""
text_area_cells() = TEXT_AREA_CELLS[]

"""
    sixel_scale() → (w, h)

Return the sixel pixel scale factors (from LocalPreferences.toml).
"""
sixel_scale() = SIXEL_SCALE[]

"""
    sixel_area_pixels() → (w, h)

Return the actual sixel rendering pixel dimensions (from XTSMGRAPHICS).
Returns `(w=0, h=0)` if not available.
"""
sixel_area_pixels() = SIXEL_AREA_PX[]

"""
    render_graphics!(f::Frame, data::Vector{UInt8}, area::Rect;
                     pixels::Union{Matrix{ColorRGB}, Nothing}=nothing,
                     format::GraphicsFormat=gfx_fmt_sixel)

Place pre-encoded raster data (sixel or Kitty) into the frame,
reserving the character buffer area with blanks. When `pixels` is
provided, the pixel matrix is stored for raster export (GIF/APNG).
"""
function render_graphics!(f::Frame, data::Vector{UInt8}, area::Rect;
                          pixels::Union{Matrix{ColorRGBA}, Matrix{ColorRGB}, Nothing}=nothing,
                          format::GraphicsFormat=gfx_fmt_sixel)
    # Blank cells directly (bypass set_char! which preserves old bg)
    buf = f.buffer
    for row in area.y:bottom(area)
        for col in area.x:right(area)
            in_bounds(buf, col, row) || continue
            @inbounds buf.content[buf_index(buf, col, row)] = _GFX_BLANK
        end
    end
    push!(f.gfx_regions, GraphicsRegion(area.y, area.x, area.width, area.height, data, format))
    if pixels !== nothing
        rgba_pixels = if pixels isa Matrix{ColorRGBA}
            pixels
        else
            ColorRGBA.(pixels, 0xff)
        end
        push!(f.pixel_snapshots, (area.y, area.x, rgba_pixels))
    end
    nothing
end


# ── Virtual Framebuffer for sixel compositing ─────────────────────────
#
# A full-screen RGBA pixel buffer. During view(), each render_rgba! call
# alpha-blends into this buffer. After view() returns, dirty regions are
# encoded as sixel and emitted — giving proper compositing, transparency,
# and z-ordering without kitty's native layer support.

mutable struct PixelFramebuffer
    rgba::Vector{UInt8}      # flat RGBA, row-major (w pixels per row)
    width::Int               # pixels
    height::Int              # pixels
    dirty::Bool
    dirty_x0::Int            # pixel bounding box of dirty region
    dirty_y0::Int
    dirty_x1::Int
    dirty_y1::Int
    # Per-render cell rects for separate sixel emission
    render_rects::Vector{Rect}
end

const _PIXEL_FB = PixelFramebuffer(UInt8[], 0, 0, false, 0, 0, 0, 0, Rect[])

"""Clear/resize framebuffer, filling with cell background colors from the buffer."""
function _fb_init!(fb::PixelFramebuffer, buf::Buffer, area::Rect)
    cp = CELL_PX[]
    cpw = max(1, cp.w)
    cph = max(1, cp.h)
    pw = area.width * cpw
    ph = area.height * cph
    nbytes = pw * ph * 4

    if fb.width != pw || fb.height != ph || length(fb.rgba) != nbytes
        fb.rgba = Vector{UInt8}(undef, nbytes)
        fb.width = pw
        fb.height = ph
    end

    # Fill with transparent black — pixels that are never written won't be encoded
    fill!(fb.rgba, 0x00)

    fb.dirty = false
    empty!(fb.render_rects)
    fb.dirty_x0 = pw + 1
    fb.dirty_y0 = ph + 1
    fb.dirty_x1 = 0
    fb.dirty_y1 = 0
end

"""Blend RGBA image into the framebuffer at the given cell position."""
function _fb_blend!(fb::PixelFramebuffer, rgba::Vector{UInt8}, w::Int, h::Int,
                    area::Rect, screen_area::Rect, buf::Buffer)
    cp = CELL_PX[]
    cpw = max(1, cp.w)
    cph = max(1, cp.h)
    fbw = fb.width
    fbh = fb.height

    x_off = (area.x - screen_area.x) * cpw
    y_off = (area.y - screen_area.y) * cph
    dst_w = area.width * cpw
    dst_h = area.height * cph

    GC.@preserve fb rgba begin
        src_ptr = pointer(rgba)
        dst_ptr = pointer(fb.rgba)

        # Scale source (w × h) to destination (dst_w × dst_h)
        for dsy in 1:dst_h
            dy = y_off + dsy
            (dy < 1 || dy > fbh) && continue
            # Map destination row to source row
            sy = clamp(round(Int, (dsy - 0.5) / dst_h * h + 0.5), 1, h)
            for dsx in 1:dst_w
                dx = x_off + dsx
                (dx < 1 || dx > fbw) && continue
                # Map destination col to source col
                sx = clamp(round(Int, (dsx - 0.5) / dst_w * w + 0.5), 1, w)
                si = ((sy - 1) * w + (sx - 1)) * 4

                r = unsafe_load(src_ptr, si + 1)
                g = unsafe_load(src_ptr, si + 2)
                b = unsafe_load(src_ptr, si + 3)
                a = unsafe_load(src_ptr, si + 4)

                a == 0x00 && continue

                dp = dst_ptr + ((dy - 1) * fbw + (dx - 1)) * 4

                if a == 0xff
                    unsafe_store!(dp, r, 1)
                    unsafe_store!(dp, g, 2)
                    unsafe_store!(dp, b, 3)
                    unsafe_store!(dp, 0xff, 4)
                else
                    da = unsafe_load(dp, 4)
                    if da == 0x00
                        unsafe_store!(dp, r, 1)
                        unsafe_store!(dp, g, 2)
                        unsafe_store!(dp, b, 3)
                        unsafe_store!(dp, a, 4)
                    else
                        af = a / 255.0
                        inv_af = 1.0 - af
                        unsafe_store!(dp, unsafe_trunc(UInt8, min(r * af + unsafe_load(dp, 1) * inv_af, 255.0)), 1)
                        unsafe_store!(dp, unsafe_trunc(UInt8, min(g * af + unsafe_load(dp, 2) * inv_af, 255.0)), 2)
                        unsafe_store!(dp, unsafe_trunc(UInt8, min(b * af + unsafe_load(dp, 3) * inv_af, 255.0)), 3)
                        unsafe_store!(dp, unsafe_trunc(UInt8, min(da + a * inv_af, 255.0)), 4)
                    end
                end
            end
        end
    end

    # Expand dirty region (in pixels)
    x0 = x_off + 1
    y0 = y_off + 1
    x1 = min(x_off + dst_w, fbw)
    y1 = min(y_off + dst_h, fbh)
    fb.dirty = true
    push!(fb.render_rects, area)
    fb.dirty_x0 = min(fb.dirty_x0, x0)
    fb.dirty_y0 = min(fb.dirty_y0, y0)
    fb.dirty_x1 = max(fb.dirty_x1, x1)
    fb.dirty_y1 = max(fb.dirty_y1, y1)
    # Record this window's cell rect for separate sixel emission
end

"""Encode dirty framebuffer region as sixel and emit as graphics."""
function _fb_flush!(fb::PixelFramebuffer, f::Frame, screen_area::Rect)
    fb.dirty || return

    cp = CELL_PX[]
    cpw = max(1, cp.w)
    cph = max(1, cp.h)
    fbw = fb.width
    buf = f.buffer
    sw = screen_area.width
    sh = screen_area.height

    # Step 1: Build text mask — true means "text here, don't cover with sixel"
    # Only non-space characters count as text. Styled spaces (e.g. background
    # fills from Block/FloatingWindow) are visual chrome that sixel can safely
    # cover — the pixel content IS the intended content for those cells.
    # Border chars (│─┌ etc.), titles, labels, and braille dots are all
    # non-space and will be preserved.
    text_mask = Matrix{Bool}(undef, sh, sw)
    @inbounds for row in 1:sh
        for col in 1:sw
            cr = screen_area.y + row - 1
            cc = screen_area.x + col - 1
            if in_bounds(buf, cc, cr)
                cell = buf.content[buf_index(buf, cc, cr)]
                text_mask[row, col] = cell.char != ' '
            else
                text_mask[row, col] = false
            end
        end
    end

    # Close single-space gaps within text runs on each row — spaces inside
    # titles like "Spiral (opaque)" should be protected, not covered by sixel.
    # Only fills gaps of exactly 1 space between two text cells.
    @inbounds for row in 1:sh
        for col in 2:(sw - 1)
            if !text_mask[row, col] && text_mask[row, col - 1] && text_mask[row, col + 1]
                text_mask[row, col] = true
            end
        end
    end

    # Step 2: Build pixel_mask from render_rects — any cell that was targeted
    # by render_rgba! should get sixel coverage, even if pixels are transparent.
    # This prevents flicker on transparent-background plots where the content
    # moves between frames (old sixel persists, new has gaps → flash).
    pixel_mask = falses(sh, sw)
    @inbounds for rr in fb.render_rects
        r0 = max(1, rr.y - screen_area.y + 1)
        r1 = min(sh, rr.y + rr.height - 1 - screen_area.y + 1)
        c0 = max(1, rr.x - screen_area.x + 1)
        c1 = min(sw, rr.x + rr.width - 1 - screen_area.x + 1)
        for row in r0:r1, col in c0:c1
            pixel_mask[row, col] = true
        end
    end

    # Step 3: Sixel-ok cells = targeted by render_rgba! AND no text on top
    sixel_ok = pixel_mask .& .!text_mask

    # Zero framebuffer pixels where text exists, preventing pixel leakage
    # at sixel rectangle boundaries (e.g. window title over behind-window pixels)
    @inbounds for row in 1:sh
        for col in 1:sw
            text_mask[row, col] || continue
            px_x0 = (col - 1) * cpw + 1
            px_y0 = (row - 1) * cph + 1
            for py in px_y0:min(px_y0 + cph - 1, fb.height)
                for px in px_x0:min(px_x0 + cpw - 1, fb.width)
                    di = ((py - 1) * fbw + (px - 1)) * 4
                    fb.rgba[di + 1] = 0x00
                    fb.rgba[di + 2] = 0x00
                    fb.rgba[di + 3] = 0x00
                    fb.rgba[di + 4] = 0x00
                end
            end
        end
    end

    # Step 4: Find maximal horizontal runs of sixel-ok cells per row,
    # then merge vertically where runs align — forming rectangles.
    # Simple greedy: scan row by row, emit horizontal strips.
    # Each strip becomes its own sixel image.
    emitted = falses(sh, sw)
    @inbounds for row in 1:sh
        col = 1
        while col <= sw
            if sixel_ok[row, col] && !emitted[row, col]
                # Found start of a run — extend right
                col_end = col
                while col_end < sw && sixel_ok[row, col_end + 1] && !emitted[row, col_end + 1]
                    col_end += 1
                end
                # Extend down while the same column range is all sixel-ok
                row_end = row
                while row_end < sh
                    all_ok = true
                    for c in col:col_end
                        if !sixel_ok[row_end + 1, c] || emitted[row_end + 1, c]
                            all_ok = false
                            break
                        end
                    end
                    all_ok || break
                    row_end += 1
                end
                # Mark as emitted
                for r in row:row_end, c in col:col_end
                    emitted[r, c] = true
                end
                # Extract pixel data for this rectangle
                rect_w = col_end - col + 1
                rect_h = row_end - row + 1
                px_x0 = (col - 1) * cpw + 1
                px_y0 = (row - 1) * cph + 1
                pw = rect_w * cpw
                ph = rect_h * cph
                px_x1 = min(px_x0 + pw - 1, fb.width)
                px_y1 = min(px_y0 + ph - 1, fb.height)
                aw = px_x1 - px_x0 + 1
                ah = px_y1 - px_y0 + 1

                # Extract pixels, replacing transparent with canvas bg so
                # every sixel is fully opaque — eliminates flash on redraw.
                cbg = canvas_bg()
                pixels = Matrix{ColorRGBA}(undef, ah, aw)
                @inbounds for dy in 1:ah
                    for dx in 1:aw
                        di = ((px_y0 + dy - 2) * fbw + (px_x0 + dx - 2)) * 4
                        a = fb.rgba[di + 4]
                        if a == 0x00
                            pixels[dy, dx] = cbg
                        else
                            pixels[dy, dx] = ColorRGBA(
                                fb.rgba[di + 1], fb.rgba[di + 2],
                                fb.rgba[di + 3], a)
                        end
                    end
                end

                data = encode_sixel(pixels)
                if !isempty(data)
                    cell_rect = Rect(screen_area.x + col - 1, screen_area.y + row - 1,
                                     rect_w, rect_h)
                    render_graphics!(f, data, cell_rect; pixels=pixels, format=gfx_fmt_sixel)
                end

                col = col_end + 1
            else
                col += 1
            end
        end
    end
end

# ── render_rgba! — public API ─────────────────────────────────────────

"""
    render_rgba!(f::Frame, rgba::Vector{UInt8}, w::Int, h::Int, area::Rect;
                 cols::Int=area.width, rows::Int=area.height, z::Int=-1,
                 scale_to_cells::Bool=true)

Render RGBA pixel data into a Frame. On kitty, uses native RGBA with z-index
for layered compositing. On sixel, blends into a virtual framebuffer that
gets composited and encoded at frame end. Pixels with `(0,0,0,0)` are
transparent and will not be rendered.

`rgba` must be `w * h * 4` bytes in row-major order (top-to-bottom, left-to-right).
"""
function render_rgba!(f::Frame, rgba::Vector{UInt8}, w::Int, h::Int, area::Rect;
                      cols::Int=area.width, rows::Int=area.height, z::Int=-1,
                      scale_to_cells::Bool=true)
    gfx = GRAPHICS_PROTOCOL[]
    gfx == gfx_none && return

    if gfx == gfx_kitty
        c = scale_to_cells ? cols : 0
        r = scale_to_cells ? rows : 0
        data = encode_kitty_rgba(rgba, w, h; cols=c, rows=r, z=z)
        isempty(data) && return
        render_graphics!(f, data, area; format=gfx_fmt_kitty)
    else
        # Sixel: blend into the virtual framebuffer.
        # _fb_flush! encodes and emits after view() returns.
        _fb_blend!(_PIXEL_FB, rgba, w, h, area, f.area, f.buffer)
    end
end
# ── Recording badge (drawn after capture, so it's on-screen only) ─────

function _draw_rec_badge!(buf::Buffer, area::Rect)
    label = "● REC"
    rx = right(area) - length(label)
    rx < area.x && return
    set_string!(buf, rx, area.y, label,
                Style(fg=ColorRGB(0xff, 0x40, 0x40), bold=true);
                max_x=right(area))
end

# ── Draw / Flush ──────────────────────────────────────────────────────

function draw!(func::Function, t::Terminal)
    _kitty_shm_cleanup!()   # unlink previous frame's shm segments (terminal has had a full frame to read them)
    resized = check_resize!(t)
    t.frame_count += 1
    f = Frame(current_buf(t), t.size, GraphicsRegion[], PixelSnapshot[])
    # Initialize the pixel framebuffer for sixel compositing
    if t.graphics_protocol != gfx_kitty
        _fb_init!(_PIXEL_FB, current_buf(t), t.size)
    end
    func(f)
    # Flush sixel framebuffer — encode dirty regions
    if t.graphics_protocol != gfx_kitty && _PIXEL_FB.dirty
        _fb_flush!(_PIXEL_FB, f, t.size)
    end
    # Capture frame for .cast recording BEFORE the REC badge is drawn,
    # so the badge appears on-screen but not in the recording.
    if t.recorder.active
        capture_frame!(t.recorder, current_buf(t), t.size.width, t.size.height;
                       gfx_regions=f.gfx_regions, pixel_snapshots=f.pixel_snapshots)
        _draw_rec_badge!(current_buf(t), t.size)
    end
    # Filter graphics regions: skip any where a later widget wrote content on top.
    # render_graphics! blanks cells to (' ', RESET); if any cell differs, something
    # rendered over the graphics area (e.g. a modal) and we must not emit the sixel.
    buf = current_buf(t)
    # Skip the visibility filter when using the framebuffer compositor
    # (kitty handles z-order natively, sixel framebuffer handles compositing).
    # Only use the filter for non-framebuffer sixel rendering (e.g. PixelImage).
    visible_regions = if t.graphics_protocol == gfx_kitty || _PIXEL_FB.dirty
        f.gfx_regions
    else
        _filter_visible_gfx(f.gfx_regions, buf)
    end
    has_gfx = !isempty(visible_regions)
    # Accumulate all output into a single IOBuffer so the terminal receives
    # clear + character redraw + graphics data in one write (no intermediate
    # blank-screen render → no flash).
    io = IOBuffer()
    write(io, SYNC_START)
    has_sixel = any(r -> r.format == gfx_fmt_sixel, visible_regions)
    if resized
        # Terminal was resized: clear screen inside the sync block to avoid a
        # blank-screen flash between the clear and the redrawn content.
        write(io, CLEAR_SCREEN)
        reset!(previous_buf(t))
    elseif t.frame_count % t.clear_interval == 0 && has_sixel && !_PIXEL_FB.dirty
        # Periodic clear: cap iTerm2 sixel memory growth by clearing the
        # screen AND scrollback buffer.  \e[3J frees iTerm2's accumulated
        # sixel image objects.  Skip when using the virtual framebuffer
        # (it overwrites sixel data each frame anyway).
        write(io, CLEAR_SCROLLBACK)
        reset!(previous_buf(t))
    elseif t.had_gfx && !has_gfx
        # Graphics were active last frame but not this one — clear the graphics
        # layer by erasing the screen, then force a full character redraw.
        write(io, CLEAR_SCREEN)
        reset!(previous_buf(t))
    elseif !isempty(t.prev_gfx_bounds)
        # Force-dirty cells that were graphics-covered last frame but aren't
        # this frame.  The diff would otherwise skip them (both buffers
        # contain SIXEL_BLANK), leaving stale graphics pixels on screen.
        _dirty_stale_gfx!(previous_buf(t), buf, t.prev_gfx_bounds, visible_regions)
    end
    flush!(t, io)
    # Kitty: unlike sixel, writing characters does NOT clear placed images.
    # Issue delete-all inside the sync block so stale images from a previous
    # frame (different positions after a zoom/layout change) are removed
    # atomically before the new images are placed — no visible flash.
    if t.graphics_protocol == gfx_kitty && (has_gfx || t.had_gfx)
        write(io, "\e_Ga=d,d=a,q=2\e\\")
    end
    flush_gfx!(visible_regions, io)
    write(io, SYNC_END)
    write(t.io, take!(io))
    Base.flush(t.io)
    t.had_gfx = has_gfx
    t.prev_gfx_bounds = [(r.row, r.col, r.width, r.height) for r in visible_regions]
    swap_buffers!(t)
end

const _GFX_BLANK = Cell(' ', RESET)

"""
    _filter_visible_gfx(regions, buf) → Vector{GraphicsRegion}

Return only graphics regions whose reserved cell area has not been
overwritten by later widget rendering. A region is occluded if any
cell in its area differs from the blank (' ', RESET) that
`render_graphics!` placed there.
"""
function _filter_visible_gfx(regions::Vector{GraphicsRegion}, buf::Buffer)
    isempty(regions) && return regions
    filter(regions) do r
        for row in r.row:(r.row + r.height - 1)
            for col in r.col:(r.col + r.width - 1)
                in_bounds(buf, col, row) || continue
                @inbounds c = buf.content[buf_index(buf, col, row)]
                c == _GFX_BLANK || return false
            end
        end
        true
    end
end

"""
    _dirty_stale_gfx!(prev, cur, old_bounds, new_regions)

Force cells that were sixel-covered last frame but not this frame to
appear changed in the diff, so `flush!` re-emits them.  Writing any
character to a cell clears the terminal's sixel layer at that position.
"""
function _dirty_stale_gfx!(prev::Buffer, cur::Buffer,
                             old_bounds::Vector{NTuple{4,Int}},
                             new_regions::Vector{GraphicsRegion})
    for (orow, ocol, ow, oh) in old_bounds
        for row in orow:(orow + oh - 1)
            for col in ocol:(ocol + ow - 1)
                in_bounds(cur, col, row) || continue
                _in_any_gfx_region(col, row, new_regions) && continue
                i = buf_index(cur, col, row)
                @inbounds cur.content[i] == _GFX_BLANK || continue
                # Make prev differ so flush! will re-emit the space
                @inbounds prev.content[i] = Cell('\0', RESET)
            end
        end
    end
end

@inline function _in_any_gfx_region(col::Int, row::Int, regions::Vector{GraphicsRegion})
    for r in regions
        if row >= r.row && row < r.row + r.height &&
           col >= r.col && col < r.col + r.width
            return true
        end
    end
    false
end

function flush!(t::Terminal, io::IO)
    cur = current_buf(t)
    prev = previous_buf(t)

    last_style = Style()
    last_col = -1
    last_row = -1
    last_hyperlink = ""

    for row in cur.area.y:bottom(cur.area)
        for col in cur.area.x:right(cur.area)
            i = buf_index(cur, col, row)
            @inbounds cc = cur.content[i]

            # Skip wide-char continuation cells — the leading cell already
            # covers this column on the terminal.
            cc.char == WIDE_CHAR_PAD && continue

            @inbounds pc = prev.content[i]
            cc == pc && continue

            # Skip cursor move if contiguous
            if row != last_row || col != last_col + 1
                write(io, "\e[", string(row), ";",
                      string(col), "H")
            end

            if cc.style != last_style
                write_style(io, cc.style)
                last_style = cc.style
            end

            # OSC 8 hyperlinks (separate from SGR style)
            hl = cc.style.hyperlink
            if hl != last_hyperlink
                if isempty(hl)
                    write(io, "\e]8;;\e\\")
                else
                    write(io, "\e]8;;", hl, "\e\\")
                end
                last_hyperlink = hl
            end

            write(io, cc.char)
            # Wide chars advance the terminal cursor by 2 columns
            w = textwidth(cc.char)
            last_col = col + w - 1
            last_row = row
        end
    end

    # Close any open hyperlink, then reset style
    if last_col != -1
        !isempty(last_hyperlink) && write(io, "\e]8;;\e\\")
        write(io, "\e[0m")
    end
end

function flush_gfx!(regions::Vector{GraphicsRegion}, io::IO)
    for r in regions
        write(io, "\e[", string(r.row), ";", string(r.col), "H")
        write(io, r.data)
    end
end

function swap_buffers!(t::Terminal)
    other = 3 - t.current
    reset!(t.buffers[other])
    t.current = other
end

# ── Remote TTY input ─────────────────────────────────────────────────
#
# When the TUI renders to a remote TTY (tty_out parameter), we also read
# input from that TTY.  An async task pumps raw bytes from the remote fd
# into a BufferStream; INPUT_IO[] is pointed at that stream so the normal
# poll_event / read_event pipeline works unchanged.

const _REMOTE_INPUT_FD       = Ref{Int32}(-1)
const _REMOTE_INPUT_STREAM   = Ref{Union{Base.BufferStream, Nothing}}(nothing)
const _REMOTE_INPUT_TERMIOS  = Ref{Vector{UInt8}}(UInt8[])

function _start_remote_input!(path::String)
    @static Sys.iswindows() && error("Remote TTY input is not supported on Windows")
    buf = Base.BufferStream()
    # O_RDWR|O_NONBLOCK|O_NOCTTY: non-blocking so the @async reader never
    # stalls the Julia thread; O_NOCTTY prevents accidental controlling-
    # terminal acquisition (our process already owns the REPL TTY).
    o_nonblock = @static (Sys.isapple() || Sys.isbsd()) ? Cint(0x0004) : Cint(0x0800)
    o_noctty   = @static (Sys.isapple() || Sys.isbsd()) ? Cint(0x20000) : Cint(0x0400)
    fd = ccall(:open, Cint, (Cstring, Cint), path, Cint(2) | o_nonblock | o_noctty)
    fd == -1 && error("Cannot open remote TTY for input: $path")

    # Save terminal settings and switch to raw mode so we get individual
    # keypresses (no line buffering, no echo on the remote TTY).
    old_termios = zeros(UInt8, 64)
    ccall(:tcgetattr, Cint, (Cint, Ptr{UInt8}), fd, old_termios)
    raw_termios = copy(old_termios)
    ccall(:cfmakeraw, Cvoid, (Ptr{UInt8},), raw_termios)
    ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}), fd, 0, raw_termios)

    _REMOTE_INPUT_FD[]      = fd
    _REMOTE_INPUT_TERMIOS[] = old_termios
    _REMOTE_INPUT_STREAM[]  = buf

    # Pump bytes from the remote TTY fd into the BufferStream.
    # Uses poll_fd (libuv event-driven) — same pattern as PTY reader.
    eagain = @static Sys.isapple() ? Cint(35) : Cint(11)
    @async begin
        byte_buf = zeros(UInt8, 64)
        raw_fd = RawFD(fd)
        while _REMOTE_INPUT_FD[] == fd && isopen(buf)
            result = poll_fd(raw_fd, 1.0; readable=true, writable=false)
            result.readable || continue
            while true
                n = ccall(:read, Cssize_t, (Cint, Ptr{UInt8}, Csize_t), fd, byte_buf, 64)
                if n > 0
                    write(buf, @view byte_buf[1:n])
                elseif n < 0 && Base.Libc.errno() == eagain
                    break  # no more data right now
                else
                    break  # fd closed or error
                end
            end
        end
    end

    INPUT_IO[] = buf
    nothing
end

function _stop_remote_input!()
    @static Sys.iswindows() && return
    fd = _REMOTE_INPUT_FD[]
    fd == -1 && return
    _REMOTE_INPUT_FD[] = -1          # signals the reader task to stop
    buf = _REMOTE_INPUT_STREAM[]
    _REMOTE_INPUT_STREAM[] = nothing
    INPUT_IO[] = nothing             # restore: fall back to live stdin
    buf !== nothing && close(buf)    # unblocks any pending bytesavailable
    old = _REMOTE_INPUT_TERMIOS[]
    if !isempty(old)
        ccall(:tcsetattr, Cint, (Cint, Cint, Ptr{UInt8}), fd, 0, old)
        _REMOTE_INPUT_TERMIOS[] = UInt8[]
    end
    ccall(:close, Cint, (Cint,), fd)
    nothing
end

function check_resize!(t::Terminal)
    if t.remote_tty_path !== nothing
        # Remote TTY: SIGWINCH doesn't reach us, so poll periodically (once per second at 60fps).
        t.frame_count % 60 == 0 || return false
        sz = _tty_size(t.remote_tty_path)
    else
        sz = terminal_size()
    end
    new_rect = Rect(1, 1, sz.cols, sz.rows)
    new_rect == t.size && return false
    t.size = new_rect
    for buf in t.buffers
        resize_buf!(buf, new_rect)
    end
    return true  # draw! will emit CLEAR_SCREEN inside the SYNC block
end

# ── TUI mode lifecycle ────────────────────────────────────────────────

"""
    _detect_graphics_from_env() -> GraphicsProtocol

Infer graphics protocol from terminal environment variables, without
sending any escape sequences. Used as:
- Primary detection for remote TTY sessions (where probing is unsafe).
- Fast-path before probing for known terminals in local sessions.

Detection priority (kitty > sixel):
- Kitty: `TERM=xterm-kitty`, `KITTY_WINDOW_ID` set, `TERM_PROGRAM=kitty`
- Ghostty: `TERM=xterm-ghostty`, `GHOSTTY_RESOURCES_DIR` set
- WezTerm: `TERM_PROGRAM=WezTerm` → sixel (kitty support incomplete)
- iTerm2: `TERM_PROGRAM=iTerm.app` → sixel
- foot: `TERM=foot` or `TERM=foot-extra` → sixel
- mlterm: `TERM=mlterm` → sixel
"""
function _detect_graphics_from_env()
    term      = get(ENV, "TERM", "")
    term_prog = get(ENV, "TERM_PROGRAM", "")

    # Kitty: canonical env signals
    if term == "xterm-kitty" || haskey(ENV, "KITTY_WINDOW_ID") ||
            term_prog == "kitty"
        return gfx_kitty
    end
    # Ghostty: kitty graphics protocol
    if term == "xterm-ghostty" || haskey(ENV, "GHOSTTY_RESOURCES_DIR")
        return gfx_kitty
    end
    # WezTerm / iTerm2: prefer their native sixel path
    if term_prog in ("WezTerm", "iTerm.app")
        return gfx_sixel
    end
    # foot, mlterm: sixel
    if term in ("foot", "foot-extra", "mlterm", "mlterm-256color")
        return gfx_sixel
    end
    return gfx_none
end

function enter_tui!(t::Terminal; remote_tty::Bool = false)
    print(t.io, ALT_SCREEN_ON, CURSOR_HIDE, CLEAR_SCREEN)
    Base.flush(t.io)
    if remote_tty
        # Remote TTY: open the remote fd for input and set it to raw mode via
        # termios directly.  Do NOT set raw mode on the local Julia stdin —
        # that would corrupt the REPL that owns this process.
        if t.remote_tty_path !== nothing
            _start_remote_input!(t.remote_tty_path)
        end
        # Reset application cursor key mode (\e[?1l) so arrow keys arrive as
        # standard VT100 CSI sequences (\e[A etc.) rather than SS3 (\eOA etc.).
        # The shell or a previous TUI may have left the terminal in app mode.
        print(t.io, "\e[?1l", MOUSE_ON)
        Base.flush(t.io)
    else
        # Local terminal: set raw mode on stdin and enable mouse.
        set_raw_mode!(true)
        print(t.io, MOUSE_ON)
        Base.flush(t.io)
    end
    start_input!()
    if !remote_tty
        # Detect and enable Kitty keyboard protocol
        t.kitty_keyboard = _detect_kitty_keyboard!(t.io)
        if t.kitty_keyboard
            print(t.io, KITTY_KEYBOARD_ON)
            Base.flush(t.io)
        end
        # Detect graphics protocol (TACHIKOMA_GFX=kitty|sixel|none to override)
        gfx_env = lowercase(get(ENV, "TACHIKOMA_GFX", ""))
        if gfx_env == "kitty"
            t.graphics_protocol = gfx_kitty
        elseif gfx_env == "sixel"
            t.graphics_protocol = gfx_sixel
        elseif gfx_env == "none"
            t.graphics_protocol = gfx_none
        else
            # Fast path: ENV-based detection for well-known terminals avoids
            # the 100ms kitty probe round-trip (and correctly skips kitty probing
            # for WezTerm/iTerm2 which have incomplete kitty graphics support).
            env_proto = _detect_graphics_from_env()
            if env_proto != gfx_none
                t.graphics_protocol = env_proto
            else
                # Unknown terminal: probe for Kitty graphics support, then
                # fall back to sixel if the XTSMGRAPHICS query succeeded.
                kitty_gfx = _detect_kitty_graphics!(t.io)
                if kitty_gfx
                    t.graphics_protocol = gfx_kitty
                elseif SIXEL_AREA_PX[].w > 0
                    t.graphics_protocol = gfx_sixel
                else
                    t.graphics_protocol = gfx_none
                end
            end
        end
    else
        # Remote TTY: skip all terminal queries (responses would buffer in the
        # remote TTY's input and corrupt its shell after the TUI exits).
        # Honour TACHIKOMA_GFX env override first; fall back to ENV-based
        # detection which is safe to use without sending any escape sequences.
        gfx_env = lowercase(get(ENV, "TACHIKOMA_GFX", ""))
        t.graphics_protocol = if gfx_env == "kitty"
            gfx_kitty
        elseif gfx_env == "sixel"
            gfx_sixel
        elseif gfx_env == "none"
            gfx_none
        else
            _detect_graphics_from_env()
        end
    end
    GRAPHICS_PROTOCOL[] = t.graphics_protocol
    # Clear any probe artifacts (some terminals render APC/CSI probe bytes as
    # raw text) before the first TUI frame, so they don't persist on screen.
    !remote_tty && (print(t.io, CLEAR_SCREEN); Base.flush(t.io))
end

function leave_tui!(t::Terminal)
    # Send all "off" sequences up-front while libuv is still reading.
    # Order matters: turning off mouse tracking and Kitty keyboard here
    # stops the terminal from generating new input events (mouse moves,
    # key releases) during the drain window below.
    try
        seq = ""
        t.graphics_protocol == gfx_kitty && (seq *= "\e_Ga=d,d=a,q=2\e\\")
        t.kitty_keyboard                  && (seq *= KITTY_KEYBOARD_OFF)
        seq *= MOUSE_OFF
        print(t.io, seq)
        Base.flush(t.io)
    catch end

    # Sleep briefly while libuv is still active so that any events already
    # in flight (key release for the quit key, final mouse events before
    # MOUSE_OFF reaches the terminal) arrive and are pumped into Julia's
    # stdin buffer.  stop_input! then drains that buffer.
    try sleep(0.015) catch end
    try stop_input!() catch end
    if t.remote_tty_path !== nothing
        try _stop_remote_input!() catch end
    else
        try set_raw_mode!(false) catch end
    end
    try
        print(t.io, "\e[0m", CURSOR_SHOW, ALT_SCREEN_OFF)
        Base.flush(t.io)
    catch end
    GRAPHICS_PROTOCOL[] = gfx_none
    _KITTY_SHM_AVAILABLE[] = nothing
    _KITTY_SHM_COUNTER[] = UInt32(0)
    _kitty_shm_cleanup_all!()   # unlink all shm segments (pending + ring) on TUI exit
end

"""
    prepare_for_exec!()

Prepare the terminal for process replacement via `execvp`. Restores
stdin/stdout/stderr to `/dev/tty`, writes terminal restore sequences,
and exits raw mode. Works without access to the `Terminal` struct or
`CaptureState` — operates entirely at the OS fd level.

Call this immediately before `ccall(:execvp, ...)` or similar process
replacement from any context (async tasks, bridge code, etc.).
"""
function prepare_for_exec!()
    @static Sys.iswindows() && return
    # 1. Stop libuv stdin reading (before we touch fds)
    try stop_input!() catch end

    # 2. Exit raw mode while stdin is still accessible via libuv
    try set_raw_mode!(false) catch end

    # 3. Open /dev/tty — the real terminal, bypassing any pipe redirections
    tty_fd = ccall(:open, Cint, (Cstring, Cint), "/dev/tty", 2)  # O_RDWR = 2
    tty_fd == -1 && return  # not a terminal environment, nothing to restore

    try
        # 4. Write terminal restore sequences directly to /dev/tty fd
        #    Send unconditionally — harmless on terminals that don't support them
        restore = string(
            "\e_Ga=d,d=a,q=2\e\\",  # delete all Kitty images
            KITTY_KEYBOARD_OFF,       # disable Kitty keyboard protocol
            MOUSE_OFF,                # disable mouse tracking
            "\e[0m",                  # reset SGR attributes
            CURSOR_SHOW,              # show cursor
            ALT_SCREEN_OFF,           # exit alternate screen
        )
        buf = Vector{UInt8}(restore)
        ccall(:write, Cssize_t, (Cint, Ptr{UInt8}, Csize_t),
              tty_fd, buf, length(buf))

        # 5. dup2: restore stdin/stdout/stderr to the terminal
        ccall(:dup2, Cint, (Cint, Cint), tty_fd, 0)  # stdin
        ccall(:dup2, Cint, (Cint, Cint), tty_fd, 1)  # stdout
        ccall(:dup2, Cint, (Cint, Cint), tty_fd, 2)  # stderr
    finally
        # 6. Close the temporary /dev/tty fd (dup2'd copies remain open)
        ccall(:close, Cint, (Cint,), tty_fd)
    end

    # 7. Reset global graphics protocol state
    GRAPHICS_PROTOCOL[] = gfx_none
    _KITTY_SHM_AVAILABLE[] = nothing
    _KITTY_SHM_COUNTER[] = UInt32(0)

    # 8. Clean up all shm segments (pending + ring) before process replacement
    _kitty_shm_cleanup_all!()

    nothing
end

const _DISCARD_OUTPUT = (_::AbstractString) -> nothing

"""
    tty_path() → Union{String, Nothing}

Return the device path of the current terminal (e.g. `"/dev/ttys042"`).
Tries `/dev/tty` first, then falls back to `ttyname(0)` (stdin's device).
Returns `nothing` if no terminal is available (e.g. piped stdin).

Useful for passing as `tty_out` when launching a Tachikoma app inside
a PTY-spawned subprocess where `/dev/tty` may not be configured.
"""
function tty_path()
    @static Sys.iswindows() && return nothing
    try
        open(io -> close(io), "/dev/tty", "w")
        return "/dev/tty"
    catch; end
    # No controlling terminal — get the device path behind stdin
    p = ccall(:ttyname, Cstring, (Cint,), Cint(0))
    p != C_NULL ? unsafe_string(p) : nothing
end

"""
    with_terminal(f; tty_out=nothing, on_stdout=nothing, on_stderr=nothing)

Run `f(terminal)` inside the TUI lifecycle (alt screen, raw mode, mouse).

Stdout and stderr are always redirected to pipes during TUI mode to prevent
background `println()` calls from corrupting the display. Rendering goes to
`/dev/tty` directly, bypassing the redirected file descriptors.

Pass `on_stdout` / `on_stderr` callbacks to receive captured lines (e.g., for
an activity log). When no callbacks are provided, captured output is silently
discarded.

Pass `tty_out` with a path like `"/dev/ttys042"` to render into a different
terminal window than the one running the Julia process. Run `cat > /dev/null`
in the target terminal before handing off its path — this parks the shell and
absorbs any buffered input without displaying it. Input (keyboard/mouse)
continues to come from the current terminal or via synthetic events. Terminal
resize is supported via periodic size polling (once per second).
"""
function with_terminal(f::Function; tty_out=nothing, tty_size=nothing, on_stdout=nothing, on_stderr=nothing)
    # Skip pixel detection when rendering to a remote TTY — detection queries
    # the current terminal (not tty_out) and its escape-sequence responses
    # buffer up in the remote TTY's input, corrupting the shell on exit.
    tty_out === nothing && detect_cell_pixels!()
    tty_io = if tty_out !== nothing
        open(tty_out, "w")
    elseif Sys.iswindows()
        stdout
    else
        open("/dev/tty", "w")
    end
    sz = if tty_out !== nothing
        something(tty_size, _tty_size(tty_out))
    else
        terminal_size()
    end
    state = _start_capture(something(on_stdout, _DISCARD_OUTPUT),
                           something(on_stderr, _DISCARD_OUTPUT))
    t = Terminal(io = tty_io, size = sz, remote_tty_path = tty_out)
    enter_tui!(t; remote_tty = tty_out !== nothing)
    try
        f(t)
    finally
        leave_tui!(t)
        _stop_capture(state)
        tty_io !== stdout && try close(tty_io) catch end
    end
end

# ── stdout/stderr capture ────────────────────────────────────────────

struct CaptureState
    orig_stdout::Any
    orig_stderr::Any
    stdout_task::Union{Task, Nothing}
    stderr_task::Union{Task, Nothing}
    stdout_wr::Any   # pipe write-end (close to signal reader)
    stderr_wr::Any
end

function _start_capture(on_stdout, on_stderr)
    orig_stdout = nothing
    orig_stderr = nothing
    stdout_task = nothing
    stderr_task = nothing
    stdout_wr = nothing
    stderr_wr = nothing

    if on_stdout !== nothing || stdout isa Base.TTY
        orig_stdout = stdout
        rd, wr = redirect_stdout()
        stdout_wr = wr
        # `let` captures rd by value — without it, the @async closure
        # captures rd by reference, and the stderr block below would
        # reassign rd, making the stdout drain task read the wrong pipe.
        let rd = rd
            if on_stdout !== nothing
                stdout_task = @async _drain_output(rd, on_stdout)
            else
                stdout_task = @async _drain_output(rd, _ -> nothing)
            end
        end
    end

    if on_stderr !== nothing || stderr isa Base.TTY
        orig_stderr = stderr
        rd, wr = redirect_stderr()
        stderr_wr = wr
        if on_stderr !== nothing
            stderr_task = @async _drain_output(rd, on_stderr)
        else
            stderr_task = @async _drain_output(rd, _ -> nothing)
        end
    end

    CaptureState(orig_stdout, orig_stderr, stdout_task, stderr_task,
                 stdout_wr, stderr_wr)
end

function _drain_output(rd, callback)
    try
        while !eof(rd)
            data = readavailable(rd)
            isempty(data) && continue
            callback(String(data))
        end
    catch e
        e isa EOFError || e isa Base.IOError || rethrow()
    end
end

function _stop_capture(s::CaptureState)
    # Restore streams first, then close pipes so reader tasks finish
    if s.orig_stdout !== nothing
        try redirect_stdout(s.orig_stdout) catch end
    end
    if s.orig_stderr !== nothing
        try redirect_stderr(s.orig_stderr) catch end
    end
    s.stdout_wr !== nothing && try close(s.stdout_wr) catch end
    s.stderr_wr !== nothing && try close(s.stderr_wr) catch end
    s.stdout_task !== nothing && try wait(s.stdout_task) catch end
    s.stderr_task !== nothing && try wait(s.stderr_task) catch end
end
