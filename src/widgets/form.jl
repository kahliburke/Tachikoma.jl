# ═══════════════════════════════════════════════════════════════════════
# Form ── container for labeled input fields with tab navigation
# ═══════════════════════════════════════════════════════════════════════

struct FormField
    label::String
    widget::Any                    # TextInput, TextArea, Checkbox, RadioGroup, DropDown
    required::Bool
end

FormField(label::String, widget; required::Bool=false) =
    FormField(label, widget, required)

mutable struct Form
    fields::Vector{FormField}
    submit_label::String
    block::Union{Block, Nothing}
    label_width::Int               # 0 = auto
    focus::FocusRing
    tick::Union{Int, Nothing}
    submit_button::Button
end

"""
    Form(fields; submit_label="Submit", block=nothing, tick=nothing, ...)

Container for labeled input fields with Tab/Shift-Tab navigation and a submit button.
Use `value(form)` to get a `Dict` of field values and `valid(form)` to check validation.
"""
function Form(fields::Vector{FormField};
    submit_label::String="Submit",
    block::Union{Block, Nothing}=nothing,
    label_width::Int=0,
    tick::Union{Int, Nothing}=nothing,
    bordered_submit::Bool=false,
)
    # Build focus ring from widgets + submit button
    widgets = Any[f.widget for f in fields]
    btn_style = bordered_submit ? ButtonStyle(decoration=BorderedButton()) : ButtonStyle()
    btn = Button(submit_label; focused=false, tick=tick, button_style=btn_style)
    push!(widgets, btn)
    ring = FocusRing(widgets)

    # Auto-compute label width
    lw = label_width > 0 ? label_width : maximum(length(f.label) for f in fields; init=6) + 2

    Form(fields, submit_label, block, lw, ring, tick, btn)
end

focusable(::Form) = true
value(form::Form) = form_values(form)

function valid(form::Form)::Bool
    for f in form.fields
        w = f.widget
        if f.required
            val = _field_value(w)
            (val === "" || val === nothing) && return false
        end
        Tachikoma.valid(w) || return false
    end
    true
end

# ── Key handling ──

function handle_key!(form::Form, evt::KeyEvent)::Bool
    if evt.key == :tab
        _form_unfocus!(form)
        next!(form.focus)
        _form_apply_focus!(form)
        return true
    elseif evt.key == :backtab
        _form_unfocus!(form)
        prev!(form.focus)
        _form_apply_focus!(form)
        return true
    end

    # Delegate to focused widget
    cur = current(form.focus)
    if cur !== nothing
        if hasmethod(handle_key!, Tuple{typeof(cur), KeyEvent})
            return handle_key!(cur, evt)
        end
    end
    false
end

function _form_unfocus!(form::Form)
    for f in form.fields
        w = f.widget
        if hasproperty(w, :focused)
            w.focused = false
        end
    end
    form.submit_button.focused = false
end

function _form_apply_focus!(form::Form)
    cur = current(form.focus)
    if cur !== nothing && hasproperty(cur, :focused)
        cur.focused = true
    end
end

# ── Mouse handling ──

function handle_mouse!(form::Form, evt::MouseEvent)::Bool
    if evt.button == mouse_left && evt.action == mouse_press
        # Try each field widget
        for (i, field) in enumerate(form.fields)
            w = field.widget
            if applicable(handle_mouse!, w, evt)
                if handle_mouse!(w, evt)
                    # Switch focus to this widget
                    _form_unfocus!(form)
                    form.focus.active = i
                    _form_apply_focus!(form)
                    return true
                end
            end
        end
        # Try submit button
        if handle_mouse!(form.submit_button, evt)
            _form_unfocus!(form)
            form.focus.active = length(form.fields) + 1
            _form_apply_focus!(form)
            return true
        end
    end
    false
end

# ── Validation helpers ──

function form_values(form::Form)::Dict{String, Any}
    d = Dict{String, Any}()
    for f in form.fields
        d[f.label] = _field_value(f.widget)
    end
    d
end

function _field_value(w)
    try value(w) catch; nothing end
end

# ── Render ──

function _form_field_height(w)::Int
    if w isa TextArea
        max(2, length(w.lines) + 1)
    elseif w isa RadioGroup
        length(w.labels)
    elseif w isa TextInput && !isempty(w.error_msg)
        2
    elseif w isa DropDown && w.open
        1 + min(length(w.items), w.max_visible)
    elseif w isa Button && w.button_style.decoration isa BorderedButton
        3
    else
        1
    end
end

function render(form::Form, rect::Rect, buf::Buffer)
    content_area = if form.block !== nothing
        render(form.block, rect, buf)
    else
        rect
    end
    (content_area.width < 8 || content_area.height < 2) && return

    lw = min(form.label_width, content_area.width ÷ 2)

    # Separate trailing Button fields — they share a horizontal row with submit
    n_fields = length(form.fields)
    first_btn_field = n_fields + 1
    for i in n_fields:-1:1
        if form.fields[i].widget isa Button
            first_btn_field = i
        else
            break
        end
    end

    regular_fields = @view form.fields[1:first_btn_field-1]
    button_fields = @view form.fields[first_btn_field:end]

    # Build vertical constraints: regular fields + one button row
    constraints = Constraint[]
    for field in regular_fields
        push!(constraints, Fixed(_form_field_height(field.widget)))
    end
    # Button row height: max of all button heights + submit
    btn_h = button_height(form.submit_button.button_style.decoration)
    if !isempty(button_fields)
        btn_h = max(btn_h, maximum(_form_field_height(f.widget) for f in button_fields))
    end
    push!(constraints, Fixed(btn_h))

    layout = Layout(Vertical, constraints; spacing=1)
    areas = split_layout(layout, content_area)

    label_style = tstyle(:text_dim)
    focused_label_style = tstyle(:accent, bold=true)
    cur_widget = current(form.focus)

    # Render regular (non-button) fields with label + widget
    for (i, field) in enumerate(regular_fields)
        i > length(areas) && break
        field_area = areas[i]
        field_area.height < 1 && continue

        is_focused = field.widget === cur_widget
        label_text = field.label
        if field.required
            label_text = string(label_text, "*")
        end
        ls = is_focused ? focused_label_style : label_style
        set_string!(buf, field_area.x, field_area.y, label_text, ls;
                    max_x=field_area.x + lw - 1)

        w_rect = Rect(field_area.x + lw, field_area.y,
                      field_area.width - lw, field_area.height)
        render(field.widget, w_rect, buf)
    end

    # Render button row: trailing Button fields + submit in horizontal layout
    btn_row_idx = length(regular_fields) + 1
    if btn_row_idx <= length(areas)
        btn_row_area = areas[btn_row_idx]
        all_buttons = Any[f.widget for f in button_fields]
        push!(all_buttons, form.submit_button)

        n_btns = length(all_buttons)
        h_constraints = Constraint[Fill() for _ in 1:n_btns]
        h_layout = Layout(Horizontal, h_constraints; spacing=2)
        btn_areas = split_layout(h_layout, btn_row_area)

        for (j, btn) in enumerate(all_buttons)
            j > length(btn_areas) && break
            render(btn, btn_areas[j], buf)
        end
    end
end
