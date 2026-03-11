# ═══════════════════════════════════════════════════════════════════════
# Export Preferences ── persistent settings for recording export
# ═══════════════════════════════════════════════════════════════════════

const EXPORT_FONT_PREF = Ref("")
const EXPORT_FORMATS_PREF = Ref(Set{String}())
const EXPORT_THEME_PREF = Ref("")
const EXPORT_EMBED_FONT_PREF = Ref(true)

function load_export_prefs!()
    EXPORT_FONT_PREF[] = @load_preference("export_font", "")
    fmts_str = @load_preference("export_formats", "gif,svg")
    EXPORT_FORMATS_PREF[] = Set(filter(!isempty, Base.split(fmts_str, ",")))
    EXPORT_THEME_PREF[] = @load_preference("export_theme", "")
    EXPORT_EMBED_FONT_PREF[] = @load_preference("export_embed_font", true)
end

function save_export_prefs!(font_path::String, formats::Set{String};
                            theme_name::String="", embed_font::Bool=true)
    EXPORT_FONT_PREF[] = font_path
    EXPORT_FORMATS_PREF[] = formats
    EXPORT_THEME_PREF[] = theme_name
    EXPORT_EMBED_FONT_PREF[] = embed_font
    fmts_str = join(sort(collect(formats)), ",")
    @set_preferences!("export_font" => font_path, "export_formats" => fmts_str,
                       "export_theme" => theme_name, "export_embed_font" => embed_font)
end
