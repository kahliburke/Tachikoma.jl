module TachikomaGifExt

using Tachikoma
using FreeTypeAbstraction
using ColorTypes
using ColorTypes.FixedPointNumbers: N0f8

# ── Types ──────────────────────────────────────────────────────────────

# Face key: (bold, italic) → index into faces/glyph caches
const _FACE_REGULAR     = 1
const _FACE_BOLD        = 2
const _FACE_ITALIC      = 3
const _FACE_BOLD_ITALIC = 4

struct GlyphCache
    faces::NTuple{4, Union{FTFont, Nothing}}  # regular, bold, italic, bold-italic
    size::Int
    glyphs::NTuple{4, Dict{Char, Matrix{UInt8}}}
    metrics::NTuple{4, Dict{Char, Tuple{Int,Int}}}
end

# ── Glyph rendering ───────────────────────────────────────────────────

function GlyphCache(font_path::String, pixel_size::Int)
    face = FTFont(font_path)
    _load(variant) = let p = Tachikoma.find_font_variant(font_path, variant)
        !isempty(p) ? FTFont(p) : nothing
    end
    faces = (face, _load("Bold"), _load("Italic"), _load("BoldItalic"))
    glyphs = ntuple(_ -> Dict{Char, Matrix{UInt8}}(), 4)
    mets = ntuple(_ -> Dict{Char, Tuple{Int,Int}}(), 4)
    GlyphCache(faces, pixel_size, glyphs, mets)
end

@inline function _face_index(bold::Bool, italic::Bool)
    bold && italic ? _FACE_BOLD_ITALIC :
    bold           ? _FACE_BOLD :
    italic         ? _FACE_ITALIC :
                     _FACE_REGULAR
end

function get_glyph!(gc::GlyphCache, ch::Char; bold::Bool=false, italic::Bool=false)
    idx = _face_index(bold, italic)
    # Fall back to regular if the requested variant isn't available
    face = gc.faces[idx]
    if face === nothing
        idx = _FACE_REGULAR
        face = gc.faces[idx]
    end

    gd = gc.glyphs[idx]
    md = gc.metrics[idx]
    haskey(gd, ch) && return gd[ch], md[ch]

    raw_bitmap, extent = renderface(face, ch, gc.size)
    bitmap = collect(transpose(raw_bitmap))
    hb = extent.horizontal_bearing
    bx = round(Int, hb[1])
    by = round(Int, hb[2])
    gd[ch] = bitmap
    md[ch] = (bx, by)
    bitmap, (bx, by)
end

# ── Color conversion ──────────────────────────────────────────────────

@inline function tachikoma_to_rgb(c::Tachikoma.ColorRGB)
    RGB{N0f8}(reinterpret(N0f8, c.r), reinterpret(N0f8, c.g), reinterpret(N0f8, c.b))
end

@inline function tachikoma_to_rgb(c::Tachikoma.Color256)
    rgb = Tachikoma.to_rgb(c)
    tachikoma_to_rgb(rgb)
end

@inline tachikoma_to_rgb(::Tachikoma.NoColor) = nothing

# ── Frame rasterizer ──────────────────────────────────────────────────

function rasterize_frame(buf::Tachikoma.Buffer, width::Int, height::Int,
                         gc::Union{GlyphCache, Nothing}=nothing;
                         cell_w::Int=10, cell_h::Int=20,
                         bg::RGB{N0f8}=RGB{N0f8}(0.067, 0.075, 0.118),
                         pixel_snapshots::Vector=Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[])
    img_w = width * cell_w
    img_h = height * cell_h
    img = fill(bg, img_h, img_w)

    # ── 1. Cell backgrounds + characters ──
    for cy in 1:height, cx in 1:width
        Tachikoma.in_bounds(buf, cx, cy) || continue
        cell = @inbounds buf.content[Tachikoma.buf_index(buf, cx, cy)]
        ch = cell.char
        st = cell.style

        px0 = (cx - 1) * cell_w + 1
        py0 = (cy - 1) * cell_h + 1

        # Background fill via @view
        bg_rgb = tachikoma_to_rgb(st.bg)
        if bg_rgb !== nothing
            py_end = min(py0 + cell_h - 1, img_h)
            px_end = min(px0 + cell_w - 1, img_w)
            cell_view = @view img[py0:py_end, px0:px_end]
            fill!(cell_view, bg_rgb)
        end

        # Character rendering
        if ch != ' ' && ch != '\0'
            fg_rgb = tachikoma_to_rgb(st.fg)
            if fg_rgb === nothing
                fg_rgb = RGB{N0f8}(0.878, 0.878, 0.878)
            end
            if _is_braille(ch)
                _draw_braille!(img, ch, px0, py0, cell_w, cell_h, fg_rgb, st.dim)
            elseif _is_block(ch)
                _draw_block!(img, ch, px0, py0, cell_w, cell_h, fg_rgb, st.dim) ||
                    (gc !== nothing && _draw_char!(img, gc, ch, px0, py0, cell_w, cell_h, fg_rgb, st.bold, st.italic, st.dim))
            elseif gc !== nothing
                _draw_char!(img, gc, ch, px0, py0, cell_w, cell_h, fg_rgb,
                            st.bold, st.italic, st.dim)
            end
        end
    end

    # ── 2. Pixel overlay ──
    for (row, col, pixels) in pixel_snapshots
        px0 = (col - 1) * cell_w + 1
        py0 = (row - 1) * cell_h + 1
        ph, pw = size(pixels)
        for sy in 1:ph, sx in 1:pw
            tx = px0 + sx - 1
            ty = py0 + sy - 1
            (1 <= tx <= img_w && 1 <= ty <= img_h) || continue
            p = pixels[sy, sx]
            (p.r == 0x00 && p.g == 0x00 && p.b == 0x00) && continue
            @inbounds img[ty, tx] = tachikoma_to_rgb(p)
        end
    end

    img
end

function _draw_char!(img::Matrix{RGB{N0f8}}, gc::GlyphCache, ch::Char,
                     px0::Int, py0::Int, cell_w::Int, cell_h::Int,
                     fg::RGB{N0f8}, bold::Bool, italic::Bool, dim::Bool)
    bitmap, (bx, by) = get_glyph!(gc, ch; bold=bold, italic=italic)
    bh, bw = size(bitmap)
    img_h, img_w = size(img)

    baseline_y = py0 + round(Int, cell_h * 0.8)
    ox = px0 + bx
    oy = baseline_y - by

    alpha_scale = dim ? 0.5f0 : 1.0f0

    for gy in 1:bh, gx in 1:bw
        tx = ox + gx - 1
        ty = oy + gy - 1
        (1 <= tx <= img_w && 1 <= ty <= img_h) || continue
        @inbounds alpha = Float32(bitmap[gy, gx]) / 255.0f0 * alpha_scale
        alpha < 0.01f0 && continue
        if alpha >= 0.99f0
            @inbounds img[ty, tx] = fg
        else
            @inbounds old = img[ty, tx]
            r = Float32(old.r) * (1 - alpha) + Float32(fg.r) * alpha
            g = Float32(old.g) * (1 - alpha) + Float32(fg.g) * alpha
            b = Float32(old.b) * (1 - alpha) + Float32(fg.b) * alpha
            @inbounds img[ty, tx] = RGB{N0f8}(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1))
        end
    end
end

# ── Braille character rendering ───────────────────────────────────────

# Braille characters U+2800–U+28FF encode a 2×4 dot grid in the codepoint bits:
#   bit 0 (0x01) → row 0, col 0    bit 3 (0x08) → row 0, col 1
#   bit 1 (0x02) → row 1, col 0    bit 4 (0x10) → row 1, col 1
#   bit 2 (0x04) → row 2, col 0    bit 5 (0x20) → row 2, col 1
#   bit 6 (0x40) → row 3, col 0    bit 7 (0x80) → row 3, col 1

@inline _is_braille(ch::Char) = '⠀' <= ch <= '⣿'  # U+2800..U+28FF

# Dot bit positions indexed by (row, col): _BRAILLE_BITS[row+1][col+1]
const _BRAILLE_BITS = (
    (0x01, 0x08),  # row 0
    (0x02, 0x10),  # row 1
    (0x04, 0x20),  # row 2
    (0x40, 0x80),  # row 3
)

function _draw_braille!(img::Matrix{RGB{N0f8}}, ch::Char,
                        px0::Int, py0::Int, cell_w::Int, cell_h::Int,
                        fg::RGB{N0f8}, dim::Bool)
    mask = UInt32(ch) - UInt32('⠀')
    mask == 0 && return  # blank braille
    img_h, img_w = size(img)

    alpha_scale = dim ? 0.5f0 : 1.0f0

    # Kitty-style rendering: each dot fills a rectangular block in a 2×4 grid,
    # so active dots tile seamlessly with no gaps between them.
    col_w = cell_w ÷ 2
    row_h = cell_h ÷ 4

    for row in 0:3, col in 0:1
        (mask & _BRAILLE_BITS[row + 1][col + 1]) == 0 && continue
        # Block bounds for this dot
        x0 = px0 + col * col_w
        y0 = py0 + row * row_h
        x1 = col == 1 ? px0 + cell_w - 1 : x0 + col_w - 1  # right col absorbs remainder
        y1 = row == 3 ? py0 + cell_h - 1 : y0 + row_h - 1  # bottom row absorbs remainder
        for ty in y0:y1, tx in x0:x1
            (1 <= tx <= img_w && 1 <= ty <= img_h) || continue
            if alpha_scale >= 0.99f0
                @inbounds img[ty, tx] = fg
            else
                @inbounds old = img[ty, tx]
                r = Float32(old.r) * (1 - alpha_scale) + Float32(fg.r) * alpha_scale
                g = Float32(old.g) * (1 - alpha_scale) + Float32(fg.g) * alpha_scale
                b = Float32(old.b) * (1 - alpha_scale) + Float32(fg.b) * alpha_scale
                @inbounds img[ty, tx] = RGB{N0f8}(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1))
            end
        end
    end
end

# ── Block element rendering ──────────────────────────────────────────

# Unicode Block Elements U+2580–U+259F: each defines a rectangular
# fill region within the cell (top/bottom/left/right fractions).
# Returns (x_frac, y_frac, w_frac, h_frac) or nothing if not a block char.

@inline _is_block(ch::Char) = '▀' <= ch <= '▟'  # U+2580..U+259F

function _block_rect(ch::Char)
    c = UInt32(ch)
    c == 0x2580 && return (0.0, 0.0, 1.0, 0.5)   # ▀ upper half
    c == 0x2581 && return (0.0, 0.875, 1.0, 0.125) # ▁ lower 1/8
    c == 0x2582 && return (0.0, 0.75, 1.0, 0.25)  # ▂ lower 1/4
    c == 0x2583 && return (0.0, 0.625, 1.0, 0.375) # ▃ lower 3/8
    c == 0x2584 && return (0.0, 0.5, 1.0, 0.5)    # ▄ lower half
    c == 0x2585 && return (0.0, 0.375, 1.0, 0.625) # ▅ lower 5/8
    c == 0x2586 && return (0.0, 0.25, 1.0, 0.75)  # ▆ lower 3/4
    c == 0x2587 && return (0.0, 0.125, 1.0, 0.875) # ▇ lower 7/8
    c == 0x2588 && return (0.0, 0.0, 1.0, 1.0)    # █ full block
    c == 0x2589 && return (0.0, 0.0, 0.875, 1.0)  # ▉ left 7/8
    c == 0x258a && return (0.0, 0.0, 0.75, 1.0)   # ▊ left 3/4
    c == 0x258b && return (0.0, 0.0, 0.625, 1.0)  # ▋ left 5/8
    c == 0x258c && return (0.0, 0.0, 0.5, 1.0)    # ▌ left half
    c == 0x258d && return (0.0, 0.0, 0.375, 1.0)  # ▍ left 3/8
    c == 0x258e && return (0.0, 0.0, 0.25, 1.0)   # ▎ left 1/4
    c == 0x258f && return (0.0, 0.0, 0.125, 1.0)  # ▏ left 1/8
    c == 0x2590 && return (0.5, 0.0, 0.5, 1.0)    # ▐ right half
    c == 0x2591 && return nothing  # ░ light shade (skip — needs pattern)
    c == 0x2592 && return nothing  # ▒ medium shade
    c == 0x2593 && return nothing  # ▓ dark shade
    c == 0x2594 && return (0.0, 0.0, 1.0, 0.125)  # ▔ upper 1/8
    c == 0x2595 && return (0.875, 0.0, 0.125, 1.0) # ▕ right 1/8
    c == 0x2596 && return (0.0, 0.5, 0.5, 0.5)    # ▖ quadrant lower left
    c == 0x2597 && return (0.5, 0.5, 0.5, 0.5)    # ▗ quadrant lower right
    c == 0x2598 && return (0.0, 0.0, 0.5, 0.5)    # ▘ quadrant upper left
    c == 0x2599 && return nothing  # ▙ quad UL+LL+LR (complex)
    c == 0x259a && return nothing  # ▚ quad UL+LR (complex)
    c == 0x259b && return nothing  # ▛ quad UL+UR+LL (complex)
    c == 0x259c && return nothing  # ▜ quad UL+UR+LR (complex)
    c == 0x259d && return (0.5, 0.0, 0.5, 0.5)    # ▝ quadrant upper right
    c == 0x259e && return nothing  # ▞ quad UR+LL (complex)
    c == 0x259f && return nothing  # ▟ quad UR+LL+LR (complex)
    return nothing
end

function _draw_block!(img::Matrix{RGB{N0f8}}, ch::Char,
                      px0::Int, py0::Int, cell_w::Int, cell_h::Int,
                      fg::RGB{N0f8}, dim::Bool)
    img_h, img_w = size(img)

    # Shade characters: stippled pixel patterns matching terminal appearance
    c = UInt32(ch)
    shade_level = if c == 0x2591; 1    # ░ light shade ~25%
    elseif c == 0x2592; 2              # ▒ medium shade ~50%
    elseif c == 0x2593; 3              # ▓ dark shade ~75%
    else; 0
    end
    if shade_level > 0
        color = if dim
            RGB{N0f8}(clamp(Float32(fg.r) * 0.5f0, 0, 1),
                      clamp(Float32(fg.g) * 0.5f0, 0, 1),
                      clamp(Float32(fg.b) * 0.5f0, 0, 1))
        else
            fg
        end
        py_end = min(py0 + cell_h - 1, img_h)
        px_end = min(px0 + cell_w - 1, img_w)
        for ty in py0:py_end, tx in px0:px_end
            (1 <= tx && 1 <= ty) || continue
            lx = tx - px0  # local coords within cell
            ly = ty - py0
            fill = if shade_level == 1      # ░ sparse dots
                (lx % 4 == 0 && ly % 2 == 0) || (lx % 4 == 2 && ly % 2 == 1)
            elseif shade_level == 2         # ▒ checkerboard
                (lx + ly) % 2 == 0
            else                            # ▓ dense (inverse of light)
                !((lx % 4 == 0 && ly % 2 == 0) || (lx % 4 == 2 && ly % 2 == 1))
            end
            if fill
                @inbounds img[ty, tx] = color
            end
        end
        return true
    end

    rect = _block_rect(ch)
    rect === nothing && return false
    xf, yf, wf, hf = rect

    # Use floor consistently so adjacent blocks (e.g. upper/lower half) tile
    # without gaps: the end of one region == the start of the next.
    x1 = px0 + floor(Int, xf * cell_w)
    y1 = py0 + floor(Int, yf * cell_h)
    x2 = px0 + floor(Int, (xf + wf) * cell_w) - 1
    y2 = py0 + floor(Int, (yf + hf) * cell_h) - 1

    color = if dim
        RGB{N0f8}(clamp(Float32(fg.r) * 0.5f0, 0, 1),
                  clamp(Float32(fg.g) * 0.5f0, 0, 1),
                  clamp(Float32(fg.b) * 0.5f0, 0, 1))
    else
        fg
    end

    for ty in max(1, y1):min(img_h, y2), tx in max(1, x1):min(img_w, x2)
        @inbounds img[ty, tx] = color
    end
    true
end

# ── Minimal GIF89a encoder ────────────────────────────────────────────

function _quantize_frame(img::Matrix{RGB{N0f8}})
    h, w = size(img)
    palette = RGB{N0f8}[]
    color_map = Dict{UInt32, UInt8}()
    indices = Matrix{UInt8}(undef, h, w)

    for j in 1:w, i in 1:h
        @inbounds c = img[i, j]
        r5 = UInt8(round(UInt8, Float32(c.r) * 31)) & 0x1f
        g5 = UInt8(round(UInt8, Float32(c.g) * 31)) & 0x1f
        b5 = UInt8(round(UInt8, Float32(c.b) * 31)) & 0x1f
        key = (UInt32(r5) << 10) | (UInt32(g5) << 5) | UInt32(b5)

        idx = get(color_map, key, nothing)
        if idx !== nothing
            @inbounds indices[i, j] = idx
        else
            if length(palette) < 256
                push!(palette, RGB{N0f8}(r5/31, g5/31, b5/31))
                new_idx = UInt8(length(palette) - 1)
                color_map[key] = new_idx
                @inbounds indices[i, j] = new_idx
            else
                best = UInt8(0)
                best_dist = typemax(Float32)
                cr, cg, cb = Float32(c.r), Float32(c.g), Float32(c.b)
                for k in 1:length(palette)
                    p = palette[k]
                    d = (Float32(p.r)-cr)^2 + (Float32(p.g)-cg)^2 + (Float32(p.b)-cb)^2
                    if d < best_dist
                        best_dist = d
                        best = UInt8(k - 1)
                    end
                end
                color_map[key] = best
                @inbounds indices[i, j] = best
            end
        end
    end

    while length(palette) < 256
        push!(palette, RGB{N0f8}(0, 0, 0))
    end

    palette, indices
end

# LZW encoder using integer-keyed dictionary (no Vector allocations)
function _lzw_encode(indices::Matrix{UInt8}, min_code_size::UInt8)
    h, w = size(indices)
    clear_code = 1 << min_code_size
    eoi_code = clear_code + 1

    io = IOBuffer()
    bit_buf = UInt32(0)
    bit_count = 0
    sub_buf = Vector{UInt8}(undef, 255)
    sub_len = 0

    @inline function emit_bits(code::Int, code_size::Int)
        bit_buf |= UInt32(code) << bit_count
        bit_count += code_size
        while bit_count >= 8
            sub_len += 1
            @inbounds sub_buf[sub_len] = UInt8(bit_buf & 0xff)
            bit_buf >>= 8
            bit_count -= 8
            if sub_len >= 255
                write(io, UInt8(255))
                write(io, @view sub_buf[1:255])
                sub_len = 0
            end
        end
    end

    # (prefix_code, pixel) → code, using UInt32 key = prefix << 8 | pixel
    dict = Dict{UInt32, Int}()
    next_code = eoi_code + 1
    code_size = Int(min_code_size) + 1
    max_code = 1 << code_size

    emit_bits(clear_code, code_size)
    prefix = Int(@inbounds indices[1, 1])

    # Row-major iteration (GIF pixel order)
    for i in 1:h, j in 1:w
        (i == 1 && j == 1) && continue
        pixel = Int(@inbounds indices[i, j])
        key = UInt32(prefix) << 8 | UInt32(pixel)

        entry = get(dict, key, -1)
        if entry >= 0
            prefix = entry
        else
            emit_bits(prefix, code_size)
            if next_code < 4096
                dict[key] = next_code
                next_code += 1
                if next_code > max_code && code_size < 12
                    code_size += 1
                    max_code = 1 << code_size
                end
            else
                emit_bits(clear_code, code_size)
                empty!(dict)
                next_code = eoi_code + 1
                code_size = Int(min_code_size) + 1
                max_code = 1 << code_size
            end
            prefix = pixel
        end
    end

    emit_bits(prefix, code_size)
    emit_bits(eoi_code, code_size)

    if bit_count > 0
        sub_len += 1
        @inbounds sub_buf[sub_len] = UInt8(bit_buf & 0xff)
    end
    if sub_len > 0
        write(io, UInt8(sub_len))
        write(io, @view sub_buf[1:sub_len])
    end
    write(io, UInt8(0))  # block terminator

    take!(io)
end

function _write_gif(filename::String, frames::Vector{Matrix{RGB{N0f8}}};
                    fps::Int=10)
    isempty(frames) && return
    h, w = size(frames[1])
    delay = round(UInt16, 100 / fps)

    open(filename, "w") do f
        write(f, b"GIF89a")
        write(f, UInt16(w))
        write(f, UInt16(h))

        palette, _ = _quantize_frame(frames[1])
        write(f, UInt8(0xf7))  # GCT flag=1, color_res=7, GCT_size=7
        write(f, UInt8(0))     # bg color index
        write(f, UInt8(0))     # pixel aspect ratio

        for c in palette
            write(f, UInt8(round(UInt8, Float32(c.r) * 255)))
            write(f, UInt8(round(UInt8, Float32(c.g) * 255)))
            write(f, UInt8(round(UInt8, Float32(c.b) * 255)))
        end

        # Netscape looping extension
        write(f, UInt8(0x21), UInt8(0xff), UInt8(11))
        write(f, b"NETSCAPE2.0")
        write(f, UInt8(3), UInt8(1))
        write(f, UInt16(0))  # infinite loop
        write(f, UInt8(0))

        for img in frames
            # Graphic Control Extension
            write(f, UInt8(0x21), UInt8(0xf9), UInt8(4))
            write(f, UInt8(0x00))  # disposal=none
            write(f, delay)
            write(f, UInt8(0), UInt8(0))  # transparent idx + terminator

            # Image Descriptor
            write(f, UInt8(0x2c))
            write(f, UInt16(0), UInt16(0), UInt16(w), UInt16(h))

            local_palette, indices = _quantize_frame(img)
            write(f, UInt8(0x87))  # LCT flag=1, size=7

            for c in local_palette
                write(f, UInt8(round(UInt8, Float32(c.r) * 255)))
                write(f, UInt8(round(UInt8, Float32(c.g) * 255)))
                write(f, UInt8(round(UInt8, Float32(c.b) * 255)))
            end

            write(f, UInt8(8))  # LZW min code size
            write(f, _lzw_encode(indices, UInt8(8)))
        end

        write(f, UInt8(0x3b))  # trailer
    end
    nothing
end

# ── Public API ─────────────────────────────────────────────────────────

function Tachikoma.record_gif(func::Function, filename::String,
                              width::Int, height::Int, num_frames::Int;
                              fps::Int=10,
                              font_path::String="",
                              font_size::Int=16,
                              cell_w::Int=10, cell_h::Int=20)
    gc = nothing
    if !isempty(font_path) && isfile(font_path)
        gc = GlyphCache(font_path, font_size)
    end

    tb = Tachikoma.TestBackend(width, height)
    buf = tb.buf
    area = Tachikoma.Rect(1, 1, width, height)
    bg = RGB{N0f8}(0.067, 0.075, 0.118)

    frames = Matrix{RGB{N0f8}}[]

    for i in 1:num_frames
        Tachikoma.reset!(buf)
        f = Tachikoma.Frame(buf, area, Tachikoma.GraphicsRegion[], Tachikoma.PixelSnapshot[])
        func(buf, area, i, f)

        px_data = Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[]

        img = rasterize_frame(buf, width, height, gc;
                              cell_w, cell_h, bg, pixel_snapshots=px_data)
        push!(frames, img)
    end

    _write_gif(filename, frames; fps)
    filename
end

# ── Snapshot-based rasterizer ────────────────────────────────────────

function _rasterize_snapshot(cells::Vector{Tachikoma.Cell}, width::Int, height::Int,
                             gc::Union{GlyphCache, Nothing}=nothing;
                             cell_w::Int=10, cell_h::Int=20,
                             bg::RGB{N0f8}=RGB{N0f8}(0.067, 0.075, 0.118),
                             default_fg::RGB{N0f8}=RGB{N0f8}(0.878, 0.878, 0.878),
                             pixel_snapshots::Vector{Tachikoma.PixelSnapshot}=Tachikoma.PixelSnapshot[])
    img_w = width * cell_w
    img_h = height * cell_h
    img = fill(bg, img_h, img_w)

    for cy in 1:height, cx in 1:width
        idx = (cy - 1) * width + cx
        idx > length(cells) && continue
        cell = cells[idx]
        ch = cell.char
        st = cell.style

        px0 = (cx - 1) * cell_w + 1
        py0 = (cy - 1) * cell_h + 1

        bg_rgb = tachikoma_to_rgb(st.bg)
        if bg_rgb !== nothing
            py_end = min(py0 + cell_h - 1, img_h)
            px_end = min(px0 + cell_w - 1, img_w)
            cell_view = @view img[py0:py_end, px0:px_end]
            fill!(cell_view, bg_rgb)
        end

        if ch != ' ' && ch != '\0'
            fg_rgb = tachikoma_to_rgb(st.fg)
            if fg_rgb === nothing
                fg_rgb = default_fg
            end
            if _is_braille(ch)
                _draw_braille!(img, ch, px0, py0, cell_w, cell_h, fg_rgb, st.dim)
            elseif _is_block(ch)
                _draw_block!(img, ch, px0, py0, cell_w, cell_h, fg_rgb, st.dim) ||
                    (gc !== nothing && _draw_char!(img, gc, ch, px0, py0, cell_w, cell_h, fg_rgb, st.bold, st.italic, st.dim))
            elseif gc !== nothing
                _draw_char!(img, gc, ch, px0, py0, cell_w, cell_h, fg_rgb,
                            st.bold, st.italic, st.dim)
            end
        end
    end

    # Overlay pixel regions
    for (row, col, pixels) in pixel_snapshots
        px0 = (col - 1) * cell_w + 1
        py0 = (row - 1) * cell_h + 1
        ph, pw = size(pixels)
        for sy in 1:ph, sx in 1:pw
            tx = px0 + sx - 1
            ty = py0 + sy - 1
            (1 <= tx <= img_w && 1 <= ty <= img_h) || continue
            @inbounds p = pixels[sy, sx]
            (p.r == 0x00 && p.g == 0x00 && p.b == 0x00) && continue
            @inbounds img[ty, tx] = tachikoma_to_rgb(p)
        end
    end

    img
end

# ── Snapshot-based GIF export ────────────────────────────────────────

function Tachikoma.export_gif_from_snapshots(filename::String, width::Int, height::Int,
                                             cell_snapshots::Vector{Vector{Tachikoma.Cell}},
                                             timestamps::Vector{Float64};
                                             pixel_snapshots::Vector{Vector{Tachikoma.PixelSnapshot}}=Vector{Tachikoma.PixelSnapshot}[],
                                             font_path::String="",
                                             font_size::Int=16,
                                             cell_w::Int=10, cell_h::Int=20,
                                             bg::RGB{N0f8}=RGB{N0f8}(0.067, 0.075, 0.118),
                                             default_fg::Union{Tachikoma.ColorRGB, Nothing}=nothing)
    isempty(cell_snapshots) && return filename
    gc = nothing
    if !isempty(font_path) && isfile(font_path)
        gc = GlyphCache(font_path, font_size)
    end
    fg = default_fg !== nothing ? tachikoma_to_rgb(default_fg) : RGB{N0f8}(0.878, 0.878, 0.878)

    frames = Matrix{RGB{N0f8}}[]
    for (i, cells) in enumerate(cell_snapshots)
        spx = i <= length(pixel_snapshots) ? pixel_snapshots[i] : Tachikoma.PixelSnapshot[]
        push!(frames, _rasterize_snapshot(cells, width, height, gc;
                                          cell_w, cell_h, bg, default_fg=fg, pixel_snapshots=spx))
    end

    # Estimate fps from timestamps
    fps = length(timestamps) > 1 ?
        round(Int, clamp((length(timestamps) - 1) / (timestamps[end] - timestamps[1]), 1, 60)) : 10

    _write_gif(filename, frames; fps)
    filename
end

# ── CRC32 lookup table ──────────────────────────────────────────────

const _CRC32_TABLE = let
    table = Vector{UInt32}(undef, 256)
    for n in 0:255
        c = UInt32(n)
        for _ in 1:8
            if (c & 1) != 0
                c = 0xedb88320 ⊻ (c >> 1)
            else
                c >>= 1
            end
        end
        table[n + 1] = c
    end
    table
end

function _crc32(data::Vector{UInt8}, crc::UInt32=0xffffffff)
    for b in data
        crc = _CRC32_TABLE[(UInt8(crc & 0xff) ⊻ b) + 1] ⊻ (crc >> 8)
    end
    crc ⊻ 0xffffffff
end

# ── Minimal APNG encoder ────────────────────────────────────────────

function _png_chunk(io::IO, chunk_type::Vector{UInt8}, data::Vector{UInt8})
    write(io, hton(UInt32(length(data))))
    write(io, chunk_type)
    write(io, data)
    crc = _crc32(vcat(chunk_type, data))
    write(io, hton(crc))
end

function _uncompressed_deflate(raw::Vector{UInt8})
    # Zlib header (CM=8, CINFO=7, FCHECK) + uncompressed deflate blocks
    io = IOBuffer()
    # Zlib header: CMF=0x78 (deflate, window=32768), FLG=0x01 (FCHECK=1, no dict, level=0)
    write(io, UInt8(0x78), UInt8(0x01))
    # Split into 65535-byte blocks
    pos = 1
    while pos <= length(raw)
        block_end = min(pos + 65534, length(raw))
        is_last = block_end == length(raw)
        write(io, UInt8(is_last ? 0x01 : 0x00))  # BFINAL + BTYPE=00 (no compression)
        len = UInt16(block_end - pos + 1)
        nlen = ~len
        write(io, len)
        write(io, nlen)
        write(io, @view raw[pos:block_end])
        pos = block_end + 1
    end
    # Adler32 checksum
    s1 = UInt32(1)
    s2 = UInt32(0)
    for b in raw
        s1 = (s1 + UInt32(b)) % UInt32(65521)
        s2 = (s2 + s1) % UInt32(65521)
    end
    adler = (s2 << 16) | s1
    write(io, hton(adler))
    take!(io)
end

function _encode_png_frame(img::Matrix{RGB{N0f8}})
    h, w = size(img)
    # Raw pixel data with filter byte (0 = None) per row
    raw = Vector{UInt8}(undef, h * (1 + w * 3))
    pos = 1
    for y in 1:h
        raw[pos] = 0x00  # filter: None
        pos += 1
        for x in 1:w
            @inbounds c = img[y, x]
            raw[pos]     = round(UInt8, Float32(c.r) * 255)
            raw[pos + 1] = round(UInt8, Float32(c.g) * 255)
            raw[pos + 2] = round(UInt8, Float32(c.b) * 255)
            pos += 3
        end
    end
    _uncompressed_deflate(raw)
end

function _write_apng(filename::String, frames::Vector{Matrix{RGB{N0f8}}},
                     delays_ms::Vector{Int})
    isempty(frames) && return
    h, w = size(frames[1])

    open(filename, "w") do f
        # PNG signature
        write(f, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

        # IHDR
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(w)))       # width
        write(ihdr, hton(UInt32(h)))       # height
        write(ihdr, UInt8(8))              # bit depth
        write(ihdr, UInt8(2))              # color type: RGB
        write(ihdr, UInt8(0))              # compression
        write(ihdr, UInt8(0))              # filter
        write(ihdr, UInt8(0))              # interlace
        _png_chunk(f, collect(b"IHDR"), take!(ihdr))

        # acTL (animation control)
        actl = IOBuffer()
        write(actl, hton(UInt32(length(frames))))  # num_frames
        write(actl, hton(UInt32(0)))               # num_plays (0 = infinite)
        _png_chunk(f, collect(b"acTL"), take!(actl))

        seq_num = 0  # Int — cast to UInt32 when writing to avoid type promotion

        for (i, img) in enumerate(frames)
            delay = delays_ms[min(i, length(delays_ms))]

            # fcTL (frame control)
            fctl = IOBuffer()
            write(fctl, hton(UInt32(seq_num))); seq_num += 1
            write(fctl, hton(UInt32(w)))       # width
            write(fctl, hton(UInt32(h)))       # height
            write(fctl, hton(UInt32(0)))       # x_offset
            write(fctl, hton(UInt32(0)))       # y_offset
            write(fctl, hton(UInt16(delay)))   # delay_num (ms)
            write(fctl, hton(UInt16(1000)))    # delay_den
            write(fctl, UInt8(0))              # dispose_op: none
            write(fctl, UInt8(0))              # blend_op: source
            _png_chunk(f, collect(b"fcTL"), take!(fctl))

            compressed = _encode_png_frame(img)

            if i == 1
                # First frame uses IDAT
                _png_chunk(f, collect(b"IDAT"), compressed)
            else
                # Subsequent frames use fdAT (seq_num + data)
                fdat = IOBuffer()
                write(fdat, hton(UInt32(seq_num))); seq_num += 1
                write(fdat, compressed)
                _png_chunk(f, collect(b"fdAT"), take!(fdat))
            end
        end

        # IEND
        _png_chunk(f, collect(b"IEND"), UInt8[])
    end
    nothing
end

# ── Snapshot-based APNG export ───────────────────────────────────────

function Tachikoma.export_apng_from_snapshots(filename::String, width::Int, height::Int,
                                              cell_snapshots::Vector{Vector{Tachikoma.Cell}},
                                              timestamps::Vector{Float64};
                                              pixel_snapshots::Vector{Vector{Tachikoma.PixelSnapshot}}=Vector{Tachikoma.PixelSnapshot}[],
                                              font_path::String="",
                                              font_size::Int=16,
                                              cell_w::Int=10, cell_h::Int=20,
                                              bg::RGB{N0f8}=RGB{N0f8}(0.067, 0.075, 0.118),
                                              default_fg::Union{Tachikoma.ColorRGB, Nothing}=nothing)
    isempty(cell_snapshots) && return filename
    gc = nothing
    if !isempty(font_path) && isfile(font_path)
        gc = GlyphCache(font_path, font_size)
    end
    fg = default_fg !== nothing ? tachikoma_to_rgb(default_fg) : RGB{N0f8}(0.878, 0.878, 0.878)

    frames = Matrix{RGB{N0f8}}[]
    for (i, cells) in enumerate(cell_snapshots)
        spx = i <= length(pixel_snapshots) ? pixel_snapshots[i] : Tachikoma.PixelSnapshot[]
        push!(frames, _rasterize_snapshot(cells, width, height, gc;
                                          cell_w, cell_h, bg, default_fg=fg, pixel_snapshots=spx))
    end

    # Compute per-frame delays in milliseconds from timestamps
    delays_ms = Int[]
    for i in 1:length(timestamps)
        if i < length(timestamps)
            push!(delays_ms, round(Int, (timestamps[i+1] - timestamps[i]) * 1000))
        else
            # Last frame: use previous delta or 100ms default
            push!(delays_ms, length(delays_ms) >= 1 ? delays_ms[end] : 100)
        end
    end

    _write_apng(filename, frames, delays_ms)
    filename
end

end # module
