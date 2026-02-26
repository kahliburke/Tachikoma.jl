# ═══════════════════════════════════════════════════════════════════════
# MarkdownPane ── convenience widget wrapping ScrollPane + markdown_to_spans
#
# Parses CommonMark markdown into styled Span lines and displays them
# in a ScrollPane. Automatically reflows when the render width changes.
# ═══════════════════════════════════════════════════════════════════════

mutable struct MarkdownPane
    source::String                    # raw markdown text
    pane::ScrollPane                  # underlying scrollable pane
    last_width::Int                   # width used for last parse (for responsive reflow)
    h1_style::Style
    h2_style::Style
    h3_style::Style
    bold_style::Style
    emph_style::Style
    code_style::Style
    link_style::Style
    quote_style::Style
    text_style::Style
    hr_style::Style
end

"""
    MarkdownPane(source; width=80, block=nothing, show_scrollbar=true, ...)

Scrollable markdown viewer. Parses `source` via CommonMark.jl (requires the
markdown extension — call `enable_markdown()` first) and displays styled output
in a `ScrollPane`. Automatically reflows text when the render width changes.

# Style keyword arguments
`h1_style`, `h2_style`, `h3_style`, `bold_style`, `emph_style`, `code_style`,
`link_style`, `quote_style`, `text_style`, `hr_style`.
"""
function MarkdownPane(source::AbstractString;
    width::Int=80,
    block::Union{Block, Nothing}=nothing,
    show_scrollbar::Bool=true,
    following::Bool=false,
    tick::Union{Int, Nothing}=nothing,
    h1_style::Style=Style(fg=SKY.c400, bold=true),
    h2_style::Style=Style(fg=SKY.c500, bold=true),
    h3_style::Style=Style(fg=SKY.c600, bold=true),
    bold_style::Style=Style(bold=true),
    emph_style::Style=Style(dim=true),
    code_style::Style=Style(fg=GREEN.c400, bg=SLATE.c800),
    link_style::Style=Style(fg=BLUE.c400),
    quote_style::Style=Style(fg=SLATE.c400),
    text_style::Style=Style(fg=SLATE.c200),
    hr_style::Style=Style(fg=SLATE.c600),
)
    lines = _md_parse(string(source), width;
        h1_style, h2_style, h3_style, bold_style, emph_style,
        code_style, link_style, quote_style, text_style, hr_style)
    pane = ScrollPane(lines; block, show_scrollbar, following, tick)
    MarkdownPane(string(source), pane, width,
        h1_style, h2_style, h3_style, bold_style, emph_style,
        code_style, link_style, quote_style, text_style, hr_style)
end

# ── Internal parse helper ───────────────────────────────────────────

function _md_parse(source::String, width::Int;
    h1_style::Style=Style(fg=SKY.c400, bold=true),
    h2_style::Style=Style(fg=SKY.c500, bold=true),
    h3_style::Style=Style(fg=SKY.c600, bold=true),
    bold_style::Style=Style(bold=true),
    emph_style::Style=Style(dim=true),
    code_style::Style=Style(fg=GREEN.c400, bg=SLATE.c800),
    link_style::Style=Style(fg=BLUE.c400),
    quote_style::Style=Style(fg=SLATE.c400),
    text_style::Style=Style(fg=SLATE.c200),
    hr_style::Style=Style(fg=SLATE.c600),
)
    if !markdown_extension_loaded()
        return Vector{Span}[
            [Span("CommonMark.jl not loaded", Style(fg=AMBER.c400, bold=true))],
            [Span("Call enable_markdown() or `using CommonMark`", Style(fg=SLATE.c400))],
            Span[],
            [s for s in _plain_lines(source, text_style)]...,
        ]
    end
    Base.invokelatest(markdown_to_spans, source, width;
        h1_style, h2_style, h3_style, bold_style, emph_style,
        code_style, link_style, quote_style, text_style, hr_style)
end

function _plain_lines(source::String, style::Style)
    lines = Vector{Span}[]
    for line in Base.split(source, '\n')
        push!(lines, [Span(string(line), style)])
    end
    lines
end

# ── Public API ──────────────────────────────────────────────────────

"""
    set_markdown!(mp::MarkdownPane, source; width=mp.last_width)

Update the markdown content and re-parse. Optionally specify a new width.
"""
function set_markdown!(mp::MarkdownPane, source::AbstractString;
                       width::Int=mp.last_width)
    mp.source = string(source)
    mp.last_width = width
    lines = _md_parse(mp.source, width;
        h1_style=mp.h1_style, h2_style=mp.h2_style, h3_style=mp.h3_style,
        bold_style=mp.bold_style, emph_style=mp.emph_style,
        code_style=mp.code_style, link_style=mp.link_style,
        quote_style=mp.quote_style, text_style=mp.text_style,
        hr_style=mp.hr_style)
    set_content!(mp.pane, lines)
    nothing
end

# ── Widget protocol ─────────────────────────────────────────────────

focusable(::MarkdownPane) = true

function handle_key!(mp::MarkdownPane, evt)
    handle_key!(mp.pane, evt)
end

function handle_mouse!(mp::MarkdownPane, evt::MouseEvent)
    handle_mouse!(mp.pane, evt)
end

# ── Render with responsive reflow ───────────────────────────────────

function render(mp::MarkdownPane, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    # Compute content width (rect minus borders minus scrollbar)
    border_w = mp.pane.block !== nothing ? 2 : 0
    scrollbar_w = mp.pane.show_scrollbar ? 1 : 0
    content_width = max(1, rect.width - border_w - scrollbar_w)

    # Reflow if width changed
    if content_width != mp.last_width
        set_markdown!(mp, mp.source; width=content_width)
    end

    render(mp.pane, rect, buf)
end
