# ═══════════════════════════════════════════════════════════════════════════════
# Input Tester TUI — displays all keyboard/mouse events in real time
# ═══════════════════════════════════════════════════════════════════════════════

const MAX_HISTORY = 200

struct EventRecord
    count::Int
    event::Tachikoma.Event
    summary::String
end

@kwdef mutable struct InputTesterModel <: Tachikoma.Model
    quit::Bool = false
    tick::Int = 0
    events::Vector{EventRecord} = EventRecord[]
    count::Int = 0
    scroll::Int = 0
    kitty::Bool = false
    terminal_size::Tuple{Int,Int} = (0, 0)
end

Tachikoma.should_quit(m::InputTesterModel) = m.quit
Tachikoma.handle_all_key_actions(::InputTesterModel) = true

function Tachikoma.init!(m::InputTesterModel, t::Tachikoma.Terminal)
    m.kitty = t.kitty_keyboard
    m.terminal_size = (t.size.width, t.size.height)
end

# ── Event summarization ──────────────────────────────────────────────────────

function summarize_event(evt::Tachikoma.KeyEvent)
    parts = String[]
    push!(parts, "KEY")
    if evt.key == :char
        c = evt.char
        if c == ' '
            push!(parts, "<space>")
        elseif isprint(c)
            push!(parts, "'$(c)'")
        else
            push!(parts, "0x$(string(Int(c), base=16, pad=2))")
        end
    elseif evt.key == :ctrl
        push!(parts, "ctrl+$(evt.char)")
    else
        push!(parts, string(evt.key))
    end
    push!(parts, string(evt.action))
    join(parts, "  ")
end

function summarize_event(evt::Tachikoma.MouseEvent)
    "MOUSE  $(evt.button) $(evt.action)  ($(evt.x),$(evt.y))" *
    (evt.shift ? " +shift" : "") *
    (evt.alt ? " +alt" : "") *
    (evt.ctrl ? " +ctrl" : "")
end

summarize_event(evt) = "EVENT  " * repr(evt)

# ── Update ───────────────────────────────────────────────────────────────────

function Tachikoma.update!(m::InputTesterModel, evt::Tachikoma.Event)
    m.count += 1
    summary = summarize_event(evt)
    push!(m.events, EventRecord(m.count, evt, summary))
    while length(m.events) > MAX_HISTORY
        popfirst!(m.events)
    end
    # Auto-scroll to bottom
    m.scroll = max(0, length(m.events))
    # Scroll controls
    if evt isa Tachikoma.KeyEvent
        if evt.key == :pageup
            m.scroll = max(0, m.scroll - 10)
        elseif evt.key == :pagedown
            m.scroll += 10
        end
    end
end

# ── View ─────────────────────────────────────────────────────────────────────

function Tachikoma.view(m::InputTesterModel, f::Tachikoma.Frame)
    m.tick += 1
    buf = f.buffer

    inner = Tachikoma.render(Tachikoma.Block(title="Input Tester",
        border_style=Tachikoma.tstyle(:border)), f.area, buf)

    rows = Tachikoma.split_layout(Tachikoma.Layout(Tachikoma.Vertical,
        [Tachikoma.Fixed(3), Tachikoma.Fixed(1), Tachikoma.Fill(), Tachikoma.Fixed(1)]), inner)
    length(rows) < 4 && return

    header_area, sep_area, log_area, footer_area = rows[1], rows[2], rows[3], rows[4]

    _render_header(buf, header_area, m)
    Tachikoma.render(Tachikoma.Separator(), sep_area, buf)
    _render_log(buf, log_area, m)
    _render_footer(buf, footer_area, m)
end

function _render_header(buf, area, m::InputTesterModel)
    cols = Tachikoma.split_layout(Tachikoma.Layout(Tachikoma.Horizontal,
        [Tachikoma.Percent(35), Tachikoma.Fill()]), area)
    length(cols) < 2 && return
    left, right = cols[1], cols[2]

    # Protocol status
    kitty_label = m.kitty ? "Kitty ON" : "Kitty OFF"
    kitty_style = m.kitty ? Tachikoma.tstyle(:success, bold=true) : Tachikoma.tstyle(:warning)
    Tachikoma.set_string!(buf, left.x, left.y, "Protocol: ", Tachikoma.tstyle(:text_dim))
    Tachikoma.set_string!(buf, left.x + 10, left.y, kitty_label, kitty_style)
    Tachikoma.set_string!(buf, left.x, left.y + 1, "Events: $(m.count)", Tachikoma.tstyle(:accent))
    Tachikoma.set_string!(buf, left.x, left.y + 2,
        "Size: $(m.terminal_size[1])×$(m.terminal_size[2])", Tachikoma.tstyle(:text_dim, dim=true))

    # Latest event detail
    if !isempty(m.events)
        rec = m.events[end]
        evt = rec.event
        Tachikoma.set_string!(buf, right.x, right.y,
            "Latest (#$(rec.count)):", Tachikoma.tstyle(:primary, bold=true))
        if evt isa Tachikoma.KeyEvent
            line2 = "key=:$(evt.key)  char='$(evt.char)' ($(Int(evt.char)))  action=$(evt.action)"
            Tachikoma.set_string!(buf, right.x, right.y + 1, line2, Tachikoma.tstyle(:accent))
        elseif evt isa Tachikoma.MouseEvent
            line2 = "btn=$(evt.button) act=$(evt.action) pos=($(evt.x),$(evt.y))"
            mods = (evt.shift ? "shift " : "") * (evt.alt ? "alt " : "") * (evt.ctrl ? "ctrl" : "")
            Tachikoma.set_string!(buf, right.x, right.y + 1, line2, Tachikoma.tstyle(:accent))
            !isempty(strip(mods)) && Tachikoma.set_string!(buf, right.x, right.y + 2,
                "mods: $mods", Tachikoma.tstyle(:text_dim))
        end
    else
        Tachikoma.set_string!(buf, right.x, right.y,
            "Press any key...", Tachikoma.tstyle(:text_dim, dim=true))
    end
end

function _render_log(buf, area, m::InputTesterModel)
    h = area.height
    h <= 0 && return
    n = length(m.events)
    visible_end = min(n, m.scroll)
    visible_start = max(1, visible_end - h + 1)

    for (row, idx) in enumerate(visible_start:visible_end)
        row > h && break
        rec = m.events[idx]
        evt = rec.event

        num_str = lpad(string(rec.count), 4) * " "
        Tachikoma.set_string!(buf, area.x, area.y + row - 1, num_str,
            Tachikoma.tstyle(:text_dim, dim=true))

        action_style = if evt isa Tachikoma.KeyEvent
            if evt.action == Tachikoma.key_press
                Tachikoma.tstyle(:success)
            elseif evt.action == Tachikoma.key_repeat
                Tachikoma.tstyle(:warning)
            else
                Tachikoma.tstyle(:error)
            end
        else
            Tachikoma.tstyle(:accent)
        end

        summary = rec.summary
        max_w = area.width - 6
        if length(summary) > max_w
            summary = summary[1:max_w]
        end
        Tachikoma.set_string!(buf, area.x + 5, area.y + row - 1, summary, action_style)
    end
end

function _render_footer(buf, area, m::InputTesterModel)
    Tachikoma.render(Tachikoma.StatusBar(
        left=[
            Tachikoma.Span("  PgUp/PgDn ", Tachikoma.tstyle(:accent)),
            Tachikoma.Span("scroll  ", Tachikoma.tstyle(:text_dim)),
        ],
        right=[
            Tachikoma.Span("press=", Tachikoma.tstyle(:text_dim)),
            Tachikoma.Span("green ", Tachikoma.tstyle(:success)),
            Tachikoma.Span("repeat=", Tachikoma.tstyle(:text_dim)),
            Tachikoma.Span("yellow ", Tachikoma.tstyle(:warning)),
            Tachikoma.Span("release=", Tachikoma.tstyle(:text_dim)),
            Tachikoma.Span("red ", Tachikoma.tstyle(:error)),
            Tachikoma.Span(" Ctrl+C quit ", Tachikoma.tstyle(:text_dim, dim=true)),
        ]
    ), area, buf)
end
