# ═══════════════════════════════════════════════════════════════════════
# Windows console input ── ReadConsoleInputW backend
# ═══════════════════════════════════════════════════════════════════════
#
# On Windows, libuv's raw-mode TTY reader translates KEY_EVENT records to VT
# escape sequences itself but silently DROPS mouse records — so the VT-parsing
# path in events.jl never sees a mouse event (keyboard works, mouse doesn't).
# libuv's pass-through mode (RAW_VT) that would fix this isn't in Julia's bundled
# libuv. So on Windows we bypass libuv for input entirely: read INPUT_RECORDs
# directly via ReadConsoleInputW and translate them into the same KeyEvent /
# MouseEvent types the VT parser produces. The console under WezTerm/ConPTY does
# deliver full mouse records (position, buttons, wheel), so this is all we need.
#
# Gated behind TACHIKOMA_WIN_CONSOLE_INPUT while it's stabilised; once proven it
# becomes the default on Windows. No-op / never compiled into the hot path off
# Windows.

# ── Win32 constants ────────────────────────────────────────────────────
const _STD_INPUT_HANDLE = reinterpret(UInt32, Int32(-10))

# console input mode bits
const _ENABLE_PROCESSED_INPUT = 0x0001
const _ENABLE_LINE_INPUT = 0x0002
const _ENABLE_ECHO_INPUT = 0x0004
const _ENABLE_WINDOW_INPUT = 0x0008
const _ENABLE_MOUSE_INPUT = 0x0010
const _ENABLE_QUICK_EDIT_MODE = 0x0040
const _ENABLE_EXTENDED_FLAGS = 0x0080

# INPUT_RECORD event types
const _KEY_EVENT = 0x0001
const _MOUSE_EVENT = 0x0002
const _WINDOW_BUFFER_SIZE_EVENT = 0x0004

# dwControlKeyState
const _RIGHT_ALT_PRESSED = 0x0001
const _LEFT_ALT_PRESSED = 0x0002
const _RIGHT_CTRL_PRESSED = 0x0004
const _LEFT_CTRL_PRESSED = 0x0008
const _SHIFT_PRESSED = 0x0010

# dwButtonState (mouse)
const _LEFT_BTN = 0x0001
const _RIGHT_BTN = 0x0002
const _MIDDLE_BTN = 0x0004

# dwEventFlags (mouse)
const _MOUSE_MOVED = 0x0001
const _DOUBLE_CLICK = 0x0002
const _MOUSE_WHEELED = 0x0004
const _MOUSE_HWHEELED = 0x0008

# ── State ──────────────────────────────────────────────────────────────
const _WIN_INPUT_ENABLED = Ref(false)              # this backend is driving input
const _WIN_STDIN_HANDLE = Ref{Ptr{Cvoid}}(Ptr{Cvoid}(0))
const _WIN_SAVED_MODE = Ref{UInt32}(0)
const _WIN_MODE_SAVED = Ref(false)
const _WIN_MOUSE_BTN = Ref{UInt32}(0)         # previous button state, for press/release diff

"""Whether to use the ReadConsoleInputW backend — the default on Windows (it's the
only path that delivers mouse; libuv's raw reader drops mouse records). Opt out with
`TACHIKOMA_WIN_CONSOLE_INPUT=0` (or `false`/`off`/`no`) to fall back to the libuv
keyboard-only path. Always off on non-Windows."""
function _win_console_input()
    @static Sys.iswindows() || return false
    v = lowercase(strip(get(ENV, "TACHIKOMA_WIN_CONSOLE_INPUT", "")))
    return v != "0" && v != "false" && v != "off" && v != "no"
end

function _win_stdin()
    h = _WIN_STDIN_HANDLE[]
    h == Ptr{Cvoid}(0) || return h
    h = ccall((:GetStdHandle, "kernel32"), Ptr{Cvoid}, (UInt32,), _STD_INPUT_HANDLE)
    _WIN_STDIN_HANDLE[] = h
    return h
end

# Little-endian field reads out of a 20-byte INPUT_RECORD.
@inline _u16(b, i) = UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
@inline _i16(b, i) = reinterpret(Int16, _u16(b, i))
@inline _u32(b, i) =
    UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)

"""Put the console into raw + mouse mode (no line/echo/quick-edit), saving the old
mode for restore. Idempotent."""
function _win_enter_input!()
    h = _win_stdin()
    h == Ptr{Cvoid}(-1) && return false
    mref = Ref{UInt32}(0)
    ccall((:GetConsoleMode, "kernel32"), Cint, (Ptr{Cvoid}, Ptr{UInt32}), h, mref) == 0 &&
        return false
    _WIN_SAVED_MODE[] = mref[]
    _WIN_MODE_SAVED[] = true
    newmode =
        (mref[] | _ENABLE_MOUSE_INPUT | _ENABLE_EXTENDED_FLAGS | _ENABLE_WINDOW_INPUT) &
        ~UInt32(
            _ENABLE_QUICK_EDIT_MODE | _ENABLE_LINE_INPUT | _ENABLE_ECHO_INPUT |
            _ENABLE_PROCESSED_INPUT,
        )
    ccall((:SetConsoleMode, "kernel32"), Cint, (Ptr{Cvoid}, UInt32), h, newmode)
    _WIN_MOUSE_BTN[] = 0
    _WIN_INPUT_ENABLED[] = true
    return true
end

"""Restore the console mode captured by `_win_enter_input!`."""
function _win_leave_input!()
    _WIN_INPUT_ENABLED[] = false
    if _WIN_MODE_SAVED[]
        h = _win_stdin()
        h == Ptr{Cvoid}(-1) ||
            ccall((:SetConsoleMode, "kernel32"), Cint, (Ptr{Cvoid}, UInt32), h, _WIN_SAVED_MODE[])
        _WIN_MODE_SAVED[] = false
    end
    return nothing
end

"""Number of pending console input records (GetNumberOfConsoleInputEvents)."""
function _win_events_pending()
    h = _win_stdin()
    h == Ptr{Cvoid}(-1) && return 0
    nref = Ref{UInt32}(0)
    ccall((:GetNumberOfConsoleInputEvents, "kernel32"), Cint, (Ptr{Cvoid}, Ptr{UInt32}), h, nref) ==
    0 && return 0
    return Int(nref[])
end

# Decode a single mouse button bit → MouseButton.
_win_btn(bits) =
    if (bits & _LEFT_BTN) != 0
        mouse_left
    elseif (bits & _RIGHT_BTN) != 0
        mouse_right
    elseif (bits & _MIDDLE_BTN) != 0
        mouse_middle
    else
        mouse_none
    end

function _win_translate_mouse(buf)
    x = Int(_i16(buf, 5)) + 1          # console is 0-based; MouseEvent is 1-based
    y = Int(_i16(buf, 7)) + 1
    bstate = _u32(buf, 9)
    cks = _u32(buf, 13)
    flags = _u32(buf, 17)
    shift = (cks & _SHIFT_PRESSED) != 0
    alt = (cks & (_LEFT_ALT_PRESSED | _RIGHT_ALT_PRESSED)) != 0
    ctrl = (cks & (_LEFT_CTRL_PRESSED | _RIGHT_CTRL_PRESSED)) != 0

    if (flags & _MOUSE_WHEELED) != 0
        delta = reinterpret(Int16, UInt16((bstate >> 16) & 0xffff))
        btn = delta > 0 ? mouse_scroll_up : mouse_scroll_down
        return MouseEvent(x, y, btn, mouse_press, shift, alt, ctrl)
    elseif (flags & _MOUSE_HWHEELED) != 0
        delta = reinterpret(Int16, UInt16((bstate >> 16) & 0xffff))
        btn = delta > 0 ? mouse_scroll_right : mouse_scroll_left
        return MouseEvent(x, y, btn, mouse_press, shift, alt, ctrl)
    elseif (flags & _MOUSE_MOVED) != 0
        if bstate != 0
            return MouseEvent(x, y, _win_btn(bstate), mouse_drag, shift, alt, ctrl)
        end
        return MouseEvent(x, y, mouse_none, mouse_move, shift, alt, ctrl)
    else
        # Button state change: diff against the previous state → press or release.
        prev = _WIN_MOUSE_BTN[]
        _WIN_MOUSE_BTN[] = bstate
        pressed = bstate & ~prev
        released = prev & ~bstate
        if pressed != 0
            return MouseEvent(x, y, _win_btn(pressed), mouse_press, shift, alt, ctrl)
        elseif released != 0
            return MouseEvent(x, y, _win_btn(released), mouse_release, shift, alt, ctrl)
        end
        return nothing   # no button transition (e.g. a redundant record) — skip
    end
end

# Virtual-key code → Tachikoma key symbol for non-character keys.
const _WIN_VK = Dict{UInt16,Symbol}(
    0x0D => :enter,
    0x08 => :backspace,
    0x1B => :escape,
    0x25 => :left,
    0x26 => :up,
    0x27 => :right,
    0x28 => :down,
    0x24 => :home,
    0x23 => :end,
    0x21 => :page_up,
    0x22 => :page_down,
    0x2D => :insert,
    0x2E => :delete,
    0x70 => :f1,
    0x71 => :f2,
    0x72 => :f3,
    0x73 => :f4,
    0x74 => :f5,
    0x75 => :f6,
    0x76 => :f7,
    0x77 => :f8,
    0x78 => :f9,
    0x79 => :f10,
    0x7A => :f11,
    0x7B => :f12,
)

function _win_translate_key(buf)
    _u32(buf, 5) == 0 && return nothing    # bKeyDown == 0 → key-up, ignore
    vk = _u16(buf, 11)
    ch = _u16(buf, 15)
    cks = _u32(buf, 17)
    shift = (cks & _SHIFT_PRESSED) != 0
    ctrl = (cks & (_LEFT_CTRL_PRESSED | _RIGHT_CTRL_PRESSED)) != 0

    # Tab (Shift+Tab → backtab) before the generic VK map so shift is honoured.
    if vk == 0x09
        return KeyEvent(shift ? :backtab : :tab)
    end
    sym = get(_WIN_VK, vk, :nothing)
    sym === :nothing || return KeyEvent(sym)

    # Control combinations: the console reports ctrl+letter as a control char
    # (ctrl+a → 0x01). Mirror _read_event_impl: 0x03 → :ctrl_c, else :ctrl+letter.
    if ch != 0 && ch < 0x20
        ch == 0x03 && return KeyEvent(:ctrl_c)
        ch == 0x0D && return KeyEvent(:enter)
        ch == 0x09 && return KeyEvent(shift ? :backtab : :tab)
        return KeyEvent(:ctrl, Char(ch + 0x60))
    end
    # A printable character (already reflects shift/AltGr/layout from the console).
    ch >= 0x20 && return KeyEvent(Char(ch))
    return nothing   # modifier-only key press, etc. — nothing to emit
end

"""Read and translate one console input record. Returns a KeyEvent/MouseEvent, or
`nothing` for records that don't map to a Tachikoma event (key-up, resize,
no-op mouse). Blocks until a record is available."""
function _win_read_record()
    h = _win_stdin()
    h == Ptr{Cvoid}(-1) && return nothing
    buf = _WIN_RECBUF
    nref = Ref{UInt32}(0)
    ok = ccall(
        (:ReadConsoleInputW, "kernel32"),
        Cint,
        (Ptr{Cvoid}, Ptr{UInt8}, UInt32, Ptr{UInt32}),
        h,
        buf,
        UInt32(1),
        nref,
    )
    (ok == 0 || nref[] == 0) && return nothing
    et = _u16(buf, 1)
    if et == _MOUSE_EVENT
        return _win_translate_mouse(buf)
    elseif et == _KEY_EVENT
        return _win_translate_key(buf)
    elseif et == _WINDOW_BUFFER_SIZE_EVENT
        return :resize   # sentinel — the app already polls size via CONOUT$
    end
    return nothing
end

const _WIN_RECBUF = zeros(UInt8, 20)

"""Poll for one input event via the console backend, waiting up to `timeout_s`.
Skips non-event records (key-up, resize sentinel, no-op mouse)."""
function _win_poll_event(timeout_s::Float64)
    deadline = time() + timeout_s
    while true
        if _win_events_pending() > 0
            evt = _win_read_record()
            evt === :resize && continue
            evt === nothing && continue
            return evt isa KeyEvent ? _track_key_state!(evt) : evt
        end
        remaining = deadline - time()
        remaining <= 0.0 && return nothing
        remaining > 0.004 ? sleep(0.002) : yield()
    end
end
