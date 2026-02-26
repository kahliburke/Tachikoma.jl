# ═══════════════════════════════════════════════════════════════════════
# Phylogenetic Tree ── radial tree background texture
#
# Branches radiate outward from a center point in a circular pattern.
# Deterministic tree generation from seed using noise().  Rendered as
# braille dots with depth-based coloring and animated sway/rotation.
# ═══════════════════════════════════════════════════════════════════════

struct PhyloBranch
    start_angle::Float64     # angle at parent junction
    end_angle::Float64       # angle at tip
    start_radius::Float64    # normalized 0-1 distance from center
    end_radius::Float64
    depth::Int               # 0=trunk
    sway_seed::Float64       # unique per-branch for animation
end

struct PhyloTree
    branches::Vector{PhyloBranch}
    max_depth::Int
end

struct PhyloTreePreset
    name::String
    seed::Int
    n_main::Int              # primary radiating branches (3-8)
    max_depth::Int           # branching depth (3-5)
    branch_ratio::Float64    # child length / parent length
    angle_spread::Float64    # angular divergence per split (radians)
    sway_amount::Float64     # sway animation amplitude
    rotation_speed::Float64  # global rotation speed
end

const PHYLO_PRESETS = PhyloTreePreset[
    PhyloTreePreset("Radial",     42,  6, 4, 0.55, 0.45, 0.03, 0.008),
    PhyloTreePreset("Dense",      17,  8, 5, 0.50, 0.30, 0.02, 0.006),
    PhyloTreePreset("Sparse",     91,  4, 3, 0.60, 0.65, 0.05, 0.012),
    PhyloTreePreset("Asymmetric", 73,  5, 4, 0.52, 0.50, 0.04, 0.010),
]

# ── Tree generation ─────────────────────────────────────────────────

function _generate_phylo_tree(preset::PhyloTreePreset)
    branches = PhyloBranch[]
    seed = Float64(preset.seed)

    # Root branches evenly spaced with noise jitter
    base_step = 2π / preset.n_main
    for i in 1:preset.n_main
        angle = base_step * (i - 1) + (noise(seed + i * 7.13) - 0.5) * base_step * 0.4
        length_frac = 0.25 + 0.10 * noise(seed + i * 3.71)
        sway = noise(seed + i * 11.37) * 100.0
        push!(branches, PhyloBranch(angle, angle, 0.0, length_frac, 0, sway))
        _split_branch!(branches, preset, angle, length_frac, 1, seed + i * 13.17)
    end
    PhyloTree(branches, preset.max_depth)
end

function _split_branch!(branches::Vector{PhyloBranch}, preset::PhyloTreePreset,
                         parent_angle::Float64, parent_end_r::Float64,
                         depth::Int, seed::Float64)
    depth > preset.max_depth && return

    # Binary split: two children diverge from parent tip
    for side in (-1, 1)
        spread_noise = 0.7 + 0.6 * noise(seed + side * 5.23)
        child_angle = parent_angle + side * preset.angle_spread * spread_noise
        child_length = parent_end_r * preset.branch_ratio * (0.8 + 0.4 * noise(seed + side * 9.41))
        child_end_r = parent_end_r + child_length
        child_end_r > 0.95 && (child_end_r = 0.95)
        child_end_r <= parent_end_r && continue

        sway = noise(seed + side * 17.59 + depth * 3.0) * 100.0
        push!(branches, PhyloBranch(parent_angle, child_angle,
                                     parent_end_r, child_end_r, depth, sway))
        _split_branch!(branches, preset, child_angle, child_end_r,
                        depth + 1, seed + side * 23.71 + depth * 7.13)
    end
end

# ── Bresenham line into braille dot grid ────────────────────────────

function _phylo_line!(dots::Matrix{UInt8}, cell_depth::Matrix{Float64},
                       x0::Int, y0::Int, x1::Int, y1::Int,
                       depth_val::Float64, dot_w::Int, dot_h::Int,
                       cw::Int, ch::Int, ub::Bool)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx - dy
    while true
        if 0 <= x0 < dot_w && 0 <= y0 < dot_h
            cx = x0 ÷ 2 + 1
            cy = _dot_cy(y0, ub)
            if 1 <= cx <= cw && 1 <= cy <= ch
                dots[cx, cy] |= _dot_bit(x0 % 2, _dot_sub_y(y0, ub), ub)
                cell_depth[cx, cy] = depth_val
            end
        end
        (x0 == x1 && y0 == y1) && break
        e2 = 2 * err
        if e2 > -dy
            err -= dy
            x0 += sx
        end
        if e2 < dx
            err += dx
            y0 += sy
        end
    end
end

# ── Rendering ───────────────────────────────────────────────────────

function _render_phylo_tree!(buf::Buffer, area::Rect, tick::Int,
                              tree::PhyloTree, preset::PhyloTreePreset;
                              color_transform::Function=identity)
    cw = area.width
    ch = area.height
    (cw < 4 || ch < 2) && return

    ub = _use_block_backend()
    dot_w = cw * 2
    dot_h = ch * _dots_per_h(ub)

    dots = zeros(UInt8, cw, ch)
    cell_depth = ones(Float64, cw, ch)   # 1=deepest/dimmest

    # Aspect correction: terminal chars are roughly 2:1 tall:wide
    aspect = 2.0

    # Center in dot-space
    cx_dot = dot_w / 2.0
    cy_dot = dot_h / 2.0

    # Radius in dot-space (fit to smaller dimension, aspect-corrected)
    radius = min(dot_w / aspect, Float64(dot_h)) * 0.45

    # Global rotation
    rotation = Float64(tick) * preset.rotation_speed

    max_d = Float64(max(tree.max_depth, 1))

    # Draw order: trunk first → tips last (tips overwrite depth info)
    for branch in tree.branches
        d = branch.depth
        depth_frac = Float64(d) / max_d  # 0=trunk, 1=tips

        # Per-branch sway: deeper branches sway more
        sway = 0.0
        if animations_enabled()
            sway = (noise(branch.sway_seed + tick * 0.02) - 0.5) *
                    preset.sway_amount * (1.0 + depth_frac * 2.0)
        end

        sa = branch.start_angle + rotation + sway
        ea = branch.end_angle + rotation + sway

        # Convert polar → dot-space coordinates
        x0 = round(Int, cx_dot + cos(sa) * branch.start_radius * radius * aspect)
        y0 = round(Int, cy_dot + sin(sa) * branch.start_radius * radius)
        x1 = round(Int, cx_dot + cos(ea) * branch.end_radius * radius * aspect)
        y1 = round(Int, cy_dot + sin(ea) * branch.end_radius * radius)

        depth_val = 1.0 - depth_frac  # tips → 0 (brighter later)

        # Branch thickness: depth 0 = 3 parallel lines, depth 1 = 2, deeper = 1
        if d == 0
            for offset in -1:1
                ox = round(Int, -sin(ea) * offset)
                oy = round(Int, cos(ea) * offset)
                _phylo_line!(dots, cell_depth, x0 + ox, y0 + oy,
                              x1 + ox, y1 + oy, depth_val, dot_w, dot_h, cw, ch, ub)
            end
        elseif d == 1
            _phylo_line!(dots, cell_depth, x0, y0, x1, y1,
                          depth_val, dot_w, dot_h, cw, ch, ub)
            ox = round(Int, -sin(ea))
            oy = round(Int, cos(ea))
            _phylo_line!(dots, cell_depth, x0 + ox, y0 + oy,
                          x1 + ox, y1 + oy, depth_val, dot_w, dot_h, cw, ch, ub)
        else
            _phylo_line!(dots, cell_depth, x0, y0, x1, y1,
                          depth_val, dot_w, dot_h, cw, ch, ub)
        end
    end

    # ── Render chars with depth-based coloring ──
    th = theme()
    colors = (th.primary, th.accent, th.secondary)

    for cy in 1:ch
        for cx in 1:cw
            bits = dots[cx, cy]
            bits == 0x00 && continue
            ch_char = _dot_char(bits, ub)

            bx = area.x + cx - 1
            by = area.y + cy - 1

            z = cell_depth[cx, cy]  # 0=tip (bright), 1=trunk (dim)

            base_fg = color_wave(tick, cx + cy, colors; speed=0.03, spread=0.12)

            # Tips brighter, trunk dimmer
            brightness = 0.4 + (1.0 - z) * 0.5

            # Shimmer on leaf tips (low depth value = tip)
            if z < 0.3
                s = shimmer(tick, cx; speed=0.06, scale=0.2)
                brightness += s * 0.2
            end

            fg = dim_color(base_fg, 1.0 - clamp(brightness, 0.0, 1.0))
            fg = color_transform(fg)

            set_char!(buf, bx, by, ch_char, Style(fg=fg))
        end
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Cladogram ── radial fan-layout phylogenetic tree
#
# Right-angle routing in polar coordinates: arcs at constant radius
# connect to radial lines at constant angle, producing the classic
# cladogram "elbow" pattern.  Trait value evolves along branches for
# smooth color gradients (inspired by Phylo.jl :fan layout).
# ═══════════════════════════════════════════════════════════════════════

# ── Structs ────────────────────────────────────────────────────────────

"""
A drawable segment of a radial cladogram.

* **Arc** (`radius1 ≈ radius2`): sweep from `angle1` to `angle2` at constant radius.
* **Radial** (`angle1 ≈ angle2`): extend from `radius1` to `radius2` at constant angle.

`trait` is a 0–1 value that evolves along branches for coloring.
"""
struct CladoBranch
    angle1::Float64
    angle2::Float64
    radius1::Float64     # normalized 0-1
    radius2::Float64
    depth::Int
    trait::Float64       # 0-1, evolved along tree for coloring
    sway_seed::Float64
end

struct CladoTree
    branches::Vector{CladoBranch}
    max_depth::Int
    n_clades::Int
end

struct CladoPreset
    name::String
    seed::Int
    n_main::Int          # top-level clade count
    max_depth::Int
    prune_prob::Float64  # probability of early branch termination
    gap_fraction::Float64 # fraction of 2π reserved as inter-clade gaps
    sway_amount::Float64
    rotation_speed::Float64
    split_min::Float64   # minimum split fraction (lower = more asymmetric)
end

const CLADO_PRESETS = CladoPreset[
    CladoPreset("Fan",        42,  6, 5, 0.08, 0.04, 0.025, 0.006, 0.30),
    CladoPreset("Dense Fan",  17,  8, 6, 0.04, 0.02, 0.015, 0.004, 0.30),
    CladoPreset("Sparse Fan", 91,  4, 4, 0.18, 0.08, 0.040, 0.010, 0.30),
    CladoPreset("Lopsided",   73,  5, 5, 0.22, 0.05, 0.030, 0.008, 0.20),
    CladoPreset("Organic",    59,  7, 6, 0.12, 0.03, 0.025, 0.007, 0.10),
]

# ── Radius helper ──────────────────────────────────────────────────────

const _CLADO_R_MIN = 0.06
const _CLADO_R_MAX = 0.93

@inline function _clado_radius(depth::Int, max_depth::Int)
    _CLADO_R_MIN + (_CLADO_R_MAX - _CLADO_R_MIN) * Float64(depth) / Float64(max_depth)
end

# ── Tree generation ────────────────────────────────────────────────────

function _generate_clado_tree(preset::CladoPreset)
    branches = CladoBranch[]
    seed = Float64(preset.seed)
    n = preset.n_main
    gap_total = 2π * preset.gap_fraction
    gap_each = n > 0 ? gap_total / n : 0.0
    available = n > 0 ? 2π - gap_total : 2π

    # Noise-weighted clade sizes for natural asymmetry
    weights = Float64[0.5 + noise(seed + i * 19.37) for i in 1:n]
    total_w = sum(weights)

    r0 = _CLADO_R_MIN * 0.5
    r1 = _clado_radius(1, preset.max_depth)

    cum_angle = gap_each / 2
    for i in 1:n
        clade_span = available * weights[i] / total_w
        jitter = (noise(seed + i * 7.13) - 0.5) * gap_each * 0.3
        a_min = cum_angle + jitter
        a_max = a_min + clade_span
        mid = (a_min + a_max) / 2
        sway = noise(seed + i * 11.37) * 100.0
        trait0 = Float64(i - 1) / Float64(max(n, 1))

        # Trunk: center → first branch level
        push!(branches, CladoBranch(mid, mid, r0, r1, 0, trait0, sway))

        _build_clado!(branches, preset, a_min, a_max,
                      1, trait0, seed + i * 37.91)

        cum_angle += clade_span + gap_each
    end

    CladoTree(branches, preset.max_depth, n)
end

function _build_clado!(branches::Vector{CladoBranch}, preset::CladoPreset,
                       a_min::Float64, a_max::Float64,
                       depth::Int, parent_trait::Float64, seed::Float64)
    depth > preset.max_depth && return

    r_here  = _clado_radius(depth, preset.max_depth)
    r_child = _clado_radius(min(depth + 1, preset.max_depth), preset.max_depth)
    span = a_max - a_min

    # Evolve trait: parent ± noise
    trait = clamp(parent_trait + (noise(seed + 41.0) - 0.5) * 0.15, 0.0, 1.0)
    sway = noise(seed + 17.59) * 100.0

    # Leaf / narrow span → terminal tick
    if span < 0.015 || depth >= preset.max_depth
        mid = (a_min + a_max) / 2
        tip_r = min(r_here + (_CLADO_R_MAX - r_here) * 0.45, 0.96)
        push!(branches, CladoBranch(mid, mid, r_here, tip_r,
                                     depth, trait, sway))
        return
    end

    # Pruning
    if depth > 1 && noise(seed + 99.0) < preset.prune_prob
        mid = (a_min + a_max) / 2
        push!(branches, CladoBranch(mid, mid, r_here, r_child,
                                     depth, trait, sway))
        return
    end

    # Binary split (split_min controls asymmetry: lower = more uneven)
    smin = preset.split_min
    sfrac = smin + (1.0 - 2.0 * smin) * noise(seed + 5.23)
    split_a = a_min + span * sfrac
    left_mid  = (a_min + split_a) / 2
    right_mid = (split_a + a_max) / 2

    # Arc at this radius connecting children
    push!(branches, CladoBranch(left_mid, right_mid, r_here, r_here,
                                 depth, trait, sway))
    # Radial: left child
    push!(branches, CladoBranch(left_mid, left_mid, r_here, r_child,
                                 depth, trait, sway + 1.0))
    # Radial: right child
    push!(branches, CladoBranch(right_mid, right_mid, r_here, r_child,
                                 depth, trait, sway + 2.0))

    # Evolve trait independently for each subtree
    trait_l = clamp(trait + (noise(seed + 61.0) - 0.5) * 0.12, 0.0, 1.0)
    trait_r = clamp(trait + (noise(seed + 71.0) - 0.5) * 0.12, 0.0, 1.0)

    _build_clado!(branches, preset, a_min, split_a,
                  depth + 1, trait_l, seed + 23.71)
    _build_clado!(branches, preset, split_a, a_max,
                  depth + 1, trait_r, seed + 31.41)
end

# ── Drawing primitives ─────────────────────────────────────────────────

@inline function _clado_dot!(dots::Matrix{UInt8}, cell_depth::Matrix{Float64},
                              cell_trait::Matrix{Float64},
                              x::Int, y::Int, dv::Float64, tv::Float64,
                              dot_w::Int, dot_h::Int, cw::Int, ch::Int,
                              ub::Bool)
    (0 <= x < dot_w && 0 <= y < dot_h) || return
    cx = x ÷ 2 + 1
    cy = _dot_cy(y, ub)
    (1 <= cx <= cw && 1 <= cy <= ch) || return
    dots[cx, cy] |= _dot_bit(x % 2, _dot_sub_y(y, ub), ub)
    cell_depth[cx, cy] = dv
    cell_trait[cx, cy] = tv
end

function _clado_bresenham!(dots::Matrix{UInt8}, cell_depth::Matrix{Float64},
                            cell_trait::Matrix{Float64},
                            x0::Int, y0::Int, x1::Int, y1::Int,
                            dv::Float64, tv::Float64,
                            dot_w::Int, dot_h::Int, cw::Int, ch::Int,
                            ub::Bool)
    dx = abs(x1 - x0); dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1; sy = y0 < y1 ? 1 : -1
    err = dx - dy
    while true
        _clado_dot!(dots, cell_depth, cell_trait, x0, y0, dv, tv,
                     dot_w, dot_h, cw, ch, ub)
        (x0 == x1 && y0 == y1) && break
        e2 = 2 * err
        if e2 > -dy; err -= dy; x0 += sx; end
        if e2 < dx;  err += dx; y0 += sy; end
    end
end

function _clado_arc!(dots::Matrix{UInt8}, cell_depth::Matrix{Float64},
                      cell_trait::Matrix{Float64},
                      cx_d::Float64, cy_d::Float64,
                      r::Float64, a1::Float64, a2::Float64,
                      aspect::Float64, dv::Float64, tv::Float64,
                      dot_w::Int, dot_h::Int, cw::Int, ch::Int,
                      ub::Bool)
    arc_px = abs(a2 - a1) * r * max(aspect, 1.0)
    n = max(4, round(Int, arc_px * 1.5))
    for i in 0:n
        t = Float64(i) / Float64(n)
        a = a1 + (a2 - a1) * t
        x = round(Int, cx_d + cos(a) * r * aspect)
        y = round(Int, cy_d + sin(a) * r)
        _clado_dot!(dots, cell_depth, cell_trait, x, y, dv, tv,
                     dot_w, dot_h, cw, ch, ub)
    end
end

# ── Main renderer ──────────────────────────────────────────────────────

const generate_phylo_tree = _generate_phylo_tree
const render_phylo_tree! = _render_phylo_tree!

function _render_clado_tree!(buf::Buffer, area::Rect, tick::Int,
                              tree::CladoTree, preset::CladoPreset;
                              color_transform::Function=identity)
    cw = area.width; ch = area.height
    (cw < 4 || ch < 2) && return

    ub = _use_block_backend()
    dot_w = cw * 2; dot_h = ch * _dots_per_h(ub)
    dots       = zeros(UInt8, cw, ch)
    cell_depth = ones(Float64, cw, ch)
    cell_trait = zeros(Float64, cw, ch)

    aspect = 2.0
    cx_d = dot_w / 2.0
    cy_d = dot_h / 2.0
    radius = min(dot_w / aspect, Float64(dot_h)) * 0.45

    rotation = Float64(tick) * preset.rotation_speed
    max_d = Float64(max(tree.max_depth, 1))

    for br in tree.branches
        df = Float64(br.depth) / max_d
        sway = 0.0
        if animations_enabled()
            sway = (noise(br.sway_seed + tick * 0.02) - 0.5) *
                    preset.sway_amount * (1.0 + df * 2.0)
        end

        a1 = br.angle1 + rotation + sway
        a2 = br.angle2 + rotation + sway
        r1 = br.radius1 * radius
        r2 = br.radius2 * radius
        dv = 1.0 - df   # root=1 (dim), tips=0 (bright)
        tv = br.trait

        is_arc = abs(br.radius1 - br.radius2) < 1e-8

        # Thickness: trunk=3, depth 1=2, deeper=1
        offsets = br.depth == 0 ? (-1:1) : (br.depth == 1 ? (0:1) : (0:0))

        if is_arc
            for off in offsets
                _clado_arc!(dots, cell_depth, cell_trait,
                           cx_d, cy_d, r1 + Float64(off),
                           a1, a2, aspect, dv, tv,
                           dot_w, dot_h, cw, ch, ub)
            end
        else
            for off in offsets
                perp_x = -sin(a1) * Float64(off)
                perp_y =  cos(a1) * Float64(off)
                x0 = round(Int, cx_d + cos(a1) * r1 * aspect + perp_x)
                y0 = round(Int, cy_d + sin(a1) * r1 + perp_y)
                x1 = round(Int, cx_d + cos(a1) * r2 * aspect + perp_x)
                y1 = round(Int, cy_d + sin(a1) * r2 + perp_y)
                _clado_bresenham!(dots, cell_depth, cell_trait,
                                   x0, y0, x1, y1, dv, tv,
                                   dot_w, dot_h, cw, ch, ub)
            end
        end
    end

    # ── Render chars with trait-based color ──
    th = theme()
    primary = to_rgb(th.primary)
    accent  = to_rgb(th.accent)

    for cy in 1:ch
        for cx in 1:cw
            bits = dots[cx, cy]
            bits == 0x00 && continue

            bx = area.x + cx - 1
            by = area.y + cy - 1

            z  = cell_depth[cx, cy]
            tv = cell_trait[cx, cy]

            # Trait → hue rotation (300° spectrum)
            base_fg = hue_shift(color_lerp(primary, accent, 0.3), tv * 300.0)

            # Depth brightness: tips bright, trunk dim
            brightness = 0.35 + (1.0 - z) * 0.55

            # Shimmer on leaf tips
            if z < 0.25
                s = shimmer(tick, cx; speed=0.06, scale=0.2)
                brightness += s * 0.12
            end

            fg = dim_color(base_fg, clamp(1.0 - brightness, 0.0, 0.95))
            fg = color_transform(fg)

            set_char!(buf, bx, by, _dot_char(bits, ub), Style(fg=fg))
        end
    end
end

const generate_clado_tree = _generate_clado_tree
const render_clado_tree! = _render_clado_tree!
