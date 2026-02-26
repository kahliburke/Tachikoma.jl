# ═══════════════════════════════════════════════════════════════════════════════
# BridgeTool handlers for the Input Tester
#
# Each handler captures the model and provides MCP access to event state.
# Schema is auto-generated from the typed function signatures.
# ═══════════════════════════════════════════════════════════════════════════════

using MCPRepl.MCPReplBridge: BridgeTool

# ── Handlers ─────────────────────────────────────────────────────────────────

function _make_get_status(model)
    """Get current protocol status, event count, and latest event details."""
    function get_status()
        kitty = model.kitty ? "ON" : "OFF"
        lines = String[
            "Protocol: Kitty $(kitty)",
            "Events: $(model.count)",
            "Size: $(model.terminal_size[1])x$(model.terminal_size[2])",
        ]
        if !isempty(model.events)
            rec = model.events[end]
            evt = rec.event
            push!(lines, "", "Latest event (#$(rec.count)):")
            push!(lines, "  summary: $(rec.summary)")
            if evt isa Tachikoma.KeyEvent
                push!(lines, "  key: :$(evt.key)")
                push!(lines, "  char: '$(evt.char)' ($(Int(evt.char)))")
                push!(lines, "  action: $(evt.action)")
            elseif evt isa Tachikoma.MouseEvent
                push!(lines, "  button: $(evt.button)")
                push!(lines, "  action: $(evt.action)")
                push!(lines, "  position: ($(evt.x), $(evt.y))")
                push!(lines, "  modifiers: shift=$(evt.shift) alt=$(evt.alt) ctrl=$(evt.ctrl)")
            end
        else
            push!(lines, "", "No events yet — press keys in the tester terminal.")
        end
        return join(lines, "\n")
    end
end

function _make_get_events(model)
    """Get recent events. Returns the last N events with type, key, action details."""
    function get_events(last_n::Int)
        n = clamp(last_n, 1, 200)
        events = model.events
        isempty(events) && return "No events yet."
        start = max(1, length(events) - n + 1)
        recent = events[start:end]
        lines = String["$(length(recent)) of $(length(events)) total events:", ""]
        for rec in recent
            evt = rec.event
            detail = if evt isa Tachikoma.KeyEvent
                action_str = evt.action == Tachikoma.key_press ? "press" :
                             evt.action == Tachikoma.key_repeat ? "repeat" : "release"
                if evt.key == :char
                    "#$(rec.count) KEY '$(evt.char)' $(action_str)"
                elseif evt.key == :ctrl
                    "#$(rec.count) KEY ctrl+$(evt.char) $(action_str)"
                else
                    "#$(rec.count) KEY :$(evt.key) $(action_str)"
                end
            elseif evt isa Tachikoma.MouseEvent
                "#$(rec.count) MOUSE $(evt.button) $(evt.action) ($(evt.x),$(evt.y))"
            else
                "#$(rec.count) $(rec.summary)"
            end
            push!(lines, detail)
        end
        return join(lines, "\n")
    end
end

function _make_clear_events(model)
    """Clear all recorded events and reset the counter."""
    function clear_events()
        empty!(model.events)
        model.count = 0
        model.scroll = 0
        return "Events cleared."
    end
end

function _make_get_event_detail(model)
    """Get full details for a specific event by its count number."""
    function get_event_detail(event_number::Int)
        idx = findfirst(r -> r.count == event_number, model.events)
        idx === nothing && return "Event #$(event_number) not found (may have been scrolled out of history)."
        rec = model.events[idx]
        evt = rec.event
        lines = String["Event #$(rec.count):", "  summary: $(rec.summary)"]
        if evt isa Tachikoma.KeyEvent
            push!(lines, "  type: KeyEvent")
            push!(lines, "  key: :$(evt.key)")
            push!(lines, "  char: '$(evt.char)' (code=$(Int(evt.char)), hex=0x$(string(Int(evt.char), base=16)))")
            push!(lines, "  action: $(evt.action)")
        elseif evt isa Tachikoma.MouseEvent
            push!(lines, "  type: MouseEvent")
            push!(lines, "  x: $(evt.x)  y: $(evt.y)")
            push!(lines, "  button: $(evt.button)")
            push!(lines, "  action: $(evt.action)")
            push!(lines, "  shift: $(evt.shift)  alt: $(evt.alt)  ctrl: $(evt.ctrl)")
        else
            push!(lines, "  type: $(typeof(evt))")
            push!(lines, "  repr: $(repr(evt))")
        end
        return join(lines, "\n")
    end
end

function _make_get_unknown_csi_log(model)
    """Get the debug log of unrecognized CSI escape sequences. Shows raw bytes for diagnosing unknown key events."""
    function get_unknown_csi_log()
        log = Tachikoma._UNKNOWN_CSI_LOG
        isempty(log) && return "No unknown CSI sequences logged."
        return "$(length(log)) unknown CSI sequences:\n\n" * join(log, "\n")
    end
end

# ── Tool factory ─────────────────────────────────────────────────────────────

function create_tools(model)
    return BridgeTool[
        BridgeTool("get_status", _make_get_status(model)),
        BridgeTool("get_events", _make_get_events(model)),
        BridgeTool("get_event_detail", _make_get_event_detail(model)),
        BridgeTool("clear_events", _make_clear_events(model)),
        BridgeTool("get_unknown_csi_log", _make_get_unknown_csi_log(model)),
    ]
end
