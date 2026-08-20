# ═══════════════════════════════════════════════════════════════════════
# Extension dispatch stubs and convenience loaders
# ═══════════════════════════════════════════════════════════════════════

function export_gif_from_snapshots end
function export_apng_from_snapshots end

"""
    default_gif_fallback_fonts() → Vector{String}

Platform-appropriate fallback fonts (CJK / emoji / symbols) used by GIF and
APNG export when the primary font lacks a glyph, so headless renders match
what a terminal shows via OS font substitution. Only existing files are
returned; pass `fallback_fonts=` to the exporters to override the list.

This is pure filesystem discovery (no font library needed), so it is honest
about coverage even before the GIF extension is loaded. We deliberately key
off ASCII font filenames: on macOS the Japanese-named system fonts are stored
NFD-normalized, so a literal `"ヒラギノ…"` path won't reliably match on disk.
"""
function default_gif_fallback_fonts()
    paths = String[]
    if Sys.isapple()
        sys = "/System/Library/Fonts"
        cands = [
            joinpath(sys, "Apple Symbols.ttf"),     # braille, math, misc symbols
            joinpath(sys, "AquaKana.ttc"),          # half- & full-width kana + kanji
            joinpath(sys, "Hiragino Sans GB.ttc"),  # broad CJK ideographs
            joinpath(sys, "Apple Color Emoji.ttc"),
        ] # emoji (best-effort; see notes)
        for p in cands
            (!isempty(p) && isfile(p)) && push!(paths, p)
        end
    elseif Sys.islinux()
        cands = [
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
            "/usr/share/fonts/noto/NotoColorEmoji.ttf",
        ]
        for p in cands
            isfile(p) && push!(paths, p)
        end
    elseif Sys.iswindows()
        win = joinpath(get(ENV, "WINDIR", "C:\\Windows"), "Fonts")
        for p in [
            joinpath(win, "msgothic.ttc"),    # CJK
            joinpath(win, "seguiemj.ttf"),     # emoji
            joinpath(win, "seguisym.ttf"),
        ]     # symbols
            isfile(p) && push!(paths, p)
        end
    end
    return paths
end

# Ref hooks — set by TachikomaGifExt.__init__()
const _gif_export_fn = Ref{Union{Function,Nothing}}(nothing)
const _apng_export_fn = Ref{Union{Function,Nothing}}(nothing)

function gif_extension_loaded()
    return _gif_export_fn[] !== nothing
end

# ── Extension convenience loaders ─────────────────────────────────

const _FREETYPEABSTRACTION_UUID = Base.UUID("663a7486-cb36-511b-a19d-713bb74d65c9")
const _COLORTYPES_UUID = Base.UUID("3da002f7-5984-5a60-b8a6-cbb66c0b333f")
const _TABLES_UUID = Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c")

function _pkg_available(name::String, uuid::Base.UUID)
    return Base.locate_package(Base.PkgId(uuid, name)) !== nothing
end

_pkg_loaded(name::String, uuid::Base.UUID) = haskey(Base.loaded_modules, Base.PkgId(uuid, name))

"""
    enable_gif()

Ensure the GIF export extension is loaded. If `FreeTypeAbstraction` and
`ColorTypes` are installed but not yet imported, this triggers their
loading so `TachikomaGifExt` activates. Errors with an install hint
if the packages are missing.
"""
function enable_gif()
    gif_extension_loaded() && return nothing
    missing_pkgs = String[]
    _pkg_available("FreeTypeAbstraction", _FREETYPEABSTRACTION_UUID) ||
        push!(missing_pkgs, "FreeTypeAbstraction")
    _pkg_available("ColorTypes", _COLORTYPES_UUID) || push!(missing_pkgs, "ColorTypes")
    if !isempty(missing_pkgs)
        add_cmd = join(["\"$p\"" for p in missing_pkgs], ", ")
        error(
            "GIF export requires $(join(missing_pkgs, ", ")).\n  Install with: using Pkg; Pkg.add([$add_cmd])",
        )
    end
    Base.require(Main, :FreeTypeAbstraction)
    Base.require(Main, :ColorTypes)
    gif_extension_loaded() ||
        @warn "TachikomaGifExt did not activate — possible version incompatibility."
    return nothing
end

# Ref hooks — set by TachikomaTablesExt.__init__()
const _datatable_from_table = Ref{Union{Function,Nothing}}(nothing)
const _paged_provider_from_table = Ref{Union{Function,Nothing}}(nothing)

"""
    tables_extension_loaded() → Bool

Return `true` if the Tables.jl extension has been loaded (i.e. `DataTable`
accepts a Tables.jl-compatible source).
"""
function tables_extension_loaded()
    return _datatable_from_table[] !== nothing
end

"""
    enable_tables()

Ensure the Tables.jl extension is loaded. If `Tables` is installed but
not yet imported, this triggers its loading so `TachikomaTablesExt`
activates. Errors with an install hint if the package is missing.
"""
function enable_tables()
    tables_extension_loaded() && return nothing
    if !_pkg_available("Tables", _TABLES_UUID)
        error(
            "Tables integration requires Tables.jl.\n  Install with: using Pkg; Pkg.add(\"Tables\")"
        )
    end
    Base.require(Main, :Tables)
    tables_extension_loaded() ||
        @warn "TachikomaTablesExt did not activate — possible version incompatibility."
    return nothing
end

const _SQLITE_UUID = Base.UUID("0aa819cd-b072-5ff4-a722-6bc24af294d9")
const _DBINTERFACE_UUID = Base.UUID("a10d1c49-ce27-4219-8d33-6db1a4562965")

"""
    sqlite_extension_loaded() → Bool

Return `true` if the SQLite extension has been loaded (i.e. `SQLitePagedProvider`
is available).
"""
function sqlite_extension_loaded()
    return Paged._create_sqlite_provider[] !== nothing
end

"""
    enable_sqlite()

Ensure the SQLite extension is loaded. If `SQLite` and `DBInterface` are
installed but not yet imported, this triggers their loading so
`TachikomaSQLiteExt` activates.
"""
function enable_sqlite()
    sqlite_extension_loaded() && return nothing
    missing_pkgs = String[]
    _pkg_available("SQLite", _SQLITE_UUID) || push!(missing_pkgs, "SQLite")
    _pkg_available("DBInterface", _DBINTERFACE_UUID) || push!(missing_pkgs, "DBInterface")
    if !isempty(missing_pkgs)
        add_cmd = join(["\"$p\"" for p in missing_pkgs], ", ")
        error(
            "SQLite provider requires $(join(missing_pkgs, ", ")).\n  Install with: using Pkg; Pkg.add([$add_cmd])",
        )
    end
    Base.require(Main, :SQLite)
    Base.require(Main, :DBInterface)
    sqlite_extension_loaded() ||
        @warn "TachikomaSQLiteExt did not activate — possible version incompatibility."
    return nothing
end
