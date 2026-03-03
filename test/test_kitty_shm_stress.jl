#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════════
# Kitty SHM stress test — many concurrent shm segments per frame
#
# Verifies that the two-generation shm cleanup system works correctly
# with many concurrent image widgets.  Each widget creates one shm
# segment per frame; the cleanup must handle all of them without leaks.
#
# Two modes:
#   pixel — full PixelImage widgets in a grid (visual, limited by terminal size)
#   raw   — raw encode_kitty with 2×2 pixel matrices (no terminal size limit)
#
# Usage:
#   julia --project test/test_kitty_shm_stress.jl pixel 16
#   julia --project test/test_kitty_shm_stress.jl raw 10000
#   julia --project test/test_kitty_shm_stress.jl              # defaults: pixel 4
#
# Keys:   +/- to add/remove widgets, q/ESC to quit
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
using Tachikoma: _KITTY_SHM_CURRENT, _KITTY_SHM_PREVIOUS, _KITTY_SHM_COUNTER,
                 encode_kitty, ColorRGB

@enum StressMode mode_pixel mode_raw

@kwdef mutable struct ShmStressModel <: Model
    quit::Bool = false
    tick::Int = 0
    n_widgets::Int = 4
    mode::StressMode = mode_pixel
    imgs::Vector{Union{PixelImage, Nothing}} = Union{PixelImage, Nothing}[]
end

Tachikoma.should_quit(m::ShmStressModel) = m.quit

function Tachikoma.update!(m::ShmStressModel, evt::KeyEvent)
    if evt.key == :escape || evt.char == 'q'
        m.quit = true
    elseif evt.char == '+' || evt.char == '='
        m.n_widgets += 1
        resize!(m.imgs, 0)
    elseif evt.char == '-' || evt.char == '_'
        m.n_widgets = max(m.n_widgets - 1, 1)
        resize!(m.imgs, 0)
    end
end

function Tachikoma.update!(::ShmStressModel, ::MouseEvent) end

function _make_tile_pixels(idx::Int, tick::Int)
    sz = 8
    pixels = Matrix{ColorRGB}(undef, sz, sz)
    for py in 1:sz
        for px in 1:sz
            t = (px / sz + py / sz) / 2.0
            phase = (idx * 0.618 + tick * 0.02) * 2π
            r = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π)) * 255), 0, 255))
            g = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π + 2π/3)) * 255), 0, 255))
            b = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π + 4π/3)) * 255), 0, 255))
            pixels[py, px] = ColorRGB(r, g, b)
        end
    end
    pixels
end

function _draw_panel!(img::PixelImage, idx::Int, tick::Int)
    pw, ph = img.pixel_w, img.pixel_h
    for py in 1:ph
        for px in 1:pw
            t = (px / pw + py / ph) / 2.0
            phase = (idx * 0.618 + tick * 0.02) * 2π
            r = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π)) * 255), 0, 255))
            g = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π + 2π/3)) * 255), 0, 255))
            b = UInt8(clamp(round(Int, (0.5 + 0.5 * sin(phase + t * 4π + 4π/3)) * 255), 0, 255))
            set_pixel!(img, px, py, ColorRGB(r, g, b))
        end
    end
end

function _view_pixel!(m::ShmStressModel, f::Frame, grid_area::Rect)
    n = m.n_widgets
    side = ceil(Int, sqrt(n))
    cell_w = max(1, grid_area.width ÷ side)
    cell_h = max(1, grid_area.height ÷ side)

    if length(m.imgs) != n
        resize!(m.imgs, n)
        fill!(m.imgs, nothing)
    end

    buf = f.buffer
    widget_idx = 0
    for ri in 1:side
        for ci in 1:side
            widget_idx += 1
            widget_idx > n && break
            x = grid_area.x + (ci - 1) * cell_w
            y = grid_area.y + (ri - 1) * cell_h
            cell = Rect(x, y, cell_w, cell_h)

            img = m.imgs[widget_idx]
            if img === nothing || img.cells_w != cell_w || img.cells_h != cell_h
                img = PixelImage(cell_w, cell_h)
                m.imgs[widget_idx] = img
            end

            _draw_panel!(img, widget_idx, m.tick)
            render(img, cell, f; tick=m.tick)
        end
    end
end

function _view_raw!(m::ShmStressModel, f::Frame, grid_area::Rect)
    buf = f.buffer
    n = m.n_widgets
    side = ceil(Int, sqrt(n))
    # Each widget gets a 1×1 cell; encode_kitty with a 2×2 pixel matrix
    # placed at that cell position. Tiles that don't fit just wrap/overlap.
    widget_idx = 0
    for ri in 1:side
        for ci in 1:side
            widget_idx += 1
            widget_idx > n && break
            pixels = _make_tile_pixels(widget_idx, m.tick)
            data = encode_kitty(pixels; cols=1, rows=1)
            isempty(data) && continue
            x = grid_area.x + ((ci - 1) % grid_area.width)
            y = grid_area.y + ((ri - 1) % grid_area.height)
            cell = Rect(x, y, 1, 1)
            Tachikoma.render_graphics!(f, data, cell; format=gfx_fmt_kitty)
        end
    end
end

function Tachikoma.view(m::ShmStressModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    rows = split_layout(Layout(Vertical, [Fixed(2), Fill(), Fixed(1)]), area)
    length(rows) < 3 && return
    header_area, grid_area, footer_area = rows[1], rows[2], rows[3]

    n = m.n_widgets
    mode_label = m.mode == mode_pixel ? "pixel" : "raw"
    proto = graphics_protocol()
    proto_label = proto == gfx_kitty ? "KITTY (shm)" :
                  proto == gfx_sixel ? "SIXEL (no shm)" : "NONE (braille)"
    label = "SHM Stress — $(mode_label) — $(n) widgets — $proto_label"
    set_string!(buf, header_area.x + 1, header_area.y, label,
                tstyle(:accent, bold=true))
    set_string!(buf, header_area.x + 1, header_area.y + 1,
                "[+] add  [-] remove  [Q/ESC] quit",
                tstyle(:secondary))

    if m.mode == mode_pixel
        _view_pixel!(m, f, grid_area)
    else
        _view_raw!(m, f, grid_area)
    end

    # ── Footer: shm stats ──
    n_cur = length(_KITTY_SHM_CURRENT)
    n_prev = length(_KITTY_SHM_PREVIOUS)
    total = Int(_KITTY_SHM_COUNTER[])
    stats = "shm: current=$(n_cur) previous=$(n_prev) total_created=$(total)  frame=$(m.tick)"
    set_string!(buf, footer_area.x + 1, footer_area.y, stats, tstyle(:secondary))
end

# Parse args: [pixel|raw] [N]
let mode = mode_pixel, n = 4
    for arg in ARGS
        if arg == "pixel"
            mode = mode_pixel
        elseif arg == "raw"
            mode = mode_raw
        else
            n = parse(Int, arg)
        end
    end
    app(ShmStressModel(n_widgets=n, mode=mode); fps=30)
end
