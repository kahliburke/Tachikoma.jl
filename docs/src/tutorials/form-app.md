# Build a Form

This tutorial builds a registration form with text input, checkboxes, radio buttons, a dropdown, validation, and a live preview panel.

## What We'll Build

A two-panel app: a form on the left with Tab/Shift-Tab navigation, and a live preview on the right showing the current form values and validation state.

<!-- tachi:begin form_app -->

## Step 1: Define the Model

```julia
using Tachikoma

function build_form(tick)
    Form([
        FormField("Name", TextInput(; text="", focused=true, tick=tick,
                    validator=s -> length(s) < 2 ? "Min 2 chars" : nothing);
                    required=true),
        FormField("Bio",    TextArea(; text="", focused=false, tick=tick)),
        FormField("Notify", Checkbox("Enable notifications"; focused=false)),
        FormField("Role",   RadioGroup(["Admin", "Editor", "Viewer"])),
        FormField("Region", DropDown(["Tokyo", "Berlin", "NYC", "London",
                                      "São Paulo", "Sydney"])),
    ];
        submit_label="Submit",
        block=Block(title="Registration", border_style=tstyle(:border),
                    title_style=tstyle(:title)),
        tick=tick,
    )
end

@kwdef mutable struct FormApp <: Model
    quit::Bool = false
    tick::Int = 0
    form::Form = build_form(0)
    submitted::Bool = false
    flash::Int = 0
end

should_quit(m::FormApp) = m.quit
```

Key points:
- Each `FormField` pairs a label with a widget
- The `validator` on TextInput returns `nothing` for valid input or an error message
- `required=true` means the field must pass validation for the form to be valid
- `submit_label` adds a submit button to the form

## Step 2: Handle Events

```julia
function update!(m::FormApp, evt::KeyEvent)
    # Ctrl+R resets the form
    if evt.key == :ctrl && evt.char == 'r'
        m.form = build_form(m.tick)
        m.submitted = false
        m.flash = 0
        return
    end

    # Check if submit button is focused and Enter is pressed
    cur = current(m.form.focus)
    is_submit = cur === m.form.submit_button &&
                (evt.key == :enter || (evt.key == :char && evt.char == ' '))

    # Let the form handle the key (Tab navigation, widget input)
    handled = handle_key!(m.form, evt)

    # If submit was pressed and form is valid, capture values
    if is_submit && handled && valid(m.form)
        m.submitted = true
        m.flash = 90  # show "Submitted!" for ~3 seconds
    end

    # If form didn't consume the key, handle app-level keys
    if !handled
        evt.key == :escape && (m.quit = true)
    end
end
```

The `Form` widget's `FocusRing` handles Tab/Shift-Tab navigation. Each widget gets key events when focused. Unhandled keys bubble up to your `update!`.

## Step 3: Render the View

```julia
function view(m::FormApp, f::Frame)
    m.tick += 1
    m.form.tick = m.tick
    m.flash > 0 && (m.flash -= 1)
    buf = f.buffer

    # Layout: header | body | footer
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    header, body, footer = rows[1], rows[2], rows[3]

    # Header
    set_string!(buf, header.x + 1, header.y, "Form Demo",
                tstyle(:title, bold=true))

    # Body: form (55%) + preview (45%)
    cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), body)
    form_area, preview_area = cols[1], cols[2]

    # Render the form
    render(m.form, form_area, buf)

    # Render the preview panel
    render_preview!(buf, preview_area, m)

    # Footer
    render(StatusBar(
        left=[Span("  [Tab/S-Tab] navigate  [Ctrl+R] reset ", tstyle(:text_dim))],
        right=[Span("[Esc] quit ", tstyle(:text_dim))],
    ), footer, buf)
end
```

## Step 4: The Preview Panel

```julia
function render_preview!(buf::Buffer, area::Rect, m::FormApp)
    block = Block(title="Preview", border_style=tstyle(:border),
                  title_style=tstyle(:title))
    inner = render(block, area, buf)
    inner.width < 4 && return

    y = inner.y

    # Validation indicator
    if valid(m.form)
        set_string!(buf, inner.x, y, "✓ Valid", tstyle(:success, bold=true))
    else
        set_string!(buf, inner.x, y, "✗ Invalid", tstyle(:error, bold=true))
    end
    y += 2

    # Flash message
    if m.flash > 0
        set_string!(buf, inner.x, y, "Submitted!", tstyle(:accent, bold=true))
        y += 2
    end

    # Display form values
    vals = value(m.form)   # Dict{String, Any}
    for (label, val) in sort(collect(vals); by=first)
        y > bottom(inner) && break
        display = val isa Bool ? (val ? "yes" : "no") :
                  val isa String && isempty(val) ? "(empty)" : string(val)
        set_string!(buf, inner.x, y, "$(label): ", tstyle(:text_dim))
        set_string!(buf, inner.x + length(label) + 2, y, display,
                    tstyle(:text); max_x=right(inner))
        y += 1
    end
end
```

## Step 5: Run It

<!-- tachi:app form_app w=80 h=24 frames=240 fps=15 chrome -->
```julia
app(FormApp())
```

## How It Works

1. **`Form`** wraps multiple `FormField`s and manages a `FocusRing`
2. **Tab/Shift-Tab** moves focus between fields; the focused widget gets keyboard events
3. **`value(form)`** returns a `Dict` mapping field labels to their widget values
4. **`valid(form)`** checks all required fields against their validators
5. **The preview** reads `value(form)` each frame for a live display

## Exercises

- Add a password field with a minimum length validator
- Add a confirmation step using `Modal` before showing "Submitted!"
- Add a `Calendar` field for selecting a date
- Style the form differently for valid vs invalid states
