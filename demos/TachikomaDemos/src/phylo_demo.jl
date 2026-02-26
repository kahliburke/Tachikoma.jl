# ═══════════════════════════════════════════════════════════════════════
# Phylo Tree Demo ── interactive radial phylogenetic tree background
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct PhyloDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    preset_idx::Int = 1
    paused::Bool = false
    tree::PhyloTree = generate_phylo_tree(PHYLO_PRESETS[1])
end

should_quit(m::PhyloDemoModel) = m.quit

function update!(m::PhyloDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'p' && (m.paused = !m.paused)
        for c in ('1', '2', '3', '4')
            if evt.char == c
                idx = Int(c) - Int('0')
                if idx != m.preset_idx
                    m.preset_idx = idx
                    m.tree = generate_phylo_tree(PHYLO_PRESETS[idx])
                end
            end
        end
    end
    evt.key == :escape && (m.quit = true)
end

function view(m::PhyloDemoModel, f::Frame)
    if !m.paused
        m.tick += 1
    end
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    canvas_area = rows[2]
    footer = rows[3]

    preset = PHYLO_PRESETS[m.preset_idx]
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    info = "$(preset.name) $(DOT) branches=$(length(m.tree.branches)) $(DOT) depth=$(preset.max_depth)"
    set_string!(buf, header.x + 2, header.y, info, tstyle(:primary, bold=true))

    render_phylo_tree!(buf, canvas_area, m.tick, m.tree, preset)

    render(StatusBar(
        left=[Span("  [1-4]preset [p]pause ", tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function phylo_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(PhyloDemoModel(); fps=30)
end
