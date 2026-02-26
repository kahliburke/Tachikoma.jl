# Preferences

Tachikoma uses [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl) to persist user settings across sessions. Settings are stored in `LocalPreferences.toml` in your project directory.

## What's Persisted

| Setting | Key | Type |
|:--------|:----|:-----|
| Active theme | `theme` | String |
| Animations enabled | `animations_enabled` | Bool |
| Render backend | `render_backend` | String (`"braille"`, `"block"`, `"sixel"`) |
| Decay amount | `decay` | Float64 |
| Decay jitter | `decay_jitter` | Float64 |
| Decay rot probability | `decay_rot_prob` | Float64 |
| Decay noise scale | `decay_noise_scale` | Float64 |
| Background brightness | `bg_brightness` | Float64 |
| Background saturation | `bg_saturation` | Float64 |
| Background speed | `bg_speed` | Float64 |
| Cell pixel width | `cell_pixel_w` | Int |
| Cell pixel height | `cell_pixel_h` | Int |
| Pixel scale width | `sixel_scale_w` | Float64 |
| Pixel scale height | `sixel_scale_h` | Float64 |

## Settings Overlay

Press **Ctrl+S** during any app to open the interactive settings overlay:

<!-- tachi:widget settings_overlay w=40 h=12
inner = render(Block(title="Settings", title_style=tstyle(:title, bold=true), border_style=tstyle(:accent)), area, buf)
y = inner.y
set_string!(buf, inner.x + 1, y, "▸ Render Backend", tstyle(:accent, bold=true))
set_string!(buf, inner.x + 22, y, "braille", tstyle(:text_bright))
labels = ["Decay Amount", "Jitter Scale", "Rot Probability", "Noise Scale", "BG Brightness", "BG Saturation", "BG Speed"]
pcts = [40, 20, 0, 30, 30, 50, 50]
for i in 1:length(labels)
    ly = inner.y + i
    set_string!(buf, inner.x + 1, ly, "  " * labels[i], tstyle(:text))
    filled = div(pcts[i], 10)
    if filled > 0
        set_string!(buf, inner.x + 20, ly, repeat("█", filled), tstyle(:primary))
    end
    if filled < 10
        set_string!(buf, inner.x + 20 + filled, ly, repeat("░", 10 - filled), tstyle(:text_dim))
    end
    set_string!(buf, inner.x + 31, ly, lpad(string(pcts[i]) * "%", 4), tstyle(:text_dim))
end
y = inner.y + 9
set_string!(buf, inner.x + 1, y, "[↑↓]", tstyle(:accent))
set_string!(buf, inner.x + 5, y, "nav ", tstyle(:text_dim))
set_string!(buf, inner.x + 9, y, "[←→]", tstyle(:accent))
set_string!(buf, inner.x + 13, y, "adjust ", tstyle(:text_dim))
set_string!(buf, inner.x + 20, y, "[Enter]", tstyle(:accent))
set_string!(buf, inner.x + 27, y, "save ", tstyle(:text_dim))
set_string!(buf, inner.x + 32, y, "[Esc]", tstyle(:accent))
-->

Navigate with arrow keys, adjust with left/right, save with Enter.

## LocalPreferences.toml

Settings are saved to `LocalPreferences.toml` in the active project directory. Example:

```toml
[Tachikoma]
theme = "kaneda"
animations_enabled = true
render_backend = "braille"
decay = 0.0
decay_jitter = 0.0
decay_rot_prob = 0.0
decay_noise_scale = 0.0
bg_brightness = 0.3
bg_saturation = 0.5
bg_speed = 0.5
```

### Manual Overrides

You can edit `LocalPreferences.toml` directly. Changes take effect next time Tachikoma loads. This is useful for:

- Setting pixel dimensions when auto-detection fails
- Configuring defaults for a specific project
- Sharing settings via version control

### Pixel Size Overrides

If pixel graphics are mis-sized, override cell pixel dimensions:

```toml
[Tachikoma]
cell_pixel_w = 10
cell_pixel_h = 20
sixel_scale_w = 1.0
sixel_scale_h = 1.0
```

## Programmatic API

### Theme

```julia
theme()                   # get current Theme
set_theme!(:kaneda)       # set and save
```

### Animations

```julia
animations_enabled()      # check status
toggle_animations!()      # toggle and save
```

### Render Backend

<!-- tachi:noeval -->
```julia
render_backend()                      # get current
set_render_backend!(sixel_backend)    # set and save
cycle_render_backend!(1)              # cycle forward and save
```

### Decay

```julia
d = decay_params()        # get mutable DecayParams
d.decay = 0.5             # modify
# Saved when settings overlay is closed or manually via save_decay_params!()
```

### Background

```julia
cfg = bg_config()          # get mutable BackgroundConfig
cfg.brightness = 0.4       # modify
# Saved when settings overlay is closed or manually via save_bg_config!()
```

## Per-App Layout Persistence

[`ResizableLayout`](layout.md#resizablelayout) state is automatically saved and restored per model type. When your app exits, the current pane sizes are saved. Next time the app runs with the same model type, the layout is restored.

This happens automatically — no additional code needed beyond using `ResizableLayout`.
