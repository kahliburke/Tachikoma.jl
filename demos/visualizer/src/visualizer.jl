# ═══════════════════════════════════════════════════════════════════════
# Music visualizer ── audio-reactive TUI demo (Sixel pixel rendering)
#
# Plays audio through PortAudio while rendering a real-time spectrum
# analyzer using Sixel graphics. The playback task updates the
# spectrum bins; the Elm render loop composites a pixel buffer each
# frame and sixel-encodes it for smooth, high-resolution display.
#
# Supports WAV natively; other formats (MP3, FLAC, OGG, M4A, etc.)
# are auto-converted via ffmpeg.
# ═══════════════════════════════════════════════════════════════════════

# Preset steps for adjustable FFT parameters
const WINDOW_SIZES    = (512, 1024, 2048, 4096, 8192)
const BAND_COUNTS     = (16, 24, 32, 48, 64, 96, 128)
const OVERSAMPLE_STEPS = (1, 2, 4, 8)

# ── Audio loading ────────────────────────────────────────────────────

function load_audio(filepath::AbstractString)
    ext = lowercase(splitext(filepath)[2])
    if ext == ".wav"
        return wavread(filepath)
    end
    # Convert anything else via ffmpeg
    Sys.which("ffmpeg") !== nothing ||
        error("ffmpeg not found. Install it to load $ext files, " *
              "or convert manually: ffmpeg -i input$ext output.wav")
    tmpfile = tempname() * ".wav"
    try
        run(pipeline(`ffmpeg -y -i $filepath -f wav -acodec pcm_s16le
                      -ar 44100 $tmpfile`, devnull, devnull))
        samples, sr = wavread(tmpfile)
        return samples, sr
    finally
        isfile(tmpfile) && rm(tmpfile)
    end
end

# ── Color utilities ──────────────────────────────────────────────────

function c256_rgb(code::UInt8)
    c = Int(code)
    if c < 16
        tbl = ((0,0,0),(128,0,0),(0,128,0),(128,128,0),
               (0,0,128),(128,0,128),(0,128,128),(192,192,192),
               (128,128,128),(255,0,0),(0,255,0),(255,255,0),
               (0,0,255),(255,0,255),(0,255,255),(255,255,255))
        r, g, b = tbl[c + 1]
        return RGB{N0f8}(r / 255, g / 255, b / 255)
    elseif c < 232
        i = c - 16
        return RGB{N0f8}((i ÷ 36) / 5, ((i ÷ 6) % 6) / 5,
                         (i % 6) / 5)
    else
        v = ((c - 232) * 10 + 8) / 255
        return RGB{N0f8}(v, v, v)
    end
end
c256_rgb(c::Color256) = c256_rgb(c.code)

@inline function lerp_rgb(a::RGB{N0f8}, b::RGB{N0f8}, t::Float64)
    s = 1.0 - t
    RGB{N0f8}(
        clamp(Float64(red(a)) * s + Float64(red(b)) * t, 0, 1),
        clamp(Float64(green(a)) * s + Float64(green(b)) * t, 0, 1),
        clamp(Float64(blue(a)) * s + Float64(blue(b)) * t, 0, 1))
end

@inline function scale_rgb(c::RGB{N0f8}, s::Float64)
    RGB{N0f8}(
        clamp(Float64(red(c)) * s, 0, 1),
        clamp(Float64(green(c)) * s, 0, 1),
        clamp(Float64(blue(c)) * s, 0, 1))
end

@inline function additive_rgb(a::RGB{N0f8}, b::RGB{N0f8})
    RGB{N0f8}(
        clamp(Float64(red(a)) + Float64(red(b)), 0, 1),
        clamp(Float64(green(a)) + Float64(green(b)), 0, 1),
        clamp(Float64(blue(a)) + Float64(blue(b)), 0, 1))
end

# ── Pixel palette (cached RGB from theme) ────────────────────────────

struct VisPalette
    bg::RGB{N0f8}
    primary::RGB{N0f8}
    secondary::RGB{N0f8}
    accent::RGB{N0f8}
    warning::RGB{N0f8}
    error_c::RGB{N0f8}
    border::RGB{N0f8}
    success::RGB{N0f8}
end

function VisPalette(th::Theme)
    VisPalette(
        RGB{N0f8}(0.03, 0.03, 0.05),
        c256_rgb(th.primary), c256_rgb(th.secondary),
        c256_rgb(th.accent), c256_rgb(th.warning),
        c256_rgb(th.error), c256_rgb(th.border),
        c256_rgb(th.success))
end

# ── Model ────────────────────────────────────────────────────────────

@kwdef mutable struct VisualizerModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Audio
    samples::Matrix{Float64} = zeros(0, 0)
    samplerate::Int = 44100
    nchannels::Int = 2
    position::Threads.Atomic{Int} = Threads.Atomic{Int}(1)
    playing::Bool = false
    paused::Bool = false
    # FFT parameters (adjustable at runtime)
    chunk_size::Int = 2048
    num_bands::Int = 48
    oversample::Int = 4  # overlap factor: hop = chunk_size ÷ oversample
    # Spectrum (written by audio task, read by render)
    spectrum::Vector{Float64} = zeros(48)
    peaks::Vector{Float64} = zeros(48)
    peak_decay::Float64 = 0.97
    sensitivity::Float64 = 1.0
    # Waveform (last chunk for scope display)
    waveform::Vector{Float64} = Float64[]
    # Spectrogram history
    spec_history::Vector{Vector{Float64}} = Vector{Float64}[]
    max_history::Int = 800
    # Display mode
    mode::Int = 1  # 1=bars, 2=bars+scope, 3=bars+spectrogram
    # Audio task
    play_task::Union{Task, Nothing} = nothing
    stream::Any = nothing
    # Window function (cached, recomputed on chunk_size change)
    hanning::Vector{Float64} = Float64[]
    # File info
    filename::String = ""
    duration_s::Float64 = 0.0
    # Pixel rendering
    pixel_buf::Matrix{RGB{N0f8}} = Matrix{RGB{N0f8}}(undef, 0, 0)
    palette::VisPalette = VisPalette(KOKAKU)
    last_theme::String = ""
end

should_quit(m::VisualizerModel) = m.quit

function recompute_fft_state!(m::VisualizerModel)
    m.hanning = Windows.hanning(m.chunk_size)
    m.spectrum = zeros(m.num_bands)
    m.peaks = zeros(m.num_bands)
    empty!(m.spec_history)
end

function init!(m::VisualizerModel, ::Terminal)
    recompute_fft_state!(m)
    m.palette = VisPalette(theme())
    m.last_theme = theme().name
    start_playback!(m)
end

function cleanup!(m::VisualizerModel)
    m.playing = false
    m.paused = false
    s = m.stream
    s !== nothing && try close(s) catch end
    m.stream = nothing
end

# ── Audio playback ───────────────────────────────────────────────────

function start_playback!(m::VisualizerModel)
    m.playing = true
    m.paused = false
    m.play_task = @async begin
        try
            nch = min(m.nchannels, 2)
            stream = PortAudioStream(0, nch;
                samplerate=Float64(m.samplerate))
            m.stream = stream
            total = size(m.samples, 1)
            while m.playing && m.position[] <= total
                if m.paused
                    sleep(0.05)
                    continue
                end
                pos = m.position[]
                csz = m.chunk_size
                hop = max(64, csz ÷ m.oversample)
                play_end = min(pos + hop - 1, total)

                # Analyze with full FFT window (look backward)
                win_start = max(1, play_end - csz + 1)
                analyze_chunk!(m,
                    m.samples[win_start:play_end, 1])

                # Play only the hop-sized chunk
                chunk = m.samples[pos:play_end, 1:nch]
                write(stream, chunk)
                Threads.atomic_add!(m.position,
                    play_end - pos + 1)
            end
            close(stream)
            m.stream = nothing
            m.playing = false
        catch e
            m.playing = false
            m.stream = nothing
        end
    end
end

# ── Audio analysis ───────────────────────────────────────────────────

function analyze_chunk!(m::VisualizerModel, chunk::Vector{Float64})
    n = length(chunk)
    n < 64 && return

    m.waveform = chunk
    csz = m.chunk_size

    # Windowed FFT
    padded = if n < csz
        vcat(chunk, zeros(csz - n))
    else
        chunk[1:csz]
    end
    windowed = padded .* m.hanning
    fft_out = rfft(windowed)
    mags = abs.(fft_out)

    # Logarithmic frequency binning
    nbins = length(mags)
    nb = m.num_bands
    bands = zeros(nb)
    for i in 1:nb
        lo_f = (i - 1) / nb
        hi_f = i / nb
        lo = max(1, round(Int, nbins^lo_f))
        hi = max(lo, round(Int, nbins^hi_f))
        hi = min(hi, nbins)
        bands[i] = maximum(@view mags[lo:hi])
    end

    # Normalize with sensitivity
    peak = maximum(bands)
    if peak > 0
        bands .*= (m.sensitivity / peak)
        clamp!(bands, 0.0, 1.5)
    end

    # Exponential smoothing
    α = 0.35
    for i in eachindex(m.spectrum)
        m.spectrum[i] = α * bands[i] + (1 - α) * m.spectrum[i]
    end

    # Peak hold with decay
    for i in eachindex(m.peaks)
        if m.spectrum[i] > m.peaks[i]
            m.peaks[i] = m.spectrum[i]
        else
            m.peaks[i] *= m.peak_decay
        end
    end

    # Spectrogram history
    push!(m.spec_history, copy(m.spectrum))
    length(m.spec_history) > m.max_history &&
        popfirst!(m.spec_history)
end

# ── Key handling ─────────────────────────────────────────────────────

function cycle_up(val, options)
    idx = findfirst(==(val), options)
    idx === nothing && return first(options)
    idx >= length(options) ? options[end] : options[idx + 1]
end

function cycle_down(val, options)
    idx = findfirst(==(val), options)
    idx === nothing && return first(options)
    idx <= 1 ? options[1] : options[idx - 1]
end

function update!(m::VisualizerModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == ' ' && (m.paused = !m.paused)
        # Gain
        evt.char == '+' && (m.sensitivity = min(5.0,
            m.sensitivity * 1.3))
        evt.char == '=' && (m.sensitivity = min(5.0,
            m.sensitivity * 1.3))
        evt.char == '-' && (m.sensitivity = max(0.2,
            m.sensitivity / 1.3))
        # Display mode
        evt.char == '1' && (m.mode = 1)
        evt.char == '2' && (m.mode = 2)
        evt.char == '3' && (m.mode = 3)
        # Theme
        evt.char == 'k' && set_theme!(KOKAKU)
        evt.char == 'e' && set_theme!(ESPER)
        # Bands: [ decrease, ] increase
        if evt.char == '['
            m.num_bands = cycle_down(m.num_bands, BAND_COUNTS)
            recompute_fft_state!(m)
        elseif evt.char == ']'
            m.num_bands = cycle_up(m.num_bands, BAND_COUNTS)
            recompute_fft_state!(m)
        end
        # FFT window: , decrease, . increase
        if evt.char == ','
            m.chunk_size = cycle_down(m.chunk_size, WINDOW_SIZES)
            recompute_fft_state!(m)
        elseif evt.char == '.'
            m.chunk_size = cycle_up(m.chunk_size, WINDOW_SIZES)
            recompute_fft_state!(m)
        end
        # Oversample: o decrease, O increase
        if evt.char == 'o'
            m.oversample = cycle_down(m.oversample,
                OVERSAMPLE_STEPS)
        elseif evt.char == 'O'
            m.oversample = cycle_up(m.oversample,
                OVERSAMPLE_STEPS)
        end
    elseif evt.key == :right
        skip = 5 * m.samplerate
        new_pos = min(m.position[] + skip, size(m.samples, 1))
        Threads.atomic_xchg!(m.position, new_pos)
    elseif evt.key == :left
        skip = 5 * m.samplerate
        new_pos = max(1, m.position[] - skip)
        Threads.atomic_xchg!(m.position, new_pos)
    end
    evt.key == :escape && (m.quit = true)
end

# ── Pixel rendering ─────────────────────────────────────────────────

function draw_bars_px!(img::AbstractMatrix{RGB{N0f8}},
                       spectrum::Vector{Float64},
                       peaks::Vector{Float64},
                       pal::VisPalette)
    h, w = size(img)
    n = length(spectrum)
    (n == 0 || h < 1 || w < 1) && return

    # Bar geometry
    gap_px = max(1, w ÷ (n * 4))
    bar_w = max(1, (w - gap_px * (n - 1)) ÷ n)
    total_used = bar_w * n + gap_px * (n - 1)
    x_off = (w - total_used) ÷ 2

    for i in 1:n
        val = clamp(spectrum[i] / 1.5, 0.0, 1.0)
        bar_h = round(Int, val * h * 0.88)
        peak_h = round(Int, clamp(peaks[i] / 1.5, 0.0, 1.0) *
                        h * 0.88)
        bx = x_off + (i - 1) * (bar_w + gap_px) + 1

        # ── Bar fill with gradient ──
        for rfb in 1:bar_h
            y = h - rfb + 1
            (y < 1 || y > h) && continue
            frac = rfb / h

            color = if frac > 0.82
                lerp_rgb(pal.warning, pal.error_c,
                         (frac - 0.82) / 0.18)
            elseif frac > 0.50
                lerp_rgb(pal.primary, pal.warning,
                         (frac - 0.50) / 0.32)
            else
                lerp_rgb(scale_rgb(pal.primary, 0.35),
                         pal.primary, frac / 0.50)
            end

            for dx in 0:bar_w - 1
                x = bx + dx
                (x < 1 || x > w) && continue
                c = if dx == 0 || dx == bar_w - 1
                    scale_rgb(color, 0.6)
                elseif dx == 1
                    scale_rgb(color, 1.2)
                else
                    color
                end
                img[y, x] = c
            end
        end

        # ── Peak marker with glow ──
        if peak_h > bar_h && peak_h > 0
            py = h - peak_h + 1
            for dy in -1:1
                gy = py + dy
                (gy < 1 || gy > h) && continue
                intensity = dy == 0 ? 1.0 : 0.25
                c = scale_rgb(pal.accent, intensity)
                for dx in 0:bar_w - 1
                    x = bx + dx
                    (x < 1 || x > w) && continue
                    img[gy, x] = c
                end
            end
        end

        # ── Top glow ──
        if bar_h > 4
            top_y = h - bar_h + 1
            for dy in -2:-1
                gy = top_y + dy
                (gy < 1 || gy > h) && continue
                fade = 0.15 + 0.1 * (dy + 3)
                glow_c = scale_rgb(pal.primary, fade)
                for dx in 0:bar_w - 1
                    x = bx + dx
                    (x < 1 || x > w) && continue
                    img[gy, x] = additive_rgb(img[gy, x], glow_c)
                end
            end
        end
    end
end

function draw_scope_px!(img::AbstractMatrix{RGB{N0f8}},
                        waveform::Vector{Float64},
                        pal::VisPalette)
    h, w = size(img)
    n = length(waveform)
    (n == 0 || h < 2 || w < 2) && return

    center = h ÷ 2

    for x in 1:w
        img[1, x] = scale_rgb(pal.border, 0.4)
    end
    if 1 <= center <= h
        for x in 1:w
            img[center, x] = scale_rgb(pal.border, 0.2)
        end
    end

    prev_y = center
    for col in 1:w
        idx = clamp(round(Int, (col - 1) / w * n) + 1, 1, n)
        val = waveform[idx]
        offset = round(Int, val * (h ÷ 2) * 0.85)
        y = clamp(center - offset, 2, h)

        for dy in -1:1, dx in -1:1
            py, px = y + dy, col + dx
            (1 <= py <= h && 1 <= px <= w) || continue
            dist = abs(dy) + abs(dx)
            intensity = dist == 0 ? 1.0 : dist == 1 ? 0.5 : 0.2
            img[py, px] = scale_rgb(pal.accent, intensity)
        end

        if col > 1 && abs(y - prev_y) > 1
            dir = y > prev_y ? 1 : -1
            for s in 1:abs(y - prev_y) - 1
                ly = prev_y + dir * s
                (1 <= ly <= h) || continue
                img[ly, col] = scale_rgb(pal.accent, 0.5)
            end
        end
        prev_y = y
    end
end

function spec_heatmap(val::Float64, pal::VisPalette)
    val <= 0.04 && return pal.bg
    val > 0.80 && return lerp_rgb(pal.warning, pal.error_c,
                                   (val - 0.80) / 0.20)
    val > 0.50 && return lerp_rgb(pal.primary, pal.warning,
                                   (val - 0.50) / 0.30)
    val > 0.20 && return lerp_rgb(pal.secondary, pal.primary,
                                   (val - 0.20) / 0.30)
    return lerp_rgb(pal.bg, pal.secondary,
                    (val - 0.04) / 0.16)
end

function draw_spectrogram_px!(img::AbstractMatrix{RGB{N0f8}},
                              history::Vector{Vector{Float64}},
                              pal::VisPalette)
    isempty(history) && return
    h, w = size(img)
    (h < 2 || w < 1) && return

    n_bands = length(history[1])
    n_slices = length(history)

    for x in 1:w
        img[1, x] = scale_rgb(pal.border, 0.4)
    end

    usable_h = h - 1

    for px_col in 1:w
        tf = (px_col - 1) / max(1, w - 1) * (n_slices - 1)
        idx_lo = clamp(floor(Int, tf) + 1, 1, n_slices)
        idx_hi = clamp(idx_lo + 1, 1, n_slices)
        ft = tf - (idx_lo - 1)

        slice_lo = history[idx_lo]
        slice_hi = history[idx_hi]

        for py in 0:usable_h - 1
            y = h - py
            (y < 2 || y > h) && continue

            band_f = py / usable_h * (n_bands - 1)
            band_lo = clamp(floor(Int, band_f) + 1, 1, n_bands)
            band_hi = clamp(band_lo + 1, 1, n_bands)
            bt = band_f - (band_lo - 1)

            v00 = slice_lo[band_lo] / 1.5
            v01 = slice_lo[band_hi] / 1.5
            v10 = slice_hi[band_lo] / 1.5
            v11 = slice_hi[band_hi] / 1.5
            val = clamp(
                (v00 * (1 - ft) + v10 * ft) * (1 - bt) +
                (v01 * (1 - ft) + v11 * ft) * bt,
                0.0, 1.0)

            val <= 0.04 && continue
            img[y, px_col] = spec_heatmap(val, pal)
        end
    end
end

# ── Main render ──────────────────────────────────────────────────────

function view(m::VisualizerModel, f::Frame)
    m.tick += 1
    th = theme()
    buf = f.buffer

    if th.name != m.last_theme
        m.palette = VisPalette(th)
        m.last_theme = th.name
    end

    block = Block(
        title="$(m.filename)",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    content = render(block, f.area, buf)
    x0 = content.x
    status_y = bottom(content)

    vis_area = Rect(x0, content.y, content.width,
                    max(1, content.height - 1))

    cpx = cell_pixels()
    pw = vis_area.width * cpx.w
    ph = vis_area.height * cpx.h
    if pw > 0 && ph > 0
        if size(m.pixel_buf) != (ph, pw)
            m.pixel_buf = fill(m.palette.bg, ph, pw)
        else
            fill!(m.pixel_buf, m.palette.bg)
        end

        pal = m.palette
        if m.mode == 1
            draw_bars_px!(m.pixel_buf, m.spectrum, m.peaks, pal)
        elseif m.mode == 2
            h_split = (ph * 2) ÷ 3
            draw_bars_px!(
                @view(m.pixel_buf[1:h_split, :]),
                m.spectrum, m.peaks, pal)
            draw_scope_px!(
                @view(m.pixel_buf[h_split+1:end, :]),
                m.waveform, pal)
        elseif m.mode == 3
            h_split = (ph * 2) ÷ 3
            draw_bars_px!(
                @view(m.pixel_buf[1:h_split, :]),
                m.spectrum, m.peaks, pal)
            draw_spectrogram_px!(
                @view(m.pixel_buf[h_split+1:end, :]),
                m.spec_history, pal)
        end

        render_sixel!(f, m.pixel_buf, vis_area)
    end

    # ── Status bar ──
    if status_y <= bottom(f.area)
        pos_s = round(Int, m.position[] / m.samplerate)
        dur_s = round(Int, m.duration_s)
        pm, ps = divrem(pos_s, 60)
        dm, ds = divrem(dur_s, 60)
        time_str = string(pm, ":", lpad(ps, 2, '0'),
                          " / ", dm, ":", lpad(ds, 2, '0'))
        state = m.paused ? "paused" :
                m.playing ? "playing" : "stopped"

        cx = set_string!(buf, x0, status_y, state,
                    tstyle(m.paused ? :warning : :success))
        cx = set_string!(buf, cx + 1, status_y, time_str,
                    tstyle(:text_dim))
        hop = max(64, m.chunk_size ÷ m.oversample)
        update_hz = round(Int, m.samplerate / hop)
        fft_str = string(m.num_bands, "b ",
                         m.chunk_size, "w ",
                         m.oversample, "x ",
                         update_hz, "Hz ",
                         "g=",
                         round(m.sensitivity; digits=1))
        cx = set_string!(buf, cx + 1, status_y, fft_str,
                    tstyle(:text_dim))

        inst = " [1-3]mode [+-]gain [[]]]bands" *
               " [,.]fft [oO]oversample [space]pause"
        ix = right(content) - length(inst)
        if ix > cx + 2
            set_string!(buf, ix, status_y, inst,
                        tstyle(:text_dim, dim=true))
        end
    end
end

# ── Entry point ──────────────────────────────────────────────────────

"""
    visualizer(filepath; theme_name=:kokaku, num_bands=48, chunk_size=2048)

Play an audio file with a real-time Sixel spectrum analyzer TUI.
Supports WAV natively; MP3/FLAC/OGG/M4A via ffmpeg.

Modes: [1] bars  [2] bars+scope  [3] bars+spectrogram
Controls:
  [+-]    gain          [←→]   seek 5s
  [\\[\\]]   bands ($(join(BAND_COUNTS, "/")))
  [,.]    FFT window ($(join(WINDOW_SIZES, "/")))
  [space] pause         [k/e]  theme
"""
function visualizer(filepath::AbstractString;
                    theme_name=:kokaku, num_bands=48,
                    chunk_size=2048, oversample=4)
    isfile(filepath) ||
        error("File not found: $filepath")

    samples, sr = load_audio(filepath)
    set_theme!(theme_name)

    m = VisualizerModel(
        samples=samples,
        samplerate=round(Int, sr),
        nchannels=size(samples, 2),
        num_bands=num_bands,
        chunk_size=chunk_size,
        oversample=oversample,
        filename=basename(filepath),
        duration_s=size(samples, 1) / sr,
    )
    app(m; fps=60)
end
