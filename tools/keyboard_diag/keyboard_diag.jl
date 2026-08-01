#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════════
# Tachikoma keyboard diagnostic  (Tachikoma app)
# ═══════════════════════════════════════════════════════════════════════
#
# A guided input-capture TUI for debugging how Tachikoma (and therefore
# Kaimon) handles keyboards — especially international layouts (AZERTY,
# QWERTZ, dead keys, Option/AltGr, accented characters).
#
# For every key you press it records, side by side:
#   • the RAW bytes the terminal actually sent
#   • the UTF-8 interpretation of those bytes (the "truth")
#   • the KeyEvent Tachikoma's LIVE decoder produced from them
#
# The gap between the UTF-8 truth and Tachikoma's decode is the bug we are
# hunting. This uses Tachikoma's own `enable_raw_capture!` / `last_event_raw`
# tap, so the "decoded" column is exactly what a real app sees.
#
# Run it against the Julia environment that has Tachikoma (e.g. Kaimon's):
#
#     julia --project=/path/to/env  keyboard_diag.jl
#
# When you finish (Ctrl+C through the free-form section) it writes a log
# file and shows its path. Send that file back for analysis.
# ═══════════════════════════════════════════════════════════════════════

module KeyDiag

using Tachikoma
using Dates
@tachikoma_app

import Tachikoma:
    enable_raw_capture!,
    disable_raw_capture!,
    last_event_raw,
    reset_key_state!,
    KITTY_KEYBOARD_ON,
    KITTY_KEYBOARD_OFF,
    key_press,
    key_repeat

# ───────────────────────────────────────────────────────────────────────
# Prompt list — tuned for Mac-French AZERTY, but useful for any layout.
# ───────────────────────────────────────────────────────────────────────

struct Prompt
    section::String
    label::String
    hint::String
    is_space::Bool   # the prompt where SPACE means "record", not "skip"
    is_ctrlc::Bool   # the prompt where Ctrl+C means "record", not "advance"
end

# Prompts ask you to PRODUCE a character/key however your layout makes it —
# layout-neutral. Parenthetical hints marked "AZERTY:" are optional guidance
# for French keyboards; ignore them on other layouts. Skip (SPACE) anything you
# can't type or that your OS intercepts.
const SECTIONS = [
    "Control & navigation keys" => [
        ("Enter", "", false, false),
        ("Tab", "", false, false),
        ("Backspace", "", false, false),
        ("Escape", "", false, false),
        ("Spacebar", "", true, false),
        ("Delete (forward)", "Fn+Delete on Mac — skip if you have none", false, false),
        ("Up arrow", "", false, false),
        ("Down arrow", "", false, false),
        ("Left arrow", "", false, false),
        ("Right arrow", "", false, false),
        ("Home", "", false, false),
        ("End", "", false, false),
        ("Page Up", "", false, false),
        ("Page Down", "", false, false),
    ],
    "Produce each LETTER (type it however your layout does)" => [
        ("a", "", false, false),
        ("z", "", false, false),
        ("q", "", false, false),
        ("w", "", false, false),
        ("m", "", false, false),
        ("A   (capital — with Shift)", "", false, false),
    ],
    "Produce each DIGIT" => [
        ("1", "AZERTY: Shift + the & key", false, false),
        ("2", "AZERTY: Shift + the é key", false, false),
        ("0", "AZERTY: Shift + the à key", false, false),
    ],
    "Produce each ACCENTED letter (skip any you can't make)" => [
        ("é", "", false, false),
        ("è", "", false, false),
        ("à", "", false, false),
        ("ç", "", false, false),
        ("ù", "", false, false),
    ],
    "Produce each CODING symbol (essential for programming)" => [
        ("@", "", false, false),
        ("#", "", false, false),
        ("[", "", false, false),
        ("]", "", false, false),
        ("{", "", false, false),
        ("}", "", false, false),
        ("|   (pipe)", "", false, false),
        ("\\   (backslash)", "", false, false),
        ("~   (tilde)", "", false, false),
        ("`   (backtick)", "", false, false),
        ("€   (euro)", "skip if you can't type it", false, false),
    ],
    "Produce each PUNCTUATION mark" => [
        (".", "", false, false),
        (",", "", false, false),
        (";", "", false, false),
        (":", "", false, false),
        ("/", "", false, false),
        ("=", "", false, false),
        ("!", "", false, false),
        ("?", "", false, false),
    ],
    "Dead-key composition (skip if your layout has no dead keys)" => [
        ("ê   (e-circumflex)", "AZERTY: tap the ^ dead key, then e", false, false),
        ("ë   (e-trema)", "AZERTY: Shift+^ then e", false, false),
    ],
    "Ctrl combinations  (hold Ctrl, NO Shift; Ctrl+C quits, Ctrl+Z undoes)" => [
        ("Ctrl + a", "hold Ctrl, tap the A key — no Shift", false, false),
        ("Ctrl + k", "hold Ctrl, tap the K key — no Shift", false, false),
        ("Ctrl + w", "hold Ctrl, tap the W key — no Shift", false, false),
        ("Ctrl + Left arrow", "often an OS shortcut — SKIP if it doesn't reach here", false, false),
        (
            "Ctrl + Right arrow",
            "often an OS shortcut — SKIP if it doesn't reach here",
            false,
            false,
        ),
    ],
    "Option (⌥) probe — Mac only; reveals 'Option as Meta' (skip elsewhere)" => [
        ("Option + a", "hold Option, tap the A key — no Shift", false, false),
        ("Option + e", "hold Option, tap the E key — no Shift", false, false),
        ("Option + 5", "hold Option, tap the 5 key — no Shift", false, false),
    ],
    "Function keys" => [
        ("F1", "", false, false),
        ("F2", "", false, false),
        ("F5", "", false, false),
        ("F12", "", false, false),
    ],
]

const PROMPTS = Prompt[
    Prompt(section, label, hint, sp, cc) for (section, ps) in SECTIONS for
    (label, hint, sp, cc) in ps
]

# ───────────────────────────────────────────────────────────────────────
# Captured record
# ───────────────────────────────────────────────────────────────────────

struct Record
    section::String
    label::String
    mode::Symbol
    raw::Vector{UInt8}
    valid_utf8::Bool
    utf8::String
    decoded::String
    ok::Union{Bool,Nothing}   # nothing = no automatic judgement
    skipped::Bool
end

hexbytes(b) = isempty(b) ? "—" : join((string(x; base=16, pad=2) for x in b), " ")
decbytes(b) = join(Int.(b), " ")

function utf8_view(bytes)
    s = String(copy(bytes))
    return isvalid(s) ? (true, s) : (false, "")
end

_show(c::Char) = isvalid(c) ? "'$(c)'" : "U+" * uppercase(string(UInt32(c); base=16, pad=4))

function describe(e::KeyEvent)
    a = if e.action == key_press
        ""
    elseif e.action == key_repeat
        " [repeat]"
    else
        " [release]"
    end
    if e.key == :char
        ":char $(_show(e.char))$a"
    elseif e.char == '\0'
        ":$(e.key)$a"
    else
        ":$(e.key) $(_show(e.char))$a"
    end
end
describe(e::MouseEvent) = "mouse($(e.button) $(e.action) @ $(e.x),$(e.y))"
describe(::Event) = "(other event)"

function make_record(p::Prompt, raw, evt, mode)
    valid, utf8 = utf8_view(raw)
    dec = describe(evt)
    ok = nothing
    if evt isa KeyEvent && evt.key == :char && valid && length(utf8) == 1
        # Decoder fidelity: did the produced char match the raw bytes' UTF-8?
        ok = (evt.char == utf8[1])
    end
    return Record(p.section, p.label, mode, copy(raw), valid, utf8, dec, ok, false)
end

function skipped_record(p::Prompt, raw, evt, mode)
    valid, utf8 = utf8_view(raw)
    return Record(
        p.section,
        p.label,
        mode,
        copy(raw),
        valid,
        utf8,
        "skipped via $(describe(evt))",
        nothing,
        true,
    )
end

function free_record(i, raw, evt, mode)
    valid, utf8 = utf8_view(raw)
    ok = if (evt isa KeyEvent && evt.key == :char && valid && length(utf8) == 1)
        (evt.char == utf8[1])
    else
        nothing
    end
    return Record(
        "Free-form", "(free #$(i))", mode, copy(raw), valid, utf8, describe(evt), ok, false
    )
end

# ───────────────────────────────────────────────────────────────────────
# Model
# ───────────────────────────────────────────────────────────────────────

@kwdef mutable struct KeyDiagModel <: Model
    phase::Symbol = :intro          # :intro :mode :guided :freeform :done
    idx::Int = 1                    # current prompt index
    results::Vector{Record} = Record[]
    modes::Vector{Symbol} = [:kitty]  # protocol(s) captured per prompt (both = [:legacy,:kitty])
    pass_i::Int = 1                   # which protocol pass for the CURRENT prompt
    history::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[]  # (idx,pass) before each guided capture, for undo
    desc::String = ""
    free_i::Int = 0
    kitty_supported::Bool = false
    io::Any = nothing
    logpath::String = ""
    quit::Bool = false
end

should_quit(m::KeyDiagModel) = m.quit

function init!(m::KeyDiagModel, t::Terminal)
    m.io = t.io
    m.kitty_supported = t.kitty_keyboard
    return enable_raw_capture!()
end
cleanup!(m::KeyDiagModel) = disable_raw_capture!()

curmode(m) = m.modes[clamp(m.pass_i, 1, length(m.modes))]
dual(m) = length(m.modes) > 1

function apply_mode!(m::KeyDiagModel)
    # Use the Kitty "set flags" form (CSI = flags ; 1 u) rather than push/pop
    # (CSI > u / CSI < u). This edits the single protocol entry the framework
    # already pushed at enter_tui!, instead of churning the terminal's flag
    # STACK dozens of times per session — which some terminals (iTerm2) handle
    # poorly and can leave the protocol stuck on after exit.
    if curmode(m) == :legacy
        print(m.io, "\e[=0;1u")                       # disable all enhancements
    elseif curmode(m) == :kitty && m.kitty_supported
        print(m.io, "\e[=$(Tachikoma.KITTY_FLAGS);1u")  # enable the full flag set
    end
    return flush(m.io)
end

function start_guided!(m::KeyDiagModel)
    m.phase = :guided
    m.idx = 1
    m.pass_i = 1
    return apply_mode!(m)
end

# Called after each capture. In dual ("both") mode, capture the SAME prompt
# once per protocol (legacy then kitty) before moving to the next key — the
# terminal is flipped between the two presses so a single trip through the
# list yields both encodings, side by side.
function advance!(m::KeyDiagModel)
    if m.pass_i < length(m.modes)
        m.pass_i += 1          # same key, other protocol — user presses it again
        apply_mode!(m)
        return nothing
    end
    m.pass_i = 1
    m.idx += 1
    if m.idx > length(PROMPTS)
        m.phase = :freeform
        m.free_i = 0
        m.pass_i = length(m.modes)   # free-form uses the richest protocol (kitty if both)
    end
    return apply_mode!(m)
end

# Undo the previous capture: drop its record and return to that exact prompt /
# protocol pass so the user can re-press a key they fat-fingered.
function undo!(m::KeyDiagModel)
    isempty(m.history) && return nothing
    idx, pass = pop!(m.history)
    isempty(m.results) || pop!(m.results)
    m.phase = :guided                 # may have been bumped into free-form
    m.idx = idx
    m.pass_i = pass
    return apply_mode!(m)
end

# ── env report (for the log) ──
function env_report()
    keys = [
        "TERM",
        "TERM_PROGRAM",
        "TERM_PROGRAM_VERSION",
        "COLORTERM",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LANGUAGE",
        "KITTY_WINDOW_ID",
        "WEZTERM_EXECUTABLE",
        "ALACRITTY_WINDOW_ID",
        "ITERM_SESSION_ID",
        "SSH_CONNECTION",
        "TMUX",
        "STY",
    ]
    lines = ["Julia: $(VERSION)  ($(Sys.MACHINE))", "OS:    $(Sys.KERNEL)"]
    for k in keys
        haskey(ENV, k) && push!(lines, rpad(k * ":", 22) * ENV[k])
    end
    return join(lines, "\n")
end

function finish!(m::KeyDiagModel)
    # Write once, and only if something was captured.
    (isempty(m.logpath) && !isempty(m.results)) || return nothing
    io = IOBuffer()
    println(io, "Tachikoma keyboard diagnostic")
    println(io, "Keyboard/OS (user-described): $(m.desc)")
    println(io, "Capture mode(s): $(join(m.modes, ", "))")
    println(io, "Kitty keyboard supported: $(m.kitty_supported)")
    println(io, "")
    println(io, "── Environment ──")
    println(io, env_report())
    println(io, "")
    println(io, "── Captures ──")
    println(io, "(each key tagged [legacy]/[kitty]; in 'both' mode the two land together)")
    last_section = ""
    for r in m.results
        if r.section != last_section
            println(io, "\n-- $(r.section) --")
            last_section = r.section
        end
        tag = "[$(r.mode)]"
        if r.skipped
            println(io, "  $(rpad(r.label, 24)) $(rpad(tag, 8))  skipped ($(r.decoded))")
        else
            flag = if r.ok === nothing
                ""
            elseif r.ok
                "  OK"
            else
                "  *** MISMATCH ***"
            end
            println(io, "  $(r.label)  $(tag)")
            println(io, "      raw.hex : $(hexbytes(r.raw))")
            println(io, "      raw.dec : $(decbytes(r.raw))")
            println(io, "      utf8    : $(r.valid_utf8 ? repr(r.utf8) : "<INVALID UTF-8>")")
            println(io, "      decoded : $(r.decoded)$flag")
        end
    end
    fname = "tachikoma_keydiag_$(Dates.format(now(), "yyyymmdd_HHMMSS")).log"
    path = abspath(fname)
    open(path, "w") do f
        return write(f, String(take!(io)))
    end
    return m.logpath = path
end

# ───────────────────────────────────────────────────────────────────────
# update!
# ───────────────────────────────────────────────────────────────────────

# Modifier keys report as their own events in kitty mode (flag 8). Ignore them
# during capture so pressing e.g. Shift+a records the 'A', not the Shift press.
const MODIFIER_KEYS = Set{Symbol}([
    :left_shift,
    :right_shift,
    :left_ctrl,
    :right_ctrl,
    :left_alt,
    :right_alt,
    :left_super,
    :right_super,
    :left_hyper,
    :right_hyper,
    :left_meta,
    :right_meta,
    :caps_lock,
    :num_lock,
    :scroll_lock,
])

update!(m::KeyDiagModel, ::MouseEvent) = nothing   # ignore mouse

function update!(m::KeyDiagModel, evt::KeyEvent)
    # Clear held-key tracking so the NEXT event is seen as a fresh press. In
    # legacy mode there are no key-release events, so _track_key_state! would
    # otherwise reclassify a repeated same-key press (e.g. Space to answer the
    # Spacebar prompt, then Space again to skip the next key) as a key_repeat
    # and we'd drop it below. A per-key diagnostic wants every deliberate press.
    reset_key_state!()
    # Genuine held-key repeats (kitty event_type=2) are still filtered here.
    evt.action == key_repeat && return nothing
    # A lone modifier keypress is never the answer to a prompt — wait for the
    # real key it modifies.
    evt.key in MODIFIER_KEYS && return nothing

    # Global quit: Ctrl+C saves the log and exits from ANY phase, one press.
    if evt.key == :ctrl_c
        finish!(m)
        m.quit = true
        return nothing
    end

    if m.phase == :intro
        if evt.key == :enter
            m.kitty_supported ? (m.phase = :mode) : (m.modes=[:legacy]; start_guided!(m))
        elseif evt.key == :backspace
            isempty(m.desc) || (m.desc = m.desc[1:prevind(m.desc, lastindex(m.desc))])
        elseif evt.key == :char
            m.desc *= evt.char
        end

    elseif m.phase == :mode
        if evt.key == :char
            c = evt.char
            c == '1' && (m.modes=[:kitty]; start_guided!(m))
            c == '2' && (m.modes=[:legacy]; start_guided!(m))
            c == '3' && (m.modes=[:legacy, :kitty]; start_guided!(m))
        end

    elseif m.phase == :guided
        p = PROMPTS[m.idx]
        # Ctrl+Z: undo the previous capture and re-do that key.
        if evt.key == :ctrl && evt.char == 'z'
            undo!(m)
            return nothing
        end
        # SPACE skips a key you can't type (except on the Spacebar prompt itself).
        if !p.is_space && evt.key == :char && evt.char == ' '
            push!(m.history, (m.idx, m.pass_i))
            push!(m.results, skipped_record(p, last_event_raw(), evt, curmode(m)))
            m.pass_i = length(m.modes)   # skip remaining protocol passes of this key
            advance!(m)
            return nothing
        end
        push!(m.history, (m.idx, m.pass_i))
        push!(m.results, make_record(p, last_event_raw(), evt, curmode(m)))
        advance!(m)

    elseif m.phase == :freeform
        m.free_i += 1
        push!(m.results, free_record(m.free_i, last_event_raw(), evt, curmode(m)))
    end
end

# ───────────────────────────────────────────────────────────────────────
# view
# ───────────────────────────────────────────────────────────────────────

function view(m::KeyDiagModel, f::Frame)
    buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(10), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return nothing
    render_top!(m, rows[1], buf)
    render_log!(m, rows[2], buf)
    return render_footer!(m, rows[3], buf)
end

# Persistent control bar — always shows how to skip and how to quit.
function render_footer!(m::KeyDiagModel, area, buf)
    controls = if m.phase == :intro
        "Type your description   ·   Enter: continue   ·   Ctrl+C: quit"
    elseif m.phase == :mode
        "Press 1 / 2 / 3 to choose a mode   ·   Ctrl+C: quit"
    elseif m.phase == :guided
        "SPACE: skip   ·   Ctrl+Z: undo last   ·   Ctrl+C: save & quit"
    elseif m.phase == :freeform
        "Press any keys to check   ·   Ctrl+C: save & exit"
    else
        "Ctrl+C: quit"
    end
    for cx in area.x:right(area)
        set_char!(buf, cx, area.y, ' ', tstyle(:title))
    end
    return set_string!(
        buf, area.x + 1, area.y, controls, tstyle(:title; bold=true); max_x=right(area)
    )
end

function render_top!(m::KeyDiagModel, area, buf)
    modestr = m.phase in (:guided,) ? "  ·  mode: $(uppercase(string(curmode(m))))" : ""
    blk = Block(;
        title="Tachikoma keyboard diagnostic$modestr",
        border_style=tstyle(:border),
        title_style=tstyle(:title; bold=true),
    )
    c = render(blk, area, buf)
    x = c.x + 1
    y = c.y

    if m.phase == :intro
        y = putln(
            buf,
            x,
            y,
            c,
            "Records the RAW bytes your terminal sends for each key,",
            tstyle(:text_dim),
        )
        y = putln(
            buf,
            x,
            y,
            c,
            "so we can fix keyboard handling for international layouts.",
            tstyle(:text_dim),
        )
        y += 1
        ks = if m.kitty_supported
            ("Kitty keyboard protocol: SUPPORTED", tstyle(:success))
        else
            ("Kitty keyboard protocol: not supported", tstyle(:warning))
        end
        y = putln(buf, x, y, c, ks[1], ks[2])
        y += 1
        y = putln(
            buf,
            x,
            y,
            c,
            "Type your keyboard & OS (e.g. \"French AZERTY, macOS, iTerm2\"):",
            tstyle(:text; bold=true),
        )
        # Editable input line: prompt marker, the typed text, then a block cursor.
        set_string!(buf, x, y, "❯ ", tstyle(:accent; bold=true))
        tx = set_string!(buf, x + 2, y, m.desc, tstyle(:accent; bold=true); max_x=right(c) - 1)
        set_char!(buf, min(tx, right(c)), y, '█', tstyle(:accent))

    elseif m.phase == :mode
        y = putln(buf, x, y, c, "Choose capture mode:", tstyle(:text; bold=true))
        y = putln(
            buf,
            x,
            y,
            c,
            "  [1] Kitty mode   (what Kaimon actually uses — recommended)",
            tstyle(:text),
        )
        y = putln(buf, x, y, c, "  [2] Legacy mode  (plain bytes, no protocol)", tstyle(:text))
        putln(buf, x, y, c, "  [3] Both  (press each key twice — legacy then kitty)", tstyle(:text))

    elseif m.phase == :guided
        p = PROMPTS[m.idx]
        set_string!(buf, x, y, p.section, tstyle(:secondary; bold=true); max_x=right(c))
        set_string!(
            buf, right(c) - 10, y, lpad("[$(m.idx)/$(length(PROMPTS))]", 10), tstyle(:text_dim)
        )
        y += 2
        # In "both" mode each key is pressed once per protocol — show which pass.
        if dual(m)
            again = m.pass_i > 1 ? " AGAIN" : ""
            y = putln(
                buf,
                x,
                y,
                c,
                "$(uppercase(string(curmode(m)))) protocol  ·  press $(m.pass_i) of $(length(m.modes))$again",
                tstyle(:warning; bold=true),
            )
        end
        set_string!(buf, x, y, "Produce:  ", tstyle(:text))
        hx = set_string!(buf, x + 10, y, p.label, tstyle(:accent; bold=true); max_x=right(c))
        isempty(p.hint) ||
            set_string!(buf, hx + 2, y, "($(p.hint))", tstyle(:text_dim; dim=true); max_x=right(c))
        putln(
            buf,
            x,
            y + 2,
            c,
            "…however your keyboard makes it.  SPACE skips anything you can't type.",
            tstyle(:text_dim; dim=true),
        )

    elseif m.phase == :freeform
        y = putln(buf, x, y, c, "Free-form capture (optional)", tstyle(:secondary; bold=true))
        y = putln(
            buf,
            x,
            y,
            c,
            "Press any keys you'd like to check — or Ctrl+C to save & exit.",
            tstyle(:text),
        )
        putln(
            buf, x, y, c, "Not sure? You're done — just press Ctrl+C.", tstyle(:text_dim; dim=true)
        )
    end
end

function render_log!(m::KeyDiagModel, area, buf)
    blk = Block(;
        title="Captured  ($(length(m.results)))",
        border_style=tstyle(:border),
        title_style=tstyle(:title),
    )
    c = render(blk, area, buf)
    h = c.height
    h <= 0 && return nothing
    # Show the tail that fits (newest at the bottom).
    start = max(1, length(m.results) - h + 1)
    y = c.y
    for i in start:length(m.results)
        r = m.results[i]
        render_record_line!(buf, c.x, y, c, r)
        y += 1
    end
end

function render_record_line!(buf, x, y, c, r::Record)
    # Protocol tag so legacy/kitty captures are distinguishable at a glance.
    tag = r.mode == :kitty ? "K " : "L "
    x = set_string!(buf, x, y, tag, tstyle(:secondary; dim=true); max_x=right(c))
    if r.skipped
        set_string!(
            buf, x, y, "· $(r.label)  →  $(r.decoded)", tstyle(:text_dim; dim=true); max_x=right(c)
        )
        return nothing
    end
    xx = set_string!(buf, x, y, "[$(hexbytes(r.raw))]", tstyle(:text_dim); max_x=right(c))
    utf8_disp = r.valid_utf8 ? "\"$(r.utf8)\"" : "<bad utf8>"
    ustyle = r.valid_utf8 ? tstyle(:primary) : tstyle(:warning)
    xx = set_string!(buf, xx + 1, y, utf8_disp, ustyle; max_x=right(c))
    xx = set_string!(buf, xx + 1, y, "→", tstyle(:text_dim); max_x=right(c))
    dstyle = r.ok === false ? tstyle(:error; bold=true) : tstyle(:text)
    xx = set_string!(buf, xx + 1, y, r.decoded, dstyle; max_x=right(c))
    if r.ok !== nothing
        mark = r.ok ? " ✓" : " ⚠"
        set_string!(buf, xx, y, mark, r.ok ? tstyle(:success) : tstyle(:error); max_x=right(c))
    end
end

# Print a line clamped to the block; returns next y. `maxx` kw kept flexible.
function putln(buf, x, y, c, str, style; maxx=right(c))
    y > bottom(c) && return y
    set_string!(buf, x, y, str, style; max_x=maxx)
    return y + 1
end

# ───────────────────────────────────────────────────────────────────────

# Belt-and-suspenders terminal restore. Runs after app() regardless of how it
# exited (clean quit, Ctrl+C, or a teardown that got interrupted). Forces the
# shell back to a usable state even if leave_tui! didn't fully complete.
function _force_restore_terminal!()
    try
        Tachikoma.set_raw_mode!(false)
    catch
    end          # cooked mode (echo/line editing)
    try
        print(
            stdout,
            "\e[<u",                     # pop any lingering Kitty keyboard entry
            "\e[=0;1u",                  # and clear its flags for good measure
            "\e[?1049l",                 # leave alternate screen
            "\e[?25h",                   # show cursor
            "\e[?1000l\e[?1002l\e[?1006l", # disable mouse reporting
            "\e[0m",
        )                     # reset text attributes
        flush(stdout)
    catch
    end
end

function run()
    m = KeyDiagModel()
    try
        app(m; default_bindings=false)
    catch e
        e isa InterruptException || rethrow()   # Ctrl+C that slipped through as a signal
    finally
        finish!(m)                               # ensure the log is saved (no-op if already)
        _force_restore_terminal!()               # guarantee a usable shell on the way out
    end
    if isempty(m.results)
        println("\n(No keys were captured — nothing written.)")
    else
        println("\nDiagnostic written to:\n  ", m.logpath)
        println("Please send that file back for analysis. Thank you!")
    end
    return m
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    KeyDiag.run()
end
