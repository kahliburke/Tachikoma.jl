# ═══════════════════════════════════════════════════════════════════════
# PanelTree ── nested tiling panes with resizable dividers + drag-to-move/dock
#
# The tiling counterpart to WindowManager (which floats). A PanelTree owns a
# binary-ish TREE of panes: a `PaneLeaf` holds one content widget/Model; a
# `PaneSplit` arranges children along one axis with its own `ResizableLayout`
# for that level's dividers. Because splits nest, you get arbitrary combined
# horizontal+vertical layouts, and divider-resize works at every depth (it's
# the existing `ResizableLayout` under the hood).
#
# Content is any widget with `render(w, rect, buf)` (+ optional handle_key!/
# handle_mouse!), OR a `Model` (rendered via `view`, driven via `update!`).
#
# Mouse: drag a pane's header bar to MOVE it (drop on an edge to re-split, in
# the center to swap); drag a divider to resize; click to focus. The move
# gesture is modifier-free so it works over a forwarded/remote mouse stream.
#
#   pt = PanelTree(my_widget; title="main")
#   split_pane!(pt; content=other, horizontal=true, title="side")
#   render(pt, area, buf); handle_mouse!(pt, evt); handle_key!(pt, evt)
# ═══════════════════════════════════════════════════════════════════════

# ── Content dispatch (widget OR Model) ────────────────────────────────
function _pt_render!(c, rect::Rect, buf::Buffer)
    return if c isa Model
        view(c, Frame(buf, rect, GraphicsRegion[], PixelSnapshot[]))
    else
        render(c, rect, buf)
    end
end
function _pt_key!(c, e::KeyEvent)
    return if c isa Model
        (update!(c, e); true)
    else
        (applicable(handle_key!, c, e) ? handle_key!(c, e) : false)
    end
end
function _pt_mouse!(c, e::MouseEvent)
    return if c isa Model
        (update!(c, e); true)
    else
        (applicable(handle_mouse!, c, e) ? handle_mouse!(c, e) : false)
    end
end
_pt_drain!(c) = (c isa Model || (applicable(drain!, c) && (
    try
        drain!(c)
    catch
    end
)); nothing)
_pt_alive(c) = c isa Model ? !should_quit(c) : true

# ── Tree ──────────────────────────────────────────────────────────────
abstract type PaneNode end

mutable struct PaneLeaf <: PaneNode
    content::Any
    title::String
    rect::Rect            # last rendered rect (hit-testing / drop zones)
end
PaneLeaf(content; title::AbstractString="") = PaneLeaf(content, String(title), Rect())

mutable struct PaneSplit <: PaneNode
    horizontal::Bool                  # true = children side-by-side (columns)
    children::Vector{PaneNode}
    rl::ResizableLayout               # this level's dividers (one constraint per child)
    rect::Rect
end

_pt_dir(h::Bool) = h ? Horizontal : Vertical
_pt_rl(h::Bool, n::Int) = ResizableLayout(_pt_dir(h), Constraint[Fill(1) for _ in 1:max(n, 1)])
PaneSplit(h::Bool, kids::Vector{PaneNode}) = PaneSplit(h, kids, _pt_rl(h, length(kids)), Rect())

"""
    PanelTree(content; title="", chrome=:bars, alive=nothing)

A tiling pane manager. `chrome` is `:bars` (a 1-row header/drag bar per pane when
there's more than one) or `:minimal` (thin dividers + an accent ring on the focused
pane). `alive` is an optional `content -> Bool`; dead panes are pruned each render
(default: Models prune on `should_quit`, other widgets never auto-prune).
"""
mutable struct PanelTree
    root::PaneNode
    focus::PaneLeaf
    chrome::Symbol
    alive::Function
    resizing::Union{PaneSplit,Nothing}
    grab::Union{PaneLeaf,Nothing}
    grab_from::Union{PaneLeaf,Nothing}
    drop_target::Union{PaneLeaf,Nothing}
    drop_zone::Symbol
    last_area::Rect
end
function PanelTree(
    content; title::AbstractString="", chrome::Symbol=:bars, alive::Union{Function,Nothing}=nothing
)
    leaf = PaneLeaf(content; title=title)
    return PanelTree(
        leaf,
        leaf,
        chrome,
        alive === nothing ? _pt_alive : alive,
        nothing,
        nothing,
        nothing,
        nothing,
        :none,
        Rect(),
    )
end

focusable(::PanelTree) = true

# ── Traversal / query ─────────────────────────────────────────────────
_panes(n::PaneLeaf) = PaneLeaf[n]
function _panes(n::PaneSplit)
    out = PaneLeaf[]
    for c in n.children
        append!(out, _panes(c))
    end
    return out
end
"""All leaf panes, left-to-right / top-to-bottom."""
panes(pt::PanelTree) = _panes(pt.root)
"""Number of panes."""
pane_count(pt::PanelTree) = length(_panes(pt.root))
"""The focused pane / its content."""
focused_pane(pt::PanelTree) = pt.focus
focused_content(pt::PanelTree) = pt.focus.content

function _pt_parent(node::PaneNode, target::PaneNode)
    node isa PaneSplit || return nothing
    for c in node.children
        c === target && return node
    end
    for c in node.children
        p = _pt_parent(c, target)
        p === nothing || return p
    end
    return nothing
end
function _pt_at(node::PaneNode, x::Int, y::Int)
    if node isa PaneLeaf
        return contains(node.rect, x, y) ? node : nothing
    end
    for c in node.children
        l = _pt_at(c, x, y)
        l === nothing || return l
    end
    return nothing
end

# ── Structural edits ──────────────────────────────────────────────────
function _pt_split_leaf!(
    pt::PanelTree, target::PaneLeaf, newleaf::PaneLeaf, horizontal::Bool, after::Bool
)
    kids = PaneNode[after ? target : newleaf, after ? newleaf : target]
    ns = PaneSplit(horizontal, kids)
    parent = _pt_parent(pt.root, target)
    if parent === nothing
        pt.root = ns
    else
        i = findfirst(c -> c === target, parent.children)
        i === nothing || (parent.children[i] = ns)
    end
    return nothing
end

function _pt_collapse!(pt::PanelTree, parent::PaneSplit)
    only = parent.children[1]
    gp = _pt_parent(pt.root, parent)
    if gp === nothing
        pt.root = only
    else
        i = findfirst(c -> c === parent, gp.children)
        i === nothing || (gp.children[i] = only)
    end
    return nothing
end

function _pt_remove!(pt::PanelTree, node::PaneNode)
    parent = _pt_parent(pt.root, node)
    parent === nothing && return nothing
    i = findfirst(c -> c === node, parent.children)
    i === nothing && return nothing
    deleteat!(parent.children, i)
    if length(parent.children) == 1
        _pt_collapse!(pt, parent)
    else
        (parent.rl = _pt_rl(parent.horizontal, length(parent.children)))
    end
    return nothing
end

"""
    split_pane!(pt, content; horizontal=true, title="", after=true, at=focused_pane(pt)) -> PaneLeaf

Split a pane (the focused one by default), inserting `content` beside it along `horizontal`
(`after` = the new pane goes second). Returns the new `PaneLeaf` and focuses it.
"""
function split_pane!(
    pt::PanelTree,
    content;
    horizontal::Bool=true,
    title::AbstractString="",
    after::Bool=true,
    at::PaneLeaf=pt.focus,
)
    leaf = PaneLeaf(content; title=title)
    _pt_split_leaf!(pt, at, leaf, horizontal, after)
    pt.focus = leaf
    return leaf
end

"""Close a pane (the focused one by default). Never closes the last pane; returns true if it closed one."""
function close_pane!(pt::PanelTree, leaf::PaneLeaf=pt.focus)
    pane_count(pt) <= 1 && return false
    ps = _panes(pt.root)
    i = findfirst(l -> l === leaf, ps)
    _pt_remove!(pt, leaf)
    np = _panes(pt.root)
    pt.focus = np[clamp(i === nothing ? 1 : i, 1, length(np))]
    return true
end

function focus_next!(pt::PanelTree)
    ps = _panes(pt.root)
    i = findfirst(l -> l === pt.focus, ps)
    i === nothing && (i = 1)
    pt.focus = ps[mod1(i + 1, length(ps))]
    return nothing
end
function focus_prev!(pt::PanelTree)
    ps = _panes(pt.root)
    i = findfirst(l -> l === pt.focus, ps)
    i === nothing && (i = 1)
    pt.focus = ps[mod1(i - 1, length(ps))]
    return nothing
end

"""Drop dead panes (per `pt.alive`); returns false when every pane is dead."""
function prune!(pt::PanelTree)
    ps = _panes(pt.root)
    dead = filter(l -> !pt.alive(l.content), ps)
    isempty(dead) && return true
    length(dead) == length(ps) && return false        # caller decides what an all-dead tree means
    for l in dead
        _pt_remove!(pt, l)
    end
    np = _panes(pt.root)
    any(l -> l === pt.focus, np) || (pt.focus = np[1])
    return true
end

# center = swap the two panes' content; an edge = re-split the target, docking src on that side.
function _pt_dock!(pt::PanelTree, src::PaneLeaf, tgt::PaneLeaf, zone::Symbol)
    src === tgt && return nothing
    if zone === :center
        src.content, tgt.content = tgt.content, src.content
        src.title, tgt.title = tgt.title, src.title
        pt.focus = tgt
        return nothing
    end
    horizontal = zone === :left || zone === :right
    after = zone === :right || zone === :bottom
    _pt_remove!(pt, src)
    _pt_split_leaf!(pt, tgt, src, horizontal, after)
    pt.focus = src
    return nothing
end

function _pt_zone(r::Rect, x::Int, y::Int)
    (r.width < 1 || r.height < 1) && return :center
    fx = clamp((x - r.x) / max(1, r.width - 1), 0.0, 1.0)
    fy = clamp((y - r.y) / max(1, r.height - 1), 0.0, 1.0)
    left = fx
    rightv = 1 - fx
    top = fy
    bottom = 1 - fy
    mn = min(left, rightv, top, bottom)
    mn > 0.30 && return :center
    mn == left && return :left
    mn == rightv && return :right
    mn == top && return :top
    return :bottom
end

# ── Render ────────────────────────────────────────────────────────────
_pt_content_rect(h::Bool, r::Rect, last::Bool) =
    if last
        r
    elseif h
        Rect(r.x, r.y, max(1, r.width - 1), r.height)
    else
        Rect(r.x, r.y, r.width, max(1, r.height - 1))
    end

function _pt_dividers!(node::PaneSplit, buf::Buffer, rects)
    sty = tstyle(:border)
    for i in 1:(length(rects) - 1)
        r = rects[i]
        if node.horizontal
            x = r.x + r.width - 1
            for y in r.y:(r.y + r.height - 1)
                set_char!(buf, x, y, '│', sty)
            end
        else
            y = r.y + r.height - 1
            for x in r.x:(r.x + r.width - 1)
                set_char!(buf, x, y, '─', sty)
            end
        end
    end
    return nothing
end

# Header bar = the drag handle (whole row), accent when focused / primary while moving.
_pt_handle_rect(l::PaneLeaf) = Rect(l.rect.x, l.rect.y, l.rect.width, 1)
function _pt_header!(pt::PanelTree, l::PaneLeaf, buf::Buffer)
    r = l.rect
    sty = if l === pt.grab
        tstyle(:primary; bold=true)
    elseif l === pt.focus
        tstyle(:accent; bold=true)
    else
        tstyle(:border)
    end
    title = isempty(l.title) ? "⠿" : "⠿ " * l.title
    nx = set_string!(buf, r.x, r.y, first(" " * title * " ", r.width), sty)
    for x in nx:(r.x + r.width - 1)
        set_char!(buf, x, r.y, '─', sty)
    end
    return nothing
end

# Minimal-chrome focus indicator: accent the divider/gap cells bordering the focused pane (no content
# clobber — those cells are dividers or the canvas edge).
function _pt_focus_ring!(pt::PanelTree, buf::Buffer, area::Rect)
    r = pt.focus.rect
    (r.width < 1 || r.height < 1) && return nothing
    sty = tstyle(:accent; bold=true)
    x0 = r.x - 1
    x1 = r.x + r.width
    y0 = r.y - 1
    y1 = r.y + r.height
    for y in max(r.y, area.y):min(r.y + r.height - 1, bottom(area))
        x0 >= area.x && set_char!(buf, x0, y, '│', sty)
        x1 <= right(area) && set_char!(buf, x1, y, '│', sty)
    end
    for x in max(r.x, area.x):min(r.x + r.width - 1, right(area))
        y0 >= area.y && set_char!(buf, x, y0, '─', sty)
        y1 <= bottom(area) && set_char!(buf, x, y1, '─', sty)
    end
    return nothing
end

function _pt_render_node!(pt::PanelTree, node::PaneLeaf, rect::Rect, buf::Buffer, bars::Bool)
    node.rect = rect
    _pt_drain!(node.content)
    content = bars ? Rect(rect.x, rect.y + 1, rect.width, max(1, rect.height - 1)) : rect
    try
        _pt_render!(node.content, content, buf)
    catch
    end
    bars && _pt_header!(pt, node, buf)
    return nothing
end

function _pt_render_node!(pt::PanelTree, node::PaneSplit, rect::Rect, buf::Buffer, bars::Bool)
    node.rect = rect
    node.horizontal = node.rl.direction == Horizontal     # honor mouse rotate/reset
    rects = split_layout(node.rl, rect)
    n = length(node.children)
    for (i, c) in enumerate(node.children)
        i <= length(rects) || break
        _pt_render_node!(pt, c, _pt_content_rect(node.horizontal, rects[i], i == n), buf, bars)
    end
    _pt_dividers!(node, buf, rects)
    try
        render_resize_handles!(buf, node.rl)
    catch
    end
    return nothing
end

"""
    render(pt::PanelTree, area::Rect, buf::Buffer)

Lay the panes out in `area` and draw them (chrome + dividers + any drag preview).
"""
function render(pt::PanelTree, area::Rect, buf::Buffer)
    pt.last_area = area
    prune!(pt) || return nothing
    multi = pane_count(pt) > 1
    bars = multi && pt.chrome === :bars
    _pt_render_node!(pt, pt.root, area, buf, bars)
    if multi && pt.chrome === :minimal && pt.grab === nothing
        _pt_focus_ring!(pt, buf, area)
    end
    if pt.grab !== nothing
        _pt_outline!(buf, pt.grab.rect, tstyle(:primary; bold=true))
        _pt_drop_overlay!(pt, buf)
    end
    return nothing
end

function _pt_outline!(buf::Buffer, r::Rect, sty::Style)
    (r.width < 2 || r.height < 2) && return nothing
    x2 = r.x + r.width - 1
    y2 = r.y + r.height - 1
    for x in r.x:x2
        set_char!(buf, x, r.y, '─', sty)
        set_char!(buf, x, y2, '─', sty)
    end
    for y in r.y:y2
        set_char!(buf, r.x, y, '│', sty)
        set_char!(buf, x2, y, '│', sty)
    end
    set_char!(buf, r.x, r.y, '┌', sty)
    set_char!(buf, x2, r.y, '┐', sty)
    set_char!(buf, r.x, y2, '└', sty)
    set_char!(buf, x2, y2, '┘', sty)
    return nothing
end

function _pt_drop_overlay!(pt::PanelTree, buf::Buffer)
    t = pt.drop_target
    (t === nothing || pt.drop_zone === :none) && return nothing
    r = t.rect
    z = pt.drop_zone
    hw = max(1, r.width ÷ 2)
    hh = max(1, r.height ÷ 2)
    sub = if z === :left
        Rect(r.x, r.y, hw, r.height)
    elseif z === :right
        Rect(r.x + r.width - hw, r.y, hw, r.height)
    elseif z === :top
        Rect(r.x, r.y, r.width, hh)
    elseif z === :bottom
        Rect(r.x, r.y + r.height - hh, r.width, hh)
    else
        r
    end
    for y in sub.y:(sub.y + sub.height - 1), x in sub.x:(sub.x + sub.width - 1)
        set_char!(buf, x, y, '░', tstyle(:accent))
    end
    _pt_outline!(buf, sub, tstyle(:accent; bold=true))
    label = z === :center ? " swap " : " split "
    set_string!(
        buf,
        sub.x + max(0, (sub.width - length(label)) ÷ 2),
        sub.y + sub.height ÷ 2,
        label,
        tstyle(:primary; bold=true),
    )
    return nothing
end

# ── Keyboard: delegate to the focused pane (the app owns any prefix/commands) ──
function handle_key!(pt::PanelTree, e::KeyEvent)::Bool
    return _pt_key!(pt.focus.content, e)
end

# ── Mouse: header-drag move/dock · divider resize · click focus ───────
function handle_mouse!(pt::PanelTree, e::MouseEvent)::Bool
    # A pane is grabbed: preview the drop, dock on release.
    if pt.grab !== nothing
        e.action == mouse_release ? _pt_finish_grab!(pt, e.x, e.y) : _pt_update_drop!(pt, e.x, e.y)
        return true
    end
    multi = pane_count(pt) > 1
    # Header press → pick the pane up. BEFORE resize: a stacked pane's header row sits one cell from
    # the divider above it, and _find_border's ±1 tolerance would otherwise let resize steal it.
    if multi && e.action == mouse_press && e.button == mouse_left && pt.chrome === :bars
        leaf = _pt_at(pt.root, e.x, e.y)
        if leaf !== nothing && contains(_pt_handle_rect(leaf), e.x, e.y)
            pt.focus = leaf
            _pt_begin_grab!(pt, leaf, e)
            return true
        end
    end
    _pt_dispatch_resize!(pt, e) && return true
    if e.action == mouse_press && e.button == mouse_left
        leaf = _pt_at(pt.root, e.x, e.y)
        if leaf !== nothing
            pt.focus = leaf
            pt.grab_from = leaf
            _pt_mouse!(leaf.content, e)
        end
        return true
    end
    if e.action == mouse_drag && pt.grab_from !== nothing
        _pt_mouse!(pt.grab_from.content, e)
        return true
    end
    e.action == mouse_release && (pt.grab_from = nothing)
    leaf = _pt_at(pt.root, e.x, e.y)
    leaf === nothing || _pt_mouse!(leaf.content, e)
    return true
end

function _pt_border_at(node::PaneNode, e::MouseEvent)
    node isa PaneSplit || return nothing
    for c in node.children
        d = _pt_border_at(c, e)
        d === nothing || return d
    end
    rl = node.rl
    isempty(rl.rects) && return nothing
    pos = rl.direction == Horizontal ? e.x : e.y
    within = if rl.direction == Horizontal
        (e.y >= rl.last_area.y && e.y <= bottom(rl.last_area))
    else
        (e.x >= rl.last_area.x && e.x <= right(rl.last_area))
    end
    return (within && _find_border(rl, pos) > 0) ? node : nothing
end

function _pt_dispatch_resize!(pt::PanelTree, e::MouseEvent)
    if pt.resizing !== nothing
        consumed = handle_resize!(pt.resizing.rl, e)
        e.action == mouse_release && (pt.resizing = nothing)
        return consumed || e.action == mouse_release
    end
    if e.action == mouse_move
        _pt_each_split(n -> handle_resize!(n.rl, e), pt.root)
        return false
    end
    if e.action == mouse_press && e.button == mouse_left
        node = _pt_border_at(pt.root, e)
        if node !== nothing && handle_resize!(node.rl, e)
            node.rl.drag.status == drag_active && (pt.resizing = node)
            return true
        end
    end
    return false
end

function _pt_each_split(f, node::PaneNode)
    if node isa PaneSplit
        f(node)
        for c in node.children
            _pt_each_split(f, c)
        end
    end
    return nothing
end

function _pt_begin_grab!(pt::PanelTree, leaf::PaneLeaf, e::MouseEvent)
    pt.grab = leaf
    pt.grab_from = nothing
    try
        _pt_mouse!(
            leaf.content, MouseEvent(e.x, e.y, mouse_left, mouse_release, false, false, false)
        )
    catch
    end
    return nothing
end

function _pt_update_drop!(pt::PanelTree, x::Int, y::Int)
    leaf = _pt_at(pt.root, x, y)
    if leaf === nothing || leaf === pt.grab
        pt.drop_target = nothing
        pt.drop_zone = :none
    else
        pt.drop_target = leaf
        pt.drop_zone = _pt_zone(leaf.rect, x, y)
    end
    return nothing
end

function _pt_finish_grab!(pt::PanelTree, x::Int, y::Int)
    _pt_update_drop!(pt, x, y)
    src = pt.grab
    tgt = pt.drop_target
    zone = pt.drop_zone
    (src !== nothing && tgt !== nothing && tgt !== src && zone !== :none) &&
        _pt_dock!(pt, src, tgt, zone)
    pt.grab = nothing
    pt.grab_from = nothing
    pt.drop_target = nothing
    pt.drop_zone = :none
    return nothing
end

"""Cancel an in-progress pane move (e.g. on Esc)."""
function cancel_move!(pt::PanelTree)
    return (
        pt.grab=nothing; pt.grab_from=nothing; pt.drop_target=nothing; pt.drop_zone=:none; nothing
    )
end

"""True while a pane is being dragged."""
is_moving(pt::PanelTree) = pt.grab !== nothing
