# ═══════════════════════════════════════════════════════════════════════
# TestBackend ── lightweight test harness for widget rendering
# ═══════════════════════════════════════════════════════════════════════

struct TestBackend
    width::Int
    height::Int
    buf::Buffer
end

function TestBackend(width::Int, height::Int)
    rect = Rect(1, 1, width, height)
    TestBackend(width, height, Buffer(rect))
end

function render_widget!(tb::TestBackend, widget; rect::Union{Rect,Nothing}=nothing)
    reset!(tb.buf)
    r = rect !== nothing ? rect : Rect(1, 1, tb.width, tb.height)
    render(widget, r, tb.buf)
    tb
end

function char_at(tb::TestBackend, x::Int, y::Int)
    in_bounds(tb.buf, x, y) || return ' '
    tb.buf.content[buf_index(tb.buf, x, y)].char
end

function style_at(tb::TestBackend, x::Int, y::Int)
    in_bounds(tb.buf, x, y) || return RESET
    tb.buf.content[buf_index(tb.buf, x, y)].style
end

function row_text(tb::TestBackend, y::Int)
    (y < 1 || y > tb.height) && return ""
    String([char_at(tb, x, y) for x in 1:tb.width])
end

function find_text(tb::TestBackend, text::AbstractString)
    for y in 1:tb.height
        row = row_text(tb, y)
        pos = findfirst(text, row)
        pos !== nothing && return (x=first(pos), y=y)
    end
    nothing
end
