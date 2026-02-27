# ═══════════════════════════════════════════════════════════════════════
# Recording ── .tach file generation from buffer snapshots
#
# CastRecorder struct is defined in cast_recorder.jl (included before
# terminal.jl so Terminal can hold a recorder field).
#
# Two modes:
# 1. Live recording: Ctrl+R hotkey captures each frame after draw!.
# 2. Headless: record_app() / record_widget() for docs/CI.
#
# All recordings use the .tach binary format (cell snapshots + Zstd).
# Export to SVG/GIF/APNG from the snapshots via export_svg(), etc.
# ═══════════════════════════════════════════════════════════════════════

using Dates
using Base64: base64encode


# ── Live recording control ───────────────────────────────────────────

const RECORDING_COUNTDOWN = 5.0  # seconds before capture begins

"""
    start_recording!(rec::CastRecorder, width::Int, height::Int;
                     filename::String="")

Begin a live recording session. A 5-second countdown runs first so the
"Recording in N..." notification disappears before frames are captured.
"""
function start_recording!(rec::CastRecorder, width::Int, height::Int;
                          filename::String="")
    if isempty(filename)
        # Default: timestamped file in current directory
        ts = Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
        filename = "tachikoma_$(ts).tach"
    end
    rec.active = true
    rec.width = width
    rec.height = height
    rec.start_time = time()
    rec.countdown = RECORDING_COUNTDOWN
    rec.filename = filename
    empty!(rec.timestamps)
    empty!(rec.cell_snapshots)
    empty!(rec.pixel_snapshots)
    nothing
end

"""
    stop_recording!(rec::CastRecorder) → String

Stop recording and write the .tach file. Returns the filename written.
Cell snapshots are preserved for the export modal; call `clear_recording!`
after export is complete to free memory.
"""
function stop_recording!(rec::CastRecorder)
    rec.active = false
    isempty(rec.cell_snapshots) && return rec.filename
    write_tach(rec.filename, rec.width, rec.height,
               rec.cell_snapshots, rec.timestamps, rec.pixel_snapshots)
    rec.filename
end

"""
    clear_recording!(rec::CastRecorder)

Free all recording data (timestamps, cell snapshots, pixel snapshots).
Call after export is complete or when dismissing the export modal.
"""
function clear_recording!(rec::CastRecorder)
    empty!(rec.timestamps)
    empty!(rec.cell_snapshots)
    empty!(rec.pixel_snapshots)
    nothing
end

"""
    capture_frame!(rec::CastRecorder, buf::Buffer, width::Int, height::Int;
                   gfx_regions, pixel_snapshots)

Snapshot the current buffer as cell-level data and pixel snapshots.
Called from `draw!`. No ANSI encoding is done during recording —
the .tach format stores cell snapshots directly, and export formats
(.gif, .svg, .apng) are generated on demand from the snapshots.

During the countdown period, frames are skipped so UI notifications
(like the countdown itself) don't appear in the recording.
"""
function capture_frame!(rec::CastRecorder, buf::Buffer, width::Int, height::Int;
                        gfx_regions::Vector{GraphicsRegion}=GraphicsRegion[],
                        pixel_snapshots::Vector{PixelSnapshot}=PixelSnapshot[])
    rec.active || return
    # During countdown, tick elapsed time but don't capture
    if rec.countdown > 0.0
        rec.countdown = max(0.0, RECORDING_COUNTDOWN - (time() - rec.start_time))
        if rec.countdown <= 0.0
            # Countdown just finished — reset start_time so timestamps begin at 0
            rec.start_time = time()
        end
        return
    end
    push!(rec.timestamps, time() - rec.start_time)
    push!(rec.cell_snapshots, copy(buf.content))
    # Pixel data for graphics regions (copy matrices so originals can mutate)
    push!(rec.pixel_snapshots, isempty(pixel_snapshots) ? PixelSnapshot[] :
        [(r, c, copy(px)) for (r, c, px) in pixel_snapshots])
    nothing
end


# ── Headless recording ───────────────────────────────────────────────

"""
    record_app(model::Model, filename::String;
               width=80, height=24, frames=120, fps=30,
               events=Event[])

Record a Model headlessly into a `.tach` file. Runs for `frames` frames
at the given `fps`, optionally injecting events from the `events` list.

The `events` argument is a vector of `(frame_number, event)` pairs.
Events are dispatched to `update!` when their frame number is reached.

# Example
```julia
record_app(DashboardModel(), "dashboard.tach";
           width=80, height=24, frames=180, fps=15)
```
"""
function record_app(model::Model, filename::String;
                    width::Int=80, height::Int=24,
                    frames::Int=120, fps::Int=30,
                    events::Vector{<:Tuple}=Tuple{Int,Event}[],
                    realtime::Bool=false,
                    warmup::Int=0)
    tb = TestBackend(width, height)
    buf = tb.buf
    area = Rect(1, 1, width, height)

    # Call init! with a dummy Terminal so async apps can spawn tasks
    dummy_term = Terminal(
        [Buffer(area), Buffer(area)], 1, area,
        false, false, NTuple{4,Int}[], 0, 300,
        CastRecorder(), devnull, false, gfx_none, nothing)
    init!(model, dummy_term)

    # Let async tasks spawned by init! settle (e.g. mock data fetches with sleep())
    for _ in 1:10
        yield()
        sleep(0.01)
        tq = task_queue(model)
        if tq !== nothing
            drain_tasks!(tq) do tevt
                update!(model, tevt)
            end
        end
    end

    sorted_events = sort(collect(events); by=first)
    evt_idx = 1

    cell_snapshots = Vector{Cell}[]
    pixel_snapshots = Vector{PixelSnapshot}[]
    dt = 1.0 / fps
    timestamps = Float64[]
    t = 0.0
    total_frames = warmup + frames

    # Frame pacing (same tiered wait as poll_event in the real app loop)
    next_frame = realtime ? time() : 0.0

    for frame_num in 1:total_frames
        if realtime
            while true
                remaining = next_frame - time()
                remaining <= 0.0 && break
                if remaining > 0.004
                    sleep(0.002)
                elseif remaining > 0.001
                    yield()
                else
                    break
                end
            end
            next_frame += dt
            if next_frame < time()
                next_frame = time()
            end
        end

        # Events are numbered relative to capture start (after warmup)
        capture_num = frame_num - warmup
        if capture_num > 0
            while evt_idx <= length(sorted_events) && sorted_events[evt_idx][1] <= capture_num
                update!(model, sorted_events[evt_idx][2])
                evt_idx += 1
            end
        end

        # Drain task queue before rendering (for async apps like GitHub PRs)
        tq = task_queue(model)
        if tq !== nothing
            yield()  # let async tasks complete
            drain_tasks!(tq) do tevt
                update!(model, tevt)
            end
        end

        reset!(buf)
        f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
        view(model, f)

        # Only capture after warmup
        if capture_num > 0
            push!(cell_snapshots, copy(buf.content))
            push!(pixel_snapshots, isempty(f.pixel_snapshots) ? PixelSnapshot[] :
                [(r, c, copy(px)) for (r, c, px) in f.pixel_snapshots])
            push!(timestamps, t)
            t += dt

            should_quit(model) && break
        end
    end

    write_tach(filename, width, height, cell_snapshots, timestamps, pixel_snapshots)
    filename
end

"""
    record_widget(filename::String, width::Int, height::Int,
                  num_frames::Int; fps::Int=10) do buf, area, frame_idx
        # render widgets here
    end

Record arbitrary widget rendering into a `.tach` file. The callback
receives (Buffer, Rect, frame_index) and should render into the buffer.
Pixel content is supported: use `render_graphics!(frame, data, rect)` by
accepting a Frame from the 4-argument callback form.

For single-frame static screenshots, use `num_frames=1`.

# Example
```julia
record_widget("gauge.tach", 60, 3, 1) do buf, area, frame
    render(Gauge(0.75, block=Block(title="CPU")), area, buf)
end
```
"""
function record_gif end

function record_widget(func::Function, filename::String,
                       width::Int, height::Int, num_frames::Int;
                       fps::Int=10)
    tb = TestBackend(width, height)
    buf = tb.buf
    area = Rect(1, 1, width, height)

    cell_snapshots = Vector{Cell}[]
    pixel_snapshots = Vector{PixelSnapshot}[]
    dt = 1.0 / fps
    timestamps = Float64[]
    t = 0.0

    for i in 1:num_frames
        reset!(buf)
        f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
        if applicable(func, buf, area, i, f)
            func(buf, area, i, f)
        else
            func(buf, area, i)
        end
        push!(cell_snapshots, copy(buf.content))
        push!(pixel_snapshots, isempty(f.pixel_snapshots) ? PixelSnapshot[] :
            [(r, c, copy(px)) for (r, c, px) in f.pixel_snapshots])
        push!(timestamps, t)
        t += dt
    end

    write_tach(filename, width, height, cell_snapshots, timestamps, pixel_snapshots)
    filename
end

# ── Bold font variant discovery ──────────────────────────────────────

const _FONT_VARIANT_CACHE = Dict{Tuple{String,String}, String}()

"""
    find_font_variant(font_path, variant) → String

Find a style variant of a font file (e.g. "Bold", "Italic", "BoldItalic").
Returns the path to the variant file, or `""` if not found.
Results are cached to avoid repeated filesystem lookups during export.
"""
function find_font_variant(font_path::String, variant::String)
    isempty(font_path) && return ""
    key = (font_path, variant)
    haskey(_FONT_VARIANT_CACHE, key) && return _FONT_VARIANT_CACHE[key]
    result = _find_font_variant_uncached(font_path, variant)
    _FONT_VARIANT_CACHE[key] = result
    result
end

function _find_font_variant_uncached(font_path::String, variant::String)
    dir = dirname(font_path)
    base = basename(font_path)
    for (from, to) in [("-Regular", "-$variant"), ("-regular", "-$(lowercase(variant))"),
                        ("Regular", variant)]
        if occursin(from, base)
            candidate = joinpath(dir, replace(base, from => to))
            isfile(candidate) && return candidate
        end
    end
    name, ext = splitext(base)
    candidate = joinpath(dir, name * "-$variant" * ext)
    isfile(candidate) && return candidate
    ""
end

find_bold_variant(font_path::String) = find_font_variant(font_path, "Bold")

# ── Extension dispatch stubs ─────────────────────────────────────────

function export_gif_from_snapshots end
function export_apng_from_snapshots end

function gif_extension_loaded()
    hasmethod(export_gif_from_snapshots,
              Tuple{String, Int, Int, Vector{Vector{Cell}}, Vector{Float64}};
              world=Base.get_world_counter())
end

# ── Extension convenience loaders ─────────────────────────────────

const _FREETYPEABSTRACTION_UUID = Base.UUID("663a7486-cb36-511b-a19d-713bb74d65c9")
const _COLORTYPES_UUID          = Base.UUID("3da002f7-5984-5a60-b8a6-cbb66c0b333f")
const _TABLES_UUID              = Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c")

_pkg_available(name::String, uuid::Base.UUID) =
    Base.locate_package(Base.PkgId(uuid, name)) !== nothing

_pkg_loaded(name::String, uuid::Base.UUID) =
    haskey(Base.loaded_modules, Base.PkgId(uuid, name))

"""
    enable_gif()

Ensure the GIF export extension is loaded. If `FreeTypeAbstraction` and
`ColorTypes` are installed but not yet imported, this triggers their
loading so `TachikomaGifExt` activates. Errors with an install hint
if the packages are missing.
"""
function enable_gif()
    gif_extension_loaded() && return nothing
    missing_pkgs = String[]
    _pkg_available("FreeTypeAbstraction", _FREETYPEABSTRACTION_UUID) || push!(missing_pkgs, "FreeTypeAbstraction")
    _pkg_available("ColorTypes", _COLORTYPES_UUID) || push!(missing_pkgs, "ColorTypes")
    if !isempty(missing_pkgs)
        add_cmd = join(["\"$p\"" for p in missing_pkgs], ", ")
        error("GIF export requires $(join(missing_pkgs, ", ")).\n  Install with: using Pkg; Pkg.add([$add_cmd])")
    end
    Base.require(Main, :FreeTypeAbstraction)
    Base.require(Main, :ColorTypes)
    gif_extension_loaded() || @warn "TachikomaGifExt did not activate — possible version incompatibility."
    nothing
end

"""
    tables_extension_loaded() → Bool

Return `true` if the Tables.jl extension has been loaded (i.e. `DataTable`
accepts a Tables.jl-compatible source).
"""
function tables_extension_loaded()
    hasmethod(DataTable, Tuple{Any}; world=Base.get_world_counter())
end

"""
    enable_tables()

Ensure the Tables.jl extension is loaded. If `Tables` is installed but
not yet imported, this triggers its loading so `TachikomaTablesExt`
activates. Errors with an install hint if the package is missing.
"""
function enable_tables()
    tables_extension_loaded() && return nothing
    if !_pkg_available("Tables", _TABLES_UUID)
        error("Tables integration requires Tables.jl.\n  Install with: using Pkg; Pkg.add(\"Tables\")")
    end
    Base.require(Main, :Tables)
    tables_extension_loaded() || @warn "TachikomaTablesExt did not activate — possible version incompatibility."
    nothing
end

# ── SVG export ───────────────────────────────────────────────────────

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

# ── Font discovery ────────────────────────────────────────────────────

const _MONO_KEYWORDS = [
    "mono", "code", "menlo", "monaco", "courier", "meslo", "fira",
    "consol", "sfnsmono", "hack", "iosevka", "source code",
    "inconsolata", "dejavu sans mono", "liberation mono", "noto mono",
    "ibm plex mono",
]

const _FONT_EXTENSIONS = (".ttf", ".ttc", ".otf")

const _DISCOVERED_FONTS = Ref{Union{Nothing, Vector{NamedTuple{(:name, :path), Tuple{String, String}}}}}(nothing)

function _font_search_dirs()
    dirs = String[]
    if Sys.isapple()
        push!(dirs, "/System/Library/Fonts", "/Library/Fonts")
        push!(dirs, joinpath(homedir(), "Library", "Fonts"))
    elseif Sys.islinux()
        push!(dirs, "/usr/share/fonts", "/usr/local/share/fonts")
        push!(dirs, joinpath(homedir(), ".local", "share", "fonts"))
        push!(dirs, joinpath(homedir(), ".fonts"))
    elseif Sys.iswindows()
        push!(dirs, raw"C:\Windows\Fonts")
        localappdata = get(ENV, "LOCALAPPDATA", "")
        if !isempty(localappdata)
            push!(dirs, joinpath(localappdata, "Microsoft", "Windows", "Fonts"))
        end
    end
    filter(isdir, dirs)
end

function _name_from_filename(fname::String)
    base = replace(fname, r"\.(ttf|ttc|otf)$"i => "")
    base = replace(base, r"[-_](Regular|Bold|Italic|Light|Medium|Thin|Black|ExtraBold|SemiBold|ExtraLight|BoldItalic|LightItalic|MediumItalic)$"i => "")
    # Insert spaces before capitals (CamelCase → Camel Case)
    base = replace(base, r"([a-z])([A-Z])" => s"\1 \2")
    base = replace(base, r"[-_]" => " ")
    strip(base)
end

function _is_mono_font(fname_lower::String)
    any(kw -> occursin(kw, fname_lower), _MONO_KEYWORDS)
end

"""
    discover_mono_fonts() → Vector{NamedTuple{(:name,:path), Tuple{String,String}}}

Scan system font directories for monospace fonts. Results are cached
for the session. The first entry is always `(name="(none — text hidden)", path="")`
for users who only want SVG export.
"""
function discover_mono_fonts()
    cached = _DISCOVERED_FONTS[]
    cached !== nothing && return cached

    found = Dict{String, String}()  # name => path (prefer Regular weight)

    for dir in _font_search_dirs()
        for (root, _dirs, files) in walkdir(dir)
            for f in files
                fl = lowercase(f)
                any(ext -> endswith(fl, ext), _FONT_EXTENSIONS) || continue
                _is_mono_font(fl) || continue

                path = joinpath(root, f)
                name = _name_from_filename(f)
                isempty(name) && continue

                if !haskey(found, name) || occursin(r"regular"i, f)
                    found[name] = path
                end
            end
        end
    end

    fonts = [(name=k, path=v) for (k, v) in found]
    sort!(fonts; by=x -> lowercase(x.name))
    pushfirst!(fonts, (name="(none — text hidden)", path=""))

    _DISCOVERED_FONTS[] = fonts
    fonts
end

# ── Export preferences ────────────────────────────────────────────────

const EXPORT_FONT_PREF = Ref("")
const EXPORT_FORMATS_PREF = Ref(Set{String}())
const EXPORT_THEME_PREF = Ref("")
const EXPORT_EMBED_FONT_PREF = Ref(true)

function load_export_prefs!()
    EXPORT_FONT_PREF[] = @load_preference("export_font", "")
    fmts_str = @load_preference("export_formats", "gif,svg")
    EXPORT_FORMATS_PREF[] = Set(filter(!isempty, Base.split(fmts_str, ",")))
    EXPORT_THEME_PREF[] = @load_preference("export_theme", "")
    EXPORT_EMBED_FONT_PREF[] = @load_preference("export_embed_font", true)
end

function save_export_prefs!(font_path::String, formats::Set{String};
                            theme_name::String="", embed_font::Bool=true)
    EXPORT_FONT_PREF[] = font_path
    EXPORT_FORMATS_PREF[] = formats
    EXPORT_THEME_PREF[] = theme_name
    EXPORT_EMBED_FONT_PREF[] = embed_font
    fmts_str = join(sort(collect(formats)), ",")
    @set_preferences!("export_font" => font_path, "export_formats" => fmts_str,
                       "export_theme" => theme_name, "export_embed_font" => embed_font)
end
