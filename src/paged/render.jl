# ── Render helpers ────────────────────────────────────────────────────

function _pdt_render_header!(pdt::PagedDataTable, buf::Buffer,
                             hy::Int, data_x::Int, max_x::Int,
                             widths::Vector{Int}, first_col::Int, nc::Int)
    hx = data_x
    pdt.last_col_positions = Tuple{Int,Int}[]
    for i in first_col:nc
        hx > max_x && break
        w = widths[i]
        col = pdt.columns[i]
        hdr = col.name

        # Sort indicator
        indicator = if pdt.sort_col == i && pdt.sort_dir == sort_asc
            "▲"
        elseif pdt.sort_col == i && pdt.sort_dir == sort_desc
            "▼"
        else
            ""
        end

        # Filter indicator
        filter_ind = haskey(pdt.filters, i) && !isempty(pdt.filters[i].value) ? "⊘" : ""

        combined = string(hdr, indicator, filter_ind)
        text_str = length(combined) <= w ? combined : combined[1:min(end, w)]

        hdr_style = if pdt.col_hover_border > 0 && i == pdt.col_hover_border
            Style(fg=pdt.header_style.fg, bold=true, underline=true)
        else
            pdt.header_style
        end
        set_string!(buf, hx, hy, text_str, hdr_style; max_x=min(hx + w - 1, max_x))
        hx += w

        if i < nc
            if hx <= max_x
                set_char!(buf, hx, hy, '│', tstyle(:border))
                push!(pdt.last_col_positions, (hx, i))
            end
            hx += 1
        else
            if hx <= max_x
                set_char!(buf, hx, hy, '│', tstyle(:border, dim=true))
                push!(pdt.last_col_positions, (hx, i))
            end
        end
    end
end

function _pdt_render_separator!(buf::Buffer, sep_y::Int,
                                data_x::Int, data_w::Int, max_x::Int,
                                widths::Vector{Int}, first_col::Int, nc::Int,
                                has_left_overflow::Bool, has_right_overflow::Bool)
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
            if sx <= max_x
                set_char!(buf, sx, sep_y, '┤', tstyle(:border, dim=true))
            end
        end
    end

    if has_left_overflow
        set_char!(buf, data_x, sep_y, '◀', tstyle(:accent))
    end
    if has_right_overflow
        set_char!(buf, min(max_x, data_x + data_w - 1), sep_y, '▶', tstyle(:accent))
    end
end

function _pdt_render_data!(pdt::PagedDataTable, buf::Buffer,
                           cur_y::Int, footer_y::Int, vis_h::Int, n::Int,
                           content_area::Rect, data_x::Int, max_x::Int,
                           widths::Vector{Int}, first_col::Int, nc::Int)
    for vi in 1:vis_h
        row_idx = pdt.row_offset + vi
        row_idx > n && break
        ry = cur_y + vi - 1
        ry >= footer_y && break

        row_data = pdt.rows[row_idx]
        is_selected = pdt.selected > 0 && row_idx == pdt.selected
        row_style = if is_selected
            pdt.selected_style
        elseif row_idx % 2 == 0
            pdt.alt_style
        else
            pdt.style
        end

        # Animated selection highlight
        if is_selected && pdt.tick !== nothing && animations_enabled() && !(row_style.fg isa NoColor)
            base_fg = to_rgb(row_style.fg)
            p = pulse(pdt.tick; period=80, lo=0.0, hi=0.2)
            anim_fg = brighten(base_fg, p * 0.3)
            row_style = Style(fg=anim_fg, bold=row_style.bold)
        end

        if is_selected
            set_char!(buf, content_area.x, ry, MARKER, row_style)
        end

        rx = data_x
        for i in first_col:nc
            rx > max_x && break
            col = pdt.columns[i]
            w = widths[i]
            cell_text = _pdt_format_cell(col, row_data, i)
            avail = min(w, max_x - rx + 1)
            if length(cell_text) > avail
                cell_text = avail > 1 ? cell_text[1:max(1, avail-1)] * "…" : string(cell_text[1])
            end

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
                if rx <= max_x
                    set_char!(buf, rx, ry, '│', tstyle(:border, dim=true))
                end
            end
        end
    end

    # Scrollbar
    if n > vis_h
        sb_rect = Rect(right(content_area), cur_y, 1, vis_h)
        sb = Scrollbar(n, vis_h, pdt.row_offset)
        render(sb, sb_rect, buf)
    end
end

# ── Render ────────────────────────────────────────────────────────────

function render(pdt::PagedDataTable, rect::Rect, buf::Buffer)
    content_area = if pdt.block !== nothing
        render(pdt.block, rect, buf)
    else
        rect
    end
    (content_area.width < 4 || content_area.height < 5) && return

    pdt.last_content_area = content_area

    nc = length(pdt.columns)
    nc == 0 && return
    n = _pdt_nrows(pdt)

    # Vertical layout: [search] [header] [separator] [filter] [data rows] [footer]
    cur_y = content_area.y

    # ── Search bar ──
    if pdt.search_visible
        search_rect = Rect(content_area.x, cur_y, content_area.width, 1)
        render(pdt.search_input, search_rect, buf)
        cur_y += 1
    end

    # ── Go-to-page bar ──
    if pdt.goto_visible
        # Show max page hint in the label
        mp = _pdt_max_page(pdt)
        pdt.goto_input.label = "Go to page (1-$mp): "
        goto_rect = Rect(content_area.x, cur_y, content_area.width, 1)
        render(pdt.goto_input, goto_rect, buf)
        cur_y += 1
    end

    # Column widths
    sb_w = 1  # scrollbar width
    data_x = content_area.x + 1  # 1-char left margin for selection marker
    data_w = content_area.width - 1 - sb_w
    widths = _pdt_compute_widths(pdt, data_w)
    pdt.last_computed_widths = widths
    max_x = data_x + data_w - 1

    # Clamp col_offset
    pdt.col_offset = clamp(pdt.col_offset, 0, max(0, nc - 1))

    # Determine visible column range
    first_col = pdt.col_offset + 1
    last_col = nc
    used_w = 0
    for i in first_col:nc
        sep = i < nc ? 1 : 0
        if used_w + widths[i] + sep > data_w
            last_col = i
            break
        end
        used_w += widths[i] + sep
        last_col = i
    end

    has_left_overflow = pdt.col_offset > 0
    has_right_overflow = last_col < nc

    _pdt_render_header!(pdt, buf, cur_y, data_x, max_x, widths, first_col, nc)
    cur_y += 1

    _pdt_render_separator!(buf, cur_y, data_x, data_w, max_x, widths,
                           first_col, nc, has_left_overflow, has_right_overflow)
    cur_y += 1

    # (filter modal renders as overlay later)

    # ── Footer area (reserve 1 row) ──
    footer_y = bottom(content_area)
    vis_h = footer_y - cur_y  # rows available for data
    vis_h < 1 && return

    # ── Auto-scroll to keep selection visible ──
    if pdt.selected > 0
        if pdt.selected - 1 < pdt.row_offset
            pdt.row_offset = pdt.selected - 1
        elseif pdt.selected > pdt.row_offset + vis_h
            pdt.row_offset = pdt.selected - vis_h
        end
    end
    pdt.row_offset = clamp(pdt.row_offset, 0, max(0, n - vis_h))

    _pdt_render_data!(pdt, buf, cur_y, footer_y, vis_h, n,
                      content_area, data_x, max_x, widths, first_col, nc)

    # ── Footer ──
    _pdt_render_footer!(pdt, Rect(content_area.x, footer_y, content_area.width, 1), buf)

    # ── Detail view overlay ──
    if pdt.show_detail
        _pdt_render_detail!(pdt, content_area, buf)
    end

    # ── Filter modal overlay ──
    if pdt.filter_modal.visible
        _pdt_render_filter_modal!(pdt, content_area, buf)
    end

    # ── Loading overlay ──
    if pdt.loading
        spinner_chars = SPINNER_BRAILLE
        si = pdt.tick !== nothing ? mod1(pdt.tick ÷ 3, length(spinner_chars)) : 1
        load_text = string(" ", spinner_chars[si], " Loading… ")
        lx = content_area.x + max(0, (content_area.width - length(load_text)) ÷ 2)
        ly = content_area.y + max(0, (content_area.height - 1) ÷ 2)
        set_string!(buf, lx, ly, load_text, tstyle(:accent, bold=true);
                    max_x=right(content_area))
    end

    # ── Error overlay ──
    if !isempty(pdt.error_msg)
        err_text = "Error: " * pdt.error_msg
        if length(err_text) > content_area.width - 2
            err_text = err_text[1:content_area.width - 3] * "…"
        end
        err_y = content_area.y + max(0, (content_area.height - 2) ÷ 2)
        # Background bars for visibility
        for ry in err_y:min(err_y + 1, bottom(content_area))
            for rx in content_area.x:right(content_area)
                set_char!(buf, rx, ry, ' ', tstyle(:error))
            end
        end
        err_x = content_area.x + max(0, (content_area.width - length(err_text)) ÷ 2)
        set_string!(buf, err_x, err_y, err_text,
                    tstyle(:error, bold=true); max_x=right(content_area))
        # Retry hint
        retry_text = "Press [r] to retry"
        retry_x = content_area.x + max(0, (content_area.width - length(retry_text)) ÷ 2)
        retry_y = err_y + 1
        if retry_y <= bottom(content_area)
            set_string!(buf, retry_x, retry_y, retry_text,
                        tstyle(:error); max_x=right(content_area))
        end
    end
end

# ── Footer ────────────────────────────────────────────────────────────

function _pdt_render_footer!(pdt::PagedDataTable, rect::Rect, buf::Buffer)
    pdt.last_footer_area = rect
    pdt.last_page_size_rects = Tuple{Rect,Int}[]

    x = rect.x
    y = rect.y
    max_x = right(rect)
    fs = pdt.footer_style

    max_page = _pdt_max_page(pdt)

    # [◀] button
    prev_text = "[◀]"
    prev_style = pdt.page > 1 ? tstyle(:accent) : tstyle(:text_dim)
    set_string!(buf, x, y, prev_text, prev_style; max_x)
    pdt.last_prev_rect = Rect(x, y, length(prev_text), 1)
    x += length(prev_text) + 1

    # Page N/M
    page_text = "Page $(pdt.page)/$(max_page)"
    set_string!(buf, x, y, page_text, fs; max_x)
    x += length(page_text) + 1

    # [▶] button
    next_text = "[▶]"
    next_style = pdt.page < max_page ? tstyle(:accent) : tstyle(:text_dim)
    set_string!(buf, x, y, next_text, next_style; max_x)
    pdt.last_next_rect = Rect(x, y, length(next_text), 1)
    x += length(next_text) + 2

    # Row range
    if pdt.loading
        range_text = "loading…"
        set_string!(buf, x, y, range_text, tstyle(:text_dim); max_x)
    else
        first_row = (pdt.page - 1) * pdt.page_size + 1
        last_row = min(pdt.page * pdt.page_size, pdt.total_count)
        range_text = "$(first_row)-$(last_row) of $(pdt.total_count)"
        set_string!(buf, x, y, range_text, fs; max_x)
    end
    x += length(range_text) + 2

    # Page size labels
    sep_text = "│ per page:"
    set_string!(buf, x, y, sep_text, tstyle(:text_dim); max_x)
    x += length(sep_text) + 1

    for ps in pdt.page_sizes
        x > max_x && break
        ps_text = string(ps)
        ps_style = ps == pdt.page_size ? tstyle(:accent, bold=true) : fs
        if ps == pdt.page_size
            ps_text = "[$(ps_text)]"
        end
        set_string!(buf, x, y, ps_text, ps_style; max_x)
        push!(pdt.last_page_size_rects, (Rect(x, y, length(ps_text), 1), ps))
        x += length(ps_text) + 1
    end
end

# ── Detail view ───────────────────────────────────────────────────────

function _pdt_word_wrap(text::String, width::Int)::Vector{String}
    width < 1 && return [text]
    lines = String[]
    for raw_line in split(text, '\n')
        words = split(raw_line, ' ')
        current = ""
        for word in words
            if isempty(current)
                current = word
            elseif length(current) + 1 + length(word) <= width
                current = current * " " * word
            else
                push!(lines, current)
                current = word
            end
        end
        push!(lines, current)
    end
    isempty(lines) ? [""] : lines
end

function _pdt_render_detail!(pdt::PagedDataTable, content_area::Rect, buf::Buffer)
    row_idx = pdt.detail_row
    (row_idx < 1 || row_idx > length(pdt.rows)) && return

    row_data = pdt.rows[row_idx]
    fields = _pdt_detail_fn(pdt)(pdt.columns, row_data)
    nf = length(fields)
    nf == 0 && return

    modal_w = min(content_area.width - 4, max(70, content_area.width * 3 ÷ 4))
    label_w = min(16, maximum(length(first(p)) for p in fields) + 1)
    val_w = modal_w - label_w - 4  # -4 for borders + padding

    # Pre-wrap all values to compute total line count
    wrapped = [_pdt_word_wrap(string(last(p)), val_w) for p in fields]
    total_lines = sum(length(w) for w in wrapped)

    max_h = content_area.height - 4
    modal_h = min(max_h, total_lines + 4)  # +4 for top border, sep, help, bottom border
    modal_h < 5 && return

    modal_pos = center(content_area, modal_w, modal_h)
    mx, my = modal_pos.x, modal_pos.y
    inner_w = modal_w - 2
    max_row = my + modal_h - 1

    border_style = tstyle(:accent)
    title_style  = tstyle(:title, bold=true)
    label_style  = tstyle(:text_dim)
    value_style  = tstyle(:text)
    bg_col       = ColorRGB(0x12, 0x14, 0x1e)
    bg_style     = Style(bg=bg_col)

    # Flood fill background
    blank = repeat(' ', modal_w)
    for ry in my:max_row
        set_string!(buf, mx, ry, blank, bg_style)
    end

    # Top border  ┌─ Record Detail ─┐
    set_char!(buf, mx, my, '┌', border_style)
    title_str = " Record Detail "
    title_pad = inner_w - length(title_str)
    left_pad  = title_pad ÷ 2
    right_pad = title_pad - left_pad
    set_string!(buf, mx + 1, my,
        repeat('─', left_pad) * title_str * repeat('─', right_pad),
        border_style; max_x = mx + modal_w - 2)
    set_char!(buf, mx + modal_w - 1, my, '┐', border_style)

    # Separator  ├──────┤
    sep_y = my + 1
    set_char!(buf, mx, sep_y, '├', border_style)
    for rx in mx+1:mx+modal_w-2
        set_char!(buf, rx, sep_y, '─', border_style)
    end
    set_char!(buf, mx + modal_w - 1, sep_y, '┤', border_style)

    # Scrollable field rows
    vis_rows = modal_h - 4  # rows between separator and bottom border
    # Build flat list of (label_or_"", line_text) for scrolling
    flat_lines = Tuple{String,String}[]
    for (fi, (label, _)) in enumerate(fields)
        for (li, wline) in enumerate(wrapped[fi])
            push!(flat_lines, (li == 1 ? label : "", wline))
        end
    end
    total_flat = length(flat_lines)
    pdt.detail_scroll = clamp(pdt.detail_scroll, 0, max(0, total_flat - vis_rows))

    for ri in 1:vis_rows
        fy = sep_y + ri
        fy >= max_row && break
        set_char!(buf, mx, fy, '│', border_style)
        set_char!(buf, mx + modal_w - 1, fy, '│', border_style)
        flat_idx = pdt.detail_scroll + ri
        flat_idx > total_flat && continue
        lbl, val = flat_lines[flat_idx]
        if !isempty(lbl)
            lbl_text = rpad(lbl * ":", label_w)
            set_string!(buf, mx + 2, fy, lbl_text, label_style;
                        max_x = mx + 1 + label_w)
        end
        set_string!(buf, mx + 2 + label_w, fy, val, value_style;
                    max_x = mx + modal_w - 2)
    end

    # Bottom border  └──── [↑↓]scroll [Esc]close ────┘
    bot_y = max_row
    set_char!(buf, mx, bot_y, '└', border_style)
    help_str = " [↑↓] scroll  [Esc] close "
    hpad = inner_w - length(help_str)
    lh = hpad ÷ 2; rh = hpad - lh
    set_string!(buf, mx + 1, bot_y,
        repeat('─', lh) * help_str * repeat('─', rh),
        border_style; max_x = mx + modal_w - 2)
    set_char!(buf, mx + modal_w - 1, bot_y, '┘', border_style)
end

# ── Filter modal ─────────────────────────────────────────────────────

function _pdt_render_filter_modal!(pdt::PagedDataTable, content_area::Rect, buf::Buffer)
    fm = pdt.filter_modal
    nc = length(pdt.columns)
    filterable_cols = [i for i in 1:nc if pdt.columns[i].filterable]
    nf = length(filterable_cols)
    nf == 0 && return

    nops = length(fm.available_ops)

    # Modal size: columns + separator + ops row + separator + value row + separator + help
    modal_h = min(content_area.height - 2, nf + nops + 8)
    modal_w = min(50, content_area.width - 4)
    modal_h < 8 && return

    modal_rect = center(content_area, modal_w, modal_h)
    mx, my = modal_rect.x, modal_rect.y

    border_style = tstyle(:accent)
    title_style = tstyle(:title, bold=true)
    bg_style = tstyle(:text)
    section_style = tstyle(:primary, bold=true)
    selected_style = tstyle(:accent, bold=true)
    dim_style = tstyle(:text_dim)
    active_marker_style = tstyle(:accent)
    badge_style = tstyle(:accent)

    # Dim background
    for ry in content_area.y:bottom(content_area)
        for rx in content_area.x:right(content_area)
            set_char!(buf, rx, ry, ' ', dim_style)
        end
    end

    # Border with shimmer
    if pdt.tick !== nothing && pdt.tick > 0 && animations_enabled()
        border_shimmer!(buf, modal_rect, border_style.fg, pdt.tick;
                        box=BOX_HEAVY, intensity=0.12)
    else
        block = Block(border_style=border_style, box=BOX_HEAVY)
        render(block, modal_rect, buf)
    end

    # Clear interior
    for ry in my+1:my+modal_h-2
        for rx in mx+1:mx+modal_w-2
            set_char!(buf, rx, ry, ' ', bg_style)
        end
    end

    # Title
    title = " Filter "
    set_string!(buf, mx + (modal_w - length(title)) ÷ 2, my, title, title_style)

    cx = mx + 3
    max_cx = mx + modal_w - 2
    cy = my + 1

    # ── Section 1: Column list ──
    col_header = fm.section == 1 ? "▸ Column" : "  Column"
    col_header_style = fm.section == 1 ? section_style : dim_style
    set_string!(buf, cx, cy, col_header, col_header_style; max_x=max_cx)
    cy += 1

    for ci in filterable_cols
        cy > my + modal_h - 6 && break
        col = pdt.columns[ci]
        is_sel = ci == fm.col_cursor
        marker = is_sel ? "●" : "○"
        marker_style = is_sel ? active_marker_style : dim_style
        label_style = if fm.section == 1 && is_sel
            selected_style
        elseif is_sel
            tstyle(:text)
        else
            dim_style
        end

        set_string!(buf, cx + 2, cy, marker, marker_style; max_x=max_cx)
        set_string!(buf, cx + 4, cy, col.name, label_style; max_x=max_cx)

        # Show active filter badge
        existing = get(pdt.filters, ci, nothing)
        if existing !== nothing && !isempty(existing.value)
            badge = " ⊘ $(filter_op_label(existing.op)) \"$(existing.value)\""
            bx = cx + 4 + length(col.name)
            if bx + length(badge) <= max_cx
                set_string!(buf, bx, cy, badge, badge_style; max_x=max_cx)
            end
        end
        cy += 1
    end

    # Separator
    cy = min(cy, my + modal_h - 5)
    set_char!(buf, mx, cy, '┃', border_style)
    for rx in mx+1:mx+modal_w-2
        set_char!(buf, rx, cy, '─', border_style)
    end
    set_char!(buf, mx + modal_w - 1, cy, '┃', border_style)
    cy += 1

    # ── Section 2: Operator ──
    op_header = fm.section == 2 ? "▸ Operator" : "  Operator"
    op_header_style = fm.section == 2 ? section_style : dim_style
    if cy <= my + modal_h - 4
        set_string!(buf, cx, cy, op_header, op_header_style; max_x=max_cx)
        cy += 1
    end

    if nops > 0 && cy <= my + modal_h - 3
        ox = cx + 2
        for (oi, op) in enumerate(fm.available_ops)
            is_sel = oi == fm.op_cursor
            marker = is_sel ? "●" : "○"
            label = filter_op_label(op)
            entry = "$marker $label"
            entry_style = if fm.section == 2 && is_sel
                selected_style
            elseif is_sel
                tstyle(:text)
            else
                dim_style
            end
            if ox + length(entry) + 1 > max_cx
                # Wrap to next line
                cy += 1
                ox = cx + 2
                cy > my + modal_h - 3 && break
            end
            set_string!(buf, ox, cy, entry, entry_style; max_x=max_cx)
            ox += length(entry) + 2
        end
        cy += 1
    end

    # Separator
    cy = min(cy, my + modal_h - 3)
    set_char!(buf, mx, cy, '┃', border_style)
    for rx in mx+1:mx+modal_w-2
        set_char!(buf, rx, cy, '─', border_style)
    end
    set_char!(buf, mx + modal_w - 1, cy, '┃', border_style)
    cy += 1

    # ── Section 3: Value input ──
    if cy <= my + modal_h - 2
        val_header = fm.section == 3 ? "▸ " : "  "
        val_header_style = fm.section == 3 ? section_style : dim_style
        set_string!(buf, cx, cy, val_header, val_header_style; max_x=max_cx)
        input_rect = Rect(cx + 2, cy, modal_w - 6, 1)
        render(fm.value_input, input_rect, buf)
        cy += 1
    end

    # Help row
    help_y = my + modal_h - 1
    help = " [↑↓]select [Tab]next [x]clear [Enter]apply [Esc]cancel "
    set_string!(buf, mx + max(0, (modal_w - length(help)) ÷ 2), help_y, help, dim_style)
end
