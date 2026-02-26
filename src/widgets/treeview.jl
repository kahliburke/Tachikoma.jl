# ═══════════════════════════════════════════════════════════════════════
# TreeView ── hierarchical tree with expand/collapse
# ═══════════════════════════════════════════════════════════════════════

mutable struct TreeNode
    label::String
    children::Vector{TreeNode}
    expanded::Bool
    style::Style
end

function TreeNode(label::String;
    children=TreeNode[],
    expanded=true,
    style=tstyle(:text),
)
    TreeNode(label, children, expanded, style)
end

function TreeNode(label::String, children::Vector{TreeNode};
    expanded=true, style=tstyle(:text))
    TreeNode(label, children, expanded, style)
end

# Flatten tree into renderable rows (defined before TreeView for cache field)
struct FlatRow
    label::String
    depth::Int
    is_last::Bool          # last child at this depth
    parent_lasts::Vector{Bool}  # whether each ancestor was last
    has_children::Bool
    expanded::Bool
    style::Style
    node::TreeNode         # back-reference for mutation
end

mutable struct TreeView
    root::TreeNode
    selected::Int                  # flattened row index (1-based, 0=none)
    offset::Int                    # scroll offset (0-based)
    focused::Bool
    block::Union{Block, Nothing}
    indent::Int
    connector_style::Style
    selected_style::Style
    show_root::Bool
    tick::Union{Int, Nothing}
    last_area::Rect                # cached content area for mouse hit testing
    _flat_cache::Vector{FlatRow}   # cached flattened rows
    _flat_dirty::Bool              # true when cache needs rebuild
end

"""
    TreeView(root; selected=0, focused=false, tick=nothing, ...)

Hierarchical tree with keyboard navigation. Up/Down to move, Left to collapse/go to parent,
Right to expand/enter child, Enter/Space to toggle.
"""
function TreeView(root::TreeNode;
    selected=0,
    offset=0,
    focused=false,
    block=nothing,
    indent=2,
    connector_style=tstyle(:border, dim=true),
    selected_style=tstyle(:accent, bold=true),
    show_root=true,
    tick=nothing,
)
    TreeView(root, selected, offset, focused, block, indent,
             connector_style, selected_style, show_root, tick, Rect(),
             FlatRow[], true)
end

function flatten_tree(node::TreeNode, show_root::Bool)
    rows = FlatRow[]
    if show_root
        flatten_node!(rows, node, 0, true, Bool[])
    else
        for (i, child) in enumerate(node.children)
            flatten_node!(rows, child, 0, i == length(node.children), Bool[])
        end
    end
    rows
end

function flatten_node!(rows, node, depth, is_last, parent_lasts)
    push!(rows, FlatRow(
        node.label, depth, is_last, copy(parent_lasts),
        !isempty(node.children), node.expanded, node.style, node))
    if node.expanded
        new_lasts = vcat(parent_lasts, is_last)
        for (i, child) in enumerate(node.children)
            flatten_node!(rows, child, depth + 1,
                          i == length(node.children), new_lasts)
        end
    end
end

function _get_flat(tv::TreeView)
    if tv._flat_dirty
        tv._flat_cache = flatten_tree(tv.root, tv.show_root)
        tv._flat_dirty = false
    end
    tv._flat_cache
end

_invalidate_flat!(tv::TreeView) = (tv._flat_dirty = true; nothing)

value(tv::TreeView) = tv.selected

focusable(::TreeView) = true

function handle_key!(tv::TreeView, evt::KeyEvent)::Bool
    flat = _get_flat(tv)
    n = length(flat)
    n == 0 && return false

    if evt.key == :up
        tv.selected = tv.selected > 1 ? tv.selected - 1 : n
    elseif evt.key == :down
        tv.selected = tv.selected < n ? tv.selected + 1 : 1
    elseif evt.key == :home
        tv.selected = 1
    elseif evt.key == :end_key
        tv.selected = n
    elseif evt.key == :left
        # Collapse current node or move to parent
        if tv.selected >= 1 && tv.selected <= n
            row = flat[tv.selected]
            if row.has_children && row.expanded
                row.node.expanded = false
                _invalidate_flat!(tv)
            elseif row.depth > 0
                # Move to parent node
                target_depth = row.depth - 1
                for j in (tv.selected - 1):-1:1
                    if flat[j].depth == target_depth
                        tv.selected = j
                        break
                    end
                end
            end
        end
    elseif evt.key == :right
        # Expand current node or move to first child
        if tv.selected >= 1 && tv.selected <= n
            row = flat[tv.selected]
            if row.has_children && !row.expanded
                row.node.expanded = true
                _invalidate_flat!(tv)
            elseif row.has_children && row.expanded && tv.selected < n
                tv.selected += 1  # move to first child
            end
        end
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        # Toggle expand/collapse
        if tv.selected >= 1 && tv.selected <= n
            row = flat[tv.selected]
            if row.has_children
                row.node.expanded = !row.node.expanded
                _invalidate_flat!(tv)
            end
        end
    else
        return false
    end
    true
end

function render(tv::TreeView, rect::Rect, buf::Buffer)
    content = if tv.block !== nothing
        render(tv.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return
    tv.last_area = content

    flat = _get_flat(tv)
    n = length(flat)
    visible_h = content.height

    # Auto-scroll to keep selection visible
    if tv.selected >= 1
        if tv.selected - 1 < tv.offset
            tv.offset = tv.selected - 1
        elseif tv.selected > tv.offset + visible_h
            tv.offset = tv.selected - visible_h
        end
    end

    max_cx = right(content)
    for i in 1:visible_h
        idx = tv.offset + i
        idx > n && break
        row = flat[idx]
        y = content.y + i - 1

        cx = content.x

        # Draw tree connectors
        if row.depth > 0
            for d in 1:(row.depth - 1)
                if cx <= max_cx && d <= length(row.parent_lasts) && !row.parent_lasts[d]
                    set_char!(buf, cx, y, '│', tv.connector_style)
                end
                cx += tv.indent
            end
            # Branch connector
            if cx <= max_cx
                connector = row.is_last ? '└' : '├'
                set_char!(buf, cx, y, connector, tv.connector_style)
            end
            cx += 1
            if cx <= max_cx
                set_char!(buf, cx, y, '─', tv.connector_style)
            end
            cx += 1
        end

        # Expand/collapse indicator
        if row.has_children && cx <= max_cx
            indicator = row.expanded ? '▾' : '▸'
            set_char!(buf, cx, y, indicator, tv.connector_style)
            cx += 1
        end

        # Label
        cx > max_cx && continue
        style = (tv.selected == idx) ? tv.selected_style : row.style
        if tv.selected == idx
            set_char!(buf, cx, y, ' ', style)
            cx += 1
        end
        set_string!(buf, cx, y, row.label, style; max_x=max_cx)
    end

    # Scroll indicators
    if tv.offset > 0
        set_char!(buf, right(content), content.y, '▲',
                  tstyle(:text_dim))
    end
    if tv.offset + visible_h < n
        set_char!(buf, right(content), bottom(content), '▼',
                  tstyle(:text_dim))
    end
end

# Count visible (flattened) rows
function tree_visible_count(tv::TreeView)
    length(_get_flat(tv))
end

# ── Mouse handling ───────────────────────────────────────────────────

function handle_mouse!(tv::TreeView, evt::MouseEvent)
    Base.contains(tv.last_area, evt.x, evt.y) || return false
    flat = _get_flat(tv)
    n = length(flat)
    visible_h = max(1, tv.last_area.height)

    # Click to select / toggle
    hit = list_hit(evt, tv.last_area, tv.offset, n)
    if hit > 0
        if tv.selected == hit
            # Second click on same row → toggle expand/collapse
            row = flat[hit]
            if row.has_children
                row.node.expanded = !row.node.expanded
                _invalidate_flat!(tv)
            end
        else
            tv.selected = hit
        end
        return true
    end

    # Scroll wheel
    new_offset = list_scroll(evt, tv.offset, n, visible_h)
    if new_offset != tv.offset
        tv.offset = new_offset
        return true
    end

    false
end
