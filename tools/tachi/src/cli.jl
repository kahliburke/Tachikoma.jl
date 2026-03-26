# ═══════════════════════════════════════════════════════════════════════
# CLI argument parsing and dispatch
# ═══════════════════════════════════════════════════════════════════════

function cli_main(args::Vector{String})
    isempty(args) && (print_usage(); return)

    cmd = args[1]
    rest = args[2:end]

    if cmd == "render"
        cmd_render(rest)
    elseif cmd == "info"
        cmd_info(rest)
    elseif cmd == "fonts"
        cmd_fonts()
    elseif cmd in ("-i", "--interactive")
        cmd_interactive(rest)
    elseif cmd in ("-h", "--help", "help")
        print_usage()
    elseif endswith(cmd, ".tach")
        # Shortcut: tachi file.tach → tachi render file.tach
        cmd_render(args)
    else
        printstyled(stderr, "Unknown command: $cmd\n"; color=:red)
        print_usage()
        exit(1)
    end
end

function print_usage()
    println("""
    tachi — Tachikoma recording tool

    Usage:
      tachi render <file.tach> [options]    Render .tach to GIF/APNG
      tachi info <file.tach>                Show recording info
      tachi fonts                           List available monospace fonts
      tachi -i [file.tach]                  Interactive TUI mode
      tachi <file.tach> [options]           Shortcut for render

    Render options:
      -o, --output <path>       Output file (default: <input>.gif)
      -f, --font <name|path>    Font name or path (use `tachi fonts` to list)
      --font-size <n>           Font size in pixels (default: 16)
      --scale <f>               Scale factor (default: 1.0)
      --skip <n>                Use every Nth frame (default: 1)
      --compress                Compress dead space before rendering
      --bg <color>              Background: black, dark (default), white, or r,g,b
      --format <fmt>            Output format: gif (default), apng
      --fps <n>                 Override frame rate
      --cell-w <n>              Cell width in pixels (default: 10)
      --cell-h <n>              Cell height in pixels (default: 20)

    Examples:
      tachi render demo.tach -o demo.gif --font "Meslo" --bg black
      tachi demo.tach --scale 0.7 --skip 2
      tachi info demo.tach
      tachi fonts
      tachi -i demo.tach""")
end

# ── Argument parser ──────────────────────────────────────────────────

function parse_render_opts(args)
    opts = Dict{Symbol, Any}(
        :input => nothing,
        :output => nothing,
        :font => "",
        :font_size => 16,
        :scale => 1.0,
        :skip => 1,
        :compress => false,
        :bg => "dark",
        :format => "gif",
        :fps => nothing,
        :cell_w => 10,
        :cell_h => 20,
    )
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "-o" || a == "--output"
            i += 1; opts[:output] = args[i]
        elseif a == "-f" || a == "--font"
            i += 1; opts[:font] = args[i]
        elseif a == "--font-size"
            i += 1; opts[:font_size] = parse(Int, args[i])
        elseif a == "--scale"
            i += 1; opts[:scale] = parse(Float64, args[i])
        elseif a == "--skip"
            i += 1; opts[:skip] = parse(Int, args[i])
        elseif a == "--compress"
            opts[:compress] = true
        elseif a == "--bg"
            i += 1; opts[:bg] = args[i]
        elseif a == "--format"
            i += 1; opts[:format] = lowercase(args[i])
        elseif a == "--fps"
            i += 1; opts[:fps] = parse(Int, args[i])
        elseif a == "--cell-w"
            i += 1; opts[:cell_w] = parse(Int, args[i])
        elseif a == "--cell-h"
            i += 1; opts[:cell_h] = parse(Int, args[i])
        elseif startswith(a, "-")
            printstyled(stderr, "Unknown option: $a\n"; color=:red)
            exit(1)
        elseif opts[:input] === nothing
            opts[:input] = a
        else
            printstyled(stderr, "Unexpected argument: $a\n"; color=:red)
            exit(1)
        end
        i += 1
    end
    opts
end

# ── Font resolution ──────────────────────────────────────────────────

function resolve_font(font_spec::String)
    isempty(font_spec) && return ""
    isfile(font_spec) && return font_spec
    fonts = Tachikoma.discover_mono_fonts()
    # Exact match first
    for f in fonts
        lowercase(f.name) == lowercase(font_spec) && return f.path
    end
    # Substring match
    for f in fonts
        occursin(lowercase(font_spec), lowercase(f.name)) && return f.path
    end
    printstyled(stderr, "Font not found: $font_spec\n"; color=:red)
    printstyled(stderr, "Use `tachi fonts` to list available fonts.\n"; color=:yellow)
    exit(1)
end

# ── Background color parsing ─────────────────────────────────────────

function parse_bg(bg_str::String)
    bg_str == "black" && return CT.RGB{CT.FixedPointNumbers.N0f8}(0.0, 0.0, 0.0)
    bg_str == "dark"  && return CT.RGB{CT.FixedPointNumbers.N0f8}(0.067, 0.075, 0.118)
    bg_str == "white" && return CT.RGB{CT.FixedPointNumbers.N0f8}(1.0, 1.0, 1.0)
    parts = split(bg_str, ',')
    if length(parts) == 3
        r, g, b = parse.(Int, parts)
        return CT.RGB{CT.FixedPointNumbers.N0f8}(r/255, g/255, b/255)
    end
    printstyled(stderr, "Invalid --bg: $bg_str (use: black, dark, white, or r,g,b)\n"; color=:red)
    exit(1)
end

# ── Commands ─────────────────────────────────────────────────────────

function cmd_info(args)
    if isempty(args)
        printstyled(stderr, "Usage: tachi info <file.tach>\n"; color=:yellow)
        exit(1)
    end
    path = args[1]
    isfile(path) || (printstyled(stderr, "File not found: $path\n"; color=:red); exit(1))

    w, h, cells, ts, pixels = Tachikoma.load_tach(path)
    nframes = length(cells)
    duration = nframes > 1 ? ts[end] - ts[1] : 0.0
    avg_fps = duration > 0 ? (nframes - 1) / duration : 0.0
    has_pixels = any(!isempty, pixels)

    println("File:       $path")
    println("Size:       $(round(filesize(path) / 1024, digits=1)) KB")
    println("Terminal:   $(w)×$(h) cells")
    println("Frames:     $nframes")
    println("Duration:   $(round(duration, digits=1))s")
    println("Avg FPS:    $(round(avg_fps, digits=1))")
    println("Pixels:     $(has_pixels ? "yes" : "no")")
    if nframes > 1
        delays = diff(ts)
        println("Min delay:  $(round(minimum(delays) * 1000, digits=1))ms")
        println("Max delay:  $(round(maximum(delays) * 1000, digits=1))ms")
    end
end

function cmd_fonts()
    fonts = Tachikoma.discover_mono_fonts()
    if isempty(fonts)
        println("No monospace fonts found.")
        return
    end
    # Column widths
    max_name = maximum(length(f.name) for f in fonts)
    for f in fonts
        isempty(f.path) && continue
        printstyled(rpad(f.name, max_name + 2); color=:cyan)
        printstyled(f.path, "\n"; color=:light_black)
    end
    println("\n$(length(fonts)) fonts found")
end

function cmd_render(args)
    opts = parse_render_opts(args)
    if opts[:input] === nothing
        printstyled(stderr, "Usage: tachi render <file.tach> [options]\n"; color=:yellow)
        exit(1)
    end
    render_tach(opts)
end

function cmd_interactive(args)
    # TODO: TUI mode
    printstyled("Interactive mode coming soon!\n"; color=:yellow)
    if !isempty(args) && isfile(args[1])
        printstyled("Would open: $(args[1])\n"; color=:cyan)
    end
end
