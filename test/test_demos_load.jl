@testset "Demos compile and load" begin
    demos_dir = joinpath(@__DIR__, "..", "demos", "TachikomaDemos")
    if !isdir(demos_dir)
        @warn "demos directory not found, skipping"
        @test_skip false
    else
        code = raw"""
        using Pkg
        Pkg.instantiate(; io=devnull)
        using TachikomaDemos
        m = TachikomaDemos.LauncherModel()
        @assert m.quit == false
        @assert m.selected == 1
        @assert length(TachikomaDemos.DEMO_ENTRIES) > 0
        print(length(TachikomaDemos.DEMO_ENTRIES))
        """
        out = IOBuffer()
        p = run(pipeline(`julia --project=$demos_dir -e $code`, stdout=out, stderr=devnull), wait=true)
        @test p.exitcode == 0
        n_demos = tryparse(Int, String(take!(out)))
        @test n_demos !== nothing && n_demos > 0
    end
end
