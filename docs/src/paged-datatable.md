# PagedDataTable

`PagedDataTable` is a virtual data table widget that delegates data fetching to a **provider**. Unlike `DataTable` which holds all data in memory, `PagedDataTable` requests data one page at a time — making it suitable for datasets of any size, from a few hundred rows to millions.

<!-- tachi:app paged_datatable_demo w=90 h=24 frames=300 fps=15 -->

## Provider Protocol

A provider is any subtype of `PagedDataProvider` that implements two methods.

Access the provider protocol types via `using Tachikoma.Paged`, and use `import` for functions you need to extend:

<!-- tachi:noeval -->
```julia
using Tachikoma.Paged
import Tachikoma.Paged: column_defs, fetch_page, supports_search, supports_filter

struct MyProvider <: PagedDataProvider
    # ... your state
end

# Required
column_defs(p::MyProvider) = [PagedColumn("Name"), PagedColumn("Score"; col_type=:numeric)]
fetch_page(p::MyProvider, req::PageRequest) = PageResult(rows, total_count)

# Optional
supports_search(::MyProvider) = true
supports_filter(::MyProvider) = true
filter_capabilities(::MyProvider) = FilterCapabilities()
```

### PagedColumn

Column definitions include type metadata so the UI knows which filter operators to offer:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `String` | required | Column header text |
| `width` | `Int` | `0` | Column width (0 = auto) |
| `align` | `ColumnAlign` | `col_left` | Text alignment |
| `format` | `Function` or `Nothing` | `nothing` | Value formatter `v -> String` |
| `filterable` | `Bool` | `true` | Whether column appears in filter modal |
| `sortable` | `Bool` | `true` | Whether column can be sorted |
| `col_type` | `Symbol` | `:text` | `:text` or `:numeric` — controls available filter operators |

### PageRequest

The request sent to `fetch_page`:

| Field | Type | Description |
|-------|------|-------------|
| `page` | `Int` | 1-based page number |
| `page_size` | `Int` | Rows per page |
| `sort_col` | `Int` | Column index to sort by (0 = no sort) |
| `sort_dir` | `SortDir` | `sort_none`, `sort_asc`, or `sort_desc` |
| `filters` | `Dict{Int,ColumnFilter}` | Per-column typed filters |
| `search` | `String` | Global search query |

### PageResult

<!-- tachi:noeval -->
```julia
PageResult(rows::Vector{Vector{Any}}, total_count::Int)
```

`rows` is row-major: each inner vector is one row with values in column order. `total_count` is the total number of matching rows (not just the page).

## Typed Filters

Filters use operators that depend on the column type:

### FilterOp

| Operator | Label | Numeric | Text |
|----------|-------|---------|------|
| `filter_contains` | "contains" | - | default |
| `filter_eq` | "=" | yes | yes |
| `filter_neq` | "≠" | yes | yes |
| `filter_gt` | ">" | yes | - |
| `filter_gte` | "≥" | yes | - |
| `filter_lt` | "<" | yes | - |
| `filter_lte` | "≤" | yes | - |
| `filter_regex` | "regex" | - | opt-in |
| `filter_wildcard` | "wildcard" | - | opt-in |

### FilterCapabilities

Providers declare which operators they support:

<!-- tachi:noeval -->
```julia
# Default capabilities
FilterCapabilities()
# text:    [filter_contains, filter_eq, filter_neq]
# numeric: [filter_eq, filter_neq, filter_gt, filter_gte, filter_lt, filter_lte]

# Custom capabilities (e.g. SQLite with REGEXP support)
FilterCapabilities(
    [filter_contains, filter_eq, filter_neq, filter_regex],  # text_ops
    [filter_eq, filter_neq, filter_gt, filter_gte, filter_lt, filter_lte],  # numeric_ops
)
```

### ColumnFilter

A filter applied to a column:

<!-- tachi:noeval -->
```julia
ColumnFilter(filter_gt, "1000")     # numeric: > 1000
ColumnFilter(filter_contains, "Kepler")  # text: contains "Kepler"
```

## Filter Modal

Press `f` to open the filter modal. It has three sections navigable with `Tab`:

1. **Column list** — `Up`/`Down` to select a column. Active filters show a badge. Press `x` to clear a filter.
2. **Operator** — `Left`/`Right` to select the operator. Options depend on column type and provider capabilities.
3. **Value input** — type the filter value, press `Enter` to apply.

`Escape` closes the modal without applying.

## Built-in Providers

### InMemoryPagedProvider

Wraps column-major `Vector{Vector{Any}}` data with in-process sorting, search, and filtering:

<!-- tachi:noeval -->
```julia
cols = [
    PagedColumn("Name"),
    PagedColumn("Score"; col_type=:numeric, align=col_right),
    PagedColumn("Status"),
]
data = Vector{Any}[names_vec, scores_vec, statuses_vec]
provider = InMemoryPagedProvider(cols, data)
```

### DataFrames / Tables.jl

With the `TachikomaTablesExt` extension (loaded automatically when `Tables.jl` is available), you can pass any Tables.jl-compatible source directly to `PagedDataTable`:

<!-- tachi:noeval -->
```julia
using DataFrames
using Tachikoma.Paged

df = DataFrame(name=["Alice", "Bob", "Carol"], score=[95, 87, 92], grade=["A", "B+", "A-"])
pdt = PagedDataTable(df)
```

<!-- tachi:widget pdt_dataframe w=60 h=10 -->
```julia
cols = [
    Tachikoma.Paged.PagedColumn("Name"),
    Tachikoma.Paged.PagedColumn("Score"; col_type=:numeric),
    Tachikoma.Paged.PagedColumn("Grade"),
    Tachikoma.Paged.PagedColumn("Status"),
]
data = Vector{Any}[
    Any["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"],
    Any[95, 82, 91, 78, 99, 85],
    Any["A", "B+", "A-", "C+", "A+", "B"],
    Any["Active", "Active", "Alumni", "Active", "Alumni", "Active"],
]
provider = Tachikoma.Paged.InMemoryPagedProvider(cols, data)
pdt = PagedDataTable(provider; page_size=6)
render(pdt, area, buf)
```

Column types are inferred automatically — numeric columns get numeric filter operators, everything else gets text filters. Sorting, search, and filtering all work out of the box.

This works with any Tables.jl source: DataFrames, CSV.File, TypedTables, Arrow tables, etc.

### SQLitePagedProvider (Extension)

The `TachikomaSQLiteExt` extension provides a SQLite-backed provider that translates filters to SQL `WHERE` clauses. Requires `SQLite.jl` and `DBInterface.jl`:

<!-- tachi:noeval -->
```julia
using SQLite, DBInterface
using Tachikoma

db = SQLite.DB("data.sqlite")
provider = SQLitePagedProvider(db, "my_table")
```

The extension:
- Introspects the table schema via `PRAGMA table_info` to auto-detect column types
- Registers a custom `REGEXP` function for regex filter support
- Translates `ColumnFilter` operators to SQL (`filter_contains` → `LIKE '%val%'`, `filter_gt` → `> val`, etc.)
- Supports global search, per-column filters, sorting, and pagination via SQL

Enable the extension:

<!-- tachi:noeval -->
```julia
Tachikoma.enable_sqlite()  # triggers loading of SQLite + DBInterface
```

## Access Model

- `using Tachikoma` exports `PagedDataTable` and `pdt_set_provider!` — enough to use the widget with an existing provider.
- `using Tachikoma.Paged` gives the full provider protocol: `PagedDataProvider`, `PagedColumn`, `PageRequest`, `PageResult`, `InMemoryPagedProvider`, all filter types, and the fetch/receive API.

## Widget Construction

<!-- tachi:noeval -->
```julia
using Tachikoma.Paged

pdt = PagedDataTable(provider;
    page_size=50,
    page_sizes=[25, 50, 100],
    detail_fn=(cols, row) -> [col.name => string(row[i]) for (i, col) in enumerate(cols)],
    on_fetch=nothing,  # set to enable async fetching
)
```

## Async Fetching

For non-blocking data loading, wire up the `on_fetch` callback:

<!-- tachi:noeval -->
```julia
tq = TaskQueue()
pdt = PagedDataTable(provider; page_size=50)

# Widget calls this instead of blocking fetch
pdt.on_fetch = () -> pdt_fetch_async!(pdt, tq; task_id=:pdt_fetch)

# In your update! handler:
function update!(model, evt::TaskEvent)
    if evt.id == :pdt_fetch
        if evt.value isa Exception
            pdt_receive_error!(pdt, evt.value)
        else
            pdt_receive!(pdt, evt.value)
        end
    end
end
```

## Runtime API

| Function | Description |
|----------|-------------|
| `pdt_set_provider!(pdt, provider)` | Switch to a new provider, resetting page/sort/filter state |
| `pdt_refresh!(pdt)` | Re-fetch the current page (respects `on_fetch` for async) |
| `pdt_set_page_size!(pdt, n)` | Change rows per page and re-fetch |
| `pdt_fetch!(pdt)` | Synchronous fetch (used by constructor and tests) |
| `pdt_fetch_async!(pdt, tq; task_id)` | Submit async fetch to a `TaskQueue` |
| `pdt_receive!(pdt, result)` | Deliver a `PageResult` from async fetch |
| `pdt_receive_error!(pdt, exception)` | Deliver an error from async fetch |

## Keyboard Controls

| Key | Action |
|-----|--------|
| `Up`/`Down` | Navigate rows within page |
| `PgUp`/`PgDn` | Previous/next page |
| `Home`/`End` | First/last page |
| `1`-`9` | Sort by column number |
| `/` | Toggle search input |
| `f` | Open filter modal |
| `g` | Go to page number |
| `d` or `Enter` | Open detail view (if `detail_fn` set) |
| `Left`/`Right` | Horizontal scroll (when columns overflow) |

Mouse scroll navigates rows. Click column headers to sort. Drag column borders to resize.

## Detail View

When `detail_fn` is provided, pressing `d` or `Enter` opens a modal showing all fields for the selected row:

<!-- tachi:noeval -->
```julia
function my_detail(columns::Vector{PagedColumn}, row_data::Vector{Any})
    [col.name => (col.format !== nothing ? col.format(row_data[i]) : string(row_data[i]))
     for (i, col) in enumerate(columns) if i <= length(row_data)]
end

pdt = PagedDataTable(provider; detail_fn=my_detail)
```

## Demo

The `paged_datatable_demo` showcases an exoplanet catalog with two switchable data sources:

- **Synthetic** — 1M deterministic rows with configurable latency and failure simulation
- **SQLite** — 50k rows in a temporary SQLite database with real SQL query execution

Press `s` to open settings, where you can switch data sources and configure simulation parameters (latency/failure controls only available for the synthetic source).

<!-- tachi:noeval -->
```julia
using TachikomaDemos
paged_datatable_demo()
```
