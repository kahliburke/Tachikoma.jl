# ═══════════════════════════════════════════════════════════════════════
# Editor Demo ── CodeEditor widget showcase
#
# Arrow keys to move, type to edit, Tab/Shift-Tab for indent/dedent,
# Esc to quit.
# ═══════════════════════════════════════════════════════════════════════

const _SAMPLE_CODE = """
# Fibonacci with memoization
const _fib_cache = Dict{Int,Int}()

function fibonacci(n::Int)
    n <= 1 && return n
    haskey(_fib_cache, n) && return _fib_cache[n]
    result = fibonacci(n - 1) + fibonacci(n - 2)
    _fib_cache[n] = result
    return result
end

# A simple struct
mutable struct Particle
    x::Float64
    y::Float64
    vx::Float64
    vy::Float64
    mass::Float64
end

function step!(p::Particle, dt::Float64)
    p.x += p.vx * dt
    p.y += p.vy * dt
end

# Constants and collection ops
const GRAVITY = 9.81
const MAX_ITER = 1000

function simulate(particles, steps)
    dt = 0.01
    for i in 1:steps
        for p in particles
            p.vy -= GRAVITY * dt
            step!(p, dt)
        end
    end
    return nothing
end

# String interpolation and macros
function greet(name::String)
    msg = "Hello, \$(name)!"
    @info msg
    return msg
end
"""

@kwdef mutable struct EditorModel <: Model
    quit::Bool = false
    tick::Int = 0
    editor::CodeEditor = CodeEditor(;
        text=_SAMPLE_CODE,
        block=Block(title="CodeEditor",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        focused=true,
        tick=0,
    )
end

should_quit(m::EditorModel) = m.quit

function update!(m::EditorModel, evt::KeyEvent)
    handle_key!(m.editor, evt)
end

function view(m::EditorModel, f::Frame)
    m.tick += 1
    m.editor.tick = m.tick
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    body_area   = rows[2]
    footer_area = rows[3]

    # Header
    title = "Code Editor Demo"
    hx = header_area.x + max(0, (header_area.width - length(title)) ÷ 2)
    set_string!(buf, hx, header_area.y, title, tstyle(:title, bold=true))

    # Editor
    render(m.editor, body_area, buf)

    # Mode indicator + footer
    mode = editor_mode(m.editor)
    mode_span = if mode == :normal
        Span(" NORMAL ", tstyle(:accent, bold=true))
    elseif mode == :search
        Span(" SEARCH ", tstyle(:warning, bold=true))
    else
        Span(" INSERT ", tstyle(:success, bold=true))
    end

    ln = m.editor.cursor_row
    col = m.editor.cursor_col + 1
    pos = "Ln $(ln), Col $(col)"
    render(StatusBar(
        left=[mode_span, Span("  [i]insert [Esc]normal [/]search [Ctrl+C]quit ", tstyle(:text_dim))],
        right=[Span("$(pos) ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function editor_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(EditorModel(); fps=30)
end
