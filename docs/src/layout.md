# Layout

Tachikoma uses a constraint-based layout system to divide terminal space into regions. You define constraints (fixed size, percentage, fill remaining space) and the layout engine computes the resulting rectangles.

## Rect

`Rect` is the fundamental geometry type — a rectangle defined by position and size:

<!-- tachi:noeval -->
```julia
r = Rect(x, y, width, height)   # 1-based coordinates
```

### Geometric Helpers

<!-- tachi:noeval -->
```julia
right(r)                         # r.x + r.width - 1
bottom(r)                        # r.y + r.height - 1
inner(r)                         # shrink by 1 on all sides (for borders)
margin(r; top=0, right=0, bottom=0, left=0)  # apply margins
shrink(r, n)                     # uniform margin of n cells
center(parent, width, height)    # center a rect inside parent
anchor(parent, w, h; h=:center, v=:center)   # anchor by h/v symbols
```

`anchor` supports `h` values `:left`, `:center`, `:right` and `v` values `:top`, `:center`, `:bottom`.

## Constraints

Five constraint types control how space is divided:

| Type | Description | Example |
|:-----|:------------|:--------|
| `Fixed(n)` | Exactly `n` cells | `Fixed(20)` — always 20 cells |
| `Fill(w)` | Expand to fill remaining space | `Fill()` — weight 1 (default) |
| `Percent(p)` | Percentage of total space | `Percent(50)` — half the space |
| `Min(n)` | At least `n` cells, expands if available | `Min(10)` |
| `Max(n)` | At most `n` cells | `Max(40)` |

`Fill` accepts an optional weight: `Fill(2)` gets twice the remaining space of `Fill(1)`.

<!-- tachi:widget layout_constraint_types w=54 h=7 -->
```julia
cols = split_layout(Layout(Horizontal, [Fixed(12), Percent(35), Fill()]), area)
for (col, label) in zip(cols, ["Fixed(12)", "Percent(35)", "Fill()"])
    inner = render(Block(), col, buf)
    lx = inner.x + max(0, (inner.width - length(label)) ÷ 2)
    set_string!(buf, lx, inner.y + inner.height ÷ 2, label, tstyle(:primary, bold=true))
end
```

<!-- tachi:widget layout_fill_weights w=54 h=7 -->
```julia
cols = split_layout(Layout(Horizontal, [Fill(1), Fill(2), Fill(3)]), area)
for (i, col) in enumerate(cols)
    label = "Fill($i)"
    inner = render(Block(), col, buf)
    lx = inner.x + max(0, (inner.width - length(label)) ÷ 2)
    set_string!(buf, lx, inner.y + inner.height ÷ 2, label, tstyle(:accent, bold=true))
    sz = "$(col.width) cols"
    lx2 = inner.x + max(0, (inner.width - length(sz)) ÷ 2)
    set_string!(buf, lx2, inner.y + inner.height ÷ 2 + 1, sz, tstyle(:text_dim))
end
```

## Layout and split_layout

Create a `Layout` with a direction and constraints, then split a `Rect`:

```julia
# Vertical split: header (3 rows) + body (flexible) + footer (1 row)
layout = Layout(Vertical, [Fixed(3), Fill(), Fixed(1)])
rects = split_layout(layout, area)
# rects[1] = header, rects[2] = body, rects[3] = footer

# Horizontal split: sidebar (25%) + main (75%)
layout = Layout(Horizontal, [Percent(25), Fill()])
cols = split_layout(layout, area)
```

### Direction

`Vertical` splits top to bottom. `Horizontal` splits left to right.

<!-- tachi:widget layout_vertical w=40 h=12 -->
```julia
rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(2)]), area)
render(Block(title="Fixed(3)"), rows[1], buf)
render(Block(title="Fill()"), rows[2], buf)
render(Block(title="Fixed(2)"), rows[3], buf)
```

<!-- tachi:widget layout_horizontal w=54 h=7 -->
```julia
cols = split_layout(Layout(Horizontal, [Percent(30), Fill()]), area)
render(Block(title="Percent(30)"), cols[1], buf)
render(Block(title="Fill()"), cols[2], buf)
```

### Alignment

```julia
layout = Layout(Horizontal, [Fixed(20), Fixed(20)]; align=layout_center)
```

| Alignment | Behavior |
|:----------|:---------|
| `layout_start` | Pack children at the start (default) |
| `layout_center` | Center children in available space |
| `layout_end` | Pack children at the end |
| `layout_space_between` | Distribute space evenly between children |

<!-- tachi:widget layout_alignment w=54 h=7 -->
```julia
cols = split_layout(Layout(Horizontal, [Fixed(14), Fixed(14), Fixed(14)];
                           align=layout_space_between), area)
render(Block(title="Fixed(14)"), cols[1], buf)
render(Block(title="Fixed(14)"), cols[2], buf)
render(Block(title="Fixed(14)"), cols[3], buf)
set_string!(buf, area.x, bottom(area), " align=layout_space_between", tstyle(:text_dim))
```

## Nesting Layouts

Build complex interfaces by nesting layouts:

<!-- tachi:widget layout_nested w=60 h=16 -->
```julia
rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), area)
header, body, footer = rows[1], rows[2], rows[3]

cols = split_layout(Layout(Horizontal, [Percent(25), Fill()]), body)
sidebar, main = cols[1], cols[2]

render(Block(title="Header"), header, buf)
render(Block(title="Sidebar"), sidebar, buf)
render(Block(title="Main Content"), main, buf)
render(StatusBar(
    left=[Span("  Footer ", tstyle(:text_dim))],
    right=[Span("[q] quit ", tstyle(:text_dim))],
), footer, buf)
```

## ResizableLayout

`ResizableLayout` lets users drag pane borders with the mouse:

```julia
@kwdef mutable struct MyApp <: Model
    layout::ResizableLayout = ResizableLayout(Horizontal, [Fixed(30), Fill()])
end

function update!(m::MyApp, evt::MouseEvent)
    handle_resize!(m.layout, evt) && return   # consumed by resize
    # ... handle other mouse events
end

function view(m::MyApp, f::Frame)
    buf = f.buffer
    rects = split_layout(m.layout, f.area)

    # Render panes
    render(left_widget, rects[1], buf)
    render(right_widget, rects[2], buf)

    # Draw resize handles (highlights border on hover)
    render_resize_handles!(buf, m.layout)
end
```

### ResizableLayout API

<!-- tachi:noeval -->
```julia
ResizableLayout(direction, constraints; min_pane_size=3)
split_layout(rl, rect)           # compute child rects
handle_resize!(rl, evt)          # process mouse drag, returns true if consumed
reset_layout!(rl)                # restore original constraints
render_resize_handles!(buf, rl)  # draw visual feedback on borders
```

- **Alt+click** on a border rotates the layout direction (Horizontal ↔ Vertical)
- **Alt+drag** a pane to swap it with another
- Layout state is automatically persisted via Preferences.jl

<!-- tachi:widget layout_resizable w=54 h=10 -->
```julia
rl = ResizableLayout(Horizontal, [Fixed(20), Fill()])
rects = split_layout(rl, area)
render(Block(title="Left Pane"), rects[1], buf)
render(Block(title="Right Pane"), rects[2], buf)
render_resize_handles!(buf, rl)
set_string!(buf, rects[1].x + 1, bottom(rects[1]) - 1,
    "← drag border →", tstyle(:text_dim, dim=true))
```

## Positioning

Layout divides space among multiple children. **Positioning** places a single widget within a space. The two compose naturally:

<!-- tachi:noeval -->
```julia
rects = split_layout(Layout(Vertical, [Fixed(7), Fill()]), area)
render(bt, center(rects[1], bt), buf)    # centered widget in top slot
render(content, rects[2], buf)           # fill-style widget in bottom slot
```

### center and anchor

`center` places a widget (or explicit dimensions) in the middle of a parent rect. `anchor` gives full control over horizontal and vertical alignment:

<!-- tachi:noeval -->
```julia
center(parent, width, height)            # center explicit dimensions
center(parent, widget)                   # center using intrinsic_size

anchor(parent, w, h; h=:center, v=:center)   # explicit dimensions
anchor(parent, widget; h=:right, v=:bottom)  # widget intrinsic_size
```

`anchor` supports `h` values `:left`, `:center`, `:right` and `v` values `:top`, `:center`, `:bottom`.

`anchor` composes with `margin` for offset positioning:

<!-- tachi:noeval -->
```julia
# Notification toast: centered horizontally, offset 1 row from top
toast_rect = anchor(margin(area; top=1), tw, 1; h=:center, v=:top)

# Status label: bottom-right corner with 1-cell margin
status_rect = anchor(margin(area; bottom=1, right=1), sw, 1; h=:right, v=:bottom)
```

<!-- tachi:widget layout_center_anchor w=54 h=14 -->
```julia
render(Block(), area, buf)
inner = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2)

# center() — places a dialog in the middle of the content area
render(Block(title=" Dialog "), center(inner, 28, 5), buf)

# anchor() — overlays labels pinned to edges
for (h, v, label, sty) in [
    (:center, :top,    "✓ Saved",  tstyle(:success, bold=true)),
    (:right,  :bottom, "Ln 42 ",   tstyle(:text_dim)),
    (:left,   :bottom, " [?] ",    tstyle(:text_dim)),
]
    r = anchor(inner, length(label), 1; h=h, v=v)
    set_string!(buf, r.x, r.y, label, sty)
end
```

### intrinsic_size protocol

Widgets with a natural size implement `intrinsic_size(widget) -> (width, height)`. This lets `center` and `anchor` position them automatically:

| Widget | intrinsic_size | Notes |
|:-------|:---------------|:------|
| `BigText` | `(width, 5)` | 3-wide glyphs + 1-cell gaps |
| `Button` | `(length(label) + 4, 1)` | Renders as `"[ label ]"` |
| `Checkbox` | `(length(label) + 4, 1)` | Renders as `"[x] label"` |
| `RadioGroup` | `(max_label_width + 2, n_labels)` | Marker + space + label per row |
| `Calendar` | `(22, 9)` | Fixed grid: 7 cols x 3 chars + header rows |

Space-filling widgets (Gauge, Paragraph, Chart, Table, etc.) return `nothing` -- they expand to fill whatever rect they are given.

To add `intrinsic_size` to a custom widget:

<!-- tachi:noeval -->
```julia
struct MyWidget
    text::String
end
Tachikoma.intrinsic_size(w::MyWidget) = (length(w.text), 1)
```

## Container

`Container` groups widgets with a layout for automatic positioning:

```julia
container = Container(
    [widget1, widget2, widget3],
    Layout(Vertical, [Fixed(3), Fill(), Fixed(1)])
)
render(container, area, buf)
```

Each child is rendered into its corresponding layout rect. Pass three arguments to wrap in a `Block`:

```julia
container = Container(
    [widget1, widget2],
    Layout(Horizontal, [Percent(50), Fill()]),
    Block(title="Panel"),
)
```

<!-- tachi:widget layout_container w=54 h=10 -->
```julia
container = Container(
    [Block(title="Alpha"), Block(title="Beta"), Block(title="Gamma")],
    Layout(Horizontal, [Fill(), Fill(), Fill()]),
    Block(title="Container"),
)
render(container, area, buf)
```
