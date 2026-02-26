"""
    render(widget, area::Rect, buf::Buffer)

Render a widget into the given buffer region. This is the core widget protocol —
implement this method via multiple dispatch to create new widgets.
"""
function render end

"""
    intrinsic_size(widget) → (width, height) or nothing

Return the natural size of a widget in terminal cells, or `nothing` if the
widget fills whatever space it is given.
"""
intrinsic_size(::Any) = nothing

"""
    focusable(widget) → Bool

Return whether a widget can receive keyboard focus. Defaults to `false`.
"""
focusable(::Any) = false

"""
    value(widget)

Return the current user-facing value of a widget.

Returns: `String` (TextInput/TextArea/CodeEditor), `Bool` (Checkbox),
`Int` (RadioGroup/SelectableList/DataTable), `String` (DropDown),
`Dict{String,Any}` (Form).
"""
function value end

"""
    set_value!(widget, v)

Programmatically set a widget's value.
"""
function set_value! end

"""
    valid(widget) → Bool

Return whether a widget's current value passes validation.
Defaults to `true` for widgets without validators.
"""
valid(::Any) = true

# ── Widget includes ──────────────────────────────────────────────────

include("block.jl")
include("paragraph.jl")
include("gauge.jl")
include("sparkline.jl")
include("table.jl")
include("list.jl")
include("tabs.jl")
include("statusbar.jl")
include("textinput.jl")
include("modal.jl")
include("canvas.jl")
include("barchart.jl")
include("calendar.jl")
include("scrollbar.jl")
include("scrollpane.jl")
include("bigtext.jl")
include("treeview.jl")
include("progresslist.jl")
include("separator.jl")
include("checkbox.jl")
include("button.jl")
include("dropdown.jl")
include("textarea.jl")
include("codeeditor.jl")
include("tokenizers.jl")
include("chart.jl")
include("datatable.jl")
include("markdownpane.jl")

# NOTE: form.jl depends on FocusRing, included after its definition below

# ── FocusRing ────────────────────────────────────────────────────────

"""
    FocusRing(items::Vector)

Circular focus manager for navigating between focusable widgets.
Use `next!`/`prev!` to cycle focus and `current` to get the active widget.
"""
mutable struct FocusRing
    items::Vector{Any}
    active::Int
end

FocusRing(items::Vector) = FocusRing(Any[items...], isempty(items) ? 0 : 1)

function next!(ring::FocusRing)
    isempty(ring.items) && return nothing
    ring.active = mod1(ring.active + 1, length(ring.items))
    current(ring)
end

function prev!(ring::FocusRing)
    isempty(ring.items) && return nothing
    ring.active = mod1(ring.active - 1, length(ring.items))
    current(ring)
end

function current(ring::FocusRing)
    isempty(ring.items) && return nothing
    ring.items[ring.active]
end

function handle_key!(ring::FocusRing, evt)
    w = current(ring)
    w === nothing && return
    if evt.key == :tab
        next!(ring)
    elseif evt.key == :backtab
        prev!(ring)
    elseif applicable(update!, w, evt)
        update!(w, evt)
    end
end

# ── Container ────────────────────────────────────────────────────────

struct Container
    children::Vector{Any}
    layout::Layout
    block::Union{Block,Nothing}
end

Container(children::Vector, layout::Layout) = Container(Any[children...], layout, nothing)

include("form.jl")

function render(c::Container, rect::Rect, buf::Buffer)
    area = if c.block !== nothing
        render(c.block, rect, buf)
    else
        rect
    end
    rects = split_layout(c.layout, area)
    for (i, child) in enumerate(c.children)
        i > length(rects) && break
        render(child, rects[i], buf)
    end
end
