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
struct Fill    <: Constraint; weight::Int; end

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
        total_w = sum(
            layout.constraints[i] isa Fill ?
                layout.constraints[i].weight : 1
            for i in flex_idx
        )
        for (j, i) in enumerate(flex_idx)
            c = layout.constraints[i]
            w = c isa Fill ? c.weight : 1
            share = j == length(flex_idx) ? remaining :
                    div(remaining * w, total_w)
            c isa Max && (share = min(share, c.size))
            sizes[i] += share
            remaining -= share
        end
    end

    # Compute leftover after all sizes allocated
    used = sum(sizes)
    leftover = max(0, effective_total - used)

    # Build rects with alignment
    rects = Vector{Rect}(undef, n)
    pos = layout.direction == Horizontal ? rect.x : rect.y
    align = layout.align

    # Pre-offset for alignment
    if align == layout_center
        pos += leftover ÷ 2
    elseif align == layout_end
        pos += leftover
    elseif align == layout_space_around && n > 0 && leftover > 0
        pos += round(Int, leftover / (2n))
    elseif align == layout_space_evenly && n > 0 && leftover > 0
        pos += round(Int, leftover / (n + 1))
    end

    # Between-item alignment gap
    align_gap = 0.0
    is_gap_align = align in (layout_space_between, layout_space_around, layout_space_evenly)
    if is_gap_align && n > 1 && leftover > 0
        if align == layout_space_between
            align_gap = leftover / (n - 1)
        elseif align == layout_space_around
            align_gap = leftover / n
        elseif align == layout_space_evenly
            align_gap = leftover / (n + 1)
        end
    end

    gap_accum = 0.0
    for i in 1:n
        rects[i] = if layout.direction == Horizontal
            Rect(pos, rect.y, sizes[i], rect.height)
        else
            Rect(rect.x, pos, rect.width, sizes[i])
        end
        pos += sizes[i]
        if i < n
            pos += layout.spacing  # structural gap (can be negative for overlap)
            if is_gap_align && leftover > 0
                gap_accum += align_gap
                int_gap = round(Int, gap_accum) - round(Int, gap_accum - align_gap)
                pos += int_gap
            end
        end
    end
    rects
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
