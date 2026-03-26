module Tachi

# Load FreeTypeAbstraction + ColorTypes before Tachikoma so the
# TachikomaGifExt extension triggers at precompile time.
using FreeTypeAbstraction
using ColorTypes
using Tachikoma

import ColorTypes as CT

include("cli.jl")
include("render.jl")

(@main)(ARGS) = cli_main(ARGS)

end
