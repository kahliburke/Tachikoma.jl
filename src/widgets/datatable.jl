# ═══════════════════════════════════════════════════════════════════════
# DataTable ── scrollable typed data table with sorting
# ═══════════════════════════════════════════════════════════════════════

@enum ColumnAlign col_left col_right col_center
@enum SortDir sort_none sort_asc sort_desc

struct DataColumn
    name::String
    values::Vector{Any}
    width::Int                     # 0 = auto
    align::ColumnAlign
    format::Union{Function, Nothing}  # value -> String
end

"""
    DataColumn(name, values; width=0, align=col_left, format=nothing)

A column in a `DataTable`. Set `width=0` for auto-sizing, `format` for custom display.
"""
function DataColumn(name::String, values::Vector;
    width::Int=0,
    align::ColumnAlign=col_left,
    format=nothing,
)
    DataColumn(name, collect(Any, values), width, align, format)
end

mutable struct DataTable
    columns::Vector{DataColumn}
    selected::Int                  # 0 = no selection, 1-based row
    offset::Int                    # scroll offset (0-based)
    block::Union{Block, Nothing}
    show_scrollbar::Bool
    sort_col::Int                  # 0 = unsorted
    sort_dir::SortDir
    sort_perm::Vector{Int}         # permutation of row indices
    style::Style
    header_style::Style
    selected_style::Style
    alt_style::Style
    tick::Union{Int, Nothing}
    # Column resize
    col_widths::Vector{Int}        # user-overridden widths (0 = auto); populated on first render
    col_drag::Int                  # 0 = idle, >0 = index of column border being dragged
    col_drag_start_x::Int          # mouse x at drag start
    col_drag_start_w::Int          # column width at drag start
    col_hover_border::Int          # 0 = no hover, >0 = hovered border index (visual feedback)
    # Horizontal scroll
    col_offset::Int                # first visible column index (0-based, 0 = show from col 1)
    # Detail view
    detail_fn::Union{Function, Nothing}  # (columns, row_idx) -> Vector{Pair{String,String}}
    detail_key::Symbol             # key to open detail view (default :char with 'd')
    detail_char::Char              # the char to match (default 'd')
    show_detail::Bool              # whether detail popup is visible
    detail_row::Int                # which row is being detailed
    detail_scroll::Int             # scroll offset within detail view
    # Cached render state for mouse hit testing
    last_content_area::Rect        # cached from last render
    last_col_positions::Vector{Tuple{Int,Int}} # (x-position, column index) of each border after last render
    last_widths::Vector{Int}       # rendered widths from last frame (for drag start)
end

function DataTable(columns::Vector{DataColumn};
    selected::Int=0,
    block::Union{Block, Nothing}=nothing,
    show_scrollbar::Bool=true,
    style::Style=tstyle(:text),
    header_style::Style=tstyle(:title, bold=true),
    selected_style::Style=tstyle(:accent, bold=true),
    alt_style::Style=tstyle(:text, dim=true),
    tick::Union{Int, Nothing}=nothing,
    detail_fn::Union{Function, Nothing}=nothing,
    detail_key::Symbol=:char,
    detail_char::Char='d',
)
    n = _dt_nrows(columns)
    perm = collect(1:n)
    sel = clamp(selected, 0, n)
    DataTable(columns, sel, 0, block, show_scrollbar, 0, sort_none, perm,
              style, header_style, selected_style, alt_style, tick,
              Int[], 0, 0, 0, 0,   # col resize
              0,                     # col_offset
              detail_fn, detail_key, detail_char, false, 0, 0,  # detail view
              Rect(), Tuple{Int,Int}[], Int[])  # cached render state
end

# Convenience: headers + data vectors
function DataTable(headers::Vector{String}, data::Vector{<:AbstractVector}; kwargs...)
    cols = [DataColumn(h, collect(Any, v)) for (h, v) in zip(headers, data)]
    DataTable(cols; kwargs...)
end

_dt_nrows(cols::Vector{DataColumn}) = isempty(cols) ? 0 : maximum(length(c.values) for c in cols)

function _dt_format_cell(col::DataColumn, row::Int)
    row > length(col.values) && return ""
    v = col.values[row]
    col.format !== nothing ? col.format(v) : string(v)
end

# ── Sorting ──

function sort_by!(dt::DataTable, col_idx::Int)
    (col_idx < 1 || col_idx > length(dt.columns)) && return
    if dt.sort_col == col_idx
        # Cycle: none → asc → desc → none
        dt.sort_dir = if dt.sort_dir == sort_none
            sort_asc
        elseif dt.sort_dir == sort_asc
            sort_desc
        else
            sort_none
        end
    else
        dt.sort_col = col_idx
        dt.sort_dir = sort_asc
    end

    n = _dt_nrows(dt.columns)
    if dt.sort_dir == sort_none || dt.sort_col == 0
        dt.sort_perm = collect(1:n)
    else
        col = dt.columns[dt.sort_col]
        dt.sort_perm = sortperm(col.values[1:min(n, length(col.values))];
                                rev=(dt.sort_dir == sort_desc))
    end
end

# ── Key handling ──

value(dt::DataTable) = dt.selected
set_value!(dt::DataTable, idx::Int) = (dt.selected = clamp(idx, 0, _dt_nrows(dt.columns)); nothing)

focusable(::DataTable) = true

function handle_key!(dt::DataTable, evt::KeyEvent)::Bool
    # Detail view intercepts all keys when open
    if dt.show_detail
        return _dt_handle_detail_key!(dt, evt)
    end

    n = _dt_nrows(dt.columns)
    n == 0 && return false

    # Open detail view
    if dt.detail_fn !== nothing && evt.key == dt.detail_key && evt.char == dt.detail_char
        if dt.selected > 0
            dt.show_detail = true
            dt.detail_row = dt.selected
            dt.detail_scroll = 0
            return true
        end
    end

    if evt.key == :up
        dt.selected = dt.selected <= 1 ? n : dt.selected - 1
        return true
    elseif evt.key == :down
        dt.selected = dt.selected >= n ? 1 : dt.selected + 1
        return true
    elseif evt.key == :pageup
        dt.selected = max(1, dt.selected - 10)
        return true
    elseif evt.key == :pagedown
        dt.selected = min(n, dt.selected + 10)
        return true
    elseif evt.key == :home
        dt.selected = 1
        return true
    elseif evt.key == :end_key
        dt.selected = n
        return true
    elseif evt.key == :left
        if dt.col_offset > 0
            dt.col_offset -= 1
            return true
        end
    elseif evt.key == :right
        nc = length(dt.columns)
        # Compute data_w for visible column count (approximate with last_content_area)
        data_w = max(10, dt.last_content_area.width - 2)
        max_off = max(0, nc - _dt_visible_cols(dt, data_w))
        if dt.col_offset < max_off
            dt.col_offset += 1
            return true
        end
    end
    false
end

function _dt_handle_detail_key!(dt::DataTable, evt::KeyEvent)::Bool
    if evt.key == :escape
        dt.show_detail = false
        return true
    end
    if evt.key == dt.detail_key && evt.char == dt.detail_char
        dt.show_detail = false
        return true
    end
    if evt.key == :up
        dt.detail_scroll = max(0, dt.detail_scroll - 1)
        return true
    elseif evt.key == :down
        # Clamp proactively using column count as upper bound;
        # render will refine with actual field count.
        max_scroll = max(0, length(dt.columns) - 1)
        dt.detail_scroll = min(dt.detail_scroll + 1, max_scroll)
        return true
    end
    true  # consume all keys while detail is open
end

"""Convenience overload using cached content area from last render."""
function handle_mouse!(dt::DataTable, evt::MouseEvent)::Bool
    dt.last_content_area.width > 0 || return false
    handle_mouse!(dt, evt, dt.last_content_area)
end

function handle_mouse!(dt::DataTable, evt::MouseEvent, content_area::Rect)::Bool
    # Active column drag
    if dt.col_drag > 0
        if evt.action == mouse_drag
            delta = evt.x - dt.col_drag_start_x
            new_w = max(3, dt.col_drag_start_w + delta)
            if length(dt.col_widths) >= dt.col_drag
                dt.col_widths[dt.col_drag] = new_w
            end
            return true
        end
        if evt.action == mouse_release
            dt.col_drag = 0
            return true
        end
    end

    # Mouse move: check for hover on column borders
    if evt.action == mouse_move
        dt.col_hover_border = _dt_find_border(dt, evt.x)
        return dt.col_hover_border > 0
    end

    # Left press on column border → start drag (header or separator row)
    if evt.button == mouse_left && evt.action == mouse_press
        border_idx = _dt_find_border(dt, evt.x)
        header_y = dt.last_content_area.y
        if border_idx > 0 && (evt.y == header_y || evt.y == header_y + 1)
            dt.col_drag = border_idx
            dt.col_drag_start_x = evt.x
            dt.col_drag_start_w = length(dt.last_widths) >= border_idx ? dt.last_widths[border_idx] : 10
            return true
        end
    end

    n = _dt_nrows(dt.columns)
    vis_h = content_area.height - 2  # header + separator
    hit = list_hit(evt, Rect(content_area.x, content_area.y + 2, content_area.width, vis_h),
                   dt.offset, n)
    if hit > 0
        dt.selected = hit
        return true
    end
    new_off = list_scroll(evt, dt.offset, n, vis_h)
    if new_off != dt.offset
        dt.offset = new_off
        return true
    end
    false
end

"""Find column index whose right border is near x (±1 cell tolerance). Returns 0 if none."""
function _dt_find_border(dt::DataTable, x::Int)
    for (bx, col_idx) in dt.last_col_positions
        if abs(x - bx) <= 1
            return col_idx
        end
    end
    return 0
end

# ── Column sizing ──

"""Count how many columns are fully visible starting from col_offset, using last rendered widths."""
function _dt_visible_cols(dt::DataTable, total_width::Int)
    nc = length(dt.columns)
    nc == 0 && return 0
    nw = length(dt.last_widths)
    x = 0
    count = 0
    for i in (dt.col_offset + 1):nc
        w = i <= nw ? dt.last_widths[i] : 8  # fallback before first render
        sep = 1  # between-column or trailing border
        x + w + sep > total_width && break
        x += w + sep
        count += 1
    end
    count
end

function _dt_compute_widths(dt::DataTable, total_width::Int)
    nc = length(dt.columns)
    nc == 0 && return Int[]
    n = _dt_nrows(dt.columns)
    sample_n = min(n, 50)

    # Ensure col_widths vector exists (all zeros = all auto)
    if length(dt.col_widths) < nc
        old_len = length(dt.col_widths)
        resize!(dt.col_widths, nc)
        dt.col_widths[old_len+1:nc] .= 0
    end

    widths = zeros(Int, nc)
    for (i, col) in enumerate(dt.columns)
        # Non-zero col_widths = user-dragged override (already includes padding)
        if dt.col_widths[i] > 0
            widths[i] = dt.col_widths[i]
        elseif col.width > 0
            widths[i] = col.width + 1  # +1 for sort indicator padding
        else
            w = length(col.name)
            for row in 1:sample_n
                w = max(w, length(_dt_format_cell(col, row)))
            end
            widths[i] = w + 1  # +1 for sort indicator padding
        end
    end

    # Check if total exceeds viewport (h-scroll active)
    # nc-1 between-column separators + 1 trailing border = nc separator chars
    total = sum(widths) + nc  # columns + all separators including trailing
    hscroll_active = dt.col_offset > 0 || total > total_width

    if !hscroll_active
        # Proportionally shrink if too wide (only when not h-scrolling)
        if total > total_width && total > 0
            ratio = total_width / total
            for i in 1:nc
                widths[i] = max(2, round(Int, widths[i] * ratio))
            end
        end

        # Expand last column to fill remaining space, but only if it hasn't
        # been manually resized (col_widths[nc] == 0 means auto).
        used = sum(widths) + nc
        remaining = total_width - used
        if remaining > 0 && dt.col_widths[nc] == 0
            widths[end] += remaining
        end
    end

    widths
end

# ── Render ──

function render(dt::DataTable, rect::Rect, buf::Buffer)
    content_area = if dt.block !== nothing
        render(dt.block, rect, buf)
    else
        rect
    end
    (content_area.width < 4 || content_area.height < 3) && return

    nc = length(dt.columns)
    nc == 0 && return
    n = _dt_nrows(dt.columns)

    # Cache content area for mouse hit testing
    dt.last_content_area = content_area

    # Column widths — reserve 1 char left margin for selection marker
    sb_w = dt.show_scrollbar && n > content_area.height - 2 ? 1 : 0
    data_x = content_area.x + 1  # 1-char left margin
    data_w = content_area.width - 1 - sb_w
    widths = _dt_compute_widths(dt, data_w)
    dt.last_widths = widths

    # Clamp col_offset
    dt.col_offset = clamp(dt.col_offset, 0, max(0, nc - 1))

    # Determine visible column range (starting from col_offset)
    first_col = dt.col_offset + 1
    last_col = nc
    used_w = 0
    for i in first_col:nc
        sep = i < nc ? 1 : 0
        if used_w + widths[i] + sep > data_w
            # Partially visible — still draw it but track last fully visible
            last_col = i
            break
        end
        used_w += widths[i] + sep
        last_col = i
    end

    has_left_overflow = dt.col_offset > 0
    has_right_overflow = last_col < nc

    # Auto-scroll to keep selection visible
    vis_h = content_area.height - 2  # header + separator
    if dt.selected > 0
        if dt.selected - 1 < dt.offset
            dt.offset = dt.selected - 1
        elseif dt.selected > dt.offset + vis_h
            dt.offset = dt.selected - vis_h
        end
    end

    # ── Header ──
    hx = data_x
    hy = content_area.y
    dt.last_col_positions = Tuple{Int,Int}[]
    max_x = data_x + data_w - 1
    for i in first_col:nc
        hx > max_x && break
        w = widths[i]
        col = dt.columns[i]
        hdr = col.name
        # Sort indicator
        indicator = if dt.sort_col == i && dt.sort_dir == sort_asc
            "▲"
        elseif dt.sort_col == i && dt.sort_dir == sort_desc
            "▼"
        else
            ""
        end
        text = length(hdr) + length(indicator) <= w ?
            string(hdr, indicator) : hdr[1:min(end, w)]

        # Highlight hovered border column header
        hdr_style = if dt.col_hover_border > 0 && i == dt.col_hover_border
            Style(fg=dt.header_style.fg, bold=true, underline=true)
        else
            dt.header_style
        end
        set_string!(buf, hx, hy, text, hdr_style; max_x=min(hx + w - 1, max_x))
        hx += w
        if i < nc
            if hx <= max_x
                set_char!(buf, hx, hy, '│', tstyle(:border))
                push!(dt.last_col_positions, (hx, i))  # border to the right of column i
            end
            hx += 1
        else
            # Trailing border after last column — drag target for resizing it
            if hx <= max_x
                set_char!(buf, hx, hy, '│', tstyle(:border, dim=true))
                push!(dt.last_col_positions, (hx, i))
            end
        end
    end

    # ── Separator ──
    sep_y = content_area.y + 1
    sx = data_x
    for i in first_col:nc
        sx > max_x && break
        w = widths[i]
        for dx in 0:w-1
            sx + dx <= max_x && set_char!(buf, sx + dx, sep_y, '─', tstyle(:border))
        end
        sx += w
        if i < nc
            if sx <= max_x
                set_char!(buf, sx, sep_y, '┼', tstyle(:border))
            end
            sx += 1
        else
            # Trailing separator after last column
            if sx <= max_x
                set_char!(buf, sx, sep_y, '┤', tstyle(:border, dim=true))
            end
        end
    end

    # H-scroll indicators on separator row
    if has_left_overflow
        set_char!(buf, data_x, sep_y, '◀', tstyle(:accent))
    end
    if has_right_overflow
        set_char!(buf, min(max_x, data_x + data_w - 1), sep_y, '▶', tstyle(:accent))
    end

    # ── Data rows ──
    for vi in 1:vis_h
        row_perm_idx = dt.offset + vi
        row_perm_idx > n && break
        data_row = dt.sort_perm[min(row_perm_idx, length(dt.sort_perm))]
        ry = content_area.y + 1 + vi
        ry > bottom(content_area) && break

        is_selected = dt.selected > 0 && row_perm_idx == dt.selected
        row_style = if is_selected
            dt.selected_style
        elseif data_row % 2 == 0
            dt.alt_style
        else
            dt.style
        end

        # Animated selection highlight
        if is_selected && dt.tick !== nothing && animations_enabled() && !(row_style.fg isa NoColor)
            base_fg = to_rgb(row_style.fg)
            p = pulse(dt.tick; period=80, lo=0.0, hi=0.2)
            anim_fg = brighten(base_fg, p * 0.3)
            row_style = Style(fg=anim_fg, bold=row_style.bold)
        end

        if is_selected
            set_char!(buf, content_area.x, ry, MARKER, row_style)
        end

        rx = data_x
        for i in first_col:nc
            rx > max_x && break
            col = dt.columns[i]
            w = widths[i]
            cell_text = _dt_format_cell(col, data_row)
            avail = min(w, max_x - rx + 1)
            if length(cell_text) > avail
                cell_text = avail > 1 ? cell_text[1:max(1, avail-1)] * "…" : string(cell_text[1])
            end

            # Alignment
            padding = max(0, avail - length(cell_text))
            cell_x = if col.align == col_right
                rx + padding
            elseif col.align == col_center
                rx + padding ÷ 2
            else
                rx
            end

            set_string!(buf, cell_x, ry, cell_text, row_style;
                        max_x=min(rx + w - 1, max_x))
            rx += w
            if i < nc
                if rx <= max_x
                    set_char!(buf, rx, ry, '│', tstyle(:border))
                end
                rx += 1
            else
                # Trailing border after last column
                if rx <= max_x
                    set_char!(buf, rx, ry, '│', tstyle(:border, dim=true))
                end
            end
        end
    end

    # ── Scrollbar ──
    if sb_w > 0
        sb_rect = Rect(right(content_area), content_area.y + 2,
                        1, vis_h)
        sb = Scrollbar(n, vis_h, dt.offset)
        render(sb, sb_rect, buf)
    end

    # ── Detail view overlay ──
    if dt.show_detail && dt.detail_fn !== nothing
        _dt_render_detail!(dt, content_area, buf)
    end
end

# ── Detail view ──

"""Default detail function: shows all column values for a row."""
function datatable_detail(columns::Vector{DataColumn}, row::Int)
    [col.name => _dt_format_cell(col, row) for col in columns]
end

function _dt_render_detail!(dt::DataTable, content_area::Rect, buf::Buffer)
    # Get detail data
    data_row = dt.sort_perm[min(dt.detail_row, length(dt.sort_perm))]
    fields = dt.detail_fn(dt.columns, data_row)
    nf = length(fields)
    nf == 0 && return

    # Modal dimensions
    label_w = maximum(length(first(p)) for p in fields) + 2
    val_w = maximum(length(last(p)) for p in fields)
    inner_w = label_w + val_w + 1
    modal_w = min(content_area.width - 4, max(inner_w + 4, 30))
    modal_h = min(content_area.height - 4, nf + 4)  # title + sep + fields + sep + help
    modal_h < 4 && return

    # Center the modal
    modal_pos = center(content_area, modal_w, modal_h)
    mx, my = modal_pos.x, modal_pos.y

    border_style = tstyle(:accent)
    title_style = tstyle(:title, bold=true)
    label_style = tstyle(:text_dim)
    value_style = tstyle(:text)
    bg_style = tstyle(:text)

    # Dim background (fill modal area with background)
    for ry in my:my+modal_h-1
        for rx in mx:mx+modal_w-1
            set_char!(buf, rx, ry, ' ', bg_style)
        end
    end

    # Top border
    set_char!(buf, mx, my, '┃', border_style)
    title = " Record Detail "
    set_string!(buf, mx + 2, my, title, title_style; max_x=mx + modal_w - 2)
    for rx in mx + 2 + length(title):mx + modal_w - 2
        set_char!(buf, rx, my, ' ', bg_style)
    end
    set_char!(buf, mx + modal_w - 1, my, '┃', border_style)

    # Title separator
    sep_y = my + 1
    set_char!(buf, mx, sep_y, '┃', border_style)
    for rx in mx+1:mx+modal_w-2
        set_char!(buf, rx, sep_y, '─', border_style)
    end
    set_char!(buf, mx + modal_w - 1, sep_y, '┃', border_style)

    # Field rows
    vis_fields = modal_h - 4  # title + title_sep + bottom_sep + help
    dt.detail_scroll = clamp(dt.detail_scroll, 0, max(0, nf - vis_fields))
    for fi in 1:vis_fields
        field_idx = dt.detail_scroll + fi
        fy = my + 1 + fi
        fy > my + modal_h - 3 && break

        set_char!(buf, mx, fy, '┃', border_style)
        if field_idx <= nf
            label, val = fields[field_idx]
            label_text = rpad(label * ":", label_w)
            set_string!(buf, mx + 2, fy, label_text, label_style;
                        max_x=mx + 2 + label_w - 1)
            set_string!(buf, mx + 2 + label_w, fy, val, value_style;
                        max_x=mx + modal_w - 2)
        end
        set_char!(buf, mx + modal_w - 1, fy, '┃', border_style)
    end

    # Bottom separator
    bsep_y = my + modal_h - 2
    set_char!(buf, mx, bsep_y, '┃', border_style)
    for rx in mx+1:mx+modal_w-2
        set_char!(buf, rx, bsep_y, '─', border_style)
    end
    set_char!(buf, mx + modal_w - 1, bsep_y, '┃', border_style)

    # Help row
    help_y = my + modal_h - 1
    set_char!(buf, mx, help_y, '┃', border_style)
    help_text = " [↑↓]scroll [Esc/$(dt.detail_char)]close "
    set_string!(buf, mx + 2, help_y, help_text, label_style;
                max_x=mx + modal_w - 2)
    set_char!(buf, mx + modal_w - 1, help_y, '┃', border_style)
end
