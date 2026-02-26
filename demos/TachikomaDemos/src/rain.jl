# ═══════════════════════════════════════════════════════════════════════
# Matrix Rain ── digital rain animation
#
# Falling columns of characters with brightness falloff from head to
# tail. Random mix of half-width katakana and latin characters.
# Pure character buffer, theme-aware colors.
# ═══════════════════════════════════════════════════════════════════════

# Character pools for the rain
const RAIN_CHARS_KATA = collect('ｦ':'ﾝ')  # half-width katakana
const RAIN_CHARS_LATIN = collect('!':'~')
const RAIN_CHARS = vcat(RAIN_CHARS_KATA, RAIN_CHARS_LATIN)

mutable struct RainDrop
    col::Int          # terminal column
    head::Float64     # head position (fractional for smooth movement)
    speed::Float64    # cells per tick
    length::Int       # trail length
    chars::Vector{Char}
end

function random_drop(col::Int, max_height::Int)
    len = rand(8:25)
    spd = 0.2 + rand() * 0.8
    chars = [rand(RAIN_CHARS) for _ in 1:len]
    RainDrop(col, -rand(0:max_height), spd, len, chars)
end

@kwdef mutable struct RainModel <: Model
    quit::Bool = false
    tick::Int = 0
    drops::Vector{RainDrop} = RainDrop[]
    density::Float64 = 0.4   # fraction of columns with active drops
    initialized::Bool = false
end

should_quit(m::RainModel) = m.quit

function init!(m::RainModel, t::Terminal)
    w = t.size.width
    h = t.size.height
    n_drops = round(Int, w * m.density)
    m.drops = [random_drop(rand(1:w), h) for _ in 1:n_drops]
    m.initialized = true
end

function update!(m::RainModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        # Density controls
        evt.char == '+' && (m.density = min(1.0, m.density + 0.05))
        evt.char == '=' && (m.density = min(1.0, m.density + 0.05))
        evt.char == '-' && (m.density = max(0.1, m.density - 0.05))
    end
    evt.key == :escape && (m.quit = true)
end

function rain_color(th::Theme, intensity::Float64)
    # Map intensity 0-1 to theme colors
    # Head is brightest (accent), tail fades through primary to dim
    if intensity > 0.9
        # Head: bright white/accent
        return tstyle(:text_bright, bold=true)
    elseif intensity > 0.6
        return tstyle(:accent)
    elseif intensity > 0.3
        return tstyle(:primary)
    elseif intensity > 0.1
        return tstyle(:secondary, dim=true)
    else
        return tstyle(:text_dim, dim=true)
    end
end

function view(m::RainModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    th = theme()
    w = f.area.width
    h = f.area.height

    # Ensure enough drops for current density
    target = round(Int, w * m.density)
    while length(m.drops) < target
        push!(m.drops, random_drop(rand(1:w), h))
    end

    # Update and render drops
    alive = Bool[]
    for drop in m.drops
        drop.head += drop.speed

        # Occasionally mutate a random character in the trail
        if rand() < 0.08
            idx = rand(1:length(drop.chars))
            drop.chars[idx] = rand(RAIN_CHARS)
        end

        head_row = floor(Int, drop.head)

        # Render trail
        for i in 0:(drop.length - 1)
            row = head_row - i
            (1 <= row <= h) || continue

            intensity = 1.0 - (i / drop.length)
            char_idx = mod1(i + 1, length(drop.chars))
            style = rain_color(th, intensity)
            set_char!(buf, drop.col, row, drop.chars[char_idx], style)
        end

        # Check if drop has fallen off screen
        tail_row = head_row - drop.length
        push!(alive, tail_row <= h)
    end

    # Replace dead drops
    for (i, is_alive) in enumerate(alive)
        if !is_alive
            m.drops[i] = random_drop(rand(1:w), h)
        end
    end

    # Status bar at bottom
    status_y = h
    inst = " [+-]density [k/e/m/a/n/c]theme [q]quit"
    set_string!(buf, 1, status_y, inst, tstyle(:text_dim, dim=true))
end

function rain(; theme_name=nothing, density=0.4)
    theme_name !== nothing && set_theme!(theme_name)
    app(RainModel(density=density); fps=30)
end
