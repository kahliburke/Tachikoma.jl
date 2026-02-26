# ═══════════════════════════════════════════════════════════════════════
# Table ── data table with styled header, selection, per-row styles
# ═══════════════════════════════════════════════════════════════════════

struct Table
    header::Vector{String}
    rows::Vector{Vector{String}}
    widths::Vector{Int}            # column widths
    block::Union{Block, Nothing}
    header_style::Style
    row_style::Style
    alt_row_style::Style           # alternating row color
    separator::Char
    selected::Int                  # 0 = no selection, 1-based index
    selected_style::Style
    row_styles::Vector{Style}      # per-row overrides (empty = use defaults)
end

function Table(header::Vector{String}, rows::Vector{Vector{String}};
    widths=Int[],
    block=nothing,
    header_style=tstyle(:title, bold=true),
    row_style=tstyle(:text),
    alt_row_style=tstyle(:text_dim),
    separator='│',
    selected=0,
    selected_style=tstyle(:accent, bold=true),
    row_styles=Style[],
)
    # Auto-compute column widths if not specified
    w = if isempty(widths)
        ncols = length(header)
        ws = [length(h) + 2 for h in header]
        for row in rows
            for (j, cell) in enumerate(row)
                j <= ncols && (ws[j] = max(ws[j], length(cell) + 2))
            end
        end
        ws
    else
        widths
    end
    Table(header, rows, w, block, header_style, row_style,
          alt_row_style, separator, selected, selected_style, row_styles)
end

function render(tbl::Table, rect::Rect, buf::Buffer)
    content = if tbl.block !== nothing
        render(tbl.block, rect, buf)
    else
        rect
    end
    (content.width < 1 || content.height < 1) && return

    y = content.y
    ncols = length(tbl.header)

    # When selection is active, reserve 2 chars at the left for the marker
    # so all rows (header + data) start at the same x offset.
    has_selection = tbl.selected > 0
    data_x = has_selection ? content.x + 2 : content.x

    # Render header
    if y <= bottom(content)
        render_table_row!(buf, data_x, y, tbl.header,
                          tbl.widths, tbl.header_style,
                          tbl.separator, content)
        y += 1
    end

    # Header separator line
    if y <= bottom(content)
        for col in content.x:right(content)
            set_char!(buf, col, y, '─', tstyle(:border, dim=true))
        end
        y += 1
    end

    # Render data rows
    for (i, row) in enumerate(tbl.rows)
        y > bottom(content) && break

        # Determine style: selected > per-row > alternating default
        style = if tbl.selected == i
            tbl.selected_style
        elseif !isempty(tbl.row_styles) && i <= length(tbl.row_styles)
            tbl.row_styles[i]
        else
            isodd(i) ? tbl.row_style : tbl.alt_row_style
        end

        # Draw selection marker (or space) — all rows use data_x for content
        if tbl.selected == i
            set_char!(buf, content.x, y, MARKER, tbl.selected_style)
        end
        render_table_row!(buf, data_x, y, row,
                          tbl.widths, style,
                          tbl.separator, content)
        y += 1
    end
end

function render_table_row!(buf::Buffer, x0::Int, y::Int,
                           cells::Vector{String},
                           widths::Vector{Int}, style::Style,
                           sep::Char, content::Rect)
    cx = x0
    for (j, cell) in enumerate(cells)
        j > length(widths) && break
        w = widths[j]
        # Truncate cell text to fit
        txt = length(cell) > w - 1 ? cell[1:w-2] * "…" : cell
        set_string!(buf, cx, y, txt, style)
        cx += w
        # Column separator
        if j < length(cells) && cx <= right(content)
            set_char!(buf, cx, y, sep, tstyle(:border, dim=true))
            cx += 1
        end
    end
end
