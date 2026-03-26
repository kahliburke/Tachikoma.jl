module Tachi

# Load FreeTypeAbstraction + ColorTypes before Tachikoma so the
# TachikomaGifExt extension triggers at precompile time.
using FreeTypeAbstraction
using ColorTypes
using Tachikoma
using FFMPEG: FFMPEG_jll

import ColorTypes as CT

include("cli.jl")
include("render.jl")
include("mp4.jl")

(@main)(ARGS) = cli_main(ARGS)

end
