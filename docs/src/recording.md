# Recording & Export

Tachikoma has a built-in recording system that captures terminal output and exports to animated GIF and SVG. Recordings work both interactively (via hotkey) and programmatically (for documentation and CI).

## Interactive Recording

### Ctrl+R Workflow

Press **Ctrl+R** during any running app to start a recording:

1. A 5-second countdown appears: `"Recording in 5..."`
2. After the countdown, frame capture begins silently
3. Use the app normally — every rendered frame is captured
4. Press **Ctrl+R** again to stop
5. A `.tach` file is saved: `tachikoma_2026-02-18_143022.tach`
6. An export modal appears

### Export Modal

The modal lets you choose output formats and configure rendering:

<!-- tachi:widget export_modal w=42 h=13
inner = render(Block(title="Export Recording", title_style=tstyle(:title, bold=true), border_style=tstyle(:accent)), area, buf)
y = inner.y
set_string!(buf, inner.x + 1, y, ".tach saved", tstyle(:success))
y += 2
set_string!(buf, inner.x + 1, y, "[x]", tstyle(:accent, bold=true))
set_string!(buf, inner.x + 5, y, ".gif", tstyle(:text, bold=true))
set_string!(buf, inner.x + 12, y, "(animated GIF)", tstyle(:text_dim))
y += 1
set_string!(buf, inner.x + 1, y, "[ ]", tstyle(:text_dim))
set_string!(buf, inner.x + 5, y, ".svg", tstyle(:text))
set_string!(buf, inner.x + 12, y, "(animated SVG)", tstyle(:text_dim))
y += 2
set_string!(buf, inner.x + 1, y, "Font:", tstyle(:text))
set_string!(buf, inner.x + 8, y, "◀", tstyle(:accent))
set_string!(buf, inner.x + 10, y, "JetBrains Mono", tstyle(:text_bright))
set_string!(buf, inner.x + 25, y, "▶", tstyle(:accent))
y += 1
set_string!(buf, inner.x + 1, y, "Theme:", tstyle(:text))
set_string!(buf, inner.x + 8, y, "◀", tstyle(:accent))
set_string!(buf, inner.x + 10, y, "Dracula", tstyle(:text_bright))
set_string!(buf, inner.x + 18, y, "▶", tstyle(:accent))
y += 1
set_string!(buf, inner.x + 1, y, "[ ]", tstyle(:text_dim))
set_string!(buf, inner.x + 5, y, "Embed font in SVG", tstyle(:text))
y += 2
set_string!(buf, inner.x + 1, y, "[Space]", tstyle(:accent))
set_string!(buf, inner.x + 8, y, "toggle ", tstyle(:text_dim))
set_string!(buf, inner.x + 16, y, "[◀▶]", tstyle(:accent))
set_string!(buf, inner.x + 20, y, "adjust", tstyle(:text_dim))
y += 1
set_string!(buf, inner.x + 1, y, "[Enter]", tstyle(:accent))
set_string!(buf, inner.x + 8, y, "export ", tstyle(:text_dim))
set_string!(buf, inner.x + 16, y, "[Esc]", tstyle(:accent))
set_string!(buf, inner.x + 21, y, "done", tstyle(:text_dim))
-->

| Key | Action |
|:----|:-------|
| `↑`/`↓` | Navigate options |
| `Space` | Toggle format selection or embed option |
| `◀`/`▶` | Cycle font or theme |
| `Enter` | Export selected formats (runs in background) |
| `Esc` | Dismiss modal |

Export preferences (font, formats, theme, embed) are saved to `LocalPreferences.toml` and persist across sessions.

## Output Formats

### .tach (Native Binary)

The native recording format. Compact, lossless, and supports all Tachikoma features including pixel data. Files are Zstd-compressed.

<!-- tachi:noeval -->
```julia
# Load a .tach file
width, height, cells, timestamps, sixels = load_tach("recording.tach")

# Re-export to other formats
export_gif_from_snapshots("recording.gif", width, height, cells, timestamps;
                          sixel_snapshots=sixels)
export_svg("recording.svg", width, height, cells, timestamps)
```

### .gif (Animated GIF)

Animated GIF with per-frame timing, 256-color quantization, and LZW compression. Requires a TrueType/OpenType font for glyph rendering.

!!! note
    GIF export requires the `FreeTypeAbstraction` and `ColorTypes` packages. Call `enable_gif()` or add them to your project to activate the extension.

### .svg (Animated SVG)

SMIL-based animation with discrete frame visibility. Supports font embedding via base64 `@font-face`, braille character rendering as dot patterns, and Unicode block elements as rectangles.

SVG export works without any extra dependencies.

## Programmatic Recording

### record_app

Record a Model headlessly — no terminal needed:

```julia
record_app(model::Model, filename::String;
           width=80, height=24, frames=120, fps=30,
           events=Event[])
```

The model runs through its normal lifecycle (`view` is called `frames` times) and output is captured to a `.tach` file. Inject events at specific frames to simulate interaction:

```julia
events = [
    (30, KeyEvent(:down)),    # frame 30: press down
    (60, KeyEvent(:enter)),   # frame 60: press enter
    (90, KeyEvent(:escape)),  # frame 90: press escape
]
record_app(MyModel(), "demo"; width=80, height=24, frames=120, events=events)
```

### record_widget

Record a single widget's rendering:

```julia
record_widget(filename, width, height, num_frames; fps=10) do buf, area, frame
    # Render your widget for this frame
    progress = frame / num_frames
    render(Gauge(progress; label="$(round(Int, progress*100))%"), area, buf)
end
```

The callback receives `(buf, area, frame_idx)` and is called once per frame. A 4-argument form `(buf, area, frame_idx, frame)` is available for pixel-producing widgets.

### record_gif

Record directly to GIF without an intermediate `.tach` file:

<!-- tachi:noeval -->
```julia
record_gif("demo.gif", 80, 24, 100; fps=15,
           font_path="/path/to/JetBrainsMono.ttf",
           font_size=14, cell_w=10, cell_h=20)
```

The callback form is the same as `record_widget`.

## Font Discovery

Tachikoma scans standard system directories for monospace fonts:

```julia
fonts = discover_mono_fonts()
# → [(name="JetBrains Mono", path="/Library/Fonts/JetBrainsMono.ttf"), ...]
```

The export modal uses this list for the font picker. Scanned directories:

- **macOS**: `/System/Library/Fonts`, `/Library/Fonts`, `~/Library/Fonts`
- **Linux**: `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.local/share/fonts`
- **Windows**: `C:\Windows\Fonts`

## GIF Extension Setup

GIF export is a weak dependency. Enable it with:

```julia
enable_gif()
```

This calls `Base.require` for `FreeTypeAbstraction` and `ColorTypes`. If those packages aren't installed, you'll get an error with installation instructions.

Check if the extension is loaded:

```julia
gif_extension_loaded()  # → Bool
```

## Export from .tach Files

Load a previously saved recording and re-export with different settings:

<!-- tachi:noeval -->
```julia
w, h, cells, ts, sixels = load_tach("recording.tach")

# GIF with a specific font
export_gif_from_snapshots("recording.gif", w, h, cells, ts;
    sixel_snapshots=sixels,
    font_path="/path/to/font.ttf",
    font_size=16, cell_w=10, cell_h=20)

# SVG with embedded font
export_svg("recording.svg", w, h, cells, ts;
    font_path="/path/to/font.ttf")
```

## Preferences

Export settings persist in `LocalPreferences.toml`:

| Preference | Default | Description |
|:-----------|:--------|:------------|
| `export_font` | `""` | Path to font file for GIF/APNG |
| `export_formats` | `"gif,svg"` | Comma-separated list of export formats |
| `export_theme` | `""` | Theme name for SVG colors |
| `export_embed_font` | `true` | Embed font in SVG via base64 |

These are set automatically through the export modal. To set them programmatically:

<!-- tachi:noeval -->
```julia
save_export_prefs!("/path/to/font.ttf", Set(["gif", "svg"]);
                   theme_name="dracula", embed_font=true)
```
