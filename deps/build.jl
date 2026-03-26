using Pkg

tachi_dir = joinpath(@__DIR__, "..", "tools", "tachi")
if isdir(tachi_dir)
    try
        Pkg.Apps.develop(path=tachi_dir)
        @info "Installed tachi CLI to ~/.julia/bin/tachi"
    catch e
        @warn "Could not install tachi CLI (requires Julia 1.12+)" exception=(e, catch_backtrace())
    end
end
