@enum Direction Horizontal Vertical
@enum LayoutAlign layout_start layout_center layout_end layout_space_between layout_space_around layout_space_evenly

abstract type Constraint end

"""Fixed-size constraint in cells."""
struct Fixed   <: Constraint; size::Int; end

"""Minimum-size constraint — takes at least `size` cells, expands if space remains."""
struct Min     <: Constraint; size::Int; end

"""Maximum-size constraint — expands up to `size` cells."""
struct Max     <: Constraint; size::Int; end

"""Percentage of total space."""
struct Percent <: Constraint; pct::Int;  end

"""Fills remaining space. `weight` controls relative proportion when multiple Fills exist."""
struct Fill <: Constraint
    weight::Int
    function Fill(weight::Integer)
        weight >= 0 || throw(ArgumentError("Fill weight must be non-negative, got $weight"))
        new(weight)
    end
end

Fill() = Fill(1)

"""Ratio of total space — `num/den` of the effective total."""
struct Ratio   <: Constraint; num::Int; den::Int; end

Base.show(io::IO, c::Fixed)   = print(io, "Fixed(", c.size, ")")
Base.show(io::IO, c::Min)     = print(io, "Min(", c.size, ")")
Base.show(io::IO, c::Max)     = print(io, "Max(", c.size, ")")
Base.show(io::IO, c::Percent) = print(io, "Percent(", c.pct, ")")
Base.show(io::IO, c::Fill)    = print(io, "Fill(", c.weight, ")")
Base.show(io::IO, c::Ratio)   = print(io, "Ratio(", c.num, ", ", c.den, ")")

struct Layout
    direction::Direction
    constraints::Vector{Constraint}
    align::LayoutAlign
    spacing::Int
end

function Layout(dir::Direction, cs::Vector{Constraint};
                align::LayoutAlign=layout_start, spacing::Int=0)
    Layout(dir, cs, align, spacing)
end

function Layout(dir::Direction, cs::Vector;
                align::LayoutAlign=layout_start, spacing::Int=0)
    Layout(dir, Constraint[c for c in cs], align, spacing)
end

"""
    split_layout(layout::Layout, rect::Rect) → Vector{Rect}

Divide a `Rect` into sub-regions according to the layout's direction and constraints.
"""
function split_layout(layout::Layout, rect::Rect)
    n = length(layout.constraints)
    n == 0 && return Rect[]

    total = layout.direction == Horizontal ? rect.width : rect.height

    # Reserve space for structural spacing between items
    spacing_reserved = max(0, layout.spacing * (n - 1))
    effective_total = max(0, total - spacing_reserved)

    sizes = zeros(Int, n)
    remaining = effective_total
    is_flex = falses(n)

    # Pass 1: resolve definite sizes
    for i in 1:n
        c = layout.constraints[i]
        if c isa Fixed
            sizes[i] = clamp(c.size, 0, remaining)
            remaining -= sizes[i]
        elseif c isa Percent
            sizes[i] = clamp(div(effective_total * c.pct, 100), 0, remaining)
            remaining -= sizes[i]
        elseif c isa Ratio
            sizes[i] = c.den == 0 ? 0 : clamp(div(effective_total * c.num, c.den), 0, remaining)
            remaining -= sizes[i]
        elseif c isa Min
            sizes[i] = clamp(c.size, 0, remaining)
            remaining -= sizes[i]
            is_flex[i] = true
        elseif c isa Fill || c isa Max
            is_flex[i] = true
        end
    end

    # Pass 2: distribute remaining to flex items
    flex_idx = findall(is_flex)
    if !isempty(flex_idx) && remaining > 0
        _distribute_flex!(sizes, layout.constraints, flex_idx, remaining)
    end

    # Compute leftover after all sizes allocated
    used = sum(sizes)
    leftover = max(0, effective_total - used)

    # Build rects with alignment
    rects = Vector{Rect}(undef, n)
    start = layout.direction == Horizontal ? rect.x : rect.y
    pos = start
    for i in 1:n
        at = pos + _align_offset(layout.align, i, n, leftover)
        rects[i] = if layout.direction == Horizontal
            Rect(at, rect.y, sizes[i], rect.height)
        else
            Rect(rect.x, at, rect.width, sizes[i])
        end
        pos += sizes[i] + layout.spacing  # structural gap (can be negative for overlap)
    end
    rects
end

# Share `remaining` among the flex items in proportion to their weights (a Fill's weight,
# 1 for Min and Max). Shares come from cumulative weight, so they sum to `remaining` exactly
# and equal weights differ by at most one cell. A Max whose share exceeds its cap is held at
# the cap and the rest is shared again among the others; capping only raises the others'
# shares, so this settles within one round per Max.
function _distribute_flex!(sizes::Vector{Int}, cs::Vector{Constraint},
                           flex_idx::Vector{Int}, remaining::Int)
    active = copy(flex_idx)
    while !isempty(active) && remaining > 0
        weights = [cs[i] isa Fill ? cs[i].weight : 1 for i in active]
        total_w = sum(weights)
        if total_w == 0               # all zero-weight Fills: split equally
            weights .= 1
            total_w = length(active)
        end
        shares = similar(weights)
        cum = 0
        prev = 0
        for (j, w) in enumerate(weights)
            cum += w
            next = Int(div(widemul(remaining, cum), total_w))
            shares[j] = next - prev
            prev = next
        end
        capped = [j for (j, i) in enumerate(active)
                  if cs[i] isa Max && shares[j] > max(0, cs[i].size)]
        if isempty(capped)
            for (j, i) in enumerate(active)
                sizes[i] += shares[j]
            end
            return sizes
        end
        for j in capped
            i = active[j]
            cap = max(0, cs[i].size)
            sizes[i] += cap
            remaining -= cap
        end
        deleteat!(active, capped)
    end
    sizes
end

# Offset of item `i` of `n` from its packed position, placing `leftover` cells per `align`.
# Each offset is computed directly rather than accumulated, so the last item never passes
# the end of the area.
function _align_offset(align::LayoutAlign, i::Int, n::Int, leftover::Int)
    leftover > 0 || return 0
    align == layout_center && return leftover ÷ 2
    align == layout_end && return leftover
    align == layout_space_between && return n > 1 ? round(Int, (i - 1) * leftover / (n - 1)) : 0
    align == layout_space_around &&
        return round(Int, leftover / (2n)) + round(Int, (i - 1) * leftover / n)
    align == layout_space_evenly &&
        return round(Int, leftover / (n + 1)) + round(Int, (i - 1) * leftover / (n + 1))
    return 0
end

# Backward compat alias
split(layout::Layout, rect::Rect) = split_layout(layout, rect)

"""
    split_with_spacers(layout::Layout, rect::Rect) → (Vector{Rect}, Vector{Rect})

Like `split_layout`, but also returns N+1 spacer rects: a leading edge spacer,
one between each item pair, and a trailing edge spacer. Edge spacers have zero
width/height when items fill the entire space.
"""
function split_with_spacers(layout::Layout, rect::Rect)
    rects = split_layout(layout, rect)
    n = length(rects)
    n == 0 && return (rects, Rect[])
    horiz = layout.direction == Horizontal
    spacers = Vector{Rect}(undef, n + 1)

    # Leading edge spacer
    if horiz
        w = max(0, rects[1].x - rect.x)
        spacers[1] = Rect(rect.x, rect.y, w, rect.height)
    else
        h = max(0, rects[1].y - rect.y)
        spacers[1] = Rect(rect.x, rect.y, rect.width, h)
    end

    # Between-item spacers
    for i in 1:(n - 1)
        if horiz
            sx = right(rects[i]) + 1
            w = max(0, rects[i + 1].x - sx)
            spacers[i + 1] = Rect(sx, rect.y, w, rect.height)
        else
            sy = bottom(rects[i]) + 1
            h = max(0, rects[i + 1].y - sy)
            spacers[i + 1] = Rect(rect.x, sy, rect.width, h)
        end
    end

    # Trailing edge spacer
    if horiz
        tx = right(rects[n]) + 1
        w = max(0, right(rect) - tx + 1)
        spacers[n + 1] = Rect(tx, rect.y, w, rect.height)
    else
        ty = bottom(rects[n]) + 1
        h = max(0, bottom(rect) - ty + 1)
        spacers[n + 1] = Rect(rect.x, ty, rect.width, h)
    end

    (rects, spacers)
end

# ═══════════════════════════════════════════════════════════════════════
# ResizableLayout ── drag pane borders to resize
# ═══════════════════════════════════════════════════════════════════════

@enum DragStatus drag_idle drag_active drag_swap

mutable struct DragState
    status::DragStatus
    border_index::Int              # which border (1 = between pane 1 and 2)
    start_pos::Int                 # mouse position at drag start
    start_sizes::Vector{Int}       # pane sizes snapshot at drag start
    start_constraints::Vector{Constraint}  # constraint snapshot at drag start
    source_pane::Int               # pane index where swap-drag started
end

DragState() = DragState(drag_idle, 0, 0, Int[], Constraint[], 0)

mutable struct ResizableLayout
    direction::Direction
    original_direction::Direction
    original_constraints::Vector{Constraint}
    constraints::Vector{Constraint}
    rects::Vector{Rect}        # cached from last split_layout
    last_area::Rect
    drag::DragState
    min_pane_size::Int         # default 3
    hover_border::Int          # 0 = none, >0 = hovered border index
end

function ResizableLayout(dir::Direction, constraints::Vector{<:Constraint};
                         min_pane_size::Int=3)
    cs = Constraint[c for c in constraints]
    ResizableLayout(dir, dir, copy(cs), cs, Rect[], Rect(), DragState(),
                    min_pane_size, 0)
end

function ResizableLayout(dir::Direction, constraints::Vector; min_pane_size::Int=3)
    ResizableLayout(dir, Constraint[c for c in constraints]; min_pane_size)
end

function split_layout(rl::ResizableLayout, rect::Rect)
    layout = Layout(rl.direction, rl.constraints)
    rl.rects = split_layout(layout, rect)
    rl.last_area = rect
    rl.rects
end

function reset_layout!(rl::ResizableLayout)
    rl.constraints = copy(rl.original_constraints)
    rl.drag = DragState()
    rl.hover_border = 0
    nothing
end

# ── Internal helpers ──────────────────────────────────────────────────

function _current_sizes(rl::ResizableLayout)
    [rl.direction == Horizontal ? r.width : r.height for r in rl.rects]
end

function _find_border(rl::ResizableLayout, pos::Int)
    isempty(rl.rects) && return 0
    for i in 1:(length(rl.rects) - 1)
        border_pos = if rl.direction == Horizontal
            right(rl.rects[i])
        else
            bottom(rl.rects[i])
        end
        abs(pos - border_pos) <= 1 && return i
    end
    return 0
end

function _apply_delta!(rl::ResizableLayout, border_idx::Int, delta::Int,
                       sizes::Vector{Int})
    delta == 0 && return
    n = length(rl.constraints)
    (border_idx < 1 || border_idx >= n) && return

    left_c = rl.constraints[border_idx]
    right_c = rl.constraints[border_idx + 1]

    new_left = sizes[border_idx] + delta
    new_right = sizes[border_idx + 1] - delta

    # Enforce min pane size
    if new_left < rl.min_pane_size
        delta = rl.min_pane_size - sizes[border_idx]
        new_left = rl.min_pane_size
        new_right = sizes[border_idx + 1] - delta
    end
    if new_right < rl.min_pane_size
        delta = sizes[border_idx + 1] - rl.min_pane_size
        new_left = sizes[border_idx] + delta
        new_right = rl.min_pane_size
    end

    new_left < rl.min_pane_size && return
    new_right < rl.min_pane_size && return

    if left_c isa Fixed && right_c isa Fixed
        rl.constraints[border_idx] = Fixed(new_left)
        rl.constraints[border_idx + 1] = Fixed(new_right)
    elseif left_c isa Fixed && right_c isa Fill
        rl.constraints[border_idx] = Fixed(new_left)
    elseif left_c isa Fill && right_c isa Fixed
        rl.constraints[border_idx + 1] = Fixed(new_right)
    elseif left_c isa Fill && right_c isa Fill
        rl.constraints[border_idx] = Fixed(new_left)
        rl.constraints[border_idx + 1] = Fixed(new_right)
    elseif left_c isa Percent && right_c isa Percent
        total_pct = left_c.pct + right_c.pct
        total_px = sizes[border_idx] + sizes[border_idx + 1]
        total_px > 0 || return
        new_left_pct = clamp(round(Int, new_left / total_px * total_pct), 1, total_pct - 1)
        rl.constraints[border_idx] = Percent(new_left_pct)
        rl.constraints[border_idx + 1] = Percent(total_pct - new_left_pct)
    elseif left_c isa Percent && right_c isa Fill
        # Convert Percent to Fixed so Fill continues to absorb remaining space
        rl.constraints[border_idx] = Fixed(new_left)
    elseif left_c isa Fill && right_c isa Percent
        rl.constraints[border_idx + 1] = Fixed(new_right)
    else
        # Other combos: convert both to Fixed
        rl.constraints[border_idx] = Fixed(new_left)
        rl.constraints[border_idx + 1] = Fixed(new_right)
    end
    nothing
end

function _find_pane(rl::ResizableLayout, x::Int, y::Int)
    for i in eachindex(rl.rects)
        Base.contains(rl.rects[i], x, y) && return i
    end
    return 0
end

function _swap_panes!(rl::ResizableLayout, a::Int, b::Int)
    (a < 1 || b < 1 || a > length(rl.constraints) || b > length(rl.constraints)) && return
    a == b && return
    rl.constraints[a], rl.constraints[b] = rl.constraints[b], rl.constraints[a]
    nothing
end

function _rotate_direction!(rl::ResizableLayout)
    rl.direction = rl.direction == Horizontal ? Vertical : Horizontal
    nothing
end

function _reset_layout!(rl::ResizableLayout)
    rl.direction = rl.original_direction
    rl.constraints = copy(rl.original_constraints)
    nothing
end

# Mouse-dependent methods (handle_resize!, render_resize_handles!) are in
# resizable_layout.jl, included after events.jl

# ═══════════════════════════════════════════════════════════════════════
# Layout persistence via Preferences.jl
# ═══════════════════════════════════════════════════════════════════════

function _serialize_constraint(c::Constraint)
    c isa Fixed   && return "F$(c.size)"
    c isa Fill    && return "L$(c.weight)"
    c isa Percent && return "P$(c.pct)"
    c isa Min     && return "N$(c.size)"
    c isa Max     && return "X$(c.size)"
    c isa Ratio   && return "R$(c.num)/$(c.den)"
    error("Unknown constraint type: $(typeof(c))")
end

function _deserialize_constraint(s::AbstractString)
    isempty(s) && error("Empty constraint string")
    tag = s[1]
    if tag == 'R'
        parts = Base.split(s[2:end], '/')
        return Ratio(parse(Int, parts[1]), parse(Int, parts[2]))
    end
    val = parse(Int, s[2:end])
    tag == 'F' && return Fixed(val)
    tag == 'L' && return Fill(val)
    tag == 'P' && return Percent(val)
    tag == 'N' && return Min(val)
    tag == 'X' && return Max(val)
    error("Unknown constraint tag: $tag")
end

function _serialize_constraints(cs::Vector{Constraint})
    join((_serialize_constraint(c) for c in cs), ",")
end

function _deserialize_constraints(s::AbstractString)
    isempty(s) && return Constraint[]
    Constraint[_deserialize_constraint(p) for p in Base.split(s, ",")]
end

function _layout_fingerprint(rl::ResizableLayout)
    dir_char = rl.original_direction == Horizontal ? "H" : "V"
    string(dir_char, "|", _serialize_constraints(rl.original_constraints))
end

function _save_layout_pref!(model_type::String, field_name::String, rl::ResizableLayout)
    key_dir = "layout_$(model_type)_$(field_name)_dir"
    key_cs = "layout_$(model_type)_$(field_name)_cs"
    key_orig = "layout_$(model_type)_$(field_name)_orig"
    dir_str = rl.direction == Horizontal ? "Horizontal" : "Vertical"
    cs_str = _serialize_constraints(rl.constraints)
    orig_str = _layout_fingerprint(rl)
    Preferences.set_preferences!(@__MODULE__,
        key_dir => dir_str, key_cs => cs_str, key_orig => orig_str; force=true)
    nothing
end

function _load_layout_pref!(model_type::String, field_name::String, rl::ResizableLayout)
    key_dir = "layout_$(model_type)_$(field_name)_dir"
    key_cs = "layout_$(model_type)_$(field_name)_cs"
    key_orig = "layout_$(model_type)_$(field_name)_orig"
    expected_fp = _layout_fingerprint(rl)
    stored_fp = Preferences.load_preference(@__MODULE__, key_orig, "")
    stored_fp == expected_fp || return false
    dir_str = Preferences.load_preference(@__MODULE__, key_dir, "")
    cs_str = Preferences.load_preference(@__MODULE__, key_cs, "")
    (isempty(dir_str) || isempty(cs_str)) && return false
    try
        dir = dir_str == "Horizontal" ? Horizontal : Vertical
        cs = _deserialize_constraints(cs_str)
        length(cs) == length(rl.constraints) || return false
        rl.direction = dir
        rl.constraints = cs
        return true
    catch
        return false
    end
end

function _save_layout_prefs!(model)
    model_type = string(nameof(typeof(model)))
    for fname in fieldnames(typeof(model))
        ftype = fieldtype(typeof(model), fname)
        ftype === ResizableLayout || continue
        _save_layout_pref!(model_type, string(fname), getfield(model, fname))
    end
    nothing
end

function _load_layout_prefs!(model)
    model_type = string(nameof(typeof(model)))
    for fname in fieldnames(typeof(model))
        ftype = fieldtype(typeof(model), fname)
        ftype === ResizableLayout || continue
        _load_layout_pref!(model_type, string(fname), getfield(model, fname))
    end
    nothing
end
