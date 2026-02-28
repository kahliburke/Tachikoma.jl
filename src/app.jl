# ═══════════════════════════════════════════════════════════════════════
# Model ── Elm architecture: init / update / view / should_quit
# ═══════════════════════════════════════════════════════════════════════

"""
    @tachikoma_app

Import the Tachikoma callback functions so you can extend them with your own
methods. Place this after `using Tachikoma` in your module:

```julia
module MyApp
using Tachikoma
@tachikoma_app

struct App <: Model ... end
view(m::App, f::Frame) = ...
update!(m::App, e::KeyEvent) = ...
should_quit(m::App) = ...
end
```

Equivalent to:
```julia
import Tachikoma: view, update!, should_quit, init!, cleanup!,
                  handle_all_key_actions, copy_rect, task_queue
```
"""
macro tachikoma_app()
    esc(quote
        import Tachikoma: view, update!, should_quit, init!, cleanup!,
                          handle_all_key_actions, copy_rect, task_queue
    end)
end

"""
    Model

Abstract type for application state. Subtype this and implement:
- `view(model, frame)` — render the UI (required)
- `update!(model, event)` — handle events (required)
- `should_quit(model)` — return `true` to exit (default: `false`)
- `init!(model, terminal)` — one-time setup (optional)
- `cleanup!(model)` — teardown (optional)
"""
abstract type Model end

init!(::Model, ::Terminal) = nothing
update!(::Model, ::Event) = nothing
cleanup!(::Model) = nothing
should_quit(::Model) = false

"""
    handle_all_key_actions(model::Model) → Bool

Override to return `true` if the app should receive `key_release` events in
addition to `key_press` and `key_repeat`. By default, press and repeat events
are forwarded to `update!` but release events are dropped. Apps that need
release events (e.g. games) can override this to return `true`.
"""
handle_all_key_actions(::Model) = false

function view end

"""
    copy_rect(model::Model) → Union{Rect, Nothing}

Override to return the Rect of the focused pane for Ctrl+Y copy.
Return `nothing` to copy the full screen (default).
"""
copy_rect(::Model) = nothing

"""
    task_queue(model::Model) → Union{TaskQueue, Nothing}

Override to return a `TaskQueue` for background task integration.
When non-`nothing`, completed tasks are drained each frame and dispatched
to `update!(model, event)` as `TaskEvent`s. Default: `nothing` (no queue).
"""
task_queue(::Model) = nothing

# ═══════════════════════════════════════════════════════════════════════
# Default bindings ── framework-level key shortcuts
# ═══════════════════════════════════════════════════════════════════════

mutable struct AppOverlay
    show_theme::Bool
    theme_idx::Int
    show_help::Bool
    show_settings::Bool
    settings_idx::Int
    notify_text::String
    notify_ttl::Int           # frames remaining to show notification
    show_export::Bool
    export_selected::Vector{Bool}    # [gif, svg] toggles
    export_available::Vector{Bool}   # grayed out if extension not loaded
    export_idx::Int                  # cursor position (1..n formats, n+1 = font, n+2 = theme, n+3 = embed font)
    export_font_idx::Int             # index into discover_mono_fonts() list
    export_theme_idx::Int            # index into ALL_THEMES (1-based)
    export_embed_font::Bool          # embed font in SVG via base64 @font-face
    pending_stop::Bool               # deferred stop_recording!
    pending_export::Bool             # deferred _do_exports!
end
AppOverlay() = AppOverlay(false, 1, false, false, 1, "", 0,
                          false, [false, false],
                          [true, true], 1, 1, 1,
                          true, false, false)

"""
    clipboard_copy!(text::String)

Copy text to the system clipboard. Uses `pbcopy` on macOS, `xclip` on Linux.
"""
function clipboard_copy!(text::String)
    try
        if Sys.isapple()
            open(pipeline(`pbcopy`), "w") do io
                write(io, text)
            end
        elseif Sys.islinux()
            open(pipeline(`xclip -selection clipboard`), "w") do io
                write(io, text)
            end
        end
    catch
        # Silently ignore clipboard errors (e.g., xclip not installed)
    end
    nothing
end

function handle_default_binding!(t::Terminal, overlay::AppOverlay, model::Model, evt::KeyEvent)
    # Theme overlay is open — consume keys
    if overlay.show_theme
        if evt.key == :escape
            overlay.show_theme = false
        elseif evt.key == :up
            overlay.theme_idx = mod1(overlay.theme_idx - 1, length(ALL_THEMES))
            set_theme!(ALL_THEMES[overlay.theme_idx])
        elseif evt.key == :down
            overlay.theme_idx = mod1(overlay.theme_idx + 1, length(ALL_THEMES))
            set_theme!(ALL_THEMES[overlay.theme_idx])
        elseif evt.key == :enter
            save_theme(theme().name)
            overlay.show_theme = false
        end
        return true
    end
    # Help overlay is open — consume keys
    if overlay.show_help
        if evt.key == :escape || (evt.key == :ctrl && evt.char == '\x7f')
            overlay.show_help = false
        end
        return true
    end
    # Settings overlay is open — consume keys
    if overlay.show_settings
        _handle_settings_key!(overlay, evt)
        return true
    end
    # Ctrl+G → toggle mouse
    if evt.key == :ctrl && evt.char == 'g'
        toggle_mouse!(t)
        return true
    end
    # Ctrl+\ → open theme selector (byte 0x1c → Char(0x1c + 0x60) = '|')
    if evt.key == :ctrl && evt.char == '|'
        overlay.show_theme = true
        return true
    end
    # Ctrl+A → toggle animations (byte 0x01 → Char(0x01 + 0x60) = 'a')
    if evt.key == :ctrl && evt.char == 'a'
        toggle_animations!()
        state = animations_enabled() ? "ON" : "OFF"
        overlay.notify_text = "Animations: $state (saved)"
        overlay.notify_ttl = 90  # ~1.5s at 60fps
        return true
    end
    # Ctrl+S → open settings (byte 0x13 → Char(0x13 + 0x60) = 's')
    if evt.key == :ctrl && evt.char == 's'
        overlay.show_settings = true
        return true
    end
    # Ctrl+/ → open help (legacy: byte 0x1f → Char(0x1f + 0x60) = '\x7f')
    if evt.key == :ctrl && evt.char == '\x7f'
        overlay.show_help = true
        return true
    end
    # Ctrl+Y → copy focused pane (or full screen) to clipboard
    if evt.key == :ctrl && evt.char == 'y'
        buf = previous_buf(t)  # last rendered frame
        rect = copy_rect(model)
        rect === nothing && (rect = t.size)
        text = buffer_to_text(buf, rect)
        clipboard_copy!(text)
        return true
    end
    # Export overlay is open — consume keys
    if overlay.show_export
        _handle_export_key!(overlay, t.recorder, evt)
        return true
    end
    # Ctrl+R → toggle .tach recording (byte 0x12 → Char(0x12 + 0x60) = 'r')
    if evt.key == :ctrl && evt.char == 'r'
        rec = t.recorder
        if rec.active
            # Stop capturing immediately so no more frames are recorded,
            # but defer the file-writing so "Saving recording..." renders first.
            rec.active = false
            overlay.notify_text = "Saving recording..."
            overlay.notify_ttl = typemax(Int)
            overlay.pending_stop = true
        else
            start_recording!(rec, t.size.width, t.size.height)
            overlay.notify_text = "Recording in 5..."
            overlay.notify_ttl = typemax(Int)  # managed by countdown logic
        end
        return true
    end
    return false
end

function overlay_active(overlay::AppOverlay)
    overlay.show_theme || overlay.show_help || overlay.show_settings || overlay.show_export
end

function render_overlay!(overlay::AppOverlay, f::Frame)
    overlay.show_theme && return render_theme_overlay!(overlay, f)
    overlay.show_help && return render_help_overlay!(f)
    overlay.show_settings && return render_settings_overlay!(overlay, f)
    overlay.show_export && return render_export_overlay!(overlay, f)
    # Transient notification (rendered on top of normal view)
    overlay.notify_ttl > 0 && render_notification!(overlay, f)
    nothing
end

function render_notification!(overlay::AppOverlay, f::Frame)
    # typemax(Int) is a sentinel for "managed notification — don't auto-decrement".
    # Only finite TTL values should count down (countdown & deferred ops use typemax).
    if overlay.notify_ttl < typemax(Int)
        overlay.notify_ttl -= 1
    end
    buf = f.buffer
    area = f.area
    text = overlay.notify_text
    tw = length(text) + 4  # 2 padding each side

    # Centered near top
    toast = anchor(margin(area; top=1), tw, 1; h=:center, v=:top)
    bx, by = toast.x, toast.y

    # Fade: full brightness first 60 frames, then dim
    fade = overlay.notify_ttl < 30 ? Float64(overlay.notify_ttl) / 30.0 : 1.0

    th = theme()
    bg_color = th.accent
    fg_color = Color256(0)  # black text on accent background

    # Draw background bar
    for cx in bx:(bx + tw - 1)
        cx > right(area) && break
        set_char!(buf, cx, by, ' ', Style(bg=bg_color))
    end

    # Draw text centered in bar
    tx = bx + 2
    if fade < 1.0
        # Dim during fade-out
        fg_color = dim_color(to_rgb(bg_color), 1.0 - fade)
        set_string!(buf, tx, by, text, Style(fg=fg_color, bg=bg_color, bold=true);
                    max_x=right(area))
    else
        set_string!(buf, tx, by, text, Style(fg=fg_color, bg=bg_color, bold=true);
                    max_x=right(area))
    end
    nothing
end

function render_theme_overlay!(overlay::AppOverlay, f::Frame)
    buf = f.buffer
    area = f.area

    n = length(ALL_THEMES)
    modal_w = 30
    modal_h = n + 4
    modal_rect = center(area, modal_w, modal_h)

    # Dim background
    for row in area.y:bottom(area), col in area.x:right(area)
        set_char!(buf, col, row, ' ', Style(fg=Color256(238)))
    end

    # Draw border
    block = Block(
        title="Theme",
        border_style=tstyle(:accent, bold=true),
        title_style=tstyle(:accent, bold=true),
        box=BOX_HEAVY,
    )
    content = render(block, modal_rect, buf)

    # List themes
    rx = right(content)
    for (i, th) in enumerate(ALL_THEMES)
        y = content.y + i - 1
        y > bottom(content) && break
        if i == overlay.theme_idx
            for cx in content.x:rx
                set_char!(buf, cx, y, ' ', tstyle(:accent))
            end
            label = string(MARKER, ' ', th.name)
            set_string!(buf, content.x, y, label,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        else
            set_string!(buf, content.x + 2, y, th.name, tstyle(:text);
                        max_x=rx)
        end
    end

    # Footer hint
    hint_y = bottom(content)
    if hint_y > content.y + n
        set_string!(buf, content.x, hint_y,
                    "[↑↓] [Enter]save [Esc]close",
                    tstyle(:text_dim); max_x=rx)
    end
    nothing
end

const HELP_LINES = [
    "Ctrl+A       Toggle animations",
    "Ctrl+G       Toggle mouse mode",
    "Ctrl+R       Record .tach file",
    "Ctrl+S       Settings",
    "Ctrl+Y       Copy pane to clipboard",
    "Ctrl+\\       Theme selector",
    "Ctrl+?       This help",
    "Ctrl+C       Quit",
]

function render_help_overlay!(f::Frame)
    buf = f.buffer
    area = f.area

    n = length(HELP_LINES)
    modal_w = 38
    modal_h = n + 4
    modal_rect = center(area, modal_w, modal_h)

    # Dim background
    for row in area.y:bottom(area), col in area.x:right(area)
        set_char!(buf, col, row, ' ', Style(fg=Color256(238)))
    end

    block = Block(
        title="Help",
        border_style=tstyle(:accent, bold=true),
        title_style=tstyle(:accent, bold=true),
        box=BOX_HEAVY,
    )
    content = render(block, modal_rect, buf)

    rx = right(content)
    for (i, line) in enumerate(HELP_LINES)
        y = content.y + i - 1
        y > bottom(content) && break
        set_string!(buf, content.x + 1, y, line, tstyle(:text); max_x=rx)
    end

    hint_y = bottom(content)
    if hint_y > content.y + n
        set_string!(buf, content.x, hint_y,
                    "[Esc]close",
                    tstyle(:text_dim); max_x=rx)
    end
    nothing
end

# ── Settings overlay ──────────────────────────────────────────────────

const SETTINGS_ITEMS = [
    "Render Backend",
    "Decay Amount",
    "Jitter Scale",
    "Rot Probability",
    "Noise Scale",
    "BG Brightness",
    "BG Saturation",
    "BG Speed",
]

function _handle_settings_key!(overlay::AppOverlay, evt::KeyEvent)
    n = length(SETTINGS_ITEMS)
    if evt.key == :escape
        overlay.show_settings = false
    elseif evt.key == :up
        overlay.settings_idx = mod1(overlay.settings_idx - 1, n)
    elseif evt.key == :down
        overlay.settings_idx = mod1(overlay.settings_idx + 1, n)
    elseif evt.key == :left || evt.key == :right
        dir = evt.key == :right ? 1 : -1
        _adjust_setting!(overlay.settings_idx, dir)
    elseif evt.key == :enter
        save_decay_params!()
        save_bg_config!()
        overlay.show_settings = false
    end
end

function _adjust_setting!(idx::Int, dir::Int)
    d = DECAY[]
    step = 0.05
    if idx == 1
        # Cycle backend: braille → block → sixel (← →)
        cycle_render_backend!(dir)
    elseif idx == 2
        d.decay = clamp(d.decay + dir * step, 0.0, 1.0)
    elseif idx == 3
        d.jitter = clamp(d.jitter + dir * step, 0.0, 1.0)
    elseif idx == 4
        d.rot_prob = clamp(d.rot_prob + dir * step, 0.0, 1.0)
    elseif idx == 5
        d.noise_scale = clamp(d.noise_scale + dir * step, 0.0, 1.0)
    elseif idx == 6
        bg = BG_CONFIG[]
        bg.brightness = clamp(bg.brightness + dir * step, 0.0, 1.0)
    elseif idx == 7
        bg = BG_CONFIG[]
        bg.saturation = clamp(bg.saturation + dir * step, 0.0, 1.0)
    elseif idx == 8
        bg = BG_CONFIG[]
        bg.speed = clamp(bg.speed + dir * step, 0.0, 1.0)
    end
end

function _settings_value_str(idx::Int)
    if idx == 1
        rb = RENDER_BACKEND[]
        rb == sixel_backend ? "sixel" : rb == block_backend ? "block" : "braille"
    elseif idx == 2
        _pct_bar(DECAY[].decay)
    elseif idx == 3
        _pct_bar(DECAY[].jitter)
    elseif idx == 4
        _pct_bar(DECAY[].rot_prob)
    elseif idx == 5
        _pct_bar(DECAY[].noise_scale)
    elseif idx == 6
        _pct_bar(BG_CONFIG[].brightness)
    elseif idx == 7
        _pct_bar(BG_CONFIG[].saturation)
    elseif idx == 8
        _pct_bar(BG_CONFIG[].speed)
    else
        ""
    end
end

function _pct_bar(v::Float64)
    filled = round(Int, v * 10)
    empty = 10 - filled
    string(repeat('█', filled), repeat('░', empty), ' ',
           lpad(string(round(Int, v * 100)), 3), '%')
end

function render_settings_overlay!(overlay::AppOverlay, f::Frame)
    buf = f.buffer
    area = f.area

    n = length(SETTINGS_ITEMS)
    modal_w = 42
    modal_h = n + 5
    modal_rect = center(area, modal_w, modal_h)

    # Dim background
    for row in area.y:bottom(area), col in area.x:right(area)
        set_char!(buf, col, row, ' ', Style(fg=Color256(238)))
    end

    block = Block(
        title="Settings",
        border_style=tstyle(:accent, bold=true),
        title_style=tstyle(:accent, bold=true),
        box=BOX_HEAVY,
    )
    content = render(block, modal_rect, buf)

    rx = right(content)
    for (i, label) in enumerate(SETTINGS_ITEMS)
        y = content.y + i - 1
        y > bottom(content) && break
        val_str = _settings_value_str(i)
        if i == overlay.settings_idx
            for cx in content.x:rx
                set_char!(buf, cx, y, ' ', tstyle(:accent))
            end
            line = string(MARKER, ' ', rpad(label, 18), val_str)
            set_string!(buf, content.x, y, line,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        else
            line = string("  ", rpad(label, 18), val_str)
            set_string!(buf, content.x, y, line, tstyle(:text);
                        max_x=rx)
        end
    end

    # Footer hint
    hint_y = bottom(content)
    if hint_y > content.y + n
        set_string!(buf, content.x, hint_y,
                    "[↑↓]nav [←→]adjust [Enter]save [Esc]close",
                    tstyle(:text_dim); max_x=rx)
    end
    nothing
end

# ── Export recording overlay ──────────────────────────────────────────

const EXPORT_FORMATS = [".gif", ".svg"]
const EXPORT_LABELS  = ["animated GIF", "animated SVG"]

function render_export_overlay!(overlay::AppOverlay, f::Frame)
    buf = f.buffer
    area = f.area

    n = length(EXPORT_FORMATS)
    modal_w = 42
    modal_h = n + 12  # .tach + formats + blank + font + theme + embed + blank + 2 hints + borders
    modal_rect = center(area, modal_w, modal_h)

    # Dim background
    for row in area.y:bottom(area), col in area.x:right(area)
        set_char!(buf, col, row, ' ', Style(fg=Color256(238)))
    end

    block = Block(
        title="Export Recording",
        border_style=tstyle(:accent, bold=true),
        title_style=tstyle(:accent, bold=true),
        box=BOX_HEAVY,
    )
    content = render(block, modal_rect, buf)
    rx = right(content)

    # Show .tach saved notice
    set_string!(buf, content.x + 1, content.y, ".tach saved",
                tstyle(:success, bold=true); max_x=rx)

    # Format toggles
    for (i, fmt) in enumerate(EXPORT_FORMATS)
        y = content.y + i  # offset by 1 for the .tach notice
        y > bottom(content) && break
        avail = overlay.export_available[i]
        selected = overlay.export_selected[i]
        check = selected ? "[x]" : "[ ]"
        label = string(check, " ", fmt, "   (", EXPORT_LABELS[i], ")")

        if i == overlay.export_idx
            for cx in content.x:rx
                set_char!(buf, cx, y, ' ', tstyle(:accent))
            end
            set_string!(buf, content.x + 1, y, label,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        elseif !avail
            set_string!(buf, content.x + 1, y, label, tstyle(:text_dim);
                        max_x=rx)
        else
            set_string!(buf, content.x + 1, y, label, tstyle(:text);
                        max_x=rx)
        end
    end

    # Font selector row (after blank line)
    font_y = content.y + n + 2
    if font_y <= bottom(content)
        fonts = discover_mono_fonts()
        fi = clamp(overlay.export_font_idx, 1, length(fonts))
        font_name = fonts[fi].name
        max_name_w = modal_w - 15  # room for "Font:  ◀  ▶" + padding
        if length(font_name) > max_name_w
            font_name = font_name[1:max_name_w-1] * "…"
        end
        label = string("Font:  ◀ ", font_name, " ▶")

        is_font_row = overlay.export_idx == n + 1
        if is_font_row
            for cx in content.x:rx
                set_char!(buf, cx, font_y, ' ', tstyle(:accent))
            end
            set_string!(buf, content.x + 1, font_y, label,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        else
            set_string!(buf, content.x + 1, font_y, label, tstyle(:text);
                        max_x=rx)
        end
    end

    # Theme selector row
    theme_y = content.y + n + 3
    if theme_y <= bottom(content)
        ti = clamp(overlay.export_theme_idx, 1, length(ALL_THEMES))
        theme_name = ALL_THEMES[ti].name
        label = string("Theme: ◀ ", theme_name, " ▶")

        is_theme_row = overlay.export_idx == n + 2
        if is_theme_row
            for cx in content.x:rx
                set_char!(buf, cx, theme_y, ' ', tstyle(:accent))
            end
            set_string!(buf, content.x + 1, theme_y, label,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        else
            set_string!(buf, content.x + 1, theme_y, label, tstyle(:text);
                        max_x=rx)
        end
    end

    # Embed font toggle row
    embed_y = content.y + n + 4
    if embed_y <= bottom(content)
        check = overlay.export_embed_font ? "[x]" : "[ ]"
        label = string(check, " Embed font in SVG")

        is_embed_row = overlay.export_idx == n + 3
        if is_embed_row
            for cx in content.x:rx
                set_char!(buf, cx, embed_y, ' ', tstyle(:accent))
            end
            set_string!(buf, content.x + 1, embed_y, label,
                        Style(fg=Color256(0), bg=theme().accent, bold=true);
                        max_x=rx)
        else
            set_string!(buf, content.x + 1, embed_y, label, tstyle(:text);
                        max_x=rx)
        end
    end

    # Footer hints
    hint_y = content.y + n + 6
    if hint_y <= bottom(content)
        set_string!(buf, content.x, hint_y,
                    " [Space]toggle [◀▶]adjust",
                    tstyle(:text_dim); max_x=rx)
    end
    hint_y2 = content.y + n + 7
    if hint_y2 <= bottom(content)
        set_string!(buf, content.x, hint_y2,
                    " [Enter]export [Esc]done",
                    tstyle(:text_dim); max_x=rx)
    end
    nothing
end

function _save_export_overlay_prefs!(overlay::AppOverlay)
    fonts = discover_mono_fonts()
    fi = clamp(overlay.export_font_idx, 1, length(fonts))
    font_path = fonts[fi].path
    ti = clamp(overlay.export_theme_idx, 1, length(ALL_THEMES))
    theme_name = ALL_THEMES[ti].name
    selected_fmts = Set{String}()
    fmt_keys = ["gif", "svg"]
    for (i, key) in enumerate(fmt_keys)
        overlay.export_selected[i] && push!(selected_fmts, key)
    end
    save_export_prefs!(font_path, selected_fmts;
                       theme_name=theme_name,
                       embed_font=overlay.export_embed_font)
end

function _handle_export_key!(overlay::AppOverlay, rec::CastRecorder, evt::KeyEvent)
    n = length(EXPORT_FORMATS)
    total_rows = n + 3  # format rows + font row + theme row + embed font row
    if evt.key == :escape
        overlay.show_export = false
        # Persist font/theme/format prefs even when dismissing without export
        _save_export_overlay_prefs!(overlay)
        clear_recording!(rec)
    elseif evt.key == :up
        overlay.export_idx = mod1(overlay.export_idx - 1, total_rows)
    elseif evt.key == :down
        overlay.export_idx = mod1(overlay.export_idx + 1, total_rows)
    elseif evt.key == :left || evt.key == :right
        dir = evt.key == :right ? 1 : -1
        if overlay.export_idx == n + 2
            # Theme row: cycle themes
            nt = length(ALL_THEMES)
            overlay.export_theme_idx = mod1(overlay.export_theme_idx + dir, nt)
        elseif overlay.export_idx <= n || overlay.export_idx == n + 1
            # Font row (or format row as shortcut): cycle fonts
            fonts = discover_mono_fonts()
            nf = length(fonts)
            if nf > 0
                overlay.export_font_idx = mod1(overlay.export_font_idx + dir, nf)
            end
        end
    elseif evt.key == :char && evt.char == ' '
        idx = overlay.export_idx
        if idx <= n && overlay.export_available[idx]
            overlay.export_selected[idx] = !overlay.export_selected[idx]
        elseif idx == n + 3
            overlay.export_embed_font = !overlay.export_embed_font
        end
    elseif evt.key == :enter
        overlay.notify_text = "Exporting..."
        overlay.notify_ttl = typemax(Int)
        overlay.show_export = false
        overlay.pending_export = true
    end
end

function _setup_export_modal!(overlay::AppOverlay, rec::CastRecorder)
    overlay.show_export = true
    # Auto-load GIF extension if packages are available
    if !gif_extension_loaded()
        try enable_gif() catch end
    end
    # Pre-select formats from saved preferences
    overlay.export_selected = [
        "gif" in EXPORT_FORMATS_PREF[],
        "svg" in EXPORT_FORMATS_PREF[],
    ]
    overlay.export_available = [gif_extension_loaded(), true]
    overlay.export_idx = 1
    # Resolve font index from saved preference
    fonts = discover_mono_fonts()
    saved_path = EXPORT_FONT_PREF[]
    font_idx = 1  # default to "(none)"
    for (i, f) in enumerate(fonts)
        if f.path == saved_path
            font_idx = i
            break
        end
    end
    overlay.export_font_idx = font_idx
    # Resolve theme index from saved preference (or current theme)
    saved_theme = EXPORT_THEME_PREF[]
    theme_idx = 1
    for (i, th) in enumerate(ALL_THEMES)
        if (!isempty(saved_theme) && th.name == saved_theme) ||
           (isempty(saved_theme) && th === THEME[])
            theme_idx = i
            break
        end
    end
    overlay.export_theme_idx = theme_idx
    overlay.export_embed_font = EXPORT_EMBED_FONT_PREF[]
    overlay.notify_text = ""
    overlay.notify_ttl = 0
end

# ── Async export types ────────────────────────────────────────────────

struct ExportConfig
    base::String
    export_gif::Bool
    export_svg::Bool
    font_path::String
    font_name::String
    export_theme_name::String
    svg_fg::String
    text_rgb::ColorRGB
    svg_font_family::String
    svg_embed_font_path::String
end

struct RecordingSnapshot
    filename::String
    width::Int
    height::Int
    cell_snapshots::Vector{Vector{Cell}}
    pixel_snapshots::Vector{Vector{PixelSnapshot}}
    timestamps::Vector{Float64}
end

function snapshot_recording(rec::CastRecorder)
    RecordingSnapshot(rec.filename, rec.width, rec.height,
                      copy(rec.cell_snapshots), copy(rec.pixel_snapshots),
                      copy(rec.timestamps))
end

function _resolve_export_config(overlay::AppOverlay, snap::RecordingSnapshot)
    base = replace(snap.filename, r"\.tach$" => "")

    # Get selected font (main thread — fonts cache not thread-safe)
    fonts = discover_mono_fonts()
    fi = clamp(overlay.export_font_idx, 1, length(fonts))
    font_path = fonts[fi].path
    font_name = fonts[fi].name

    # Get selected theme colors
    ti = clamp(overlay.export_theme_idx, 1, length(ALL_THEMES))
    export_theme = ALL_THEMES[ti]
    svg_fg = _color_to_hex(export_theme.text)
    svg_fg === nothing && (svg_fg = _SVG_DEFAULT_FG)
    text_rgb = to_rgb(export_theme.text)

    # Build font-family CSS
    ff = if !isempty(font_name) && font_name != "(none — text hidden)"
        string("'", font_name, "',", _SVG_DEFAULT_FONTS)
    else
        _SVG_DEFAULT_FONTS
    end
    svg_font = overlay.export_embed_font ? font_path : ""

    # Save preferences on main thread (Preferences.jl not thread-safe)
    selected_fmts = Set{String}()
    fmt_keys = ["gif", "svg"]
    for (i, key) in enumerate(fmt_keys)
        overlay.export_selected[i] && push!(selected_fmts, key)
    end
    save_export_prefs!(font_path, selected_fmts;
                       theme_name=export_theme.name,
                       embed_font=overlay.export_embed_font)

    ExportConfig(base, overlay.export_selected[1], overlay.export_selected[2],
                 font_path, font_name, export_theme.name,
                 svg_fg, text_rgb, ff, svg_font)
end

function _do_exports_bg(config::ExportConfig, snap::RecordingSnapshot)
    # invokelatest is required because extension methods (TachikomaGifExt)
    # may have been defined after the world age captured by Threads.@spawn.
    if config.export_gif
        try
            Base.invokelatest(export_gif_from_snapshots,
                              config.base * ".gif", snap.width, snap.height,
                              snap.cell_snapshots, snap.timestamps;
                              pixel_snapshots=snap.pixel_snapshots,
                              font_path=config.font_path,
                              default_fg=config.text_rgb)
        catch e
            @warn "GIF export failed" exception=e
        end
    end

    if config.export_svg
        try
            Base.invokelatest(export_svg,
                              config.base * ".svg", snap.width, snap.height,
                              snap.cell_snapshots, snap.timestamps;
                              font_family=config.svg_font_family,
                              font_path=config.svg_embed_font_path,
                              fg_color=config.svg_fg)
        catch e
            @warn "SVG export failed" exception=e
        end
    end

    # Build notification string
    base_name = basename(config.base)
    exported = String[".tach"]
    config.export_gif && push!(exported, ".gif")
    config.export_svg && push!(exported, ".svg")
    "Saved: $base_name ($(join(exported, " ")))"
end

function dispatch_event!(t::Terminal, overlay::AppOverlay, model::Model,
                        evt::Event, default_bindings::Bool)
    # With Kitty keyboard protocol, each key generates press, repeat, and
    # release events.  Press and repeat are forwarded (repeat = held key),
    # but release is dropped by default.  Apps that need release events
    # (e.g. games) can override `handle_all_key_actions(::MyModel) = true`.
    if evt isa KeyEvent && evt.action == key_release
        handle_all_key_actions(model) || return
    end
    if default_bindings && evt isa KeyEvent
        handled = handle_default_binding!(t, overlay, model, evt)
        handled || Base.invokelatest(update!, model, evt)
    else
        Base.invokelatest(update!, model, evt)
    end
end

"""
    app(model::Model; fps=60, default_bindings=true, on_stdout=nothing, on_stderr=nothing)

Run a TUI application with the Elm architecture loop: poll events → `update!` → `view`.
Enters the alternate screen, enables raw mode and mouse, then renders at `fps` frames/sec.
Press Ctrl+C to quit. Set `default_bindings=false` to disable built-in shortcuts
(theme picker, help overlay, etc.).

Stdout and stderr are automatically redirected during TUI mode to prevent background
`println()` from corrupting the display. Pass `on_stdout` / `on_stderr` callbacks to
receive captured lines (e.g., for an activity log). See [`with_terminal`](@ref).
"""
function app(model::Model; fps=60, default_bindings=true, on_stdout=nothing, on_stderr=nothing, tty_out=nothing, tty_size=nothing)
    with_terminal(; on_stdout, on_stderr, tty_out, tty_size) do t
        init!(model, t)
        _load_layout_prefs!(model)
        overlay = AppOverlay()
        _framework_tasks = TaskQueue()
        # Sync overlay theme_idx with current theme
        for (i, th) in enumerate(ALL_THEMES)
            th === THEME[] && (overlay.theme_idx = i; break)
        end
        frame_interval = 1.0 / fps
        next_frame = time()
        quit = false
        try
            while !quit && !should_quit(model)
                # Wait until next frame, processing events as they arrive.
                # When rendering exceeds the frame budget, the poll loop below
                # would be skipped entirely (now >= next_frame), starving input.
                # Guarantee at least one blocking poll per frame so keyboard
                # events are never missed, even under heavy render load.
                now = time()
                if now >= next_frame
                    # Behind schedule — still poll once with a short timeout
                    # so the terminal can deliver buffered keystrokes.
                    evt = poll_event(0.002)  # 2ms minimum event window
                    if evt !== nothing
                        if evt isa KeyEvent && evt.key == :ctrl_c && evt.action == key_press
                            quit = true
                        else
                            dispatch_event!(t, overlay, model, evt, default_bindings)
                        end
                    end
                else
                    while now < next_frame
                        evt = poll_event(next_frame - now)
                        if evt !== nothing
                            if evt isa KeyEvent && evt.key == :ctrl_c && evt.action == key_press
                                quit = true; break
                            end
                            dispatch_event!(t, overlay, model, evt, default_bindings)
                        end
                        now = time()
                    end
                end
                quit && break
                # Drain any remaining pending events
                while INPUT_ACTIVE[] && bytesavailable(_input_io()) > 0
                    evt = read_event()
                    evt isa KeyEvent && (evt = _track_key_state!(evt))
                    if evt isa KeyEvent && evt.key == :ctrl_c && evt.action == key_press
                        quit = true; break
                    end
                    dispatch_event!(t, overlay, model, evt, default_bindings)
                end
                quit && break
                # Drain async task queues
                drain_tasks!(_framework_tasks) do tevt
                    if tevt isa TaskEvent && tevt.id == :_export_done
                        msg = tevt.value
                        overlay.notify_text = msg isa String ? msg : "Export failed"
                        overlay.notify_ttl = 300
                    elseif tevt isa TaskEvent && tevt.id == :_tach_saved
                        # no-op, .tach write complete
                    else
                        dispatch_event!(t, overlay, model, tevt, default_bindings)
                    end
                end
                _user_tq = task_queue(model)
                if _user_tq !== nothing
                    drain_tasks!(_user_tq) do tevt
                        dispatch_event!(t, overlay, model, tevt, default_bindings)
                    end
                end
                next_frame += frame_interval
                if next_frame < time()
                    next_frame = time()
                end
                # Update recording countdown notification
                if default_bindings
                    rec = t.recorder
                    if rec.active && rec.countdown > 0.0
                        secs = ceil(Int, rec.countdown)
                        overlay.notify_text = "Recording in $secs..."
                        overlay.notify_ttl = typemax(Int)
                    elseif rec.active && rec.countdown <= 0.0 && overlay.notify_ttl == typemax(Int)
                        # Countdown just finished — clear notification so it
                        # doesn't leak into the first recorded frames.
                        # _draw_rec_badge! (drawn AFTER capture) provides the
                        # on-screen "● REC" indicator instead.
                        overlay.notify_text = ""
                        overlay.notify_ttl = 0
                    end
                end
                draw!(t) do f
                    # Skip expensive view() when an overlay modal is shown.
                    # The overlay covers the full screen, so the model view
                    # would be rendered and then immediately occluded — just
                    # wasted computation (especially heavy for sixel content).
                    if default_bindings && overlay_active(overlay)
                        render_overlay!(overlay, f)
                    else
                        Base.invokelatest(view, model, f)
                        default_bindings && render_overlay!(overlay, f)
                    end
                end
                # Process deferred operations AFTER draw so status is visible
                if default_bindings && overlay.pending_stop
                    overlay.pending_stop = false
                    rec = t.recorder
                    _tach_snap = snapshot_recording(rec)
                    spawn_task!(_framework_tasks, :_tach_saved) do
                        Base.invokelatest(write_tach,
                                          _tach_snap.filename, _tach_snap.width, _tach_snap.height,
                                          _tach_snap.cell_snapshots, _tach_snap.timestamps,
                                          _tach_snap.pixel_snapshots)
                        :ok
                    end
                    _setup_export_modal!(overlay, rec)
                end
                if default_bindings && overlay.pending_export
                    overlay.pending_export = false
                    _snap = snapshot_recording(t.recorder)
                    _cfg = _resolve_export_config(overlay, _snap)
                    clear_recording!(t.recorder)
                    spawn_task!(_framework_tasks, :_export_done) do
                        _do_exports_bg(_cfg, _snap)
                    end
                    overlay.notify_text = "Exporting..."
                    overlay.notify_ttl = typemax(Int)
                end
            end
        finally
            close(_framework_tasks.channel)
            _save_layout_prefs!(model)
        end
    end
    # cleanup! runs after with_terminal returns — terminal is fully restored
    # (leave_tui!, raw mode off, alt screen off) before app teardown begins.
    cleanup!(model)
end
