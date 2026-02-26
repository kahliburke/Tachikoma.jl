# ═══════════════════════════════════════════════════════════════════════
# Span ── styled text fragment
# ═══════════════════════════════════════════════════════════════════════

struct Span
    content::String
    style::Style
end

Span(s::AbstractString) = Span(s, tstyle(:text))

# ═══════════════════════════════════════════════════════════════════════
# Paragraph ── renders styled text with wrapping + alignment
# ═══════════════════════════════════════════════════════════════════════

@enum WrapMode no_wrap word_wrap char_wrap
@enum Alignment align_left align_center align_right

mutable struct Paragraph
    spans::Vector{Span}
    block::Union{Block, Nothing}
    wrap::WrapMode
    alignment::Alignment
    scroll_offset::Int
    tick::Union{Int, Nothing}
    show_scrollbar::Bool
end

"""
    Paragraph(text; wrap=no_wrap, alignment=align_left, block=nothing, ...)

Styled text block with configurable wrapping (`no_wrap`, `word_wrap`, `char_wrap`)
and alignment (`align_left`, `align_center`, `align_right`).
Also accepts `Vector{Span}` for mixed-style text.
"""
function Paragraph(text::AbstractString;
                   block=nothing, style=tstyle(:text),
                   wrap::WrapMode=no_wrap, alignment::Alignment=align_left,
                   scroll_offset::Int=0, tick=nothing, show_scrollbar::Bool=true)
    Paragraph([Span(text, style)], block, wrap, alignment, scroll_offset, tick, show_scrollbar)
end

function Paragraph(spans::Vector{Span}; block=nothing,
                   wrap::WrapMode=no_wrap, alignment::Alignment=align_left,
                   scroll_offset::Int=0, tick=nothing, show_scrollbar::Bool=true)
    Paragraph(spans, block, wrap, alignment, scroll_offset, tick, show_scrollbar)
end

# ── Layout pass: break spans into visual lines ──

function _layout_lines(spans::Vector{Span}, width::Int, wrap::WrapMode)
    width < 1 && return Vector{Vector{Tuple{String,Style}}}()

    lines = Vector{Tuple{String,Style}}[]
    current_line = Tuple{String,Style}[]
    col = 0

    function flush_line!()
        push!(lines, current_line)
        current_line = Tuple{String,Style}[]
        col = 0
    end

    function add_text!(text::AbstractString, style::Style)
        isempty(text) && return
        push!(current_line, (String(text), style))
        col += length(text)
    end

    for span in spans
        parts = Base.split(span.content, '\n'; keepempty=true)
        for (pi, part) in enumerate(parts)
            if pi > 1
                flush_line!()
            end

            # Convert to Vector{Char} for safe integer indexing (avoids
            # StringIndexError with multi-byte Unicode characters like ✓, ✗).
            chars = collect(part)
            nchars = length(chars)

            if wrap == no_wrap
                avail = width - col
                avail <= 0 && continue
                text = nchars > avail ? String(chars[1:avail]) : part
                add_text!(text, span.style)

            elseif wrap == char_wrap
                ci = 1
                while ci <= nchars
                    avail = width - col
                    if avail <= 0
                        flush_line!()
                        avail = width
                    end
                    take = min(nchars - ci + 1, avail)
                    add_text!(String(chars[ci:ci+take-1]), span.style)
                    ci += take
                end

            else  # word_wrap
                i = 1
                while i <= nchars
                    # Collect word (non-space chars)
                    j = i
                    while j <= nchars && chars[j] != ' '
                        j += 1
                    end
                    word = String(chars[i:j-1])
                    # Collect trailing spaces
                    k = j
                    while k <= nchars && chars[k] == ' '
                        k += 1
                    end
                    spaces = String(chars[j:k-1])
                    wlen = j - i  # character count of word

                    if wlen == 0
                        if col + length(spaces) <= width
                            add_text!(spaces, span.style)
                        end
                        i = k
                        continue
                    end

                    # Wrap if word doesn't fit
                    if col + wlen > width && col > 0
                        flush_line!()
                    end

                    # Char-break words wider than the line
                    if wlen > width
                        wchars = chars[i:j-1]
                        wi = 1
                        while wi <= wlen
                            avail = width - col
                            if avail <= 0
                                flush_line!()
                                avail = width
                            end
                            take = min(wlen - wi + 1, avail)
                            add_text!(String(wchars[wi:wi+take-1]), span.style)
                            wi += take
                        end
                    else
                        add_text!(word, span.style)
                    end

                    # Trailing spaces if they fit
                    if !isempty(spaces) && col + length(spaces) <= width
                        add_text!(spaces, span.style)
                    end

                    i = k
                end
            end
        end
    end

    if !isempty(current_line) || isempty(lines)
        push!(lines, current_line)
    end

    lines
end

# ── Render ──

function render(p::Paragraph, rect::Rect, buf::Buffer)
    content_area = if p.block !== nothing
        render(p.block, rect, buf)
    else
        rect
    end

    (content_area.width < 1 || content_area.height < 1) && return

    if p.wrap == no_wrap && p.alignment == align_left && p.scroll_offset == 0
        # Fast path: original behavior (no scrollbar needed — no scrolling)
        col = content_area.x
        row = content_area.y
        for span in p.spans
            for ch in span.content
                if ch == '\n'
                    col = content_area.x
                    row += 1
                    row > bottom(content_area) && return
                    continue
                end
                if col <= right(content_area)
                    set_char!(buf, col, row, ch, span.style)
                    col += 1
                end
            end
        end
        return
    end

    # Layout pass (use full width first to determine if scrollbar is needed)
    lines = _layout_lines(p.spans, content_area.width, p.wrap)
    total_lines = length(lines)
    needs_scrollbar = p.show_scrollbar && total_lines > content_area.height

    # Re-layout with reduced width if scrollbar takes a column
    text_area = content_area
    if needs_scrollbar && content_area.width > 1
        text_area = Rect(content_area.x, content_area.y,
                         content_area.width - 1, content_area.height)
        lines = _layout_lines(p.spans, text_area.width, p.wrap)
        total_lines = length(lines)
    end

    # Record visible height for key handling
    _PARA_VISIBLE_H[] = content_area.height

    # Apply scroll offset and clamp
    max_offset = max(0, total_lines - content_area.height)
    p.scroll_offset = clamp(p.scroll_offset, 0, max_offset)
    offset = p.scroll_offset

    # Render pass
    for row_idx in 1:content_area.height
        line_idx = offset + row_idx
        line_idx > total_lines && break
        line = lines[line_idx]

        # Compute line width for alignment
        line_width = sum(length(t) for (t, _) in line; init=0)

        x_offset = if p.alignment == align_center
            max(0, (text_area.width - line_width) ÷ 2)
        elseif p.alignment == align_right
            max(0, text_area.width - line_width)
        else
            0
        end

        col = text_area.x + x_offset
        y = text_area.y + row_idx - 1
        for (text, style) in line
            for ch in text
                col > right(text_area) && break
                set_char!(buf, col, y, ch, style)
                col += 1
            end
        end
    end

    # Scrollbar
    if needs_scrollbar && content_area.width > 1
        sb_rect = Rect(right(content_area), content_area.y,
                       1, content_area.height)
        sb = Scrollbar(total_lines, content_area.height, offset)
        render(sb, sb_rect, buf)
    end
end

# Total layout line count (for scroll bounds)
# Pass the content width (width inside block borders).
# If the paragraph has a scrollbar, the caller should account for the
# 1-column reduction — or call this twice (once to check, once with reduced width).
function paragraph_line_count(p::Paragraph, width::Int)
    length(_layout_lines(p.spans, width, p.wrap))
end

# ── Scrollable paragraph (keyboard + mouse) ──

focusable(p::Paragraph) = p.wrap != no_wrap

# Store last known visible height for key handling
const _PARA_VISIBLE_H = Ref(10)

function handle_key!(p::Paragraph, evt::KeyEvent)::Bool
    p.wrap == no_wrap && return false
    vis = _PARA_VISIBLE_H[]
    if evt.key == :up
        p.scroll_offset = max(0, p.scroll_offset - 1)
        return true
    elseif evt.key == :down
        p.scroll_offset += 1
        return true
    elseif evt.key == :pageup
        p.scroll_offset = max(0, p.scroll_offset - vis)
        return true
    elseif evt.key == :pagedown
        p.scroll_offset += vis
        return true
    elseif evt.key == :home
        p.scroll_offset = 0
        return true
    elseif evt.key == :end_key
        p.scroll_offset = typemax(Int) ÷ 2  # will be clamped at render
        return true
    end
    false
end

function handle_mouse!(p::Paragraph, evt::MouseEvent)::Bool
    p.wrap == no_wrap && return false
    if evt.button == mouse_scroll_up && evt.action == mouse_press
        p.scroll_offset = max(0, p.scroll_offset - 1)
        return true
    elseif evt.button == mouse_scroll_down && evt.action == mouse_press
        p.scroll_offset += 1
        return true
    end
    false
end
