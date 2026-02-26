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
    description::String
    launch::Function
end

const DEMO_ENTRIES = DemoEntry[
    DemoEntry("Theme Gallery",
        "Color palettes, box styles, block characters, signal bars. Showcases the theme system.",
        () -> demo()),
    DemoEntry("Dashboard",
        "Simulated system monitor with CPU/memory gauges, network sparkline, process table, log list.",
        () -> dashboard()),
    DemoEntry("Matrix Rain",
        "Falling katakana and latin characters with brightness falloff. Pure character-buffer animation.",
        () -> rain()),
    DemoEntry("System Monitor",
        "3-tab monitor: overview with bar charts and calendar, process table with scrollbar, network canvas plots.",
        () -> sysmon()),
    DemoEntry("Clock",
        "Real-time BigText clock with blinking colon, date display, stopwatch, and calendar widget.",
        () -> clock()),
    DemoEntry("Snake",
        "Classic snake game. Arrow keys to steer, eat food to grow. Speed increases with score.",
        () -> snake()),
    DemoEntry("Waves",
        "Animated parametric curves on braille canvas. Lissajous, spirograph, sine, oscilloscope modes.",
        () -> waves()),
    DemoEntry("Game of Life",
        "Conway's cellular automaton on braille canvas. Interactive cursor, play/pause, step, randomize.",
        () -> life()),
    DemoEntry("Animation System",
        "Showcases Tween, Spring, Timeline, and easing functions. Four live panels: easing gallery, spring physics, staggered cascade, loop modes.",
        () -> anim_demo()),
    DemoEntry("Mouse Draw",
        "Interactive braille canvas. Left-click to draw, right-click to erase, scroll to resize brush. Showcases mouse event support.",
        () -> mouse_demo()),
    DemoEntry("Chaos",
        "Logistic map bifurcation diagram on braille canvas. Animated cursor scans r from 2.5 to 4.0.",
        () -> chaos()),
    DemoEntry("Dot Waves",
        "Halftone dot field modulated by layered sine waves and noise. Pulsing, organic wave patterns.",
        () -> dotwave()),
    DemoEntry("Showcase",
        "Visual feast: rainbow arc, terrain background, spring gauges, sparklines, particles. Exercises every animation subsystem at once.",
        () -> showcase()),
    DemoEntry("Backend Compare",
        "Split-screen: same animation in braille (left), block (center), and PixelImage (right).",
        () -> backend_demo()),
    DemoEntry("Resize Panes",
        "Drag pane borders to resize. Click list items to select. Demonstrates ResizableLayout and list mouse helpers.",
        () -> resize_demo()),
    DemoEntry("ScrollPane Log",
        "Live log viewer with auto-follow, reverse mode, styled spans, mouse wheel, and keyboard scrolling. Three panes showing different ScrollPane content modes.",
        () -> scrollpane_demo()),
    DemoEntry("Effects Gallery",
        "Showcase of fill_gradient!, fill_noise!, glow, flicker, drift, Gauge shimmer, TextInput breathing, and Modal pulse effects.",
        () -> effects_demo()),
    DemoEntry("Chart",
        "Interactive chart with animated data. Three modes: dual sine/cosine, scatter cloud, and live streaming sparkline. Press [m] to cycle.",
        () -> chart_demo()),
    DemoEntry("DataTable",
        "Sortable, scrollable data table with cyberpunk-themed roster. Arrow keys navigate, number keys [1-4] sort by column.",
        () -> datatable_demo()),
    DemoEntry("Form",
        "Form with TextInput, TextArea, Checkbox, RadioGroup, and DropDown. Live preview panel shows values and validation state.",
        () -> form_demo()),
    DemoEntry("Code Editor",
        "Code editor with line numbers, Julia syntax highlighting, auto-indentation, and Tab/Shift-Tab indent control.",
        () -> editor_demo()),
    DemoEntry("FPS Stress Test",
        "Interactive frame rate stress test and monitor. Crank up sparklines, particles, animation complexity, and tokenizer load while watching FPS respond in real time.",
        () -> fps_demo()),
    DemoEntry("Phylo Tree",
        "Radial phylogenetic tree background. Animated branches radiate from center with sway and rotation. Keys 1-4 switch presets.",
        () -> phylo_demo()),
    DemoEntry("Cladogram",
        "Fan-layout cladogram with right-angle polar routing and trait-based coloring. Inspired by Phylo.jl :fan layout. Keys 1-5 switch presets (5=Organic).",
        () -> clado_demo()),
    DemoEntry("PixelImage Demo",
        "PixelImage widget showcase: plasma, terrain heightmap, Mandelbrot fractal, interference rings. Renders via sixel on capable terminals, falls back to braille. Press Ctrl+S to adjust decay.",
        () -> sixel_demo()),
    DemoEntry("Sixel Gallery",
        "Performance monitor dashboard using PixelImage widgets: CPU heatmap, latency distribution, memory page map, flame graph. Demonstrates bounded sixel rendering alongside text widgets.",
        () -> sixel_gallery()),
    DemoEntry("Async Tasks",
        "Background task system demo. Spawn compute tasks, trigger failures, launch batches of 5, and toggle a repeating timer. Results arrive without blocking the UI.",
        () -> async_demo()),
    DemoEntry("Markdown Viewer",
        "Three-mode markdown demo: README viewer with rich formatting, live split-pane editor with real-time preview, and style preset picker. Uses the CommonMark.jl extension.",
        () -> markdown_demo()),
]

# ── Launcher model ───────────────────────────────────────────────────

@kwdef mutable struct LauncherModel <: Model
    quit::Bool = false
    selected::Int = 1
    launch_idx::Int = 0   # 0 = stay in menu, >0 = demo index to launch
    tick::Int = 0
end

should_quit(m::LauncherModel) = m.quit || m.launch_idx > 0

function update!(m::LauncherModel, evt::KeyEvent)
    n = length(DEMO_ENTRIES)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _)  => (m.quit = true)
        (:up, _) || (:char, 'k')      => (m.selected = m.selected > 1 ? m.selected - 1 : n)
        (:down, _) || (:char, 'j')    => (m.selected = m.selected < n ? m.selected + 1 : 1)
        (:enter, _)                    => (m.launch_idx = m.selected)
        _                              => nothing
    end
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
        sx = header_area.x + max(0, (header_area.width - length(subtitle)) ÷ 2)
        br = breathe(m.tick; period=120)
        sub_color = color_lerp(to_rgb(th.text_dim), to_rgb(th.accent), br * 0.5)
        set_string!(buf, sx, sub_y, subtitle, Style(fg=sub_color))
    end

    # ── Content: demo list | description ──
    cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), content_area)
    length(cols) < 2 && return
    list_area = cols[1]
    desc_area = cols[2]

    # Demo list via SelectableList (handles scrolling + highlight)
    demo_items = [ListItem(e.name) for e in DEMO_ENTRIES]
    demo_list = SelectableList(demo_items;
        selected=m.selected,
        block=Block(title="Demos",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        highlight_style=tstyle(:accent, bold=true),
        tick=m.tick,
    )
    render(demo_list, list_area, buf)

    # Description panel
    desc_block = Block(title="Description",
                       border_style=tstyle(:border),
                       title_style=tstyle(:title))
    desc_inner = render(desc_block, desc_area, buf)

    if 1 <= m.selected <= length(DEMO_ENTRIES)
        entry = DEMO_ENTRIES[m.selected]

        # Name
        set_string!(buf, desc_inner.x, desc_inner.y,
                    entry.name, tstyle(:primary, bold=true))

        # Description — word-wrap to panel width
        max_w = desc_inner.width
        words = Base.split(entry.description)
        line = ""
        dy = 2
        for word in words
            test = isempty(line) ? word : line * " " * word
            if length(test) > max_w && !isempty(line)
                set_string!(buf, desc_inner.x, desc_inner.y + dy,
                            line, tstyle(:text))
                dy += 1
                line = string(word)
            else
                line = test
            end
        end
        if !isempty(line)
            set_string!(buf, desc_inner.x, desc_inner.y + dy,
                        line, tstyle(:text))
            dy += 1
        end

        # Launch hint — gentle pulse
        dy += 1
        if desc_inner.y + dy <= bottom(desc_inner)
            hint_color = if animations_enabled()
                p = breathe(m.tick; period=100)
                color_lerp(th.text_dim, th.accent, 0.4 + p * 0.6)
            else
                th.accent
            end
            set_string!(buf, desc_inner.x, desc_inner.y + dy,
                        "Press Enter to launch", Style(fg=hint_color))
        end
    end

    # ── Footer ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, footer_area.x, footer_area.y,
              SPINNER_BRAILLE[si], tstyle(:accent))

    render(StatusBar(
        left=[Span("  [↑↓/jk]select [Enter]launch [Ctrl+\\]theme [Ctrl+?]help ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function launcher(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    while true
        model = LauncherModel()
        app(model; fps=30)
        model.launch_idx == 0 && break
        # Launch selected demo, return to menu on exit
        try
            DEMO_ENTRIES[model.launch_idx].launch()
        catch e
            e isa InterruptException && rethrow()
            @warn "Demo exited with error" exception=(e, catch_backtrace())
        end
    end
end
