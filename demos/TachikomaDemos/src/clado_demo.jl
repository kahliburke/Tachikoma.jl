# ═══════════════════════════════════════════════════════════════════════
# Cladogram Demo ── interactive radial fan-layout phylogenetic tree
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct CladoDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    preset_idx::Int = 1
    paused::Bool = false
    tree::CladoTree = generate_clado_tree(CLADO_PRESETS[1])
end

should_quit(m::CladoDemoModel) = m.quit

function update!(m::CladoDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        for c in ('1', '2', '3', '4', '5')
            if evt.char == c
                idx = Int(c) - Int('0')
                if idx != m.preset_idx && idx <= length(CLADO_PRESETS)
                    m.preset_idx = idx
                    m.tree = generate_clado_tree(CLADO_PRESETS[idx])
                end
            end
        end
    end
    evt.key == :escape && (m.quit = true)
end

function view(m::CladoDemoModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    canvas_area = rows[2]
    footer = rows[3]

    preset = CLADO_PRESETS[m.preset_idx]
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    info = "$(preset.name) $(DOT) branches=$(length(m.tree.branches)) $(DOT) depth=$(preset.max_depth)"
    set_string!(buf, header.x + 2, header.y, info, tstyle(:primary, bold=true))

    render_clado_tree!(buf, canvas_area, m.tick, m.tree, preset)

    render(StatusBar(
        left=[Span("  [1-5]preset [p]pause ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function clado_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(CladoDemoModel(); fps=30)
end
