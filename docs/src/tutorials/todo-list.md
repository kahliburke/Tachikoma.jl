# Todo List App

This tutorial builds a todo list application with a selectable list, detail pane, and status toggling — a classic TUI pattern.

## What We'll Build

A two-pane app: a scrollable list of todo items on top with checkboxes that can be toggled, and a detail pane below showing information about the selected item. Supports keyboard navigation and enter to toggle status.

<!-- tachi:begin todo_app -->

## Step 1: Data Model

```julia
using Tachikoma
@tachikoma_app

@enum Status Todo Completed

struct TodoItem
    title::String
    info::String
    status::Status
end

TODOS = [
    TodoItem("Set up project", "Initialize the project structure and dependencies", Completed),
    TodoItem("Design TUI layout", "Plan the header, list, and detail pane regions", Completed),
    TodoItem("Implement model", "Define TodoModel with items and selection state", Todo),
    TodoItem("Add keyboard nav", "Up/down arrows to select, enter to toggle status", Todo),
    TodoItem("Add mouse support", "Click to select items, scroll wheel to navigate", Todo),
    TodoItem("Style the UI", "Apply theme-aware colors and borders", Todo),
]
```

Each item has a title (shown in the list), info text (shown in the detail pane), and a status that can be toggled between `Todo` and `Completed`.

## Step 2: Building the List

The `SelectableList` widget handles rendering, scrolling, and keyboard navigation. We build the list items with checkbox characters and color coding based on status:

```julia
function make_list(items; selected=1, tick=0)
    list_items = [ListItem(
        item.status == Completed ? " ✓ $(item.title)" : " ☐ $(item.title)",
        item.status == Completed ? tstyle(:success) : tstyle(:text),
    ) for item in items]

    SelectableList(list_items;
        selected=selected,
        block=Block(title="TODO List", border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        highlight_style=tstyle(:accent, bold=true),
        tick=tick,
    )
end
```

When an item's status changes, we rebuild the list to update the checkbox characters and colors. The `tick` parameter enables the subtle highlight animation on the selected row.

## Step 3: Define the Model

```julia
@kwdef mutable struct TodoModel <: Model
    quit::Bool = false
    tick::Int = 0
    items::Vector{TodoItem} = copy(TODOS)
    list::SelectableList = make_list(TODOS)
end

should_quit(m::TodoModel) = m.quit
```

The model holds the raw `items` vector and the rendered `list` widget. When items change, we rebuild the list.

## Step 4: Toggle Logic

```julia
function toggle_status!(m::TodoModel)
    idx = m.list.selected
    item = m.items[idx]
    new_status = item.status == Todo ? Completed : Todo
    m.items[idx] = TodoItem(item.title, item.info, new_status)
    m.list = make_list(m.items; selected=idx, tick=m.tick)
end
```

The list is rebuilt after toggling because `ListItem` objects are immutable — the styled text includes the checkbox character and color.

## Step 5: Handle Events

```julia
function update!(m::TodoModel, evt::KeyEvent)
    if evt.key == :escape
        m.quit = true
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        toggle_status!(m)
    else
        handle_key!(m.list, evt)
    end
end
```

Escape quits, Enter or Space toggles the selected item's status, and all other keys are delegated to `handle_key!` which handles Up/Down navigation, Home/End, and PageUp/PageDown.

## Step 6: Render the View

```julia
function view(m::TodoModel, f::Frame)
    m.tick += 1
    m.list.tick = m.tick
    buf = f.buffer

    # Layout: list (top half) | detail pane (bottom half) | status bar
    rows = split_layout(Layout(Vertical, [Fill(), Fill(), Fixed(1)]), f.area)

    # Render the selectable list
    render(m.list, rows[1], buf)

    # Render the detail pane
    idx = m.list.selected
    item = m.items[idx]
    status_text = item.status == Completed ? "Completed" : "Todo"
    status_style = item.status == Completed ? tstyle(:success, bold=true) : tstyle(:warning, bold=true)

    detail_block = Block(title="Details", border_style=tstyle(:border),
                         title_style=tstyle(:title))
    inner = render(detail_block, rows[2], buf)

    if inner.height >= 3
        set_string!(buf, inner.x, inner.y, item.title, tstyle(:text, bold=true))
        set_string!(buf, inner.x, inner.y + 1, "Status: ", tstyle(:text_dim))
        set_string!(buf, inner.x + 8, inner.y + 1, status_text, status_style)
        render(Paragraph(item.info; wrap=word_wrap, style=tstyle(:text)),
               Rect(inner.x, inner.y + 3, inner.width, max(1, inner.height - 3)), buf)
    end

    # Footer
    render(StatusBar(
        left=[Span("  [↑↓] navigate  [Enter] toggle ", tstyle(:text_dim))],
        right=[Span("[Esc] quit ", tstyle(:text_dim))],
    ), rows[3], buf)
end
```

The view splits the screen into three rows: the list on top, a detail pane below it, and a status bar at the bottom. The detail pane shows the selected item's title, status, and info text with word wrapping.

## Step 7: Mouse Support

You can extend the app with mouse support by adding an `update!` method for `MouseEvent`. The `SelectableList` widget has built-in mouse handling via `handle_mouse!` — it supports click-to-select and scroll wheel navigation:

<!-- tachi:noeval -->
```julia
function update!(m::TodoModel, evt::MouseEvent)
    handle_mouse!(m.list, evt)
end
```

For checkbox toggling on click, you could check the click's x-coordinate against the checkbox column position and call `toggle_status!` when the checkbox is clicked.

## Step 8: Run It

<!-- tachi:app todo_app w=60 h=20 frames=120 fps=15 chrome -->
```julia
app(TodoModel())
```

## Key Techniques

1. **Immutable data + rebuild** — `TodoItem` is a struct; changes create new items and rebuild the list
2. **Delegate navigation** — `handle_key!` on `SelectableList` handles all arrow key, Home/End, and PageUp/PageDown logic
3. **Checkbox rendering** — Unicode characters with color coding via `tstyle(:success)` and `tstyle(:text)`
4. **Word-wrapped detail** — `Paragraph` with `word_wrap` displays long info text cleanly

## Exercises

- Add a "new item" mode with `TextInput` for creating todos
- Add drag-to-reorder with `MouseEvent` tracking
- Persist items to a JSON file
- Add priority levels with color-coded markers
