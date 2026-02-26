# ═══════════════════════════════════════════════════════════════════════
# Event hierarchy
# ═══════════════════════════════════════════════════════════════════════

abstract type Event end

@enum KeyAction key_press key_repeat key_release

struct KeyEvent <: Event
    key::Symbol
    char::Char
    action::KeyAction
end

# ── Mouse types ──────────────────────────────────────────────────────

@enum MouseButton mouse_left mouse_middle mouse_right mouse_none mouse_scroll_up mouse_scroll_down
@enum MouseAction mouse_press mouse_release mouse_drag mouse_move

struct MouseEvent <: Event
    x::Int          # 1-based column
    y::Int          # 1-based row
    button::MouseButton
    action::MouseAction
    shift::Bool
    alt::Bool
    ctrl::Bool
end

struct TaskEvent{T} <: Event
    id::Symbol
    value::T
end

KeyEvent(key::Symbol, char::Char) = KeyEvent(key, char, key_press)
KeyEvent(key::Symbol) = KeyEvent(key, '\0', key_press)
KeyEvent(c::Char) = KeyEvent(:char, c, key_press)
KeyEvent(key::Symbol, action::KeyAction) = KeyEvent(key, '\0', action)
KeyEvent(c::Char, action::KeyAction) = KeyEvent(:char, c, action)

# ═══════════════════════════════════════════════════════════════════════
# Key state tracking ── infer key_repeat from terminals that send
# repeats as plain bytes instead of CSI u with event_type=2.
# ═══════════════════════════════════════════════════════════════════════

const _KEYS_DOWN = Set{Tuple{Symbol,Char}}()

"""
    _track_key_state!(evt::KeyEvent) -> KeyEvent

Update key-down tracking and reclassify press→repeat when appropriate.
If a key_press arrives for a key already in _KEYS_DOWN (no release seen),
it's a repeat from a terminal sending raw bytes for held keys.
"""
function _track_key_state!(evt::KeyEvent)
    id = (evt.key, evt.char)
    if evt.action == key_press
        if id in _KEYS_DOWN
            return KeyEvent(evt.key, evt.char, key_repeat)
        end
        push!(_KEYS_DOWN, id)
    elseif evt.action == key_release
        delete!(_KEYS_DOWN, id)
    end
    return evt
end

function reset_key_state!()
    empty!(_KEYS_DOWN)
end

# ═══════════════════════════════════════════════════════════════════════
# Input ── libuv-driven stdin reading (no background task)
# ═══════════════════════════════════════════════════════════════════════

const INPUT_ACTIVE = Ref(false)

# Override input IO for remote TTY rendering. When nothing (the default),
# functions fall back to the live `stdin` global — critical because in MCP
# server contexts stdin is a pipe at module-load time but becomes the real
# terminal by the time a TUI runs (via /dev/tty redirection or similar).
const INPUT_IO = Ref{Union{IO,Nothing}}(nothing)

_input_io() = something(INPUT_IO[], stdin)

function start_input!()
    INPUT_ACTIVE[] = true
    reset_key_state!()
    io = _input_io()
    if io isa Base.LibuvStream
        Base.start_reading(io)
    end
    nothing
end

function stop_input!()
    INPUT_ACTIVE[] = false
    io = _input_io()
    if io isa Base.LibuvStream
        try Base.stop_reading(io) catch end
    end
    # Drain any stale bytes left in the input buffer
    while bytesavailable(io) > 0
        read(io, UInt8)
    end
    nothing
end

function read_byte(timeout_s::Float64=0.05)
    INPUT_ACTIVE[] || return nothing
    io = _input_io()
    deadline = time() + timeout_s
    while time() < deadline
        bytesavailable(io) > 0 && return read(io, UInt8)
        sleep(0.001)
    end
    return nothing
end

function poll_event(timeout_s::Float64=0.033)
    INPUT_ACTIVE[] || return nothing
    io = _input_io()
    deadline = time() + timeout_s
    while true
        remaining = deadline - time()
        remaining <= 0.0 && break
        if bytesavailable(io) > 0
            evt = read_event()
            return evt isa KeyEvent ? _track_key_state!(evt) : evt
        end
        if remaining > 0.004
            sleep(0.002)          # coarse sleep when far from deadline
        elseif remaining > 0.001
            yield()               # just yield to scheduler when close
        else
            break                 # spin-wait threshold: exit and let caller proceed
        end
    end
    return nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Event parsing
# ═══════════════════════════════════════════════════════════════════════

function read_event()
    io = _input_io()
    bytesavailable(io) == 0 && return KeyEvent(:unknown)
    byte = read(io, UInt8)
    byte == 0x1b && return read_escape()
    byte == 0x0d && return KeyEvent(:enter)
    byte == 0x7f && return KeyEvent(:backspace)
    byte == 0x08 && return KeyEvent(:backspace)
    byte == 0x09 && return KeyEvent(:tab)
    byte == 0x03 && return KeyEvent(:ctrl_c)
    byte < 0x20  && return KeyEvent(:ctrl, Char(byte + 0x60))
    return KeyEvent(Char(byte))
end

function read_escape()
    b = read_byte(0.05)
    b === nothing && return KeyEvent(:escape)
    b == UInt8('[') && return read_csi()
    b == UInt8('O') && return read_ss3()
    return KeyEvent(:escape)
end

function read_csi()
    params = UInt8[]
    while true
        b = read_byte(0.05)
        b === nothing && return KeyEvent(:escape)
        if b >= 0x40 && b <= 0x7e
            return csi_to_key(params, Char(b))
        end
        push!(params, b)
        length(params) > 16 && return KeyEvent(:unknown)
    end
end

function read_ss3()
    b = read_byte(0.05)
    b === nothing && return KeyEvent(:escape)
    # Application cursor key mode: \eOA/B/C/D for arrow keys
    Char(b) == 'A' && return KeyEvent(:up)
    Char(b) == 'B' && return KeyEvent(:down)
    Char(b) == 'C' && return KeyEvent(:right)
    Char(b) == 'D' && return KeyEvent(:left)
    Char(b) == 'P' && return KeyEvent(:f1)
    Char(b) == 'Q' && return KeyEvent(:f2)
    Char(b) == 'R' && return KeyEvent(:f3)
    Char(b) == 'S' && return KeyEvent(:f4)
    return KeyEvent(:unknown)
end

function csi_to_key(params::Vector{UInt8}, final::Char)
    # Kitty keyboard protocol: CSI ... u
    final == 'u' && return parse_kitty_key(params)
    # SGR mouse: ESC [ < Cb ; Cx ; Cy M/m
    if !isempty(params) && params[1] == UInt8('<') && (final == 'M' || final == 'm')
        return parse_sgr_mouse(params, final)
    end
    # Arrow/nav keys — extract action for Kitty event type support
    action = _extract_action_from_params(params)
    final == 'A' && return KeyEvent(:up, action)
    final == 'B' && return KeyEvent(:down, action)
    final == 'C' && return KeyEvent(:right, action)
    final == 'D' && return KeyEvent(:left, action)
    final == 'H' && return KeyEvent(:home, action)
    final == 'F' && return KeyEvent(:end_key, action)
    final == 'Z' && return KeyEvent(:backtab, action)
    # F1-F4: sent as CSI P/Q/R/S when Kitty protocol upgrades SS3 sequences
    final == 'P' && return KeyEvent(:f1, action)
    final == 'Q' && return KeyEvent(:f2, action)
    final == 'R' && return KeyEvent(:f3, action)
    final == 'S' && return KeyEvent(:f4, action)
    if final == '~' && !isempty(params)
        n = parse_csi_num(params)
        n == 2  && return KeyEvent(:insert, action)
        n == 3  && return KeyEvent(:delete, action)
        n == 5  && return KeyEvent(:pageup, action)
        n == 6  && return KeyEvent(:pagedown, action)
        n == 11 && return KeyEvent(:f1, action)
        n == 12 && return KeyEvent(:f2, action)
        n == 13 && return KeyEvent(:f3, action)
        n == 14 && return KeyEvent(:f4, action)
        n == 15 && return KeyEvent(:f5, action)
        n == 17 && return KeyEvent(:f6, action)
        n == 18 && return KeyEvent(:f7, action)
        n == 19 && return KeyEvent(:f8, action)
        n == 20 && return KeyEvent(:f9, action)
        n == 21 && return KeyEvent(:f10, action)
        n == 23 && return KeyEvent(:f11, action)
        n == 24 && return KeyEvent(:f12, action)
    end
    # Log unknown CSI sequences for debugging
    _log_unknown_csi(params, final)
    return KeyEvent(:unknown)
end

# Debug log for unrecognized CSI sequences (ring buffer, last 20)
const _UNKNOWN_CSI_LOG = Vector{String}()
function _log_unknown_csi(params::Vector{UInt8}, final::Char)
    entry = "CSI $(join(string.(params), ",")) $(final) (params_str=$(repr(String(copy(params)))))"
    push!(_UNKNOWN_CSI_LOG, entry)
    length(_UNKNOWN_CSI_LOG) > 20 && popfirst!(_UNKNOWN_CSI_LOG)
end

# ═══════════════════════════════════════════════════════════════════════
# SGR mouse parsing  (ESC [ < Cb ; Cx ; Cy M/m)
# ═══════════════════════════════════════════════════════════════════════

function parse_sgr_mouse(params::Vector{UInt8}, final::Char)
    # params includes leading '<', strip it
    str = String(params[2:end])
    parts = Base.split(str, ';')
    length(parts) == 3 || return KeyEvent(:unknown)
    cb = tryparse(Int, parts[1])
    cx = tryparse(Int, parts[2])
    cy = tryparse(Int, parts[3])
    (cb === nothing || cx === nothing || cy === nothing) && return KeyEvent(:unknown)

    # Decode modifiers from bits 2,3,4 of Cb
    shift = (cb & 4) != 0
    alt   = (cb & 8) != 0
    ctrl  = (cb & 16) != 0

    # Strip modifier bits for button decoding
    base = cb & ~(4 | 8 | 16)

    # Decode button and action
    is_release = (final == 'm')

    if base in (0, 1, 2)
        # Normal press: 0=left, 1=middle, 2=right
        btn = base == 0 ? mouse_left : base == 1 ? mouse_middle : mouse_right
        action = is_release ? mouse_release : mouse_press
    elseif base in (32, 33, 34)
        # Drag: 32=left, 33=middle, 34=right (base + 32)
        btn = base == 32 ? mouse_left : base == 33 ? mouse_middle : mouse_right
        action = mouse_drag
    elseif base == 64
        btn = mouse_scroll_up
        action = mouse_press
    elseif base == 65
        btn = mouse_scroll_down
        action = mouse_press
    elseif base == 35
        btn = mouse_none
        action = mouse_move
    else
        return KeyEvent(:unknown)
    end

    MouseEvent(cx, cy, btn, action, shift, alt, ctrl)
end

function parse_csi_num(params::Vector{UInt8})
    # Extract only leading digits (stop at first non-digit: ';', ':', etc.)
    digits = UInt8[]
    for p in params
        p >= 0x30 && p <= 0x39 || break
        push!(digits, p)
    end
    isempty(digits) && return 0
    try parse(Int, String(digits)) catch; 0 end
end

# ═══════════════════════════════════════════════════════════════════════
# Kitty keyboard protocol parsing  (CSI keycode ; modifiers:event_type u)
# ═══════════════════════════════════════════════════════════════════════

# Functional keycodes from the Kitty spec (57344+)
const KITTY_FUNCTIONAL_KEYS = Dict{Int, Symbol}(
    57344 => :escape,     57345 => :enter,      57346 => :tab,
    57347 => :backspace,  57348 => :insert,      57349 => :delete,
    57350 => :left,       57351 => :right,       57352 => :up,
    57353 => :down,       57354 => :pageup,      57355 => :pagedown,
    57356 => :home,       57357 => :end_key,
    57358 => :caps_lock,  57359 => :scroll_lock, 57360 => :num_lock,
    57361 => :print_screen, 57362 => :pause,     57363 => :menu,
    # F1-F12
    57364 => :f1,  57365 => :f2,  57366 => :f3,  57367 => :f4,
    57368 => :f5,  57369 => :f6,  57370 => :f7,  57371 => :f8,
    57372 => :f9,  57373 => :f10, 57374 => :f11, 57375 => :f12,
    # F13-F35
    57376 => :f13, 57377 => :f14, 57378 => :f15, 57379 => :f16,
    57380 => :f17, 57381 => :f18, 57382 => :f19, 57383 => :f20,
    57384 => :f21, 57385 => :f22, 57386 => :f23, 57387 => :f24,
    57388 => :f25, 57389 => :f26, 57390 => :f27, 57391 => :f28,
    57392 => :f29, 57393 => :f30, 57394 => :f31, 57395 => :f32,
    57396 => :f33, 57397 => :f34, 57398 => :f35,
    # Keypad
    57399 => :kp_0, 57400 => :kp_1, 57401 => :kp_2, 57402 => :kp_3,
    57403 => :kp_4, 57404 => :kp_5, 57405 => :kp_6, 57406 => :kp_7,
    57407 => :kp_8, 57408 => :kp_9, 57409 => :kp_decimal,
    57410 => :kp_divide, 57411 => :kp_multiply, 57412 => :kp_subtract,
    57413 => :kp_add, 57414 => :kp_enter, 57415 => :kp_equal,
    57416 => :kp_separator, 57417 => :kp_left, 57418 => :kp_right,
    57419 => :kp_up, 57420 => :kp_down, 57421 => :kp_pageup,
    57422 => :kp_pagedown, 57423 => :kp_home, 57424 => :kp_end,
    57425 => :kp_insert, 57426 => :kp_delete, 57427 => :kp_begin,
    # Media keys
    57428 => :media_play, 57429 => :media_pause, 57430 => :media_play_pause,
    57431 => :media_reverse, 57432 => :media_stop, 57433 => :media_fast_forward,
    57434 => :media_rewind, 57435 => :media_next, 57436 => :media_prev,
    57437 => :media_record, 57438 => :media_vol_down, 57439 => :media_vol_up,
    57440 => :media_mute,
    # Modifier keys (pressed alone)
    57441 => :left_shift, 57442 => :left_ctrl, 57443 => :left_alt,
    57444 => :left_super, 57445 => :left_hyper, 57446 => :left_meta,
    57447 => :right_shift, 57448 => :right_ctrl, 57449 => :right_alt,
    57450 => :right_super, 57451 => :right_hyper, 57452 => :right_meta,
)

# US keyboard shift+symbol map: base char → shifted char.
# Used as a fallback when the terminal doesn't supply the shifted codepoint.
const _SHIFT_SYMBOL_MAP = Dict{Char,Char}(
    '`'  => '~', '1' => '!', '2' => '@', '3' => '#', '4' => '$', '5' => '%',
    '6'  => '^', '7' => '&', '8' => '*', '9' => '(', '0' => ')',
    '-'  => '_', '=' => '+', '[' => '{', ']' => '}', '\\' => '|',
    ';'  => ':', '\'' => '"', ',' => '<', '.' => '>', '/' => '?',
)

# Legacy control byte mapping for Ctrl+non-letter keys.
# Maps keycode → control byte that legacy terminals actually send.
# Most follow keycode & 0x1f, but some (like /) are terminal conventions.
const _CTRL_KEYCODE_TO_BYTE = Dict{Int, UInt8}(
    Int('@')  => 0x00,  # Ctrl+@ → NUL
    Int('[')  => 0x1b,  # Ctrl+[ → ESC
    Int('\\') => 0x1c,  # Ctrl+\ → FS
    Int(']')  => 0x1d,  # Ctrl+] → GS
    Int('^')  => 0x1e,  # Ctrl+^ → RS
    Int('_')  => 0x1f,  # Ctrl+_ → US
    Int('/')  => 0x1f,  # Ctrl+/ → US (terminal convention, same as Ctrl+_)
)

"""
    parse_kitty_key(params::Vector{UInt8}) -> KeyEvent

Parse a CSI u sequence from the Kitty keyboard protocol.
Format: `keycode[;[modifiers][:event_type]]u`
"""
function parse_kitty_key(params::Vector{UInt8})
    str = String(copy(params))

    # Split on ';' → [keycode_part, modifier_part]
    parts = Base.split(str, ';')
    keycode_str = parts[1]

    # keycode_part may have ':shifted_key[:base_layout_key]' sub-params
    keycode_parts = Base.split(keycode_str, ':')
    keycode = tryparse(Int, keycode_parts[1])
    keycode === nothing && return KeyEvent(:unknown)
    # Shifted codepoint: the actual character produced with shift held
    shifted_keycode = length(keycode_parts) >= 2 ? tryparse(Int, keycode_parts[2]) : nothing

    # Parse modifiers and event type from second field
    raw_mod = 1      # 1-based: 1 = no modifiers
    event_type = 1   # 1 = press (default if omitted)
    if length(parts) >= 2
        mod_str = parts[2]
        mod_parts = Base.split(mod_str, ':')
        if !isempty(mod_parts[1])
            raw_mod = something(tryparse(Int, mod_parts[1]), 1)
        end
        if length(mod_parts) >= 2
            event_type = something(tryparse(Int, mod_parts[2]), 1)
        end
    end

    # Decode modifiers (subtract 1 from 1-based value, then bitmask)
    mod_bits = raw_mod - 1
    shift = (mod_bits & 1) != 0
    alt   = (mod_bits & 2) != 0
    ctrl  = (mod_bits & 4) != 0

    # Decode action
    action = event_type == 2 ? key_repeat : event_type == 3 ? key_release : key_press

    # Prefer the shifted codepoint provided by Kitty when shift is active
    effective_keycode = (shift && shifted_keycode !== nothing && shifted_keycode > 0) ?
                        shifted_keycode : keycode
    return _kitty_keycode_to_event(effective_keycode, shift, alt, ctrl, action)
end

function _kitty_keycode_to_event(keycode::Int, shift::Bool, alt::Bool, ctrl::Bool, action::KeyAction)
    # Ctrl combinations → replicate legacy terminal behavior
    if ctrl && !alt
        if keycode == Int('c') && !shift
            return KeyEvent(:ctrl_c, action)
        elseif keycode == Int(' ') && !shift
            return KeyEvent(:ctrl_space, action)
        elseif !shift && keycode >= Int('a') && keycode <= Int('z')
            return KeyEvent(:ctrl, Char(keycode), action)
        elseif !shift
            # Ctrl+non-letter: look up legacy control byte
            ctrl_byte = get(_CTRL_KEYCODE_TO_BYTE, keycode, nothing)
            if ctrl_byte !== nothing
                mapped = ctrl_byte == 0x00 ? '\0' : Char(ctrl_byte + 0x60)
                return KeyEvent(:ctrl, mapped, action)
            end
        end
    end

    # Shift+Tab → backtab (replicate legacy CSI Z)
    if shift && !alt && !ctrl && keycode == 9
        return KeyEvent(:backtab, action)
    end

    # Functional keycodes (57344+)
    sym = get(KITTY_FUNCTIONAL_KEYS, keycode, nothing)
    sym !== nothing && return KeyEvent(sym, action)

    # Standard keycodes that map to symbols
    keycode == 27  && return KeyEvent(:escape, action)
    keycode == 13  && return KeyEvent(:enter, action)
    keycode == 9   && return KeyEvent(:tab, action)
    keycode == 127 && return KeyEvent(:backspace, action)

    # Printable characters
    if keycode >= 32 && keycode <= 0x10FFFF
        c = Char(keycode)
        # Apply shift: uppercase letters, or map symbols via US keyboard layout
        if shift && !ctrl && !alt
            if c >= 'a' && c <= 'z'
                c = uppercase(c)
            else
                c = get(_SHIFT_SYMBOL_MAP, c, c)
            end
        end
        isvalid(c) && return KeyEvent(:char, c, action)
    end

    return KeyEvent(:unknown, action)
end

"""
    _extract_action_from_params(params) -> KeyAction

Extract event type from CSI params that may contain colon-separated
`modifiers:event_type` format (Kitty protocol extension on legacy sequences).
Returns `key_press` when no event type is present (legacy terminals).
"""
function _extract_action_from_params(params::Vector{UInt8})
    isempty(params) && return key_press
    str = String(copy(params))
    # The modifier field is after the last ';' and may contain ':event_type'
    parts = Base.split(str, ';')
    length(parts) < 2 && return key_press
    mod_str = parts[end]
    colon_parts = Base.split(mod_str, ':')
    length(colon_parts) < 2 && return key_press
    et = tryparse(Int, colon_parts[2])
    et === nothing && return key_press
    return et == 2 ? key_repeat : et == 3 ? key_release : key_press
end
