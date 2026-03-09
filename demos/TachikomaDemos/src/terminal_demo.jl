# ═══════════════════════════════════════════════════════════════════════
# Terminal Demo ── terminal emulators and Julia REPLs in floating windows
#
# Ctrl+N spawns a new shell terminal, Ctrl+R spawns an in-process Julia
# REPL. Both render through the same VT parser and PTY infrastructure.
# Ctrl+T cycles tile/cascade layout. Ctrl+J / Ctrl+K cycle focus.
# Ctrl+U spawns "all the way down" — a nested Tachikoma terminal demo
# inside a terminal widget, recursively up to 20 levels deep.
# ═══════════════════════════════════════════════════════════════════════

import Tachikoma

_tachikoma_depth() = parse(Int, get(ENV, "TACHIKOMA_DEPTH", "0"))
const _TACHIKOMA_MAX_DEPTH = 6

# Find the TachikomaDemos project path (needed for recursive spawns)
const _DEMOS_PROJECT = let
    p = dirname(dirname(@__FILE__))  # TachikomaDemos/
    isfile(joinpath(p, "Project.toml")) ? p : nothing
end

@kwdef mutable struct TerminalDemoModel <: Tachikoma.Model
    quit::Bool = false
    tick::Int = 0
    wm::Tachikoma.WindowManager = Tachikoma.WindowManager()
    term_count::Int = 0
    repl_count::Int = 0
    recurse_count::Int = 0
    terminals::Vector{Tachikoma.TerminalWidget} = Tachikoma.TerminalWidget[]
    repls::Vector{Tachikoma.REPLWidget} = Tachikoma.REPLWidget[]
    layout_mode::Symbol = :none   # :none, :tile, :cascade
    _wake_fn::Union{Function, Nothing} = nothing
end

Tachikoma.should_quit(m::TerminalDemoModel) = m.quit
Tachikoma.recording_enabled(::TerminalDemoModel) = false

# ── Window colors ─────────────────────────────────────────────────────

const _TERM_COLORS = [
    Tachikoma.ColorRGB(0xc0, 0x90, 0x60),  # amber
    Tachikoma.ColorRGB(0xc0, 0x60, 0x90),  # pink
    Tachikoma.ColorRGB(0x90, 0x60, 0xc0),  # purple
    Tachikoma.ColorRGB(0x90, 0xc0, 0x60),  # lime
]

const _REPL_COLORS = [
    Tachikoma.ColorRGB(0x60, 0xc0, 0x90),  # green
    Tachikoma.ColorRGB(0x60, 0x90, 0xc0),  # blue
    Tachikoma.ColorRGB(0x70, 0xb0, 0xd0),  # sky
    Tachikoma.ColorRGB(0x50, 0xd0, 0xb0),  # teal
]

# ── Spawn / close helpers ─────────────────────────────────────────────

function _new_window_geometry(wm::Tachikoma.WindowManager, area::Tachikoma.Rect)
    nw = length(wm.windows)
    offset = nw * 2
    w = max(40, area.width - 4 - offset)
    h = max(10, area.height - 3 - offset)
    x = area.x + 1 + offset
    y = area.y + 1 + offset
    x = min(x, Tachikoma.right(area) - w)
    y = min(y, Tachikoma.bottom(area) - h)
    (x, y, w, h)
end

function _close_window!(m::TerminalDemoModel, win_id::Symbol)
    idx = findfirst(w -> w.id == win_id, m.wm.windows)
    idx === nothing && return
    win = m.wm.windows[idx]
    if win.content isa Tachikoma.TerminalWidget
        Tachikoma.close!(win.content)
        filter!(t -> t !== win.content, m.terminals)
    elseif win.content isa Tachikoma.REPLWidget
        Tachikoma.close!(win.content)
        filter!(r -> r !== win.content, m.repls)
    end
    deleteat!(m.wm, idx)
    _reapply_layout!(m)
end

function _spawn_terminal!(m::TerminalDemoModel, area::Tachikoma.Rect)
    m.term_count += 1
    n = m.term_count
    x, y, w, h = _new_window_geometry(m.wm, area)

    shell = get(ENV, "SHELL", "/bin/sh")
    tw = Tachikoma.TerminalWidget([shell];
        rows=h - 2, cols=w - 2, focused=true)
    m._wake_fn !== nothing && Tachikoma.set_wake!(tw, m._wake_fn)
    push!(m.terminals, tw)

    win_id = Symbol("term_$n")
    win = Tachikoma.FloatingWindow(
        id = win_id,
        title = "Terminal #$n",
        x = x, y = y, width = w, height = h,
        content = tw,
        border_color = _TERM_COLORS[mod1(n, length(_TERM_COLORS))],
        closeable = true,
        on_close = () -> _close_window!(m, win_id),
    )
    push!(m.wm, win)
end

function _spawn_repl!(m::TerminalDemoModel, area::Tachikoma.Rect)
    m.repl_count += 1
    n = m.repl_count
    x, y, w, h = _new_window_geometry(m.wm, area)

    rw = Tachikoma.REPLWidget(; rows=h - 2, cols=w - 2)
    m._wake_fn !== nothing && Tachikoma.set_wake!(rw.tw, m._wake_fn)
    push!(m.repls, rw)

    win_id = Symbol("repl_$n")
    win = Tachikoma.FloatingWindow(
        id = win_id,
        title = "Julia REPL #$n",
        x = x, y = y, width = w, height = h,
        content = rw,
        border_color = _REPL_COLORS[mod1(n, length(_REPL_COLORS))],
        closeable = true,
        on_close = () -> _close_window!(m, win_id),
    )
    push!(m.wm, win)
end

# ── Recursive "all the way down" spawn ───────────────────────────────

const _DEPTH_COLORS = [
    Tachikoma.ColorRGB(0xd0, 0x40, 0x40),  # red
    Tachikoma.ColorRGB(0xd0, 0x80, 0x20),  # orange
    Tachikoma.ColorRGB(0xd0, 0xd0, 0x30),  # yellow
    Tachikoma.ColorRGB(0x30, 0xd0, 0x40),  # green
    Tachikoma.ColorRGB(0x30, 0x90, 0xd0),  # blue
    Tachikoma.ColorRGB(0x90, 0x40, 0xd0),  # violet
]

function _spawn_recursive!(m::TerminalDemoModel, area::Tachikoma.Rect)
    next_depth = _tachikoma_depth() + 1
    if next_depth > _TACHIKOMA_MAX_DEPTH
        return  # too deep, refuse
    end

    _DEMOS_PROJECT === nothing && return

    m.recurse_count += 1
    n = m.recurse_count
    x, y, w, h = _new_window_geometry(m.wm, area)

    julia_bin = joinpath(Sys.BINDIR, "julia")
    script = """
    ENV["TACHIKOMA_DEPTH"] = "$next_depth"
    using TachikomaDemos, Tachikoma
    terminal_demo(; tty_out = tty_path())
    """
    cmd = [julia_bin, "--project=$_DEMOS_PROJECT", "-e", script]
    tw = Tachikoma.TerminalWidget(cmd;
        rows=h - 2, cols=w - 2, focused=true)
    m._wake_fn !== nothing && Tachikoma.set_wake!(tw, m._wake_fn)
    push!(m.terminals, tw)

    win_id = Symbol("recurse_$n")
    depth_label = join(["🐢" for _ in 1:min(next_depth, 5)]) * (next_depth > 5 ? "+" : "")
    win = Tachikoma.FloatingWindow(
        id = win_id,
        title = "$depth_label Depth $next_depth",
        x = x, y = y, width = w, height = h,
        content = tw,
        border_color = _DEPTH_COLORS[mod1(next_depth, length(_DEPTH_COLORS))],
        closeable = true,
        on_close = () -> _close_window!(m, win_id),
    )
    push!(m.wm, win)
end

# ── Layout helpers ────────────────────────────────────────────────────

function _resize_pty_widgets!(m::TerminalDemoModel)
    for win in m.wm.windows
        inner_w = win.width - 2
        inner_h = win.height - 2
        (inner_w > 0 && inner_h > 0) || continue
        if win.content isa Tachikoma.TerminalWidget
            Tachikoma.pty_resize!(win.content.pty, inner_h, inner_w)
        elseif win.content isa Tachikoma.REPLWidget
            Tachikoma.pty_resize!(win.content.tw.pty, inner_h, inner_w)
        end
    end
end

function _reapply_layout!(m::TerminalDemoModel)
    if m.layout_mode == :tile
        Tachikoma.tile!(m.wm)
        _resize_pty_widgets!(m)
    elseif m.layout_mode == :cascade
        Tachikoma.cascade!(m.wm)
        _resize_pty_widgets!(m)
    end
end

# ── Async output fast-track ───────────────────────────────────────────

function Tachikoma.has_pending_output(m::TerminalDemoModel)
    for tw in m.terminals
        isready(tw.pty.output) && return true
    end
    for rw in m.repls
        isready(rw.tw.pty.output) && return true
    end
    false
end

function Tachikoma.set_wake!(m::TerminalDemoModel, notify::Function)
    m._wake_fn = notify
    for tw in m.terminals
        Tachikoma.set_wake!(tw, notify)
    end
    for rw in m.repls
        Tachikoma.set_wake!(rw.tw, notify)
    end
end

# ── Event handling ────────────────────────────────────────────────────

function Tachikoma.update!(m::TerminalDemoModel, evt::Tachikoma.Event)
    if evt isa Tachikoma.KeyEvent
        if evt.key == :escape
            m.quit = true
            return
        end

        # Ctrl+N: spawn new terminal
        if evt.key == :ctrl && evt.char == 'n'
            if m.wm.last_area.width > 0
                _spawn_terminal!(m, m.wm.last_area)
            end
            return
        end

        # Ctrl+R: spawn new REPL
        if evt.key == :ctrl && evt.char == 'r'
            if m.wm.last_area.width > 0
                _spawn_repl!(m, m.wm.last_area)
            end
            return
        end

        # Ctrl+U: all the way down — spawn nested Tachikoma
        if evt.key == :ctrl && evt.char == 'u'
            if m.wm.last_area.width > 0
                _spawn_recursive!(m, m.wm.last_area)
            end
            return
        end

        # Ctrl+T: cycle tile → cascade → free
        if evt.key == :ctrl && evt.char == 't'
            if m.layout_mode == :tile
                Tachikoma.cascade!(m.wm)
                m.layout_mode = :cascade
            else
                Tachikoma.tile!(m.wm)
                m.layout_mode = :tile
            end
            _resize_pty_widgets!(m)
            return
        end
    end

    Tachikoma.handle_event!(m.wm, evt)
end

# ── Rendering ─────────────────────────────────────────────────────────

function Tachikoma.view(m::TerminalDemoModel, f::Tachikoma.Frame)
    m.tick += 1
    buf = f.buffer

    # Layout: content | footer
    rows = Tachikoma.split_layout(
        Tachikoma.Layout(Tachikoma.Vertical, [Tachikoma.Fill(), Tachikoma.Fixed(1)]),
        f.area)
    length(rows) < 2 && return
    content_area = rows[1]
    footer_area = rows[2]

    # Spawn first window automatically
    if isempty(m.wm.windows)
        if _tachikoma_depth() > 0 && _tachikoma_depth() < _TACHIKOMA_MAX_DEPTH
            # Keep going deeper automatically
            _spawn_recursive!(m, content_area)
        else
            _spawn_terminal!(m, content_area)
        end
    end

    # Render window manager
    Tachikoma.render(m.wm, content_area, buf; tick=m.tick)

    # Footer
    n = length(m.wm.windows)
    focused = Tachikoma.focused_window(m.wm)
    focus_name = focused !== nothing ? string(focused.title) : "none"
    layout = m.layout_mode == :tile ? "tile" : m.layout_mode == :cascade ? "cascade" : "free"
    depth_str = _tachikoma_depth() > 0 ? " │ depth: $(_tachikoma_depth())" : ""
    down_hint = _tachikoma_depth() + 1 <= _TACHIKOMA_MAX_DEPTH ? " [Ctrl+U] recurse │" : ""
    hint = "$down_hint [Ctrl+N] terminal │ [Ctrl+R] repl │ [Ctrl+T] $layout │ [Ctrl+J/K] focus │ [Esc] quit │ $n window$(n != 1 ? "s" : "")$depth_str │ focus: $focus_name "
    Tachikoma.render(Tachikoma.StatusBar(
        left=[Tachikoma.Span(hint, Tachikoma.tstyle(:text_dim))],
    ), footer_area, buf)
end

# ── Output routing for REPL widgets ──────────────────────────────────

function _route_output(m::TerminalDemoModel, line::String)
    isempty(m.repls) && return
    fw = Tachikoma.focused_window(m.wm)
    if fw !== nothing && fw.content isa Tachikoma.REPLWidget
        Tachikoma.route_output!(fw.content, line)
    else
        Tachikoma.route_output!(m.repls[end], line)
    end
end

# ── Entry point ───────────────────────────────────────────────────────

function terminal_demo(; tty_out=nothing)
    # Inside a PTY (recursive spawn), /dev/tty isn't available because
    # macOS doesn't auto-assign a controlling terminal on posix_spawn.
    # Use ttyname(0) to get the slave device path and pass it as tty_out.
    if tty_out === nothing && _tachikoma_depth() > 0
        p = ccall(:ttyname, Cstring, (Cint,), Cint(0))
        p != C_NULL && (tty_out = unsafe_string(p))
    end
    while true
        model = TerminalDemoModel()
        result = try
            Tachikoma.app(model; fps=30, tty_out,
                on_stdout = line -> _route_output(model, line),
                on_stderr = line -> _route_output(model, line),
            )
        finally
            for tw in model.terminals
                Tachikoma.close!(tw)
            end
            for rw in model.repls
                Tachikoma.close!(rw)
            end
        end
        result === :restart || break
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    terminal_demo()
end
