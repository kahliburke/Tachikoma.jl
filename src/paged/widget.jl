# ── Widget ────────────────────────────────────────────────────────────

mutable struct PagedDataTable
    # Provider
    provider::PagedDataProvider
    columns::Vector{PagedColumn}        # cached from column_defs

    # Page state
    page::Int                           # 1-based current page
    page_size::Int
    page_sizes::Vector{Int}             # selectable page sizes (e.g. [25, 50, 100])
    total_count::Int
    rows::Vector{Vector{Any}}           # cached page data (row-major)

    # Selection
    selected::Int                       # 1-based within page, 0 = none
    row_offset::Int                     # scroll offset within page (0-based)

    # Sort
    sort_col::Int                       # 0 = no sort
    sort_dir::SortDir

    # Filters
    filters::Dict{Int,ColumnFilter}
    filter_modal::FilterModalState

    # Search
    search_query::String
    search_input::TextInput
    search_visible::Bool

    # Go-to-page
    goto_input::TextInput
    goto_visible::Bool

    # Column resize (same pattern as DataTable)
    col_widths::Vector{Int}
    col_drag::Int
    col_drag_start_x::Int
    col_drag_start_w::Int
    col_hover_border::Int
    col_offset::Int                     # horizontal scroll

    # Detail view
    detail_fn::Union{Function, Nothing} # (columns, row_data) -> Vector{Pair}
    show_detail::Bool
    detail_row::Int                     # index within page
    detail_scroll::Int

    # Styling
    block::Union{Block, Nothing}
    style::Style
    header_style::Style
    selected_style::Style
    alt_style::Style
    footer_style::Style
    tick::Union{Int, Nothing}

    # Cached hit rects
    last_content_area::Rect
    last_col_positions::Vector{Tuple{Int,Int}}
    last_computed_widths::Vector{Int}         # from most recent render
    last_footer_area::Rect
    last_prev_rect::Rect
    last_next_rect::Rect
    last_page_size_rects::Vector{Tuple{Rect,Int}} # (rect, page_size)

    # Loading/error
    loading::Bool
    error_msg::String

    # Async hook: when set, called instead of pdt_fetch!() for data refreshes.
    # Signature: () -> nothing. The callback should call pdt_fetch_async!.
    on_fetch::Union{Function, Nothing}
end

function PagedDataTable(provider::PagedDataProvider;
    page::Int=1,
    page_size::Int=50,
    page_sizes::Vector{Int}=Int[25, 50, 100],
    selected::Int=1,
    block::Union{Block, Nothing}=nothing,
    style::Style=tstyle(:text),
    header_style::Style=tstyle(:title, bold=true),
    selected_style::Style=tstyle(:accent, bold=true),
    alt_style::Style=tstyle(:text, dim=true),
    footer_style::Style=tstyle(:text_dim),
    tick::Union{Int, Nothing}=nothing,
    detail_fn::Union{Function, Nothing}=nothing,
    on_fetch::Union{Function, Nothing}=nothing,
)
    cols = column_defs(provider)
    search_input = TextInput(; label="Search: ", focused=true)
    goto_input = TextInput(; label="Go to page: ", focused=true)

    pdt = PagedDataTable(
        provider, cols,
        page, page_size, page_sizes, 0, Vector{Any}[],  # page state
        selected, 0,                                      # selection
        0, sort_none,                                     # sort
        Dict{Int,ColumnFilter}(), FilterModalState(),     # filters
        "", search_input, false,                           # search
        goto_input, false,                                 # goto
        Int[], 0, 0, 0, 0, 0,                             # col resize + h-scroll
        detail_fn, false, 0, 0,                            # detail
        block, style, header_style, selected_style, alt_style, footer_style, tick,
        Rect(), Tuple{Int,Int}[], Int[], Rect(), Rect(), Rect(), Tuple{Rect,Int}[],
        false, "",                                         # loading/error
        on_fetch,                                          # async hook
    )
    pdt_fetch!(pdt)  # sync initial load
    pdt
end

# ── Data flow ─────────────────────────────────────────────────────────

"""Build a PageRequest from current widget state."""
function _pdt_build_request(pdt::PagedDataTable)
    PageRequest(
        pdt.page, pdt.page_size,
        pdt.sort_col, pdt.sort_dir,
        Dict{Int,ColumnFilter}(k => v for (k, v) in pdt.filters if !isempty(v.value)),
        pdt.search_query,
    )
end

"""Synchronous fetch — blocks until data is available. Used by constructor and tests."""
function pdt_fetch!(pdt::PagedDataTable)
    req = _pdt_build_request(pdt)
    try
        pdt.loading = true
        result = fetch_page(pdt.provider, req)
        pdt_receive!(pdt, result)
    catch e
        pdt_receive_error!(pdt, e)
    end
end

"""
    pdt_fetch_async!(pdt, queue; task_id=:pdt_fetch)

Non-blocking fetch — spawns the provider call on a background thread.
The result arrives as a `TaskEvent{PageResult}` or `TaskEvent{Exception}`.
Call `pdt_receive!` from your `update!(model, ::TaskEvent)` handler.
"""
function pdt_fetch_async!(pdt::PagedDataTable, queue::TaskQueue;
                           task_id::Symbol=:pdt_fetch)
    req = _pdt_build_request(pdt)
    pdt.loading = true
    pdt.error_msg = ""
    provider = pdt.provider
    spawn_task!(queue, task_id) do
        fetch_page(provider, req)
    end
end

"""Apply a successful PageResult to the widget."""
function pdt_receive!(pdt::PagedDataTable, result::PageResult)
    pdt.rows = result.rows
    pdt.total_count = result.total_count
    pdt.error_msg = ""
    pdt.loading = false
    _pdt_clamp_state!(pdt)
end

"""Apply a fetch error to the widget."""
function pdt_receive_error!(pdt::PagedDataTable, e::Exception)
    pdt.rows = Vector{Any}[]
    pdt.error_msg = sprint(showerror, e)
    pdt.loading = false
    _pdt_clamp_state!(pdt)
end

"""Clamp page/selection after data changes."""
function _pdt_clamp_state!(pdt::PagedDataTable)
    max_page = _pdt_max_page(pdt)
    pdt.page = clamp(pdt.page, 1, max(1, max_page))
    n = length(pdt.rows)
    pdt.selected = n == 0 ? 0 : clamp(pdt.selected, 1, n)
    pdt.row_offset = 0
end

"""Trigger a data refresh — uses async hook if set, otherwise sync fetch."""
function pdt_refresh!(pdt::PagedDataTable)
    if pdt.on_fetch !== nothing
        pdt.on_fetch()
    else
        pdt_fetch!(pdt)
    end
end

_pdt_max_page(pdt::PagedDataTable) = max(1, cld(pdt.total_count, pdt.page_size))

_pdt_nrows(pdt::PagedDataTable) = length(pdt.rows)

function _pdt_format_cell(col::PagedColumn, row_data::Vector{Any}, col_idx::Int)
    col_idx > length(row_data) && return ""
    v = row_data[col_idx]
    col.format !== nothing ? col.format(v) : string(v)
end

# ── Widget protocol ───────────────────────────────────────────────────

value(pdt::PagedDataTable) = pdt.selected
function set_value!(pdt::PagedDataTable, idx::Int)
    pdt.selected = clamp(idx, 0, _pdt_nrows(pdt))
    nothing
end
focusable(::PagedDataTable) = true

"""Default detail view: shows each column name paired with its value."""
function _pdt_default_detail(columns::Vector{PagedColumn}, row_data::Vector{Any})
    [col.name => (col.format !== nothing ? col.format(row_data[i]) : string(row_data[i]))
     for (i, col) in enumerate(columns) if i <= length(row_data)]
end

"""Return the effective detail function (custom or built-in default)."""
_pdt_detail_fn(pdt::PagedDataTable) = pdt.detail_fn !== nothing ? pdt.detail_fn : _pdt_default_detail

# ── Key handling ──────────────────────────────────────────────────────

function handle_key!(pdt::PagedDataTable, evt::KeyEvent)::Bool
    # Detail view intercepts all keys when open
    if pdt.show_detail
        return _pdt_handle_detail_key!(pdt, evt)
    end

    # Search input active
    if pdt.search_visible
        return _pdt_handle_search_key!(pdt, evt)
    end

    # Filter modal active
    if pdt.filter_modal.visible
        return _pdt_handle_filter_modal_key!(pdt, evt)
    end

    # Go-to-page input active
    if pdt.goto_visible
        return _pdt_handle_goto_key!(pdt, evt)
    end

    # Retry after error
    if !isempty(pdt.error_msg) && evt.key == :char && evt.char == 'r'
        pdt.error_msg = ""
        pdt_refresh!(pdt)
        return true
    end

    n = _pdt_nrows(pdt)

    # Open detail view
    if evt.key == :enter || (evt.key == :char && evt.char == 'd')
        if pdt.selected > 0 && pdt.selected <= n
            pdt.show_detail = true
            pdt.detail_row = pdt.selected
            pdt.detail_scroll = 0
            return true
        end
    end

    # Toggle search
    if evt.key == :char && evt.char == '/'
        if supports_search(pdt.provider)
            pdt.search_visible = !pdt.search_visible
            if pdt.search_visible
                pdt.search_input.focused = true
            end
            return true
        end
    end

    # Open filter modal
    if evt.key == :char && evt.char == 'f'
        if supports_filter(pdt.provider)
            _pdt_open_filter_modal!(pdt)
            return true
        end
    end

    # Go to page
    if evt.key == :char && evt.char == 'g'
        pdt.goto_visible = true
        pdt.goto_input.focused = true
        # Clear previous text
        empty!(pdt.goto_input.buffer)
        pdt.goto_input.cursor = 0
        return true
    end

    # Sort by column number
    if evt.key == :char && '1' <= evt.char <= '9'
        col_num = Int(evt.char) - Int('0')
        if col_num <= length(pdt.columns) && pdt.columns[col_num].sortable
            _pdt_sort_by!(pdt, col_num)
            return true
        end
    end

    # Row navigation — stops at page boundaries
    if evt.key == :up
        if n > 0 && pdt.selected > 1
            pdt.selected -= 1
        end
        return true
    elseif evt.key == :down
        if n > 0 && pdt.selected < n
            pdt.selected += 1
        end
        return true
    end

    # Page navigation
    if evt.key == :pageup
        if pdt.page > 1
            pdt.page -= 1
            pdt_refresh!(pdt)
        end
        return true
    elseif evt.key == :pagedown
        if pdt.page < _pdt_max_page(pdt)
            pdt.page += 1
            pdt_refresh!(pdt)
        end
        return true
    elseif evt.key == :home
        if pdt.page != 1
            pdt.page = 1
            pdt_refresh!(pdt)
        end
        return true
    elseif evt.key == :end_key
        mp = _pdt_max_page(pdt)
        if pdt.page != mp
            pdt.page = mp
            pdt_refresh!(pdt)
        end
        return true
    end

    # Horizontal scroll
    if evt.key == :left
        if pdt.col_offset > 0
            pdt.col_offset -= 1
            return true
        end
    elseif evt.key == :right
        nc = length(pdt.columns)
        data_w = max(10, pdt.last_content_area.width - 2)
        max_off = max(0, nc - _pdt_visible_cols(pdt, data_w))
        if pdt.col_offset < max_off
            pdt.col_offset += 1
            return true
        end
    end

    false
end

function _pdt_handle_detail_key!(pdt::PagedDataTable, evt::KeyEvent)::Bool
    if evt.key == :escape || (evt.key == :char && evt.char == 'd')
        pdt.show_detail = false
        return true
    end
    if evt.key == :up
        pdt.detail_scroll = max(0, pdt.detail_scroll - 1)
        return true
    elseif evt.key == :down
        max_scroll = max(0, length(pdt.columns) - 1)
        pdt.detail_scroll = min(pdt.detail_scroll + 1, max_scroll)
        return true
    end
    true  # consume all keys while detail is open
end

function _pdt_handle_search_key!(pdt::PagedDataTable, evt::KeyEvent)::Bool
    if evt.key == :escape
        pdt.search_visible = false
        return true
    end
    if evt.key == :enter
        pdt.search_query = text(pdt.search_input)
        pdt.page = 1
        pdt_refresh!(pdt)
        pdt.search_visible = false
        return true
    end
    handle_key!(pdt.search_input, evt)
    true
end

function _pdt_handle_goto_key!(pdt::PagedDataTable, evt::KeyEvent)::Bool
    if evt.key == :escape
        pdt.goto_visible = false
        return true
    end
    if evt.key == :enter
        input_text = text(pdt.goto_input)
        pdt.goto_visible = false
        target = tryparse(Int, strip(input_text))
        if target !== nothing
            mp = _pdt_max_page(pdt)
            target = clamp(target, 1, mp)
            if target != pdt.page
                pdt.page = target
                pdt_refresh!(pdt)
            end
        end
        return true
    end
    handle_key!(pdt.goto_input, evt)
    true
end

# ── Sort ──────────────────────────────────────────────────────────────

function _pdt_sort_by!(pdt::PagedDataTable, col_idx::Int)
    if pdt.sort_col == col_idx
        pdt.sort_dir = if pdt.sort_dir == sort_none
            sort_asc
        elseif pdt.sort_dir == sort_asc
            sort_desc
        else
            sort_none
        end
    else
        pdt.sort_col = col_idx
        pdt.sort_dir = sort_asc
    end
    pdt.page = 1
    pdt_refresh!(pdt)
end

# ── Page size helpers ─────────────────────────────────────────────────

function _pdt_prev_page_size!(pdt::PagedDataTable)
    isempty(pdt.page_sizes) && return
    idx = findfirst(==(pdt.page_size), pdt.page_sizes)
    if idx !== nothing && idx > 1
        pdt_set_page_size!(pdt, pdt.page_sizes[idx - 1])
    end
end

function _pdt_next_page_size!(pdt::PagedDataTable)
    isempty(pdt.page_sizes) && return
    idx = findfirst(==(pdt.page_size), pdt.page_sizes)
    if idx !== nothing && idx < length(pdt.page_sizes)
        pdt_set_page_size!(pdt, pdt.page_sizes[idx + 1])
    end
end

function pdt_set_page_size!(pdt::PagedDataTable, new_size::Int)
    old_first_row = (pdt.page - 1) * pdt.page_size + 1
    pdt.page_size = new_size
    pdt.page = max(1, cld(old_first_row, new_size))
    pdt_refresh!(pdt)
end

"""
    pdt_set_provider!(pdt::PagedDataTable, provider::PagedDataProvider)

Switch the data provider with automatic state reset. Resets page, filters,
search, column widths, and re-fetches data from the new provider.
"""
function pdt_set_provider!(pdt::PagedDataTable, provider::PagedDataProvider)
    pdt.provider = provider
    pdt.columns = column_defs(provider)
    empty!(pdt.col_widths)
    pdt.page = 1
    pdt.filters = Dict{Int,ColumnFilter}()
    pdt.search_query = ""
    pdt.sort_col = 0
    pdt.sort_dir = sort_none
    pdt_refresh!(pdt)
end

# ── Mouse handling ────────────────────────────────────────────────────

function handle_mouse!(pdt::PagedDataTable, evt::MouseEvent)::Bool
    pdt.last_content_area.width > 0 || return false

    # Column drag (active)
    if pdt.col_drag > 0
        if evt.action == mouse_drag
            delta = evt.x - pdt.col_drag_start_x
            new_w = max(3, pdt.col_drag_start_w + delta)
            if length(pdt.col_widths) >= pdt.col_drag
                pdt.col_widths[pdt.col_drag] = new_w
            end
            return true
        end
        if evt.action == mouse_release
            pdt.col_drag = 0
            return true
        end
    end

    # Mouse move: hover on column borders
    if evt.action == mouse_move
        pdt.col_hover_border = _pdt_find_border(pdt, evt.x)
        return pdt.col_hover_border > 0
    end

    # Footer interactions
    if _pdt_handle_footer_mouse!(pdt, evt)
        return true
    end

    content_area = pdt.last_content_area

    # Left press on column border → start drag
    if evt.button == mouse_left && evt.action == mouse_press
        border_idx = _pdt_find_border(pdt, evt.x)
        header_y = content_area.y + (pdt.search_visible ? 1 : 0)
        if border_idx > 0 && (evt.y == header_y || evt.y == header_y + 1)
            pdt.col_drag = border_idx
            pdt.col_drag_start_x = evt.x
            manual_w = border_idx <= length(pdt.col_widths) ? pdt.col_widths[border_idx] : 0
            if manual_w > 0
                pdt.col_drag_start_w = manual_w
            elseif border_idx <= length(pdt.last_computed_widths)
                pdt.col_drag_start_w = pdt.last_computed_widths[border_idx]
            else
                pdt.col_drag_start_w = 10
            end
            return true
        end

        # Click on header → sort or filter
        if evt.y == header_y && evt.x >= content_area.x + 1
            col_idx = _pdt_col_at_x(pdt, evt.x)
            if col_idx > 0 && col_idx <= length(pdt.columns)
                col = pdt.columns[col_idx]
                # Check if click is on the filter indicator (⊘) at end of header
                if col.sortable
                    _pdt_sort_by!(pdt, col_idx)
                    return true
                elseif col.filterable && supports_filter(pdt.provider)
                    _pdt_open_filter_modal!(pdt)
                    return true
                end
            end
        end

        # Click on search bar → focus
        if pdt.search_visible
            if handle_mouse!(pdt.search_input, evt)
                return true
            end
        end

        # Click on filter modal value input → focus
        if pdt.filter_modal.visible && pdt.filter_modal.section == 3
            if handle_mouse!(pdt.filter_modal.value_input, evt)
                return true
            end
        end
    end

    # Row selection via click
    search_rows = pdt.search_visible ? 1 : 0
    goto_rows = pdt.goto_visible ? 1 : 0
    header_offset = 2 + search_rows + goto_rows  # header + separator + search + goto
    vis_h = content_area.height - header_offset - 1  # -1 for footer
    data_area = Rect(content_area.x, content_area.y + header_offset, content_area.width, vis_h)

    n = _pdt_nrows(pdt)
    hit = list_hit(evt, data_area, pdt.row_offset, n)
    if hit > 0
        pdt.selected = hit
        return true
    end

    # Scroll within page — move selection and viewport together
    if (evt.button == mouse_scroll_up || evt.button == mouse_scroll_down) && evt.action == mouse_press
        if Base.contains(data_area, evt.x, evt.y)
            if evt.button == mouse_scroll_up
                if pdt.selected > 1
                    pdt.selected -= 1
                end
            else
                if pdt.selected < n
                    pdt.selected += 1
                end
            end
            return true
        end
    end

    false
end

function _pdt_handle_footer_mouse!(pdt::PagedDataTable, evt::MouseEvent)::Bool
    evt.button == mouse_left && evt.action == mouse_press || return false

    # Prev page button
    if pdt.last_prev_rect.width > 0
        if Base.contains(pdt.last_prev_rect, evt.x, evt.y)
            if pdt.page > 1
                pdt.page -= 1
                pdt_refresh!(pdt)
            end
            return true
        end
    end

    # Next page button
    if pdt.last_next_rect.width > 0
        if Base.contains(pdt.last_next_rect, evt.x, evt.y)
            if pdt.page < _pdt_max_page(pdt)
                pdt.page += 1
                pdt_refresh!(pdt)
            end
            return true
        end
    end

    # Page size labels
    for (rect, ps) in pdt.last_page_size_rects
        if Base.contains(rect, evt.x, evt.y)
            if ps != pdt.page_size
                pdt_set_page_size!(pdt, ps)
            end
            return true
        end
    end

    false
end

function _pdt_find_border(pdt::PagedDataTable, x::Int)
    for (bx, col_idx) in pdt.last_col_positions
        if abs(x - bx) <= 1
            return col_idx
        end
    end
    return 0
end

function _pdt_col_at_x(pdt::PagedDataTable, x::Int)
    # Use cached column positions to determine which column the x coordinate falls in
    isempty(pdt.last_col_positions) && return 0
    prev_x = pdt.last_content_area.x + 1  # data starts after marker column
    for (bx, col_idx) in pdt.last_col_positions
        if x >= prev_x && x < bx
            return col_idx
        end
        prev_x = bx + 1
    end
    # Past last border → last column
    if !isempty(pdt.last_col_positions)
        return pdt.last_col_positions[end][2]
    end
    return 0
end

# ── Column sizing (reuses DataTable pattern) ──────────────────────────

function _pdt_visible_cols(pdt::PagedDataTable, total_width::Int)
    nc = length(pdt.columns)
    nc == 0 && return 0
    x = 0
    count = 0
    for i in (pdt.col_offset + 1):nc
        w = i <= length(pdt.col_widths) && pdt.col_widths[i] > 0 ? pdt.col_widths[i] : 8
        x + w + 1 > total_width && break
        x += w + 1
        count += 1
    end
    count
end

function _pdt_compute_widths(pdt::PagedDataTable, total_width::Int)
    nc = length(pdt.columns)
    nc == 0 && return Int[]
    n = _pdt_nrows(pdt)
    sample_n = min(n, 50)

    if length(pdt.col_widths) < nc
        old_len = length(pdt.col_widths)
        resize!(pdt.col_widths, nc)
        pdt.col_widths[old_len+1:nc] .= 0
    end

    widths = zeros(Int, nc)
    for (i, col) in enumerate(pdt.columns)
        if pdt.col_widths[i] > 0
            widths[i] = pdt.col_widths[i]
        elseif col.width > 0
            widths[i] = col.width + 1
        else
            w = length(col.name) + 2  # +2 for sort/filter indicators
            for ri in 1:sample_n
                ri <= length(pdt.rows) || break
                w = max(w, length(_pdt_format_cell(col, pdt.rows[ri], i)) + 1)
            end
            widths[i] = w
        end
    end

    total = sum(widths) + nc
    hscroll_active = pdt.col_offset > 0 || total > total_width

    if !hscroll_active
        if total > total_width && total > 0
            ratio = total_width / total
            for i in 1:nc
                widths[i] = max(2, round(Int, widths[i] * ratio))
            end
        end
        used = sum(widths) + nc
        remaining = total_width - used
        if remaining > 0 && pdt.col_widths[nc] == 0
            widths[end] += remaining
        end
    end

    widths
end
