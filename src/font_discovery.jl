# ═══════════════════════════════════════════════════════════════════════
# Font Discovery ── find monospace fonts and font variants on the system
# ═══════════════════════════════════════════════════════════════════════

# ── Bold font variant discovery ──────────────────────────────────────

const _FONT_VARIANT_CACHE = Dict{Tuple{String,String}, String}()

"""
    find_font_variant(font_path, variant) → String

Find a style variant of a font file (e.g. "Bold", "Italic", "BoldItalic").
Returns the path to the variant file, or `""` if not found.
Results are cached to avoid repeated filesystem lookups during export.
"""
function find_font_variant(font_path::String, variant::String)
    isempty(font_path) && return ""
    key = (font_path, variant)
    haskey(_FONT_VARIANT_CACHE, key) && return _FONT_VARIANT_CACHE[key]
    result = _find_font_variant_uncached(font_path, variant)
    _FONT_VARIANT_CACHE[key] = result
    result
end

function _find_font_variant_uncached(font_path::String, variant::String)
    dir = dirname(font_path)
    base = basename(font_path)
    for (from, to) in [("-Regular", "-$variant"), ("-regular", "-$(lowercase(variant))"),
                        ("Regular", variant)]
        if occursin(from, base)
            candidate = joinpath(dir, replace(base, from => to))
            isfile(candidate) && return candidate
        end
    end
    name, ext = splitext(base)
    candidate = joinpath(dir, name * "-$variant" * ext)
    isfile(candidate) && return candidate
    ""
end

find_bold_variant(font_path::String) = find_font_variant(font_path, "Bold")

# ── Font discovery ────────────────────────────────────────────────────

const _MONO_KEYWORDS = [
    "mono", "code", "menlo", "monaco", "courier", "meslo", "fira",
    "consol", "sfnsmono", "hack", "iosevka", "source code",
    "inconsolata", "dejavu sans mono", "liberation mono", "noto mono",
    "ibm plex mono",
]

const _FONT_EXTENSIONS = (".ttf", ".ttc", ".otf")

const _DISCOVERED_FONTS = Ref{Union{Nothing, Vector{NamedTuple{(:name, :path), Tuple{String, String}}}}}(nothing)

function _font_search_dirs()
    dirs = String[]
    if Sys.isapple()
        push!(dirs, "/System/Library/Fonts", "/Library/Fonts")
        push!(dirs, joinpath(homedir(), "Library", "Fonts"))
    elseif Sys.islinux()
        push!(dirs, "/usr/share/fonts", "/usr/local/share/fonts")
        push!(dirs, joinpath(homedir(), ".local", "share", "fonts"))
        push!(dirs, joinpath(homedir(), ".fonts"))
    elseif Sys.iswindows()
        push!(dirs, raw"C:\Windows\Fonts")
        localappdata = get(ENV, "LOCALAPPDATA", "")
        if !isempty(localappdata)
            push!(dirs, joinpath(localappdata, "Microsoft", "Windows", "Fonts"))
        end
    end
    filter(isdir, dirs)
end

function _name_from_filename(fname::String)
    base = replace(fname, r"\.(ttf|ttc|otf)$"i => "")
    base = replace(base, r"[-_](Regular|Bold|Italic|Light|Medium|Thin|Black|ExtraBold|SemiBold|ExtraLight|BoldItalic|LightItalic|MediumItalic)$"i => "")
    # Insert spaces before capitals (CamelCase → Camel Case)
    base = replace(base, r"([a-z])([A-Z])" => s"\1 \2")
    base = replace(base, r"[-_]" => " ")
    strip(base)
end

function _is_mono_font(fname_lower::String)
    any(kw -> occursin(kw, fname_lower), _MONO_KEYWORDS)
end

"""
    discover_mono_fonts() → Vector{NamedTuple{(:name,:path), Tuple{String,String}}}

Scan system font directories for monospace fonts. Results are cached
for the session. The first entry is always `(name="(none — text hidden)", path="")`
for users who only want SVG export.
"""
function discover_mono_fonts()
    cached = _DISCOVERED_FONTS[]
    cached !== nothing && return cached

    found = Dict{String, String}()  # name => path (prefer Regular weight)

    for dir in _font_search_dirs()
        for (root, _dirs, files) in walkdir(dir)
            for f in files
                fl = lowercase(f)
                any(ext -> endswith(fl, ext), _FONT_EXTENSIONS) || continue
                _is_mono_font(fl) || continue

                path = joinpath(root, f)
                name = _name_from_filename(f)
                isempty(name) && continue

                if !haskey(found, name) || occursin(r"regular"i, f)
                    found[name] = path
                end
            end
        end
    end

    fonts = [(name=k, path=v) for (k, v) in found]
    sort!(fonts; by=x -> lowercase(x.name))
    pushfirst!(fonts, (name="(none — text hidden)", path=""))

    _DISCOVERED_FONTS[] = fonts
    fonts
end
