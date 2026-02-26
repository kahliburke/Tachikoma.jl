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
)
    # Build focus ring from widgets + submit button
    widgets = Any[f.widget for f in fields]
    btn = Button(submit_label; focused=false, tick=tick)
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

function render(form::Form, rect::Rect, buf::Buffer)
    content_area = if form.block !== nothing
        render(form.block, rect, buf)
    else
        rect
    end
    (content_area.width < 8 || content_area.height < 2) && return

    lw = min(form.label_width, content_area.width ÷ 2)
    widget_x = content_area.x + lw
    widget_w = content_area.width - lw

    y = content_area.y
    label_style = tstyle(:text_dim)
    req_style = tstyle(:error)

    for (i, field) in enumerate(form.fields)
        y > bottom(content_area) - 1 && break

        # Label
        label_text = field.label
        if field.required
            label_text = string(label_text, "*")
        end
        set_string!(buf, content_area.x, y, label_text, label_style;
                    max_x=widget_x - 1)

        # Widget — determine height needed
        w = field.widget
        wh = 1
        if w isa TextArea
            wh = min(max(2, length(w.lines) + 1), content_area.height - (y - content_area.y) - 1)
        elseif w isa RadioGroup
            wh = min(length(w.labels), content_area.height - (y - content_area.y) - 1)
        elseif w isa TextInput && !isempty(w.error_msg)
            wh = 2
        elseif w isa DropDown && w.open
            vis = min(length(w.items), w.max_visible)
            wh = min(1 + vis, content_area.height - (y - content_area.y) - 1)
        end

        w_rect = Rect(widget_x, y, widget_w, wh)
        render(w, w_rect, buf)
        y += wh + 1  # +1 spacing between fields
    end

    # Submit button at bottom
    if y <= bottom(content_area)
        btn_rect = Rect(content_area.x, y, content_area.width, 1)
        render(form.submit_button, btn_rect, buf)
    end
end
