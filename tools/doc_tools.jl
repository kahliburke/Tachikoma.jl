# ═══════════════════════════════════════════════════════════════════════════════
# Doc build tools — register as BridgeTools for MCP access
#
# Load into a running MCPRepl session:
#   include("tools/doc_tools.jl")
#
# This registers three tools:
#   build_docs_assets  — render example assets (generate_assets.jl)
#   build_docs_make    — run Documenter + VitePress markdown (make.jl)
#   docs_dev_server    — start/stop the VitePress dev server
# ═══════════════════════════════════════════════════════════════════════════════

using MCPRepl.MCPReplBridge: BridgeTool, serve

const _DOCS_ROOT = joinpath(dirname(@__DIR__), "docs")
const _PROJECT_ROOT = dirname(@__DIR__)

# Track the dev server process
const _DEV_SERVER = Ref{Union{Base.Process,Nothing}}(nothing)

"""
    _run_julia_docs(script, args) → String

Run a Julia script in the docs project environment, streaming output
line-by-line via println (which MCPRepl publishes to the TUI) to keep
the connection alive during long builds. Returns the full output.
"""
function _run_julia_docs(script::String, args::Vector{String}=String[])
    cmd = `$(Base.julia_cmd()) --project=$(_DOCS_ROOT) $(joinpath(_DOCS_ROOT, script))`
    if !isempty(args)
        cmd = `$cmd $args`
    end
    lines = String[]
    proc = open(cmd; read=true, write=false)
    try
        for line in eachline(proc)
            push!(lines, line)
            println(line)  # stream to MCPRepl TUI
        end
    catch e
        e isa EOFError || push!(lines, "Error reading output: $(sprint(showerror, e))")
    end
    wait(proc)
    output = join(lines, "\n")
    if proc.exitcode != 0
        output = "FAILED (exit code $(proc.exitcode)):\n$output"
    end
    return output
end

# ── Tool: build_docs_assets ─────────────────────────────────────────────────

"""Build doc assets (examples, hero images). Runs generate_assets.jl.

Steps: snippets, hero, examples, apps, or all (default).
Use force to regenerate everything ignoring cache."""
function build_docs_assets(step::String)
    valid = ["all", "snippets", "hero", "examples", "apps", "force"]
    step = strip(step)
    args = if step == "all" || isempty(step)
        String[]
    elseif step == "force"
        ["--force"]
    elseif step in valid
        ["--$step"]
    else
        return "Invalid step: '$step'. Valid: $(join(valid, ", "))"
    end
    _run_julia_docs("generate_assets.jl", args)
end

# ── Tool: build_docs_make ───────────────────────────────────────────────────

"""Run Documenter + DocumenterVitepress to generate markdown output.

This runs make.jl which processes docstrings, copies assets, and produces
the VitePress-ready markdown in build/.documenter/."""
function build_docs_make()
    _run_julia_docs("make.jl")
end

# ── Tool: docs_dev_server ───────────────────────────────────────────────────

"""Start or stop the VitePress dev server for local docs preview.

Commands: start, stop, status"""
function docs_dev_server(command::String)
    command = strip(lowercase(command))
    if command == "start"
        if _DEV_SERVER[] !== nothing && process_running(_DEV_SERVER[])
            return "Dev server already running (PID $(getpid(_DEV_SERVER[])))"
        end
        npm = Sys.iswindows() ? "npm.cmd" : "npm"
        proc = run(Cmd(`$npm run docs:dev`; dir=_DOCS_ROOT); wait=false)
        _DEV_SERVER[] = proc
        return "VitePress dev server started (PID $(getpid(proc))). View at http://localhost:5173/"
    elseif command == "stop"
        if _DEV_SERVER[] === nothing || !process_running(_DEV_SERVER[])
            _DEV_SERVER[] = nothing
            return "No dev server running."
        end
        kill(_DEV_SERVER[])
        _DEV_SERVER[] = nothing
        return "Dev server stopped."
    elseif command == "status"
        if _DEV_SERVER[] !== nothing && process_running(_DEV_SERVER[])
            return "Dev server running (PID $(getpid(_DEV_SERVER[])))"
        else
            _DEV_SERVER[] = nothing
            return "Dev server not running."
        end
    else
        return "Unknown command: '$command'. Use: start, stop, status"
    end
end

# ── Register ────────────────────────────────────────────────────────────────

const DOC_TOOLS = BridgeTool[
    BridgeTool("build_docs_assets", build_docs_assets),
    BridgeTool("build_docs_make", build_docs_make),
    BridgeTool("docs_dev_server", docs_dev_server),
]

serve(tools=DOC_TOOLS)
