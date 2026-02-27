# ═══════════════════════════════════════════════════════════════════════
# generate_assets.jl ── Render all doc assets: hero, widget examples, app demos
#
# Uses a hash-based cache so only changed renders are re-generated.
# Cache maps: SHA256(source) → SHA256(.tach file)
# Stored in docs/.render_cache.json, persists across processes.
#
# Usage:
#   julia --project=docs docs/generate_assets.jl [flags]
#
# Flags:
#   --force       Regenerate everything (ignore cache)
#   --hero        Only render hero assets
#   --examples    Only render widget examples from markdown
#   --apps        Only render app demos
#
# Default (no flags): render all.
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
using SHA
using JSON3

import Tachikoma: set_char!, Style, Buffer, Rect, Frame, Model,
    render, StatusBar, Span, tstyle, theme, to_rgb, dim_color,
    color_lerp, brighten, bottom, right, in_bounds, set_string!,
    Block, Layout, Vertical, Horizontal, Fixed, Fill, Percent, Min, Max,
    split_layout, ColorRGB, KeyEvent, TestBackend, Cell,
    record_widget, record_app, write_tach, load_tach,
    enable_gif, export_gif_from_snapshots, discover_mono_fonts,
    should_quit, handle_key!, text, set_text!, set_value!,
    TabBar, BarChart, BarEntry, Gauge, Canvas, Calendar,
    Table, DataTable, DataColumn, Scrollbar, Sparkline, GraphicsRegion, PixelSnapshot,
    set_theme!, Paragraph, Separator, BigText,
    Checkbox, RadioGroup, DropDown, Form, FormField, TextInput, TextArea,
    CodeEditor,
    TreeView, TreeNode, SelectableList, ListItem, Modal,
    ProgressList, ProgressItem, task_done, task_running, task_pending,
    Container, FocusRing, Button, ScrollPane, BlockCanvas,
    col_left, col_right, col_center, sort_desc,
    tween, advance!, value, done, reset!, Spring, retarget!, settled,
    sequence, stagger, parallel, Animator, animate!, tick!, val,
    pulse, breathe, shimmer, noise, fbm,
    fill_gradient!, fill_noise!, border_shimmer!,
    BOX_ROUNDED, BOX_HEAVY, BOX_DOUBLE, BOX_PLAIN,
    DotWaveBackground, PhyloTreeBackground, CladogramBackground,
    render_background!, bg_config,
    SPINNER_BRAILLE, DOT, SCANLINE, MARKER,
    word_wrap, no_wrap, align_center, align_left,
    chart_line, DataSeries,
    LayoutAlign, layout_start, layout_center, layout_end,
    layout_space_between, layout_space_around, layout_space_evenly,
    Constraint, center, intrinsic_size,
    MarkdownPane, set_markdown!,
    TaskQueue, TaskEvent, spawn_task!, drain_tasks!

set_theme!(:kokaku)
enable_markdown()   # load CommonMark extension for MarkdownPane renders

const ASSETS_DIR = joinpath(@__DIR__, "src", "assets")
const EXAMPLES_DIR = joinpath(ASSETS_DIR, "examples")
const CACHE_FILE = joinpath(@__DIR__, ".render_cache.json")

# ═══════════════════════════════════════════════════════════════════════
# Render cache: skip unchanged renders
# ═══════════════════════════════════════════════════════════════════════

function load_cache()::Dict{String,String}
    isfile(CACHE_FILE) || return Dict{String,String}()
    try
        JSON3.read(read(CACHE_FILE, String), Dict{String,String})
    catch
        Dict{String,String}()
    end
end

function save_cache!(cache::Dict{String,String})
    open(CACHE_FILE, "w") do io
        JSON3.pretty(io, cache)
    end
end

function file_sha256(path::String)::String
    isfile(path) || return ""
    bytes2hex(sha256(read(path)))
end

function should_render(cache::Dict{String,String}, key::String,
                       source_hash::String, tach_path::String)
    cached = get(cache, key, nothing)
    cached === nothing && return true
    parts = split(cached, ':')
    length(parts) != 2 && return true
    cached_src, cached_tach = parts
    cached_src != source_hash && return true
    file_sha256(tach_path) != cached_tach && return true
    false
end

function update_cache!(cache::Dict{String,String}, key::String,
                       source_hash::String, tach_path::String)
    tach_hash = file_sha256(tach_path)
    cache[key] = "$(source_hash):$(tach_hash)"
end

# ═══════════════════════════════════════════════════════════════════════
# Font discovery
# ═══════════════════════════════════════════════════════════════════════

function _find_font()
    fonts = discover_mono_fonts()
    # Normalize by stripping spaces — _name_from_filename splits CamelCase
    # (e.g. "JetBrainsMono" → "Jet Brains Mono") so direct substring match fails.
    for name in ["MesloLGL Nerd Font Mono", "JetBrains Mono", "MesloLGS NF", "MesloLGM NF",
                  "Menlo", "DejaVu Sans Mono", "Liberation Mono"]
        norm = lowercase(replace(name, " " => ""))
        idx = findfirst(f -> occursin(norm, lowercase(replace(f.name, " " => ""))), fonts)
        idx !== nothing && return fonts[idx].path
    end
    # Skip the "(none)" sentinel at index 1
    idx = findfirst(f -> !isempty(f.path), fonts)
    idx !== nothing ? fonts[idx].path : ""
end

# ═══════════════════════════════════════════════════════════════════════
# Export: .tach → .gif
# ═══════════════════════════════════════════════════════════════════════

function export_formats(tach_file::String; gif::Bool=true)
    w, h, cells, timestamps, sixels = load_tach(tach_file)
    base = replace(tach_file, r"\.tach$" => "")
    font_path = _find_font()

    if gif
        try
            enable_gif()
            gif_file = base * ".gif"
            # 2x cell size for retina displays (default is cell_w=10, cell_h=20, font_size=16)
            Base.invokelatest(export_gif_from_snapshots, gif_file, w, h, cells, timestamps;
                              pixel_snapshots=sixels, font_path=font_path,
                              cell_w=20, cell_h=40, font_size=32)
            println("    → $(basename(gif_file))")
        catch e
            @warn "GIF export skipped" exception=(e, catch_backtrace())
        end
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Hero assets (logo + sysmon demo)
# ═══════════════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "hero_assets.jl"))

# ═══════════════════════════════════════════════════════════════════════
# App demos
# ═══════════════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "example_apps.jl"))

# Hash of example_apps.jl — folded into all app source hashes so that
# changing APP_REGISTRY entries or APP_EVENTS scripts invalidates their caches.
const _EXAMPLE_APPS_HASH = bytes2hex(sha256(read(joinpath(@__DIR__, "example_apps.jl"))))

# ═══════════════════════════════════════════════════════════════════════
# Markdown scanner: parse tachi:widget / tachi:app annotations
# ═══════════════════════════════════════════════════════════════════════

struct TachiAnnotation
    kind::Symbol          # :widget or :app
    id::String            # unique identifier
    params::Dict{String,String}
    code::String          # extracted code block (widget only)
    source_hash::String   # SHA256 of annotation + code
end

"""
    parse_annotation_params(param_str) → Dict{String,String}

Parse "w=60 h=5 frames=1 fps=10 chrome" into a Dict.
Bare flags (no =) get value "true".
"""
function parse_annotation_params(s::AbstractString)
    params = Dict{String,String}()
    for tok in split(strip(s))
        if contains(tok, '=')
            k, v = split(tok, '='; limit=2)
            params[k] = v
        else
            params[tok] = "true"
        end
    end
    params
end

"""
    _accumulate_fences(text) → String

Walk a markdown text region, extract all non-noeval Julia code fences,
and return their concatenated content. Used by mechanism B (multi-section
accumulation) to gather code between `tachi:begin` and `tachi:app` markers.
"""
function _accumulate_fences(text::String)
    lines = split(text, '\n')
    fences = String[]
    last_noeval_line = 0
    i = 1

    while i <= length(lines)
        line = lines[i]
        stripped = strip(line)

        # Track noeval markers
        if match(r"<!--\s*tachi:noeval\s*-->", stripped) !== nothing
            last_noeval_line = i
        end

        # Find ```julia fences
        if startswith(stripped, "```julia")
            fence_start = i
            noeval = last_noeval_line > 0 && (fence_start - last_noeval_line) <= 5
            i += 1
            fence_lines = String[]
            while i <= length(lines) && !startswith(strip(lines[i]), "```")
                push!(fence_lines, lines[i])
                i += 1
            end
            if !noeval
                push!(fences, join(fence_lines, "\n"))
            end
        end

        i += 1
    end

    join(fences, "\n")
end

"""
    scan_markdown(filepath) → Vector{TachiAnnotation}

Scan a markdown file for tachi annotations. Supports three extraction mechanisms:

**A. Single-fence** — extract code from the next Julia code fence after the annotation.

**B. Multi-section accumulation** — `<!-- tachi:begin id -->` marker before the first
code fence. All non-noeval Julia fences between `begin` and `tachi:app` are concatenated,
plus the fence after the app annotation.

**C. Inline scaffold with `__FENCE__`** — multi-line annotation body contains scaffold
code with `__FENCE__` placeholder, replaced by the content of the next code fence.

Also supports multi-line annotations with embedded render code (for widgets).
"""
function scan_markdown(filepath::String)
    content = read(filepath, String)
    annotations = TachiAnnotation[]

    # Step 1: Find all tachi:begin markers → id => character offset
    begin_markers = Dict{String,Int}()
    for bm in eachmatch(r"<!--\s*tachi:begin\s+(\S+)\s*-->", content)
        begin_markers[bm.captures[1]] = bm.offset
    end

    # Step 2: Process annotations
    for m in eachmatch(r"<!--\s*tachi:(widget|app)\s+(\S+)([\s\S]*?)-->"m, content)
        kind = Symbol(m.captures[1])
        id = m.captures[2]
        body = something(m.captures[3], "")

        # Check if body contains newlines → embedded render code
        if contains(body, '\n')
            first_line, rest = split(body, '\n'; limit=2)
            params = parse_annotation_params(strip(first_line))
            code = strip(rest)
            # Unescape \$ → $ (escaped in markdown to prevent DocumenterVitepress
            # from interpreting $ as Julia interpolation in HTML comments)
            code = replace(code, "\\\$" => "\$")
        else
            params = parse_annotation_params(strip(body))
            code = ""
        end

        ann_end_pos = m.offset + length(m.match)

        # Mechanism C: __FENCE__ replacement
        if !isempty(code) && contains(code, "__FENCE__")
            fence_match = match(r"```julia\s*\n(.*?)```"s, content[ann_end_pos:end])
            if fence_match !== nothing
                fence_content = strip(fence_match.captures[1])
                code = replace(code, "__FENCE__" => fence_content)
            end
        end

        # Mechanism B: tachi:begin accumulation
        if isempty(code) && haskey(begin_markers, id)
            begin_pos = begin_markers[id]
            region = content[begin_pos:m.offset-1]
            accumulated = _accumulate_fences(region)
            # Also get the fence after the app annotation
            fence_match = match(r"```julia\s*\n(.*?)```"s, content[ann_end_pos:end])
            if fence_match !== nothing
                accumulated *= "\n" * fence_match.captures[1]
            end
            code = accumulated
        end

        # Mechanism A: Single fence extraction (for both widget and app)
        # Bounded to the current section: stops at the next heading or tachi annotation
        # so that later code blocks in the document are not mistakenly extracted.
        if isempty(code)
            pos = ann_end_pos
            remaining = content[pos:end]
            stop_match = match(r"(?:^#{1,6}\s|<!--\s*tachi:)"m, remaining)
            search_end = stop_match !== nothing ? stop_match.offset - 1 : length(remaining)
            fence_match = match(r"```julia\s*\n(.*?)```"s, remaining[1:search_end])
            if fence_match !== nothing
                code = fence_match.captures[1]
            end
        end

        # Strip `using Tachikoma` lines
        code = replace(code, r"^using Tachikoma\s*\n?"m => "")

        source = "$(m.match)\n$(code)"
        src_hash = bytes2hex(sha256(source))

        push!(annotations, TachiAnnotation(kind, id, params, code, src_hash))
    end
    annotations
end

"""
    scan_all_markdown() → Vector{TachiAnnotation}

Scan all markdown files under docs/src/ for tachi annotations.
"""
function scan_all_markdown()
    docs_src = joinpath(@__DIR__, "src")
    annotations = TachiAnnotation[]
    for (root, dirs, files) in walkdir(docs_src)
        for f in files
            endswith(f, ".md") || continue
            filepath = joinpath(root, f)
            append!(annotations, scan_markdown(filepath))
        end
    end
    annotations
end

# ═══════════════════════════════════════════════════════════════════════
# Widget example rendering
# ═══════════════════════════════════════════════════════════════════════

"""
    render_widget_example(ann, cache; force) → nothing

Render a tachi:widget annotation by wrapping its code in a record_widget block.
"""
function render_widget_example(ann::TachiAnnotation, cache::Dict{String,String};
                                force::Bool=false)
    w = parse(Int, get(ann.params, "w", "60"))
    h = parse(Int, get(ann.params, "h", "5"))
    frames = parse(Int, get(ann.params, "frames", "1"))
    fps = parse(Int, get(ann.params, "fps", "10"))

    tach_file = joinpath(EXAMPLES_DIR, "$(ann.id).tach")

    if !force && !should_render(cache, ann.id, ann.source_hash, tach_file)
        println("  $(ann.id): up to date (skipped)")
        return
    end

    println("  $(ann.id): rendering $(frames) frame$(frames > 1 ? "s" : "") $(w)×$(h)...")

    # Build the render function from extracted code
    # Variables available: buf, area, frame_idx, tick, f (Frame)
    render_code = """
    function _render_example_$(ann.id)(buf::Buffer, area::Rect, frame_idx::Int)
        tick = frame_idx
        f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
        $(ann.code)
    end
    """

    try
        eval(Meta.parse(render_code))

        render_fn = eval(Symbol("_render_example_$(ann.id)"))

        record_widget(tach_file, w, h, frames; fps=fps) do buf, area, frame_idx
            Base.invokelatest(render_fn, buf, area, frame_idx)
        end

        println("    → $(basename(tach_file))")
        export_formats(tach_file)
        update_cache!(cache, ann.id, ann.source_hash, tach_file)
    catch e
        @error "Failed to render $(ann.id)" exception=(e, catch_backtrace())
    end
end

# ═══════════════════════════════════════════════════════════════════════
# App demo rendering
# ═══════════════════════════════════════════════════════════════════════

"""
    _is_app_call(ex) → Bool

Check if an expression is a call to `app(...)`.
"""
function _is_app_call(ex)
    ex isa Expr || return false
    if ex.head == :call && length(ex.args) >= 1
        fn = ex.args[1]
        return fn == :app || (fn isa Expr && fn.head == :. &&
                              length(fn.args) >= 2 && fn.args[end] == QuoteNode(:app))
    end
    false
end

"""
    _app_constructor_arg(ex) → Expr or nothing

Extract the model constructor argument from an `app(Model(...))` call.
"""
function _app_constructor_arg(ex)
    for (i, arg) in enumerate(ex.args)
        i == 1 && continue  # skip function name
        arg isa Expr && arg.head == :parameters && continue  # skip kwargs
        return arg
    end
    nothing
end

"""
    render_app_from_markdown(ann, tach_file, w, h, frames, fps) → nothing

Render an app whose complete source code was extracted from markdown.
Creates an isolated module, evaluates the code, intercepts the `app()` call
to capture the model constructor, then records with `record_app`.
"""
function render_app_from_markdown(ann::TachiAnnotation, tach_file::String,
                                   w::Int, h::Int, frames::Int, fps::Int)
    # Create isolated module
    mod = Module(Symbol("_app_$(ann.id)"))

    # Setup: using Tachikoma + key imports
    Core.eval(mod, :(using Tachikoma))
    Core.eval(mod, :(import Tachikoma: update!, view, should_quit, init!, task_queue, cleanup!))
    Core.eval(mod, :(using Random))
    Core.eval(mod, :(Random.seed!(42)))

    # Also import Match if available (some apps use @match)
    try
        Core.eval(mod, :(using Match))
    catch; end

    # Parse code as AST block
    code = ann.code
    block_expr = Meta.parse("begin\n$(code)\nend")

    if block_expr isa Expr && block_expr.head == :incomplete
        error("Incomplete code for $(ann.id): $(block_expr.args[1])")
    end

    # Walk top-level expressions: eval everything except app() call
    model_constructor = nothing
    for expr in block_expr.args
        expr isa LineNumberNode && continue
        if _is_app_call(expr)
            model_constructor = _app_constructor_arg(expr)
        else
            Base.invokelatest(Core.eval, mod, expr)
        end
    end

    if model_constructor === nothing
        error("No app() call found in code for $(ann.id)")
    end

    # Create model from captured constructor
    model = Base.invokelatest(Core.eval, mod, model_constructor)

    # Call init! if defined for this model type
    try
        Base.invokelatest(Core.eval(mod, :init!), model, nothing)
    catch e
        e isa MethodError || rethrow(e)
    end

    # Get events from APP_EVENTS if registered
    events = if haskey(APP_EVENTS, ann.id)
        Base.invokelatest(APP_EVENTS[ann.id], fps)
    else
        Tuple{Int,Event}[]
    end

    # Check params
    realtime = haskey(ann.params, "realtime")
    warmup = parse(Int, get(ann.params, "warmup", "0"))

    # Record
    Base.invokelatest(record_app, model, tach_file;
        width=w, height=h, frames=frames, fps=fps,
        events=events, realtime=realtime, warmup=warmup)

    # Call cleanup! if defined (e.g. theme restore)
    try
        Base.invokelatest(Core.eval(mod, :cleanup!), model)
    catch e
        e isa MethodError || rethrow(e)
    end
end

"""
    render_app_example(ann, cache; force) → nothing

Render a tachi:app annotation. If the annotation has extracted code from markdown,
uses `render_app_from_markdown`. Otherwise falls back to `APP_REGISTRY` lookup.
"""
function render_app_example(ann::TachiAnnotation, cache::Dict{String,String};
                             force::Bool=false)
    w = parse(Int, get(ann.params, "w", "80"))
    h = parse(Int, get(ann.params, "h", "24"))
    frames = parse(Int, get(ann.params, "frames", "120"))
    fps = parse(Int, get(ann.params, "fps", "15"))

    tach_file = joinpath(EXAMPLES_DIR, "$(ann.id).tach")

    # Augment source hash with example_apps.jl — covers APP_REGISTRY code and
    # APP_EVENTS scripts which aren't captured in ann.source_hash.
    app_hash = bytes2hex(sha256(ann.source_hash * _EXAMPLE_APPS_HASH))

    if !force && !should_render(cache, ann.id, app_hash, tach_file)
        println("  $(ann.id): up to date (skipped)")
        return
    end

    println("  $(ann.id): rendering $(frames) frames $(w)×$(h)...")

    try
        if !isempty(ann.code)
            render_app_from_markdown(ann, tach_file, w, h, frames, fps)
        else
            render_fn = get(APP_REGISTRY, ann.id, nothing)
            if render_fn === nothing
                @warn "No app registered for id=$(ann.id), skipping"
                return
            end
            realtime = haskey(ann.params, "realtime")
            warmup = parse(Int, get(ann.params, "warmup", "0"))
            Base.invokelatest(render_fn, tach_file, w, h, frames, fps, realtime, warmup)
        end
        println("    → $(basename(tach_file))")
        export_formats(tach_file)
        update_cache!(cache, ann.id, app_hash, tach_file)
    catch e
        @error "Failed to render app $(ann.id)" exception=(e, catch_backtrace())
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Code snippet validation: ensure all Julia code fences parse and run
# ═══════════════════════════════════════════════════════════════════════

struct CodeFence
    file::String
    line::Int
    code::String
    annotated::Bool   # preceded by a tachi annotation (already tested via render)
    noeval::Bool      # preceded by <!-- tachi:noeval --> (skip validation)
end

"""
    extract_code_fences(filepath) → Vector{CodeFence}

Extract all ```julia code fences from a markdown file.
Marks fences that follow a tachi annotation within 5 lines as "annotated".
"""
function extract_code_fences(filepath::String)
    lines = readlines(filepath)
    fences = CodeFence[]
    i = 1
    last_ann_line = 0
    last_noeval_line = 0

    while i <= length(lines)
        line = lines[i]

        # Track tachi annotations (single-line or multi-line start)
        if match(r"<!--\s*tachi:(widget|app)", line) !== nothing
            last_ann_line = i
        end

        # Track noeval annotations
        if match(r"<!--\s*tachi:noeval\s*-->", line) !== nothing
            last_noeval_line = i
        end

        # Find ```julia fences
        if startswith(strip(line), "```julia")
            fence_line = i
            i += 1
            code_lines = String[]
            while i <= length(lines) && !startswith(strip(lines[i]), "```")
                push!(code_lines, lines[i])
                i += 1
            end
            code = join(code_lines, "\n")
            annotated = last_ann_line > 0 && (fence_line - last_ann_line) <= 5
            noeval = last_noeval_line > 0 && (fence_line - last_noeval_line) <= 5
            push!(fences, CodeFence(filepath, fence_line, code, annotated, noeval))
        end

        i += 1
    end
    fences
end

"""
    validate_snippets() → Int

Extract and validate all Julia code fences from docs/src/ markdown files.
For each file, fences are evaluated sequentially in a shared module so that
variables from earlier blocks are available to later ones.

Returns the number of errors found.
"""
function validate_snippets()
    docs_src = joinpath(@__DIR__, "src")
    file_fences = Dict{String,Vector{CodeFence}}()

    for (root, _, files) in walkdir(docs_src)
        for f in files
            endswith(f, ".md") || continue
            filepath = joinpath(root, f)
            fences = extract_code_fences(filepath)
            isempty(fences) || (file_fences[filepath] = fences)
        end
    end

    total = sum(length(v) for v in values(file_fences); init=0)
    tested = 0
    skipped = 0
    errors = Tuple{String,Int,String,String}[]

    for (filepath, fences) in sort(collect(file_fences); by=first)
        relfile = relpath(filepath, docs_src)

        # Fresh module per file — blocks share state within a file
        mod = Module(gensym(replace(relfile, r"[/\\.]" => "_")))

        # Use Meta.parse for all evals to avoid quote-block scope issues
        try
            Base.eval(mod, Meta.parse("using Tachikoma"))
            Base.eval(mod, Meta.parse("using Test"))
            Base.eval(mod, Meta.parse("using Match"))
            Base.eval(mod, Meta.parse("""
                import Tachikoma: set_char!, Style, Buffer, Rect, Frame, Model,
                    render, StatusBar, Span, tstyle, theme, to_rgb, dim_color,
                    color_lerp, brighten, bottom, right, in_bounds, set_string!,
                    Block, Layout, Vertical, Horizontal, Fixed, Fill, Percent, Min, Max,
                    split_layout, ColorRGB, KeyEvent, MouseEvent, TestBackend, Cell,
                    record_widget, record_app, write_tach, load_tach,
                    should_quit, handle_key!, text, set_text!, set_value!,
                    TabBar, BarChart, BarEntry, Gauge, Canvas, Calendar,
                    Table, DataTable, DataColumn, Scrollbar, Sparkline, GraphicsRegion, PixelSnapshot,
                    set_theme!, Paragraph, Separator, BigText,
                    Checkbox, RadioGroup, DropDown, Form, FormField, TextInput, TextArea,
                    CodeEditor,
                    TreeView, TreeNode, SelectableList, ListItem, Modal,
                    ProgressList, ProgressItem, task_done, task_running, task_pending,
                    Container, FocusRing, Button, ScrollPane, BlockCanvas,
                    intrinsic_size,
                    col_left, col_right, col_center, sort_desc,
                    tween, advance!, value, done, reset!, Spring, retarget!, settled,
                    sequence, stagger, parallel, Animator, animate!, tick!, val,
                    pulse, breathe, shimmer, noise, fbm,
                    fill_gradient!, fill_noise!, border_shimmer!,
                    BOX_ROUNDED, BOX_HEAVY, BOX_DOUBLE, BOX_PLAIN,
                    DotWaveBackground, PhyloTreeBackground, CladogramBackground,
                    render_background!, bg_config,
                    SPINNER_BRAILLE, DOT, SCANLINE, MARKER,
                    word_wrap, no_wrap, align_center, align_left,
                    chart_line, DataSeries,
                    NoColor, Color256, ResizableLayout, handle_resize!, render_resize_handles!,
                    reset_layout!, Constraint, Event,
                    mouse_left, mouse_right, mouse_press, mouse_release,
                    mouse_scroll_up, mouse_scroll_down, mouse_drag, mouse_move,
                    mouse_none, mouse_middle,
                    TaskQueue, TaskEvent, spawn_task!, drain_tasks!, task_queue,
                    spawn_timer!, cancel!, is_cancelled, CancelToken,
                    PixelImage, PixelCanvas, set_pixel!, fill_rect!, load_pixels!,
                    pixel_line!, fill_pixel_rect!,
                    set_point!, unset_point!, line!, rect!, circle!, arc!,
                    set_render_backend!, braille_backend, block_backend, sixel_backend,
                    cycle_render_backend!, render_backend, create_canvas,
                    decay_params, DecayParams,
                    animations_enabled, toggle_animations!,
                    MarkdownPane, set_markdown!,
                    LayoutAlign, layout_start, layout_center, layout_end,
                    layout_space_between, layout_space_around, layout_space_evenly,
                    gif_extension_loaded, discover_mono_fonts,
                    paragraph_line_count,
                    list_hit, list_scroll,
                    clipboard_copy!, buffer_to_text
            """))
            Base.eval(mod, Meta.parse("const T = Tachikoma"))

            # Common stubs — variables referenced in API-only code blocks
            stubs = """
            begin
                evt = KeyEvent(:enter)
                area = Rect(1, 1, 80, 24)
                buf = Buffer(area)
                f = Frame(buf, area, GraphicsRegion[], PixelSnapshot[])
                tick = 1
                frame_idx = 1
                x = 10
                y = 5
                width = 80
                rect = Rect(1, 1, 80, 24)
                widget1 = Block()
                widget2 = Block()
                widget3 = Block()
                child_widget = Block()
            end
            """
            Base.eval(mod, Meta.parse(stubs))
        catch e
            @warn "Failed to init snippet module for $(relfile)" exception=e
            continue
        end

        for fence in fences
            code = fence.code
            stripped = strip(code)

            # Skip empty, pkg commands, pure using blocks
            if isempty(stripped) ||
               startswith(stripped, "Pkg.") ||
               startswith(stripped, "pkg>") ||
               startswith(stripped, "using Pkg")
                skipped += 1
                continue
            end

            # Skip blocks marked with <!-- tachi:noeval -->
            if fence.noeval
                skipped += 1
                continue
            end

            # Strip lines we handle ourselves
            code = replace(code, r"^using Tachikoma\s*\n?"m => "")
            # Skip blocks that require unloaded extensions or unavailable packages
            if contains(code, "using Tables") || contains(code, "using CommonMark") ||
               contains(code, "using Supposition") || contains(code, "@check ")
                skipped += 1
                continue
            end
            # Skip blocks that launch interactive apps or recordings
            if contains(code, "app(") || contains(code, "record_app(") ||
               contains(code, "record_widget(") || contains(code, "enable_gif(") ||
               contains(code, "enable_tables(") || contains(code, "enable_markdown(")
                skipped += 1
                continue
            end
            # Strip other using lines (already loaded or not needed for validation)
            code = replace(code, r"^using \w+\s*\n?"m => "")
            code = strip(code)
            isempty(code) && (skipped += 1; continue)

            tested += 1

            try
                expr = Meta.parse("let\n$(code)\nend")
                if expr isa Expr && expr.head == :incomplete
                    push!(errors, (relfile, fence.line, first(split(code, '\n')),
                                   string(expr.args[1])))
                    continue
                end
                Base.invokelatest(Base.eval, mod, expr)
            catch e
                preview = first(split(code, '\n'))
                length(preview) > 70 && (preview = preview[1:67] * "...")
                msg = sprint(showerror, e; context=:compact=>true)
                # Truncate long error messages
                length(msg) > 120 && (msg = msg[1:117] * "...")
                push!(errors, (relfile, fence.line, preview, msg))
            end
        end
    end

    # Report
    println()
    if isempty(errors)
        println("  ✓ All $(tested) snippets passed ($(skipped) skipped)")
    else
        println("  $(tested - length(errors))/$(tested) snippets passed, " *
                "$(length(errors)) FAILED ($(skipped) skipped)")
        for (file, line, preview, msg) in errors
            println("    ✗ $(file):$(line)")
            println("      $(preview)")
            println("      → $(msg)")
        end
    end

    length(errors)
end

# ═══════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════

function main()
    force = "--force" in ARGS
    do_hero = "--hero" in ARGS
    do_examples = "--examples" in ARGS
    do_apps = "--apps" in ARGS
    do_snippets = "--snippets" in ARGS
    do_all = !do_hero && !do_examples && !do_apps && !do_snippets

    mkpath(ASSETS_DIR)
    mkpath(EXAMPLES_DIR)
    cache = load_cache()

    println("=" ^ 60)
    println("Generating Tachikoma.jl doc assets")
    force && println("  (--force: regenerating all)")
    println("=" ^ 60)

    # ── Hero assets ──
    if do_all || do_hero
        println()
        println("── Hero Assets ──")
        generate_logo(cache; force)
        generate_demo(cache; force)
        generate_code_reveal(cache; force)
        # Quick Start app (rendered inline in index.md side-by-side, no tachi annotation)
        _generate_quickstart(cache; force)
    end

    # ── Scan markdown for annotations ──
    annotations = scan_all_markdown()

    widget_anns = filter(a -> a.kind == :widget, annotations)
    app_anns = filter(a -> a.kind == :app, annotations)

    # ── Widget examples ──
    if (do_all || do_examples) && !isempty(widget_anns)
        println()
        println("── Widget Examples ($(length(widget_anns)) annotations) ──")
        for ann in widget_anns
            render_widget_example(ann, cache; force)
        end
    end

    # ── App demos ──
    if (do_all || do_apps) && !isempty(app_anns)
        println()
        println("── App Demos ($(length(app_anns)) annotations) ──")
        for ann in app_anns
            render_app_example(ann, cache; force)
        end
    end

    save_cache!(cache)
    println()
    println("Cache saved to $(CACHE_FILE)")
    println("Assets in $(ASSETS_DIR)")
    n_total = (do_all || do_hero ? 4 : 0) + length(widget_anns) + length(app_anns)
    println("Total renderable items: $(n_total)")

    # ── Snippet validation ──
    if do_all || do_snippets
        println()
        println("── Code Snippet Validation ──")
        n_errors = validate_snippets()
        if n_errors > 0
            println()
            println("⚠  $(n_errors) snippet(s) failed — fix the code blocks above")
        end
    end

    println("=" ^ 60)
end

main()
