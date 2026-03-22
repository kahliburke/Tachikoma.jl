module Tachikoma

using PrecompileTools
using Preferences
using FileWatching: poll_fd

include("style.jl")
include("buffer.jl")
include("layout.jl")
include("cast_recorder.jl")     # CastRecorder struct (before terminal.jl)
include("terminal.jl")
include("pty.jl")
include("events.jl")
include("scripting.jl")
include("async.jl")
include("resizable_layout.jl")
include("animation.jl")
include("widgets/widgets.jl")
include("sixel.jl")
include("kitty_graphics.jl")
include("sixel_canvas.jl")
include("sixel_image.jl")
include("widgets/blockcanvas.jl")
include("app.jl")
include("test_backend.jl")
include("paged/Paged.jl")       # PagedDataTable submodule
using .Paged                    # re-export all Paged symbols
include("font_discovery.jl")    # font scanning (before export_svg.jl)
include("export_stubs.jl")      # extension dispatch stubs + loaders (after widgets)
include("recording.jl")         # core recording functions (after app.jl + test_backend.jl)
include("export_svg.jl")        # SVG export (after font_discovery.jl)
include("export_prefs.jl")      # export preferences
include("tach_format.jl")       # .tach binary format (after recording.jl)
include("dotwave_terrain.jl")
include("phylo_tree.jl")
include("background.jl")
include("markdown.jl")

function __init__()
    load_light_mode!()
    load_theme!()
    load_animations!()
    load_render_backend!()
    load_decay_params!()
    load_bg_config!()
    load_window_opacity!()
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
       mouse_scroll_up, mouse_scroll_down, mouse_scroll_left, mouse_scroll_right,
       mouse_press, mouse_release, mouse_drag, mouse_move,
       Block, StatusBar, Span,
       # Layout
       Layout, Vertical, Horizontal, Constraint, Fixed, Fill, Percent, Min, Max, Ratio,
       split_layout, split_with_spacers,
       LayoutAlign, layout_start, layout_center, layout_end,
       layout_space_between, layout_space_around, layout_space_evenly,
       ResizableLayout, handle_resize!, reset_layout!, render_resize_handles!,
       # App framework
       app, @tachikoma_app, set_wake!,
       tty_path,
       prepare_for_exec!,
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
       PAPER, LATTE, SOLARIS, SAKURA, AYU,
       GRUVBOX, FROST, MEADOW, DUNE, LAVENDER, HORIZON,
       OVERCAST, DUSK,
       DARK_THEMES, LIGHT_THEMES, ALL_THEMES, THEME, RESET,
       light_mode, set_light_mode!, active_themes, canvas_bg,
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
       SelectableList, ListItem, TabBar, TabBarStyle, TabDecoration,
       BracketTabs, BoxTabs, PlainTabs, tab_height,
       Calendar, Scrollbar, inner_area,
       ScrollPane, push_line!, set_content!, set_total!, handle_mouse!,
       list_hit, list_scroll,
       TextInput, text, set_text!,
       Modal, Paragraph, WrapMode, no_wrap, word_wrap, char_wrap,
       Alignment, align_left, align_center, align_right,
       paragraph_line_count,
       TreeView, TreeNode,
       Separator,
       Checkbox, RadioGroup,
       Button, ButtonStyle, ButtonDecoration,
       BracketButton, BorderedButton, PlainButton, button_height,
       DropDown,
       TextArea,
       CodeEditor, tokenize_line, TokenKind, Token, editor_mode, pending_command!,
       tokenize_python, tokenize_shell, tokenize_typescript,
       tokenize_code, token_style,
       Chart, DataSeries, ChartType, chart_line, chart_scatter,
       DataTable, DataColumn, ColumnAlign, col_left, col_right, col_center,
       SortDir, sort_none, sort_asc, sort_desc, sort_by!,
       datatable_detail,
       PagedDataTable, pdt_set_provider!,
       Form, FormField,
       ProgressList, ProgressItem, TaskStatus,
       task_pending, task_running, task_done, task_error, task_skipped,
       # Floating windows
       FloatingWindow, WindowManager,
       window_rect, focused_window, bring_to_front!,
       focus_next!, focus_prev!, tile!, cascade!,
       handle_event!, step!, tick,
       window_opacity, set_window_opacity!, WINDOW_OPACITY,
       recording_enabled,
       # Terminal widget
       TerminalWidget, TermScreen, PTY, REPLWidget,
       pty_spawn, pty_pair, pty_close!, pty_resize!, pty_alive, drain!,
       route_output!,
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
       PixelImage, fill_rect!, load_pixels!, render_rgba!,
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
       gif_extension_loaded, tables_extension_loaded, sqlite_extension_loaded,
       enable_gif, enable_tables, enable_sqlite, create_sqlite_provider,
       discover_mono_fonts, find_font_variant, find_bold_variant,
       # Markdown extension
       MarkdownPane, set_markdown!,
       markdown_to_spans, enable_markdown, markdown_extension_loaded,
       # ANSI text
       parse_ansi, ansi_enabled, set_ansi_enabled!,
       # .tach format
       write_tach, load_tach, compress_dead_space

# ── Precompilation workload ──────────────────────────────────────────
@compile_workload begin
    tb = TestBackend(80, 24)
    r = Rect(1, 1, 80, 24)

    # Layout
    layout = Layout(Vertical, [Fixed(3), Fill(1), Fixed(1)])
    split_layout(layout, r)
    layout_h = Layout(Horizontal, [Percent(30), Fill(1), Fixed(20)])
    split_layout(layout_h, r)

    # Style
    Style(fg=BLUE.c500, bg=SLATE.c900, bold=true)

    # Widgets
    render_widget!(tb, Block(title="Test"))
    render_widget!(tb, Gauge(0.65, label="Loading"))
    render_widget!(tb, SelectableList(["Alpha", "Beta", "Gamma", "Delta"]))
    render_widget!(tb, TextInput(label="Search"))
    render_widget!(tb, Table(["Name", "Age"], [["Alice", "30"], ["Bob", "25"]]))
    render_widget!(tb, Sparkline([1.0, 4.0, 2.0, 8.0, 5.0, 7.0]))
    render_widget!(tb, BarChart([BarEntry("A", 5), BarEntry("B", 3), BarEntry("C", 8)]))

    # Canvas
    c = Canvas(40, 20)
    line!(c, 0, 0, 39, 19)
    circle!(c, 20, 10, 8)
    render_widget!(tb, c)

    # Animation
    tw = tween(0.0, 1.0, duration=30)
    advance!(tw)
    value(tw)

    # Buffer inspection
    row_text(tb, 1)
    char_at(tb, 1, 1)
    find_text(tb, "Test")
end

end
