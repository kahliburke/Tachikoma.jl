# ═══════════════════════════════════════════════════════════════════════
# DataTable Demo ── sortable, scrollable data table with mock data
#
# Cyberpunk-themed roster. [↑↓/PgUp/PgDn/Home/End] navigate,
# [1-4] sort by column, [m] toggle wide mode, [q/Esc] quits.
# ═══════════════════════════════════════════════════════════════════════

const DT_NAMES = [
    "Motoko Kusanagi", "Batou", "Togusa", "Ishikawa", "Saito",
    "Borma", "Pazu", "Proto", "Tachikoma #1", "Tachikoma #2",
    "Laughing Man", "Puppet Master", "Kuze", "Gouda", "Aramaki",
    "Yano", "Azuma", "Section 4 Op", "Operator", "Logicoma",
    "Hideo Kuze", "Fem", "Paz", "Chief Daisuke", "Major Kira",
]

const DT_STATUSES = ["online", "idle", "offline"]
const DT_ROLES = ["Major", "Operator", "Analyst", "Sniper", "Engineer",
                   "Medic", "Hacker", "Scout"]
const DT_REGIONS = ["Tokyo-3", "Neo Hong Kong", "Newport", "Shanghai-2",
                     "Osaka-7", "Singapore-4", "Seoul-9", "Nagasaki-5"]

function _build_datatable()
    n = length(DT_NAMES)
    names   = DT_NAMES
    status  = [DT_STATUSES[mod1(i, length(DT_STATUSES))] for i in 1:n]
    scores  = [rand(50:999) for _ in 1:n]
    latency = [round(rand() * 200.0; digits=1) for _ in 1:n]

    DataTable([
        DataColumn("Name",    collect(Any, names)),
        DataColumn("Status",  collect(Any, status)),
        DataColumn("Score",   collect(Any, scores);  align=col_right),
        DataColumn("Latency", collect(Any, latency); align=col_right,
                   format=v -> string(v, " ms")),
    ];
        selected=1,
        show_scrollbar=true,
    )
end

function _build_wide_datatable()
    n = length(DT_NAMES)
    names   = DT_NAMES
    roles   = [DT_ROLES[mod1(i, length(DT_ROLES))] for i in 1:n]
    status  = [DT_STATUSES[mod1(i, length(DT_STATUSES))] for i in 1:n]
    scores  = [rand(50:999) for _ in 1:n]
    latency = [round(rand() * 200.0; digits=1) for _ in 1:n]
    uptime  = [rand(1:9999) for _ in 1:n]
    memory  = [rand(64:4096) for _ in 1:n]
    regions = [DT_REGIONS[mod1(i, length(DT_REGIONS))] for i in 1:n]

    DataTable([
        DataColumn("Name",    collect(Any, names)),
        DataColumn("Role",    collect(Any, roles)),
        DataColumn("Status",  collect(Any, status)),
        DataColumn("Score",   collect(Any, scores);  align=col_right),
        DataColumn("Latency", collect(Any, latency); align=col_right,
                   format=v -> string(v, " ms")),
        DataColumn("Uptime",  collect(Any, uptime);  align=col_right,
                   format=v -> string(v, " hrs")),
        DataColumn("Memory",  collect(Any, memory);  align=col_right,
                   format=v -> string(v, " MB")),
        DataColumn("Region",  collect(Any, regions)),
    ];
        selected=1,
        show_scrollbar=true,
        detail_fn=datatable_detail,
    )
end

@kwdef mutable struct DataTableModel <: Model
    quit::Bool = false
    tick::Int = 0
    mode::Int = 1               # 1 = compact (4 cols), 2 = wide (8 cols)
    dt::DataTable = _build_datatable()
    dt_wide::DataTable = _build_wide_datatable()
end

should_quit(m::DataTableModel) = m.quit

function _active_dt(m::DataTableModel)
    m.mode == 1 ? m.dt : m.dt_wide
end

function update!(m::DataTableModel, evt::KeyEvent)
    dt = _active_dt(m)

    # When detail view is open, delegate everything to DataTable
    if dt.show_detail
        handle_key!(dt, evt)
        return
    end

    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _)    => (m.quit = true)
        (:char, 'm')                     => (m.mode = m.mode == 1 ? 2 : 1)
        (:char, c) where '1' <= c <= '9' => begin
            col_num = Int(c) - Int('0')
            col_num <= length(dt.columns) && sort_by!(dt, col_num)
        end
        _                                => handle_key!(dt, evt)
    end
end

function update!(m::DataTableModel, evt::MouseEvent)
    handle_mouse!(_active_dt(m), evt)
end

function view(m::DataTableModel, f::Frame)
    m.tick += 1
    dt = _active_dt(m)
    dt.tick = m.tick
    buf = f.buffer

    # Layout: title | table | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    table_area  = rows[2]
    footer_area = rows[3]

    # ── Header ──
    title = m.mode == 1 ? "DataTable Demo" : "DataTable Demo (Wide)"
    hx = header_area.x + max(0, (header_area.width - length(title)) ÷ 2)
    set_string!(buf, hx, header_area.y, title, tstyle(:title, bold=true))

    # ── Table ──
    sort_info = if dt.sort_col > 0 && dt.sort_dir != sort_none
        col_name = dt.columns[dt.sort_col].name
        dir_str = dt.sort_dir == sort_asc ? "▲" : "▼"
        " sorted: $(col_name) $(dir_str) "
    else
        " unsorted "
    end

    dt.block = Block(title="Roster$(sort_info)",
                     border_style=tstyle(:border),
                     title_style=tstyle(:title))
    render(dt, table_area, buf)

    # ── Footer ──
    footer = if m.mode == 1
        StatusBar(
            left=[Span("  [↑↓]navigate [PgUp/PgDn]page [1-4]sort [m]wide mode ",
                        tstyle(:text_dim))],
            right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
        )
    else
        StatusBar(
            left=[Span("  [↑↓]navigate [←→]scroll [1-8]sort [d]detail [m]compact mode ",
                        tstyle(:text_dim))],
            right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
        )
    end
    render(footer, footer_area, buf)
end

function datatable_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(DataTableModel(); fps=30)
end
