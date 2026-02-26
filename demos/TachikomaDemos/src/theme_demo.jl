# ═══════════════════════════════════════════════════════════════════════
# Demo ── boot sequence + palette + visual bling
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct DemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    theme_idx::Int = 1
end

should_quit(m::DemoModel) = m.quit

function update!(m::DemoModel, evt::KeyEvent)
    n = length(ALL_THEMES)
    if evt.key == :up || (evt.key == :char && evt.char == 'k')
        m.theme_idx = m.theme_idx > 1 ? m.theme_idx - 1 : n
        set_theme!(ALL_THEMES[m.theme_idx])
    elseif evt.key == :down || (evt.key == :char && evt.char == 'j')
        m.theme_idx = m.theme_idx < n ? m.theme_idx + 1 : 1
        set_theme!(ALL_THEMES[m.theme_idx])
    elseif evt.key == :char && evt.char == 'q'
        m.quit = true
    elseif evt.key == :escape
        m.quit = true
    end
end

function view(m::DemoModel, f::Frame)
    m.tick += 1
    th = theme()
    buf = f.buffer

    # Layout: main content | theme list sidebar
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(18)]), f.area)
    length(cols) < 2 && return
    main_area = cols[1]
    sidebar_area = cols[2]

    # ── outer frame ──
    block = Block(
        title="tachikoma v0.1.0",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    content = render(block, main_area, buf)
    x = content.x + 1
    y = content.y

    # ── spinner + status ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, x, y, SPINNER_BRAILLE[si], tstyle(:accent))
    x2 = set_string!(buf, x + 2, y,
                      "$(th.name) theme", tstyle(:text_dim))
    set_string!(buf, x2 + 1, y,
        "$(DOT) $(f.area.width)×$(f.area.height)",
        tstyle(:text_dim, dim=true))

    # ── palette ──
    y += 2
    set_string!(buf, x, y, "palette", tstyle(:text, bold=true))
    y += 1
    palette = [
        ("primary",   :primary),   ("secondary", :secondary),
        ("accent",    :accent),    ("border",    :border),
        ("success",   :success),   ("warning",   :warning),
        ("error",     :error),     ("text",      :text),
    ]
    col_w = 18
    for (i, (label, field)) in enumerate(palette)
        c = getfield(th, field)
        cx = x + ((i - 1) % 2) * col_w
        cy = y + (i - 1) ÷ 2
        set_string!(buf, cx, cy, "▓▓", Style(fg=c))
        set_string!(buf, cx + 3, cy, label, tstyle(:text_dim))
    end
    y += (length(palette) + 1) ÷ 2

    # ── signal bars (vertical block chars) ──
    y += 1
    set_string!(buf, x, y, "signal", tstyle(:text, bold=true))
    y += 1
    bars = [0.8, 0.6, 0.9, 0.3, 0.7, 0.5, 0.85, 0.4,
            0.65, 0.75, 0.2, 0.95]
    for (i, v) in enumerate(bars)
        phase = sin(m.tick / 15.0 + i * 0.7)
        val = clamp(v + phase * 0.15, 0.0, 1.0)
        nn = round(Int, val * 8)
        ch = nn > 0 ? BARS_V[min(nn, 8)] : ' '
        c = if animations_enabled()
            color_wave(m.tick, i, (th.primary, th.accent, th.secondary);
                       speed=0.03, spread=0.4)
        else
            th.primary
        end
        set_char!(buf, x + i - 1, y, ch, Style(fg=c, bold=true))
    end

    # ── gradient blocks ──
    y += 2
    set_string!(buf, x, y, "density",
                tstyle(:text, bold=true))
    y += 1
    for (i, ch) in enumerate(BLOCKS)
        for j in 1:5
            set_char!(buf, x + (i - 1) * 5 + j - 1, y,
                      ch, tstyle(:primary))
        end
    end

    # ── box style showcase ──
    y += 2
    set_string!(buf, x, y, "borders",
                tstyle(:text, bold=true))
    y += 1
    boxes = [
        ("rounded", BOX_ROUNDED), ("heavy", BOX_HEAVY),
        ("double", BOX_DOUBLE),   ("plain", BOX_PLAIN),
    ]
    bx = x
    for (label, box) in boxes
        w = max(length(label) + 4, 10)
        if bx + w <= right(content)
            mini = Block(title="$label",
                         box=box,
                         border_style=tstyle(:border),
                         title_style=tstyle(:text_dim))
            render(mini, Rect(bx, y, w, 3), buf)
            bx += w + 1
        end
    end

    # ── scanline separator ──
    y += 4
    if y <= bottom(content)
        for cx in x:(right(content) - 1)
            set_char!(buf, cx, y, SCANLINE,
                      tstyle(:border, dim=true))
        end
    end

    # ── instructions ──
    iy = bottom(content)
    if iy > y
        set_string!(buf, x, iy,
            "[↑↓/jk]theme [q/Esc]quit",
            tstyle(:text_dim, dim=true))
    end

    # ── theme selector sidebar ──
    sb_block = Block(title="Themes",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    sb_inner = render(sb_block, sidebar_area, buf)

    for (i, t) in enumerate(ALL_THEMES)
        sy = sb_inner.y + i - 1
        sy > bottom(sb_inner) && break
        if i == m.theme_idx
            sel_c = if animations_enabled()
                p = pulse(m.tick; period=80, lo=0.0, hi=0.2)
                color_lerp(th.accent, th.primary, p)
            else
                th.accent
            end
            for cx in sb_inner.x:right(sb_inner)
                set_char!(buf, cx, sy, ' ', Style(bg=sel_c))
            end
            label = string(MARKER, ' ', t.name)
            set_string!(buf, sb_inner.x, sy, label,
                        Style(fg=Color256(0), bg=sel_c, bold=true);
                        max_x=right(sb_inner))
        else
            set_string!(buf, sb_inner.x + 2, sy, t.name,
                        tstyle(:text_dim); max_x=right(sb_inner))
        end
    end
end

function demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    model = DemoModel()
    # Sync theme_idx with current theme
    for (i, t) in enumerate(ALL_THEMES)
        if t === THEME[]
            model.theme_idx = i
            break
        end
    end
    app(model)
end
