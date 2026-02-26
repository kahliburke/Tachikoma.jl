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
end

# ── Constructors ─────────────────────────────────────────────────────

function ScrollPane(lines::Vector{String};
    offset=0, following=true, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
)
    ScrollPane(lines, offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick)
end

function ScrollPane(lines::Vector{Vector{Span}};
    offset=0, following=true, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
)
    ScrollPane(lines, offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick)
end

function ScrollPane(render_fn::Function, total_lines::Int;
    offset=0, following=false, reverse=false, block=nothing,
    show_scrollbar=true,
    scrollbar_style=tstyle(:text_dim, dim=true),
    scrollbar_thumb_style=tstyle(:primary),
    text_style=tstyle(:text),
    tick=nothing,
)
    ScrollPane((render_fn, total_lines), offset, following, reverse, block,
               show_scrollbar, scrollbar_style, scrollbar_thumb_style,
               text_style, 0, Rect(), tick)
end

focusable(::ScrollPane) = true

# ── Content helpers ──────────────────────────────────────────────────

function _total_lines(sp::ScrollPane)
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
    total = _total_lines(sp)

    # 2. Reserve scrollbar column
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
    c = sp.content
    if c isa Tuple{Function,Int}
        c[1](buf, text_area, sp.offset)
    else
        _render_lines!(sp, c, text_area, buf, visible_h)
    end

    # 6. Scrollbar
    if needs_scrollbar && content_area.width > 1
        sb_rect = Rect(right(content_area), content_area.y,
                       1, content_area.height)
        sb = Scrollbar(total, visible_h, sp.offset;
                       style=sp.scrollbar_style,
                       thumb_style=sp.scrollbar_thumb_style)
        render(sb, sb_rect, buf)
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
        set_string!(buf, text_area.x, y, lines[idx], sp.text_style;
                    max_x=right(text_area))
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
    Base.contains(sp.last_area, evt.x, evt.y) || return false
    visible_h = max(1, sp.last_area.height)
    total = _total_lines(sp)
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
