# ═══════════════════════════════════════════════════════════════════════
# Sixel encoder ── pure Julia, zero dependencies
#
# Converts a ColorRGB pixel matrix to sixel escape sequences with
# optional "bit-rot" decay effects (jitter, corruption, desaturation).
# Uses noise(), fbm(), hue_shift(), color_lerp() from animation.jl.
# ═══════════════════════════════════════════════════════════════════════

const BLACK = ColorRGBA(0x00, 0x00, 0x00, 0xff)
const TRANSPARENT = ColorRGBA(0x00, 0x00, 0x00, 0x00)
const _SIXEL_IO = IOBuffer(sizehint=256_000)

# ── Color quantization & fast palette lookup ─────────────────────────

# Quantize color by masking low bits. `shift` controls coarseness:
# shift=2 → 64 levels/channel (high quality), shift=4 → 16 levels (more banding).
# Adaptive quantization increases shift until unique colors ≤ 255.
@inline _quantize(c::ColorRGB, shift::Int) = ColorRGB(
    (c.r >> shift) << shift,
    (c.g >> shift) << shift,
    (c.b >> shift) << shift)
@inline _quantize(c::ColorRGBA, shift::Int) = ColorRGB(
    (c.r >> shift) << shift,
    (c.g >> shift) << shift,
    (c.b >> shift) << shift)

# Color key for LUT lookup. Packs quantized channels into a single
# integer index (1-based). Max key depends on shift:
# shift=2 → 262144, shift=3 → 32768, shift=4 → 4096.
# All fit within the 262144-entry LUT.
@inline function _color_key(c::ColorRGB, shift::Int)
    bits = 8 - shift
    (Int(c.r >> shift) << (2 * bits)) | (Int(c.g >> shift) << bits) | Int(c.b >> shift) + 1
end
@inline _color_key(c::ColorRGBA, shift::Int) = _color_key(ColorRGB(c.r, c.g, c.b), shift)

# Compile-time constant shift specializations for the common case
@inline _quantize_2(c::ColorRGB) = ColorRGB(
    (c.r >> 0x02) << 0x02,
    (c.g >> 0x02) << 0x02,
    (c.b >> 0x02) << 0x02)
@inline _color_key_2(c::ColorRGB) =
    (Int(c.r >> 0x02) << 12) | (Int(c.g >> 0x02) << 6) | Int(c.b >> 0x02) + 1

# Convenience wrappers at the default quality level (shift=2)
@inline _quantize(c::ColorRGB) = _quantize(c, 2)
@inline _color_key(c::ColorRGB) = _color_key(c, 2)

# ── Decay effects ─────────────────────────────────────────────────────

"""
    apply_decay!(pixels, params::DecayParams, tick::Int)

In-place bit-rot effects on pixel buffer. All effects are scaled by
the master `params.decay` intensity. Skips black (background) pixels.
"""
function apply_decay!(pixels::Matrix{ColorRGBA}, params::DecayParams, tick::Int;
                      )
    params.decay <= 0.0 && return pixels
    h, w = size(pixels)
    master = params.decay
    do_jitter = params.jitter > 0.0
    do_rot = params.rot_prob > 0.0
    do_noise = params.noise_scale > 0.0
    j = params.jitter * master
    rot_threshold = params.rot_prob * master
    ns = params.noise_scale
    tick_f = Float64(tick)

    @inbounds for cy in 1:h, cx in 1:w
        px = pixels[cy, cx]
        px == TRANSPARENT && continue

        x = Float64(cx)
        y = Float64(cy)

        # Jitter: noise-driven RGB offset
        if do_jitter
            nr = noise(x * 0.7, y + tick_f * 0.05) - 0.5
            ng = noise(x * 0.7 + 31.7, y + tick_f * 0.05) - 0.5
            nb = noise(x * 0.7 + 67.3, y + tick_f * 0.05) - 0.5
            r = clamp(Int(px.r) + round(Int, nr * j * 255), 0, 255)
            g = clamp(Int(px.g) + round(Int, ng * j * 255), 0, 255)
            b = clamp(Int(px.b) + round(Int, nb * j * 255), 0, 255)
            px = ColorRGBA(UInt8(r), UInt8(g), UInt8(b), px.a)
        end

        # Rot: stochastic pixel corruption
        if do_rot
            n = noise(x * 13.7, y * 17.3 + tick_f * 0.01)
            if n < rot_threshold
                # Flip to transparent or hue-shifted version
                if n < rot_threshold * 0.5
                    px = TRANSPARENT
                else
                    px = hue_shift(px, n * 360.0)
                end
            end
        end

        # Noise desaturation: fbm-driven lerp toward grayscale
        if do_noise
            f = fbm(x * ns * 0.1, y * ns * 0.1 + tick_f * 0.003) * master
            gray_val = UInt8(round(Int(px.r) * 0.299 + Int(px.g) * 0.587 + Int(px.b) * 0.114))
            gray = ColorRGBA(gray_val, gray_val, gray_val, px.a)
            px = color_lerp(px, gray, f)
        end

        pixels[cy, cx] = px
    end
    pixels
end

# ── Decay with subsampling ────────────────────────────────────────────

"""
    apply_decay_subsampled!(pixels, params::DecayParams, tick::Int, step::Int)

Subsampled decay: compute effects every `step` pixels and fill blocks.
Gives step² speedup for decay-heavy frames at the cost of block artifacts
(acceptable since decay is itself a distortion effect).
"""
function apply_decay_subsampled!(pixels::Matrix{ColorRGBA}, params::DecayParams,
                                 tick::Int, step::Int; )
    params.decay <= 0.0 && return pixels
    step <= 1 && return apply_decay!(pixels, params, tick)
    h, w = size(pixels)
    master = params.decay
    do_jitter = params.jitter > 0.0
    do_rot = params.rot_prob > 0.0
    do_noise = params.noise_scale > 0.0
    j = params.jitter * master
    rot_threshold = params.rot_prob * master
    ns = params.noise_scale
    tick_f = Float64(tick)

    @inbounds for cy in 1:step:h
        y = Float64(cy)
        for cx in 1:step:w
            px = pixels[cy, cx]
            px == TRANSPARENT && continue

            x = Float64(cx)

            if do_jitter
                nr = noise(x * 0.7, y + tick_f * 0.05) - 0.5
                ng = noise(x * 0.7 + 31.7, y + tick_f * 0.05) - 0.5
                nb = noise(x * 0.7 + 67.3, y + tick_f * 0.05) - 0.5
                r = clamp(Int(px.r) + round(Int, nr * j * 255), 0, 255)
                g = clamp(Int(px.g) + round(Int, ng * j * 255), 0, 255)
                b = clamp(Int(px.b) + round(Int, nb * j * 255), 0, 255)
                px = ColorRGBA(UInt8(r), UInt8(g), UInt8(b), px.a)
            end

            if do_rot
                n = noise(x * 13.7, y * 17.3 + tick_f * 0.01)
                if n < rot_threshold
                    if n < rot_threshold * 0.5
                        px = TRANSPARENT
                    else
                        px = hue_shift(px, n * 360.0)
                    end
                end
            end

            if do_noise
                f = fbm(x * ns * 0.1, y * ns * 0.1 + tick_f * 0.003) * master
                gray_val = UInt8(round(Int(px.r) * 0.299 + Int(px.g) * 0.587 + Int(px.b) * 0.114))
                gray = ColorRGBA(gray_val, gray_val, gray_val, px.a)
                px = color_lerp(px, gray, f)
            end

            # Fill the block with the decayed color
            for by in cy:min(cy + step - 1, h)
                for bx in cx:min(cx + step - 1, w)
                    pixels[by, bx] = px
                end
            end
        end
    end
    pixels
end

# ── Inline decimal writer (replaces string() allocations) ────────────

# Write an integer 0–9999 as ASCII decimal digits directly to an IOBuffer.
# Eliminates ~5000 String allocations per frame from the band encoding loop.
@inline function _write_decimal(io::IOBuffer, n::Int)
    if n < 10
        write(io, UInt8(0x30 + n))
    elseif n < 100
        write(io, UInt8(0x30 + n ÷ 10), UInt8(0x30 + n % 10))
    elseif n < 1000
        d2 = n ÷ 100
        rem = n - d2 * 100
        write(io, UInt8(0x30 + d2), UInt8(0x30 + rem ÷ 10), UInt8(0x30 + rem % 10))
    else
        d3 = n ÷ 1000
        rem = n - d3 * 1000
        d2 = rem ÷ 100
        rem = rem - d2 * 100
        write(io, UInt8(0x30 + d3), UInt8(0x30 + d2),
              UInt8(0x30 + rem ÷ 10), UInt8(0x30 + rem % 10))
    end
    nothing
end

# ── Module-level reusable buffers ────────────────────────────────────

# LUT: 64^3 entries, reset only dirty keys each frame
const _ENC_LUT = zeros(UInt16, 262144)
const _ENC_DIRTY = Vector{Int}(undef, 8192)  # palette entries + nearest-color cache

# idx matrix: reused across frames, reallocated only on dimension change
const _ENC_IDX = Ref(Matrix{UInt16}(undef, 0, 0))

# Per-band multi-color buffers: track all colors per band for multi-pass encoding
# _BAND_BITS[ci, col] = 6-bit mask for color ci at column col (reset per band)
const _BAND_BITS = Ref(Matrix{UInt8}(undef, 0, 0))
# Dirty tracking for efficient per-band reset
const _BAND_DIRTY = Ref(Vector{Int}(undef, 0))   # linear indices into _BAND_BITS to reset
# Active colors per band
const _BAND_COLORS = Ref(Vector{Int}(undef, 0))   # list of active color indices
const _BAND_COLOR_SEEN = Ref(Vector{Bool}(undef, 0))  # has color been added to list?

# Pixel copy buffer for decay: reused across frames
const _ENC_BUF = Ref(Matrix{ColorRGB}(undef, 0, 0))

# ── Nearest-color fallback for palette overflow ───────────────────

# When the 255-color sixel palette is full, find the closest existing
# palette entry for a new color. Result is cached in the LUT so each
# unique quantized color only triggers one linear search.
@inline function _nearest_palette_color(c::ColorRGB, palette::Vector{ColorRGB})
    best = UInt16(1)
    best_dist = typemax(Int)
    @inbounds for i in 1:length(palette)
        p = palette[i]
        dr = Int(c.r) - Int(p.r)
        dg = Int(c.g) - Int(p.g)
        db = Int(c.b) - Int(p.b)
        d = dr*dr + dg*dg + db*db
        if d < best_dist
            best_dist = d
            best = UInt16(i)
        end
    end
    best
end

# ── Two-pass color quantization ───────────────────────────────────

# Reverse a color key back to a quantized ColorRGB.
@inline function _key_to_color(key::Int, shift::Int=2)
    key -= 1  # back to 0-based
    bits = 8 - shift
    mask = (1 << bits) - 1
    b = UInt8((key & mask) << shift)
    g = UInt8(((key >> bits) & mask) << shift)
    r = UInt8(((key >> (2 * bits)) & mask) << shift)
    ColorRGB(r, g, b)
end

# Collect all unique quantized color keys from the image.
# Returns the count of unique colors found. Keys are stored in
# unique_keys[1:count] and also marked in lut (cleaned up by caller).
const _UNIQUE_KEYS = Ref(Vector{Int}(undef, 0))

function _collect_unique_colors!(src::Matrix{ColorRGBA}, lut::Vector{UInt16},
                                  dirty::Vector{Int}, shift::Int=2)
    unique_keys = _UNIQUE_KEYS[]
    if length(unique_keys) < 262144
        unique_keys = Vector{Int}(undef, 262144)
        _UNIQUE_KEYS[] = unique_keys
    end
    n = 0
    nd = 0
    npix = length(src)
    GC.@preserve src lut dirty unique_keys begin
        src_ptr = Ptr{UInt8}(pointer(src))
        lut_ptr = pointer(lut)
        for i in 1:npix
            r = unsafe_load(src_ptr, (i-1)*4 + 1)
            g = unsafe_load(src_ptr, (i-1)*4 + 2)
            b = unsafe_load(src_ptr, (i-1)*4 + 3)
            a = unsafe_load(src_ptr, (i-1)*4 + 4)
            # Skip transparent pixels (alpha = 0)
            a == 0x00 && continue
            # Inline quantize + color_key for shift=2
            qr = (r >> shift) << shift
            qg = (g >> shift) << shift
            qb = (b >> shift) << shift
            bits = 8 - shift
            key = (Int(qr >> shift) << (2 * bits)) | (Int(qg >> shift) << bits) | Int(qb >> shift) + 1
            @inbounds if lut[key] == 0
                lut[key] = UInt16(1)
                nd += 1
                dirty[nd] = key
                n += 1
                unique_keys[n] = key
            end
        end
    end
    # Clean up lut markers
    @inbounds for j in 1:nd
        lut[dirty[j]] = zero(UInt16)
    end
    n
end

# Select up to 255 representative colors from a list of unique keys.
# Strategy: sort keys (which distributes colors evenly in RGB space
# due to r-g-b bit packing), then pick 255 evenly spaced entries.
# Returns palette::Vector{ColorRGB} of at most 255 entries.
function _select_palette(unique_keys::Vector{Int}, n_unique::Int, shift::Int=2)
    if n_unique <= 255
        palette = Vector{ColorRGB}(undef, n_unique)
        @inbounds for i in 1:n_unique
            palette[i] = _key_to_color(unique_keys[i], shift)
        end
        return palette
    end
    # Sort keys — since key = (r<<12)|(g<<6)|b, sorting distributes
    # evenly across the full RGB cube
    sort!(Base.view(unique_keys, 1:n_unique))
    # Pick 255 evenly spaced entries
    palette = Vector{ColorRGB}(undef, 255)
    @inbounds for i in 1:255
        # Map i ∈ [1,255] to index in [1,n_unique] evenly
        idx = round(Int, (i - 1) * (n_unique - 1) / 254) + 1
        palette[i] = _key_to_color(unique_keys[idx], shift)
    end
    palette
end

# ── Main encoder ──────────────────────────────────────────────────────

function encode_sixel(pixels::Matrix{ColorRGBA};
                      decay::DecayParams=DecayParams(), tick::Int=0)
    h, w = size(pixels)
    (h == 0 || w == 0) && return UInt8[]

    # Only copy pixels when decay will modify them
    needs_decay = decay.decay > 0.0
    if needs_decay
        enc_buf = _ENC_BUF[]
        if size(enc_buf) != (h, w)
            enc_buf = Matrix{ColorRGB}(undef, h, w)
            _ENC_BUF[] = enc_buf
        end
        copyto!(enc_buf, pixels)
        src = enc_buf

        # Subsampled decay for large images
        npix = h * w
        decay_step = npix > 500_000 ? max(1, round(Int, sqrt(npix / 500_000))) : 1
        apply_decay_subsampled!(src, decay, tick, decay_step)
    else
        src = pixels
    end

    # Reuse LUT with dirty tracking — reset only written entries
    lut = _ENC_LUT
    dirty = _ENC_DIRTY
    n_dirty = 0

    has_any = false

    # Adaptive color quantization: start at shift=2 (64 levels/channel,
    # high quality). If there are more than 255 unique colors, coarsen
    # to shift=3 (32 levels) then shift=4 (16 levels). This avoids the
    # expensive _nearest_palette_color linear search entirely when
    # coarsening brings the count under 255, and also reduces the number
    # of band passes (fewer colors = smaller output).
    shift = 2
    n_unique = _collect_unique_colors!(src, lut, dirty, shift)
    while n_unique > 255 && shift < 4
        shift += 1
        n_unique = _collect_unique_colors!(src, lut, dirty, shift)
    end
    unique_keys = _UNIQUE_KEYS[]
    palette = _select_palette(unique_keys, n_unique, shift)
    n_palette = length(palette)

    # Build LUT: for palette colors, direct map. When n_unique ≤ 255
    # (the common case after adaptive shift), every pixel maps directly
    # with no nearest-color search needed.
    for ci in 1:n_palette
        key = _color_key(palette[ci], shift)
        lut[key] = UInt16(ci)
        n_dirty += 1
        if n_dirty <= length(dirty)
            dirty[n_dirty] = key
        end
    end

    has_any = n_palette > 0
    has_any || return UInt8[]

    # Reuse IOBuffer across frames — avoids allocation every call
    io = _SIXEL_IO
    truncate(io, 0)

    # DCS P1;P2;P3 q  (Device Control String, sixel mode)
    # P2=1: transparent background — unpainted pixels leave existing content
    write(io, "\eP0;1q")

    # Raster attributes: 1:1 pixel aspect ratio, image dimensions
    write(io, "\"1;1;")
    _write_decimal(io, w)
    write(io, UInt8(';'))
    _write_decimal(io, h)

    # Color 0: background — explicitly painted each band to ensure
    # clean background regardless of terminal P2 support.
    _cbg = canvas_bg_rgb()
    bg_r = round(Int, Int(_cbg.r) / 255 * 100)
    bg_g = round(Int, Int(_cbg.g) / 255 * 100)
    bg_b = round(Int, Int(_cbg.b) / 255 * 100)
    write(io, "#0;2;")
    _write_decimal(io, bg_r)
    write(io, UInt8(';'))
    _write_decimal(io, bg_g)
    write(io, UInt8(';'))
    _write_decimal(io, bg_b)

    # Data colors: indices 1..N
    for (i, c) in enumerate(palette)
        r100 = round(Int, Int(c.r) / 255 * 100)
        g100 = round(Int, Int(c.g) / 255 * 100)
        b100 = round(Int, Int(c.b) / 255 * 100)
        write(io, UInt8('#'))
        _write_decimal(io, i)
        write(io, ";2;")
        _write_decimal(io, r100)
        write(io, UInt8(';'))
        _write_decimal(io, g100)
        write(io, UInt8(';'))
        _write_decimal(io, b100)
    end

    # ── Multi-pass encoding per band ──
    # For each 6-pixel-tall band:
    #   Pass 0: paint entire band with color 0 (black) — solid background
    #   Pass 1..N: one pass per active color, using $ (CR) to overlay
    # This ensures ALL colors in a band are rendered, not just one per column.
    num_bands = (h + 5) ÷ 6

    # Reuse per-band multi-color buffers — grow only when dimensions increase
    max_colors = n_palette + 1  # palette indices are 1..n_palette
    band_bits = _BAND_BITS[]
    if size(band_bits, 1) < max_colors || size(band_bits, 2) < w
        band_bits = zeros(UInt8, max_colors, w)
        _BAND_BITS[] = band_bits
    end
    band_dirty = _BAND_DIRTY[]
    max_dirty = 6 * w  # up to 6 rows × w columns per band
    if length(band_dirty) < max_dirty
        band_dirty = Vector{Int}(undef, max_dirty)
        _BAND_DIRTY[] = band_dirty
    end
    band_colors = _BAND_COLORS[]
    if length(band_colors) < max_colors
        band_colors = Vector{Int}(undef, max_colors)
        _BAND_COLORS[] = band_colors
    end
    color_seen = _BAND_COLOR_SEEN[]
    if length(color_seen) < max_colors
        color_seen = Vector{Bool}(undef, max_colors)
        _BAND_COLOR_SEEN[] = color_seen
    end

    for band in 0:(num_bands - 1)
        y0 = band * 6  # 0-based row offset

        # Compute how many rows are valid in this band
        band_rows = min(6, h - y0)
        # Background mask: all valid rows set
        bg_bits_val = UInt8((1 << band_rows) - 1)
        bg_char = 0x3F + bg_bits_val

        # Pass 0: paint background only for columns that have content.
        # Build a per-column mask: paint bg bits only where pixels are opaque.
        write(io, "#0")
        @inbounds for col in 1:w
            col_bits = UInt8(0)
            for bit in 0:(band_rows - 1)
                row_idx = y0 + bit + 1
                px = src[row_idx, col]
                if px.a > 0x00
                    col_bits |= UInt8(1) << bit
                end
            end
            write(io, UInt8(0x3F + col_bits))
        end

        # Scan band: build per-color per-column bit masks
        n_band_dirty = 0
        n_band_colors = 0
        @inbounds for ci in 1:max_colors
            color_seen[ci] = false
        end

        @inbounds for col in 1:w
            for bit in 0:5
                row_idx = y0 + bit + 1
                row_idx > h && continue
                px = src[row_idx, col]
                px.a == 0x00 && continue
                qpx = _quantize(px, shift)
                key = _color_key(qpx, shift)
                ci = Int(lut[key])
                if ci == 0
                    ci = Int(_nearest_palette_color(qpx, palette))
                    lut[key] = UInt16(ci)
                    n_dirty += 1
                    if n_dirty <= length(dirty)
                        dirty[n_dirty] = key
                    end
                end
                band_bits[ci, col] |= UInt8(1) << bit
                n_band_dirty += 1
                band_dirty[n_band_dirty] = (ci - 1) * w + col
                if !color_seen[ci]
                    color_seen[ci] = true
                    n_band_colors += 1
                    band_colors[n_band_colors] = ci
                end
            end
        end

        # Write one pass per active color
        for ci_idx in 1:n_band_colors
            ci = band_colors[ci_idx]
            write(io, UInt8('$'))  # CR — back to start of band
            write(io, UInt8('#'))
            _write_decimal(io, ci)

            # RLE-encode this color's bit pattern across columns
            col = 1
            @inbounds while col <= w
                bits = band_bits[ci, col]
                ch = 0x3F + bits
                # Count run of identical chars
                run = 1
                while col + run <= w && @inbounds(band_bits[ci, col + run]) == bits
                    run += 1
                end
                if bits == 0
                    # No pixels for this color — emit '?' (noop sixel)
                    if run >= 4
                        write(io, UInt8('!'))
                        _write_decimal(io, run)
                        write(io, UInt8('?'))
                    else
                        for _ in 1:run; write(io, UInt8('?')); end
                    end
                else
                    if run >= 4
                        write(io, UInt8('!'))
                        _write_decimal(io, run)
                        write(io, ch)
                    elseif run > 1
                        for _ in 1:run; write(io, ch); end
                    else
                        write(io, ch)
                    end
                end
                col += run
            end
        end

        # Reset dirty entries in band_bits for next band
        @inbounds for j in 1:n_band_dirty
            li = band_dirty[j]
            ci_off = (li - 1) ÷ w
            col_off = (li - 1) % w + 1
            band_bits[ci_off + 1, col_off] = 0x00
        end

        # Band separator
        if band < num_bands - 1
            write(io, UInt8('-'))
        end
    end

    # ST (String Terminator)
    write(io, "\e\\")

    # Clean up LUT dirty entries for next frame
    if n_dirty <= length(dirty)
        @inbounds for j in 1:n_dirty
            lut[dirty[j]] = zero(UInt16)
        end
    else
        fill!(lut, zero(UInt16))
    end

    take!(io)
end

