@testset "Demos compile and load" begin
    demos_dir = joinpath(@__DIR__, "..", "demos", "TachikomaDemos")
    if !isdir(demos_dir)
        @warn "demos directory not found, skipping"
        @test_skip false
    else
        tachikoma_dir = joinpath(@__DIR__, "..")
        code = """
        using Pkg
        Pkg.develop(; path=$(repr(tachikoma_dir)), io=devnull)
        Pkg.instantiate(; io=devnull)
        using TachikomaDemos
        m = TachikomaDemos.LauncherModel()
        @assert m.quit == false
        @assert m.selected == 1
        @assert length(TachikomaDemos.DEMO_ENTRIES) > 0
        print(length(TachikomaDemos.DEMO_ENTRIES))
        """
        out = IOBuffer()
        err = IOBuffer()
        p = run(pipeline(`julia --project=$demos_dir -e $code`, stdout=out, stderr=err); wait=false)
        wait(p)
        if p.exitcode != 0
            println("DEMO LOAD STDERR:\n", String(take!(err)))
        end
        @test p.exitcode == 0
        n_demos = tryparse(Int, String(take!(out)))
        @test n_demos !== nothing && n_demos > 0
    end
end
