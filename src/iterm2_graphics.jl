# ═══════════════════════════════════════════════════════════════════════
# iTerm2 inline images encoder (OSC 1337)
#
# Converts a ColorRGB pixel matrix to an iTerm2 inline image escape
# sequence containing a minimal PNG.  Uses the same apply_decay!
# pipeline as the sixel/kitty encoders for bit-rot effects.
#
# No external PNG library needed — we hand-build a minimal PNG using
# CodecZlib for IDAT compression and a pure-Julia CRC-32 for chunk
# checksums.
#
# Protocol reference:
#   https://iterm2.com/documentation-images.html
#
# Supported terminals: iTerm2, WezTerm, Ghostty, mintty, Konsole (≥23.08)
# ═══════════════════════════════════════════════════════════════════════

using Base64: Base64EncodePipe
using CodecZlib: ZlibCompressor

# ── Reusable buffers ──────────────────────────────────────────────────

const _ITERM2_ENC_BUF = Ref(Matrix{ColorRGB}(undef, 0, 0))
const _ITERM2_PNG_IO = IOBuffer()
const _ITERM2_SEQ_IO = IOBuffer()
const _ITERM2_RAW_DATA = Ref(Vector{UInt8}(undef, 0))

# ── PNG helpers ───────────────────────────────────────────────────────

# PNG requires CRC-32 (ISO 3309 polynomial 0xEDB88320), not CRC-32C from the stdlib.
const _CRC32_TABLE = let t = Vector{UInt32}(undef, 256)
    for i in 0:255
        c = UInt32(i)
        for _ in 1:8
            c = (c & 1) == 1 ? xor(UInt32(0xEDB88320), c >> 1) : c >> 1
        end
        t[i + 1] = c
    end
    Tuple(t)
end

function _png_crc32(data::AbstractVector{UInt8})
    crc = ~UInt32(0)
    @inbounds for b in data
        crc = xor(_CRC32_TABLE[(xor(crc, b) & 0xff) + 1], crc >> 8)
    end
    ~crc
end

# Incremental CRC — feed type bytes then data without vcat
function _png_crc32(a::AbstractVector{UInt8}, b::AbstractVector{UInt8})
    crc = ~UInt32(0)
    @inbounds for byte in a
        crc = xor(_CRC32_TABLE[(xor(crc, byte) & 0xff) + 1], crc >> 8)
    end
    @inbounds for byte in b
        crc = xor(_CRC32_TABLE[(xor(crc, byte) & 0xff) + 1], crc >> 8)
    end
    ~crc
end

# Write a 4-byte big-endian UInt32
@inline function _write_be32(io::IO, v::UInt32)
    write(io, UInt8((v >> 24) & 0xff))
    write(io, UInt8((v >> 16) & 0xff))
    write(io, UInt8((v >> 8) & 0xff))
    write(io, UInt8(v & 0xff))
end

# Write a PNG chunk: length + type + data + crc
function _write_png_chunk(io::IO, chunk_type::NTuple{4,UInt8}, data::Vector{UInt8})
    _write_be32(io, UInt32(length(data)))
    type_bytes = UInt8[chunk_type[1], chunk_type[2], chunk_type[3], chunk_type[4]]
    write(io, type_bytes)
    write(io, data)
    _write_be32(io, _png_crc32(type_bytes, data))
end

const _PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const _IHDR_TYPE = (UInt8('I'), UInt8('H'), UInt8('D'), UInt8('R'))
const _IDAT_TYPE = (UInt8('I'), UInt8('D'), UInt8('A'), UInt8('T'))
const _IEND_TYPE = (UInt8('I'), UInt8('E'), UInt8('N'), UInt8('D'))

"""
    _encode_minimal_png(pixels::Matrix{ColorRGB}) -> Vector{UInt8}

Encode a pixel matrix as a minimal valid PNG (8-bit RGB, no filtering).
Layout: signature + IHDR + IDAT + IEND.
"""
function _encode_minimal_png(pixels::Matrix{ColorRGB})
    h, w = size(pixels)

    png_io = _ITERM2_PNG_IO
    truncate(png_io, 0)

    # PNG signature
    write(png_io, _PNG_SIGNATURE)

    # ── IHDR (13 bytes, always the same structure) ──
    ihdr = UInt8[0,0,0,0, 0,0,0,0, 8, 2, 0, 0, 0]
    ihdr[1] = UInt8((w >> 24) & 0xff); ihdr[2] = UInt8((w >> 16) & 0xff)
    ihdr[3] = UInt8((w >> 8) & 0xff);  ihdr[4] = UInt8(w & 0xff)
    ihdr[5] = UInt8((h >> 24) & 0xff); ihdr[6] = UInt8((h >> 16) & 0xff)
    ihdr[7] = UInt8((h >> 8) & 0xff);  ihdr[8] = UInt8(h & 0xff)
    _write_png_chunk(png_io, _IHDR_TYPE, ihdr)

    # ── IDAT: raw scanlines with filter byte 0 (None) per row ──
    scanline_len = 1 + w * 3
    needed = h * scanline_len
    raw_data = _ITERM2_RAW_DATA[]
    if length(raw_data) < needed
        raw_data = Vector{UInt8}(undef, needed)
        _ITERM2_RAW_DATA[] = raw_data
    end
    idx = 1
    @inbounds for row in 1:h
        raw_data[idx] = 0x00  # filter: None
        idx += 1
        for col in 1:w
            c = pixels[row, col]
            raw_data[idx]     = c.r
            raw_data[idx + 1] = c.g
            raw_data[idx + 2] = c.b
            idx += 3
        end
    end

    # Compress with zlib
    resize!(raw_data, needed)
    compressed = transcode(ZlibCompressor, raw_data)
    _write_png_chunk(png_io, _IDAT_TYPE, compressed)

    # ── IEND ──
    _write_png_chunk(png_io, _IEND_TYPE, UInt8[])

    take!(png_io)
end

# ── Main encoder ──────────────────────────────────────────────────────

"""
    encode_iterm2(pixels::Matrix{ColorRGB};
                  decay::DecayParams=DecayParams(), tick::Int=0,
                  cols::Int=0, rows::Int=0) -> Vector{UInt8}

Encode pixels as an iTerm2 inline image (OSC 1337) containing a minimal PNG.
Returns the complete escape sequence as bytes, ready to write to the terminal.
"""
function encode_iterm2(pixels::Matrix{ColorRGB};
                       decay::DecayParams=DecayParams(), tick::Int=0,
                       cols::Int=0, rows::Int=0)
    h, w = size(pixels)
    (h == 0 || w == 0) && return UInt8[]

    # Decay handling (same pattern as kitty/sixel encoders)
    needs_decay = decay.decay > 0.0
    if needs_decay
        enc_buf = _ITERM2_ENC_BUF[]
        if size(enc_buf) != (h, w)
            enc_buf = Matrix{ColorRGB}(undef, h, w)
            _ITERM2_ENC_BUF[] = enc_buf
        end
        copyto!(enc_buf, pixels)
        src = enc_buf
        npix = h * w
        decay_step = npix > 500_000 ? max(1, round(Int, sqrt(npix / 500_000))) : 1
        apply_decay_subsampled!(src, decay, tick, decay_step)
    else
        src = pixels
    end

    # Skip all-black frames
    any(!=(BLACK), src) || return UInt8[]

    # Encode as PNG
    png_bytes = _encode_minimal_png(src)

    # Build OSC 1337 escape sequence directly into reusable IOBuffer
    seq_io = _ITERM2_SEQ_IO
    truncate(seq_io, 0)
    write(seq_io, "\e]1337;File=inline=1;preserveAspectRatio=0")
    if cols > 0
        write(seq_io, ";width=", string(cols))
    end
    if rows > 0
        write(seq_io, ";height=", string(rows))
    end
    write(seq_io, ':')
    b64pipe = Base64EncodePipe(seq_io)
    write(b64pipe, png_bytes)
    close(b64pipe)
    write(seq_io, '\a')
    take!(seq_io)
end
