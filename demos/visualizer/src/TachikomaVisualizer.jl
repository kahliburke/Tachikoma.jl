module TachikomaVisualizer

using Tachikoma
import Tachikoma: should_quit, update!, view, init!, cleanup!

using WAV: wavread
using PortAudio: PortAudioStream
using FFTW: rfft
using DSP: Windows
using Sixel: sixel_encode
using Colors: RGB, N0f8, red, green, blue

# Sixel rendering for Matrix images (extends core Vector{UInt8} method)
function render_sixel!(f::Frame, img::AbstractMatrix, area::Rect)
    buf = IOBuffer()
    sixel_encode(buf, img)
    data = take!(buf)
    Tachikoma.render_sixel!(f, data, area)
end

include("visualizer.jl")

export visualizer

end
