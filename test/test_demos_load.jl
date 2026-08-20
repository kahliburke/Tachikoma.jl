@testset "Demos compile and load" begin
    demos_dir = normpath(abspath(joinpath(@__DIR__, "..", "demos", "TachikomaDemos")))
    if !isdir(demos_dir)
        @warn "demos directory not found, skipping"
        @test_skip false
    else
        tachikoma_dir = normpath(abspath(joinpath(@__DIR__, "..")))

        # On 1.11+ the demo project's own `[sources]` entry already points at this
        # working tree, so no `Pkg.develop` is needed and nothing is written.
        #
        # On the 1.10 LTS `[sources]` is ignored entirely, and since Tachikoma is
        # registered, dropping the develop there would let the demos quietly resolve
        # the RELEASED package from General and smoke-test that instead of this
        # branch. So the LTS keeps it -- at the cost of `Pkg.develop` rewriting the
        # tracked demos Project.toml `[sources]` to an absolute local path. That is
        # accepted: CI is ephemeral, and local development is expected to be on
        # 1.11+. If you run this suite on 1.10, check out that file afterwards.
        dev = if VERSION >= v"1.11"
            ""
        else
            "Pkg.develop(; path=$(repr(tachikoma_dir)), io=devnull)\n"
        end
        code = """
        using Pkg
        $(dev)Pkg.instantiate(; io=devnull)
        using TachikomaDemos
        m = TachikomaDemos.LauncherModel()
        @assert m.quit == false
        @assert m.tree.selected > 0
        @assert length(TachikomaDemos.DEMO_ENTRIES) > 0
        print(length(TachikomaDemos.DEMO_ENTRIES))
        """
        # Base.julia_cmd() rather than a bare `julia`: the branch above is chosen on
        # the TEST process's VERSION, so the subprocess has to be that same binary
        # or the gate is deciding for a Julia that isn't the one doing the work.
        out, err = IOBuffer(), IOBuffer()
        p = run(
            pipeline(`$(Base.julia_cmd()) --project=$demos_dir -e $code`, stdout=out, stderr=err);
            wait=false,
        )
        wait(p)
        p.exitcode == 0 || println("DEMO LOAD STDERR:\n", String(take!(err)))
        @test p.exitcode == 0
        n_demos = tryparse(Int, String(take!(out)))
        @test n_demos !== nothing && n_demos > 0

        # Regression guard: a test run must leave the tracked project untouched.
        # Only meaningful where no develop ran -- the LTS rewrites it by design.
        if VERSION >= v"1.11"
            @test occursin("path = \"../..\"", read(joinpath(demos_dir, "Project.toml"), String))
        end
    end
end
