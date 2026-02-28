# Build a Dashboard

This tutorial builds a multi-pane system monitor dashboard with live-updating gauges, sparklines, a process table, and a log viewer.

## What We'll Build

A dashboard with four sections: CPU/memory gauges, network sparklines, a process table, and a scrollable log list — all driven by simulated data that updates each frame.

<!-- tachi:begin dashboard_app -->

## Step 1: Define the Model

```julia
using Tachikoma
@tachikoma_app

@kwdef mutable struct Dashboard <: Model
    quit::Bool = false
    tick::Int = 0
    # Simulated metrics
    cpu::Float64 = 0.45
    mem::Float64 = 0.62
    net_history::Vector{Float64} = zeros(60)
    cpu_history::Vector{Float64} = zeros(60)
    # Log list state
    log_selected::Int = 1
end

should_quit(m::Dashboard) = m.quit
```

## Step 2: Simulated Data

We'll use sinusoidal functions to generate realistic-looking metrics:

```julia
LOGS = [
    "system    boot sequence complete",
    "net       interface eth0 up",
    "auth      session opened for user tachikoma",
    "kernel    loaded module tachikoma_core",
    "firewall  rule ACCEPT tcp/443 applied",
    "monitor   cpu governor: performance",
    "storage   /dev/sda1 mounted at /",
    "net       DNS resolver configured",
    "system    all services nominal",
]

PROCS = [
    ["tachikoma", "running", "12.3%", "148 MB"],
    ["section9",  "running", " 8.1%", " 96 MB"],
    ["motoko_ai", "running", "22.8%", "512 MB"],
    ["batou_srv", "running", " 3.2%", " 52 MB"],
    ["togusa_db", "idle",    " 1.1%", " 31 MB"],
]
```

## Step 3: Handle Events

```julia
function update!(m::Dashboard, evt::KeyEvent)
    if evt.key == :char && evt.char == 'q'
        m.quit = true
    elseif evt.key == :up
        m.log_selected = max(1, m.log_selected - 1)
    elseif evt.key == :down
        m.log_selected = min(length(LOGS), m.log_selected + 1)
    elseif evt.key == :escape
        m.quit = true
    end
end
```

## Step 4: Build the Layout

The dashboard uses nested layouts:

<!-- tachi:widget dashboard_layout w=54 h=16
main = render(Block(title="tachikoma dashboard", border_style=tstyle(:border), title_style=tstyle(:title, bold=true)), area, buf)
rows = split_layout(Layout(Vertical, [Fixed(1), Fixed(6), Fixed(1), Fill(), Fixed(1)]), main)
length(rows) >= 5 || return
set_string!(buf, rows[1].x, rows[1].y, "⠋ kokaku · 54×16 · tick 42", tstyle(:primary, bold=true))
top_cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), rows[2])
length(top_cols) >= 2 && render(Block(title="system", border_style=tstyle(:border), title_style=tstyle(:text_dim)), top_cols[1], buf)
length(top_cols) >= 2 && render(Block(title="network", border_style=tstyle(:border), title_style=tstyle(:text_dim)), top_cols[2], buf)
si = Rect(top_cols[1].x+1, top_cols[1].y+1, top_cols[1].width-2, top_cols[1].height-2)
set_string!(buf, si.x, si.y, "CPU", tstyle(:text, bold=true))
set_string!(buf, si.x, si.y+1, "████████░░░ 73%", tstyle(:accent))
set_string!(buf, si.x, si.y+2, "MEM", tstyle(:text, bold=true))
set_string!(buf, si.x, si.y+3, "██████░░░░ 62%", tstyle(:success))
ni = Rect(top_cols[2].x+1, top_cols[2].y+1, top_cols[2].width-2, top_cols[2].height-2)
set_string!(buf, ni.x, ni.y, "throughput", tstyle(:text_dim))
set_string!(buf, ni.x, ni.y+1, "▁▃▅▇▆▃▁▂▅▇▆▄▂▁▃▅▇", tstyle(:accent))
set_string!(buf, ni.x, ni.y+2, "cpu load", tstyle(:text_dim))
set_string!(buf, ni.x, ni.y+3, "▃▄▅▆▅▄▃▃▄▅▆▇▆▅▃▄▅", tstyle(:warning))
for x in rows[3].x:rows[3].x+rows[3].width-1
    set_char!(buf, x, rows[3].y, '╌', tstyle(:border))
end
bot_cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), rows[4])
length(bot_cols) >= 2 && render(Block(title="processes", border_style=tstyle(:border), title_style=tstyle(:text_dim)), bot_cols[1], buf)
length(bot_cols) >= 2 && render(Block(title="logs", border_style=tstyle(:border), title_style=tstyle(:text_dim)), bot_cols[2], buf)
bi = Rect(bot_cols[1].x+1, bot_cols[1].y+1, bot_cols[1].width-2, bot_cols[1].height-2)
set_string!(buf, bi.x, bi.y, "NAME    STATUS", tstyle(:text, bold=true))
set_string!(buf, bi.x, bi.y+1, "nginx   ● up", tstyle(:success))
set_string!(buf, bi.x, bi.y+2, "redis   ● up", tstyle(:success))
li = Rect(bot_cols[2].x+1, bot_cols[2].y+1, bot_cols[2].width-2, bot_cols[2].height-2)
set_string!(buf, li.x, li.y, "▸ system  boot sequence", tstyle(:accent))
set_string!(buf, li.x, li.y+1, "  net     interface eth0 up", tstyle(:text_dim))
set_string!(buf, li.x, li.y+2, "  disk    mount /dev/sda1", tstyle(:text_dim))
render(StatusBar(left=[Span(" [↑↓]scroll [q]quit ", tstyle(:text_dim))]), rows[5], buf)
-->

## Step 5: Render the View

```julia
function view(m::Dashboard, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Simulate data
    t = m.tick / 30.0
    m.cpu = clamp(0.35 + 0.25 * sin(t * 0.7) + 0.1 * sin(t * 2.3), 0.05, 0.95)
    m.mem = clamp(0.60 + 0.08 * sin(t * 0.3), 0.4, 0.85)
    push!(m.net_history, clamp(0.4 + 0.35 * sin(t * 1.1) + 0.05 * randn(), 0.0, 1.0))
    length(m.net_history) > 120 && popfirst!(m.net_history)
    push!(m.cpu_history, m.cpu)
    length(m.cpu_history) > 120 && popfirst!(m.cpu_history)

    # Outer border
    outer = Block(title="tachikoma dashboard",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title, bold=true))
    main = render(outer, f.area, buf)

    # Layout: header | top gauges | separator | bottom tables
    rows = split_layout(
        Layout(Vertical, [Fixed(1), Fixed(8), Fixed(1), Fill()]), main)
    length(rows) < 4 && return

    # ── Header with spinner ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, rows[1].x, rows[1].y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, rows[1].x + 2, rows[1].y,
                "$(theme().name) $(DOT) $(f.area.width)×$(f.area.height)",
                tstyle(:primary, bold=true))

    # ── Top: gauges (40%) + sparklines (60%) ──
    top_cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), rows[2])
    render_gauges!(buf, top_cols[1], m)
    render_sparklines!(buf, top_cols[2], m)

    # ── Separator ──
    for cx in main.x:right(main)
        set_char!(buf, cx, rows[3].y, SCANLINE, tstyle(:border, dim=true))
    end

    # ── Bottom: table (55%) + log list (45%) ──
    bot_cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), rows[4])
    render_table!(buf, bot_cols[1])
    render_logs!(buf, bot_cols[2], m)
end
```

## Step 6: Render Helper Functions

### Gauges

```julia
function render_gauges!(buf, area, m)
    block = Block(title="system", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)
    inner.height < 6 && return

    y = inner.y
    set_string!(buf, inner.x, y, "CPU", tstyle(:text, bold=true))
    render(Gauge(m.cpu; filled_style=tstyle(:primary),
                 empty_style=tstyle(:text_dim, dim=true), tick=m.tick),
           Rect(inner.x, y + 1, inner.width, 1), buf)

    set_string!(buf, inner.x, y + 3, "MEM", tstyle(:text, bold=true))
    render(Gauge(m.mem; filled_style=tstyle(:secondary),
                 empty_style=tstyle(:text_dim, dim=true), tick=m.tick),
           Rect(inner.x, y + 4, inner.width, 1), buf)
end
```

### Sparklines

```julia
function render_sparklines!(buf, area, m)
    block = Block(title="network", border_style=tstyle(:border),
                  title_style=tstyle(:text_dim))
    inner = render(block, area, buf)
    inner.height < 2 && return

    spark_rows = split_layout(
        Layout(Vertical, [Fixed(1), Fill(), Fixed(1), Fill()]), inner)
    length(spark_rows) >= 4 || return

    set_string!(buf, spark_rows[1].x, spark_rows[1].y, "throughput",
                tstyle(:text_dim))
    render(Sparkline(m.net_history; style=tstyle(:accent)), spark_rows[2], buf)

    set_string!(buf, spark_rows[3].x, spark_rows[3].y, "cpu load",
                tstyle(:text_dim))
    render(Sparkline(m.cpu_history; style=tstyle(:primary)), spark_rows[4], buf)
end
```

### Process Table

```julia
function render_table!(buf, area)
    render(Table(
        ["NAME", "STATUS", "CPU", "MEM"], PROCS;
        block=Block(title="processes", border_style=tstyle(:border),
                    title_style=tstyle(:text_dim)),
        header_style=tstyle(:title, bold=true),
        row_style=tstyle(:text),
        alt_row_style=tstyle(:text_dim),
    ), area, buf)
end
```

### Log List

```julia
function render_logs!(buf, area, m)
    render(SelectableList(
        [ListItem(l, tstyle(:text)) for l in LOGS];
        selected=m.log_selected,
        block=Block(title="logs", border_style=tstyle(:border),
                    title_style=tstyle(:text_dim)),
        highlight_style=tstyle(:accent, bold=true),
        tick=m.tick,
    ), area, buf)
end
```

## Step 7: Run It

<!-- tachi:app dashboard_app w=80 h=24 frames=240 fps=15 chrome -->
```julia
app(Dashboard())
```

## Key Techniques

1. **Nested layouts** — Vertical outer split, then horizontal inner splits for each row
2. **Tick-driven data** — Simulated metrics update every frame using `sin` and `randn`
3. **History buffers** — Push/pop vectors feed into `Sparkline` for rolling charts
4. **Block borders** — Every section is wrapped in a `Block` for visual separation
5. **Theme-aware styles** — `tstyle(:primary)`, `tstyle(:text_dim)` etc. adapt to any theme

## Exercises

- Add a `ResizableLayout` so users can drag pane borders
- Add mouse click handling for the log list with `list_hit`
- Add a `BarChart` showing disk usage
- Add scroll support to the log list with `list_scroll`
