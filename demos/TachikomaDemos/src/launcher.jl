# ═══════════════════════════════════════════════════════════════════════
# Launcher ── demo menu that can launch any Tachikoma demo
#
# Animated block-letter logo with morphing noise-textured coloring.
# ═══════════════════════════════════════════════════════════════════════

# ── Logo (block font, '#' = filled) ─────────────────────────────────
# Letters: T A C H I K O M A — each row is 74 chars wide.

const _LOGO_DATA = [
    "#######   #####    #####  ##   ##  ##  ##  ##   #####   ###   ###   ##### ",
    "  ##     ##   ##  ##      ##   ##  ##  ## ##   ##   ##  #### ####  ##   ##",
    "  ##     #######  ##      #######  ##  ####    ##   ##  ## ### ##  #######",
    "  ##     ##   ##  ##      ##   ##  ##  ## ##   ##   ##  ##  #  ##  ##   ##",
    "  ##     ##   ##   #####  ##   ##  ##  ##  ##   #####   ##     ##  ##   ##",
]
const _LOGO_H = length(_LOGO_DATA)
const _LOGO_W = maximum(length, _LOGO_DATA)

# Precompute edge mask: filled cells adjacent to an empty cell
const _LOGO_EDGE = let
    mask = falses(_LOGO_H, _LOGO_W)
    for r in 1:_LOGO_H
        row = _LOGO_DATA[r]
        for c in 1:length(row)
            row[c] == '#' || continue
            for (dr, dc) in ((0,-1),(0,1),(-1,0),(1,0))
                nr, nc = r + dr, c + dc
                if nr < 1 || nr > _LOGO_H || nc < 1 || nc > length(_LOGO_DATA[nr])
                    mask[r, c] = true; break
                elseif _LOGO_DATA[nr][nc] != '#'
                    mask[r, c] = true; break
                end
            end
        end
    end
    mask
end

function _render_logo!(buf::Buffer, rect::Rect, tick::Int)
    th = theme()
    c1 = to_rgb(th.primary)
    c2 = to_rgb(th.accent)
    shadow_rgb = dim_color(c1, 0.8)

    for (row_i, line) in enumerate(_LOGO_DATA)
        y = rect.y + row_i - 1
        y > bottom(rect) && break
        for col_i in 1:length(line)
            line[col_i] == '#' || continue
            x = rect.x + col_i - 1
            x > right(rect) && break
            in_bounds(buf, x, y) || continue

            # Shadow at (+1, +1)
            sx, sy = x + 1, y + 1
            if in_bounds(buf, sx, sy) && sy <= bottom(rect) && sx <= right(rect)
                set_char!(buf, sx, sy, '░', Style(fg=shadow_rgb))
            end

            # Noise-driven color gradient
            n = fbm(col_i * 0.07 + tick * 0.018, row_i * 0.5 + tick * 0.012)
            fg = color_lerp(c1, c2, n)
            fg = brighten(fg, 0.15)

            # Edge glow: blocks at letter boundaries get brighter
            is_edge = _LOGO_EDGE[row_i, col_i]
            if is_edge
                fg = brighten(fg, 0.35)
            end

            # Scanline shimmer
            scan_y = mod(Float64(tick) * 0.06, Float64(_LOGO_H + 4)) - 2.0
            scan_dist = abs(Float64(row_i) - scan_y)
            if scan_dist < 1.5
                boost = (1.5 - scan_dist) / 1.5 * 0.45
                fg = brighten(fg, boost)
            end

            set_char!(buf, x, y, '█', Style(fg=fg, bold=is_edge))
        end
    end
end

# ── Demo entries ─────────────────────────────────────────────────────

struct DemoEntry
    name::String
    category::Symbol   # :visual, :widget, :data, :input, :system, :test
    description::String
    launch::Function
end

const _CATEGORY_LABELS = Dict(
    :visual  => "Visual",
    :widget  => "Widgets",
    :data    => "Data",
    :input   => "Input",
    :system  => "System",
    :test    => "Test",
)

const DEMO_ENTRIES = DemoEntry[
    # ── Visual / Animation ──
    DemoEntry("Theme Gallery", :visual,
        "Color palettes, box styles, block characters, signal bars. Showcases the theme system.",
        () -> demo()),
    DemoEntry("Matrix Rain", :visual,
        "Falling katakana and latin characters with brightness falloff. Pure character-buffer animation.",
        () -> rain()),
    DemoEntry("Waves", :visual,
        "Animated parametric curves on braille canvas. Lissajous, spirograph, sine, oscilloscope modes.",
        () -> waves()),
    DemoEntry("Chaos", :visual,
        "Logistic map bifurcation diagram on braille canvas. Animated cursor scans r from 2.5 to 4.0.",
        () -> chaos()),
    DemoEntry("Dot Waves", :visual,
        "Halftone dot field modulated by layered sine waves and noise. Pulsing, organic wave patterns.",
        () -> dotwave()),
    DemoEntry("Showcase", :visual,
        "Visual feast: rainbow arc, terrain background, spring gauges, sparklines, particles. Exercises every animation subsystem at once.",
        () -> showcase()),
    DemoEntry("Animation System", :visual,
        "Showcases Tween, Spring, Timeline, and easing functions. Four live panels: easing gallery, spring physics, staggered cascade, loop modes.",
        () -> anim_demo()),
    DemoEntry("Effects Gallery", :visual,
        "Showcase of fill_gradient!, fill_noise!, glow, flicker, drift, Gauge shimmer, TextInput breathing, and Modal pulse effects.",
        () -> effects_demo()),
    DemoEntry("Phylo Tree", :visual,
        "Radial phylogenetic tree background. Animated branches radiate from center with sway and rotation. Keys 1-4 switch presets.",
        () -> phylo_demo()),
    DemoEntry("Cladogram", :visual,
        "Fan-layout cladogram with right-angle polar routing and trait-based coloring. Inspired by Phylo.jl :fan layout. Keys 1-5 switch presets (5=Organic).",
        () -> clado_demo()),

    # ── Widget Showcases ──
    DemoEntry("Dashboard", :widget,
        "Simulated system monitor with CPU/memory gauges, network sparkline, process table, log list.",
        () -> dashboard()),
    DemoEntry("System Monitor", :widget,
        "3-tab monitor: overview with bar charts and calendar, process table with scrollbar, network canvas plots.",
        () -> sysmon()),
    DemoEntry("Clock", :widget,
        "Real-time BigText clock with blinking colon, date display, stopwatch, and calendar widget.",
        () -> clock()),
    DemoEntry("Chart", :widget,
        "Interactive chart with animated data. Three modes: dual sine/cosine, scatter cloud, and live streaming sparkline. Press [m] to cycle.",
        () -> chart_demo()),
    DemoEntry("TabBar", :widget,
        "Stateful tab bar with handle_key! and value(). Three tabs: system overview with sparklines, live activity log, and settings with checkboxes.",
        () -> tabbar_demo()),
    DemoEntry("Widget Styles", :widget,
        "Compare BracketTabs, BoxTabs (plain and heavy), and PlainTabs side by side. Also shows BracketButton, BorderedButton, and PlainButton decorations.",
        () -> widget_styles_demo()),
    DemoEntry("ScrollPane Log", :widget,
        "Live log viewer with auto-follow, reverse mode, styled spans, mouse wheel, and keyboard scrolling. Three panes showing different ScrollPane content modes.",
        () -> scrollpane_demo()),
    DemoEntry("Backend Compare", :widget,
        "Split-screen: same animation in braille (left), block (center), and PixelImage (right).",
        () -> backend_demo()),
    DemoEntry("ANSI Text", :widget,
        "ANSI escape sequence showcase. Parsed ANSI with colors and styles (left) vs raw text (right). Demonstrates parse_ansi and auto-follow log.",
        () -> ansi_demo()),
    DemoEntry("Markdown Viewer", :widget,
        "Three-mode markdown demo: README viewer with rich formatting, live split-pane editor with real-time preview, and style preset picker.",
        () -> markdown_demo()),
    DemoEntry("Widget Scroll", :widget,
        "2D pannable viewport filled with widgets: sparklines, tables, bar charts, gauges, calendars. Click-drag to pan, scroll wheel, arrow keys, Home to reset.",
        () -> scroll_demo()),
    DemoEntry("Tree View", :widget,
        "Hierarchical TreeView with keyboard/mouse navigation. Live debug panel shows value(), selected_node(), and per-node user data via TreeNode.content.",
        () -> simple_tree_demo()),

    # ── Data ──
    DemoEntry("DataTable", :data,
        "Sortable, scrollable data table with cyberpunk-themed roster. Arrow keys navigate, number keys [1-4] sort by column.",
        () -> datatable_demo()),
    DemoEntry("Paged DataTable", :data,
        "Virtual data table with 1M rows generated on the fly — zero pre-allocation. Provider interface for out-of-memory data with sort, filter, search, and pagination.",
        () -> paged_datatable_demo()),

    # ── Input / Interaction ──
    DemoEntry("Snake", :input,
        "Classic snake game. Arrow keys to steer, eat food to grow. Speed increases with score.",
        () -> snake()),
    DemoEntry("Game of Life", :input,
        "Conway's cellular automaton on braille canvas. Interactive cursor, play/pause, step, randomize.",
        () -> life()),
    DemoEntry("Mouse Draw", :input,
        "Interactive braille canvas. Left-click to draw, right-click to erase, scroll to resize brush.",
        () -> mouse_demo()),
    DemoEntry("Resize Panes", :input,
        "Drag pane borders to resize. Click list items to select. Demonstrates ResizableLayout and list mouse helpers.",
        () -> resize_demo()),
    DemoEntry("Form", :input,
        "Form with TextInput, TextArea, Checkbox, RadioGroup, and DropDown. Live preview panel shows values and validation state.",
        () -> form_demo()),
    DemoEntry("Code Editor", :input,
        "Code editor with line numbers, Julia syntax highlighting, auto-indentation, and Tab/Shift-Tab indent control.",
        () -> editor_demo()),

    # ── System / Graphics ──
    DemoEntry("PixelImage Demo", :system,
        "PixelImage widget showcase: plasma, terrain heightmap, Mandelbrot fractal, interference rings. Renders via sixel on capable terminals, falls back to braille.",
        () -> sixel_demo()),
    DemoEntry("Sixel Gallery", :system,
        "Performance monitor dashboard using PixelImage widgets: CPU heatmap, latency distribution, memory page map, flame graph.",
        () -> sixel_gallery()),
    DemoEntry("Floating Windows", :widget,
        "Overlapping windows with z-order, semi-transparent blending, sparklines, forms, and DataTable inside windows. Title-bar dragging, corner resizing, focus cycling, animated tile and cascade layouts.",
        () -> windows_demo()),
    DemoEntry("Terminal Emulator", :system,
        "Shell terminals and Julia REPLs in floating windows. Ctrl+N spawns a terminal, Ctrl+E spawns a REPL, Ctrl+U goes recursive. Ctrl+T tiles them.",
        () -> terminal_demo()),
    DemoEntry("Julia REPL", :system,
        "Multiple in-process Julia REPLs in floating windows. Each REPL shares the host's modules and variables. Ctrl+N spawns new REPLs, Ctrl+T tiles them.",
        () -> repl_demo()),
    DemoEntry("Async Tasks", :system,
        "Background task system demo. Spawn compute tasks, trigger failures, launch batches of 5, and toggle a repeating timer. Results arrive without blocking the UI.",
        () -> async_demo()),
    DemoEntry("FPS Stress Test", :system,
        "Interactive frame rate stress test and monitor. Crank up sparklines, particles, animation complexity, and tokenizer load while watching FPS respond in real time.",
        () -> fps_demo()),

    # ── Test / Verification ──
    DemoEntry("Unicode & Graphemes", :test,
        "Zero-width combining marks, precomposed glyphs, CJK wide characters, and mixed-width text across Paragraph, Table, TabBar, and StatusBar.",
        () -> unicode_demo()),
    DemoEntry("ColorTypes Interop", :test,
        "Verify ColorTypes.jl extension: to_rgb, to_rgba, to_colortype conversions between Tachikoma and ColorTypes color types.",
        () -> colortypes_demo()),
]

# ── Build category tree from demo entries ────────────────────────────

# Ordered list of categories for display
const _CATEGORY_ORDER = [:visual, :widget, :data, :input, :system, :test]

function _build_demo_tree()
    # Group entries by category, preserving order
    groups = Dict{Symbol, Vector{Int}}()
    for (i, e) in enumerate(DEMO_ENTRIES)
        push!(get!(groups, e.category, Int[]), i)
    end

    cat_nodes = TreeNode[]
    for cat in _CATEGORY_ORDER
        haskey(groups, cat) || continue
        indices = groups[cat]
        children = [TreeNode(DEMO_ENTRIES[i].name; expanded=false)
                    for i in indices]
        label = get(_CATEGORY_LABELS, cat, string(cat))
        push!(cat_nodes, TreeNode(label, children; expanded=true))
    end

    TreeNode("Demos", cat_nodes; expanded=true)
end

# Map a flattened tree row (excluding root) to a DEMO_ENTRIES index.
# Returns 0 for category nodes, >0 for leaf demos.
function _flat_row_to_demo_idx(tree::TreeView)
    flat = Tachikoma._get_flat(tree)
    sel = tree.selected
    (sel < 1 || sel > length(flat)) && return 0
    row = flat[sel]
    row.has_children && return 0  # category node, not a demo

    # Walk DEMO_ENTRIES by category order to find the matching index
    demo_idx = 0
    for cat in _CATEGORY_ORDER
        for (i, e) in enumerate(DEMO_ENTRIES)
            e.category != cat && continue
            demo_idx += 1
            if row.label == e.name
                return i  # return real DEMO_ENTRIES index
            end
        end
    end
    return 0
end

# Get the DemoEntry for the currently selected tree row (or nothing)
function _selected_entry(tree::TreeView)
    idx = _flat_row_to_demo_idx(tree)
    idx > 0 ? DEMO_ENTRIES[idx] : nothing
end

# ── Launcher model ───────────────────────────────────────────────────

@kwdef mutable struct LauncherModel <: Model
    quit::Bool = false
    launch_idx::Int = 0   # 0 = stay in menu, >0 = demo index to launch
    tick::Int = 0
    tree::TreeView = TreeView(_build_demo_tree();
        selected=2, focused=true, show_root=false,
        block=Block(title="Demos ($(length(DEMO_ENTRIES)))",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        selected_style=tstyle(:accent, bold=true),
        connector_style=tstyle(:text_dim))
end

should_quit(m::LauncherModel) = m.quit || m.launch_idx > 0

function update!(m::LauncherModel, evt::KeyEvent)
    if evt.key == :char && evt.char == 'q' || evt.key == :escape
        m.quit = true
        return
    end
    if evt.key == :enter
        idx = _flat_row_to_demo_idx(m.tree)
        if idx > 0
            m.launch_idx = idx
            return
        end
    end
    handle_key!(m.tree, evt)
end

function update!(m::LauncherModel, evt::MouseEvent)
    if evt.action == mouse_press && evt.button == mouse_left
        # Double-click detection: if clicking the already-selected leaf, launch it
        old_sel = m.tree.selected
        old_entry = _selected_entry(m.tree)
        handled = handle_mouse!(m.tree, evt)
        if handled && old_sel == m.tree.selected && old_entry !== nothing
            # Clicked same leaf row again → launch
            idx = _flat_row_to_demo_idx(m.tree)
            if idx > 0
                m.launch_idx = idx
                return
            end
        end
        return
    end
    handle_mouse!(m.tree, evt)
end

function view(m::LauncherModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()

    # Layout: title area | content | footer
    header_h = _LOGO_H + 7  # edges(2) + padding(2) + logo(h) + shadow(1) + gap(1) + subtitle(1)
    rows = split_layout(Layout(Vertical, [Fixed(header_h), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    content_area = rows[2]
    footer_area = rows[3]

    # ── Header background: slow-drifting noise texture ──
    bg_dark = dim_color(to_rgb(th.primary), 0.82)
    bg_mid  = dim_color(to_rgb(th.accent), 0.72)
    for row in header_area.y:bottom(header_area)
        for col in header_area.x:right(header_area)
            in_bounds(buf, col, row) || continue
            t = fbm(col * 0.12 + m.tick * 0.006, row * 0.25 + m.tick * 0.004)
            c = color_lerp(bg_dark, bg_mid, t)
            set_char!(buf, col, row, ' ', Style(bg=c))
        end
    end

    # ── Decorative edges ──
    accent_rgb = to_rgb(th.accent)
    for col in header_area.x:right(header_area)
        t_top = fbm(col * 0.1 + m.tick * 0.02, 0.0)
        edge_color = color_lerp(dim_color(accent_rgb, 0.6),
                                brighten(accent_rgb, 0.1), t_top)
        set_char!(buf, col, header_area.y, '▁', Style(fg=edge_color))
        t_bot = fbm(col * 0.08 - m.tick * 0.015, 5.0)
        sep_color = color_lerp(dim_color(accent_rgb, 0.7), accent_rgb, t_bot)
        set_char!(buf, col, bottom(header_area), '▔', Style(fg=sep_color))
    end

    # ── Logo ──
    tx = header_area.x + max(0, (header_area.width - _LOGO_W - 1) ÷ 2)
    logo_rect = Rect(tx, header_area.y + 2, min(_LOGO_W + 1, header_area.width), _LOGO_H + 1)
    _render_logo!(buf, logo_rect, m.tick)

    # Subtitle with gentle breathe
    sub_y = header_area.y + 2 + _LOGO_H + 1
    if sub_y <= bottom(header_area) - 1
        subtitle = "── Terminal UI Framework ──"
        sx = header_area.x + max(0, (header_area.width - textwidth(subtitle)) ÷ 2)
        br = breathe(m.tick; period=120)
        sub_color = color_lerp(to_rgb(th.text_dim), to_rgb(th.accent), br * 0.5)
        set_string!(buf, sx, sub_y, subtitle, Style(fg=sub_color))
    end

    # ── Content: demo list | description ──
    cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), content_area)
    length(cols) < 2 && return
    list_area = cols[1]
    desc_area = cols[2]

    # Demo tree
    m.tree.tick = m.tick
    render(m.tree, list_area, buf)

    # Description panel
    desc_block = Block(title="Description",
                       border_style=tstyle(:border),
                       title_style=tstyle(:title))
    desc_inner = render(desc_block, desc_area, buf)

    entry = _selected_entry(m.tree)
    if entry !== nothing
        dy = 0

        # Name — bold primary
        set_string!(buf, desc_inner.x, desc_inner.y + dy,
                    entry.name, tstyle(:primary, bold=true))
        dy += 1

        # Category badge
        cat_label = get(_CATEGORY_LABELS, entry.category, "")
        set_string!(buf, desc_inner.x, desc_inner.y + dy,
                    cat_label, tstyle(:accent))
        dy += 2

        # Description — use Paragraph with word wrap
        desc_h = max(1, desc_inner.height - dy - 3)
        if desc_h > 0 && desc_inner.y + dy <= bottom(desc_inner)
            desc_rect = Rect(desc_inner.x, desc_inner.y + dy,
                             desc_inner.width, desc_h)
            p = Paragraph(entry.description; wrap=word_wrap)
            render(p, desc_rect, buf)
            dy += desc_h
        end

        # Launch hint — gentle pulse, pinned to bottom
        hint_y = bottom(desc_inner)
        if hint_y > desc_inner.y + 3
            hint_color = if animations_enabled()
                p = breathe(m.tick; period=100)
                color_lerp(th.text_dim, th.accent, 0.4 + p * 0.6)
            else
                th.accent
            end
            set_string!(buf, desc_inner.x, hint_y,
                        "▸ Press Enter to launch", Style(fg=hint_color, bold=true))
        end
    end

    # ── Footer ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, footer_area.x, footer_area.y,
              SPINNER_BRAILLE[si], tstyle(:accent))

    render(StatusBar(
        left=[Span("  ↑↓ ", tstyle(:accent)),
              Span("select  ", tstyle(:text_dim)),
              Span("Enter ", tstyle(:accent)),
              Span("launch  ", tstyle(:text_dim)),
              Span("Ctrl+\\ ", tstyle(:accent)),
              Span("theme  ", tstyle(:text_dim)),
              Span("Ctrl+? ", tstyle(:accent)),
              Span("help", tstyle(:text_dim))],
        right=[Span("$(m.tree.selected)/$(Tachikoma.tree_visible_count(m.tree))  ", tstyle(:text_dim)),
               Span("q ", tstyle(:accent)),
               Span("quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function launcher(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    model = LauncherModel()
    while true
        result = app(model; fps=30)
        result === :restart && continue
        model.launch_idx == 0 && break
        # Launch selected demo, return to menu on exit
        idx = model.launch_idx
        model.quit = false
        model.launch_idx = 0
        model.tick = 0
        try
            DEMO_ENTRIES[idx].launch()
        catch e
            e isa InterruptException && rethrow()
            @warn "Demo exited with error" exception=(e, catch_backtrace())
        end
    end
end
