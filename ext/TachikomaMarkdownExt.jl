module TachikomaMarkdownExt

using Tachikoma
using CommonMark

# ── Public entry point ───────────────────────────────────────────────

function Tachikoma.markdown_to_spans(md::AbstractString, width::Int;
                                      h1_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SKY.c400, bold=true),
                                      h2_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SKY.c500, bold=true),
                                      h3_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SKY.c600, bold=true),
                                      bold_style::Tachikoma.Style = Tachikoma.Style(bold=true),
                                      emph_style::Tachikoma.Style = Tachikoma.Style(dim=true),
                                      code_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.GREEN.c400,
                                                                                     bg=Tachikoma.SLATE.c800),
                                      link_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.BLUE.c400),
                                      quote_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SLATE.c400),
                                      text_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SLATE.c200),
                                      hr_style::Tachikoma.Style = Tachikoma.Style(fg=Tachikoma.SLATE.c600))
    width < 1 && return [Tachikoma.Span[]]
    parser = CommonMark.Parser()
    CommonMark.enable!(parser, CommonMark.TableRule())
    if isdefined(CommonMark, :TaskListRule)
        CommonMark.enable!(parser, CommonMark.TaskListRule())
    end
    ast = parser(md)
    ctx = WalkContext(width, h1_style, h2_style, h3_style,
                      bold_style, emph_style, code_style, link_style,
                      quote_style, text_style, hr_style)
    _walk_blocks!(ctx, ast)
    # Remove trailing blank line if present
    while !isempty(ctx.lines) && _is_blank_line(ctx.lines[end])
        pop!(ctx.lines)
    end
    isempty(ctx.lines) ? [Tachikoma.Span[]] : ctx.lines
end

# ── Context ──────────────────────────────────────────────────────────

struct WalkContext
    width::Int
    h1::Tachikoma.Style
    h2::Tachikoma.Style
    h3::Tachikoma.Style
    bold::Tachikoma.Style
    emph::Tachikoma.Style
    code::Tachikoma.Style
    link::Tachikoma.Style
    quote_s::Tachikoma.Style
    text::Tachikoma.Style
    hr::Tachikoma.Style
    lines::Vector{Vector{Tachikoma.Span}}
    prefix::Vector{String}         # stack of line prefixes (blockquote nesting)
    prefix_style::Vector{Tachikoma.Style}
end

function WalkContext(width, h1, h2, h3, bold, emph, code, link, quote_s, text, hr)
    WalkContext(width, h1, h2, h3, bold, emph, code, link, quote_s, text, hr,
                Vector{Tachikoma.Span}[], String[], Tachikoma.Style[])
end

_current_prefix(ctx::WalkContext) = join(ctx.prefix)
_current_prefix_len(ctx::WalkContext) = sum(length, ctx.prefix; init=0)

function _push_line!(ctx::WalkContext, spans::Vector{Tachikoma.Span})
    pfx = _current_prefix(ctx)
    if !isempty(pfx)
        pstyle = isempty(ctx.prefix_style) ? ctx.text : ctx.prefix_style[end]
        pushfirst!(spans, Tachikoma.Span(pfx, pstyle))
    end
    push!(ctx.lines, spans)
end

function _push_blank!(ctx::WalkContext)
    _push_line!(ctx, Tachikoma.Span[])
end

_is_blank_line(spans::Vector{Tachikoma.Span}) =
    isempty(spans) || all(s -> isempty(strip(s.content)), spans)

# ── Block-level walker ───────────────────────────────────────────────

function _walk_blocks!(ctx::WalkContext, node)
    child = node.first_child
    while !CommonMark.isnull(child)
        _handle_block!(ctx, child)
        child = child.nxt
    end
end

function _handle_block!(ctx::WalkContext, node)
    t = node.t
    if t isa CommonMark.Heading
        _handle_heading!(ctx, node)
    elseif t isa CommonMark.Paragraph
        _handle_paragraph!(ctx, node)
    elseif t isa CommonMark.CodeBlock
        _handle_codeblock!(ctx, node)
    elseif t isa CommonMark.BlockQuote
        _handle_blockquote!(ctx, node)
    elseif t isa CommonMark.List
        _handle_list!(ctx, node)
    elseif t isa CommonMark.ThematicBreak
        _handle_hr!(ctx)
    elseif t isa CommonMark.Document
        _walk_blocks!(ctx, node)
    else
        # Unknown block — try recursing into children
        _walk_blocks!(ctx, node)
    end
end

# ── Heading ──────────────────────────────────────────────────────────

function _handle_heading!(ctx::WalkContext, node)
    level = node.t.level
    style = level == 1 ? ctx.h1 : level == 2 ? ctx.h2 : ctx.h3
    prefix = "#"^min(level, 3) * " "
    spans = _collect_inlines(ctx, node, style)
    pushfirst!(spans, Tachikoma.Span(prefix, style))
    _push_line!(ctx, spans)
    _push_blank!(ctx)
end

# ── Paragraph ────────────────────────────────────────────────────────

function _handle_paragraph!(ctx::WalkContext, node)
    spans = _collect_inlines(ctx, node, ctx.text)
    avail = ctx.width - _current_prefix_len(ctx)
    wrapped = _wrap_spans(spans, avail, ctx.text)
    for line in wrapped
        _push_line!(ctx, line)
    end
    _push_blank!(ctx)
end

# ── CodeBlock ────────────────────────────────────────────────────────

# Syntax highlighting for fenced code blocks.
# Uses tokenizers from Tachikoma core (codeeditor.jl + tokenizers.jl).
# Supported: Julia, Python, Shell, TypeScript/JavaScript.
# Other languages fall back to uniform code_style.

function _tokens_to_spans(chars::Vector{Char}, tokens::Vector{Tachikoma.Token},
                           code_bg::Tachikoma.AbstractColor)
    isempty(tokens) && return [Tachikoma.Span(String(chars), Tachikoma.Style(bg=code_bg))]
    spans = Tachikoma.Span[]
    pos = 1
    for tok in tokens
        if tok.start > pos
            push!(spans, Tachikoma.Span(String(chars[pos:tok.start-1]),
                                        Tachikoma.Style(bg=code_bg)))
        end
        ts = Tachikoma.token_style(tok.kind)
        merged = Tachikoma.Style(fg=ts.fg, bg=code_bg,
                                  bold=ts.bold, dim=ts.dim,
                                  italic=ts.italic, underline=ts.underline)
        push!(spans, Tachikoma.Span(String(chars[tok.start:tok.stop]), merged))
        pos = tok.stop + 1
    end
    if pos <= length(chars)
        push!(spans, Tachikoma.Span(String(chars[pos:end]),
                                    Tachikoma.Style(bg=code_bg)))
    end
    spans
end

function _highlight_code_line(line::AbstractString, code_bg::Tachikoma.AbstractColor,
                               lang::AbstractString)
    chars = collect(Char, line)
    tokens = Tachikoma.tokenize_code(lang, chars)
    tokens === nothing && return nothing
    _tokens_to_spans(chars, tokens, code_bg)
end

function _handle_codeblock!(ctx::WalkContext, node)
    info = node.t.info
    lang = lowercase(strip(string(info)))

    if !isempty(info)
        _push_line!(ctx, [Tachikoma.Span("```$info", ctx.code)])
    else
        _push_line!(ctx, [Tachikoma.Span("```", ctx.code)])
    end
    code_text = node.literal
    code_text === nothing && (code_text = "")
    code_bg = ctx.code.bg
    for line in split(rstrip(code_text), '\n')
        spans = _highlight_code_line(line, code_bg, lang)
        if spans !== nothing
            _push_line!(ctx, spans)
        else
            _push_line!(ctx, [Tachikoma.Span(string(line), ctx.code)])
        end
    end
    _push_line!(ctx, [Tachikoma.Span("```", ctx.code)])
    _push_blank!(ctx)
end

# ── BlockQuote ───────────────────────────────────────────────────────

function _handle_blockquote!(ctx::WalkContext, node)
    push!(ctx.prefix, "│ ")
    push!(ctx.prefix_style, ctx.quote_s)
    _walk_blocks!(ctx, node)
    pop!(ctx.prefix)
    pop!(ctx.prefix_style)
end

# ── List ─────────────────────────────────────────────────────────────

function _handle_list!(ctx::WalkContext, node)
    is_ordered = node.t.list_data.type === :ordered
    start_num = node.t.list_data.start
    idx = start_num
    child = node.first_child
    while !CommonMark.isnull(child)
        if child.t isa CommonMark.Item || _is_task_item(child.t)
            _handle_list_item!(ctx, child, is_ordered, idx)
            idx += 1
        end
        child = child.nxt
    end
end

_is_task_item(t) = isdefined(CommonMark, :TaskItem) && t isa CommonMark.TaskItem

function _handle_list_item!(ctx::WalkContext, node, is_ordered::Bool, idx::Int)
    bullet = if _is_task_item(node.t)
        hasproperty(node.t, :checked) && node.t.checked ? "  [x] " : "  [ ] "
    elseif is_ordered
        "  $idx. "
    else
        "  * "
    end
    # First child paragraph gets the bullet prefix inline
    first_block = true
    child = node.first_child
    while !CommonMark.isnull(child)
        if first_block && child.t isa CommonMark.Paragraph
            spans = _collect_inlines(ctx, child, ctx.text)
            pushfirst!(spans, Tachikoma.Span(bullet, ctx.text))
            avail = ctx.width - _current_prefix_len(ctx)
            wrapped = _wrap_spans(spans, avail, ctx.text)
            for line in wrapped
                _push_line!(ctx, line)
            end
            first_block = false
        else
            if first_block
                _push_line!(ctx, [Tachikoma.Span(bullet, ctx.text)])
                first_block = false
            end
            # Indent continuation
            indent = " "^length(bullet)
            push!(ctx.prefix, indent)
            push!(ctx.prefix_style, ctx.text)
            _handle_block!(ctx, child)
            pop!(ctx.prefix)
            pop!(ctx.prefix_style)
        end
        child = child.nxt
    end
end

# ── Thematic break ───────────────────────────────────────────────────

function _handle_hr!(ctx::WalkContext)
    avail = ctx.width - _current_prefix_len(ctx)
    _push_line!(ctx, [Tachikoma.Span("─"^max(1, avail), ctx.hr)])
    _push_blank!(ctx)
end

# ── Inline collector ─────────────────────────────────────────────────

function _collect_inlines(ctx::WalkContext, node, base_style::Tachikoma.Style)
    spans = Tachikoma.Span[]
    style_stack = Tachikoma.Style[base_style]
    for (n, entering) in node
        n === node && continue  # skip the node itself
        _t = n.t
        if _t isa CommonMark.Text
            push!(spans, Tachikoma.Span(n.literal, style_stack[end]))
        elseif _t isa CommonMark.Code
            push!(spans, Tachikoma.Span(n.literal, ctx.code))
        elseif _t isa CommonMark.Strong
            if entering
                push!(style_stack, ctx.bold)
            else
                length(style_stack) > 1 && pop!(style_stack)
            end
        elseif _t isa CommonMark.Emph
            if entering
                push!(style_stack, ctx.emph)
            else
                length(style_stack) > 1 && pop!(style_stack)
            end
        elseif _t isa CommonMark.Link
            if entering
                push!(style_stack, ctx.link)
            else
                length(style_stack) > 1 && pop!(style_stack)
            end
        elseif _t isa CommonMark.Image
            if entering
                push!(spans, Tachikoma.Span("[Image: ", ctx.text))
            else
                push!(spans, Tachikoma.Span("]", ctx.text))
            end
        elseif _t isa CommonMark.SoftBreak
            push!(spans, Tachikoma.Span(" ", style_stack[end]))
        elseif _t isa CommonMark.LineBreak
            # Hard break — handled by wrapping; insert a space
            push!(spans, Tachikoma.Span(" ", style_stack[end]))
        end
    end
    spans
end

# ── Word wrapper ─────────────────────────────────────────────────────

function _wrap_spans(spans::Vector{Tachikoma.Span}, width::Int,
                     space_style::Tachikoma.Style=Tachikoma.Style())
    width < 1 && return [spans]
    lines = Vector{Tachikoma.Span}[]
    current = Tachikoma.Span[]
    col = 0

    for span in spans
        words = split(span.content, ' '; keepempty=false)
        if isempty(words)
            # Span was whitespace-only — treat as a single space
            if col > 0
                push!(current, Tachikoma.Span(" ", space_style))
                col += 1
            end
            continue
        end
        for (i, word) in enumerate(words)
            w = length(word)
            need_space = col > 0
            if need_space && col + 1 + w > width
                # Wrap
                push!(lines, current)
                current = Tachikoma.Span[]
                col = 0
                need_space = false
            end
            if need_space
                push!(current, Tachikoma.Span(" ", space_style))
                col += 1
            end
            # If a single word exceeds width, emit it anyway (don't infinite loop)
            push!(current, Tachikoma.Span(string(word), span.style))
            col += w
        end
    end
    !isempty(current) && push!(lines, current)
    isempty(lines) ? [Tachikoma.Span[]] : lines
end

end # module
