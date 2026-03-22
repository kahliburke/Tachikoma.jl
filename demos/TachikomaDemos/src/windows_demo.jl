# ═══════════════════════════════════════════════════════════════════════
# Overlapping Windows Demo
#
# Showcases FloatingWindow + WindowManager widgets with:
#   • Overlapping windows with z-order and animated shimmer borders
#   • Semi-transparent windows (see-through blending)
#   • Live sparklines, Form, DataTable, input widgets, noise inside windows
#   • Title-bar dragging and corner resizing with mouse
#   • Focus cycling with F2 / F3
#   • Animated tile (Ctrl+T) and cascade (Ctrl+K) layouts
#   • Detail popup on DataTable Enter, closeable via ✕ or Escape
#
# Keys:   F2 / F3         — cycle window focus
#         +/-             — adjust window opacity
#         Ctrl+T          — tile layout (animated)
#         Ctrl+K          — cascade/stack layout (animated)
#         Enter           — open detail popup (on DataTable row)
#         Escape          — close focused detail popup
#         q               — quit
# Mouse:  Click to focus, drag title bar to move, drag corners to resize
#         Wheel over DATA/INPUTS windows to test scrolling
#         Click ✕ to close popup windows
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma

# ── Color palettes per window ──────────────────────────────────────────

const _WDM_PALETTES = Dict(
    :signals => (border=ColorRGB(0x6c, 0xd0, 0xf0), accent=ColorRGB(0x4e, 0xb8, 0xe0), dim=ColorRGB(0x20, 0x40, 0x55)),
    :inputs  => (border=ColorRGB(0xf0, 0x80, 0xd0), accent=ColorRGB(0xe0, 0x60, 0xb0), dim=ColorRGB(0x55, 0x20, 0x45)),
    :data    => (border=ColorRGB(0xa0, 0xe0, 0x70), accent=ColorRGB(0x80, 0xd0, 0x50), dim=ColorRGB(0x30, 0x50, 0x20)),
    :form    => (border=ColorRGB(0xf0, 0xc0, 0x50), accent=ColorRGB(0xe0, 0xa0, 0x30), dim=ColorRGB(0x55, 0x45, 0x15)),
    :noise   => (border=ColorRGB(0xb0, 0x90, 0xf0), accent=ColorRGB(0x90, 0x70, 0xe0), dim=ColorRGB(0x30, 0x20, 0x50)),
)

# ── Model ─────────────────────────────────────────────────────────────

@kwdef mutable struct WindowsDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    wm::Union{WindowManager, Nothing} = nothing
    opacity::Float64 = 0.95
    spark_data::Vector{Vector{Float64}} = [Float64[] for _ in 1:4]
    form::Union{Form, Nothing} = nothing
    inputs_form::Union{Form, Nothing} = nothing
    datatable::Union{DataTable, Nothing} = nothing
    detail_win_ids::Set{Symbol} = Set{Symbol}()
    last_area::Rect = Rect()
end

Tachikoma.should_quit(m::WindowsDemoModel) = m.quit

function _ensure_windows!(m::WindowsDemoModel, area::Rect)
    m.last_area = area
    m.wm !== nothing && return

    # Create Form widget
    m.form = Form([
        FormField("Name",   TextInput(; text="", label="")),
        FormField("Role",   DropDown(["Engineer", "Designer", "Manager", "Analyst"])),
        FormField("Active", Checkbox("Enabled"; checked=true)),
    ]; submit_label="Save", bordered_submit=true)

    # Create input widgets test Form — includes Button, Checkbox, RadioGroup, DropDown
    m.inputs_form = Form([
        FormField("Search",  TextInput(; text="", label="")),
        FormField("Notify",  Checkbox("Enable alerts"; checked=false)),
        FormField("Level",   RadioGroup(["Low", "Medium", "High"])),
        FormField("Mode",    DropDown(["Auto", "Manual", "Scheduled", "Burst"])),
        FormField("Action",  Button("Run Task"; bordered=true)),
    ]; submit_label="Apply", bordered_submit=true)

    # Create DataTable widget (enough rows to exercise wheel scrolling)
    nodes = ["node-$(lpad(string(i), 2, '0'))" for i in 1:24]
    cpu = [mod(17 * i + 23, 100) for i in 1:24]
    mem = [256 + mod(173 * i, 1792) for i in 1:24]
    status_cycle = ["ok", "warn", "ok", "ok", "crit", "ok"]
    statuses = [status_cycle[mod1(i, length(status_cycle))] for i in 1:24]
    m.datatable = DataTable(
        ["Node", "CPU %", "Mem MB", "Status"],
        [
            Any[nodes...],
            Any[cpu...],
            Any[mem...],
            Any[statuses...],
        ];
        selected=1,
    )

    wm = WindowManager(focus_shortcuts=true)
    push!(wm, FloatingWindow(id=:signals, title="SIGNALS", x=2, y=2, width=46, height=12,
                              border_color=_WDM_PALETTES[:signals].border, box=BOX_ROUNDED))
    push!(wm, FloatingWindow(id=:inputs, title="INPUTS", x=18, y=6, width=40, height=18,
                              border_color=_WDM_PALETTES[:inputs].border, box=BOX_ROUNDED,
                              content=m.inputs_form))
    push!(wm, FloatingWindow(id=:data, title="DATA", x=42, y=2, width=38, height=14,
                              border_color=_WDM_PALETTES[:data].border, box=BOX_HEAVY,
                              content=m.datatable))
    push!(wm, FloatingWindow(id=:form, title="FORM", x=6, y=14, width=36, height=11,
                              border_color=_WDM_PALETTES[:form].border, box=BOX_DOUBLE,
                              content=m.form))
    push!(wm, FloatingWindow(id=:noise, title="NOISE", x=52, y=12, width=28, height=10,
                              border_color=_WDM_PALETTES[:noise].border, box=BOX_ROUNDED))
    m.wm = wm
end

# ── Update ────────────────────────────────────────────────────────────

function Tachikoma.update!(m::WindowsDemoModel, evt::KeyEvent)
    wm = m.wm
    wm === nothing && return

    # ── Close focused detail popup on Escape ──
    fw = focused_window(wm)
    if fw !== nothing && fw.id in m.detail_win_ids
        if evt.key == :escape
            _close_detail!(m, fw.id)
            return
        end
    end

    @match (evt.key, evt.char) begin
        (:char, 'q') => (m.quit = true)
        (:char, '+') || (:char, '=') => begin
            step = m.opacity >= 0.90 ? 0.01 : 0.05
            m.opacity = min(1.0, m.opacity + step)
        end
        (:char, '-') || (:char, '_') => begin
            step = m.opacity > 0.90 ? 0.01 : 0.05
            m.opacity = max(0.1, m.opacity - step)
        end
        _ => begin
            # Delegate to WindowManager first
            handled = handle_key!(wm, evt)

            # Layout shortcuts (Ctrl+T = tile, Ctrl+K = cascade/stack)
            if !handled
                @match (evt.key, evt.char) begin
                    (:ctrl, 't') => tile!(wm, m.last_area)
                    (:ctrl, 'k') => cascade!(wm, m.last_area)
                    _ => nothing
                end
            end

            # Check for DataTable Enter → detail popup (allow multiple)
            if evt.key == :enter
                fw2 = focused_window(wm)
                if fw2 !== nothing && fw2.id === :data && m.datatable !== nothing
                    dt = m.datatable
                    if dt.selected > 0
                        _open_detail_popup!(m, dt, dt.selected)
                    end
                end
            end
        end
    end
end

function _close_detail!(m::WindowsDemoModel, id::Symbol)
    wm = m.wm
    wm === nothing && return
    idx = findfirst(w -> w.id === id, wm.windows)
    if idx !== nothing
        deleteat!(wm, idx)
    end
    delete!(m.detail_win_ids, id)
end

function _open_detail_popup!(m::WindowsDemoModel, dt::DataTable, row::Int)
    wm = m.wm
    wm === nothing && return

    # Build row data
    row_data = [(col.name, _wdm_format(col, row)) for col in dt.columns]
    node_name = length(dt.columns) > 0 ? _wdm_format(dt.columns[1], row) : "Row $row"

    # Unique id per row (close existing popup for same row if any)
    detail_id = Symbol("detail_", row)
    if detail_id in m.detail_win_ids
        _close_detail!(m, detail_id)
    end
    push!(m.detail_win_ids, detail_id)

    # Stagger popup position based on number of open popups
    offset = length(m.detail_win_ids) - 1
    pw, ph = 30, length(row_data) + 4
    cx = max(1, (m.last_area.width - pw) ÷ 2 + m.last_area.x + offset * 2)
    cy = max(1, (m.last_area.height - ph) ÷ 2 + m.last_area.y + offset)

    win = FloatingWindow(id=detail_id, title=node_name, x=cx, y=cy,
                         width=pw, height=ph, box=BOX_DOUBLE,
                         border_color=ColorRGB(0xff, 0xd0, 0x60), resizable=false,
                         closeable=true)

    # Set on_close callback to remove from wm and tracking set
    let mid = detail_id, model = m
        win.on_close = () -> _close_detail!(model, mid)
    end

    let rd = row_data
        win.on_render = (inner, buf, focused, frame) -> begin
            (inner.width < 3 || inner.height < 2) && return
            for (i, (label, val)) in enumerate(rd)
                y = inner.y + i - 1
                y > bottom(inner) && break
                set_string!(buf, inner.x + 1, y, label * ":", Style(fg=ColorRGB(0xa0, 0xa0, 0xa0)))
                set_string!(buf, inner.x + 10, y, val, Style(fg=ColorRGB(0xff, 0xff, 0xff), bold=true))
            end
            hy = bottom(inner)
            set_string!(buf, inner.x + 1, hy, "[Esc] close",
                        Style(fg=ColorRGB(0x80, 0x80, 0x80), dim=true))
        end
    end

    push!(wm, win)
end

function _wdm_format(col, row::Int)
    row > length(col.values) && return ""
    string(col.values[row])
end

function Tachikoma.update!(m::WindowsDemoModel, evt::MouseEvent)
    m.wm !== nothing && handle_mouse!(m.wm, evt)
end

# ── View ──────────────────────────────────────────────────────────────

function Tachikoma.view(m::WindowsDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area
    _ensure_windows!(m, area)
    wm = m.wm

    # Update sparkline data with animated waves
    for (i, data) in enumerate(m.spark_data)
        v = 0.5 + 0.4 * sin(m.tick * 0.05 * i + i * 1.2) +
            0.1 * sin(m.tick * 0.13 + i * 3.7)
        push!(data, clamp(v, 0.0, 1.0))
        length(data) > 120 && popfirst!(data)
    end

    # ── Background: solid theme color ──
    bg = to_rgb(theme().bg)
    bg_s = Style(bg=bg)
    for row in area.y:bottom(area)
        for col in area.x:right(area)
            set_char!(buf, col, row, ' ', bg_s)
        end
    end

    # ── Set opacity for all windows, attach render callbacks ──
    for (i, w) in enumerate(wm.windows)
        w.opacity = m.opacity
        # Only set on_render for callback-based windows (not content widgets or detail popups)
        if w.id === :signals
            colors = _WDM_PALETTES[:signals]
            let c = colors
                w.on_render = (inner, buf, focused, frame) -> begin
                    _render_signals!(m, c, inner, buf, focused, m.tick)
                end
            end
        elseif w.id === :noise
            colors = _WDM_PALETTES[:noise]
            let c = colors
                w.on_render = (inner, buf, focused, frame) -> begin
                    _render_noise!(c, inner, buf, focused, m.tick)
                end
            end
        end
    end

    # ── Render windows ──
    render(wm, area, buf; tick=m.tick)

    # ── Footer ──
    footer_y = bottom(area)
    footer_bg = dim_color(bg, 0.5)
    for x in area.x:right(area)
        set_char!(buf, x, footer_y, ' ', Style(bg=footer_bg))
    end
    opacity_pct = round(Int, m.opacity * 100)
    hint = " F2/F3:cycle │ wheel:DATA/INPUTS │ +/-:opacity($(opacity_pct)%) │ ^T:tile ^K:stack │ q:quit "
    set_string!(buf, area.x + 1, footer_y, hint,
                Style(fg=brighten(bg, 0.8), bg=footer_bg, bold=true))
end

# ── Per-window content rendering ─────────────────────────────────────

function _render_signals!(m::WindowsDemoModel, colors::NamedTuple,
                          inner::Rect, buf::Buffer, focused::Bool, tick::Int)
    (inner.width < 3 || inner.height < 3) && return
    s = focused ? Style(fg=colors.accent, bold=true) : Style(fg=dim_color(colors.accent, 0.3))
    set_string!(buf, inner.x + 1, inner.y, "Live Signal Monitor", s)

    data1 = m.spark_data[1]
    data2 = m.spark_data[2]

    if inner.height >= 8
        label_y = inner.y + 2
        set_string!(buf, inner.x + 1, label_y, "CH-1", Style(fg=colors.border))
        spark_rect = Rect(inner.x + 6, label_y, inner.width - 7, 3)
        render(Sparkline(data1; style=Style(fg=colors.accent), max_val=1.0), spark_rect, buf)

        label_y2 = label_y + 4
        if label_y2 + 2 <= bottom(inner)
            set_string!(buf, inner.x + 1, label_y2, "CH-2", Style(fg=colors.border))
            spark_rect2 = Rect(inner.x + 6, label_y2, inner.width - 7, 3)
            render(Sparkline(data2; style=Style(fg=brighten(colors.accent, 0.2)), max_val=1.0), spark_rect2, buf)
        end
    end
end

function _render_noise!(colors::NamedTuple,
                        inner::Rect, buf::Buffer, focused::Bool, tick::Int)
    fill_noise!(buf, inner, colors.dim, colors.accent, tick; scale=0.25, speed=0.04)

    if inner.width >= 12 && inner.height >= 3
        label = " NOISE FIELD "
        lx = center(inner, length(label), 1).x
        ly = center(inner, 1, 1).y
        s = Style(fg=ColorRGB(0xff, 0xff, 0xff), bg=ColorRGB(0x00, 0x00, 0x00), bold=true)
        set_string!(buf, lx, ly, label, s)
    end
end

# ── Entry point ───────────────────────────────────────────────────────

function windows_demo()
    app(WindowsDemoModel(); fps=30)
end

if abspath(PROGRAM_FILE) == @__FILE__
    windows_demo()
end
