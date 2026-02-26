# Widgets

Tachikoma includes dozens of widgets covering text display, input controls, data visualization, navigation, and containers. All widgets follow the render protocol: `render(widget, area::Rect, buf::Buffer)`.

## Value Protocol

Many widgets support a unified value interface:

<!-- tachi:noeval -->
```julia
value(widget)            # get the widget's current value
set_value!(widget, v)    # set the widget's value
valid(widget)            # check if the current value is valid (default: true)
```

## Text Display

### Block

Bordered panel with optional title. The workhorse container widget:

<!-- tachi:widget block_basic w=40 h=5 -->
```julia
block = Block(; title="Panel", border_style=tstyle(:border),
               title_style=tstyle(:title, bold=true), box=BOX_ROUNDED)
inner = render(block, area, buf)   # returns inner Rect after drawing borders
```

Box styles: `BOX_ROUNDED`, `BOX_HEAVY`, `BOX_DOUBLE`, `BOX_PLAIN`.

### Paragraph

Styled text with wrapping and alignment:

<!-- tachi:widget paragraph_basic w=50 h=4 -->
```julia
para = Paragraph([
    Span("Bold text ", tstyle(:text, bold=true)),
    Span("and dim text", tstyle(:text_dim)),
]; wrap=word_wrap, alignment=align_center)

render(para, area, buf)
```

```julia
para = Paragraph([Span("Hello ", tstyle(:text)), Span("world", tstyle(:accent))])
paragraph_line_count(para, 40)   # count wrapped lines for a given width
```

Wrap modes: `no_wrap`, `word_wrap`, `char_wrap`.
Alignment: `align_left`, `align_center`, `align_right`.

### Span

Inline styled text fragment, used inside `Paragraph` and `StatusBar`:

<!-- tachi:widget span_demo w=45 h=3
render(Paragraph([Span("styled ", tstyle(:primary, bold=true)),
    Span("text ", tstyle(:accent)),
    Span("fragments", tstyle(:warning))];
    block=Block(border_style=tstyle(:border))), area, buf)
-->
```julia
Span("text", tstyle(:primary, bold=true))
```

### BigText

Large block-character text (5 rows tall):

<!-- tachi:widget bigtext_basic w=40 h=7 -->
```julia
bt = BigText("12:34"; style=tstyle(:primary, bold=true))
render(bt, area, buf)
```

```julia
intrinsic_size(BigText("12:34"))   # (width, height) in terminal cells
```

### StatusBar

Full-width bar with left and right aligned spans:

<!-- tachi:widget statusbar_basic w=60 h=1 -->
```julia
render(StatusBar(
    left=[Span("  Status: OK ", tstyle(:success))],
    right=[Span("[q] quit ", tstyle(:text_dim))],
), area, buf)
```

### Separator

Visual divider line:

<!-- tachi:widget separator_basic w=40 h=1 -->
```julia
render(Separator(), area, buf)
```

## Input Widgets

### TextInput

Single-line text editor with optional validation:

<!-- tachi:app textinput_demo w=40 h=5 frames=120 fps=15
@kwdef mutable struct _M <: Model
    input::TextInput = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.input, evt)
function view(m::_M, f::Frame)
    m.tick += 1; m.input.tick = m.tick
    buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(1), Fixed(1), Fixed(1)]), f.area)
    length(rows) < 4 && return
    render(m.input, rows[1], buf)
    v = text(m.input)
    display = isempty(v) ? "(empty)" : v
    set_string!(buf, rows[3].x + 1, rows[3].y, "value: ", tstyle(:text_dim))
    set_string!(buf, rows[3].x + 8, rows[3].y, display, tstyle(:primary))
    if !valid(m.input)
        set_string!(buf, rows[4].x + 1, rows[4].y, m.input.error_msg, tstyle(:error))
    else
        set_string!(buf, rows[4].x + 1, rows[4].y, "✓ valid", tstyle(:success))
    end
end
app(_M())
-->
```julia
input = TextInput(; text="initial", label="Name:", focused=true,
                   validator=s -> length(s) < 2 ? "Min 2 chars" : nothing)
```

<!-- tachi:noeval -->
```julia
handle_key!(input, evt)   # returns true if consumed
text(input)                # get current text
set_text!(input, "new")    # set text
value(input)               # same as text()
valid(input)               # true if validator returns nothing
```

The validator function receives the current text and returns `nothing` (valid) or an error message string.

### TextArea

Multi-line text editor:

<!-- tachi:app textarea_demo w=45 h=10 frames=120 fps=15
@kwdef mutable struct _M <: Model
    area::TextArea = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.area, evt)
function view(m::_M, f::Frame)
    m.tick += 1; m.area.tick = m.tick
    buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), f.area)
    length(rows) < 2 && return
    block = Block(title="TextArea", border_style=tstyle(:border), title_style=tstyle(:title))
    inner = render(block, rows[1], buf)
    render(m.area, inner, buf)
    lines = length(m.area.lines)
    info = "\$(lines) line\$(lines > 1 ? "s" : "")  cursor: \$(m.area.cursor_row):\$(m.area.cursor_col)"
    set_string!(buf, rows[2].x + 1, rows[2].y, info, tstyle(:text_dim))
end
app(_M())
-->
```julia
area = TextArea(; text="", label="Bio:", focused=true)
```

<!-- tachi:noeval -->
```julia
handle_key!(area, evt)
handle_mouse!(area, evt, rect)
text(area)
set_text!(area, "multi\nline")
```

### CodeEditor

Syntax-highlighted code editor:

<!-- tachi:app codeeditor_demo w=50 h=10 frames=120 fps=15
@kwdef mutable struct _M <: Model
    editor::CodeEditor = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.editor, evt)
function view(m::_M, f::Frame)
    m.tick += 1; m.editor.tick = m.tick
    render(m.editor, f.area, f.buffer)
end
app(_M())
-->
```julia
CodeEditor(; text="function greet(name)\n    println(\"Hello, \$name!\")\nend",
    focused=true, block=Block(title="editor.jl", border_style=tstyle(:border),
    title_style=tstyle(:title)))
```

<!-- tachi:noeval -->
```julia
handle_key!(editor, evt)
editor_mode(editor)        # current mode symbol
```

Supports Julia syntax highlighting with token types: `token_keyword`, `token_string`, `token_comment`, `token_number`, `token_plain`.

### Checkbox

Boolean toggle:

<!-- tachi:app checkbox_demo w=55 h=6 frames=120 fps=15
@kwdef mutable struct _M <: Model
    cb1::Checkbox = __FENCE__
    cb2::Checkbox = Checkbox("Dark mode"; checked=true, focused=false)
    cb3::Checkbox = Checkbox("Auto-save"; checked=false, focused=false)
    focus_idx::Int = 1; quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
function update!(m::_M, evt::KeyEvent)
    cbs = [m.cb1, m.cb2, m.cb3]
    if evt.key == :tab || evt.key == :down
        cbs[m.focus_idx].focused = false
        m.focus_idx = mod1(m.focus_idx + 1, 3)
        cbs[m.focus_idx].focused = true
    elseif evt.key == :up
        cbs[m.focus_idx].focused = false
        m.focus_idx = mod1(m.focus_idx - 1, 3)
        cbs[m.focus_idx].focused = true
    else
        handle_key!(cbs[m.focus_idx], evt)
    end
end
function view(m::_M, f::Frame)
    m.tick += 1; buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(1), Fixed(1), Fixed(1), Fixed(1)]), f.area)
    length(rows) < 5 && return
    render(m.cb1, rows[1], buf); render(m.cb2, rows[2], buf); render(m.cb3, rows[3], buf)
    vals = join(["notifications=\$(value(m.cb1))", "dark=\$(value(m.cb2))", "autosave=\$(value(m.cb3))"], "  ")
    set_string!(buf, rows[5].x + 1, rows[5].y, vals, tstyle(:text_dim))
end
app(_M())
-->
```julia
cb = Checkbox("Enable notifications"; focused=false)
```

<!-- tachi:noeval -->
```julia
handle_key!(cb, evt)       # space toggles
value(cb)                  # true/false
set_value!(cb, true)
```

### RadioGroup

Mutually exclusive selection:

<!-- tachi:app radiogroup_demo w=30 h=9 frames=120 fps=15
@kwdef mutable struct _M <: Model
    rg::RadioGroup = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.rg, evt)
function view(m::_M, f::Frame)
    m.tick += 1; buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(5), Fixed(1), Fixed(1)]), f.area)
    length(rows) < 3 && return
    block = Block(title="Role", border_style=tstyle(:border), title_style=tstyle(:title))
    inner = render(block, rows[1], buf)
    render(m.rg, inner, buf)
    sel = value(m.rg)
    labels = ["Admin", "Editor", "Viewer"]
    label = 1 <= sel <= 3 ? labels[sel] : "?"
    set_string!(buf, rows[3].x + 1, rows[3].y, "selected: ", tstyle(:text_dim))
    set_string!(buf, rows[3].x + 11, rows[3].y, label, tstyle(:primary, bold=true))
end
app(_M())
-->
```julia
rg = RadioGroup(["Admin", "Editor", "Viewer"])
```

<!-- tachi:noeval -->
```julia
handle_key!(rg, evt)       # up/down + space/enter to select
value(rg)                  # selected index (Int)
set_value!(rg, 2)
```

### DropDown

Select from a dropdown list:

<!-- tachi:app dropdown_demo w=35 h=10 frames=120 fps=15
@kwdef mutable struct _M <: Model
    dd::DropDown = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.dd, evt)
function view(m::_M, f::Frame)
    m.tick += 1; buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(6), Fixed(1), Fixed(1)]), f.area)
    length(rows) < 4 && return
    set_string!(buf, rows[1].x + 1, rows[1].y, "Region:", tstyle(:text_dim))
    render(m.dd, Rect(rows[1].x + 9, rows[1].y, rows[1].width - 9, rows[2].height + 1), buf)
    sel = value(m.dd)
    label = sel isa AbstractString ? sel : string(sel)
    set_string!(buf, rows[4].x + 1, rows[4].y, "selected: ", tstyle(:text_dim))
    set_string!(buf, rows[4].x + 11, rows[4].y, label, tstyle(:primary, bold=true))
end
app(_M())
-->
```julia
dd = DropDown(["Tokyo", "Berlin", "NYC", "London"])
```

<!-- tachi:noeval -->
```julia
handle_key!(dd, evt)       # enter opens, up/down navigates, enter selects
value(dd)                  # selected index (Int)
```

### Calendar

Date picker widget:

<!-- tachi:widget calendar_basic w=24 h=10 -->
```julia
cal = Calendar(2026, 2; today=19)
render(cal, area, buf)
```

## Selection & Navigation

### SelectableList

Keyboard and mouse navigable list:

<!-- tachi:app selectablelist_demo w=30 h=9 frames=140 fps=15
@kwdef mutable struct _M <: Model
    list::SelectableList = __FENCE__
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(m::_M, evt::KeyEvent) = handle_key!(m.list, evt)
function view(m::_M, f::Frame)
    m.tick += 1; m.list.tick = m.tick; buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), f.area)
    length(rows) < 2 && return
    render(m.list, rows[1], buf)
    sel = value(m.list)
    items = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
    label = 1 <= sel <= length(items) ? items[sel] : "?"
    set_string!(buf, rows[2].x + 1, rows[2].y, "selected: ", tstyle(:text_dim))
    set_string!(buf, rows[2].x + 11, rows[2].y, label, tstyle(:primary, bold=true))
end
app(_M())
-->
```julia
list = SelectableList(["Alpha", "Beta", "Gamma", "Delta", "Epsilon"];
                      selected=1, focused=true,
                      block=Block(title="Items"),
                      highlight_style=tstyle(:accent, bold=true),
                      marker=MARKER)
```

<!-- tachi:noeval -->
```julia
handle_key!(list, evt)
value(list)                # selected index
set_value!(list, 2)
list_hit(list, x, y, area)    # hit test → index or nothing
list_scroll(list, lines)       # scroll by n lines
```

With styled items:

```julia
items = [ListItem("Item 1", tstyle(:text)),
         ListItem("Item 2", tstyle(:warning))]
list = SelectableList(items; selected=1)
```

### TreeView / TreeNode

Hierarchical tree display:

<!-- tachi:widget treeview_basic w=30 h=8 -->
```julia
root = TreeNode("Root", [
    TreeNode("Child 1", [
        TreeNode("Leaf A"),
        TreeNode("Leaf B"),
    ]),
    TreeNode("Child 2"),
])

tree = TreeView(root; block=Block(title="Tree"))
render(tree, area, buf)
```

<!-- tachi:noeval -->
```julia
handle_key!(tree, evt)     # up/down navigate, enter expand/collapse
```

### TabBar

Tab switching:

<!-- tachi:widget tabbar_basic w=50 h=1 -->
```julia
tabs = TabBar(["Overview", "Details", "Settings"]; active=2)
render(tabs, area, buf)
```

<!-- tachi:noeval -->
```julia
handle_key!(tabs, evt)     # left/right to switch
value(tabs)                # selected tab index
```

### Modal

Confirmation dialog:

<!-- tachi:widget modal_basic w=40 h=8 -->
```julia
modal = Modal(; title="Delete?", message="This cannot be undone.",
               confirm_label="Delete", cancel_label="Cancel",
               selected=:cancel)
render(modal, area, buf)
```

## Data Visualization

### Sparkline

Mini line chart from a data vector:

<!-- tachi:app sparkline_demo w=40 h=5 frames=90 fps=15
@kwdef mutable struct _M <: Model
    data::Vector{Float64} = Float64[0.1, 0.3, 0.2, 0.5, 0.4, 0.6, 0.3, 0.8, 0.5, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7, 0.2, 0.9, 0.4, 0.6]
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(::_M, ::KeyEvent) = nothing
function view(m::_M, f::Frame)
    m.tick += 1; buf = f.buffer
    t = m.tick / 15.0
    new_val = clamp(0.5 + 0.3 * sin(t * 1.2) + 0.15 * sin(t * 3.1) + 0.1 * cos(t * 0.7), 0.0, 1.0)
    push!(m.data, new_val)
    length(m.data) > 40 && popfirst!(m.data)
    block = Block(title="Throughput", border_style=tstyle(:border), title_style=tstyle(:title))
    inner = render(block, f.area, buf)
    data = m.data
    render(__FENCE__, inner, buf)
end
app(_M())
-->
```julia
Sparkline(data; style=tstyle(:accent))
```

### Gauge

Progress bar (0.0 to 1.0):

<!-- tachi:app gauge_demo w=50 h=1 frames=90 fps=15
@kwdef mutable struct _M <: Model
    quit::Bool = false; tick::Int = 0
end
should_quit(m::_M) = m.quit
update!(::_M, ::KeyEvent) = nothing
function view(m::_M, f::Frame)
    m.tick += 1
    tick = m.tick
    t = tick / 30.0
    progress = clamp(0.5 + 0.45 * sin(t * 0.8), 0.0, 1.0)
    render(__FENCE__, f.area, f.buffer)
end
app(_M())
-->
```julia
Gauge(progress;
    filled_style=tstyle(:primary),
    empty_style=tstyle(:text_dim, dim=true),
    tick=tick)
```

### BarChart

Bar chart with labeled entries:

<!-- tachi:widget barchart_basic w=40 h=6 -->
```julia
entries = [BarEntry("CPU", 65.0), BarEntry("MEM", 42.0), BarEntry("DSK", 78.0)]
render(BarChart(entries; block=Block(title="Usage")), area, buf)
```

### Chart

Line and scatter plots with multiple data series:

<!-- tachi:widget chart_basic w=50 h=10 -->
```julia
cpu_data = Float64[0.3 + 0.2 * sin(i * 0.3) for i in 1:30]
mem_data = Float64[0.5 + 0.1 * cos(i * 0.2) for i in 1:30]
series = [
    DataSeries(cpu_data; label="CPU", style=tstyle(:primary)),
    DataSeries(mem_data; label="Mem", style=tstyle(:secondary)),
]
render(Chart(series; block=Block(title="System")), area, buf)
```

Chart types: `chart_line`, `chart_scatter`.

### Table

Simple row/column table:

<!-- tachi:widget table_basic w=50 h=7 -->
```julia
headers = ["Name", "Status", "CPU"]
rows = [["nginx", "running", "12%"],
        ["postgres", "running", "8%"]]

render(Table(headers, rows;
    block=Block(title="Processes"),
    header_style=tstyle(:title, bold=true),
    row_style=tstyle(:text),
    alt_row_style=tstyle(:text_dim)), area, buf)
```

### DataTable

Sortable, filterable data table with pagination:

<!-- tachi:widget datatable_basic w=50 h=6 -->
```julia
dt = DataTable([
    DataColumn("Name",  ["Alice", "Bob", "Carol"]),
    DataColumn("Score", [95, 82, 91]; align=col_right),
    DataColumn("Grade", ["A", "B", "A"]; align=col_center),
]; selected=1)
render(dt, area, buf)
```

Sort directions: `sort_none`, `sort_asc`, `sort_desc`.
Column alignment: `col_left`, `col_right`, `col_center`.

With the Tables.jl extension, `DataTable` accepts any Tables.jl source:

```julia
using Tables
dt = DataTable(my_dataframe)
```

## Containers & Control

### Form / FormField

Multi-field form with focus navigation and validation:

<!-- tachi:widget form_basic w=50 h=14 -->
```julia
form = Form([
    FormField("Name", TextInput(; validator=s -> isempty(s) ? "Required" : nothing);
              required=true),
    FormField("Bio", TextArea()),
    FormField("Notify", Checkbox("Enable notifications")),
    FormField("Role", RadioGroup(["Admin", "Editor", "Viewer"])),
    FormField("City", DropDown(["Tokyo", "Berlin", "NYC"])),
]; submit_label="Submit",
   block=Block(title="Registration"))
render(form, area, buf)
```

<!-- tachi:noeval -->
```julia
handle_key!(form, evt)     # Tab/Shift-Tab navigation, widget key handling
value(form)                # Dict{String, Any} of field label → value
valid(form)                # true if all required fields are valid
```

### Button

Clickable button:

<!-- tachi:widget button_basic w=20 h=1 -->
```julia
btn = Button("Submit"; style=tstyle(:primary), focused=true)
render(btn, area, buf)
```

<!-- tachi:noeval -->
```julia
handle_key!(btn, evt)      # enter/space triggers
```

### ScrollPane

Scrollable container for content:

<!-- tachi:widget scrollpane_basic w=40 h=6
sp = ScrollPane(["Line 1", "Line 2", "Line 3", "new line"]; following=true)
render(sp, area, buf)
-->
```julia
sp = ScrollPane(["Line 1", "Line 2", "Line 3"]; following=true)
push_line!(sp, "new line")           # append content
render(sp, area, buf)
```

<!-- tachi:noeval -->
```julia
handle_mouse!(sp, evt, area)         # scrollbar drag + scroll wheel
```

### Scrollbar

Standalone scrollbar indicator:

<!-- tachi:widget scrollbar_basic w=3 h=10 -->
```julia
sb = Scrollbar(100, 20, 0)
render(sb, area, buf)
```

### ProgressList / ProgressItem

Task status list with status icons:

<!-- tachi:widget progresslist_basic w=30 h=5 -->
```julia
items = [
    ProgressItem("Build"; status=task_done),
    ProgressItem("Test"; status=task_running),
    ProgressItem("Deploy"; status=task_pending),
]
render(ProgressList(items; tick=tick), area, buf)
```

Task statuses: `task_pending`, `task_running`, `task_done`, `task_error`, `task_skipped`.

### FocusRing

Tab/Shift-Tab navigation manager — cycles focus between panes or widgets (see [Input & Events](events.md#FocusRing) for the full example):

<!-- tachi:app focusring_widget_demo w=50 h=12 frames=120 fps=15
@kwdef mutable struct _M <: Model
    quit::Bool = false; tick::Int = 0
    ring::FocusRing = FocusRing([:input, :options, :output])
end
should_quit(m::_M) = m.quit
function update!(m::_M, evt::KeyEvent)
    if evt.key == :tab; next!(m.ring)
    elseif evt.key == :backtab; prev!(m.ring)
    elseif evt.key == :escape; m.quit = true
    end
end
function view(m::_M, f::Frame)
    m.tick += 1; buf = f.buffer
    focused = current(m.ring)
    rows = split_layout(Layout(Vertical, [Fill(), Fill()]), f.area)
    top_cols = split_layout(Layout(Horizontal, [Percent(50), Fill()]), rows[1])
    pane_areas = [top_cols[1], top_cols[2], rows[2]]
    pane_names = [" input ", " options ", " output "]
    pane_syms = [:input, :options, :output]
    pane_content = [
        ["name: Alice", "email: alice@example.com"],
        ["[x] notifications", "[ ] dark mode", "[x] auto-save"],
        ["Status: ready", "Last saved: 2s ago"],
    ]
    for (i, (pa, nm, sym)) in enumerate(zip(pane_areas, pane_names, pane_syms))
        is_focused = (sym == focused)
        bs = is_focused ? tstyle(:accent, bold=true) : tstyle(:border)
        ts = is_focused ? tstyle(:accent, bold=true) : tstyle(:text_dim)
        indicator = is_focused ? " ●" : ""
        inner = render(Block(title=nm * indicator, border_style=bs, title_style=ts), pa, buf)
        for (j, line) in enumerate(pane_content[i])
            j > inner.height && break
            s = is_focused ? tstyle(:text) : tstyle(:text_dim)
            set_string!(buf, inner.x, inner.y + j - 1, line, s)
        end
    end
end
app(_M())
-->

<!-- tachi:noeval -->
```julia
ring = FocusRing([widget1, widget2, widget3])
handle_key!(ring, evt)
current(ring)
next!(ring)
prev!(ring)
```

### Container

Group widgets with automatic layout:

<!-- tachi:widget container_basic w=50 h=10
gauge1 = Gauge(0.75; filled_style=tstyle(:primary), empty_style=tstyle(:text_dim, dim=true), tick=tick)
gauge2 = Gauge(0.45; filled_style=tstyle(:accent), empty_style=tstyle(:text_dim, dim=true), tick=tick)
spark = Sparkline([0.2, 0.5, 0.3, 0.8, 0.6, 0.9, 0.4, 0.7, 0.5, 0.6]; style=tstyle(:secondary))
container = Container(
    [gauge1, gauge2, spark],
    Layout(Vertical, [Fixed(1), Fixed(1), Fill()]),
    Block(title="Metrics", border_style=tstyle(:border), title_style=tstyle(:title))
)
render(container, area, buf)
-->
```julia
container = Container(
    [widget1, widget2, widget3],
    Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]),
    Block(title="Metrics")
)
```

### MarkdownPane

Scrollable CommonMark viewer with styled headings, bold/italic, inline code, code blocks with syntax highlighting, lists, block quotes, and horizontal rules. Requires the markdown extension (`enable_markdown()` or `using CommonMark`).

<!-- tachi:widget markdownpane_basic w=50 h=12
pane = MarkdownPane("# Hello\n\n**Bold**, *italic*, `code`.\n\n- Item 1\n- Item 2";
    block=Block(title="Docs"), width=48)
render(pane, area, buf)
-->
```julia
enable_markdown()
pane = MarkdownPane("# Hello\n\n**Bold**, *italic*, `code`.\n\n- Item 1\n- Item 2";
    block=Block(title="Docs"))
render(pane, area, buf)
```

Update content dynamically with `set_markdown!`:

<!-- tachi:noeval -->
```julia
set_markdown!(pane, "# Updated\n\nNew content here.")
```

Supports keyboard scrolling (`↑`/`↓`/`Page Up`/`Page Down`) and mouse wheel. Automatically reflows text when the render width changes.
