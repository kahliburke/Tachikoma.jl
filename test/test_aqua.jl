using Test
using Aqua
using Tachikoma

@testset "Aqua.jl" begin
    Aqua.test_all(Tachikoma; ambiguities=false)
end
