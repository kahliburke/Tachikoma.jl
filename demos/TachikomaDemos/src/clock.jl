# ═══════════════════════════════════════════════════════════════════════
# Clock ── real-time clock with BigText, date, and stopwatch
#
# Shows current time in large block digits, date below,
# optional stopwatch mode. Calendar in the corner.
# ═══════════════════════════════════════════════════════════════════════

@kwdef mutable struct ClockModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Stopwatch
    stopwatch_running::Bool = false
    stopwatch_ms::Int = 0
    stopwatch_start::Float64 = 0.0
    # Blink
    blink::Bool = true
end

should_quit(m::ClockModel) = m.quit

function update!(m::ClockModel, evt::KeyEvent)
    if evt.key == :char
        evt.char == 'q' && (m.quit = true)
        evt.char == 's' && toggle_stopwatch!(m)
        evt.char == 'r' && reset_stopwatch!(m)
    end
    evt.key == :escape && (m.quit = true)
end

function toggle_stopwatch!(m::ClockModel)
    if m.stopwatch_running
        m.stopwatch_ms += round(Int, (time() - m.stopwatch_start) * 1000)
        m.stopwatch_running = false
    else
        m.stopwatch_start = time()
        m.stopwatch_running = true
    end
end

function reset_stopwatch!(m::ClockModel)
    m.stopwatch_ms = 0
    m.stopwatch_running && (m.stopwatch_start = time())
end

function stopwatch_elapsed(m::ClockModel)
    ms = m.stopwatch_ms
    m.stopwatch_running && (ms += round(Int, (time() - m.stopwatch_start) * 1000))
    ms
end

function format_stopwatch(ms::Int)
    s = ms ÷ 1000
    mins = s ÷ 60
    secs = s % 60
    centis = (ms % 1000) ÷ 10
    string(lpad(mins, 2, '0'), ":", lpad(secs, 2, '0'), ".", lpad(centis, 2, '0'))
end

function view(m::ClockModel, f::Frame)
    m.tick += 1
    m.blink = mod(m.tick, 30) < 15  # half-second blink
    buf = f.buffer

    # Layout
    rows = split_layout(Layout(Vertical,
        [Fixed(2), Fixed(5), Fixed(2), Fixed(5), Fixed(2), Fill(), Fixed(1)]),
        f.area)
    length(rows) < 7 && return

    header_area = rows[1]
    time_area = rows[2]
    date_area = rows[3]
    sw_area = rows[4]
    label_area = rows[5]
    bottom_area = rows[6]
    status_area = rows[7]

    # ── Header ──
    si = mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))
    set_char!(buf, header_area.x + 1, header_area.y,
              SPINNER_BRAILLE[si], tstyle(:accent))
    set_string!(buf, header_area.x + 3, header_area.y,
                "tachikoma clock", tstyle(:title, bold=true))

    # ── Big clock ──
    now = Dates.now()
    h = lpad(Dates.hour(now), 2, '0')
    mi = lpad(Dates.minute(now), 2, '0')
    s = lpad(Dates.second(now), 2, '0')
    colon = m.blink ? ":" : " "
    time_str = h * colon * mi * colon * s

    tw = intrinsic_size(BigText(time_str))[1]
    tx = time_area.x + max(0, (time_area.width - tw) ÷ 2)
    render(BigText(time_str; style=tstyle(:primary, bold=true)),
           Rect(tx, time_area.y, time_area.width, 5), buf)

    # ── Date ──
    date_str = Dates.format(now, "E, d U yyyy")
    dx = date_area.x + max(0, (date_area.width - length(date_str)) ÷ 2)
    set_string!(buf, dx, date_area.y, date_str, tstyle(:text_dim))

    # ── Stopwatch ──
    elapsed = stopwatch_elapsed(m)
    sw_str = format_stopwatch(elapsed)
    sww = intrinsic_size(BigText(sw_str))[1]
    swx = sw_area.x + max(0, (sw_area.width - sww) ÷ 2)
    sw_style = if m.stopwatch_running
        tstyle(:accent)
    elseif elapsed > 0
        tstyle(:warning)
    else
        tstyle(:text_dim, dim=true)
    end
    render(BigText(sw_str; style=sw_style),
           Rect(swx, sw_area.y, sw_area.width, 5), buf)

    sw_label = m.stopwatch_running ? "STOPWATCH (running)" : "STOPWATCH"
    slx = label_area.x + max(0, (label_area.width - length(sw_label)) ÷ 2)
    set_string!(buf, slx, label_area.y, sw_label, tstyle(:text_dim))

    # ── Calendar in bottom area ──
    if bottom_area.height >= 8 && bottom_area.width >= 24
        cols = split_layout(Layout(Horizontal,
            [Fill(), Fixed(24), Fill()]), bottom_area)
        if length(cols) >= 2
            render(Calendar(), cols[2], buf)
        end
    end

    # ── Status bar ──
    render(StatusBar(
        left=[Span("  [s]stopwatch [r]reset ", tstyle(:text_dim))],
        right=[Span("[k/e/m/a/n/c]theme [q]quit ", tstyle(:text_dim))],
    ), status_area, buf)
end

function clock(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(ClockModel(); fps=30)
end
