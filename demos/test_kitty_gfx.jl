#!/usr/bin/env julia
using Tachikoma

mutable struct GfxTestModel <: Model
    quit::Bool
    img::Union{PixelImage, Nothing}
    tick::Int
    need_redraw::Bool
end

Tachikoma.should_quit(m::GfxTestModel) = m.quit

function Tachikoma.update!(m::GfxTestModel, evt::KeyEvent)
    if evt.key == :escape
        m.quit = true
    elseif evt.char == 's'
        Tachikoma.GRAPHICS_PROTOCOL[] = gfx_sixel
    elseif evt.char == 'k'
        Tachikoma.GRAPHICS_PROTOCOL[] = gfx_kitty
    elseif evt.char == 'n'
        Tachikoma.GRAPHICS_PROTOCOL[] = gfx_none
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

function Tachikoma.view(m::GfxTestModel, f::Frame)
    area = f.area
    buf = f.buffer

    # Status line at top
    proto = graphics_protocol()
    label = proto == gfx_kitty ? "KITTY" :
            proto == gfx_sixel ? "SIXEL" : "NONE (braille fallback)"
    set_string!(buf, area.x + 1, area.y,
                "Graphics: $label  |  [S]ixel  [K]itty  [N]one  [ESC] quit",
                tstyle(:accent))

    # Block rendered separately (matches the pattern used by working demos)
    blk = Block(title="Pixel Backend Test")
    img_area = Rect(area.x, area.y + 1, area.width, area.height - 1)
    inner = render(blk, img_area, buf)
    (inner.width >= 2 && inner.height >= 2) || return

    # Create/recreate PixelImage to match inner area (no block on the image)
    if m.img === nothing || m.img.cells_w != inner.width || m.img.cells_h != inner.height
        m.img = PixelImage(inner.width, inner.height)
        _draw_gradient!(m.img)
    end

    render(m.img, inner, f; tick=m.tick)
end

app(GfxTestModel(false, nothing, 0, true); fps=30)
