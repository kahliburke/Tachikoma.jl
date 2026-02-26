# ═══════════════════════════════════════════════════════════════════════
# Game of Life ── Conway's cellular automaton on braille canvas
#
# Each cell maps to a braille dot (2×4 sub-character resolution).
# Interactive cursor, play/pause, step, randomize, clear.
# No external dependencies.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct LifeModel <: Model
    quit::Bool = false
    tick::Int = 0
    grid::Matrix{Bool} = falses(80, 60)
    next::Matrix{Bool} = falses(80, 60)
    running::Bool = false
    generation::Int = 0
    population::Int = 0
    cursor_x::Int = 40
    cursor_y::Int = 30
    speed::Int = 4              # frames between steps when running
    canvas::Union{Canvas, BlockCanvas, Nothing} = nothing
    canvas_area::Rect = Rect(0, 0, 0, 0)
    drawing::Symbol = :none     # :draw, :erase, or :none
    brush::Int = 3              # brush radius in grid cells
end

should_quit(m::LifeModel) = m.quit

function life_randomize!(m::LifeModel; density=0.3)
    m.grid .= rand(size(m.grid)...) .< density
    m.generation = 0
    m.population = count(m.grid)
end

function life_clear!(m::LifeModel)
    fill!(m.grid, false)
    m.generation = 0
    m.population = 0
end

function life_step!(m::LifeModel)
    grid = m.grid
    buf = m.next
    w, h = size(grid)
    fill!(buf, false)
    pop = 0
    @inbounds for x in 1:w, y in 1:h
        # Inline neighbor count — toroidal wrap
        xm = x == 1 ? w : x - 1
        xp = x == w ? 1 : x + 1
        ym = y == 1 ? h : y - 1
        yp = y == h ? 1 : y + 1
        n = Int(grid[xm, ym]) + Int(grid[xm, y]) + Int(grid[xm, yp]) +
            Int(grid[x,  ym])                     + Int(grid[x,  yp]) +
            Int(grid[xp, ym]) + Int(grid[xp, y]) + Int(grid[xp, yp])
        alive = grid[x, y] ? (n == 2 || n == 3) : (n == 3)
        buf[x, y] = alive
        pop += alive
    end
    m.grid, m.next = buf, grid
    m.generation += 1
    m.population = pop
end

function init!(m::LifeModel, t::Terminal)
    cw = t.size.width - 2
    ch = t.size.height - 4
    gw = clamp(cw * 2, 20, 600)
    gh = clamp(ch * 4, 20, 400)
    m.grid = falses(gw, gh)
    m.next = falses(gw, gh)
    m.cursor_x = gw ÷ 2
    m.cursor_y = gh ÷ 2
    m.canvas = create_canvas(cw, ch; style=tstyle(:primary))
    life_randomize!(m; density=0.25)
end

function update!(m::LifeModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.running = !m.running)
        evt.char == 's' && life_step!(m)
        evt.char == 'r' && life_randomize!(m)
        evt.char == 'x' && life_clear!(m)
        evt.char == '+' && (m.speed = max(1, m.speed - 1))
        evt.char == '=' && (m.speed = max(1, m.speed - 1))
        evt.char == '-' && (m.speed = min(30, m.speed + 1))
    elseif evt.key == :enter
        life_step!(m)
    end
    evt.key == :escape && (m.quit = true)
end

function life_paint!(m::LifeModel, gx::Int, gy::Int, alive::Bool)
    gw, gh = size(m.grid)
    r = m.brush
    for dx in -r:r, dy in -r:r
        dx * dx + dy * dy > r * r && continue
        nx, ny = gx + dx, gy + dy
        (1 <= nx <= gw && 1 <= ny <= gh) || continue
        was = m.grid[nx, ny]
        was == alive && continue
        m.grid[nx, ny] = alive
        m.population += alive ? 1 : -1
    end
end

function mouse_to_grid(m::LifeModel, mx::Int, my::Int)
    ca = m.canvas_area
    # Terminal cell → dot-space → grid coord (1-based)
    gx = (mx - ca.x) * 2 + 1
    gy = (my - ca.y) * 4 + 1
    (gx, gy)
end

function update!(m::LifeModel, evt::MouseEvent)
    ca = m.canvas_area
    ca.width == 0 && return
    in_canvas = contains(ca, evt.x, evt.y)

    if evt.button == mouse_left
        if evt.action == mouse_press && in_canvas
            m.drawing = :draw
            gx, gy = mouse_to_grid(m, evt.x, evt.y)
            life_paint!(m, gx, gy, true)
            m.cursor_x, m.cursor_y = gx, gy
        elseif evt.action == mouse_drag && m.drawing == :draw && in_canvas
            gx, gy = mouse_to_grid(m, evt.x, evt.y)
            life_paint!(m, gx, gy, true)
            m.cursor_x, m.cursor_y = gx, gy
        elseif evt.action == mouse_release
            m.drawing = :none
        end
    elseif evt.button == mouse_right
        if evt.action == mouse_press && in_canvas
            m.drawing = :erase
            gx, gy = mouse_to_grid(m, evt.x, evt.y)
            life_paint!(m, gx, gy, false)
            m.cursor_x, m.cursor_y = gx, gy
        elseif evt.action == mouse_drag && m.drawing == :erase && in_canvas
            gx, gy = mouse_to_grid(m, evt.x, evt.y)
            life_paint!(m, gx, gy, false)
            m.cursor_x, m.cursor_y = gx, gy
        elseif evt.action == mouse_release
            m.drawing = :none
        end
    elseif evt.button == mouse_middle && evt.action == mouse_press
        life_clear!(m)
    elseif evt.button == mouse_scroll_up
        m.brush = min(12, m.brush + 1)
    elseif evt.button == mouse_scroll_down
        m.brush = max(1, m.brush - 1)
    end
end


function view(m::LifeModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Auto-step when running
    if m.running && mod(m.tick, m.speed) == 0
        life_step!(m)
    end

    # Layout: canvas area + 2 status rows
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(2)]), f.area)
    length(rows) < 2 && return
    canvas_area = rows[1]
    status_area = rows[2]
    m.canvas_area = canvas_area

    cw = canvas_area.width
    ch = canvas_area.height
    (cw < 2 || ch < 1) && return

    # Reuse canvas, resize if needed
    canvas = m.canvas
    if canvas === nothing || canvas.width != cw || canvas.height != ch
        canvas = create_canvas(cw, ch; style=tstyle(:primary))
        m.canvas = canvas
    else
        clear!(canvas)
    end

    grid = m.grid
    gw, gh = size(grid)
    dw = cw * 2
    dh = ch * 4

    # Plot living cells
    @inbounds for gx in 1:min(gw, dw), gy in 1:min(gh, dh)
        grid[gx, gy] || continue
        set_point!(canvas, gx - 1, gy - 1)
    end

    render_canvas(canvas, canvas_area, f)

    # Status line 1: info
    sy = status_area.y
    info = "gen $(m.generation) $(DOT) pop $(m.population)/$(gw*gh) $(DOT) " *
           "brush $(m.brush) $(DOT) " *
           (m.running ? "RUNNING ($(m.speed))" : "PAUSED")
    set_string!(buf, 1, sy, info, tstyle(:text_dim))

    # Status line 2: controls
    sy += 1
    if sy <= bottom(f.area)
        ctrl = "[Lclick]draw [Rclick]erase [scroll]brush [Mclick]clear " *
               "[enter/s]step [p]play [r]andom [x]clear [+-]speed [q]uit"
        set_string!(buf, 1, sy, ctrl, tstyle(:text_dim, dim=true))
    end
end

function life(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(LifeModel(); fps=60)
end
