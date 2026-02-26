module Tachikoma

using Preferences

include("style.jl")
include("buffer.jl")
include("layout.jl")
include("cast_recorder.jl")     # CastRecorder struct (before terminal.jl)
include("terminal.jl")
include("events.jl")
include("scripting.jl")
include("async.jl")
include("resizable_layout.jl")
include("widgets/widgets.jl")
include("animation.jl")
include("sixel.jl")
include("kitty_graphics.jl")
include("sixel_canvas.jl")
include("sixel_image.jl")
include("widgets/blockcanvas.jl")
include("app.jl")
include("test_backend.jl")
include("recording.jl")         # recording functions (after app.jl + test_backend.jl)
include("tach_format.jl")       # .tach binary format (after recording.jl)
include("dotwave_terrain.jl")
include("phylo_tree.jl")
include("background.jl")
include("markdown.jl")

function __init__()
    load_theme!()
    load_animations!()
    load_render_backend!()
    load_decay_params!()
    load_bg_config!()
    load_export_prefs!()
end

# ── Public API ──
export # Core types
       Model, Terminal, Frame, Buffer, Rect,
       Style, Color256, Theme,
       Event, KeyEvent,
       KeyAction, key_press, key_repeat, key_release,
       MouseEvent, MouseButton, MouseAction,
       mouse_left, mouse_middle, mouse_right, mouse_none,
       mouse_scroll_up, mouse_scroll_down,
       mouse_press, mouse_release, mouse_drag, mouse_move,
       Block, StatusBar, Span,
       # Layout
       Layout, Vertical, Horizontal, Constraint, Fixed, Fill, Percent, Min, Max, Ratio,
       split_layout, split_with_spacers,
       LayoutAlign, layout_start, layout_center, layout_end,
       layout_space_between, layout_space_around, layout_space_evenly,
       ResizableLayout, handle_resize!, reset_layout!, render_resize_handles!,
       # App framework
       app, should_quit, update!, view, init!, cleanup!, copy_rect,
       prepare_for_exec!,
       handle_all_key_actions,
       task_queue,
       clipboard_copy!, buffer_to_text,
       # Async tasks
       TaskEvent, TaskQueue, CancelToken,
       spawn_task!, spawn_timer!, drain_tasks!,
       cancel!, is_cancelled,
       # Rendering primitives
       render, set_char!, set_string!, set_theme!,
       tstyle, theme, bottom, right, inner,
       pixel_size,
       cell_pixels, text_area_pixels, text_area_cells, sixel_scale, sixel_area_pixels,
       # Themes
       KOKAKU, ESPER, MOTOKO, KANEDA, NEUROMANCER, CATPPUCCIN,
       SOLARIZED, DRACULA, OUTRUN, ZENBURN, ICEBERG,
       ALL_THEMES, THEME, RESET,
       # Visual constants
       DOT, BARS_V, BARS_H, BLOCKS, SCANLINE, MARKER,
       SPINNER_BRAILLE, SPINNER_DOTS,
       # Geometry helpers
       margin, shrink, center, anchor,
       # Colors
       ColorRGB, to_rgb, color_lerp, color_wave,
       brighten, dim_color, hue_shift,
       # Tailwind palettes
       TailwindPalette, hex_to_color256,
       SLATE, GRAY, ZINC, NEUTRAL, STONE,
       RED, ORANGE, AMBER, YELLOW, LIME, GREEN, EMERALD, TEAL,
       CYAN, SKY, BLUE, INDIGO, VIOLET, PURPLE, FUCHSIA, PINK, ROSE,
       # Animation
       Tween, Spring, Timeline, TimelineEntry, Animator,
       tween, advance!, done, reset!,
       settled, retarget!,
       sequence, stagger, parallel,
       tick!, val, animate!,
       linear, ease_in_quad, ease_out_quad, ease_in_out_quad,
       ease_in_cubic, ease_out_cubic, ease_in_out_cubic,
       ease_out_elastic, ease_out_bounce, ease_out_back,
       # Organic animation
       noise, fbm, pulse, breathe, shimmer, jitter,
       flicker, drift, glow,
       animations_enabled, toggle_animations!,
       # Texture fills
       fill_gradient!, fill_noise!, border_shimmer!,
       # Widget protocol
       intrinsic_size, focusable, FocusRing, Container,
       next!, prev!, current, handle_key!,
       value, set_value!, valid,
       # Widgets
       BigText,
       Gauge, Sparkline, BarChart, BarEntry, Table,
       SelectableList, ListItem, TabBar, Calendar, Scrollbar, inner_area,
       ScrollPane, push_line!, set_content!, set_total!, handle_mouse!,
       list_hit, list_scroll,
       TextInput, text, set_text!,
       Modal, Paragraph, WrapMode, no_wrap, word_wrap, char_wrap,
       Alignment, align_left, align_center, align_right,
       paragraph_line_count,
       TreeView, TreeNode,
       Separator,
       Checkbox, RadioGroup,
       Button,
       DropDown,
       TextArea,
       CodeEditor, tokenize_line, TokenKind, Token, editor_mode,
       tokenize_python, tokenize_shell, tokenize_typescript,
       tokenize_code, token_style,
       Chart, DataSeries, ChartType, chart_line, chart_scatter,
       DataTable, DataColumn, ColumnAlign, col_left, col_right, col_center,
       SortDir, sort_none, sort_asc, sort_desc, sort_by!,
       datatable_detail,
       Form, FormField,
       ProgressList, ProgressItem, TaskStatus,
       task_pending, task_running, task_done, task_error, task_skipped,
       # Canvas
       Canvas, set_point!, line!, clear!, unset_point!, in_bounds,
       rect!, circle!, arc!,
       BlockCanvas,
       # Box styles
       BOX_ROUNDED, BOX_HEAVY, BOX_DOUBLE, BOX_PLAIN,
       # Render backend + decay
       RenderBackend, braille_backend, block_backend, sixel_backend,
       render_backend, set_render_backend!, cycle_render_backend!,
       DecayParams, decay_params,
       # Graphics protocol
       GraphicsProtocol, gfx_none, gfx_sixel, gfx_kitty, graphics_protocol,
       GraphicsRegion, GraphicsFormat, gfx_fmt_sixel, gfx_fmt_kitty,
       # Pixel canvas
       PixelCanvas, create_canvas, render_canvas, canvas_dot_size,
       set_pixel!, pixel_line!, fill_pixel_rect!,
       # PixelImage widget
       PixelImage, fill_rect!, load_pixels!,
       # Background system
       Background, DotWaveBackground, PhyloTreeBackground,
       CladogramBackground,
       render_background!, desaturate,
       BackgroundConfig, bg_config,
       # Phylo tree
       PhyloBranch, PhyloTree, PhyloTreePreset, PHYLO_PRESETS,
       generate_phylo_tree, render_phylo_tree!,
       # Cladogram
       CladoBranch, CladoTree, CladoPreset, CLADO_PRESETS,
       generate_clado_tree, render_clado_tree!,
       # Dotwave terrain
       WaveLayer, DotWavePreset, DOTWAVE_PRESETS,
       dotwave_height, render_dotwave_terrain!,
       # Scripting / event sequences
       EventScript, Wait, key, pause, seq, rep, chars,
       # Test backend
       TestBackend, render_widget!, char_at, style_at, row_text, find_text,
       # Recording
       CastRecorder, PixelSnapshot,
       record_app, record_widget, record_gif,
       start_recording!, stop_recording!, clear_recording!,
       export_svg, export_gif_from_snapshots, export_apng_from_snapshots,
       gif_extension_loaded, tables_extension_loaded,
       enable_gif, enable_tables, discover_mono_fonts, find_font_variant, find_bold_variant,
       # Markdown extension
       MarkdownPane, set_markdown!,
       markdown_to_spans, enable_markdown, markdown_extension_loaded,
       # .tach format
       write_tach, load_tach

end
