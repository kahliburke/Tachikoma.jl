module TachikomaColorTypesExt

using Tachikoma
using ColorTypes
using ColorTypes.FixedPointNumbers: N0f8

# ColorTypes → Tachikoma
function Tachikoma.to_rgb(c::RGB{N0f8})
    return Tachikoma.ColorRGB(
        reinterpret(UInt8, red(c)), reinterpret(UInt8, green(c)), reinterpret(UInt8, blue(c))
    )
end
function Tachikoma.to_rgb(c::RGB)
    return Tachikoma.ColorRGB(
        round(UInt8, Float64(red(c)) * 255),
        round(UInt8, Float64(green(c)) * 255),
        round(UInt8, Float64(blue(c)) * 255),
    )
end

function Tachikoma.to_rgba(c::RGBA{N0f8})
    return Tachikoma.ColorRGBA(
        reinterpret(UInt8, red(c)),
        reinterpret(UInt8, green(c)),
        reinterpret(UInt8, blue(c)),
        reinterpret(UInt8, alpha(c)),
    )
end
function Tachikoma.to_rgba(c::RGBA)
    return Tachikoma.ColorRGBA(
        round(UInt8, Float64(red(c)) * 255),
        round(UInt8, Float64(green(c)) * 255),
        round(UInt8, Float64(blue(c)) * 255),
        round(UInt8, Float64(alpha(c)) * 255),
    )
end
Tachikoma.to_rgba(c::RGB{N0f8}) = Tachikoma.ColorRGBA(Tachikoma.to_rgb(c))
Tachikoma.to_rgba(c::RGB) = Tachikoma.ColorRGBA(Tachikoma.to_rgb(c))

# Tachikoma → ColorTypes
function Tachikoma.to_colortype(c::Tachikoma.ColorRGB)
    return RGB{N0f8}(reinterpret(N0f8, c.r), reinterpret(N0f8, c.g), reinterpret(N0f8, c.b))
end
function Tachikoma.to_colortype(c::Tachikoma.ColorRGBA)
    return RGBA{N0f8}(
        reinterpret(N0f8, c.r),
        reinterpret(N0f8, c.g),
        reinterpret(N0f8, c.b),
        reinterpret(N0f8, c.a),
    )
end

end
