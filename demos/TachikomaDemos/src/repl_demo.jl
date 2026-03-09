# ═══════════════════════════════════════════════════════════════════════
# REPL Demo ── multiple in-process Julia REPLs in floating windows
#
# Each REPL runs in the current process and shares all loaded modules,
# variables, and state. Ctrl+N spawns a new REPL window, Ctrl+T
# cycles tile/cascade. Ctrl+J / Ctrl+K cycle focus between windows.
# ═══════════════════════════════════════════════════════════════════════

import Tachikoma
using Infiltrator

@kwdef mutable struct REPLDemoModel <: Tachikoma.Model
    quit::Bool = false
    tick::Int = 0
    wm::Tachikoma.WindowManager = Tachikoma.WindowManager()
    repl_count::Int = 0
    repls::Vector{Tachikoma.REPLWidget} = Tachikoma.REPLWidget[]
    layout_mode::Symbol = :none   # :none, :tile, :cascade
    _wake_fn::Union{Function, Nothing} = nothing
end

Tachikoma.should_quit(m::REPLDemoModel) = m.quit
Tachikoma.recording_enabled(::REPLDemoModel) = false

function Tachikoma.has_pending_output(m::REPLDemoModel)
    for rw in m.repls
        isready(rw.tw.pty.output) && return true
    end
    false
end

function Tachikoma.set_wake!(m::REPLDemoModel, notify::Function)
    m._wake_fn = notify
    for rw in m.repls
        Tachikoma.set_wake!(rw.tw, notify)
    end
end

function _close_repl_window!(m::REPLDemoModel, win_id::Symbol)
    idx = findfirst(w -> w.id == win_id, m.wm.windows)
    idx === nothing && return
    win = m.wm.windows[idx]
    if win.content isa Tachikoma.REPLWidget
        rw = win.content
        Tachikoma.close!(rw)
        filter!(r -> r !== rw, m.repls)
    end
    deleteat!(m.wm, idx)
    # Re-apply current layout so remaining windows fill the space
    if m.layout_mode == :tile
        Tachikoma.tile!(m.wm)
        _resize_repls!(m)
    elseif m.layout_mode == :cascade
        Tachikoma.cascade!(m.wm)
        _resize_repls!(m)
    end
end

function _spawn_repl!(m::REPLDemoModel, area::Tachikoma.Rect)
    m.repl_count += 1
    n = m.repl_count

    # Size and position for new window
    nw = length(m.wm.windows)
    offset = nw * 2
    w = max(40, area.width - 4 - offset)
    h = max(10, area.height - 3 - offset)
    x = area.x + 1 + offset
    y = area.y + 1 + offset

    # Fit inside area
    x = min(x, Tachikoma.right(area) - w)
    y = min(y, Tachikoma.bottom(area) - h)

    # Inner dimensions for the REPL (subtract 2 for window border)
    win_id = Symbol("repl_$n")
    rw = Tachikoma.REPLWidget(; rows=h - 2, cols=w - 2)
    m._wake_fn !== nothing && Tachikoma.set_wake!(rw.tw, m._wake_fn)
    push!(m.repls, rw)

    win = Tachikoma.FloatingWindow(
        id = win_id,
        title = "Julia REPL #$n",
        x = x, y = y, width = w, height = h,
        content = rw,
        border_color = _repl_color(n),
        closeable = true,
        on_close = () -> _close_repl_window!(m, win_id),
    )
    push!(m.wm, win)
end

function _repl_color(n::Int)
    colors = [
        Tachikoma.ColorRGB(0x60, 0xc0, 0x90),  # green
        Tachikoma.ColorRGB(0x60, 0x90, 0xc0),  # blue
        Tachikoma.ColorRGB(0xc0, 0x90, 0x60),  # amber
        Tachikoma.ColorRGB(0xc0, 0x60, 0x90),  # pink
        Tachikoma.ColorRGB(0x90, 0x60, 0xc0),  # purple
        Tachikoma.ColorRGB(0x90, 0xc0, 0x60),  # lime
    ]
    colors[mod1(n, length(colors))]
end

function _resize_repls!(m::REPLDemoModel)
    for win in m.wm.windows
        if win.content isa Tachikoma.REPLWidget
            inner_w = win.width - 2
            inner_h = win.height - 2
            if inner_w > 0 && inner_h > 0
                Tachikoma.pty_resize!(win.content.tw.pty, inner_h, inner_w)
            end
        end
    end
end

function Tachikoma.update!(m::REPLDemoModel, evt::Tachikoma.Event)
    if evt isa Tachikoma.KeyEvent
        if evt.key == :escape
            m.quit = true
            return
        end

        # Ctrl+N: spawn new REPL
        if evt.key == :ctrl && evt.char == 'n'
            if m.wm.last_area.width > 0
                _spawn_repl!(m, m.wm.last_area)
            end
            return
        end

        # Ctrl+T: cycle tile → cascade → tile
        if evt.key == :ctrl && evt.char == 't'
            if m.layout_mode == :tile
                Tachikoma.cascade!(m.wm)
                m.layout_mode = :cascade
            else
                Tachikoma.tile!(m.wm)
                m.layout_mode = :tile
            end
            _resize_repls!(m)
            return
        end
    end

    Tachikoma.handle_event!(m.wm, evt)
end

function Tachikoma.view(m::REPLDemoModel, f::Tachikoma.Frame)
    m.tick += 1
    buf = f.buffer

    # Layout: content | footer
    rows = Tachikoma.split_layout(
        Tachikoma.Layout(Tachikoma.Vertical, [Tachikoma.Fill(), Tachikoma.Fixed(1)]),
        f.area)
    length(rows) < 2 && return
    content_area = rows[1]
    footer_area = rows[2]

    # Spawn first REPL automatically if none exist
    if isempty(m.wm.windows)
        _spawn_repl!(m, content_area)
    end

    # Render window manager
    Tachikoma.render(m.wm, content_area, buf; tick=m.tick)

    # Footer
    n = length(m.wm.windows)
    focused = Tachikoma.focused_window(m.wm)
    focus_name = focused !== nothing ? string(focused.title) : "none"
    layout = m.layout_mode == :tile ? "tile" : m.layout_mode == :cascade ? "cascade" : "free"
    hint = " [Ctrl+N] new │ [Ctrl+T] $layout │ [Ctrl+J/K] focus │ [Esc] quit │ $n window$(n != 1 ? "s" : "") │ focus: $focus_name "
    Tachikoma.render(Tachikoma.StatusBar(
        left=[Tachikoma.Span(hint, Tachikoma.tstyle(:text_dim))],
    ), footer_area, buf)
end

function _route_output(m::REPLDemoModel, line::String)
    @infiltrate  # pause here to see if stderr drain reaches this callback
    isempty(m.repls) && return
    # Route to the focused REPL's widget, falling back to the last one
    fw = Tachikoma.focused_window(m.wm)
    if fw !== nothing && fw.content isa Tachikoma.REPLWidget
        Tachikoma.route_output!(fw.content, line)
    else
        Tachikoma.route_output!(m.repls[end], line)
    end
end

function repl_demo(; tty_out=nothing)
    while true
        model = REPLDemoModel()
        result = try
            Tachikoma.app(model; fps=30, tty_out,
                on_stdout = line -> _route_output(model, line),
                on_stderr = line -> _route_output(model, line),
            )
        finally
            for rw in model.repls
                Tachikoma.close!(rw)
            end
        end
        result === :restart || break
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    repl_demo()
end
