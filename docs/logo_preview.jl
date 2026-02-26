# Logo preview for TACHIKOMA.jl docs hero
# Usage: include("docs/logo_preview.jl"); logo_preview3()

using Tachikoma
import Tachikoma: set_char!, Style, Buffer, Rect, Frame, Model, should_quit, update!, view,
    render, StatusBar, Span, tstyle, theme, to_rgb, dim_color, color_lerp, brighten,
    fbm, bottom, right, in_bounds, set_string!, Block, Layout, Vertical, Horizontal,
    Fixed, Fill, Percent, split_layout, ColorRGB, breathe, KeyEvent, app

set_theme!(:kokaku)

# ── Logo data (block font, '#' = filled) ──
const _LP_LOGO_DATA = [
    "#######   #####    #####  ##   ##  ##  ##  ##   #####   ###   ###   ##### ",
    "  ##     ##   ##  ##      ##   ##  ##  ## ##   ##   ##  #### ####  ##   ##",
    "  ##     #######  ##      #######  ##  ####    ##   ##  ## ### ##  #######",
    "  ##     ##   ##  ##      ##   ##  ##  ## ##   ##   ##  ##  #  ##  ##   ##",
    "  ##     ##   ##   #####  ##   ##  ##  ##  ##   #####   ##     ##  ##   ##",
]
const _LP_LOGO_H = length(_LP_LOGO_DATA)
const _LP_LOGO_W = maximum(length, _LP_LOGO_DATA)

# Edge mask: filled cells adjacent to empty
const _LP_LOGO_EDGE = let
    mask = falses(_LP_LOGO_H, _LP_LOGO_W)
    for r in 1:_LP_LOGO_H
        row = _LP_LOGO_DATA[r]
        for c in 1:length(row)
            row[c] == '#' || continue
            for (dr, dc) in ((0,-1),(0,1),(-1,0),(1,0))
                nr, nc = r + dr, c + dc
                if nr < 1 || nr > _LP_LOGO_H || nc < 1 || nc > length(_LP_LOGO_DATA[nr])
                    mask[r, c] = true; break
                elseif _LP_LOGO_DATA[nr][nc] != '#'
                    mask[r, c] = true; break
                end
            end
        end
    end
    mask
end

# .jl suffix character data
const _LP_JL_FINAL6 = [
    "      ###  ###     ",  # j dot (1px), l
    "           ###     ",  # j gap, l
    "    #####  ###     ",  # j crossbar, l
    "      ###  ###     ",  # j stem, l
    " ##   ###  ###     ",  # period (1px), j, l [baseline]
    "      ###          ",  # j descender
    "    ####           ",  # j hook
]

# Animation constants
const LOOP_PERIOD = 180  # ticks (6 sec at 30fps)
const LOOP_TAU = 2π / LOOP_PERIOD

# ── Render TACHIKOMA letters + shadows ──
function _render_logo_v3!(buf::Buffer, tx::Int, logo_y::Int, tick::Int, rect_bottom::Int, rect_right::Int)
    th = theme()
    c1 = to_rgb(th.primary)
    c2 = to_rgb(th.accent)
    τ = LOOP_TAU
    t = Float64(tick)

    # Pass 1: shadows
    for (row_i, line) in enumerate(_LP_LOGO_DATA)
        for col_i in 1:length(line)
            line[col_i] == '#' || continue
            sx, sy = tx + col_i, logo_y + row_i
            if in_bounds(buf, sx, sy) && sy <= rect_bottom && sx <= rect_right
                phase = col_i * 0.08
                float_h = clamp(0.5 +
                    0.25 * sin(τ * t + phase) +
                    0.15 * sin(2τ * t + phase * 0.7) +
                    0.10 * cos(3τ * t + phase * 1.3), 0.0, 1.0)
                shadow_rgb = dim_color(c1, 0.55 + 0.35 * float_h)
                set_char!(buf, sx, sy, '░', Style(fg=shadow_rgb))
            end
        end
    end

    # Pass 2: letters
    for (row_i, line) in enumerate(_LP_LOGO_DATA)
        for col_i in 1:length(line)
            line[col_i] == '#' || continue
            x = tx + col_i - 1
            y = logo_y + row_i - 1
            in_bounds(buf, x, y) || continue

            phase = col_i * 0.08
            float_h = clamp(0.5 +
                0.25 * sin(τ * t + phase) +
                0.15 * sin(2τ * t + phase * 0.7) +
                0.10 * cos(3τ * t + phase * 1.3), 0.0, 1.0)

            n = 0.5 + 0.3 * sin(τ * t * 0.5 + col_i * 0.07) +
                       0.2 * cos(τ * t + row_i * 0.5)
            fg = color_lerp(c1, c2, clamp(n, 0.0, 1.0))
            fg = brighten(fg, 0.10 + 0.25 * float_h)

            is_edge = _LP_LOGO_EDGE[row_i, col_i]
            if is_edge
                fg = brighten(fg, 0.20 + 0.25 * float_h)
            end

            scan_y = mod(t * 0.06, Float64(_LP_LOGO_H + 4)) - 2.0
            scan_dist = abs(Float64(row_i) - scan_y)
            if scan_dist < 1.5
                boost = (1.5 - scan_dist) / 1.5 * 0.45
                fg = brighten(fg, boost)
            end

            set_char!(buf, x, y, '█', Style(fg=fg, bold=is_edge))
        end
    end
end

# ── Model ──
mutable struct LogoPreview3 <: Model
    quit::Bool
    tick::Int
end
should_quit(m::LogoPreview3) = m.quit
function update!(m::LogoPreview3, evt::KeyEvent)
    evt.key == :escape && (m.quit = true)
end

function view(m::LogoPreview3, f::Frame)
    buf = f.buffer
    area = f.area
    th = theme()
    τ = LOOP_TAU
    t = Float64(m.tick)

    header_area = Rect(area.x, area.y, area.width, area.height - 1)

    # ── Background ──
    bg_dark = dim_color(to_rgb(th.primary), 0.82)
    bg_mid  = dim_color(to_rgb(th.accent), 0.72)
    for row in header_area.y:bottom(header_area)
        for col in header_area.x:right(header_area)
            in_bounds(buf, col, row) || continue
            v = 0.5 + 0.25 * sin(τ * t * 0.5 + col * 0.08 + row * 0.15) +
                       0.15 * cos(τ * t + col * 0.05 - row * 0.1)
            c = color_lerp(bg_dark, bg_mid, clamp(v, 0.0, 1.0))
            set_char!(buf, col, row, ' ', Style(bg=c))
        end
    end

    # ── Edges ──
    accent_rgb = to_rgb(th.accent)
    for col in header_area.x:right(header_area)
        t_top = 0.5 + 0.4 * sin(τ * t + col * 0.1)
        edge_color = color_lerp(dim_color(accent_rgb, 0.6),
                                brighten(accent_rgb, 0.1), clamp(t_top, 0.0, 1.0))
        set_char!(buf, col, header_area.y, '▁', Style(fg=edge_color))
        t_bot = 0.5 + 0.4 * sin(τ * t * 0.8 + col * 0.08 + 2.0)
        sep_color = color_lerp(dim_color(accent_rgb, 0.7), accent_rgb, clamp(t_bot, 0.0, 1.0))
        set_char!(buf, col, bottom(header_area), '▔', Style(fg=sep_color))
    end

    # ── Centering ──
    jl_vis_w = 14
    total_w = _LP_LOGO_W + 1 + jl_vis_w
    total_h = length(_LP_JL_FINAL6)
    start_x = header_area.x + max(0, (header_area.width - total_w) ÷ 2)
    logo_y = header_area.y + max(1, (header_area.height - total_h) ÷ 2)

    # ── TACHIKOMA ──
    _render_logo_v3!(buf, start_x, logo_y, m.tick, bottom(header_area), right(header_area))

    # ── .jl ──
    jl_data = _LP_JL_FINAL6
    jl_x = start_x + _LP_LOGO_W + 1
    jl_y = logo_y
    accent_rgb2 = to_rgb(th.accent)
    amber = ColorRGB(UInt8(255), UInt8(180), UInt8(80))
    c1 = to_rgb(th.primary)

    jl_phase = 7.1
    jl_float = clamp(0.5 +
        0.25 * sin(τ * t + jl_phase) +
        0.15 * sin(2τ * t + jl_phase * 0.7) +
        0.10 * cos(3τ * t + jl_phase * 1.3), 0.0, 1.0)

    # .jl shadows
    for row in 1:length(jl_data)
        for col in 1:length(jl_data[row])
            if jl_data[row][col] == '#'
                sx, sy = jl_x + col, jl_y + row
                if in_bounds(buf, sx, sy) && sy < area.y + area.height && sx < area.x + area.width
                    shadow_rgb = dim_color(c1, 0.55 + 0.35 * jl_float)
                    set_char!(buf, sx, sy, '░', Style(fg=shadow_rgb))
                end
            end
        end
    end

    # .jl letters
    for row in 1:length(jl_data)
        for col in 1:length(jl_data[row])
            if jl_data[row][col] == '#'
                sx = jl_x + col - 1
                sy = jl_y + row - 1
                if in_bounds(buf, sx, sy) && sx < area.x + area.width && sy < area.y + area.height
                    base_color = color_lerp(accent_rgb2, amber, 0.6)
                    c = brighten(base_color, 0.10 + 0.25 * jl_float + 0.05 * sin(τ * t + Float64(col) * 0.3))
                    set_char!(buf, sx, sy, '█', Style(fg=c))
                end
            end
        end
    end

    m.tick += 1

    render(StatusBar(
        left=[Span("  Logo Preview ", tstyle(:accent))],
        right=[Span("[Esc] quit ", tstyle(:text_dim))],
    ), Rect(area.x, bottom(area), area.width, 1), buf)
end

logo_preview3() = app(LogoPreview3(false, 0); fps=30)
