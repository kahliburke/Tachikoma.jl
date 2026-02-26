# ═══════════════════════════════════════════════════════════════════════
# Markdown Demo ── three-mode MarkdownPane showcase
#
# Mode 1: README viewer with rich sample document
# Mode 2: Live editor with split-pane preview
# Mode 3: Style preset picker
#
# Ctrl+M / F1-F3: switch modes   Tab: switch focus (mode 2)
# 1-4: style presets (mode 3)    Esc: quit
# ═══════════════════════════════════════════════════════════════════════

const _MD_SAMPLE = """
# Tachikoma.jl

A **terminal UI framework** for Julia — build rich, interactive applications
that run in any terminal.

## Features

Tachikoma provides a comprehensive widget toolkit:

- **Layout engine** with constraints: `Fixed`, `Fill`, `Percent`, `Min`, `Max`
- **Styled text** with 256-color and RGB support
- **Animation system** with tweens, springs, and timelines
- **Interactive widgets**: TextInput, TextArea, CodeEditor, DataTable
- **Canvas drawing** with braille, block, and sixel backends

## Quick Start

```julia
using Tachikoma

@kwdef mutable struct MyModel <: Model
    quit::Bool = false
    count::Int = 0
end

should_quit(m::MyModel) = m.quit

function update!(m::MyModel, evt::KeyEvent)
    evt.key == :escape && (m.quit = true)
    evt.key == :char && evt.char == '+' && (m.count += 1)
end

function view(m::MyModel, f::Frame)
    render(Paragraph("Count: \$(m.count)"), f.area, f.buffer)
end

app(MyModel())
```

## Widget Gallery

### ScrollPane

> Scrollable content with auto-follow, reverse mode, mouse wheel support,
> and keyboard navigation. Handles both plain strings and styled `Span` lines.

### DataTable

Sortable, scrollable tables with column alignment and detail views.

| Column  | Type     | Notes         |
|---------|----------|---------------|
| Name    | String   | Primary key   |
| Score   | Float64  | Sortable      |
| Status  | Symbol   | Color-coded   |

### CodeEditor

Full-featured code editor with *syntax highlighting*, auto-indentation,
and `vi`-style modal editing.

---

## Links

Visit the [documentation](https://github.com/example/Tachikoma.jl) for more.

![Tachikoma Logo](logo.png)

---

*Built with Julia and a love for terminals.*
"""

# ── Style presets ───────────────────────────────────────────────────

struct _MDStylePreset
    name::String
    h1::Style
    h2::Style
    h3::Style
    bold::Style
    emph::Style
    code::Style
    link::Style
    quote_s::Style
    text::Style
    hr::Style
end

const _MD_PRESETS = [
    _MDStylePreset("Default",
        Style(fg=SKY.c400, bold=true),
        Style(fg=SKY.c500, bold=true),
        Style(fg=SKY.c600, bold=true),
        Style(bold=true),
        Style(dim=true),
        Style(fg=GREEN.c400, bg=SLATE.c800),
        Style(fg=BLUE.c400),
        Style(fg=SLATE.c400),
        Style(fg=SLATE.c200),
        Style(fg=SLATE.c600)),
    _MDStylePreset("Warm",
        Style(fg=AMBER.c400, bold=true),
        Style(fg=ORANGE.c400, bold=true),
        Style(fg=ORANGE.c500, bold=true),
        Style(bold=true),
        Style(dim=true),
        Style(fg=YELLOW.c400, bg=STONE.c800),
        Style(fg=ROSE.c400),
        Style(fg=STONE.c400),
        Style(fg=STONE.c200),
        Style(fg=STONE.c600)),
    _MDStylePreset("Ocean",
        Style(fg=TEAL.c400, bold=true),
        Style(fg=CYAN.c400, bold=true),
        Style(fg=CYAN.c500, bold=true),
        Style(bold=true),
        Style(dim=true),
        Style(fg=EMERALD.c400, bg=SLATE.c800),
        Style(fg=CYAN.c300),
        Style(fg=SLATE.c400),
        Style(fg=SLATE.c200),
        Style(fg=SLATE.c600)),
    _MDStylePreset("Monochrome",
        Style(fg=SLATE.c200, bold=true),
        Style(fg=SLATE.c300, bold=true),
        Style(fg=SLATE.c400, bold=true),
        Style(bold=true),
        Style(dim=true),
        Style(fg=SLATE.c300, bg=SLATE.c800),
        Style(fg=SLATE.c300),
        Style(fg=SLATE.c500),
        Style(fg=SLATE.c300),
        Style(fg=SLATE.c600)),
]

function _apply_preset(source::String, preset::_MDStylePreset; width=80, block=nothing, tick=nothing)
    MarkdownPane(source;
        width, block, tick,
        h1_style=preset.h1, h2_style=preset.h2, h3_style=preset.h3,
        bold_style=preset.bold, emph_style=preset.emph,
        code_style=preset.code, link_style=preset.link,
        quote_style=preset.quote_s, text_style=preset.text,
        hr_style=preset.hr)
end

# ── Model ───────────────────────────────────────────────────────────

@kwdef mutable struct MarkdownDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    mode::Int = 1                          # 1=readme, 2=editor, 3=styles

    # Mode 1: README viewer
    md_pane::MarkdownPane = MarkdownPane(_MD_SAMPLE;
        block=Block(title="Markdown Viewer",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        tick=0)

    # Mode 2: Live editor
    editor::TextArea = TextArea(;
        text="# Live Preview\n\nType **markdown** here and see it rendered on the right.\n\n- Item one\n- Item two\n\n> A blockquote\n\n`inline code`",
        focused=true, tick=0)
    preview_pane::MarkdownPane = MarkdownPane(
        "# Live Preview\n\nType **markdown** here and see it rendered on the right.\n\n- Item one\n- Item two\n\n> A blockquote\n\n`inline code`";
        block=Block(title="Preview",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        tick=0)
    focus::Int = 1                         # 1=editor, 2=preview

    # Mode 3: Style picker
    style_idx::Int = 1
    style_pane::MarkdownPane = _apply_preset(_MD_SAMPLE, _MD_PRESETS[1];
        block=Block(title="Style: Default",
                    border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        tick=0)
end

should_quit(m::MarkdownDemoModel) = m.quit

# ── Update ──────────────────────────────────────────────────────────

function update!(m::MarkdownDemoModel, evt::KeyEvent)
    evt.key == :escape && (m.quit = true; return)

    # Mode switching
    handled = @match evt.key begin
        :ctrl_m || :f1 => (m.mode = 1; true)
        :f2            => (m.mode = 2; true)
        :f3            => (m.mode = 3; true)
        _              => false
    end
    handled && return

    # Mode-specific handling
    @match m.mode begin
        1 => _update_readme!(m, evt)
        2 => _update_editor!(m, evt)
        _ => _update_styles!(m, evt)
    end
end

function _update_readme!(m::MarkdownDemoModel, evt::KeyEvent)
    handle_key!(m.md_pane, evt)
end

function _update_editor!(m::MarkdownDemoModel, evt::KeyEvent)
    if evt.key == :tab
        m.focus = m.focus == 1 ? 2 : 1
        m.editor.focused = (m.focus == 1)
        return
    end

    if m.focus == 1
        handle_key!(m.editor, evt)
    else
        handle_key!(m.preview_pane, evt)
    end
end

function _update_styles!(m::MarkdownDemoModel, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:char, c) where '1' <= c <= '4' => begin
            idx = Int(c) - Int('0')
            if idx != m.style_idx
                m.style_idx = idx
                preset = _MD_PRESETS[idx]
                m.style_pane = _apply_preset(_MD_SAMPLE, preset;
                    block=Block(title="Style: $(preset.name)",
                                border_style=tstyle(:border),
                                title_style=tstyle(:title)),
                    tick=m.tick)
            end
        end
        _ => handle_key!(m.style_pane, evt)
    end
end

function update!(m::MarkdownDemoModel, evt::MouseEvent)
    @match m.mode begin
        1 => handle_mouse!(m.md_pane, evt)
        2 => handle_mouse!(m.preview_pane, evt)
        _ => handle_mouse!(m.style_pane, evt)
    end
end

# ── View ────────────────────────────────────────────────────────────

function view(m::MarkdownDemoModel, f::Frame)
    m.tick += 1
    m.md_pane.pane.tick = m.tick
    m.editor.tick = m.tick
    m.preview_pane.pane.tick = m.tick
    m.style_pane.pane.tick = m.tick

    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    body_area   = rows[2]
    footer_area = rows[3]

    # Header: mode tabs
    _render_mode_tabs!(buf, header_area, m.mode, m.tick)

    # Body: mode-specific content
    @match m.mode begin
        1 => _render_readme!(m, body_area, buf)
        2 => _render_editor_mode!(m, body_area, buf)
        _ => _render_style_mode!(m, body_area, buf)
    end

    # Footer
    footer_text = @match m.mode begin
        1 => "  [↑↓/PgUp/PgDn]scroll [Ctrl+M/F1-F3]mode [Esc]quit "
        2 => "  [Tab]focus [↑↓]scroll/edit [Ctrl+M/F1-F3]mode [Esc]quit "
        _ => "  [1-4]preset [↑↓/PgUp/PgDn]scroll [Ctrl+M/F1-F3]mode [Esc]quit "
    end
    render(StatusBar(
        left=[Span(footer_text, tstyle(:text_dim))],
        right=[Span("mode $(m.mode) ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function _render_mode_tabs!(buf, area, active, tick)
    modes = ["F1 README", "F2 Editor", "F3 Styles"]
    col = area.x + 1
    for (i, label) in enumerate(modes)
        style = if i == active
            tstyle(:accent, bold=true)
        else
            tstyle(:text_dim)
        end
        marker = i == active ? "▸ " : "  "
        text = marker * label * "  "
        col = set_string!(buf, col, area.y, text, style; max_x=right(area))
    end
end

function _render_readme!(m::MarkdownDemoModel, area, buf)
    render(m.md_pane, area, buf)
end

function _render_editor_mode!(m::MarkdownDemoModel, area, buf)
    cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), area)
    length(cols) < 2 && return

    # Editor (left)
    editor_block = Block(
        title=m.focus == 1 ? "● Editor" : "○ Editor",
        border_style=m.focus == 1 ? tstyle(:accent) : tstyle(:border),
        title_style=m.focus == 1 ? tstyle(:accent, bold=true) : tstyle(:title))
    editor_inner = render(editor_block, cols[1], buf)
    render(m.editor, editor_inner, buf)

    # Preview (right) — sync content if changed
    editor_text = text(m.editor)
    if editor_text != m.preview_pane.source
        set_markdown!(m.preview_pane, editor_text)
    end

    m.preview_pane.pane.block = Block(
        title=m.focus == 2 ? "● Preview" : "○ Preview",
        border_style=m.focus == 2 ? tstyle(:accent) : tstyle(:border),
        title_style=m.focus == 2 ? tstyle(:accent, bold=true) : tstyle(:title))
    render(m.preview_pane, cols[2], buf)
end

function _render_style_mode!(m::MarkdownDemoModel, area, buf)
    cols = split_layout(Layout(Horizontal, [Fixed(22), Fill()]), area)
    length(cols) < 2 && return

    # Sidebar: preset list
    sidebar_block = Block(
        title="Presets",
        border_style=tstyle(:border),
        title_style=tstyle(:title))
    sidebar_inner = render(sidebar_block, cols[1], buf)

    for (i, preset) in enumerate(_MD_PRESETS)
        y = sidebar_inner.y + i - 1
        y > bottom(sidebar_inner) && break
        marker = i == m.style_idx ? "▸ " : "  "
        label = "$(i). $(preset.name)"
        style = i == m.style_idx ? tstyle(:accent, bold=true) : tstyle(:text)
        set_string!(buf, sidebar_inner.x, y, marker * label, style;
                    max_x=right(sidebar_inner))
    end

    # Main pane
    render(m.style_pane, cols[2], buf)
end

# ── Entry point ─────────────────────────────────────────────────────

function markdown_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    enable_markdown()
    model = MarkdownDemoModel()
    app(model; fps=30)
end
