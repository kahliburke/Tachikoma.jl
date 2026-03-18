# ═══════════════════════════════════════════════════════════════════════
# ScrollPane ── scrollable content pane with auto-follow, reverse mode,
#               mouse wheel, keyboard nav, and optional render callback
# ═══════════════════════════════════════════════════════════════════════

mutable struct ScrollPane
    content::Union{Vector{String}, Vector{Vector{Span}}, Tuple{Function,Int}}
    offset::Int              # 0-based scroll offset
    following::Bool          # auto-scroll to newest content
    reverse::Bool            # newest-at-top mode
    block::Union{Block, Nothing}
    show_scrollbar::Bool
    scrollbar_style::Style
    scrollbar_thumb_style::Style
    text_style::Style        # default style for String lines
    last_total::Int          # cached line count for auto-follow detection
    last_area::Rect          # cached content area for mouse hit testing
    tick::Union{Int, Nothing}
    word_wrap::Bool          # wrap long lines at content width
    ansi::Bool               # parse ANSI escape sequences in String lines
    _visual_total::Int       # cached visual line count (after word wrap)
    _sb_state::ScrollbarState
end

# ── Constructors ─────────────────────────────────────────────────────

function ScrollPane(lines::Vector{String};
    offset=0, following=true, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
    word_wrap=false,
    ansi=ansi_enabled(),
)
    ScrollPane(lines, offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick, word_wrap, ansi, 0, ScrollbarState())
end

function ScrollPane(lines::Vector{Vector{Span}};
    offset=0, following=true, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
    word_wrap=false,
    ansi=false,
)
    ScrollPane(lines, offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick, word_wrap, ansi, 0, ScrollbarState())
end

function ScrollPane(render_fn::Function, total_lines::Int;
    offset=0, following=false, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
    word_wrap=false,
    ansi=false,
)
    ScrollPane((render_fn, total_lines), offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick, word_wrap, ansi, 0, ScrollbarState())
end

focusable(::ScrollPane) = true

# ── Content helpers ──────────────────────────────────────────────────

function _total_lines(sp::ScrollPane)
    # When word wrap is active, use the cached visual total (set during render)
    if sp.word_wrap && sp._visual_total > 0
        return sp._visual_total
    end
    c = sp.content
    c isa Vector{String}        && return length(c)
    c isa Vector{Vector{Span}}  && return length(c)
    c isa Tuple{Function,Int}   && return c[2]
    return 0
end

_max_offset(sp::ScrollPane, visible_h::Int) = max(0, _total_lines(sp) - visible_h)

function _clamp_offset!(sp::ScrollPane, visible_h::Int)
    sp.offset = clamp(sp.offset, 0, _max_offset(sp, visible_h))
end

# ── Auto-follow logic ────────────────────────────────────────────────

function _update_follow!(sp::ScrollPane, visible_h::Int)
    total = _total_lines(sp)
    # Detect growth → snap to end if following
    if sp.following && total > sp.last_total
        if sp.reverse
            sp.offset = 0
        else
            sp.offset = _max_offset(sp, visible_h)
        end
    end
    sp.last_total = total
    _clamp_offset!(sp, visible_h)
end

function _check_reattach!(sp::ScrollPane, visible_h::Int)
    if sp.reverse
        sp.following = (sp.offset == 0)
    else
        sp.following = (sp.offset >= _max_offset(sp, visible_h))
    end
end

# ── Mutation API ─────────────────────────────────────────────────────

function push_line!(sp::ScrollPane, line::String)
    c = sp.content
    if c isa Vector{String}
        push!(c, line)
    end
    nothing
end

function push_line!(sp::ScrollPane, line::Vector{Span})
    c = sp.content
    if c isa Vector{Vector{Span}}
        push!(c, line)
    end
    nothing
end

function set_content!(sp::ScrollPane, lines::Vector{String})
    sp.content = lines
    nothing
end

function set_content!(sp::ScrollPane, lines::Vector{Vector{Span}})
    sp.content = lines
    nothing
end

function set_total!(sp::ScrollPane, n::Int)
    c = sp.content
    if c isa Tuple{Function,Int}
        sp.content = (c[1], n)
    end
    nothing
end

# ── Render ───────────────────────────────────────────────────────────

function render(sp::ScrollPane, rect::Rect, buf::Buffer)
    # 1. Block border
    content_area = if sp.block !== nothing
        render(sp.block, rect, buf)
    else
        rect
    end
    (content_area.width < 1 || content_area.height < 1) && return

    visible_h = content_area.height

    # 2. Word-wrap path: expand logical lines → visual lines, then render
    c = sp.content
    if sp.word_wrap && !(c isa Tuple{Function,Int}) && content_area.width > 1
        # When ANSI is enabled on String content, convert to Span vectors first
        # so that _wrap_content measures display width correctly (not raw bytes).
        wrap_c = if sp.ansi && c isa Vector{String}
            [contains(l, '\e') ? parse_ansi(l) : [Span(l, sp.text_style)] for l in c]
        else
            c
        end
        visual = _wrap_content(wrap_c, content_area.width)
        total = length(visual)

        needs_scrollbar = sp.show_scrollbar && total > visible_h
        text_area = if needs_scrollbar && content_area.width > 1
            Rect(content_area.x, content_area.y,
                 content_area.width - 1, content_area.height)
        else
            content_area
        end

        # Re-wrap with final text width if scrollbar appeared
        if needs_scrollbar
            visual = _wrap_content(wrap_c, text_area.width)
            total = length(visual)
        end

        sp._visual_total = total
        _update_follow_total!(sp, total, visible_h)
        sp.last_area = content_area
        _render_visual_lines!(sp, visual, text_area, buf, visible_h, total)

        if needs_scrollbar && content_area.width > 1
            sb_rect = Rect(right(content_area), content_area.y,
                           1, content_area.height)
            sp._sb_state.rect = sb_rect
            sb = Scrollbar(total, visible_h, sp.offset;
                           style=sp.scrollbar_style,
                           thumb_style=sp.scrollbar_thumb_style)
            render(sb, sb_rect, buf)
        else
            sp._sb_state.rect = Rect()
        end
        return
    end

    # Non-wrap path (original)
    total = _total_lines(sp)

    needs_scrollbar = sp.show_scrollbar && total > visible_h
    text_area = if needs_scrollbar && content_area.width > 1
        Rect(content_area.x, content_area.y,
             content_area.width - 1, content_area.height)
    else
        content_area
    end

    # 3. Auto-follow + clamp
    _update_follow!(sp, visible_h)

    # 4. Cache area for mouse hit testing
    sp.last_area = content_area

    # 5. Render content
    if c isa Tuple{Function,Int}
        c[1](buf, text_area, sp.offset)
    else
        _render_lines!(sp, c, text_area, buf, visible_h)
    end

    # 6. Scrollbar
    if needs_scrollbar && content_area.width > 1
        sb_rect = Rect(right(content_area), content_area.y,
                       1, content_area.height)
        sp._sb_state.rect = sb_rect
        sb = Scrollbar(total, visible_h, sp.offset;
                       style=sp.scrollbar_style,
                       thumb_style=sp.scrollbar_thumb_style)
        render(sb, sb_rect, buf)
    else
        sp._sb_state.rect = Rect()
    end
end

# ── Word-wrap helpers ───────────────────────────────────────────────

"""Like _update_follow! but takes an explicit total (for wrapped line count)."""
function _update_follow_total!(sp::ScrollPane, total::Int, visible_h::Int)
    max_off = max(0, total - visible_h)
    if sp.following && total > sp.last_total
        sp.offset = sp.reverse ? 0 : max_off
    end
    sp.last_total = total
    sp.offset = clamp(sp.offset, 0, max_off)
end

"""Wrap String content into visual lines."""
function _wrap_content(lines::Vector{String}, width::Int)
    visual = String[]
    for line in lines
        if textwidth(line) <= width
            push!(visual, line)
        else
            _char_wrap_string!(visual, line, width)
        end
    end
    visual
end

"""Wrap Span content into visual lines."""
function _wrap_content(lines::Vector{Vector{Span}}, width::Int)
    visual = Vector{Span}[]
    for spans in lines
        total_w = sum(textwidth(s.content) for s in spans; init=0)
        if total_w <= width
            push!(visual, spans)
        else
            _char_wrap_spans!(visual, spans, width)
        end
    end
    visual
end

"""Char-wrap a plain string into visual lines."""
function _char_wrap_string!(out::Vector{String}, s::String, width::Int)
    pos = 1
    while pos <= lastindex(s)
        # Find how many chars fit in `width` columns
        col = 0
        end_pos = pos
        while end_pos <= lastindex(s)
            cw = textwidth(s[end_pos])
            col + cw > width && break
            col += cw
            end_pos = nextind(s, end_pos)
        end
        push!(out, SubString(s, pos, prevind(s, end_pos)))
        pos = end_pos
    end
end

"""Char-wrap a Span vector into visual lines."""
function _char_wrap_spans!(out::Vector{Vector{Span}}, spans::Vector{Span}, width::Int)
    current_line = Span[]
    col = 0
    for span in spans
        text = span.content
        style = span.style
        pos = 1
        while pos <= lastindex(text)
            remaining = width - col
            remaining <= 0 && begin
                push!(out, current_line)
                current_line = Span[]
                col = 0
                remaining = width
            end
            # Consume up to `remaining` columns from this span
            end_pos = pos
            chunk_w = 0
            while end_pos <= lastindex(text)
                cw = textwidth(text[end_pos])
                chunk_w + cw > remaining && break
                chunk_w += cw
                end_pos = nextind(text, end_pos)
            end
            if end_pos > pos
                push!(current_line, Span(SubString(text, pos, prevind(text, end_pos)), style))
                col += chunk_w
                pos = end_pos
            elseif col == 0
                # Single char wider than width — force it
                push!(current_line, Span(string(text[pos]), style))
                pos = nextind(text, pos)
                push!(out, current_line)
                current_line = Span[]
                col = 0
            else
                # No room — wrap to next line
                push!(out, current_line)
                current_line = Span[]
                col = 0
            end
        end
    end
    isempty(current_line) || push!(out, current_line)
end

"""Render pre-wrapped visual String lines."""
function _render_visual_lines!(sp::ScrollPane, lines::Vector{String},
                               text_area::Rect, buf::Buffer, visible_h::Int, total::Int)
    n = length(lines)
    for i in 1:visible_h
        idx = sp.reverse ? n - sp.offset - i + 1 : sp.offset + i
        (idx < 1 || idx > n) && continue
        y = text_area.y + i - 1
        set_string!(buf, text_area.x, y, lines[idx], sp.text_style;
                    max_x=right(text_area))
    end
end

"""Render pre-wrapped visual Span lines."""
function _render_visual_lines!(sp::ScrollPane, lines::Vector{Vector{Span}},
                               text_area::Rect, buf::Buffer, visible_h::Int, total::Int)
    n = length(lines)
    for i in 1:visible_h
        idx = sp.reverse ? n - sp.offset - i + 1 : sp.offset + i
        (idx < 1 || idx > n) && continue
        y = text_area.y + i - 1
        col = text_area.x
        for span in lines[idx]
            col > right(text_area) && break
            col = set_string!(buf, col, y, span.content, span.style;
                              max_x=right(text_area))
        end
    end
end

function _render_lines!(sp::ScrollPane, lines::Vector{String},
                        text_area::Rect, buf::Buffer, visible_h::Int)
    n = length(lines)
    for i in 1:visible_h
        idx = if sp.reverse
            n - sp.offset - i + 1
        else
            sp.offset + i
        end
        (idx < 1 || idx > n) && continue
        y = text_area.y + i - 1
        line = lines[idx]
        if sp.ansi && contains(line, '\e')
            col = text_area.x
            for span in parse_ansi(line)
                col > right(text_area) && break
                col = set_string!(buf, col, y, span.content, span.style;
                                  max_x=right(text_area))
            end
        else
            set_string!(buf, text_area.x, y, line, sp.text_style;
                        max_x=right(text_area))
        end
    end
end

function _render_lines!(sp::ScrollPane, lines::Vector{Vector{Span}},
                        text_area::Rect, buf::Buffer, visible_h::Int)
    n = length(lines)
    for i in 1:visible_h
        idx = if sp.reverse
            n - sp.offset - i + 1
        else
            sp.offset + i
        end
        (idx < 1 || idx > n) && continue
        y = text_area.y + i - 1
        col = text_area.x
        for span in lines[idx]
            col > right(text_area) && break
            col = set_string!(buf, col, y, span.content, span.style;
                              max_x=right(text_area))
        end
    end
end

# ── Key handling ─────────────────────────────────────────────────────

function handle_key!(sp::ScrollPane, evt)
    visible_h = max(1, sp.last_area.height)
    handled = true

    if evt.key == :up
        sp.offset -= 1
        sp.following = false
    elseif evt.key == :down
        sp.offset += 1
        sp.following = false
    elseif evt.key == :pageup
        sp.offset -= visible_h
        sp.following = false
    elseif evt.key == :pagedown
        sp.offset += visible_h
        sp.following = false
    elseif evt.key == :home
        if sp.reverse
            sp.offset = _max_offset(sp, visible_h)
        else
            sp.offset = 0
        end
        sp.following = false
    elseif evt.key == :end_key
        if sp.reverse
            sp.offset = 0
        else
            sp.offset = _max_offset(sp, visible_h)
        end
        sp.following = false
    else
        handled = false
    end

    if handled
        _clamp_offset!(sp, visible_h)
        _check_reattach!(sp, visible_h)
    end
    handled
end

# ── Mouse handling ───────────────────────────────────────────────────

function handle_mouse!(sp::ScrollPane, evt::MouseEvent)
    visible_h = max(1, sp.last_area.height)
    total = _total_lines(sp)
    max_off = _max_offset(sp, visible_h)

    # ── Scrollbar click/drag ──
    was_dragging = sp._sb_state.dragging
    frac = handle_scrollbar_mouse!(sp._sb_state, evt)
    if frac !== nothing
        new_offset = round(Int, frac * max_off)
        if new_offset != sp.offset
            sp.offset = new_offset
            sp.following = false
            _clamp_offset!(sp, visible_h)
            _check_reattach!(sp, visible_h)
        end
        return true
    end
    # Drag release: handle_scrollbar_mouse! cleared dragging, returned nothing
    was_dragging && !sp._sb_state.dragging && return true

    # ── Scroll wheel anywhere in the pane ──
    Base.contains(sp.last_area, evt.x, evt.y) || return false
    new_offset = list_scroll(evt, sp.offset, total, visible_h)
    if new_offset != sp.offset
        sp.offset = new_offset
        sp.following = false
        _clamp_offset!(sp, visible_h)
        _check_reattach!(sp, visible_h)
        return true
    end
    false
end
