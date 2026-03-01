using Test
using Tachikoma
using Base64: base64decode
using Supposition, Supposition.Data

const T = Tachikoma

# Dummy model for handle_default_binding! tests
struct _DummyModel <: T.Model end

@testset "Tachikoma" begin
    include("test_core.jl")
    include("test_events.jl")
    include("test_colors.jl")
    include("test_sixel.jl")
    include("test_kitty_graphics.jl")
    include("test_layout.jl")
    include("test_pbt.jl")
    include("test_widgets_extended.jl")
    include("test_codeeditor.jl")
    include("test_backgrounds.jl")
    include("test_recording.jl")
    include("test_async.jl")
    include("test_markdown.jl")
    include("test_widgets_coverage.jl")
    include("test_scripting.jl")
    include("test_animation.jl")
    include("test_tokenizers.jl")
    include("test_style.jl")
    include("test_ccall_safety.jl")
end
