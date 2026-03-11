# ═══════════════════════════════════════════════════════════════════════
# PagedDataTable Demo ── Exoplanet Catalog
#
# Demonstrates paging with two switchable data sources:
# - Synthetic: 1M deterministic exoplanet rows (zero pre-allocation)
# - SQLite: 50k rows in an on-disk database (typed filter → SQL WHERE)
#
# [↑↓] navigate  [PgUp/PgDn] page  [Home/End] first/last page
# [1-9] sort      [/] search         [f] filter (typed modal)
# [«»] page size  [d] detail view    [s] settings
# [q/Esc] quit
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma.Paged
import Tachikoma.Paged: column_defs, fetch_page, supports_search, supports_filter

# ── Exoplanet data generation ────────────────────────────────────────

const EXO_CONSTELLATIONS = (
    "Cygnus", "Lyra", "Aquarius", "Pegasus", "Virgo", "Sagittarius",
    "Centaurus", "Pisces", "Draco", "Scorpius", "Orion", "Cassiopeia",
    "Leo", "Gemini", "Andromeda", "Eridanus", "Puppis", "Vela",
)

const EXO_DISCOVERY_METHODS = (
    "Transit", "Radial Velocity", "Direct Imaging", "Microlensing",
    "Transit Timing", "Astrometry", "Pulsar Timing",
)

const EXO_SPECTRAL_TYPES = (
    "G2V", "K0V", "K5V", "M0V", "M2V", "M4V", "M5V",
    "F5V", "F8V", "G0V", "G5V", "G8V", "K1III", "K2V",
    "A0V", "B8V", "G9V", "M1V", "M3V",
)

const EXO_NAME_PREFIXES = (
    "Kepler-", "TRAPPIST-", "TOI-", "HAT-P-", "WASP-", "GJ ", "HD ",
    "K2-", "CoRoT-", "XO-", "TrES-", "Qatar-", "KELT-", "EPIC ",
    "KOI-", "Proxima ", "LHS ", "Ross ", "Wolf ", "55 Cnc ",
)

"""Generate an exoplanet name from index."""
function _exo_name(i::Int)
    prefix = EXO_NAME_PREFIXES[mod1(i * 7 + 3, length(EXO_NAME_PREFIXES))]
    suffix = mod1(i * 31 + 17, 9999)
    letter = ('b' + mod(i * 13, 6))
    string(prefix, suffix, letter)
end

_exo_constellation(i) = EXO_CONSTELLATIONS[mod1(i * 11 + 5, length(EXO_CONSTELLATIONS))]
_exo_method(i)        = EXO_DISCOVERY_METHODS[mod1(i * 17 + 3, length(EXO_DISCOVERY_METHODS))]
_exo_year(i)          = 1995 + mod(i * 7 + 13, 30)  # 1995-2024
_exo_distance(i)      = round(4.2 + abs(sin(Float64(i) * 0.0073)) * 27996.0; digits=1)
_exo_mass(i)          = round(0.01 + abs(cos(Float64(i) * 0.019)) * 13000.0; digits=2)
_exo_radius(i)        = round(0.3 + abs(sin(Float64(i) * 0.031)) * 24.7; digits=2)
_exo_temp(i)          = 50 + round(Int, abs(cos(Float64(i) * 0.013)) * 6950)
_exo_period(i)        = round(0.1 + abs(sin(Float64(i) * 0.0053)) * 99999.9; digits=1)
_exo_spectral(i)      = EXO_SPECTRAL_TYPES[mod1(i * 23 + 7, length(EXO_SPECTRAL_TYPES))]

"""Generate a single exoplanet row by index."""
function _exo_row(i::Int)
    Any[
        i,                      # ID
        _exo_name(i),           # Name
        _exo_constellation(i),  # Constellation
        _exo_method(i),         # Discovery Method
        _exo_year(i),           # Discovery Year
        _exo_distance(i),       # Distance (ly)
        _exo_mass(i),           # Mass (M⊕)
        _exo_radius(i),         # Radius (R⊕)
        _exo_temp(i),           # Temperature (K)
        _exo_period(i),         # Orbital Period (days)
        _exo_spectral(i),       # Spectral Type
    ]
end

const _EXO_COL_GETTERS = (
    identity,              # 1: ID
    _exo_name,             # 2
    _exo_constellation,    # 3
    _exo_method,           # 4
    _exo_year,             # 5
    _exo_distance,         # 6
    _exo_mass,             # 7
    _exo_radius,           # 8
    _exo_temp,             # 9
    _exo_period,           # 10
    _exo_spectral,         # 11
)

# ── SyntheticServerProvider ───────────────────────────────────────────

mutable struct SyntheticServerProvider <: PagedDataProvider
    total::Int              # virtual dataset size (e.g. 1_000_000)
    latency_mean::Float64   # mean fetch latency in seconds
    latency_std::Float64    # standard deviation of latency
    failure_rate::Float64   # probability of a fetch throwing an error (0.0–1.0)
end

function SyntheticServerProvider(total::Int;
    latency_mean::Float64=0.0,
    latency_std::Float64=0.0,
    failure_rate::Float64=0.0,
)
    SyntheticServerProvider(total, latency_mean, latency_std, failure_rate)
end

const _SYNTH_COLUMNS = [
    PagedColumn("ID";              align=col_right, sortable=true, filterable=false, col_type=:numeric),
    PagedColumn("Name";            sortable=true, col_type=:text),
    PagedColumn("Constellation";   sortable=true, col_type=:text),
    PagedColumn("Method";          sortable=true, col_type=:text),
    PagedColumn("Year";            align=col_right, sortable=true, col_type=:numeric),
    PagedColumn("Distance (ly)";   align=col_right, format=v -> string(v), col_type=:numeric),
    PagedColumn("Mass (M⊕)";      align=col_right, format=v -> string(v), col_type=:numeric),
    PagedColumn("Radius (R⊕)";    align=col_right, format=v -> string(v), col_type=:numeric),
    PagedColumn("Temp (K)";        align=col_right, format=v -> string(v), col_type=:numeric),
    PagedColumn("Period (days)";   align=col_right, format=v -> string(v), col_type=:numeric),
    PagedColumn("Spectral";        sortable=true, col_type=:text),
]

column_defs(::SyntheticServerProvider) = _SYNTH_COLUMNS
supports_search(::SyntheticServerProvider) = true
supports_filter(::SyntheticServerProvider) = true

function fetch_page(p::SyntheticServerProvider, req::PageRequest)
    # Simulate network latency (gaussian, clamped to non-negative)
    if p.latency_mean > 0.0
        delay = max(0.0, p.latency_mean + p.latency_std * randn())
        sleep(delay)
    end

    # Simulate retrieval failure
    if p.failure_rate > 0.0 && rand() < p.failure_rate
        error("Connection to exoplanet database timed out (simulated failure)")
    end

    has_search = !isempty(req.search)
    has_filter = !isempty(req.filters) && any(cf -> !isempty(cf.value), values(req.filters))
    has_sort   = req.sort_col > 0 && req.sort_dir != sort_none

    if !has_search && !has_filter && !has_sort
        # Fast path: direct index arithmetic, generate only the page
        total = p.total
        start = (req.page - 1) * req.page_size + 1
        stop = min(start + req.page_size - 1, total)
        rows = start <= total ? [_exo_row(i) for i in start:stop] : Vector{Any}[]
        return PageResult(rows, total)
    end

    # Slow path: scan, filter, sort — collect matching *indices* only
    q = lowercase(req.search)
    matching = Int[]
    sizehint!(matching, min(p.total, 100_000))

    # Pre-resolve filter checks
    filter_checks = Tuple{Int, ColumnFilter, Symbol}[]
    if has_filter
        for (ci, cf) in req.filters
            isempty(cf.value) && continue
            ci > length(_EXO_COL_GETTERS) && continue
            col_type = ci <= length(_SYNTH_COLUMNS) ? _SYNTH_COLUMNS[ci].col_type : :text
            push!(filter_checks, (ci, cf, col_type))
        end
    end

    for i in 1:p.total
        if has_search
            found = false
            for getter in _EXO_COL_GETTERS
                if occursin(q, lowercase(string(getter(i))))
                    found = true
                    break
                end
            end
            found || continue
        end

        skip = false
        for (ci, cf, col_type) in filter_checks
            getter = _EXO_COL_GETTERS[ci]
            if !apply_filter(cf.op, cf.value, getter(i), col_type)
                skip = true
                break
            end
        end
        skip && continue

        push!(matching, i)
    end

    total = length(matching)

    if has_sort && req.sort_col > 0
        sc = req.sort_col
        getter = _EXO_COL_GETTERS[sc]
        sort_keys = [getter(i) for i in matching]
        perm = sortperm(sort_keys; rev=(req.sort_dir == sort_desc))
        matching = matching[perm]
    end

    start = (req.page - 1) * req.page_size + 1
    stop = min(start + req.page_size - 1, total)
    page_indices = start <= total ? matching[start:stop] : Int[]
    rows = [_exo_row(i) for i in page_indices]

    PageResult(rows, total)
end

# ── SQLite exoplanet database ────────────────────────────────────────

const _SQLITE_DB_ROWS = 50_000

function _create_exoplanet_db()
    db_path = joinpath(tempdir(), "tachikoma_exoplanets.sqlite")
    # Re-use existing DB if it has the right row count
    if isfile(db_path)
        try
            db = SQLite.DB(db_path)
            count = first(DBInterface.execute(db, "SELECT COUNT(*) FROM exoplanets"))[1]
            if count == _SQLITE_DB_ROWS
                return db
            end
            DBInterface.close!(db)
        catch
        end
        rm(db_path; force=true)
    end

    db = SQLite.DB(db_path)
    DBInterface.execute(db, """
        CREATE TABLE exoplanets (
            id INTEGER PRIMARY KEY,
            name TEXT,
            constellation TEXT,
            discovery_method TEXT,
            discovery_year INTEGER,
            distance_ly REAL,
            mass REAL,
            radius REAL,
            temperature INTEGER,
            orbital_period REAL,
            spectral_type TEXT
        )
    """)

    DBInterface.execute(db, "BEGIN TRANSACTION")
    stmt = DBInterface.prepare(db, """
        INSERT INTO exoplanets VALUES (?,?,?,?,?,?,?,?,?,?,?)
    """)
    for i in 1:_SQLITE_DB_ROWS
        row = _exo_row(i)
        DBInterface.execute(stmt, row)
    end
    DBInterface.execute(db, "COMMIT")
    DBInterface.close!(stmt)

    db
end


# ── Simulation settings ──────────────────────────────────────────────

const LATENCY_PRESETS = [
    (name="No latency",     mean=0.0,  std=0.0),
    (name="Fast (50ms)",    mean=0.05, std=0.02),
    (name="Medium (200ms)", mean=0.2,  std=0.08),
    (name="Slow (800ms)",   mean=0.8,  std=0.3),
    (name="Awful (2s)",     mean=2.0,  std=0.8),
]

const FAILURE_PRESETS = [
    (name="Off",    rate=0.0),
    (name="10%",    rate=0.1),
    (name="30%",    rate=0.3),
    (name="50%",    rate=0.5),
    (name="90%",    rate=0.9),
]

# Settings modal state
mutable struct SettingsModal
    visible::Bool
    section::Int          # 1 = data source, 2 = page size, 3 = latency, 4 = failure rate
    latency_idx::Int      # selected latency preset
    failure_idx::Int      # selected failure preset
    page_size_idx::Int    # selected page size preset
    source_idx::Int       # 1 = synthetic, 2 = SQLite
end

const PAGE_SIZE_PRESETS = [25, 50, 100, 250, 500]
const SOURCE_PRESETS = ["Synthetic (1M rows)", "SQLite Database"]

SettingsModal() = SettingsModal(false, 1, 1, 1, 2, 1)  # default to 50 (index 2), synthetic

# ── Model ─────────────────────────────────────────────────────────────

mutable struct PagedDataTableModel <: Model
    quit::Bool
    tick::Int
    tq::TaskQueue
    synth_provider::SyntheticServerProvider
    sqlite_provider::Any  # SQLitePagedProvider or nothing
    active_source::Symbol  # :synthetic or :sqlite
    pdt::PagedDataTable
    settings::SettingsModal
end

function PagedDataTableModel(;
    provider::SyntheticServerProvider=SyntheticServerProvider(1_000_000),
)
    tq = TaskQueue()
    pdt = PagedDataTable(provider; page_size=50)

    # Create SQLite provider — SQLite is a hard dep of TachikomaDemos,
    # so TachikomaSQLiteExt is always loaded and the hook is set.
    sqlite_prov = nothing
    try
        db = _create_exoplanet_db()
        sqlite_prov = create_sqlite_provider(db, "exoplanets")
    catch e
        @warn "Failed to create SQLite provider" exception=e
    end

    m = PagedDataTableModel(false, 0, tq, provider, sqlite_prov, :synthetic, pdt, SettingsModal())
    # Wire async: widget calls this callback instead of blocking pdt_fetch!
    pdt.on_fetch = () -> pdt_fetch_async!(pdt, tq; task_id=:pdt_fetch)
    m
end

should_quit(m::PagedDataTableModel) = m.quit
task_queue(m::PagedDataTableModel) = m.tq

function _switch_source!(m::PagedDataTableModel)
    if m.settings.source_idx == 2 && m.sqlite_provider !== nothing
        m.active_source = :sqlite
        pdt_set_provider!(m.pdt, m.sqlite_provider)
    else
        m.active_source = :synthetic
        pdt_set_provider!(m.pdt, m.synth_provider)
    end
end

function _apply_settings!(m::PagedDataTableModel)
    s = m.settings
    preset = LATENCY_PRESETS[s.latency_idx]
    m.synth_provider.latency_mean = preset.mean
    m.synth_provider.latency_std = preset.std
    m.synth_provider.failure_rate = FAILURE_PRESETS[s.failure_idx].rate
    # Page size
    new_size = PAGE_SIZE_PRESETS[s.page_size_idx]
    if new_size != m.pdt.page_size
        pdt_set_page_size!(m.pdt, new_size)
    end
end

# ── Settings modal key handling ───────────────────────────────────────

"""Cycle a 1-based index within 1:n, wrapping at boundaries."""
_cycle_idx(current::Int, delta::Int, n::Int) = mod1(current + delta, n)

function _handle_settings_key!(m::PagedDataTableModel, evt::KeyEvent)::Bool
    s = m.settings

    if evt.key == :escape || (evt.key == :char && evt.char == 's')
        s.visible = false
        return true
    end

    # Switch section: data source + page size always, latency/failure for synthetic only
    sqlite_avail = m.sqlite_provider !== nothing
    nsources = sqlite_avail ? length(SOURCE_PRESETS) : 1
    nsections = m.active_source == :synthetic ? 4 : 2  # source, page size [, latency, failure]
    if evt.key == :tab
        s.section = _cycle_idx(s.section, 1, nsections)
        return true
    elseif evt.key == :backtab
        s.section = _cycle_idx(s.section, -1, nsections)
        return true
    end

    delta = evt.key == :up ? -1 : evt.key == :down ? 1 : 0
    if delta != 0
        if s.section == 1
            old_idx = s.source_idx
            s.source_idx = _cycle_idx(s.source_idx, delta, nsources)
            if s.source_idx != old_idx
                _switch_source!(m)
            end
        elseif s.section == 2
            s.page_size_idx = _cycle_idx(s.page_size_idx, delta, length(PAGE_SIZE_PRESETS))
        elseif s.section == 3
            s.latency_idx = _cycle_idx(s.latency_idx, delta, length(LATENCY_PRESETS))
        else
            s.failure_idx = _cycle_idx(s.failure_idx, delta, length(FAILURE_PRESETS))
        end
        _apply_settings!(m)
        return true
    end

    true  # consume all keys while modal is open
end

# ── Settings modal rendering ──────────────────────────────────────────

"""Render a single preset section (header + radio list)."""
function _render_preset_section!(buf::Buffer, cx::Int, cy::Int, max_cx::Int, max_y::Int,
                                 header::String, is_active::Bool, items, selected_idx::Int,
                                 label_fn::Function;
                                 section_style, selected_style, unselected_style,
                                 dim_style, active_marker_style,
                                 suffix_fn=nothing)
    hdr_text = is_active ? "▸ $header" : "  $header"
    hdr_style = is_active ? section_style : dim_style
    set_string!(buf, cx, cy, hdr_text, hdr_style; max_x=max_cx)
    cy += 1

    for (i, item) in enumerate(items)
        cy > max_y && break
        is_sel = i == selected_idx
        marker = is_sel ? "●" : "○"
        marker_s = is_sel ? active_marker_style : dim_style
        label_s = if is_active && is_sel
            selected_style
        elseif is_sel
            unselected_style
        else
            dim_style
        end

        label = label_fn(item)
        set_string!(buf, cx + 2, cy, marker, marker_s; max_x=max_cx)
        set_string!(buf, cx + 4, cy, label, label_s; max_x=max_cx)

        if suffix_fn !== nothing && is_sel
            suffix = suffix_fn(item)
            if suffix !== nothing
                set_string!(buf, cx + 4 + length(label), cy, suffix, dim_style; max_x=max_cx)
            end
        end
        cy += 1
    end
    cy
end

function _render_settings!(m::PagedDataTableModel, area::Rect, buf::Buffer)
    s = m.settings
    is_synth = m.active_source == :synthetic
    sqlite_avail = m.sqlite_provider !== nothing
    nsources = sqlite_avail ? length(SOURCE_PRESETS) : 1
    modal_w = min(48, area.width - 4)

    # Height depends on source: synthetic shows all 4 sections, SQLite shows source + page size
    base_h = 4 + nsources + 1 + length(PAGE_SIZE_PRESETS)
    if is_synth
        modal_h = min(base_h + 1 + length(LATENCY_PRESETS) + 1 + length(FAILURE_PRESETS) + 2, area.height - 2)
    else
        modal_h = min(base_h + 2, area.height - 2)
    end
    modal_h < 8 && return

    modal_rect = center(area, modal_w, modal_h)
    mx, my = modal_rect.x, modal_rect.y

    border_style = tstyle(:accent)
    title_style = tstyle(:title, bold=true)
    bg_style = tstyle(:text)
    section_style = tstyle(:primary, bold=true)
    selected_style = tstyle(:accent, bold=true)
    unselected_style = tstyle(:text)
    dim_style = tstyle(:text_dim)
    active_marker_style = tstyle(:accent)

    # Dim background
    for ry in area.y:bottom(area)
        for rx in area.x:right(area)
            set_char!(buf, rx, ry, ' ', dim_style)
        end
    end

    # Border with shimmer
    if m.tick > 0 && animations_enabled()
        border_shimmer!(buf, modal_rect, border_style.fg, m.tick;
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
    title = " Simulation Settings "
    set_string!(buf, mx + (modal_w - length(title)) ÷ 2, my, title, title_style)

    cx = mx + 3  # content x with padding
    max_cx = mx + modal_w - 2
    max_y = my + modal_h - 3
    cy = my + 1

    styles = (;section_style, selected_style, unselected_style, dim_style, active_marker_style)

    # ── Data Source section ──
    cy = _render_preset_section!(buf, cx, cy, max_cx, max_y,
            "Data Source", s.section == 1, SOURCE_PRESETS[1:nsources], s.source_idx,
            p -> p; styles...)

    cy += 1  # gap

    # ── Page Size section ──
    cy = _render_preset_section!(buf, cx, cy, max_cx, max_y,
            "Page Size", s.section == 2, PAGE_SIZE_PRESETS, s.page_size_idx,
            sz -> "$sz rows/page"; styles...)

    # Only show latency/failure for synthetic source
    if is_synth
        cy += 1  # gap

        # ── Latency section ──
        cy = _render_preset_section!(buf, cx, cy, max_cx, max_y,
                "Network Latency", s.section == 3, LATENCY_PRESETS, s.latency_idx,
                p -> p.name;
                suffix_fn = p -> p.mean > 0 ? " (σ=$(round(Int, p.std * 1000))ms)" : nothing,
                styles...)

        cy += 1  # gap

        # ── Failure rate section ──
        if cy <= max_y
            cy = _render_preset_section!(buf, cx, cy, max_cx, max_y,
                    "Failure Rate", s.section == 4, FAILURE_PRESETS, s.failure_idx,
                    p -> p.name; styles...)
        end
    end

    # Help row
    help_y = my + modal_h - 1
    help = " [↑↓]select [Tab]section [Esc/s]close "
    set_string!(buf, mx + (modal_w - length(help)) ÷ 2, help_y, help, dim_style)
end

# ── Event dispatch ────────────────────────────────────────────────────

function update!(m::PagedDataTableModel, evt::KeyEvent)
    # Settings modal intercepts everything when open
    if m.settings.visible
        _handle_settings_key!(m, evt)
        return
    end

    pdt = m.pdt

    # When detail/search/filter/goto are active, delegate to widget
    if pdt.show_detail || pdt.search_visible || pdt.filter_modal.visible || pdt.goto_visible
        handle_key!(pdt, evt)
        return
    end

    @match (evt.key, evt.char) begin
        (:char, 'q') || (:escape, _) => (m.quit = true)
        (:char, 's')                 => (m.settings.visible = true)
        _                            => handle_key!(pdt, evt)
    end
end

function update!(m::PagedDataTableModel, evt::MouseEvent)
    m.settings.visible && return  # ignore mouse while settings open
    handle_mouse!(m.pdt, evt)
end

function update!(m::PagedDataTableModel, evt::TaskEvent)
    if evt.id == :pdt_fetch
        if evt.value isa Exception
            pdt_receive_error!(m.pdt, evt.value)
        else
            pdt_receive!(m.pdt, evt.value)
        end
    end
end

function view(m::PagedDataTableModel, f::Frame)
    m.tick += 1
    pdt = m.pdt
    pdt.tick = m.tick
    buf = f.buffer

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    table_area  = rows[2]
    footer_area = rows[3]

    # ── Header ──
    source_label = m.active_source == :synthetic ? "Synthetic (1M rows)" : "SQLite ($(_SQLITE_DB_ROWS) rows)"
    title = "Exoplanet Catalog — $source_label"
    hx = header_area.x + max(0, (header_area.width - length(title)) ÷ 2)
    set_string!(buf, hx, header_area.y, title, tstyle(:title, bold=true))

    # ── Table ──
    sort_info = if pdt.sort_col > 0 && pdt.sort_dir != sort_none
        col_name = pdt.columns[pdt.sort_col].name
        dir_str = pdt.sort_dir == sort_asc ? "▲" : "▼"
        " sorted: $(col_name) $(dir_str) "
    else
        " unsorted "
    end

    filter_info = isempty(pdt.filters) ? "" : " filtered "
    search_info = isempty(pdt.search_query) ? "" : " search:\"$(pdt.search_query)\" "

    source_tag = m.active_source == :sqlite ? " [SQLite] " : ""
    pdt.block = Block(title="Exoplanets$(sort_info)$(filter_info)$(search_info)$(source_tag)",
                      border_style=tstyle(:border),
                      title_style=tstyle(:title))
    render(pdt, table_area, buf)

    # ── Footer ──
    s = m.settings
    preset = LATENCY_PRESETS[s.latency_idx]
    fpreset = FAILURE_PRESETS[s.failure_idx]
    loading_text = pdt.loading ? " ⟳ fetching…" : ""
    loading_style = tstyle(:accent, bold=true)

    source_indicator = m.active_source == :synthetic ? "SRC:Synthetic" : "SRC:SQLite"
    source_style = m.active_source == :sqlite ? tstyle(:accent, bold=true) : tstyle(:text_dim)

    left_spans = Span[
        Span("  [↑↓]nav [PgUp/PgDn]page [g]goto [/]search [f]filter [s]settings ",
                tstyle(:text_dim)),
    ]

    # Only show latency/failure info for synthetic source
    if m.active_source == :synthetic
        latency_text = "Latency: $(preset.name)"
        failure_text = fpreset.rate > 0 ? "Failures: $(fpreset.name)" : "Failures: Off"
        latency_style = s.latency_idx == 1 ? tstyle(:text_dim) : tstyle(:accent)
        failure_style = fpreset.rate > 0 ? tstyle(:error) : tstyle(:text_dim)
        push!(left_spans, Span(latency_text, latency_style))
        push!(left_spans, Span("  ", tstyle(:text_dim)))
        push!(left_spans, Span(failure_text, failure_style))
    end

    push!(left_spans, Span(loading_text, loading_style))

    render(StatusBar(
        left=left_spans,
        right=[
            Span(source_indicator, source_style),
            Span("  ", tstyle(:text_dim)),
            Span("[s]settings [q/Esc]quit ", tstyle(:text_dim)),
        ],
    ), footer_area, buf)

    # ── Settings modal overlay ──
    if m.settings.visible
        _render_settings!(m, f.area, buf)
    end
end

function paged_datatable_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(PagedDataTableModel(); fps=30)
end
