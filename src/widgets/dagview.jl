# ═══════════════════════════════════════════════════════════════════════
# DAGView ── layered node graph for pipelines and other DAGs
#
# Nodes are laid out in columns by dependency depth (longest path from a
# source), ordered within each column to reduce edge crossings, and joined
# by orthogonal box-drawing connectors. Supports keyboard navigation along
# edges, click-to-select, hover tooltips, lineage highlighting, and panning.
# ═══════════════════════════════════════════════════════════════════════

"""
    DAGNode(id, label=string(id); deps=Symbol[], links=Symbol[], status=task_pending,
            icon=nothing, subtitle="", detail=nothing, content=nothing)

A node in a [`DAGView`](@ref). `deps` lists the ids of the nodes this one
depends on; an edge is drawn from each of them to this node.

- `links` — ids of nodes this one uses without waiting on them (a shared model,
  credentials, a config source). Laid out like `deps` but drawn dashed.
- `status` — a [`TaskStatus`](@ref) (`task_pending`, `task_running`,
  `task_done`, `task_error`, `task_skipped`), shown as a glyph and border color.
- `icon` — a `Char` naming the node's kind (`'⚡'`, `'✉'`…). Shown before the
  label in place of the status glyph, which then moves onto the top border.
- `subtitle` — optional second line under the label (a duration, a host…).
- `detail` — a `String` or `Vector{Span}` shown in a tooltip while the mouse
  hovers the node. `nothing` disables the tooltip for this node.
- `content` — arbitrary user data.

Fields are mutable: change `status`, `subtitle` or `detail` in place and the
next frame shows it. Changing ids, labels, `deps` or `links` re-runs the layout.
"""
mutable struct DAGNode
    id::Symbol
    label::String
    deps::Vector{Symbol}
    links::Vector{Symbol}
    status::TaskStatus
    icon::Union{Char,Nothing}
    subtitle::String
    detail::Any
    content::Any
end

function DAGNode(id, label=string(id); deps=Symbol[], links=Symbol[],
                 status::TaskStatus=task_pending, icon=nothing,
                 subtitle="", detail=nothing, content=nothing)
    DAGNode(Symbol(id), String(label), Symbol[Symbol(d) for d in deps],
            Symbol[Symbol(d) for d in links], status, icon, String(subtitle),
            detail, content)
end

# ── Layout ───────────────────────────────────────────────────────────

# Connector direction bits for a cell.
const _DAG_N = 0x01
const _DAG_E = 0x02
const _DAG_S = 0x04
const _DAG_W = 0x08

# Glyph for each combination of direction bits (index = bits + 1).
const _DAG_GLYPHS = (
    '─',  # 0  (lone cell)
    '│',  # N
    '─',  # E
    '╰',  # N E
    '│',  # S
    '│',  # N S
    '╭',  # E S
    '├',  # N E S
    '─',  # W
    '╯',  # N W
    '─',  # E W
    '┴',  # N E W
    '╮',  # S W
    '┤',  # N S W
    '┬',  # E S W
    '┼',  # N E S W
)

# Straight runs of a dashed link (horizontal, vertical); bends and junctions
# have no dashed form and use the solid glyph.
const _DAG_DASH_H = '╌'
const _DAG_DASH_V = '╎'

const _DagCells = Dict{Tuple{Int,Int},UInt8}

struct _DagLayout
    index::Dict{Symbol,Int}          # node id → node index
    edges::Vector{Tuple{Int,Int}}    # (upstream, downstream) node indices
    dashed::Vector{Bool}             # per edge, drawn as a link rather than a dependency
    preds::Vector{Vector{Int}}
    succs::Vector{Vector{Int}}
    layer::Vector{Int}               # per node, 1-based column
    layers::Vector{Vector{Int}}      # real nodes per column, top to bottom
    x::Vector{Int}                   # per node, graph coords (0-based)
    y::Vector{Int}
    port::Vector{Int}                # per node, row where edges attach
    node_w::Int
    node_h::Int
    width::Int
    height::Int
    edge_cells::Vector{_DagCells}    # per edge, connector cells in graph coords
    arrows::Vector{Tuple{Int,Int}}   # per edge, arrowhead cell
end

function _dag_add_hline!(m::_DagCells, y::Int, x1::Int, x2::Int)
    a, b = minmax(x1, x2)
    for x in a:b
        bits = 0x00
        x > a && (bits |= _DAG_W)
        x < b && (bits |= _DAG_E)
        m[(x, y)] = get(m, (x, y), 0x00) | bits
    end
end

function _dag_add_vline!(m::_DagCells, x::Int, y1::Int, y2::Int)
    a, b = minmax(y1, y2)
    for y in a:b
        bits = 0x00
        y > a && (bits |= _DAG_N)
        y < b && (bits |= _DAG_S)
        m[(x, y)] = get(m, (x, y), 0x00) | bits
    end
end

_dag_or!(m::_DagCells, x::Int, y::Int, bits::UInt8) = (m[(x, y)] = get(m, (x, y), 0x00) | bits)

# Edge crossings between column `l` and column `l + 1`.
function _dag_gap_crossings(layers, vsucc, pos, l::Int)
    (l < 1 || l >= length(layers)) && return 0
    segs = Tuple{Float64,Float64}[]
    for a in layers[l], b in vsucc[a]
        push!(segs, (pos[a], pos[b]))
    end
    total = 0
    for i in 1:length(segs), j in i+1:length(segs)
        (segs[i][1] - segs[j][1]) * (segs[i][2] - segs[j][2]) < 0 && (total += 1)
    end
    total
end

_dag_crossings(layers, vsucc, pos) =
    sum((_dag_gap_crossings(layers, vsucc, pos, l) for l in 1:length(layers)-1); init=0)

# Swap adjacent vertices within a column while that lowers the crossings on
# either side of it. Fixes orderings the barycenter sweeps get stuck in.
function _dag_transpose!(layers, vsucc, pos)
    for _ in 1:10
        improved = false
        for l in eachindex(layers)
            lay = layers[l]
            for i in 1:length(lay)-1
                before = _dag_gap_crossings(layers, vsucc, pos, l - 1) +
                         _dag_gap_crossings(layers, vsucc, pos, l)
                v, w = lay[i], lay[i+1]
                lay[i], lay[i+1] = w, v
                pos[v], pos[w] = pos[w], pos[v]
                after = _dag_gap_crossings(layers, vsucc, pos, l - 1) +
                        _dag_gap_crossings(layers, vsucc, pos, l)
                if after < before
                    improved = true
                else
                    lay[i], lay[i+1] = v, w
                    pos[v], pos[w] = pos[w], pos[v]
                end
            end
        end
        improved || break
    end
end

# Reorder one column by the mean position of each vertex's neighbors in the
# adjacent column. Vertices with no neighbors there keep their position.
function _dag_sort_layer!(lay::Vector{Int}, nbrs, pos::Vector{Float64})
    keys = Dict{Int,Float64}()
    for v in lay
        keys[v] = isempty(nbrs[v]) ? pos[v] : sum(pos[u] for u in nbrs[v]) / length(nbrs[v])
    end
    sort!(lay; by=v -> keys[v], alg=MergeSort)
    for (i, v) in enumerate(lay)
        pos[v] = i
    end
end

# Barycenter sweeps with adjacent swaps from the given starting order.
# Returns the best ordering seen and its crossing count.
function _dag_order!(layers, vpred, vsucc, nv)
    L = length(layers)
    pos = zeros(Float64, nv)
    for lay in layers, (i, v) in enumerate(lay)
        pos[v] = i
    end
    _dag_transpose!(layers, vsucc, pos)
    best = deepcopy(layers)
    best_x = _dag_crossings(layers, vsucc, pos)
    for sweep in 1:8
        best_x == 0 && break
        if isodd(sweep)
            for l in 2:L
                _dag_sort_layer!(layers[l], vpred, pos)
            end
        else
            for l in L-1:-1:1
                _dag_sort_layer!(layers[l], vsucc, pos)
            end
        end
        _dag_transpose!(layers, vsucc, pos)
        c = _dag_crossings(layers, vsucc, pos)
        if c < best_x
            best_x = c
            best = deepcopy(layers)
        end
    end
    best, best_x
end

# Place one column's vertices as close as possible to their desired top rows
# while keeping order and spacing. Averages a top-down and a bottom-up packing
# so a crowded column spreads in both directions instead of only downward.
function _dag_place!(y::Vector{Int}, lay::Vector{Int}, desired::Vector{Float64},
                     h::Vector{Int}, gap::Int)
    k = length(lay)
    k == 0 && return
    a = copy(desired)
    for i in 2:k
        a[i] = max(a[i], a[i-1] + h[lay[i-1]] + gap)
    end
    b = copy(desired)
    for i in k-1:-1:1
        b[i] = min(b[i], b[i+1] - h[lay[i]] - gap)
    end
    prev = typemin(Int)
    for i in 1:k
        yi = round(Int, (a[i] + b[i]) / 2)
        i > 1 && (yi = max(yi, prev + h[lay[i-1]] + gap))
        y[lay[i]] = yi
        prev = yi
    end
end

function _dag_layout(nodes::Vector{DAGNode}, node_w::Int, node_h::Int, h_gap::Int, v_gap::Int)
    n = length(nodes)
    index = Dict{Symbol,Int}()
    for (i, nd) in enumerate(nodes)
        haskey(index, nd.id) && throw(ArgumentError("DAGView: duplicate node id :$(nd.id)"))
        index[nd.id] = i
    end
    edges = Tuple{Int,Int}[]
    dashed = Bool[]
    preds = [Int[] for _ in 1:n]
    succs = [Int[] for _ in 1:n]
    for (v, nd) in enumerate(nodes), (ids, dash) in ((nd.deps, false), (nd.links, true)), d in ids
        u = get(index, d, 0)
        u == 0 && throw(ArgumentError("DAGView: node :$(nd.id) depends on unknown node :$d"))
        u == v && throw(ArgumentError("DAGView: node :$(nd.id) depends on itself"))
        u in preds[v] && continue
        push!(edges, (u, v)); push!(dashed, dash); push!(preds[v], u); push!(succs[u], v)
    end

    # Topological order (Kahn) and longest-path ranks.
    indeg = length.(preds)
    queue = [i for i in 1:n if indeg[i] == 0]
    order = Int[]
    rank = zeros(Int, n)
    while !isempty(queue)
        u = popfirst!(queue)
        push!(order, u)
        for v in succs[u]
            rank[v] = max(rank[v], rank[u] + 1)
            indeg[v] -= 1
            indeg[v] == 0 && push!(queue, v)
        end
    end
    if length(order) < n
        cyc = join((":" * string(nodes[i].id) for i in 1:n if indeg[i] > 0), ", ")
        throw(ArgumentError("DAGView: dependency cycle among $cyc"))
    end
    # Pull each source right to sit just before its earliest dependent, so an
    # input needed late in the pipeline doesn't trail a long edge behind it.
    for u in Iterators.reverse(order)
        (isempty(succs[u]) || !isempty(preds[u])) && continue
        rank[u] = minimum(rank[v] for v in succs[u]) - 1
    end

    # Vertices: real nodes 1:n, then one dummy per column an edge passes through.
    vlayer = rank .+ 1
    segs = Tuple{Int,Int,Int}[]          # (from vertex, to vertex, edge index)
    for (ei, (u, v)) in enumerate(edges)
        prev = u
        for l in vlayer[u]+1:vlayer[v]-1
            push!(vlayer, l)
            d = length(vlayer)
            push!(segs, (prev, d, ei))
            prev = d
        end
        push!(segs, (prev, v, ei))
    end
    nv = length(vlayer)
    L = n == 0 ? 0 : maximum(vlayer)
    vpred = [Int[] for _ in 1:nv]
    vsucc = [Int[] for _ in 1:nv]
    for (a, b, _) in segs
        push!(vsucc[a], b); push!(vpred[b], a)
    end

    # ── Order within columns ──
    # Barycenter sweeps plus adjacent swaps, run from a few starting orders
    # (input, reversed, depth-first); keep whichever has the fewest crossings.
    dfs_rank = zeros(Int, nv)
    let counter = 0, stack = Int[]
        for s0 in Iterators.reverse(1:nv)
            isempty(vpred[s0]) && push!(stack, s0)
        end
        while !isempty(stack)
            v = pop!(stack)
            dfs_rank[v] == 0 || continue
            dfs_rank[v] = (counter += 1)
            for w in Iterators.reverse(vsucc[v])
                dfs_rank[w] == 0 && push!(stack, w)
            end
        end
    end
    starts = (v -> v, v -> -v, v -> dfs_rank[v])
    layers = Vector{Int}[]
    best_x = typemax(Int)
    for key in starts
        cand = [Int[] for _ in 1:L]
        for v in 1:nv
            push!(cand[vlayer[v]], v)
        end
        foreach(lay -> sort!(lay; by=key), cand)
        lay_best, x_best = _dag_order!(cand, vpred, vsucc, nv)
        if x_best < best_x
            best_x, layers = x_best, lay_best
        end
        best_x == 0 && break
    end

    # ── Rows: stack each column, then pull vertices toward their neighbors ──
    h = [v <= n ? node_h : 1 for v in 1:nv]
    po = [v <= n && node_h > 1 ? 1 : 0 for v in 1:nv]   # port row within the vertex
    y = zeros(Int, nv)
    col_h(lay) = isempty(lay) ? 0 : sum(h[v] for v in lay) + v_gap * (length(lay) - 1)
    tallest = L == 0 ? 0 : maximum(col_h, layers)
    for lay in layers
        yy = (tallest - col_h(lay)) ÷ 2
        for v in lay
            y[v] = yy
            yy += h[v] + v_gap
        end
    end
    for it in 1:8
        nbrs = isodd(it) ? vpred : vsucc
        rng = isodd(it) ? (2:L) : (L-1:-1:1)
        for l in rng
            lay = layers[l]
            desired = Float64[isempty(nbrs[v]) ? y[v] :
                              sum(y[u] + po[u] for u in nbrs[v]) / length(nbrs[v]) - po[v]
                              for v in lay]
            _dag_place!(y, lay, desired, h, v_gap)
        end
    end
    if nv > 0
        ymin = minimum(y)
        y .-= ymin
    end
    port = y .+ po
    height = nv == 0 ? 0 : maximum(y[v] + h[v] for v in 1:nv)

    # ── Edge routing ──
    # Each column gap holds one vertical channel per vertex that leaves it on a
    # bend; all of that vertex's outgoing segments share it, so a fan-out reads
    # as a tree. A gap widens past `h_gap` when it needs more channels.
    # Downward-routed sources get channels from the right in top-to-bottom order
    # (upward ones bottom-to-top), so a source's horizontal run doesn't cross
    # another source's vertical in the same gap.
    gap_sources = Vector{Vector{Int}}(undef, max(L - 1, 0))
    gap_w = fill(h_gap, max(L - 1, 0))
    for l in 1:L-1
        downs = Int[]; ups = Int[]
        for a in layers[l]
            any(b -> port[b] != port[a], vsucc[a]) || continue
            dir = sum((sign(port[b] - port[a]) for b in vsucc[a]); init=0)
            push!(dir >= 0 ? downs : ups, a)
        end
        sort!(downs; by=a -> port[a])
        sort!(ups; by=a -> -port[a])
        gap_sources[l] = vcat(downs, ups)
        gap_w[l] = max(h_gap, length(gap_sources[l]) + 2)
    end
    col_x = zeros(Int, L)
    for l in 2:L
        col_x[l] = col_x[l-1] + node_w + gap_w[l-1]
    end
    width = L == 0 ? 0 : col_x[L] + node_w
    x = [col_x[vlayer[v]] for v in 1:nv]

    edge_cells = [_DagCells() for _ in edges]
    arrows = [(0, 0) for _ in edges]
    channel = Dict{Int,Int}()
    for l in 1:L-1
        xl = col_x[l+1]
        for (k, a) in enumerate(gap_sources[l])
            channel[a] = xl - 1 - k
        end
    end
    for (a, b, ei) in segs
        m = edge_cells[ei]
        xr = x[a] + node_w - 1
        xl = x[b]
        ya, yb = port[a], port[b]
        if ya == yb
            _dag_add_hline!(m, ya, xr + 1, xl - 1)
        else
            cx = channel[a]
            _dag_add_hline!(m, ya, xr + 1, cx)
            _dag_add_vline!(m, cx, ya, yb)
            _dag_add_hline!(m, yb, cx, xl - 1)
        end
        _dag_or!(m, xr + 1, ya, _DAG_W)
        _dag_or!(m, xl - 1, yb, _DAG_E)
        if b > n
            # Dummy vertex: the edge runs straight through this column.
            _dag_add_hline!(m, port[b], x[b], x[b] + node_w - 1)
            _dag_or!(m, x[b], port[b], _DAG_W)
            _dag_or!(m, x[b] + node_w - 1, port[b], _DAG_E)
        else
            arrows[ei] = (xl - 1, yb)
        end
    end

    real_layers = [filter(<=(n), lay) for lay in layers]
    _DagLayout(index, edges, dashed, preds, succs, vlayer[1:n], real_layers,
               x[1:n], y[1:n], port[1:n], node_w, node_h, width, height,
               edge_cells, arrows)
end

# ── Widget ───────────────────────────────────────────────────────────

mutable struct DAGView
    nodes::Vector{DAGNode}
    selected::Union{Symbol,Nothing}
    hovered::Union{Symbol,Nothing}
    focused::Bool
    block::Union{Block,Nothing}
    node_width::Union{Int,Nothing}
    h_gap::Int
    v_gap::Int
    zoom::Int
    show_tooltip::Bool
    tooltip_width::Int
    highlight_lineage::Bool
    show_scrollbars::Bool
    edge_style::Union{Style,Nothing}
    highlight_style::Union{Style,Nothing}
    tick::Union{Int,Nothing}
    offset_x::Int
    offset_y::Int
    last_area::Rect
    _layout::Union{_DagLayout,Nothing}
    _layout_key::UInt
    _origin::Tuple{Int,Int}
    _drag::Union{Nothing,NTuple{4,Int}}
    _reveal::Bool
    _anchor::Union{Nothing,Tuple{Symbol,Int,Int}}
    _virt::Union{Buffer,Nothing}
    _came_from::Union{Nothing,Tuple{Symbol,Symbol}}
end

"""
    DAGView(nodes::Vector{DAGNode}; selected=nothing, focused=false, block=nothing,
            zoom=3, node_width=nothing, h_gap=6, v_gap=1, show_tooltip=true,
            tooltip_width=48, highlight_lineage=true, show_scrollbars=true,
            edge_style=nothing, highlight_style=nothing, tick=nothing)

Directed acyclic graph view, e.g. a CI or data pipeline. Nodes are placed in
columns by dependency depth and joined by box-drawing connectors. The graph is
drawn on a canvas of its own size; the widget shows a window onto it, with
scrollbars when it overflows.

- **Keyboard** (`handle_key!`): Up/Down move within a column, Left/Right follow
  edges upstream/downstream, Home selects the first node, `+`/`-` zoom.
- **Mouse** (`handle_mouse!`): hover shows the node's `detail` in a tooltip,
  click selects, drag on empty space pans, wheel scrolls (Shift+wheel
  horizontally), Ctrl+wheel zooms.
- `zoom` — level of detail: `3` full boxes with subtitles, `2` compact boxes,
  `1` one line per node for an overview of a large graph.
- `highlight_lineage` — color the edges upstream and downstream of the hovered
  (or else selected) node.
- `node_width` — fixed node width at zoom 2 and 3; by default sized to the labels.
- `tick` — frame counter for the running-status spinner.

`value(dv)` is the selected node id, `selected_node(dv)` the node itself,
`hovered_node(dv)` the node under the mouse, and `dv[id]` looks up a node.
Throws `ArgumentError` on render if the graph has a cycle or an unknown dependency.
"""
function DAGView(nodes::Vector{DAGNode};
    selected=nothing,
    focused=false,
    block=nothing,
    zoom=3,
    node_width=nothing,
    h_gap=6,
    v_gap=1,
    show_tooltip=true,
    tooltip_width=48,
    highlight_lineage=true,
    show_scrollbars=true,
    edge_style=nothing,
    highlight_style=nothing,
    tick=nothing,
)
    h_gap >= 3 || throw(ArgumentError("DAGView: h_gap must be at least 3"))
    v_gap >= 0 || throw(ArgumentError("DAGView: v_gap must be non-negative"))
    DAGView(nodes, selected === nothing ? nothing : Symbol(selected), nothing,
            focused, block, node_width, h_gap, v_gap, clamp(zoom, 1, 3),
            show_tooltip, tooltip_width, highlight_lineage, show_scrollbars,
            edge_style, highlight_style, tick,
            0, 0, Rect(), nothing, UInt(0), (0, 0), nothing, selected !== nothing,
            nothing, nothing, nothing)
end

focusable(::DAGView) = true
value(dv::DAGView) = dv.selected
function set_value!(dv::DAGView, id)
    dv.selected = id === nothing ? nothing : Symbol(id)
    dv._reveal = true
    dv
end

function Base.getindex(dv::DAGView, id::Symbol)
    for nd in dv.nodes
        nd.id == id && return nd
    end
    throw(KeyError(id))
end
Base.haskey(dv::DAGView, id::Symbol) = any(nd -> nd.id == id, dv.nodes)

function selected_node(dv::DAGView)::Union{DAGNode,Nothing}
    dv.selected === nothing || !haskey(dv, dv.selected) ? nothing : dv[dv.selected]
end

"""
    hovered_node(dv::DAGView) → DAGNode or nothing

The node under the mouse pointer, as of the last `handle_mouse!` call.
"""
function hovered_node(dv::DAGView)::Union{DAGNode,Nothing}
    dv.hovered === nothing || !haskey(dv, dv.hovered) ? nothing : dv[dv.hovered]
end

# Node size and spacing for the current zoom level.
function _dag_geometry(dv::DAGView)
    nodes = dv.nodes
    lw = isempty(nodes) ? 6 : maximum(nd -> textwidth(nd.label), nodes)
    gw = isempty(nodes) ? 1 : maximum(nd -> nd.icon === nothing ? 1 : textwidth(nd.icon), nodes)
    if dv.zoom <= 1
        nw = clamp(lw + gw + 1, 6, 16)
        return (nw, 1, max(3, dv.h_gap ÷ 2), 0)
    end
    has_sub = dv.zoom >= 3 && any(nd -> !isempty(nd.subtitle), nodes)
    tw = has_sub ? max(lw, maximum(nd -> textwidth(nd.subtitle), nodes)) : lw
    nw = dv.node_width !== nothing ? max(dv.node_width, 8) :
         clamp(tw + 5 + gw, 10, dv.zoom >= 3 ? 32 : 24)
    (nw, has_sub ? 4 : 3, dv.h_gap, dv.v_gap)
end

function _dag_layout!(dv::DAGView)
    nw, nh, hg, vg = _dag_geometry(dv)
    key = hash((nw, nh, hg, vg))
    for nd in dv.nodes
        key = hash((nd.id, nd.deps, nd.links), key)
    end
    if dv._layout === nothing || key != dv._layout_key
        dv._layout = _dag_layout(dv.nodes, nw, nh, hg, vg)
        dv._layout_key = key
    end
    dv._layout::_DagLayout
end

function _dag_clamp_offsets!(dv::DAGView, lay::_DagLayout, area::Rect)
    dv.offset_x = clamp(dv.offset_x, 0, max(0, lay.width - area.width))
    dv.offset_y = clamp(dv.offset_y, 0, max(0, lay.height - area.height))
end

# Screen position of graph coordinate (0, 0). A graph smaller than the area is centered.
function _dag_origin(dv::DAGView, lay::_DagLayout, area::Rect)
    ox = lay.width <= area.width ? area.x + (area.width - lay.width) ÷ 2 : area.x - dv.offset_x
    oy = lay.height <= area.height ? area.y + (area.height - lay.height) ÷ 2 : area.y - dv.offset_y
    (ox, oy)
end

# Scroll just enough to bring the selected node fully into view.
function _dag_reveal!(dv::DAGView, lay::_DagLayout, area::Rect)
    i = dv.selected === nothing ? 0 : get(lay.index, dv.selected, 0)
    i == 0 && return
    x0, y0 = lay.x[i], lay.y[i]
    x1, y1 = x0 + lay.node_w - 1, y0 + lay.node_h - 1
    x1 > dv.offset_x + area.width - 1 && (dv.offset_x = x1 - area.width + 1)
    x0 < dv.offset_x && (dv.offset_x = x0)
    y1 > dv.offset_y + area.height - 1 && (dv.offset_y = y1 - area.height + 1)
    y0 < dv.offset_y && (dv.offset_y = y0)
end

"""
    node_at(dv::DAGView, x, y) → Symbol or nothing

Id of the node drawn at screen cell `(x, y)` in the last render.
"""
function node_at(dv::DAGView, x::Int, y::Int)::Union{Symbol,Nothing}
    lay = dv._layout
    lay === nothing && return nothing
    contains(dv.last_area, x, y) || return nothing
    gx, gy = x - dv._origin[1], y - dv._origin[2]
    for (i, nd) in enumerate(dv.nodes)
        i > length(lay.x) && break
        if lay.x[i] <= gx < lay.x[i] + lay.node_w && lay.y[i] <= gy < lay.y[i] + lay.node_h
            return nd.id
        end
    end
    nothing
end

"""
    zoom!(dv::DAGView, delta) → Bool

Change the level of detail by `delta` (clamped to 1–3), keeping the hovered or
selected node where it is on screen. Returns whether the level changed.
"""
function zoom!(dv::DAGView, delta::Int)
    z = clamp(dv.zoom + delta, 1, 3)
    z == dv.zoom && return false
    id = dv.hovered !== nothing ? dv.hovered : dv.selected
    lay = dv._layout
    if id !== nothing && lay !== nothing && haskey(lay.index, id)
        i = lay.index[id]
        dv._anchor = (id, dv._origin[1] + lay.x[i], dv._origin[2] + lay.port[i])
    end
    dv.zoom = z
    true
end

# Keep the anchored node at the same screen cell after a zoom.
function _dag_apply_anchor!(dv::DAGView, lay::_DagLayout, area::Rect)
    a = dv._anchor
    a === nothing && return
    dv._anchor = nothing
    i = get(lay.index, a[1], 0)
    i == 0 && return
    dv.offset_x = lay.x[i] - (a[2] - area.x)
    dv.offset_y = lay.port[i] - (a[3] - area.y)
end

# ── Rendering ────────────────────────────────────────────────────────

function _dag_status_glyph(s::TaskStatus, tick)
    if s == task_done
        ('✓', tstyle(:success, bold=true))
    elseif s == task_error
        ('✗', tstyle(:error, bold=true))
    elseif s == task_running
        ch = tick === nothing ? '◐' : SPINNER_BRAILLE[mod1(tick ÷ 4 + 1, length(SPINNER_BRAILLE))]
        (ch, tstyle(:primary, bold=true))
    elseif s == task_skipped
        ('⊘', tstyle(:text_dim))
    else
        ('○', tstyle(:text_dim))
    end
end

function _dag_status_border(s::TaskStatus)
    s == task_done    ? tstyle(:success) :
    s == task_error   ? tstyle(:error) :
    s == task_running ? tstyle(:primary) :
                        tstyle(:border, dim=true)
end

_dag_status_label(s::TaskStatus) =
    s == task_done ? "done" : s == task_error ? "failed" : s == task_running ? "running" :
    s == task_skipped ? "skipped" : "pending"

@inline function _dag_put!(buf::Buffer, area::Rect, x::Int, y::Int, ch::Char, st::Style)
    contains(area, x, y) && set_char!(buf, x, y, ch, st)
end

# Write `s` starting at (x, y), clipped to `area` and to `maxw` columns, with an
# ellipsis when truncated.
function _dag_text!(buf::Buffer, area::Rect, x::Int, y::Int, s::AbstractString,
                    maxw::Int, st::Style)
    maxw <= 0 && return
    truncated = textwidth(s) > maxw
    limit = truncated ? maxw - 1 : maxw
    cx = x
    for c in s
        w = textwidth(c)
        w == 0 && continue
        cx + w - x > limit && break
        _dag_put!(buf, area, cx, y, c, st)
        cx += w
    end
    truncated && _dag_put!(buf, area, cx, y, '…', st)
end

# Ids of every node upstream (or downstream) of node `i`.
function _dag_reach(nbrs::Vector{Vector{Int}}, i::Int)
    seen = Set{Int}()
    stack = copy(nbrs[i])
    while !isempty(stack)
        u = pop!(stack)
        u in seen && continue
        push!(seen, u)
        append!(stack, nbrs[u])
    end
    seen
end

function render(dv::DAGView, rect::Rect, buf::Buffer)
    area = dv.block === nothing ? rect : render(dv.block, rect, buf)
    dv.last_area = area
    (area.width < 2 || area.height < 2) && return
    lay = _dag_layout!(dv)

    # Scrollbars take a column / row only in the direction the graph overflows.
    sb = dv.show_scrollbars
    need_h = sb && lay.width > area.width
    need_v = sb && lay.height > area.height - need_h
    need_h = sb && lay.width > area.width - need_v
    view = Rect(area.x, area.y, area.width - need_v, area.height - need_h)
    dv.last_area = view

    _dag_apply_anchor!(dv, lay, view)
    if dv._reveal
        _dag_reveal!(dv, lay, view)
        dv._reveal = false
    end
    _dag_clamp_offsets!(dv, lay, view)
    ox, oy = _dag_origin(dv, lay, view)
    dv._origin = (ox, oy)
    isempty(dv.nodes) && return

    # Draw the whole graph on its own canvas, then copy the visible window.
    vr = Rect(1, 1, lay.width, lay.height)
    virt = dv._virt
    if virt === nothing || virt.area != vr
        virt = Buffer(vr)
        dv._virt = virt
    else
        reset!(virt)
    end
    _dag_draw!(dv, lay, virt)
    sx, sy = max(0, view.x - ox), max(0, view.y - oy)
    dx, dy = max(view.x, ox), max(view.y, oy)
    w = min(lay.width - sx, right(view) - dx + 1)
    h = min(lay.height - sy, bottom(view) - dy + 1)
    w > 0 && h > 0 && _blit_cells!(buf, dx, dy, virt, 1 + sx, 1 + sy, w, h)

    need_v && _scrollbar_v!(buf, right(area), view.y, view.height,
                            lay.height, dv.offset_y, lay.height - view.height)
    need_h && _scrollbar_h!(buf, view.x, bottom(area), view.width,
                            lay.width, dv.offset_x, lay.width - view.width)

    # The tooltip is drawn in screen space so it isn't clipped at the graph's edge.
    hn = hovered_node(dv)
    if dv.show_tooltip && hn !== nothing && hn.detail !== nothing
        _dag_tooltip!(dv, lay, hn, view, buf)
    end
    nothing
end

# Draw edges and nodes onto `canvas`, whose area is the graph's own extent.
function _dag_draw!(dv::DAGView, lay::_DagLayout, canvas::Buffer)
    area = canvas.area
    ox, oy = area.x, area.y
    buf = canvas

    # Lineage of the hovered (else selected) node.
    focus_id = dv.hovered !== nothing ? dv.hovered : dv.selected
    fi = focus_id === nothing ? 0 : get(lay.index, focus_id, 0)
    up = fi == 0 ? Set{Int}() : _dag_reach(lay.preds, fi)
    down = fi == 0 ? Set{Int}() : _dag_reach(lay.succs, fi)
    lineage = dv.highlight_lineage && fi > 0
    on_path(u, v) = lineage && (((v == fi || v in up) && u in up) ||
                                ((u == fi || u in down) && v in down))

    edge_st = dv.edge_style === nothing ? tstyle(:border) : dv.edge_style
    hl_st = dv.highlight_style === nothing ? tstyle(:accent, bold=true) : dv.highlight_style
    run_st = tstyle(:primary)

    # ── Edges: merge every edge's cells so junctions get the right glyph ──
    bits = _DagCells()
    cell_st = Dict{Tuple{Int,Int},Int}()          # 0 normal, 1 running, 2 highlighted
    solid = Set{Tuple{Int,Int}}()                 # cells some dependency edge passes through
    for (ei, (u, v)) in enumerate(lay.edges)
        rank = on_path(u, v) ? 2 : dv.nodes[v].status == task_running ? 1 : 0
        for (p, b) in lay.edge_cells[ei]
            bits[p] = get(bits, p, 0x00) | b
            cell_st[p] = max(get(cell_st, p, 0), rank)
            lay.dashed[ei] || push!(solid, p)
        end
    end
    cst(p) = (r = cell_st[p]; r == 2 ? hl_st : r == 1 ? run_st : edge_st)
    for (p, b) in bits
        ch = _DAG_GLYPHS[b+1]
        if !(p in solid)
            ch == '─' && (ch = _DAG_DASH_H)
            ch == '│' && (ch = _DAG_DASH_V)
        end
        _dag_put!(buf, area, ox + p[1], oy + p[2], ch, cst(p))
    end
    for ei in eachindex(lay.edges)
        p = lay.arrows[ei]
        haskey(bits, p) || continue
        _dag_put!(buf, area, ox + p[1], oy + p[2], p in solid ? '▶' : '▷', cst(p))
    end

    # ── Nodes ──
    nw, nh = lay.node_w, lay.node_h
    for (i, nd) in enumerate(dv.nodes)
        bx, by = ox + lay.x[i], oy + lay.y[i]
        sel = nd.id == dv.selected
        hov = nd.id == dv.hovered
        faded = lineage && i != fi && !(i in up) && !(i in down)
        sg, sgst = _dag_status_glyph(nd.status, dv.tick)
        lst = sel ? tstyle(:text_bright, bold=true) :
              hov ? tstyle(:text_bright) :
              faded ? tstyle(:text_dim) : tstyle(:text)
        if nh == 1
            _dag_draw_line_node!(buf, area, dv, nd, bx, by, nw, sel, hov, sg, sgst, lst)
            continue
        end
        box = sel ? BOX_HEAVY : BOX_ROUNDED
        bst = if sel
            dv.focused ? tstyle(:accent, bold=true) : tstyle(:border_focus, bold=true)
        elseif hov
            tstyle(:text_bright, bold=true)
        else
            _dag_status_border(nd.status)
        end
        rx, ry = bx + nw - 1, by + nh - 1
        _dag_put!(buf, area, bx, by, box.tl, bst)
        _dag_put!(buf, area, rx, by, box.tr, bst)
        _dag_put!(buf, area, bx, ry, box.bl, bst)
        _dag_put!(buf, area, rx, ry, box.br, bst)
        for x in bx+1:rx-1
            _dag_put!(buf, area, x, by, box.h, bst)
            _dag_put!(buf, area, x, ry, box.h, bst)
        end
        for y in by+1:ry-1
            _dag_put!(buf, area, bx, y, box.v, bst)
            _dag_put!(buf, area, rx, y, box.v, bst)
        end
        # Outgoing port joins the border
        if !isempty(lay.succs[i])
            _dag_put!(buf, area, rx, oy + lay.port[i], sel ? '┠' : '├', bst)
        end
        # Icon (or status glyph) + label. A node with its own icon shows its
        # status glyph on the top border instead.
        ly = by + 1
        if nd.icon === nothing
            _dag_put!(buf, area, bx + 2, ly, sg, sgst)
            tx = bx + 4
        else
            _dag_put!(buf, area, bx + 2, ly, nd.icon, faded ? tstyle(:text_dim) : tstyle(:secondary))
            tx = bx + 3 + textwidth(nd.icon)
            _dag_put!(buf, area, rx - 3, by, ' ', RESET)
            _dag_put!(buf, area, rx - 2, by, sg, sgst)
            _dag_put!(buf, area, rx - 1, by, ' ', RESET)
        end
        tw = rx - 1 - tx
        _dag_text!(buf, area, tx, ly, nd.label, tw, lst)
        if nh == 4 && !isempty(nd.subtitle)
            _dag_text!(buf, area, tx, by + 2, nd.subtitle, tw, tstyle(:text_dim))
        end
    end
end

# Overview zoom: a node is one line, `glyph label`, with the status glyph in
# place of an icon. The selected node is drawn in reverse.
function _dag_draw_line_node!(buf, area, dv, nd, bx, by, nw, sel, hov, sg, sgst, lst)
    th = theme()
    if sel
        fill_st = Style(fg=th.bg, bg=dv.focused ? th.accent : th.border_focus, bold=true)
        for x in bx:bx+nw-1
            _dag_put!(buf, area, x, by, ' ', fill_st)
        end
        sgst = fill_st
        lst = fill_st
    end
    _dag_put!(buf, area, bx, by, sg, sgst)
    lst = hov && !sel ? Style(fg=lst.fg, bg=lst.bg, bold=lst.bold, underline=true) : lst
    _dag_text!(buf, area, bx + 2, by, nd.label, nw - 2, lst)
end

function _dag_tooltip!(dv::DAGView, lay::_DagLayout, nd::DAGNode, area::Rect, buf::Buffer)
    detail = nd.detail
    para = detail isa Vector{Span} ?
        Paragraph(detail; wrap=word_wrap, show_scrollbar=false) :
        Paragraph(string(detail); wrap=word_wrap, show_scrollbar=false)
    text = detail isa Vector{Span} ? join(s.content for s in detail) : string(detail)
    natural = maximum(textwidth, Base.split(text, '\n'); init=0)
    title_w = textwidth(nd.label) + textwidth(_dag_status_label(nd.status)) + 8
    w = clamp(max(natural, title_w) + 4, 16, max(16, dv.tooltip_width))
    w = min(w, area.width)
    w < 6 && return
    lines = paragraph_line_count(para, w - 4)
    h = min(lines + 2, area.height)
    h < 3 && return

    i = lay.index[nd.id]
    ox, oy = dv._origin
    nx, ny = ox + lay.x[i], oy + lay.y[i]
    # Prefer right of the node, then left, then below, then above.
    x, y = nx + lay.node_w + 1, ny
    if x + w - 1 > right(area)
        x = nx - w - 1
        if x < area.x
            x = nx
            y = ny + lay.node_h
            y + h - 1 > bottom(area) && (y = ny - h)
        end
    end
    x = clamp(x, area.x, right(area) - w + 1)
    y = clamp(y, area.y, bottom(area) - h + 1)
    r = Rect(x, y, w, h)

    for yy in r.y:bottom(r), xx in r.x:right(r)
        set_char!(buf, xx, yy, ' ', RESET)
    end
    _, sst = _dag_status_glyph(nd.status, dv.tick)
    blk = Block(title=nd.label, title_right=_dag_status_label(nd.status),
                title_right_style=sst, border_style=tstyle(:border_focus))
    inner = render(blk, r, buf)
    render(para, Rect(inner.x + 1, inner.y, max(0, inner.width - 2), inner.height), buf)
end

# ── Input ────────────────────────────────────────────────────────────

# Among `cands`, the node whose port row is closest to node `i`'s.
function _dag_nearest(lay::_DagLayout, i::Int, cands)
    isempty(cands) && return 0
    best, bd = 0, typemax(Int)
    for c in cands
        d = abs(lay.port[c] - lay.port[i])
        if d < bd
            best, bd = c, d
        end
    end
    best
end

function handle_key!(dv::DAGView, evt::KeyEvent)::Bool
    isempty(dv.nodes) && return false
    if evt.key == :char
        evt.char in ('+', '=') && return zoom!(dv, 1)
        evt.char in ('-', '_') && return zoom!(dv, -1)
        return false
    end
    evt.key in (:up, :down, :left, :right, :home) || return false
    lay = _dag_layout!(dv)
    i = dv.selected === nothing ? 0 : get(lay.index, dv.selected, 0)
    j = 0
    came = dv._came_from
    dv._came_from = nothing
    if i == 0 || evt.key == :home
        j = first(first(filter(!isempty, lay.layers)))
    elseif evt.key == :up || evt.key == :down
        col = lay.layers[lay.layer[i]]
        k = findfirst(==(i), col)
        k2 = evt.key == :up ? k - 1 : k + 1
        1 <= k2 <= length(col) && (j = col[k2])
    else
        fwd = evt.key == :right
        cands = fwd ? lay.succs[i] : lay.preds[i]
        # Stepping back the way we came returns to where we came from.
        back = came === nothing ? 0 : get(lay.index, came[1], 0)
        if back in cands && came[2] == (fwd ? :left : :right)
            j = back
        else
            j = _dag_nearest(lay, i, cands)
        end
        if j == 0
            # No edge that way: step to the nearest node in the next non-empty column.
            l = lay.layer[i]
            rng = fwd ? (l+1:length(lay.layers)) : (l-1:-1:1)
            for c in rng
                isempty(lay.layers[c]) && continue
                j = _dag_nearest(lay, i, lay.layers[c])
                break
            end
        end
        j != 0 && (dv._came_from = (dv.nodes[i].id, evt.key))
    end
    j == 0 && return false
    dv.selected = dv.nodes[j].id
    dv._reveal = true
    true
end

function handle_mouse!(dv::DAGView, evt::MouseEvent)::Bool
    area = dv.last_area
    inside = contains(area, evt.x, evt.y)

    if evt.action == mouse_move
        dv.hovered = inside ? node_at(dv, evt.x, evt.y) : nothing
        return inside
    end

    # Background drag pans the view.
    if dv._drag !== nothing
        if evt.action == mouse_drag
            x0, y0, ox0, oy0 = dv._drag
            dv.offset_x = ox0 - (evt.x - x0)
            dv.offset_y = oy0 - (evt.y - y0)
            dv._layout === nothing || _dag_clamp_offsets!(dv, dv._layout, area)
            return true
        elseif evt.action == mouse_release
            dv._drag = nothing
            return true
        end
    end

    inside || return false
    wheel = evt.button in (mouse_scroll_up, mouse_scroll_down)
    if wheel && evt.ctrl
        dv.hovered = node_at(dv, evt.x, evt.y)
        zoom!(dv, evt.button == mouse_scroll_up ? 1 : -1)
        return true
    elseif wheel
        d = evt.button == mouse_scroll_up ? -2 : 2
        evt.shift ? (dv.offset_x += 2d) : (dv.offset_y += d)
    elseif evt.button == mouse_scroll_left
        dv.offset_x -= 4
    elseif evt.button == mouse_scroll_right
        dv.offset_x += 4
    elseif evt.button == mouse_left && evt.action == mouse_press
        hit = node_at(dv, evt.x, evt.y)
        if hit !== nothing
            dv.selected = hit
            dv.hovered = hit
            dv._came_from = nothing
        else
            dv._drag = (evt.x, evt.y, dv.offset_x, dv.offset_y)
        end
        return true
    else
        return false
    end
    dv._layout === nothing || _dag_clamp_offsets!(dv, dv._layout, area)
    true
end
