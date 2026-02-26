using Documenter
using DocumenterVitepress
using Tachikoma

# Copy example assets into VitePress's source-level public/ directory BEFORE
# makedocs so they're available when VitePress builds.  VitePress automatically
# copies .vitepress/public/ to the output root, so /assets/examples/foo.gif
# in public/ becomes accessible at /assets/examples/foo.gif in the built site.
let public_assets = joinpath(@__DIR__, "src", "public", "assets")
    for (subdir, src_dir) in [
        ("examples", joinpath(@__DIR__, "src", "assets", "examples")),
        ("",         joinpath(@__DIR__, "src", "assets")),
    ]
        isdir(src_dir) || continue
        dst_dir = isempty(subdir) ? public_assets : joinpath(public_assets, subdir)
        mkpath(dst_dir)
        for f in readdir(src_dir; join=false)
            src = joinpath(src_dir, f)
            isfile(src) || continue
            endswith(f, ".tach") && continue  # skip .tach, only copy .gif
            endswith(f, ".svg") && continue
            cp(src, joinpath(dst_dir, f); force=true)
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

# Step 3: Build VitePress and deploy
DocumenterVitepress.build_docs(joinpath(@__DIR__, "build"))

deploydocs(;
    repo = "github.com/kahliburke/Tachikoma.jl",
    devbranch = "main",
    push_preview = true,
)
