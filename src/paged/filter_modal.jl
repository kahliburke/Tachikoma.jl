# ── Filter modal key handling ─────────────────────────────────────────

function _pdt_handle_filter_modal_key!(pdt::PagedDataTable, evt::KeyEvent)::Bool
    fm = pdt.filter_modal
    if evt.key == :escape
        fm.visible = false
        return true
    end

    # Tab cycles sections forward, Shift-Tab backward
    if evt.key == :tab
        fm.section = fm.section < 3 ? fm.section + 1 : 1
        if fm.section == 3
            fm.value_input.focused = true
        end
        return true
    end
    if evt.key == :backtab
        fm.section = fm.section > 1 ? fm.section - 1 : 3
        if fm.section == 3
            fm.value_input.focused = true
        end
        return true
    end

    if fm.section == 1
        # Column list navigation
        nc = length(pdt.columns)
        filterable_cols = [i for i in 1:nc if pdt.columns[i].filterable]
        isempty(filterable_cols) && return true

        if evt.key == :up
            idx = findfirst(==(fm.col_cursor), filterable_cols)
            if idx !== nothing && idx > 1
                fm.col_cursor = filterable_cols[idx - 1]
            end
            _pdt_sync_filter_modal_ops!(pdt)
            return true
        elseif evt.key == :down
            idx = findfirst(==(fm.col_cursor), filterable_cols)
            if idx !== nothing && idx < length(filterable_cols)
                fm.col_cursor = filterable_cols[idx + 1]
            end
            _pdt_sync_filter_modal_ops!(pdt)
            return true
        end

        # 'x' clears filter on highlighted column
        if evt.key == :char && evt.char == 'x'
            delete!(pdt.filters, fm.col_cursor)
            pdt.page = 1
            pdt_refresh!(pdt)
            return true
        end

        # Enter on column → move to operator section
        if evt.key == :enter
            fm.section = 2
            return true
        end
    elseif fm.section == 2
        # Operator selection
        nops = length(fm.available_ops)
        nops == 0 && return true

        if evt.key == :up || evt.key == :left
            fm.op_cursor = fm.op_cursor > 1 ? fm.op_cursor - 1 : nops
            return true
        elseif evt.key == :down || evt.key == :right
            fm.op_cursor = fm.op_cursor < nops ? fm.op_cursor + 1 : 1
            return true
        end

        # Enter on operator → move to value input
        if evt.key == :enter
            fm.section = 3
            fm.value_input.focused = true
            return true
        end
    else
        # Value input section
        if evt.key == :enter
            val = text(fm.value_input)
            if isempty(val)
                delete!(pdt.filters, fm.col_cursor)
            else
                op = isempty(fm.available_ops) ? filter_contains : fm.available_ops[fm.op_cursor]
                pdt.filters[fm.col_cursor] = ColumnFilter(op, val)
            end
            fm.visible = false
            pdt.page = 1
            pdt_refresh!(pdt)
            return true
        end
        handle_key!(fm.value_input, evt)
    end
    true
end

# ── Filter modal helpers ──────────────────────────────────────────────

function _pdt_open_filter_modal!(pdt::PagedDataTable)
    fm = pdt.filter_modal
    fm.visible = true
    fm.section = 1

    # Start on first filterable column
    nc = length(pdt.columns)
    fm.col_cursor = 0
    for i in 1:nc
        if pdt.columns[i].filterable
            fm.col_cursor = i
            break
        end
    end
    fm.col_cursor == 0 && return  # no filterable columns

    _pdt_sync_filter_modal_ops!(pdt)

    # Pre-fill value input if filter exists for this column
    existing = get(pdt.filters, fm.col_cursor, nothing)
    if existing !== nothing
        set_text!(fm.value_input, existing.value)
        # Pre-select the existing operator
        op_idx = findfirst(==(existing.op), fm.available_ops)
        fm.op_cursor = op_idx !== nothing ? op_idx : 1
    else
        set_text!(fm.value_input, "")
        fm.op_cursor = 1
    end
end

function _pdt_sync_filter_modal_ops!(pdt::PagedDataTable)
    fm = pdt.filter_modal
    fm.col_cursor < 1 && return
    fm.col_cursor > length(pdt.columns) && return

    col = pdt.columns[fm.col_cursor]
    caps = filter_capabilities(pdt.provider)
    fm.available_ops = col.col_type == :numeric ? caps.numeric_ops : caps.text_ops
    fm.op_cursor = clamp(fm.op_cursor, 1, max(1, length(fm.available_ops)))

    # Sync value input with existing filter
    existing = get(pdt.filters, fm.col_cursor, nothing)
    if existing !== nothing
        set_text!(fm.value_input, existing.value)
        op_idx = findfirst(==(existing.op), fm.available_ops)
        fm.op_cursor = op_idx !== nothing ? op_idx : 1
    else
        set_text!(fm.value_input, "")
        fm.op_cursor = 1
    end
end
