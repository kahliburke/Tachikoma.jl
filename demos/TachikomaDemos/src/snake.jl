# ═══════════════════════════════════════════════════════════════════════
# Snake ── classic snake game
#
# Arrow keys to steer. Snake grows on eating food. Speed increases
# with score. Wrapping edges. Score and high score display.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct SnakeModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Game state
    width::Int = 40
    height::Int = 20
    snake::Vector{Tuple{Int,Int}} = [(20, 10)]
    direction::Tuple{Int,Int} = (1, 0)   # (dx, dy)
    next_dir::Tuple{Int,Int} = (1, 0)
    food::Tuple{Int,Int} = (30, 10)
    score::Int = 0
    high_score::Int = 0
    game_over::Bool = false
    paused::Bool = false
    speed::Int = 6                        # ticks between moves (at 60fps)
end

should_quit(m::SnakeModel) = m.quit

function snake_init!(m::SnakeModel, w::Int, h::Int)
    m.width = max(20, w - 2)     # inside borders
    m.height = max(10, h - 4)    # leave room for border + status
    cx = m.width ÷ 2
    cy = m.height ÷ 2
    m.snake = [(cx, cy), (cx - 1, cy), (cx - 2, cy)]
    m.direction = (1, 0)
    m.next_dir = (1, 0)
    m.score = 0
    m.game_over = false
    m.paused = false
    m.speed = 6
    spawn_food!(m)
end

function init!(m::SnakeModel, t::Terminal)
    snake_init!(m, t.size.width, t.size.height)
end

function spawn_food!(m::SnakeModel)
    for _ in 1:1000
        fx = rand(1:m.width)
        fy = rand(1:m.height)
        if (fx, fy) ∉ m.snake
            m.food = (fx, fy)
            return
        end
    end
end

function update!(m::SnakeModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        if m.game_over && evt.char == 'r'
            snake_init!(m, m.width, m.height)
        end
    end
    # Direction (prevent 180° reversal)
    dx, dy = m.direction
    if evt.key == :up && dy != 1
        m.next_dir = (0, -1)
    elseif evt.key == :down && dy != -1
        m.next_dir = (0, 1)
    elseif evt.key == :left && dx != 1
        m.next_dir = (-1, 0)
    elseif evt.key == :right && dx != -1
        m.next_dir = (1, 0)
    end
    evt.key == :escape && (m.quit = true)
end

function snake_step!(m::SnakeModel)
    m.direction = m.next_dir
    dx, dy = m.direction
    hx, hy = m.snake[1]
    nx = mod1(hx + dx, m.width)
    ny = mod1(hy + dy, m.height)

    # Self collision
    if (nx, ny) in m.snake
        m.game_over = true
        m.high_score = max(m.high_score, m.score)
        return
    end

    pushfirst!(m.snake, (nx, ny))

    if (nx, ny) == m.food
        m.score += 1
        # Speed up every 5 points
        m.speed = max(2, 6 - m.score ÷ 5)
        spawn_food!(m)
    else
        pop!(m.snake)
    end
end

function view(m::SnakeModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Move snake
    if !m.game_over && !m.paused && mod(m.tick, m.speed) == 0
        snake_step!(m)
    end

    # Layout: border around game area + status
    block = Block(
        title="snake",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    content = render(block, f.area, buf)

    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), content)
    length(rows) < 2 && return
    game_area = rows[1]
    status_row = rows[2]

    # Offset for centering game field
    ox = game_area.x + max(0, (game_area.width - m.width) ÷ 2)
    oy = game_area.y + max(0, (game_area.height - m.height) ÷ 2)

    # Draw food
    fx, fy = m.food
    food_x = ox + fx - 1
    food_y = oy + fy - 1
    if in_bounds(buf, food_x, food_y)
        # Pulsing food
        food_ch = mod(m.tick, 20) < 10 ? '◆' : '◇'
        set_char!(buf, food_x, food_y, food_ch, tstyle(:warning, bold=true))
    end

    # Draw snake
    for (i, (sx, sy)) in enumerate(m.snake)
        px = ox + sx - 1
        py = oy + sy - 1
        in_bounds(buf, px, py) || continue
        if i == 1
            # Head
            ch = if m.direction == (1, 0)
                '▸'
            elseif m.direction == (-1, 0)
                '◂'
            elseif m.direction == (0, -1)
                '▴'
            else
                '▾'
            end
            set_char!(buf, px, py, ch,
                      m.game_over ? tstyle(:error, bold=true) :
                                    tstyle(:accent, bold=true))
        else
            # Body: gradient from bright to dim
            frac = i / length(m.snake)
            style = frac < 0.5 ? tstyle(:primary) : tstyle(:secondary)
            set_char!(buf, px, py, '█', style)
        end
    end

    # Game over overlay
    if m.game_over
        msg = "GAME OVER"
        mx = ox + max(0, (m.width - length(msg)) ÷ 2)
        my = oy + m.height ÷ 2
        if in_bounds(buf, mx, my)
            set_string!(buf, mx, my, msg, tstyle(:error, bold=true))
            restart_msg = "press [r] to restart"
            rx = ox + max(0, (m.width - length(restart_msg)) ÷ 2)
            in_bounds(buf, rx, my + 1) &&
                set_string!(buf, rx, my + 1, restart_msg, tstyle(:text_dim))
        end
    end

    # Paused overlay
    if m.paused && !m.game_over
        msg = "PAUSED"
        mx = ox + max(0, (m.width - length(msg)) ÷ 2)
        my = oy + m.height ÷ 2
        in_bounds(buf, mx, my) &&
            set_string!(buf, mx, my, msg, tstyle(:warning, bold=true))
    end

    # Status bar
    score_str = "Score: $(m.score)"
    hi_str = "Hi: $(m.high_score)"
    speed_str = "Speed: $(7 - m.speed)"
    controls = "[arrows]move [p]pause [r]restart [q]quit"
    render(StatusBar(
        left=[
            Span("  $(score_str) ", tstyle(:primary, bold=true)),
            Span("$(DOT) $(hi_str) ", tstyle(:text_dim)),
            Span("$(DOT) $(speed_str)", tstyle(:text_dim)),
        ],
        right=[Span(controls * " ", tstyle(:text_dim))],
    ), status_row, buf)
end

function snake(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(SnakeModel(); fps=60)
end
