module Paged

using ..Tachikoma
using ..Tachikoma: tstyle, set_char!, set_string!, Block, Rect, Buffer, Style,
    TextInput, text, set_text!,
    ColumnAlign, col_left, col_right, col_center,
    SortDir, sort_none, sort_asc, sort_desc,
    Scrollbar, StatusBar, Span,
    TaskQueue, spawn_task!, TaskEvent,
    pulse, brighten, to_rgb, NoColor, ColorRGB, Color256,
    Constraint, Fixed, Fill, Layout, Vertical, split_layout,
    right, bottom, inner, center,
    MARKER, SPINNER_BRAILLE,
    BOX_HEAVY, border_shimmer!, animations_enabled,
    list_hit, mouse_left, mouse_right, mouse_press, mouse_release, mouse_drag, mouse_move,
    mouse_scroll_up, mouse_scroll_down, MouseEvent,
    KeyEvent, Frame

# Functions extended with new methods for PagedDataTable
import ..Tachikoma: render, handle_key!, handle_mouse!, value, set_value!, focusable

include("types.jl")
include("providers.jl")
include("widget.jl")
include("filter_modal.jl")
include("render.jl")

export PagedDataTable, PagedDataProvider, PagedColumn, PageRequest, PageResult,
       InMemoryPagedProvider,
       FilterOp, ColumnFilter, FilterCapabilities,
       filter_contains, filter_eq, filter_neq, filter_gt, filter_gte,
       filter_lt, filter_lte, filter_regex, filter_wildcard,
       filter_op_label, filter_capabilities,
       fetch_page, column_defs, supports_search, supports_filter,
       apply_filter,
       create_sqlite_provider,
       FilterModalState,
       pdt_fetch!, pdt_fetch_async!, pdt_receive!, pdt_receive_error!,
       pdt_refresh!, pdt_set_page_size!, pdt_set_provider!

end # module
