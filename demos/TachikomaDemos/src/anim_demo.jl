# ═══════════════════════════════════════════════════════════════════════
# Animation Demo ── showcases the Tween/Spring/Timeline system
#
# Four panels demonstrating the animation primitives:
#   1. Easing gallery    — horizontal bars comparing all easing curves
#   2. Spring physics    — interactive spring with retarget on keypress
#   3. Timeline sequence — staggered tween cascade
#   4. Pingpong & loop   — looping tweens with different easing
#
# All animation is driven through the Animator helper. No manual
# sin(tick) math needed.
# ═══════════════════════════════════════════════════════════════════════

const EASING_NAMES = [
    ("linear",        linear),
    ("ease_in_quad",  ease_in_quad),
    ("ease_out_quad", ease_out_quad),
    ("ease_in_out_q", ease_in_out_quad),
    ("ease_in_cub",   ease_in_cubic),
    ("ease_out_cub",  ease_out_cubic),
    ("ease_in_out_c", ease_in_out_cubic),
    ("ease_out_elst", ease_out_elastic),
    ("ease_out_bnce", ease_out_bounce),
    ("ease_out_back", ease_out_back),
]

@kwdef mutable struct AnimDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Easing gallery — one tween per easing function
    easing_tweens::Vector{Tween} = [
        tween(0.0, 1.0; duration=60, easing=fn, loop=:pingpong)
        for (_, fn) in EASING_NAMES
    ]
    # Spring — interactive target
    spring::Spring = Spring(0.5; value=0.0, stiffness=180.0)
    spring_target_idx::Int = 1
    spring_targets::Vector{Float64} = [0.0, 0.25, 0.5, 0.75, 1.0]
    spring_trail::Vector{Float64} = Float64[]
    # Timeline — staggered cascade
    cascade_tweens::Vector{Tween} = Tween[]
    cascade_timeline::Union{Timeline, Nothing} = nothing
    # Looping tweens
    loop_tween::Tween = tween(0.0, 1.0; duration=45, easing=ease_out_cubic, loop=:loop)
    pp_tween::Tween = tween(0.0, 1.0; duration=60, easing=ease_in_out_cubic, loop=:pingpong)
    bounce_tween::Tween = tween(0.0, 1.0; duration=50, easing=ease_out_bounce, loop=:pingpong)
    elastic_tween::Tween = tween(0.0, 1.0; duration=70, easing=ease_out_elastic, loop=:pingpong)
end

function _init_cascade!(m::AnimDemoModel, n::Int=8)
    m.cascade_tweens = [tween(0.0, 1.0; duration=30, easing=ease_out_cubic) for _ in 1:n]
    m.cascade_timeline = stagger(m.cascade_tweens...; delay=5)
end

should_quit(m::AnimDemoModel) = m.quit

function init!(m::AnimDemoModel, ::Terminal)
    _init_cascade!(m)
end

function update!(m::AnimDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        # Spring: cycle target
        if evt.char == ' '
            m.spring_target_idx = mod1(m.spring_target_idx + 1, length(m.spring_targets))
            retarget!(m.spring, m.spring_targets[m.spring_target_idx])
        end
        # Restart cascade
        if evt.char == 'r'
            for tw in m.cascade_tweens; reset!(tw); end
            m.cascade_timeline !== nothing && (m.cascade_timeline.frame = 0)
        end
        # Restart easing gallery
        if evt.char == 'e'
            for tw in m.easing_tweens; reset!(tw); end
        end
    elseif evt.key == :up
        m.spring_target_idx = mod1(m.spring_target_idx + 1, length(m.spring_targets))
        retarget!(m.spring, m.spring_targets[m.spring_target_idx])
    elseif evt.key == :down
        m.spring_target_idx = mod1(m.spring_target_idx - 1, length(m.spring_targets))
        retarget!(m.spring, m.spring_targets[m.spring_target_idx])
    end
    evt.key == :escape && (m.quit = true)
end

function view(m::AnimDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # ── Advance all animations ──
    for tw in m.easing_tweens; advance!(tw); end
    advance!(m.spring)
    push!(m.spring_trail, m.spring.value)
    length(m.spring_trail) > 120 && popfirst!(m.spring_trail)
    if m.cascade_timeline !== nothing && !done(m.cascade_timeline)
        advance!(m.cascade_timeline)
    end
    advance!(m.loop_tween)
    advance!(m.pp_tween)
    advance!(m.bounce_tween)
    advance!(m.elastic_tween)

    # ── Outer frame ──
    outer = Block(
        title="animation system",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    main = render(outer, f.area, buf)

    # Layout: header | top row | bottom row | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fill(), Fixed(1)]), main)
    length(rows) < 4 && return
    header = rows[1]
    top_area = rows[2]
    bot_area = rows[3]
    footer = rows[4]

    # ── Header ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header.x + 2, header.y,
                "Tween · Spring · Timeline · Easing", tstyle(:primary, bold=true))
    set_string!(buf, header.x + 39, header.y,
                " $(DOT) tick $(m.tick)", tstyle(:text_dim))

    # ── Top row: easing gallery | spring ──
    top_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), top_area)
    length(top_cols) < 2 && return

    _draw_easing_gallery(m, buf, top_cols[1])
    _draw_spring_panel(m, buf, top_cols[2])

    # ── Bottom row: cascade timeline | looping tweens ──
    bot_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), bot_area)
    length(bot_cols) < 2 && return

    _draw_cascade(m, buf, bot_cols[1])
    _draw_loops(m, buf, bot_cols[2])

    # ── Footer ──
    render(StatusBar(
        left=[Span("  [space/↑↓]spring [r]restart cascade [e]restart easing ", tstyle(:text_dim))],
        right=[Span("[q]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

# ── Panel: Easing Gallery ────────────────────────────────────────────

function _draw_easing_gallery(m::AnimDemoModel, buf::Buffer, area::Rect)
    blk = Block(title="easing gallery",
                border_style=tstyle(:border),
                title_style=tstyle(:text_dim))
    inner = render(blk, area, buf)
    inner.width < 10 && return

    label_w = 15
    bar_w = inner.width - label_w - 1

    for (i, tw) in enumerate(m.easing_tweens)
        y = inner.y + i - 1
        y > bottom(inner) && break
        i > length(EASING_NAMES) && break

        name = EASING_NAMES[i][1]
        # Label
        set_string!(buf, inner.x, y, rpad(name, label_w), tstyle(:text_dim))

        # Bar
        v = value(tw)
        filled = round(Int, v * bar_w)
        bar_x = inner.x + label_w
        for cx in 0:(bar_w - 1)
            ch = cx < filled ? '█' : '·'
            s = cx < filled ? tstyle(:primary) : tstyle(:text_dim, dim=true)
            set_char!(buf, bar_x + cx, y, ch, s)
        end

        # Value indicator
        marker_x = bar_x + clamp(filled, 0, bar_w - 1)
        set_char!(buf, marker_x, y, '▸', tstyle(:accent, bold=true))
    end
end

# ── Panel: Spring ────────────────────────────────────────────────────

function _draw_spring_panel(m::AnimDemoModel, buf::Buffer, area::Rect)
    blk = Block(title="spring physics",
                border_style=tstyle(:border),
                title_style=tstyle(:text_dim))
    inner = render(blk, area, buf)
    inner.width < 10 || inner.height < 4 && return

    # Info line
    tv = m.spring_targets[m.spring_target_idx]
    info = "target=$(round(tv; digits=2)) value=$(round(m.spring.value; digits=3)) vel=$(round(m.spring.velocity; digits=2))"
    set_string!(buf, inner.x, inner.y, info, tstyle(:text_dim))

    # Sparkline of spring trail
    spark_area = Rect(inner.x, inner.y + 2, inner.width, max(1, inner.height - 4))
    if !isempty(m.spring_trail) && spark_area.height >= 1
        render(Sparkline(m.spring_trail; style=tstyle(:accent)), spark_area, buf)
    end

    # Current value as a horizontal bar at bottom
    bar_y = bottom(inner)
    bar_y > inner.y + 2 || return
    bar_w = inner.width
    pos = round(Int, clamp(m.spring.value, 0.0, 1.0) * (bar_w - 1))
    target_pos = round(Int, clamp(tv, 0.0, 1.0) * (bar_w - 1))

    for cx in 0:(bar_w - 1)
        ch = cx == target_pos ? '┃' : '─'
        s = cx == target_pos ? tstyle(:warning) : tstyle(:text_dim, dim=true)
        set_char!(buf, inner.x + cx, bar_y, ch, s)
    end
    # Spring position marker
    set_char!(buf, inner.x + pos, bar_y, '●', tstyle(:primary, bold=true))
end

# ── Panel: Cascade Timeline ──────────────────────────────────────────

function _draw_cascade(m::AnimDemoModel, buf::Buffer, area::Rect)
    blk = Block(title="staggered timeline",
                border_style=tstyle(:border),
                title_style=tstyle(:text_dim))
    inner = render(blk, area, buf)
    inner.width < 10 && return

    tl = m.cascade_timeline
    tl === nothing && return

    frame_info = "frame $(tl.frame)"
    if done(tl)
        frame_info *= " [done — press r]"
    end
    set_string!(buf, inner.x, inner.y, frame_info, tstyle(:text_dim))

    bar_w = inner.width - 6
    for (i, tw) in enumerate(m.cascade_tweens)
        y = inner.y + i
        y > bottom(inner) && break

        v = value(tw)
        filled = round(Int, v * bar_w)
        label = lpad(string(i), 2) * "│ "
        set_string!(buf, inner.x, y, label, tstyle(:text_dim))

        bar_x = inner.x + 4
        # Draw the bar with gradient effect
        for cx in 0:(bar_w - 1)
            if cx < filled
                # Color intensity based on position in cascade
                brightness = 0.3 + 0.7 * (cx / bar_w)
                ch = BARS_H[clamp(round(Int, brightness * 8), 1, 8)]
                set_char!(buf, bar_x + cx, y, ch, tstyle(:primary))
            else
                set_char!(buf, bar_x + cx, y, '·', tstyle(:text_dim, dim=true))
            end
        end

        # Value text
        pct = round(Int, v * 100)
        if inner.x + 4 + bar_w + 3 <= right(inner)
            set_string!(buf, bar_x + bar_w + 1, y, "$(pct)%",
                        pct >= 100 ? tstyle(:success) : tstyle(:text_dim))
        end
    end
end

# ── Panel: Looping Tweens ────────────────────────────────────────────

function _draw_loops(m::AnimDemoModel, buf::Buffer, area::Rect)
    blk = Block(title="loop modes",
                border_style=tstyle(:border),
                title_style=tstyle(:text_dim))
    inner = render(blk, area, buf)
    inner.width < 10 || inner.height < 4 && return

    items = [
        ("loop/cubic  ", m.loop_tween,    :primary),
        ("pp/in-out   ", m.pp_tween,      :secondary),
        ("pp/bounce   ", m.bounce_tween,  :accent),
        ("pp/elastic  ", m.elastic_tween, :warning),
    ]

    label_w = 14
    bar_w = inner.width - label_w - 1
    # Give each item 2 rows: bar + trail dots
    for (i, (name, tw, color)) in enumerate(items)
        y = inner.y + (i - 1) * 2
        y > bottom(inner) && break

        set_string!(buf, inner.x, y, name, tstyle(:text_dim))

        v = value(tw)
        filled = round(Int, v * bar_w)
        bar_x = inner.x + label_w

        for cx in 0:(bar_w - 1)
            if cx < filled
                set_char!(buf, bar_x + cx, y, '█', tstyle(color))
            else
                set_char!(buf, bar_x + cx, y, '░', tstyle(:text_dim, dim=true))
            end
        end

        # Bouncing dot on next line
        dot_y = y + 1
        dot_y > bottom(inner) && continue
        dot_x = bar_x + clamp(round(Int, v * (bar_w - 1)), 0, bar_w - 1)
        set_char!(buf, dot_x, dot_y, '◆', tstyle(color, bold=true))
    end
end

function anim_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(AnimDemoModel(); fps=30)
end
