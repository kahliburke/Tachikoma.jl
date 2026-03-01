# ═══════════════════════════════════════════════════════════════════════
# Markdown extension stubs ── activated by TachikomaMarkdownExt
#
# The actual implementation lives in ext/TachikomaMarkdownExt.jl and
# is loaded automatically when CommonMark.jl is available.
# ═══════════════════════════════════════════════════════════════════════

"""
    markdown_to_spans(md::AbstractString, width::Int; kwargs...) → Vector{Vector{Span}}

Parse Markdown text and return styled Span lines suitable for `ScrollPane`.
Requires the CommonMark.jl extension — call `enable_markdown()` first.
"""
function markdown_to_spans end

const _COMMONMARK_UUID = Base.UUID("a80b9123-70ca-4bc0-993e-6e3bcb318db6")

"""
    markdown_extension_loaded() → Bool

Return `true` if the CommonMark.jl extension has been loaded.
"""
function markdown_extension_loaded()
    hasmethod(markdown_to_spans, Tuple{AbstractString, Int};
              world=Base.get_world_counter())
end

"""
    enable_markdown()

Ensure the CommonMark.jl extension is loaded. If `CommonMark` is installed
but not yet imported, this triggers its loading so `TachikomaMarkdownExt`
activates. Errors with an install hint if the package is missing.
"""
function enable_markdown()
    markdown_extension_loaded() && return nothing
    if !_pkg_available("CommonMark", _COMMONMARK_UUID)
        error("Markdown rendering requires CommonMark.jl.\n  Install with: using Pkg; Pkg.add(\"CommonMark\")")
    end
    Base.require(Main, :CommonMark)
    markdown_extension_loaded() ||
        @warn "TachikomaMarkdownExt did not activate — possible version incompatibility."
    nothing
end
