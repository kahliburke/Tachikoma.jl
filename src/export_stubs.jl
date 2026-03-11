# ═══════════════════════════════════════════════════════════════════════
# Extension dispatch stubs and convenience loaders
# ═══════════════════════════════════════════════════════════════════════

function export_gif_from_snapshots end
function export_apng_from_snapshots end

# Ref hooks — set by TachikomaGifExt.__init__()
const _gif_export_fn  = Ref{Union{Function, Nothing}}(nothing)
const _apng_export_fn = Ref{Union{Function, Nothing}}(nothing)

function gif_extension_loaded()
    _gif_export_fn[] !== nothing
end

# ── Extension convenience loaders ─────────────────────────────────

const _FREETYPEABSTRACTION_UUID = Base.UUID("663a7486-cb36-511b-a19d-713bb74d65c9")
const _COLORTYPES_UUID          = Base.UUID("3da002f7-5984-5a60-b8a6-cbb66c0b333f")
const _TABLES_UUID              = Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c")

_pkg_available(name::String, uuid::Base.UUID) =
    Base.locate_package(Base.PkgId(uuid, name)) !== nothing

_pkg_loaded(name::String, uuid::Base.UUID) =
    haskey(Base.loaded_modules, Base.PkgId(uuid, name))

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
    _pkg_available("FreeTypeAbstraction", _FREETYPEABSTRACTION_UUID) || push!(missing_pkgs, "FreeTypeAbstraction")
    _pkg_available("ColorTypes", _COLORTYPES_UUID) || push!(missing_pkgs, "ColorTypes")
    if !isempty(missing_pkgs)
        add_cmd = join(["\"$p\"" for p in missing_pkgs], ", ")
        error("GIF export requires $(join(missing_pkgs, ", ")).\n  Install with: using Pkg; Pkg.add([$add_cmd])")
    end
    Base.require(Main, :FreeTypeAbstraction)
    Base.require(Main, :ColorTypes)
    gif_extension_loaded() || @warn "TachikomaGifExt did not activate — possible version incompatibility."
    nothing
end

# Ref hooks — set by TachikomaTablesExt.__init__()
const _datatable_from_table = Ref{Union{Function, Nothing}}(nothing)
const _paged_provider_from_table = Ref{Union{Function, Nothing}}(nothing)

"""
    tables_extension_loaded() → Bool

Return `true` if the Tables.jl extension has been loaded (i.e. `DataTable`
accepts a Tables.jl-compatible source).
"""
function tables_extension_loaded()
    _datatable_from_table[] !== nothing
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
        error("Tables integration requires Tables.jl.\n  Install with: using Pkg; Pkg.add(\"Tables\")")
    end
    Base.require(Main, :Tables)
    tables_extension_loaded() || @warn "TachikomaTablesExt did not activate — possible version incompatibility."
    nothing
end

const _SQLITE_UUID      = Base.UUID("0aa819cd-b072-5ff4-a722-6bc24af294d9")
const _DBINTERFACE_UUID = Base.UUID("a10d1c49-ce27-4219-8d33-6db1a4562965")

"""
    sqlite_extension_loaded() → Bool

Return `true` if the SQLite extension has been loaded (i.e. `SQLitePagedProvider`
is available).
"""
function sqlite_extension_loaded()
    Paged._create_sqlite_provider[] !== nothing
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
        error("SQLite provider requires $(join(missing_pkgs, ", ")).\n  Install with: using Pkg; Pkg.add([$add_cmd])")
    end
    Base.require(Main, :SQLite)
    Base.require(Main, :DBInterface)
    sqlite_extension_loaded() || @warn "TachikomaSQLiteExt did not activate — possible version incompatibility."
    nothing
end
