# ═══════════════════════════════════════════════════════════════════════
# ANSI escape sequence parser ── convert SGR codes to Span styling
# ═══════════════════════════════════════════════════════════════════════

# Tagged color to avoid AbstractColor boxing during parsing.
# Only converted to AbstractColor when creating the final Style.
struct _TaggedColor
    kind::UInt8   # 0=none, 1=Color256, 2=ColorRGB
    r::UInt8
    g::UInt8
    b::UInt8
end

const _TC_NONE = _TaggedColor(0x00, 0x00, 0x00, 0x00)
_tc256(code::Int) = _TaggedColor(0x01, UInt8(code), 0x00, 0x00)
_tcrgb(r::Int, g::Int, b::Int) = _TaggedColor(0x02, UInt8(r), UInt8(g), UInt8(b))

@inline function _tc_to_color(tc::_TaggedColor)::AbstractColor
    tc.kind == 0x00 && return NoColor()
    tc.kind == 0x01 && return Color256(tc.r)
    return ColorRGB(tc.r, tc.g, tc.b)
end

# Flat mutable state — no abstract fields, no boxing
mutable struct _ParseState
    fg::_TaggedColor
    bg::_TaggedColor
    bold::Bool
    dim::Bool
    italic::Bool
    underline::Bool
    strikethrough::Bool
    reverse::Bool
end

_ParseState() = _ParseState(_TC_NONE, _TC_NONE, false, false, false, false, false, false)

@inline function _to_style(s::_ParseState)
    fg = s.reverse ? s.bg : s.fg
    bg = s.reverse ? s.fg : s.bg
    Style(_tc_to_color(fg), _tc_to_color(bg),
          s.bold, s.dim, s.italic, s.underline, s.strikethrough, "")
end

@inline function _reset!(s::_ParseState)
    s.fg = _TC_NONE
    s.bg = _TC_NONE
    s.bold = false
    s.dim = false
    s.italic = false
    s.underline = false
    s.strikethrough = false
    s.reverse = false
end

# Pre-allocated params buffer (thread-local would be ideal, but single-threaded render)
const _SGR_PARAMS = Vector{Int}(undef, 16)

# ── Manual byte-level parser ────────────────────────────────────────

# Parse a semicolon-separated integer list from bytes[start:stop] into _SGR_PARAMS.
# Returns the number of params parsed.
function _parse_sgr_params!(bytes::AbstractVector{UInt8}, start::Int, stop::Int)::Int
    n = 0
    val = 0
    has_val = false
    @inbounds for i in start:stop
        b = bytes[i]
        if b == UInt8(';')
            n += 1
            n > length(_SGR_PARAMS) && return n - 1
            _SGR_PARAMS[n] = has_val ? val : 0
            val = 0
            has_val = false
        elseif UInt8('0') <= b <= UInt8('9')
            val = val * 10 + Int(b - UInt8('0'))
            has_val = true
        end
    end
    # Last param (no trailing semicolon)
    if has_val || start <= stop
        n += 1
        n <= length(_SGR_PARAMS) && (_SGR_PARAMS[n] = has_val ? val : 0)
    end
    min(n, length(_SGR_PARAMS))
end

function _apply_sgr!(state::_ParseState, nparams::Int)
    i = 1
    @inbounds while i <= nparams
        p = _SGR_PARAMS[i]
        if p == 0
            _reset!(state)
        elseif p == 1
            state.bold = true
        elseif p == 2
            state.dim = true
        elseif p == 3
            state.italic = true
        elseif p == 4
            state.underline = true
        elseif p == 7
            state.reverse = true
        elseif p == 9
            state.strikethrough = true
        elseif p == 22
            state.bold = false
            state.dim = false
        elseif p == 23
            state.italic = false
        elseif p == 24
            state.underline = false
        elseif p == 27
            state.reverse = false
        elseif p == 29
            state.strikethrough = false
        elseif 30 <= p <= 37
            state.fg = _tc256(p - 30)
        elseif p == 38
            if i + 1 <= nparams && _SGR_PARAMS[i + 1] == 5 && i + 2 <= nparams
                state.fg = _tc256(clamp(_SGR_PARAMS[i + 2], 0, 255))
                i += 2
            elseif i + 1 <= nparams && _SGR_PARAMS[i + 1] == 2 && i + 4 <= nparams
                state.fg = _tcrgb(clamp(_SGR_PARAMS[i + 2], 0, 255),
                                  clamp(_SGR_PARAMS[i + 3], 0, 255),
                                  clamp(_SGR_PARAMS[i + 4], 0, 255))
                i += 4
            end
        elseif p == 39
            state.fg = _TC_NONE
        elseif 40 <= p <= 47
            state.bg = _tc256(p - 40)
        elseif p == 48
            if i + 1 <= nparams && _SGR_PARAMS[i + 1] == 5 && i + 2 <= nparams
                state.bg = _tc256(clamp(_SGR_PARAMS[i + 2], 0, 255))
                i += 2
            elseif i + 1 <= nparams && _SGR_PARAMS[i + 1] == 2 && i + 4 <= nparams
                state.bg = _tcrgb(clamp(_SGR_PARAMS[i + 2], 0, 255),
                                  clamp(_SGR_PARAMS[i + 3], 0, 255),
                                  clamp(_SGR_PARAMS[i + 4], 0, 255))
                i += 4
            end
        elseif p == 49
            state.bg = _TC_NONE
        elseif 90 <= p <= 97
            state.fg = _tc256(p - 90 + 8)
        elseif 100 <= p <= 107
            state.bg = _tc256(p - 100 + 8)
        end
        i += 1
    end
end

"""
    parse_ansi(str::AbstractString) → Vector{Span}

Parse a string containing ANSI escape sequences (SGR codes) and return a
vector of `Span`s with the corresponding `Style` attributes applied.

Supports:
- Standard colors (30–37 fg, 40–47 bg)
- Bright colors (90–97 fg, 100–107 bg)
- 256-color mode (`38;5;n` / `48;5;n`)
- 24-bit RGB (`38;2;r;g;b` / `48;2;r;g;b`)
- Bold, dim, italic, underline, strikethrough, reverse video
- Reset (`0` / `\\e[m`)
- Non-SGR escape sequences are silently stripped.

# Example
```julia
spans = parse_ansi("\\e[1;31mError:\\e[0m something broke")
Paragraph(spans)
```
"""
function parse_ansi(str::AbstractString)::Vector{Span}
    bytes = codeunits(String(str))
    len = length(bytes)
    spans = Span[]
    state = _ParseState()
    text_start = 1  # start of current text segment

    i = 1
    @inbounds while i <= len
        if bytes[i] == 0x1b  # ESC
            # Emit any accumulated text before this escape
            if i > text_start
                push!(spans, Span(String(bytes[text_start:i-1]), _to_style(state)))
            end

            esc_start = i
            i += 1
            i > len && (text_start = i; break)

            b = bytes[i]
            if b == UInt8('[')  # CSI sequence
                i += 1
                # Skip '?' '>' '=' '!' prefix if present
                if i <= len && (bytes[i] == UInt8('?') || bytes[i] == UInt8('>') ||
                                bytes[i] == UInt8('=') || bytes[i] == UInt8('!'))
                    i += 1
                end
                # Collect parameter bytes (digits, semicolons, colons)
                param_start = i
                while i <= len && (UInt8('0') <= bytes[i] <= UInt8('9') ||
                                   bytes[i] == UInt8(';') || bytes[i] == UInt8(':'))
                    i += 1
                end
                param_end = i - 1
                # Skip intermediate bytes (0x20-0x2f)
                while i <= len && 0x20 <= bytes[i] <= 0x2f
                    i += 1
                end
                # Final byte
                if i <= len
                    final_byte = bytes[i]
                    i += 1
                    # Only process SGR (final byte 'm')
                    if final_byte == UInt8('m')
                        if param_start > param_end
                            # Bare \e[m → reset
                            _reset!(state)
                        else
                            nparams = _parse_sgr_params!(bytes, param_start, param_end)
                            _apply_sgr!(state, nparams)
                        end
                    end
                    # All other CSI sequences silently consumed
                end
            elseif b == UInt8(']')  # OSC sequence
                i += 1
                while i <= len
                    if bytes[i] == 0x07  # BEL terminator
                        i += 1; break
                    elseif bytes[i] == 0x1b && i + 1 <= len && bytes[i+1] == UInt8('\\')
                        i += 2; break  # ST terminator
                    end
                    i += 1
                end
            elseif b == UInt8('(')  # Character set designation
                i += 1
                i <= len && (i += 1)  # skip charset byte
            elseif b == UInt8('P') || b == UInt8('^') || b == UInt8('_')
                # DCS / PM / APC — skip until ST
                i += 1
                while i <= len
                    if bytes[i] == 0x1b && i + 1 <= len && bytes[i+1] == UInt8('\\')
                        i += 2; break
                    end
                    i += 1
                end
            else
                # Single-char escape (e.g. ESC 7, ESC 8, ESC c)
                i += 1
            end
            text_start = i
        else
            i += 1
        end
    end

    # Trailing text
    if text_start <= len
        push!(spans, Span(String(bytes[text_start:len]), _to_style(state)))
    end

    isempty(spans) && push!(spans, Span("", RESET))
    spans
end
