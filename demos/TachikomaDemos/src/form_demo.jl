# ═══════════════════════════════════════════════════════════════════════
# Form Demo ── form with all input widget types + live preview panel
#
# Tab/Shift-Tab to navigate fields, widget-specific keys for editing,
# Enter on Submit, Ctrl-r to reset, Esc to quit.
# ═══════════════════════════════════════════════════════════════════════

function _build_form(tick)
    Form([
        FormField("Name",   TextInput(; text="", focused=true, tick=tick,
                    validator=s -> length(s) < 2 ? "Min 2 chars" : nothing);
                    required=true),
        FormField("Bio",    TextArea(; text="", focused=false, tick=tick)),
        FormField("Notify", Checkbox("Enable notifications"; focused=false)),
        FormField("Role",   RadioGroup(["Admin", "Editor", "Viewer"])),
        FormField("Region", DropDown(["Tokyo", "Berlin", "NYC", "London",
                                      "São Paulo", "Sydney", "Mumbai", "Seoul",
                                      "Nairobi", "Toronto"])),
    ];
        submit_label="Submit",
        block=Block(title="Form", border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        tick=tick,
    )
end

@kwdef mutable struct FormModel <: Model
    quit::Bool = false
    tick::Int = 0
    form::Form = _build_form(0)
    submitted::Bool = false
    submit_flash::Int = 0       # countdown for "Submitted!" message
end

should_quit(m::FormModel) = m.quit

function update!(m::FormModel, evt::KeyEvent)
    # Ctrl-r resets the form
    if evt.key == :char && evt.char == '\x12'  # Ctrl-R
        m.form = _build_form(m.tick)
        m.submitted = false
        m.submit_flash = 0
        return
    end

    # Detect submit: if focused widget is the submit button and key is Enter
    cur = current(m.form.focus)
    is_submit_press = cur === m.form.submit_button &&
                      (evt.key == :enter || (evt.key == :char && evt.char == ' '))

    handled = handle_key!(m.form, evt)

    if is_submit_press && handled && valid(m.form)
        m.submitted = true
        m.submit_flash = 90  # ~3 seconds at 30fps
    end

    # If the form didn't consume the key, check for quit
    if !handled
        evt.key == :escape && (m.quit = true)
    end
end

function view(m::FormModel, f::Frame)
    m.tick += 1
    m.form.tick = m.tick
    m.form.submit_button.tick = m.tick
    if m.submit_flash > 0
        m.submit_flash -= 1
    end
    buf = f.buffer

    # Layout: header | [form | preview] | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header_area = rows[1]
    body_area   = rows[2]
    footer_area = rows[3]

    # ── Header ──
    title = "Form Demo"
    hx = header_area.x + max(0, (header_area.width - length(title)) ÷ 2)
    set_string!(buf, hx, header_area.y, title, tstyle(:title, bold=true))

    # ── Body: form + preview ──
    cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), body_area)
    length(cols) < 2 && return
    form_area    = cols[1]
    preview_area = cols[2]

    # Render form
    render(m.form, form_area, buf)

    # Render preview panel
    _render_preview!(buf, preview_area, m)

    # ── Footer ──
    render(StatusBar(
        left=[Span("  [Tab/S-Tab]navigate [Ctrl-r]reset ", tstyle(:text_dim))],
        right=[Span("[Esc]quit ", tstyle(:text_dim))],
    ), footer_area, buf)
end

function _render_preview!(buf::Buffer, area::Rect, m::FormModel)
    block = Block(title="Preview",
                  border_style=tstyle(:border),
                  title_style=tstyle(:title))
    inner = render(block, area, buf)
    (inner.width < 4 || inner.height < 2) && return

    y = inner.y

    # Validity indicator
    is_valid = valid(m.form)
    if is_valid
        set_string!(buf, inner.x, y, "✓ Valid", tstyle(:success, bold=true))
    else
        set_string!(buf, inner.x, y, "✗ Invalid", tstyle(:error, bold=true))
    end
    y += 2

    # Submit flash
    if m.submit_flash > 0
        set_string!(buf, inner.x, y, "Submitted!", tstyle(:accent, bold=true))
        y += 2
    end

    # Key-value pairs from form
    vals = value(m.form)
    label_style = tstyle(:text_dim)
    value_style = tstyle(:text)

    for (label, val) in sort(collect(vals); by=first)
        y > bottom(inner) && break
        display_val = _format_preview_value(val)
        set_string!(buf, inner.x, y, "$(label): ", label_style;
                    max_x=right(inner))
        vx = inner.x + length(label) + 2
        set_string!(buf, vx, y, display_val, value_style;
                    max_x=right(inner))
        y += 1
    end
end

function _format_preview_value(val)
    if val isa Bool
        val ? "yes" : "no"
    elseif val isa Int
        string(val)
    elseif val isa String
        isempty(val) ? "(empty)" : val
    else
        string(val)
    end
end

function form_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(FormModel(); fps=30)
end
