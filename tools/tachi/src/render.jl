# ═══════════════════════════════════════════════════════════════════════
# Render — load .tach, apply options, export to GIF/APNG
# ═══════════════════════════════════════════════════════════════════════

function render_tach(opts::Dict{Symbol, Any})
    path = opts[:input]
    isfile(path) || (printstyled(stderr, "File not found: $path\n"; color=:red); exit(1))

    # Default output filename
    output = opts[:output]
    if output === nothing
        base = replace(path, r"\.tach$" => "")
        output = base * "." * opts[:format]
    end

    # Load
    printstyled("Loading "; color=:cyan)
    println(path)
    w, h, cells, ts, pixels = Tachikoma.load_tach(path)
    nframes = length(cells)
    duration = nframes > 1 ? ts[end] - ts[1] : 0.0
    println("  $(w)×$(h) cells, $nframes frames, $(round(duration, digits=1))s")

    # Compress dead space
    if opts[:compress]
        printstyled("Compressing dead space...\n"; color=:cyan)
        cells, ts, pixels = Tachikoma.compress_dead_space(cells, ts; pixel_snapshots=pixels)
        println("  → $(length(cells)) frames after compression")
    end

    # Skip frames
    skip = opts[:skip]
    if skip > 1
        idx = 1:skip:length(cells)
        cells = cells[collect(idx)]
        ts = ts[collect(idx)]
        pixels = pixels[collect(idx)]
        println("  → $(length(cells)) frames (skip=$skip)")
    end

    # Resolve font
    font_path = resolve_font(opts[:font])
    if !isempty(font_path)
        printstyled("Font: "; color=:cyan)
        println(font_path)
    end

    # Parse background
    bg = parse_bg(opts[:bg])

    # Build kwargs
    kwargs = Dict{Symbol, Any}(
        :font_path => font_path,
        :font_size => opts[:font_size],
        :cell_w => opts[:cell_w],
        :cell_h => opts[:cell_h],
        :bg => bg,
        :scale => opts[:scale],
        :pixel_snapshots => pixels,
    )
    if opts[:fps] !== nothing
        kwargs[:fps] = opts[:fps]
    end

    # GIF extension is loaded automatically because Tachi depends on
    # FreeTypeAbstraction + ColorTypes (Tachikoma's weakdeps).
    fmt = opts[:format]
    printstyled("Rendering "; color=:cyan)
    println("$nframes frames → $output ($(fmt))")

    t0 = time()
    if fmt == "gif"
        Tachikoma.export_gif_from_snapshots(output, w, h, cells, ts; kwargs...)
    elseif fmt == "apng"
        Tachikoma.export_apng_from_snapshots(output, w, h, cells, ts; kwargs...)
    else
        printstyled(stderr, "Unknown format: $fmt (supported: gif, apng)\n"; color=:red)
        exit(1)
    end
    elapsed = time() - t0

    size_mb = filesize(output) / 1024 / 1024
    printstyled("Done "; color=:green, bold=true)
    println("$(round(size_mb, digits=2)) MB in $(round(elapsed, digits=1))s → $output")
end
