# ═══════════════════════════════════════════════════════════════════════
# MP4 export via FFMPEG.jl
#
# Renders to a temp GIF first (which supports all options including
# scale and delta encoding), then converts to MP4 with ffmpeg.
# ═══════════════════════════════════════════════════════════════════════

function render_mp4(output::String, w::Int, h::Int,
                    cells, ts, kwargs::Dict{Symbol, Any};
                    fps::Union{Int, Nothing}=nothing)
    tmpdir = mktempdir()
    gif_path = joinpath(tmpdir, "frames.gif")

    try
        # Render GIF (supports scale, delta encoding, etc.)
        Tachikoma.export_gif_from_snapshots(gif_path, w, h, cells, ts; kwargs...)

        actual_fps = if fps !== nothing
            fps
        elseif length(ts) > 1
            round(Int, clamp((length(ts) - 1) / (ts[end] - ts[1]), 1, 60))
        else
            10
        end

        ffmpeg_exe = FFMPEG_jll.ffmpeg()

        # GIF → MP4
        # -c:v libx264: widely compatible
        # -pix_fmt yuv420p: required for most players
        # -crf 18: high quality (visually lossless)
        # -movflags +faststart: web-friendly streaming
        cmd = `$ffmpeg_exe -y -loglevel error
            -i $gif_path
            -c:v libx264 -pix_fmt yuv420p -crf 18
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2"
            -movflags +faststart
            $output`

        run(cmd)
    finally
        rm(tmpdir; recursive=true, force=true)
    end
end
