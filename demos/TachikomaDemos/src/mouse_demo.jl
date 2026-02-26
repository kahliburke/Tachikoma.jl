# ═══════════════════════════════════════════════════════════════════════
# Mouse Demo ── interactive canvas that responds to click, drag, scroll
#
# Draw on a braille canvas by clicking and dragging. Scroll to change
# brush size. Right-click to erase. Middle-click to clear.
# Shows live event info in a status panel.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct MouseDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Canvas state (created on first view when we know the size)
    canvas::Union{Canvas, BlockCanvas, Nothing} = nothing
    canvas_area::Rect = Rect()
    # Brush
    brush_size::Int = 1
    # Last event info
    last_event::String = "move the mouse..."
    # Trail effect: recent points for glow
    trail::Vector{Tuple{Int, Int}} = Tuple{Int, Int}[]
    trail_max::Int = 40
    # Stats
    clicks::Int = 0
    drags::Int = 0
    scrolls::Int = 0
end

should_quit(m::MouseDemoModel) = m.quit

function update!(m::MouseDemoModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 'c' && clear_canvas!(m)
        evt.char == '+' && (m.brush_size = min(8, m.brush_size + 1))
        evt.char == '=' && (m.brush_size = min(8, m.brush_size + 1))
        evt.char == '-' && (m.brush_size = max(1, m.brush_size - 1))
    end
    evt.key == :escape && (m.quit = true)
end

function update!(m::MouseDemoModel, evt::MouseEvent)
    mods = ""
    evt.ctrl  && (mods *= " +ctrl")
    evt.shift && (mods *= " +shift")
    evt.alt   && (mods *= " +alt")
    m.last_event = "$(evt.button) $(evt.action) ($(evt.x),$(evt.y))$(mods)"

    # Check if click is in canvas area
    ca = m.canvas_area
    m.canvas === nothing && return
    ca.width == 0 && return
    in_canvas = contains(ca, evt.x, evt.y)

    if evt.button == mouse_scroll_up
        m.brush_size = min(8, m.brush_size + 1)
        m.scrolls += 1
    elseif evt.button == mouse_scroll_down
        m.brush_size = max(1, m.brush_size - 1)
        m.scrolls += 1
    elseif evt.button == mouse_middle && evt.action == mouse_press
        clear_canvas!(m)
    elseif in_canvas && evt.button == mouse_left
        if evt.action == mouse_press
            m.clicks += 1
            paint!(m, evt.x, evt.y)
        elseif evt.action == mouse_drag
            m.drags += 1
            paint!(m, evt.x, evt.y)
        end
    elseif in_canvas && evt.button == mouse_right
        if evt.action in (mouse_press, mouse_drag)
            erase!(m, evt.x, evt.y)
        end
    end
end

function clear_canvas!(m::MouseDemoModel)
    m.canvas !== nothing && clear!(m.canvas)
    empty!(m.trail)
end

function screen_to_dot(m::MouseDemoModel, sx::Int, sy::Int)
    ca = m.canvas_area
    # Convert screen coords to canvas-relative, then to dot-space
    cx = sx - ca.x
    cy = sy - ca.y
    dx = cx * 2
    dy = cy * 4
    (dx, dy)
end

function paint!(m::MouseDemoModel, sx::Int, sy::Int)
    m.canvas === nothing && return
    dx, dy = screen_to_dot(m, sx, sy)
    r = m.brush_size - 1
    for bx in (dx - r):(dx + r)
        for by in (dy - r):(dy + r)
            set_point!(m.canvas, bx, by)
        end
    end
    # Add to trail
    push!(m.trail, (dx, dy))
    while length(m.trail) > m.trail_max
        popfirst!(m.trail)
    end
end

function erase!(m::MouseDemoModel, sx::Int, sy::Int)
    m.canvas === nothing && return
    dx, dy = screen_to_dot(m, sx, sy)
    r = m.brush_size + 1  # slightly larger eraser
    for bx in (dx - r):(dx + r)
        for by in (dy - r):(dy + r)
            unset_point!(m.canvas, bx, by)
        end
    end
end

function view(m::MouseDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer

    # Layout: header | [canvas | info] | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header = rows[1]
    main_area = rows[2]
    footer = rows[3]

    # Split main into canvas and info panel
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(28)]), main_area)
    length(cols) < 2 && return
    canvas_rect = cols[1]
    info_rect = cols[2]

    # ── Header ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header.x, header.y, SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header.x + 2, header.y,
                "Mouse Demo", tstyle(:primary, bold=true))
    set_string!(buf, header.x + 14, header.y,
                " $(DOT) draw with your mouse", tstyle(:text_dim))

    # ── Canvas ──
    canvas_block = Block(
        border_style=tstyle(:border),
        title_style=tstyle(:title),
    )
    canvas_inner = render(canvas_block, canvas_rect, buf)
    m.canvas_area = canvas_inner

    # Create or resize canvas
    cw = canvas_inner.width
    ch = canvas_inner.height
    if m.canvas === nothing || m.canvas.width != cw || m.canvas.height != ch
        if cw > 0 && ch > 0
            m.canvas = create_canvas(cw, ch; style=tstyle(:primary))
        end
    else
        m.canvas.style = tstyle(:primary)
    end

    if m.canvas !== nothing
        render_canvas(m.canvas, canvas_inner, f)
    end

    # ── Info panel ──
    info_block = Block(
        title="info",
        border_style=tstyle(:border),
        title_style=tstyle(:title),
    )
    info_inner = render(info_block, info_rect, buf)
    iy = info_inner.y

    # Brush size visualization
    set_string!(buf, info_inner.x, iy, "brush", tstyle(:text, bold=true))
    iy += 1
    brush_vis = repeat("●", m.brush_size) * repeat("○", 8 - m.brush_size)
    set_string!(buf, info_inner.x, iy, brush_vis, tstyle(:accent))
    iy += 1
    set_string!(buf, info_inner.x, iy,
                "size: $(m.brush_size)", tstyle(:text_dim))

    # Stats
    iy += 2
    set_string!(buf, info_inner.x, iy, "stats", tstyle(:text, bold=true))
    iy += 1
    set_string!(buf, info_inner.x, iy,
                "clicks: $(m.clicks)", tstyle(:text))
    iy += 1
    set_string!(buf, info_inner.x, iy,
                "drags:  $(m.drags)", tstyle(:text))
    iy += 1
    set_string!(buf, info_inner.x, iy,
                "scrolls: $(m.scrolls)", tstyle(:text))

    # Last event
    iy += 2
    set_string!(buf, info_inner.x, iy, "last event", tstyle(:text, bold=true))
    iy += 1
    # Truncate to panel width
    evt_str = m.last_event
    max_w = info_inner.width
    if length(evt_str) > max_w
        evt_str = evt_str[1:max_w]
    end
    set_string!(buf, info_inner.x, iy, evt_str, tstyle(:accent))

    # Controls
    iy += 2
    set_string!(buf, info_inner.x, iy, "controls", tstyle(:text, bold=true))
    iy += 1
    controls = [
        "L-click  draw",
        "R-click  erase",
        "M-click  clear",
        "scroll   brush ±",
        "[+/-]    brush ±",
        "[c]      clear",
    ]
    for line in controls
        iy > bottom(info_inner) && break
        set_string!(buf, info_inner.x, iy, line, tstyle(:text_dim))
        iy += 1
    end

    # ── Footer ──
    render(StatusBar(
        left=[Span("  brush=$(m.brush_size) $(DOT) trail=$(length(m.trail)) ",
                    tstyle(:text_dim))],
        right=[Span("[q/Esc]quit ", tstyle(:text_dim))],
    ), footer, buf)
end

function mouse_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(MouseDemoModel(); fps=30)
end
