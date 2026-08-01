# ═══════════════════════════════════════════════════════════════════════
# Unicode Demo ── zero-width combining marks, wide characters, graphemes
#
# Exercises combining marks, precomposed glyphs, CJK wide characters,
# and mixed-width text across multiple widget types to verify correct
# rendering.
#
#   [1-4] switch panels   [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

const _UNICODE_TEST_LINES = [
    "n  = normal ASCII",
    "ṅ  = precomposed dot above",
    "n̈  = combining diaeresis (U+0308)",
    "é  = precomposed acute",
    "e\u0301  = combining acute (U+0301)",
    "a\u0307\u0308 = stacked combining marks",
    "你好 = CJK wide characters",
    "A你B = mixed wide + narrow",
    "café = trailing composed é",
    "cafe\u0301 = trailing combining é",
]

# Alignment test: these lines should have = aligned vertically
const _UNICODE_ALIGN_LINES = [
    "--- n  = 2 ---",
    "--- ṅ  = 2 ---",
    "--- n̈  = 2 ---",
    "--- é  = 2 ---",
    "--- e\u0301  = 2 ---",
    "--- 你 = 2 ---",
]

@kwdef mutable struct UnicodeDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    tab::Int = 1
end

should_quit(m::UnicodeDemoModel) = m.quit

function update!(m::UnicodeDemoModel, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, '1') => (m.tab = 1)
        (:char, '2') => (m.tab = 2)
        (:char, '3') => (m.tab = 3)
        (:char, '4') => (m.tab = 4)
        _ => nothing
    end
end

function _unicode_view_paragraph(inner::Rect, buf::Buffer)
    halves = split_layout(Layout(Horizontal, [Percent(50), Fill()]), inner)

    # Left: no-wrap alignment test
    blk_l = Block(title="Alignment (no wrap)",
                  border_style=tstyle(:border), title_style=tstyle(:title))
    inner_l = render(blk_l, halves[1], buf)
    p1 = Paragraph(join(_UNICODE_ALIGN_LINES, "\n"))
    render(p1, inner_l, buf)

    # Right: all test strings
    blk_r = Block(title="Grapheme catalogue",
                  border_style=tstyle(:border), title_style=tstyle(:title))
    inner_r = render(blk_r, halves[2], buf)
    p2 = Paragraph(join(_UNICODE_TEST_LINES, "\n"))
    render(p2, inner_r, buf)
end

function _unicode_view_wrap(inner::Rect, buf::Buffer)
    blk = Block(title="Word wrap with combining marks + wide chars",
                border_style=tstyle(:border), title_style=tstyle(:title))
    inner2 = render(blk, inner, buf)

    text = "The café serves naïve customers. Letters like ṅ and n̈ " *
           "should not break alignment. CJK characters 你好世界 " *
           "take two columns each. Stacked marks a\u0307\u0308 stay attached " *
           "through line wraps. Mixed text: A你B café n̈ 你好 — " *
           "all should render correctly regardless of where the " *
           "line break falls. Résumé, Ångström, Zürich, São Paulo."
    p = Paragraph(text; wrap=word_wrap)
    render(p, inner2, buf)
end

function _unicode_view_table(inner::Rect, buf::Buffer)
    rows = [[l] for l in _UNICODE_TEST_LINES]
    header = ["Unicode test strings"]
    tbl = Table(header, rows;
                widths=[50],
                block=Block(title="Table",
                            border_style=tstyle(:border),
                            title_style=tstyle(:title)))
    render(tbl, inner, buf)
end

function _unicode_view_aligned(inner::Rect, buf::Buffer)
    chunks = split_layout(Layout(Vertical, [Ratio(1,3), Ratio(1,3), Ratio(1,3)]), inner)
    text = "--- ṅ = n̈ = 你好 ---"
    for (i, al) in enumerate([align_left, align_center, align_right])
        label = ["Left aligned", "Center aligned", "Right aligned"][i]
        p = Paragraph(text; alignment=al,
            block=Block(title=label,
                        border_style=tstyle(:border),
                        title_style=tstyle(:title)))
        render(p, chunks[i], buf)
    end
end

function view(m::UnicodeDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), area)
    length(rows) < 3 && return
    tab_area, main_area, footer_area = rows[1], rows[2], rows[3]

    # Tabs
    tabs = TabBar(["Paragraph", "Word Wrap", "Table", "Alignment"];
                  active=m.tab, focused=true)
    render(tabs, tab_area, buf)

    # Status bar with unicode in it
    render(StatusBar(
        left=[Span("  [1-4] switch tab  ", tstyle(:text_dim))],
        right=[Span("ṅ n̈ 你好 café  ", tstyle(:text_dim)),
               Span("[q] quit ", tstyle(:text_dim))],
    ), footer_area, buf)

    # Content
    if m.tab == 1
        _unicode_view_paragraph(main_area, buf)
    elseif m.tab == 2
        _unicode_view_wrap(main_area, buf)
    elseif m.tab == 3
        _unicode_view_table(main_area, buf)
    elseif m.tab == 4
        _unicode_view_aligned(main_area, buf)
    end
end

function unicode_demo()
    run_demo(UnicodeDemoModel(); fps=30)
end
