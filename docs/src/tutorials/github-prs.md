# GitHub Pull Requests

This tutorial builds a GitHub pull request viewer with an async data table, detail modal with markdown rendering, and shimmer animations — showcasing Tachikoma's async task system.

## What We'll Build

A `DataTable` showing open pull requests for a GitHub repository, fetched asynchronously. Press Enter to open a detail modal with the PR body rendered as markdown. The modal border uses `border_shimmer!` for visual polish.

<!-- tachi:begin github_prs_app -->

## Step 1: Data Types and Mock Data

```julia
using Tachikoma

struct PullRequest
    number::Int
    title::String
    url::String
    author::String
    body::String
    state::String
    created::String
    updated::String
    labels::Vector{String}
end

@enum LoadingState Idle Loading Loaded ErrorState

short_date(s::String) = length(s) >= 10 ? s[1:10] : s
```

We define a `PullRequest` struct to hold all the fields we care about. The `LoadingState` enum tracks where we are in the fetch lifecycle: `Idle` before any request, `Loading` during the async task, `Loaded` when data arrives, and `ErrorState` if the fetch fails. Note we use `ErrorState` instead of `Error` to avoid shadowing `Base.error`.

In a real app you would call the GitHub API. For this tutorial we use mock data so the demo runs without network access:

```julia
MOCK_PRS = [
    PullRequest(142, "Add WebSocket support for live updates", "",
        "motoko",
        "## Summary\nImplements WebSocket transport layer.\n\n- Handles reconnection\n- Binary frame support\n- Heartbeat mechanism",
        "open", "2025-01-15", "2025-01-18", ["enhancement", "networking"]),
    PullRequest(139, "Fix memory leak in connection pool", "",
        "batou",
        "## Problem\nConnections not released on timeout.\n\n## Fix\nAdded finalizer to pool entries.",
        "open", "2025-01-14", "2025-01-17", ["bug", "critical"]),
    PullRequest(137, "Refactor auth middleware stack", "",
        "kusanagi",
        "## Changes\nUnified OAuth and API-key paths.\n\n- Single `authenticate()` entry point\n- Token refresh handled transparently",
        "open", "2025-01-13", "2025-01-16", ["refactor"]),
    PullRequest(135, "Add dark mode to dashboard", "",
        "togusa",
        "## Overview\nCSS variables for theme switching.\n\n- Respects `prefers-color-scheme`\n- Manual toggle in settings",
        "open", "2025-01-12", "2025-01-15", ["enhancement", "ui"]),
    PullRequest(133, "Upgrade TLS to 1.3 across services", "",
        "ishikawa",
        "## Security\nForce TLS 1.3 minimum.\n\n- Updated certificate chain\n- Removed legacy cipher suites",
        "open", "2025-01-11", "2025-01-14", ["security"]),
    PullRequest(131, "Add rate limiting to public API", "",
        "saito",
        "## Implementation\nToken bucket algorithm.\n\n- 100 req/min default\n- Configurable per-route\n- Returns `Retry-After` header",
        "open", "2025-01-10", "2025-01-13", ["enhancement", "api"]),
]
```

## Step 2: Building the DataTable

```julia
function build_table(prs)
    DataTable([
        DataColumn("#",       [pr.number for pr in prs]; width=6, align=col_right),
        DataColumn("Author",  [pr.author for pr in prs]; width=16),
        DataColumn("Title",   [pr.title for pr in prs]),
        DataColumn("Updated", [short_date(pr.updated) for pr in prs]; width=10),
    ];
        selected = 1,
        block = Block(title="Pull Requests"),
    )
end
```

`DataTable` handles keyboard navigation, column layout, and alternating row styles. Each `DataColumn` has a header, data vector, and optional width and alignment. The `selected` field tracks which row has keyboard focus.

## Step 3: Define the Model

```julia
@kwdef mutable struct PRModel <: Model
    quit::Bool = false
    tick::Int = 0
    pull_requests::Vector{PullRequest} = PullRequest[]
    loading::LoadingState = Idle
    table::DataTable = DataTable([DataColumn("", String[])]; selected=1)
    tasks::TaskQueue = TaskQueue()
    detail_idx::Int = 0
    detail_pane::MarkdownPane = MarkdownPane("")
    error_msg::String = ""
end

should_quit(m::PRModel) = m.quit
task_queue(m::PRModel) = m.tasks
```

Key fields:
- `tasks` is the `TaskQueue` that Tachikoma drains each frame
- `detail_idx` is zero when no modal is showing; set it to a row index to open the detail view
- `detail_pane` is a `MarkdownPane` that renders the PR body as styled markdown

## Step 4: Async Data Fetching

```julia
function init!(m::PRModel, ::Terminal)
    m.loading = Loading
    spawn_task!(m.tasks, :pulls) do
        sleep(0.05)  # simulate network latency
        MOCK_PRS
    end
end
```

The `init!` callback runs once when the app starts. We spawn a background task that returns our mock data. In a real app you would replace the body with an HTTP call to the GitHub API — the async pattern is identical.

When the task completes, Tachikoma delivers a `TaskEvent` on the main thread:

```julia
function update!(m::PRModel, evt::TaskEvent)
    evt.id == :pulls || return
    if evt.value isa Exception
        m.loading = ErrorState
        m.error_msg = sprint(showerror, evt.value)
    else
        m.loading = Loaded
        m.pull_requests = evt.value
        m.table = build_table(m.pull_requests)
    end
end
```

If the task returned an exception, we switch to `ErrorState` and store the message. Otherwise we store the pull requests and build the `DataTable`.

## Step 5: Handle Keyboard Events

```julia
function update!(m::PRModel, evt::KeyEvent)
    if m.detail_idx > 0
        # Modal is open — Escape closes it, arrows scroll the markdown
        if evt.key == :escape
            m.detail_idx = 0
        else
            handle_key!(m.detail_pane, evt)
        end
        return
    end

    # No modal — handle table navigation and app keys
    if evt.key == :escape
        m.quit = true
    elseif evt.key == :enter && m.loading == Loaded
        idx = m.table.selected
        if 1 <= idx <= length(m.pull_requests)
            m.detail_idx = idx
            pr = m.pull_requests[idx]
            m.detail_pane = MarkdownPane(pr.body;
                block=Block(title="$(pr.title)",
                            border_style=tstyle(:border),
                            title_style=tstyle(:title, bold=true)))
        end
    else
        handle_key!(m.table, evt)
    end
end
```

When the modal is open, Escape closes it and arrow keys scroll the `MarkdownPane`. When the modal is closed, Enter opens the detail view for the selected PR, and all other navigation keys are forwarded to the `DataTable` via `handle_key!`.

## Step 6: Render Helpers

The body area dispatches on `LoadingState`:

```julia
function render_body(m, buf, area)
    if m.loading == Loading
        si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
        msg = " $(SPINNER_BRAILLE[si]) Fetching pull requests..."
        tx = area.x + max(0, (area.width - length(msg)) ÷ 2)
        ty = area.y + area.height ÷ 2
        set_string!(buf, tx, ty, msg, tstyle(:text_dim))
    elseif m.loading == ErrorState
        render(Paragraph(m.error_msg; style=tstyle(:error),
               block=Block(title="Error")), area, buf)
    else
        render(m.table, area, buf)
    end
end
```

During `Loading` we show a centered braille spinner. On `ErrorState` we render the error message in a `Paragraph`. Once `Loaded`, we render the `DataTable`.

The detail modal overlays the full screen with an animated border:

```julia
function render_detail_modal(m, buf, area)
    pr = m.pull_requests[m.detail_idx]

    # Dim the background
    for row in area.y:bottom(area)
        for col in area.x:right(area)
            set_char!(buf, col, row, ' ', tstyle(:text_dim))
        end
    end

    # Center modal at ~80% of screen
    mw = clamp(area.width * 4 ÷ 5, 40, area.width - 2)
    mh = clamp(area.height * 3 ÷ 4, 12, area.height - 2)
    modal_rect = center(area, mw, mh)

    # Animated border
    border_shimmer!(buf, modal_rect, to_rgb(theme().accent), m.tick; intensity=0.10)
    inner = shrink(modal_rect, 1)
    inner.height < 4 && return

    # Metadata header
    y = inner.y
    set_string!(buf, inner.x, y, "#$(pr.number)", tstyle(:accent, bold=true);
                max_x=right(inner))
    set_string!(buf, inner.x + length("#$(pr.number)") + 1, y,
                "by $(pr.author)", tstyle(:text_dim); max_x=right(inner))
    y += 1

    if !isempty(pr.labels)
        label_str = join(pr.labels, " · ")
        set_string!(buf, inner.x, y, label_str, tstyle(:primary); max_x=right(inner))
        y += 1
    end
    y += 1

    # Scrollable markdown body
    body_area = Rect(inner.x, y, inner.width, inner.height - (y - inner.y))
    body_area.height > 0 && render(m.detail_pane, body_area, buf)
end
```

The modal dims the background, draws a `border_shimmer!` border, shows PR metadata (number, author, labels), and renders the body markdown in a scrollable `MarkdownPane`.

## Step 7: The View

```julia
function view(m::PRModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Layout: header | body | status bar
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return

    # Header
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, rows[1].x, rows[1].y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, rows[1].x + 2, rows[1].y,
                "GitHub PRs $(DOT) $(f.area.width)×$(f.area.height)",
                tstyle(:title, bold=true))

    # Body
    render_body(m, buf, rows[2])

    # Status bar
    if m.detail_idx > 0
        render(StatusBar(
            left=[Span(" [↑↓] scroll  [Esc] close ", tstyle(:text_dim))],
            right=[Span("PR #$(m.pull_requests[m.detail_idx].number) ", tstyle(:accent))],
        ), rows[3], buf)
    else
        render(StatusBar(
            left=[Span(" [↑↓] navigate  [Enter] details  [Esc] quit ", tstyle(:text_dim))],
            right=[Span("$(length(m.pull_requests)) PRs ", tstyle(:text_dim))],
        ), rows[3], buf)
    end

    # Modal overlay
    if m.detail_idx > 0
        render_detail_modal(m, buf, f.area)
    end
end
```

The view has three rows: a header with a spinner, the body dispatched by `render_body`, and a context-sensitive status bar. When `detail_idx > 0`, the modal is drawn on top of everything.

## Step 8: Run It

<!-- tachi:app github_prs_app w=80 h=24 frames=120 fps=15 chrome -->
```julia
app(PRModel())
```

## Key Techniques

1. **`TaskQueue` + `spawn_task!`** — non-blocking data fetch that keeps the UI responsive
2. **`TaskEvent` handling** — update the model when async work completes or fails
3. **`DataTable`** — scrollable, navigable data display with configurable columns
4. **`MarkdownPane`** — rich CommonMark rendering in the terminal with keyboard scrolling
5. **`border_shimmer!`** — animated modal border driven by noise for organic visual polish
6. **Modal overlay pattern** — dim the background, center a rect, draw content on top

## Exercises

- Add column sorting by clicking headers
- Add a search/filter input above the table
- Add label-based filtering (show only PRs with specific labels)
- Add refresh with automatic polling using a timer task
