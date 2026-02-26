#!/usr/bin/env julia
using Tachikoma

mutable struct DiagModel <: Model
    quit::Bool
    img::Union{PixelImage, Nothing}
    tick::Int
    diag::String
    mode::Symbol   # :gradient, :solid, :bars
    need_redraw::Bool
end

Tachikoma.should_quit(m::DiagModel) = m.quit

function Tachikoma.update!(m::DiagModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
    elseif evt.key == :char && evt.char == 'g'
        m.mode = :gradient; m.need_redraw = true
    elseif evt.key == :char && evt.char == 's'
        m.mode = :solid; m.need_redraw = true
    elseif evt.key == :char && evt.char == 'b'
        m.mode = :bars; m.need_redraw = true
    end
    m.tick += 1
end

function _draw_gradient!(img::PixelImage)
    for py in 1:img.pixel_h
        for px in 1:img.pixel_w
            r = UInt8(clamp(round(Int, px / img.pixel_w * 255), 0, 255))
            g = UInt8(clamp(round(Int, py / img.pixel_h * 255), 0, 255))
            b = UInt8(128)
            set_pixel!(img, px, py, ColorRGB(r, g, b))
        end
    end
end

function _draw_solid!(img::PixelImage)
    c = ColorRGB(0x40, 0x80, 0xff)
    for py in 1:img.pixel_h
        for px in 1:img.pixel_w
            set_pixel!(img, px, py, c)
        end
    end
end

function _draw_bars!(img::PixelImage)
    colors = [
        ColorRGB(0xff, 0x00, 0x00),  # red
        ColorRGB(0x00, 0xff, 0x00),  # green
        ColorRGB(0x00, 0x00, 0xff),  # blue
        ColorRGB(0xff, 0xff, 0x00),  # yellow
        ColorRGB(0xff, 0x00, 0xff),  # magenta
        ColorRGB(0x00, 0xff, 0xff),  # cyan
        ColorRGB(0xff, 0xff, 0xff),  # white
        ColorRGB(0x80, 0x80, 0x80),  # gray
    ]
    bar_w = max(1, img.pixel_w ÷ length(colors))
    for py in 1:img.pixel_h
        for px in 1:img.pixel_w
            ci = min(length(colors), (px - 1) ÷ bar_w + 1)
            set_pixel!(img, px, py, colors[ci])
        end
    end
end

function Tachikoma.view(m::DiagModel, f::Frame)
    area = f.area
    buf = f.buffer

    # Gather diagnostics on first frame
    if m.diag == ""
        sap = Tachikoma.SIXEL_AREA_PX[]
        tap = Tachikoma.TEXT_AREA_PX[]
        tac = Tachikoma.TEXT_AREA_CELLS[]
        cpx = Tachikoma.CELL_PX[]
        ss  = Tachikoma.SIXEL_SCALE[]
        gfx = Tachikoma.graphics_protocol()
        m.diag = "SAP=$(sap) TAP=$(tap) TAC=$(tac) CPX=$(cpx) SS=$(ss) GFX=$(gfx)"
    end

    # Render PixelImage into the whole area (minus 2 rows for diagnostics)
    img_h = area.height - 2
    img_w = area.width
    (img_h < 2 || img_w < 2) && return

    if m.img === nothing || m.img.cells_w != img_w || m.img.cells_h != img_h
        m.img = PixelImage(img_w, img_h)
        m.need_redraw = true
    end

    if m.need_redraw
        clear!(m.img)
        if m.mode == :solid
            _draw_solid!(m.img)
        elseif m.mode == :bars
            _draw_bars!(m.img)
        else
            _draw_gradient!(m.img)
        end
        m.need_redraw = false
    end

    img_rect = Rect(area.x, area.y, img_w, img_h)
    render(m.img, img_rect, f; tick=m.tick)

    # Diagnostics at bottom
    diag_y = area.y + area.height - 2
    set_string!(buf, area.x + 1, diag_y, m.diag, tstyle(:text_dim))
    px_info = "$(m.mode) cells=$(img_w)x$(img_h) px=$(m.img.pixel_w)x$(m.img.pixel_h)  [G]radient [S]olid [B]ars [Q]uit"
    set_string!(buf, area.x + 1, diag_y + 1, px_info, tstyle(:accent))
end

app(DiagModel(false, nothing, 0, "", :gradient, true); fps=30)
