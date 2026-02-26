# ═══════════════════════════════════════════════════════════════════════
# example_apps.jl ── Event scripts + non-migrated app demos for docs
#
# All app struct/view/update code now lives in the markdown docs themselves
# and is extracted by scan_markdown() during asset generation.
#
# This file provides:
# 1. APP_EVENTS — event scripts that drive the recorded demos
# 2. APP_REGISTRY — only for apps NOT rendered via tachi:app annotations
# ═══════════════════════════════════════════════════════════════════════

import Tachikoma: MouseEvent, mouse_left, mouse_press, mouse_drag, mouse_release

# ═══════════════════════════════════════════════════════════════════════
# APP_EVENTS — scripted input events for headless app recordings
#
# Each entry maps an app id to a function: fps → Vector{Tuple{Int,Event}}
# Events are injected at the given frame numbers during record_app.
# ═══════════════════════════════════════════════════════════════════════

const APP_EVENTS = Dict{String,Function}()

# ─── Pig Game (getting-started.md) ───────────────────────────────────
APP_EVENTS["pig_game"] = EventScript(
    (1.0, key('r')),
    rep(key('r'), 3),
    (1.0, key('b')),
    rep(key('r'), 4),
    (1.0, key('b')),
    rep(key('r'), 5),
)

# ─── Dashboard App (tutorials/dashboard.md) ──────────────────────────
APP_EVENTS["dashboard_app"] = EventScript(
    (2.0, key(:down)),
    seq(key(:down), key(:down), key(:up), key(:up), key(:down)),
)

# ─── Form App (tutorials/form-app.md) ────────────────────────────────
APP_EVENTS["form_app"] = function (fps)
    events = Tuple{Int,KeyEvent}[]
    for (i, c) in enumerate("Alice")
        push!(events, (fps * 1 + i * 3, KeyEvent(c)))
    end
    push!(events, (fps * 3, KeyEvent(:tab)))
    for (i, c) in enumerate("Julia Developer")
        push!(events, (fps * 3 + 10 + i * 3, KeyEvent(c)))
    end
    push!(events, (fps * 5, KeyEvent(:tab)))
    push!(events, (fps * 5 + 10, KeyEvent(' ')))
    push!(events, (fps * 6, KeyEvent(:tab)))
    push!(events, (fps * 6 + 10, KeyEvent(:down)))
    push!(events, (fps * 7, KeyEvent(:tab)))
    events
end

# ─── Animation Showcase (tutorials/animation-showcase.md) ─────────────
APP_EVENTS["anim_showcase_app"] = EventScript(
    (2.0, key(' ')),
    (2.0, key(' ')),
    (2.0, key(:up)),
    (1.0, key('r')),
)

# ─── Constraint Explorer (tutorials/constraint-explorer.md) ──────────
APP_EVENTS["constraint_explorer_app"] = fps -> Tuple{Int,KeyEvent}[
    (fps * 1, KeyEvent(:right)),
    (fps * 2, KeyEvent(:up)),
    (fps * 2 + 5, KeyEvent(:up)),
    (fps * 2 + 10, KeyEvent(:up)),
    (fps * 3, KeyEvent(:right)),
    (fps * 4, KeyEvent('1')),
    (fps * 5, KeyEvent('+')),
    (fps * 5 + 5, KeyEvent('+')),
    (fps * 5 + 10, KeyEvent('+')),
    (fps * 6, KeyEvent('a')),
    (fps * 6 + 5, KeyEvent('5')),
    (fps * 7, KeyEvent(:left)),
    (fps * 7 + 5, KeyEvent('4')),
]

# ─── Todo List App (tutorials/todo-list.md) ──────────────────────────
APP_EVENTS["todo_app"] = EventScript(
    seq(key(:down), key(:down), key(:enter), key(:down), key(:down), key(:enter), key(:up)),
)

# ─── GitHub PRs App (tutorials/github-prs.md) ────────────────────────
APP_EVENTS["github_prs_app"] = EventScript(
    (2.0, key(:down)),
    seq(key(:down), key(:down), key(:enter)),
    (2.0, key(:escape)),
)

# ─── Async Compute Demo (async.md) ───────────────────────────────────
APP_EVENTS["compute_demo"] = EventScript(rep(key('s'), 3))

# ─── FocusRing Demo (events.md) ──────────────────────────────────────
APP_EVENTS["focusring_demo"] = EventScript(
    rep(key(:tab), 3; gap=2.0),
    (1.0, key(:backtab)),
)

# ─── TextInput Demo (widgets.md) ─────────────────────────────────────
APP_EVENTS["textinput_demo"] = function (fps)
    events = Tuple{Int,KeyEvent}[]
    for i in 1:7
        push!(events, (fps * i ÷ 4, KeyEvent(:backspace)))
    end
    for (i, c) in enumerate("Al")
        push!(events, (fps * 1 + i * 4, KeyEvent(c)))
    end
    for (i, c) in enumerate("ice")
        push!(events, (fps * 2 + i * 4, KeyEvent(c)))
    end
    push!(events, (fps * 4, KeyEvent(:backspace)))
    push!(events, (fps * 4 + 8, KeyEvent(:backspace)))
    push!(events, (fps * 4 + 16, KeyEvent(:backspace)))
    for (i, c) in enumerate("lison")
        push!(events, (fps * 5 + i * 4, KeyEvent(c)))
    end
    events
end

# ─── TextArea Demo (widgets.md) ──────────────────────────────────────
APP_EVENTS["textarea_demo"] = function (fps)
    events = Tuple{Int,KeyEvent}[]
    push!(events, (fps * 1, KeyEvent(:down)))
    push!(events, (fps * 1 + 5, KeyEvent(:end_key)))
    push!(events, (fps * 2, KeyEvent(:enter)))
    for (i, c) in enumerate("with editing support")
        push!(events, (fps * 2 + 10 + (i - 1) * 3, KeyEvent(c)))
    end
    events
end

# ─── CodeEditor Demo (widgets.md) ────────────────────────────────────
APP_EVENTS["codeeditor_demo"] = function (fps)
    events = Tuple{Int,KeyEvent}[]
    push!(events, (fps * 1, KeyEvent(:up)))
    # push!(events, (fps * 1 + 8, KeyEvent(:up)))
    push!(events, (fps * 1, KeyEvent(:esc)))
    push!(events, (fps * 2, KeyEvent('o')))
    for (i, c) in enumerate("    return msg")
        push!(events, (fps * 3 + 10 + (i - 1) * 3, KeyEvent(c)))
    end
    events
end

# ─── Checkbox Demo (widgets.md) ──────────────────────────────────────
APP_EVENTS["checkbox_demo"] = EventScript(
    seq(key(' '), key(:down), key(' '), key(:down), key(' '), key(:up), key(' ')),
)

# ─── RadioGroup Demo (widgets.md) ────────────────────────────────────
APP_EVENTS["radiogroup_demo"] = EventScript(
    seq(key(:down), key(' '), key(:down), key(' '), key(:up), key(:up), key(' ')),
)

# ─── DropDown Demo (widgets.md) ──────────────────────────────────────
APP_EVENTS["dropdown_demo"] = fps -> Tuple{Int,KeyEvent}[
    (fps * 1, KeyEvent(:enter)),
    (fps * 2, KeyEvent(:down)),
    (fps * 3, KeyEvent(:down)),
    (fps * 4, KeyEvent(:enter)),
    (fps * 5 + 5, KeyEvent(:enter)),
    (fps * 6, KeyEvent(:down)),
    (fps * 6 + 5, KeyEvent(:down)),
    (fps * 7, KeyEvent(:enter)),
]

# ─── SelectableList Demo (widgets.md) ────────────────────────────────
APP_EVENTS["selectablelist_demo"] = EventScript(
    rep(key(:down), 3),
    rep(key(:up), 2),
    rep(key(:down), 3),
)

# ─── Mouse Draw Demo (events.md) ─────────────────────────────────────
APP_EVENTS["mouse_draw_demo"] = function (fps)
    events = Vector{Tuple{Int,Event}}()
    # Diagonal stroke
    push!(events, (fps * 1, MouseEvent(5, 3, mouse_left, mouse_press, false, false, false)))
    for i in 1:12
        push!(events, (fps * 1 + i * 2,
            MouseEvent(5 + i, 3 + (i ÷ 2), mouse_left, mouse_drag, false, false, false)))
    end
    push!(events, (fps * 2, MouseEvent(17, 9, mouse_left, mouse_release, false, false, false)))
    # Horizontal line
    push!(events, (fps * 3, MouseEvent(25, 5, mouse_left, mouse_press, false, false, false)))
    for i in 1:15
        push!(events, (fps * 3 + i * 2,
            MouseEvent(25 + i, 5, mouse_left, mouse_drag, false, false, false)))
    end
    push!(events, (fps * 4, MouseEvent(40, 5, mouse_left, mouse_release, false, false, false)))
    # Vertical line
    push!(events, (fps * 5, MouseEvent(30, 8, mouse_left, mouse_press, false, false, false)))
    for i in 1:6
        push!(events, (fps * 5 + i * 2,
            MouseEvent(30, 8 + i, mouse_left, mouse_drag, false, false, false)))
    end
    push!(events, (fps * 6, MouseEvent(30, 14, mouse_left, mouse_release, false, false, false)))
    events
end


# ═══════════════════════════════════════════════════════════════════════
# APP_REGISTRY — only for apps NOT rendered via tachi:app annotations
# ═══════════════════════════════════════════════════════════════════════

const APP_REGISTRY = Dict{String,Function}()

# ─── Quick Start Game of Life (index.md) ──────────────────────────
# Rendered by _generate_quickstart in hero_assets.jl, NOT via tachi:app.

@kwdef mutable struct DocLife <: Model
    quit::Bool = false
    grid::Matrix{Bool} = zeros(Bool, 1, 1)
    tick::Int = 0
    initialized::Bool = false
end

Tachikoma.should_quit(m::DocLife) = m.quit
function Tachikoma.update!(m::DocLife, e::KeyEvent)
    e.key == :escape && (m.quit = true)
end

function _life_seed(h, w)
    [noise(Float64(i) * 0.3 + Float64(j) * 0.3) > 0.2 for i in 1:h, j in 1:w]
end

function Tachikoma.view(m::DocLife, f::Frame)
    m.tick += 1
    if !m.initialized
        m.grid = _life_seed(f.area.height, f.area.width)
        m.initialized = true
    end
    h, w = size(m.grid)
    nc = [sum(m.grid[mod1(i + di, h), mod1(j + dj, w)]
              for di in -1:1, dj in -1:1) - m.grid[i, j]
          for i in 1:h, j in 1:w]
    m.grid .= (nc .== 3) .| (m.grid .& (nc .== 2))
    buf = f.buffer
    colors = [:primary, :accent, :success, :warning, :error]
    for i in 1:min(h, f.area.height), j in 1:min(w, f.area.width)
        m.grid[i, j] || continue
        set_char!(buf, f.area.x + j - 1, f.area.y + i - 1, '█',
            tstyle(colors[clamp(nc[i, j], 1, 5)]))
    end
end

function render_quickstart_hello(tach_file, w, h, frames, fps)
    record_app(DocLife(), tach_file; width=w, height=h, frames, fps)
end

APP_REGISTRY["quickstart_hello"] = render_quickstart_hello

# ─── Theme Demo (styling.md) ─────────────────────────────────────────────────
@kwdef mutable struct ThemeDemo <: Model
    quit::Bool = false
    tick::Int = 0
    theme_idx::Int = 1
    original_theme::Theme = theme()
end

Tachikoma.should_quit(m::ThemeDemo) = m.quit

function Tachikoma.view(m::ThemeDemo, f::Frame)
    m.tick += 1
    buf = f.buffer

    m.theme_idx = mod1(div(m.tick - 1, 20) + 1, length(ALL_THEMES))
    set_theme!(ALL_THEMES[m.theme_idx])

    t_name = theme().name

    outer = Block(title="Theme Preview", border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true))
    main = render(outer, f.area, buf)
    main.width < 10 || main.height < 6 && return

    rows = split_layout(Layout(Vertical,
            [Fixed(1), Fixed(1), Fixed(1), Fixed(1), Fixed(1), Fill()]), main)
    length(rows) < 5 && return

    cols1 = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[1])
    if length(cols1) >= 2
        set_string!(buf, cols1[1].x, cols1[1].y, " ■ primary", tstyle(:primary, bold=true))
        set_string!(buf, cols1[2].x, cols1[2].y, "■ accent", tstyle(:accent, bold=true))
    end

    cols2 = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[2])
    if length(cols2) >= 2
        set_string!(buf, cols2[1].x, cols2[1].y, " ■ secondary", tstyle(:secondary))
        set_string!(buf, cols2[2].x, cols2[2].y, "■ success", tstyle(:success))
    end

    progress = mod(m.tick, 40) / 40.0
    render(Gauge(progress; filled_style=tstyle(:primary),
            empty_style=tstyle(:text_dim, dim=true), tick=m.tick), rows[3], buf)

    render(Button("Action"; focused=true, tick=m.tick,
            style=tstyle(:text), focused_style=tstyle(:accent, bold=true)), rows[4], buf)

    label = "theme: $t_name"
    set_string!(buf, rows[5].x + 1, rows[5].y, label, tstyle(:text_dim))
end

APP_REGISTRY["theme_demo"] = function (tach_file, w, h, frames, fps, realtime=false, warmup=0)
    model = ThemeDemo()
    try
        record_app(model, tach_file; width=w, height=h, frames=frames, fps=fps,
            realtime=realtime, warmup=warmup)
    finally
        set_theme!(model.original_theme)
    end
end

# ─── Event Loop Viz (architecture.md) ───────────────────────────────────────
@kwdef mutable struct EventLoopViz <: Model
    quit::Bool = false
    tick::Int = 0
end

Tachikoma.should_quit(m::EventLoopViz) = m.quit

function Tachikoma.view(m::EventLoopViz, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    box_w = 18
    box_h = 5
    gap_x = 6
    gap_y = 2

    total_w = box_w * 2 + gap_x
    total_h = box_h * 2 + gap_y
    ox = area.x + max(0, (area.width - total_w) ÷ 2)
    oy = area.y + max(0, (area.height - total_h) ÷ 2)

    boxes = [
        (rect=Rect(ox, oy, box_w, box_h),
            title="Event", subtitle="key / mouse", color=:accent),
        (rect=Rect(ox + box_w + gap_x, oy, box_w, box_h),
            title="update!", subtitle="mutate model", color=:primary),
        (rect=Rect(ox + box_w + gap_x, oy + box_h + gap_y, box_w, box_h),
            title="view", subtitle="render → buf", color=:secondary),
        (rect=Rect(ox, oy + box_h + gap_y, box_w, box_h),
            title="Terminal", subtitle="draw diff", color=:success),
    ]

    cycle = 120
    t_cycle = mod(m.tick, cycle)
    segment = div(t_cycle, cycle ÷ 4)
    seg_t = mod(t_cycle, cycle ÷ 4) / (cycle ÷ 4)
    seg_t_eased = seg_t < 0.5 ? 2.0 * seg_t * seg_t : 1.0 - (-2.0 * seg_t + 2.0)^2 / 2.0

    arrow_color_dim = tstyle(:border, dim=true)

    arrow_y_top = oy + box_h ÷ 2
    arrow_x1 = ox + box_w
    arrow_x2 = ox + box_w + gap_x - 1
    for x in arrow_x1:arrow_x2
        set_char!(buf, x, arrow_y_top, '─', arrow_color_dim)
    end
    set_char!(buf, arrow_x2, arrow_y_top, '▸', tstyle(:text_dim))

    arrow_x_right = ox + box_w + gap_x + box_w ÷ 2
    arrow_y1 = oy + box_h
    arrow_y2 = oy + box_h + gap_y - 1
    for y in arrow_y1:arrow_y2
        set_char!(buf, arrow_x_right, y, '│', arrow_color_dim)
    end
    set_char!(buf, arrow_x_right, arrow_y2, '▾', tstyle(:text_dim))

    arrow_y_bot = oy + box_h + gap_y + box_h ÷ 2
    for x in arrow_x1:arrow_x2
        set_char!(buf, x, arrow_y_bot, '─', arrow_color_dim)
    end
    set_char!(buf, arrow_x1, arrow_y_bot, '◂', tstyle(:text_dim))

    arrow_x_left = ox + box_w ÷ 2
    for y in arrow_y1:arrow_y2
        set_char!(buf, arrow_x_left, y, '│', arrow_color_dim)
    end
    set_char!(buf, arrow_x_left, arrow_y1, '▴', tstyle(:text_dim))

    packet_style = tstyle(:accent, bold=true)
    trail_style = tstyle(:accent, dim=true)

    if segment == 0
        px = arrow_x1 + round(Int, seg_t_eased * (arrow_x2 - arrow_x1))
        set_char!(buf, px, arrow_y_top, '◆', packet_style)
        px > arrow_x1 && set_char!(buf, px - 1, arrow_y_top, '◇', trail_style)
        px > arrow_x1 + 1 && set_char!(buf, px - 2, arrow_y_top, '·', trail_style)
    elseif segment == 1
        py = arrow_y1 + round(Int, seg_t_eased * (arrow_y2 - arrow_y1))
        set_char!(buf, arrow_x_right, py, '◆', packet_style)
        py > arrow_y1 && set_char!(buf, arrow_x_right, py - 1, '◇', trail_style)
    elseif segment == 2
        px = arrow_x2 - round(Int, seg_t_eased * (arrow_x2 - arrow_x1))
        set_char!(buf, px, arrow_y_bot, '◆', packet_style)
        px < arrow_x2 && set_char!(buf, px + 1, arrow_y_bot, '◇', trail_style)
        px < arrow_x2 - 1 && set_char!(buf, px + 2, arrow_y_bot, '·', trail_style)
    else
        py = arrow_y2 - round(Int, seg_t_eased * (arrow_y2 - arrow_y1))
        set_char!(buf, arrow_x_left, py, '◆', packet_style)
        py < arrow_y2 && set_char!(buf, arrow_x_left, py + 1, '◇', trail_style)
    end

    for (i, b) in enumerate(boxes)
        active = (i - 1) == segment
        leaving = (i - 1) == mod(segment - 1, 4)

        if active
            glow_amount = pulse(m.tick; period=30, lo=0.6, hi=1.0)
            base = to_rgb(theme().accent)
            c = brighten(base, glow_amount * 0.3)
            border_shimmer!(buf, b.rect, c, m.tick; intensity=0.25)
        elseif leaving
            fade = 1.0 - seg_t_eased
            base = to_rgb(getfield(theme(), b.color))
            c = dim_color(base, 1.0 - fade * 0.4)
            border_shimmer!(buf, b.rect, c, m.tick; intensity=fade * 0.15)
        else
            border_shimmer!(buf, b.rect, to_rgb(getfield(theme(), b.color)),
                m.tick; intensity=0.05)
        end

        inner = Rect(b.rect.x + 1, b.rect.y + 1, b.rect.width - 2, b.rect.height - 2)
        title_x = inner.x + max(0, (inner.width - length(b.title)) ÷ 2)
        title_style = active ? tstyle(b.color, bold=true) : tstyle(b.color)
        set_string!(buf, title_x, inner.y, strip(b.title), title_style)

        sub_style = active ? tstyle(:text) : tstyle(:text_dim, dim=true)
        sub_x = inner.x + max(0, (inner.width - length(b.subtitle)) ÷ 2)
        set_string!(buf, sub_x, inner.y + 1, b.subtitle, sub_style)

        if active
            label = i == 1 ? "polling..." :
                    i == 2 ? "dispatch" :
                    i == 3 ? "rendering" : "flushing"
            lab_x = inner.x + max(0, (inner.width - length(label)) ÷ 2)
            set_string!(buf, lab_x, inner.y + 2, label, tstyle(:text_dim, italic=true))
        end
    end

    title = "Event Loop"
    tx = area.x + max(0, (area.width - length(title)) ÷ 2)
    set_string!(buf, tx, area.y, title, tstyle(:title, bold=true))

    si = mod1(m.tick ÷ 4, length(SPINNER_BRAILLE))
    set_char!(buf, area.x + 1, bottom(area), SPINNER_BRAILLE[si], tstyle(:text_dim, dim=true))
    fps_str = "$(area.width)×$(area.height)"
    set_string!(buf, area.x + 3, bottom(area), fps_str, tstyle(:text_dim, dim=true))
end

APP_REGISTRY["event_loop"] = function (tach_file, w, h, frames, fps, realtime=false, warmup=0)
    record_app(EventLoopViz(), tach_file; width=w, height=h, frames=frames, fps=fps,
        realtime=realtime, warmup=warmup)
end

# ─── FPS Stress Test Demo (performance.md) ───────────────────────────────────
# Loads the full TachikomaDemos implementation in an isolated module so the
# markdown stays clean while the real demo generates the GIF.
let fps_path = joinpath(@__DIR__, "..", "demos", "TachikomaDemos", "src", "fps_demo.jl")
    APP_REGISTRY["fps_demo"] = function (tach_file, w, h, frames, fps, realtime=false, warmup=0)
        mod = Module(:_fps_demo_render)
        Core.eval(mod, :(using Tachikoma))
        Core.eval(mod, :(using Match))
        Core.eval(mod, :(import Tachikoma: should_quit, update!, view, init!, cleanup!, task_queue))
        Base.include(mod, fps_path)
        # Match CELL_PX to the GIF exporter's retina cell size (cell_w=20, cell_h=40)
        # so PixelImage dimensions cover the full pane in the rendered GIF.
        orig_cell_px = Tachikoma.CELL_PX[]
        Tachikoma.CELL_PX[] = (w=20, h=40)
        model = Base.invokelatest(Core.eval, mod, :(FPSModel(target_fps=$fps)))
        try
            Base.invokelatest(record_app, model, tach_file; width=w, height=h, frames=frames, fps=fps, realtime=realtime, warmup=warmup)
        finally
            Tachikoma.CELL_PX[] = orig_cell_px
        end
    end
end
