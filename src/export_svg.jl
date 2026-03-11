# ═══════════════════════════════════════════════════════════════════════
# SVG Export ── animated SVG generation from cell snapshots
# ═══════════════════════════════════════════════════════════════════════

using Base64: base64encode

function _svg_escape(s::String)
    replace(replace(replace(s, '&' => "&amp;"), '<' => "&lt;"), '>' => "&gt;")
end

function _color_to_hex(c::ColorRGB)
    string("#", lpad(string(c.r, base=16), 2, '0'),
                lpad(string(c.g, base=16), 2, '0'),
                lpad(string(c.b, base=16), 2, '0'))
end
_color_to_hex(c::Color256) = _color_to_hex(to_rgb(c))
_color_to_hex(::NoColor) = nothing

@inline _is_braille(ch::Char) = '⠀' <= ch <= '⣿'  # U+2800..U+28FF

# Braille dot bit layout (row, col) → bit mask
const _BRAILLE_BITS = (
    (0x01, 0x08),  # row 0
    (0x02, 0x10),  # row 1
    (0x04, 0x20),  # row 2
    (0x40, 0x80),  # row 3
)

function _svg_braille_rects(io::IO, ch::Char, px::Int, py::Int,
                            cell_w::Int, cell_h::Int, fg_hex::String)
    mask = UInt32(ch) - UInt32('⠀')
    mask == 0 && return
    dot_r = max(1, round(Int, min(cell_w, cell_h) * 0.12))
    dot_d = dot_r * 2 + 1
    for row in 0:3, col in 0:1
        (mask & _BRAILLE_BITS[row + 1][col + 1]) == 0 && continue
        dx = round(Int, cell_w * (0.3 + col * 0.4)) - dot_r - 1
        dy = round(Int, cell_h * (0.125 + row * 0.25)) - dot_r - 1
        write(io, """  <rect x="$(px + dx)" y="$(py + dy)" width="$dot_d" height="$dot_d" fill="$fg_hex"/>\n""")
    end
end

@inline _is_block(ch::Char) = '▀' <= ch <= '▟'  # U+2580..U+259F

function _svg_block_rect(io::IO, ch::Char, px::Int, py::Int,
                         cell_w::Int, cell_h::Int, fg_hex::String)
    c = UInt32(ch)
    # Map block character to (x_frac, y_frac, w_frac, h_frac)
    rect = if     c == 0x2580; (0.0, 0.0, 1.0, 0.5)    # ▀ upper half
    elseif c == 0x2581; (0.0, 0.875, 1.0, 0.125)  # ▁ lower 1/8
    elseif c == 0x2582; (0.0, 0.75, 1.0, 0.25)    # ▂ lower 1/4
    elseif c == 0x2583; (0.0, 0.625, 1.0, 0.375)  # ▃ lower 3/8
    elseif c == 0x2584; (0.0, 0.5, 1.0, 0.5)      # ▄ lower half
    elseif c == 0x2585; (0.0, 0.375, 1.0, 0.625)  # ▅ lower 5/8
    elseif c == 0x2586; (0.0, 0.25, 1.0, 0.75)    # ▆ lower 3/4
    elseif c == 0x2587; (0.0, 0.125, 1.0, 0.875)  # ▇ lower 7/8
    elseif c == 0x2588; (0.0, 0.0, 1.0, 1.0)      # █ full block
    elseif c == 0x2589; (0.0, 0.0, 0.875, 1.0)    # ▉ left 7/8
    elseif c == 0x258a; (0.0, 0.0, 0.75, 1.0)     # ▊ left 3/4
    elseif c == 0x258b; (0.0, 0.0, 0.625, 1.0)    # ▋ left 5/8
    elseif c == 0x258c; (0.0, 0.0, 0.5, 1.0)      # ▌ left half
    elseif c == 0x258d; (0.0, 0.0, 0.375, 1.0)    # ▍ left 3/8
    elseif c == 0x258e; (0.0, 0.0, 0.25, 1.0)     # ▎ left 1/4
    elseif c == 0x258f; (0.0, 0.0, 0.125, 1.0)    # ▏ left 1/8
    elseif c == 0x2590; (0.5, 0.0, 0.5, 1.0)      # ▐ right half
    elseif c == 0x2591  # ░ light shade — stippled pattern
        write(io, """  <rect x="$px" y="$py" width="$cell_w" height="$cell_h" fill="$fg_hex" mask="url(#m1)"/>\n""")
        return true
    elseif c == 0x2592  # ▒ medium shade — checkerboard pattern
        write(io, """  <rect x="$px" y="$py" width="$cell_w" height="$cell_h" fill="$fg_hex" mask="url(#m2)"/>\n""")
        return true
    elseif c == 0x2593  # ▓ dark shade — dense stipple pattern
        write(io, """  <rect x="$px" y="$py" width="$cell_w" height="$cell_h" fill="$fg_hex" mask="url(#m3)"/>\n""")
        return true
    elseif c == 0x2594; (0.0, 0.0, 1.0, 0.125)    # ▔ upper 1/8
    elseif c == 0x2595; (0.875, 0.0, 0.125, 1.0)  # ▕ right 1/8
    elseif c == 0x2596; (0.0, 0.5, 0.5, 0.5)      # ▖ quadrant lower left
    elseif c == 0x2597; (0.5, 0.5, 0.5, 0.5)      # ▗ quadrant lower right
    elseif c == 0x2598; (0.0, 0.0, 0.5, 0.5)      # ▘ quadrant upper left
    elseif c == 0x259d; (0.5, 0.0, 0.5, 0.5)      # ▝ quadrant upper right
    else; nothing
    end
    rect === nothing && return false
    xf, yf, wf, hf = rect
    # Use floor consistently so adjacent blocks tile without gaps
    rx = px + floor(Int, xf * cell_w)
    ry = py + floor(Int, yf * cell_h)
    rw = floor(Int, (xf + wf) * cell_w) - floor(Int, xf * cell_w)
    rh = floor(Int, (yf + hf) * cell_h) - floor(Int, yf * cell_h)
    write(io, """  <rect x="$rx" y="$ry" width="$rw" height="$rh" fill="$fg_hex"/>\n""")
    true
end

const _SVG_DEFAULT_FG = "#e0e0e0"
const _SVG_DEFAULT_BG = "#11131e"

const _SVG_DEFAULT_FONTS = "'MesloLGS NF','MesloLGM NF','JetBrains Mono','Menlo','DejaVu Sans Mono','Consolas',monospace"

"""
    export_svg(filename, width, height, cell_snapshots, timestamps;
               font_family=_SVG_DEFAULT_FONTS, font_path="",
               bg_color=_SVG_DEFAULT_BG, fg_color=_SVG_DEFAULT_FG,
               cell_w=8, cell_h=16) → String

Export an animated SVG from cell snapshots. Each frame becomes a `<g>` group
with SMIL visibility animation timed to the recording timestamps.

When `font_path` points to a .ttf/.otf file, the font is embedded via
base64 `@font-face` so the SVG renders identically on any machine.
Returns the filename written.
"""
function export_svg(filename::String, width::Int, height::Int,
                    cell_snapshots::Vector{Vector{Cell}},
                    timestamps::Vector{Float64};
                    font_family::String=_SVG_DEFAULT_FONTS,
                    font_path::String="",
                    bg_color::String=_SVG_DEFAULT_BG,
                    fg_color::String=_SVG_DEFAULT_FG,
                    cell_w::Int=8, cell_h::Int=16)
    isempty(cell_snapshots) && return filename
    nframes = length(cell_snapshots)
    img_w = width * cell_w
    img_h = height * cell_h
    total_dur = nframes > 1 ? timestamps[end] + (timestamps[end] - timestamps[end-1]) : 1.0

    io = IOBuffer()
    total_dur_s = round(total_dur, digits=3)

    write(io, """<?xml version="1.0" encoding="UTF-8"?>\n""")
    write(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$img_w" height="$img_h" """)
    write(io, """viewBox="0 0 $img_w $img_h" style="background:$(bg_color);color-scheme:dark">\n""")

    # Stipple patterns for shade characters (░▒▓)
    write(io, "<defs>\n")
    # ░ light shade: sparse dots ~25% (4×2 tile, 2 dots)
    write(io, """<pattern id="stip1" width="4" height="2" patternUnits="userSpaceOnUse">""")
    write(io, """<rect x="0" y="0" width="1" height="1" fill="white"/>""")
    write(io, """<rect x="2" y="1" width="1" height="1" fill="white"/></pattern>\n""")
    # ▒ medium shade: checkerboard ~50% (2×2 tile)
    write(io, """<pattern id="stip2" width="2" height="2" patternUnits="userSpaceOnUse">""")
    write(io, """<rect x="0" y="0" width="1" height="1" fill="white"/>""")
    write(io, """<rect x="1" y="1" width="1" height="1" fill="white"/></pattern>\n""")
    # ▓ dark shade: dense ~75% (4×2 tile, 6 dots = inverse of light)
    write(io, """<pattern id="stip3" width="4" height="2" patternUnits="userSpaceOnUse">""")
    write(io, """<rect width="4" height="2" fill="white"/>""")
    write(io, """<rect x="0" y="0" width="1" height="1" fill="black"/>""")
    write(io, """<rect x="2" y="1" width="1" height="1" fill="black"/></pattern>\n""")
    # Masks referencing the patterns
    write(io, """<mask id="m1"><rect width="$img_w" height="$img_h" fill="url(#stip1)"/></mask>\n""")
    write(io, """<mask id="m2"><rect width="$img_w" height="$img_h" fill="url(#stip2)"/></mask>\n""")
    write(io, """<mask id="m3"><rect width="$img_w" height="$img_h" fill="url(#stip3)"/></mask>\n""")
    write(io, "</defs>\n")

    # CSS for text styling only — frame visibility uses SMIL <animate>
    # (SMIL shares a single time base, avoiding flicker from independent CSS animations)
    write(io, "<style>\n")
    # Embed font via base64 @font-face if a font file is provided
    if !isempty(font_path) && isfile(font_path)
        font_data = read(font_path)
        b64 = base64encode(font_data)
        ext = lowercase(splitext(font_path)[2])
        fmt = ext == ".otf" ? "opentype" : "truetype"
        mime = ext == ".otf" ? "font/opentype" : "font/ttf"
        write(io, "@font-face{font-family:'EmbeddedFont';src:url('data:$mime;base64,$b64') format('$fmt');font-weight:normal;font-style:normal;}\n")
        # Embed style variants if available
        for (variant, css_weight, css_style) in [("Bold", "bold", "normal"),
                                                  ("Italic", "normal", "italic"),
                                                  ("BoldItalic", "bold", "italic")]
            vpath = find_font_variant(font_path, variant)
            if !isempty(vpath) && isfile(vpath)
                vdata = read(vpath)
                vb64 = base64encode(vdata)
                write(io, "@font-face{font-family:'EmbeddedFont';src:url('data:$mime;base64,$vb64') format('$fmt');font-weight:$css_weight;font-style:$css_style;}\n")
            end
        end
        write(io, "text{font-family:'EmbeddedFont',$font_family;font-size:$(max(1, cell_h - 2))px;white-space:pre;}\n")
    else
        write(io, "text{font-family:$font_family;font-size:$(max(1, cell_h - 2))px;white-space:pre;}\n")
    end
    write(io, "</style>\n")

    # Solid background rect
    write(io, """<rect width="$img_w" height="$img_h" fill="$(bg_color)"/>\n""")

    for (fi, cells) in enumerate(cell_snapshots)
        t_begin = timestamps[fi]
        t_end = fi < nframes ? timestamps[fi + 1] : total_dur
        frac_on  = t_begin / total_dur
        frac_off = t_end / total_dur

        write(io, """<g visibility="hidden">\n""")

        # SMIL discrete animation: visibility toggles at exact fractions
        if frac_on ≈ 0.0
            # First frame: visible immediately, hidden at frac_off
            write(io, """  <animate attributeName="visibility" dur="$(total_dur_s)s" """)
            write(io, """repeatCount="indefinite" calcMode="discrete" """)
            write(io, """values="visible;hidden" keyTimes="0;$(round(frac_off, digits=6))"/>\n""")
        elseif fi == nframes
            # Last frame: hidden until frac_on, then visible until loop
            write(io, """  <animate attributeName="visibility" dur="$(total_dur_s)s" """)
            write(io, """repeatCount="indefinite" calcMode="discrete" """)
            write(io, """values="hidden;visible" keyTimes="0;$(round(frac_on, digits=6))"/>\n""")
        else
            # Middle frame: hidden → visible at frac_on → hidden at frac_off
            write(io, """  <animate attributeName="visibility" dur="$(total_dur_s)s" """)
            write(io, """repeatCount="indefinite" calcMode="discrete" """)
            write(io, """values="hidden;visible;hidden" keyTimes="0;$(round(frac_on, digits=6));$(round(frac_off, digits=6))"/>\n""")
        end

        # Background rects
        for cy in 1:height, cx in 1:width
            idx = (cy - 1) * width + cx
            idx > length(cells) && continue
            cell = cells[idx]
            bg_hex = _color_to_hex(cell.style.bg)
            bg_hex === nothing && continue
            px = (cx - 1) * cell_w
            py = (cy - 1) * cell_h
            write(io, """  <rect x="$px" y="$py" width="$cell_w" height="$cell_h" fill="$bg_hex"/>\n""")
        end

        # Text — one <text> per row, grouped by style runs into <tspan>
        # Braille characters are rendered as <rect> dots instead of text.
        for cy in 1:height
            py = (cy - 1) * cell_h + max(0, cell_h - 3)  # baseline offset
            write(io, """  <text y="$py">\n""")
            run_start = 1
            while run_start <= width
                idx = (cy - 1) * width + run_start
                idx > length(cells) && break
                cell = cells[idx]
                cur_style = cell.style
                run_end = run_start
                while run_end < width
                    next_idx = (cy - 1) * width + run_end + 1
                    next_idx > length(cells) && break
                    cells[next_idx].style == cur_style || break
                    run_end += 1
                end
                chars = IOBuffer()
                all_space = true
                for cx in run_start:run_end
                    ci = (cy - 1) * width + cx
                    ci > length(cells) && break
                    ch = cells[ci].char
                    if ch == '\0' || _is_braille(ch) || _is_block(ch)
                        write(chars, ' ')  # rendered as rects below
                    else
                        write(chars, _svg_escape(string(ch)))
                        ch != ' ' && (all_space = false)
                    end
                end
                if !all_space
                    px = (run_start - 1) * cell_w
                    run_len = run_end - run_start + 1
                    span_w = run_len * cell_w
                    fg_hex = _color_to_hex(cur_style.fg)
                    fg_hex === nothing && (fg_hex = fg_color)
                    attrs = """x="$px" textLength="$span_w" lengthAdjust="spacingAndGlyphs" fill="$fg_hex\""""
                    if cur_style.bold
                        attrs *= """ font-weight="bold" stroke="$fg_hex" stroke-width="0.4\""""
                    end
                    cur_style.italic && (attrs *= """ font-style="italic\"""")
                    cur_style.dim && (attrs *= """ opacity="0.5\"""")
                    write(io, """    <tspan $attrs>$(String(take!(chars)))</tspan>\n""")
                else
                    take!(chars)  # discard
                end
                run_start = run_end + 1
            end
            write(io, """  </text>\n""")
        end

        # Braille + block characters — rendered as rects (font-independent)
        for cy in 1:height, cx in 1:width
            idx = (cy - 1) * width + cx
            idx > length(cells) && continue
            cell = cells[idx]
            ch = cell.char
            (_is_braille(ch) || _is_block(ch)) || continue
            fg_hex = _color_to_hex(cell.style.fg)
            fg_hex === nothing && (fg_hex = fg_color)
            px = (cx - 1) * cell_w
            py = (cy - 1) * cell_h
            if cell.style.dim
                write(io, """  <g opacity="0.5">\n""")
            end
            if _is_braille(ch)
                _svg_braille_rects(io, ch, px, py, cell_w, cell_h, fg_hex)
            else
                _svg_block_rect(io, ch, px, py, cell_w, cell_h, fg_hex)
            end
            if cell.style.dim
                write(io, """  </g>\n""")
            end
        end

        write(io, "</g>\n")
    end

    write(io, "</svg>\n")

    open(filename, "w") do f
        write(f, String(take!(io)))
    end
    filename
end
