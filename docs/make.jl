using Documenter
using DocumenterVitepress
using Tachikoma

# Copy local assets into VitePress public/ so they're available during build.
# In CI, these are served from the docs-assets GitHub release instead.
let public_dir = joinpath(@__DIR__, "src", ".vitepress", "public", "assets")
    src_assets = joinpath(@__DIR__, "src", "assets")
    if isdir(src_assets)
        mkpath(public_dir)
        for (root, dirs, files) in walkdir(src_assets)
            for f in files
                endswith(f, ".gif") || continue
                rel = relpath(joinpath(root, f), src_assets)
                dest = joinpath(public_dir, rel)
                mkpath(dirname(dest))
                cp(joinpath(root, f), dest; force=true)
            end
        end
    end
end

# Clean stale build directory to avoid ENOTEMPTY errors from Documenter
# Retry loop handles macOS .DS_Store race condition
let build_dir = joinpath(@__DIR__, "build")
    for attempt in 1:3
        isdir(build_dir) || break
        try
            rm(build_dir; recursive=true, force=true)
        catch
            attempt == 3 && rethrow()
            sleep(0.5)
        end
    end
end

# Step 1: Generate markdown only (skip VitePress build)
makedocs(;
    sitename = "Tachikoma.jl",
    modules = [Tachikoma],
    remotes = nothing,
    format = DocumenterVitepress.MarkdownVitepress(;
        repo = "https://github.com/kahliburke/Tachikoma.jl",
        devurl = "dev",
        deploy_url = "kahliburke.github.io/Tachikoma.jl",
        build_vitepress = false,
    ),
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Getting Started" => "getting-started.md",
        "Guide" => [
            "Architecture" => "architecture.md",
            "Layout" => "layout.md",
            "Styling & Themes" => "styling.md",
            "Input & Events" => "events.md",
            "Pattern Matching" => "match.md",
            "Animation" => "animation.md",
            "Graphics & Pixel Rendering" => "canvas.md",
            "Widgets" => "widgets.md",
            "Async Tasks" => "async.md",
            "Recording & Export" => "recording.md",
            "Scripting Interactions" => "scripting.md",
            "Backgrounds" => "backgrounds.md",
            "Performance" => "performance.md",
            "Testing" => "testing.md",
            "Preferences" => "preferences.md",
        ],
        "Tutorials" => [
            "Game of Life" => "tutorials/game-of-life.md",
            "Build a Form" => "tutorials/form-app.md",
            "Build a Dashboard" => "tutorials/dashboard.md",
            "Animation Showcase" => "tutorials/animation-showcase.md",
            "Constraint Explorer" => "tutorials/constraint-explorer.md",
            "Todo List" => "tutorials/todo-list.md",
            "GitHub PRs Viewer" => "tutorials/github-prs.md",
        ],
        "Demos" => "demos.md",
        "Comparison" => "comparison.md",
        "API Reference" => "api.md",
    ],
    warnonly = [:missing_docs, :docs_block, :cross_references],
)

# Step 2: Fix &amp; in markdown headings before VitePress builds.
# Documenter HTML-escapes & to &amp; but VitePress renders that literally.
let documenter_out = joinpath(@__DIR__, "build", ".documenter")
    for (root, dirs, files) in walkdir(documenter_out)
        for f in files
            endswith(f, ".md") || continue
            path = joinpath(root, f)
            content = read(path, String)
            fixed = replace(content, r"^(#{1,6}\s.*)&amp;(.*)"m => s"\1&\2")
            fixed != content && write(path, fixed)
        end
    end
end

# Step 3: Patch VitePress base path to include deploy subfolder (e.g. /Tachikoma.jl/dev/)
# When build_vitepress=false, DocumenterVitepress skips its config patching,
# so we must set the correct base ourselves before building.
let config_path = joinpath(@__DIR__, "build", ".documenter", ".vitepress", "config.mts")
    deploy_decision = Documenter.deploy_folder(
        Documenter.auto_detect_deploy_system();
        repo = "github.com/kahliburke/Tachikoma.jl",
        devbranch = "main",
        devurl = "dev",
        push_preview = true,
    )
    folder = deploy_decision.subfolder
    base = "/Tachikoma.jl/$(folder)$(isempty(folder) ? "" : "/")"
    config = read(config_path, String)
    config = replace(config, r"const BASE = '[^']*'" => "const BASE = '$(base)'")
    write(config_path, config)
end

# Step 4: Build VitePress and deploy
DocumenterVitepress.build_docs(joinpath(@__DIR__, "build"))

deploydocs(;
    repo = "github.com/kahliburke/Tachikoma.jl",
    target = "build/.documenter/.vitepress/dist",
    devbranch = "main",
    push_preview = true,
)
