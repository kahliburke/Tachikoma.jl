# Constraint Explorer

This tutorial builds an interactive layout constraint explorer that visualizes how different constraint types and flex alignments distribute space.

## What We'll Build

An interactive tool showing how Tachikoma's layout constraints (`Fixed`, `Min`, `Max`, `Percent`, `Fill`) work with different flex alignments (`Start`, `Center`, `End`, `SpaceBetween`, `SpaceAround`, `SpaceEvenly`). Users can add, remove, and modify constraints in real time to see how the layout engine responds.

<!-- tachi:begin constraint_explorer_app -->

## Key Concepts

### Constraint Types

Tachikoma's layout system supports five constraint types:

| Key | Type | Description |
|:----|:-----|:------------|
| `1` | `Min(n)` | At least `n` cells |
| `2` | `Max(n)` | At most `n` cells |
| `3` | `Fixed(n)` | Exactly `n` cells |
| `4` | `Percent(p)` | Percentage of total space |
| `5` | `Fill(w)` | Expand to fill remaining space (weighted) |

### Flex Alignment

The `align` parameter on `Layout` controls how blocks are distributed when there's extra space:

<!-- tachi:noeval -->
```julia
Layout(Horizontal, constraints; align=layout_start)
Layout(Horizontal, constraints; align=layout_center)
Layout(Horizontal, constraints; align=layout_space_between)
```

### Spacing

The `spacing` parameter adds gaps (positive) or overlap (negative) between blocks:

<!-- tachi:noeval -->
```julia
Layout(Horizontal, constraints; spacing=3)    # 3px gap
Layout(Horizontal, constraints; spacing=-2)   # 2px overlap
```

## Adjusting Constraints

The `adjust` function modifies a constraint's value while preserving its type. Each constraint type needs its own method because they store their value in different fields:

```julia
using Tachikoma
@tachikoma_app

adjust(c::Fixed, d::Int)   = Fixed(max(c.size + d, 0))
adjust(c::Min, d::Int)     = Min(max(c.size + d, 0))
adjust(c::Max, d::Int)     = Max(max(c.size + d, 0))
adjust(c::Percent, d::Int) = Percent(clamp(c.pct + d, 0, 100))
adjust(c::Fill, d::Int)    = Fill(max(c.weight + d, 1))
```

`Fixed`, `Min`, and `Max` use `.size`, `Percent` uses `.pct`, and `Fill` uses `.weight`. The `clamp` and `max` calls prevent invalid values.

## The Model

```julia
@kwdef mutable struct ExplorerModel <: Model
    constraints::Vector{Constraint} = Constraint[Fixed(10), Percent(30), Fill(1)]
    selected_index::Int = 1
    spacing::Int = 0
    value::Int = 10
    quit::Bool = false
    tick::Int = 0
end

should_quit(m::ExplorerModel) = m.quit
```

The model tracks:
- A vector of constraints that define the layout
- Which constraint is selected for editing
- The spacing between blocks
- A default value used when adding or switching constraint types
- A tick counter for animation

## Event Handling

```julia
function update!(m::ExplorerModel, evt::KeyEvent)
    evt.key == :escape && (m.quit = true; return)

    if evt.key == :right
        n = length(m.constraints)
        n > 0 && (m.selected_index = mod1(m.selected_index + 1, n))
    elseif evt.key == :left
        n = length(m.constraints)
        n > 0 && (m.selected_index = mod1(m.selected_index - 1, n))
    elseif evt.key == :up && !isempty(m.constraints)
        m.constraints[m.selected_index] = adjust(m.constraints[m.selected_index], 1)
    elseif evt.key == :down && !isempty(m.constraints)
        m.constraints[m.selected_index] = adjust(m.constraints[m.selected_index], -1)
    elseif evt.key == :char && evt.char == '+'
        m.spacing = min(m.spacing + 1, 20)
    elseif evt.key == :char && evt.char == '-'
        m.spacing = max(m.spacing - 1, -5)
    elseif evt.key == :char && evt.char in '1':'5' && !isempty(m.constraints)
        types = [v -> Min(v), v -> Max(v), v -> Fixed(v), v -> Percent(v), v -> Fill(v)]
        m.constraints[m.selected_index] = types[evt.char - '0'](m.value)
    elseif evt.key == :char && evt.char == 'a'
        idx = m.selected_index + 1
        insert!(m.constraints, idx, Fixed(m.value))
        m.selected_index = idx
    elseif evt.key == :char && evt.char == 'x' && length(m.constraints) > 1
        deleteat!(m.constraints, m.selected_index)
        m.selected_index = clamp(m.selected_index, 1, length(m.constraints))
    end
end
```

Key bindings:
- **Left/Right** — select previous/next constraint
- **Up/Down** — adjust the selected constraint's value
- **1-5** — switch constraint type (Min, Max, Fixed, Percent, Fill)
- **+/-** — increase/decrease spacing between blocks
- **a** — add a new constraint after the selected one
- **x** — delete the selected constraint (minimum one must remain)
- **Escape** — quit

## Rendering Layout Demos

The view renders multiple alignment demos stacked vertically, each showing the same constraints with a different `align` value:

```julia
function view(m::ExplorerModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Outer block
    outer = Block(title="constraint explorer", border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    inner = render(outer, f.area, buf)
    inner.width < 4 && return

    # Layout: header + demo area + status bar
    rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), inner)
    header, demo_area, footer = rows[1], rows[2], rows[3]

    # ── Header ──
    constraint_str = join(string.(m.constraints), "  ")
    set_string!(buf, header.x, header.y, "Constraints: ", tstyle(:text_dim))
    set_string!(buf, header.x + 13, header.y, constraint_str, tstyle(:text);
                max_x=right(header))
    set_string!(buf, header.x, header.y + 1, "Spacing: $(m.spacing)", tstyle(:text_dim))
    set_string!(buf, header.x + 20, header.y + 1,
                "Selected: $(m.selected_index)/$(length(m.constraints))",
                tstyle(:text_dim))

    # ── Alignment demos ──
    aligns = [layout_start, layout_center, layout_end,
              layout_space_between, layout_space_around, layout_space_evenly]
    align_names = ["Start", "Center", "End", "SpaceBetween", "SpaceAround", "SpaceEvenly"]
    demo_rows = split_layout(Layout(Vertical, [Fill() for _ in aligns]), demo_area)

    for (i, dr) in enumerate(demo_rows)
        i > length(aligns) && break
        dr.height < 3 && continue

        set_string!(buf, dr.x + 1, dr.y, align_names[i], tstyle(:text, bold=true))

        block_area = Rect(dr.x, dr.y + 1, dr.width, dr.height - 1)
        layout = Layout(Horizontal, copy(m.constraints); align=aligns[i], spacing=m.spacing)
        rects = split_layout(layout, block_area)

        for (j, rect) in enumerate(rects)
            j > length(m.constraints) && break
            rect.width < 1 && continue
            selected = (j == m.selected_index)
            border_s = selected ? tstyle(:accent) : tstyle(:border)
            blk = Block(title="$(m.constraints[j])", border_style=border_s,
                title_style=tstyle(:text_dim))
            render(blk, rect, buf)
        end
    end

    # ── Status bar ──
    render(StatusBar(
        left=[Span("  ←/→ select  ↑/↓ adjust  1-5 type  +/- spacing  a add  x del ",
                    tstyle(:text_dim))],
        right=[Span("[Esc] quit ", tstyle(:text_dim))],
    ), footer, buf)
end
```

Each alignment mode renders the same set of constraints with different distribution strategies. The selected block is highlighted with the theme's accent color.

## Run It

<!-- tachi:app constraint_explorer_app w=80 h=30 frames=120 fps=15 chrome -->
```julia
app(ExplorerModel())
```

## Exercises

- Add `Ratio` constraint support (divide space proportionally)
- Add mouse click to select blocks
- Add color coding by constraint type
- Add a `ResizableLayout` mode where blocks can be dragged
