# Window Manager

`WindowManager` and `FloatingWindow` let you compose multiple independent widgets into an overlapping desktop-like layout.
Windows can be positioned, moved, resized, focused, stacked, and animated between layouts while still forwarding keyboard/mouse input to their content widgets.

## When to use this

Use `FloatingWindow` when your UI has independent panels that should not consume fixed slots in a single layout:

- Floating telemetry/monitor dashboards
- Popup detail panels on demand
- Editor-style tools with resizable panes
- Debug/overlay tooling where popups are expected to overlap

If you want a strict single-flow layout instead, prefer container-based layouts from [`layout.md`](layout.md) instead of windowing.

## Basic pieces

`FloatingWindow` represents one draggable window:

- `content` is usually a widget (`TextArea`, `Form`, `ScrollPane`, etc.).
- `on_render(inner, buf, focused, frame)` lets you draw arbitrary content manually. `frame` is the current `Frame` (or `nothing` when called outside a frame context) and enables pixel graphics such as `PixelImage`, kitty, and sixel rendering inside the window.
- `x/y/width/height` define geometry in absolute terminal coordinates.
- `border_color`, `bg_color`, `box`, `resizable`, and `opacity` tune the look and behavior.

`WindowManager` stores all windows and arbitrates:

- focus stack and z-order
- mouse routing to title bar, resize handles, close buttons, and content areas
- keyboard dispatch to focused content
- layout helpers (`tile!`, `cascade!`)

## Minimal windowing example

Two overlapping windows with animated tile and cascade layout transitions.

<!-- tachi:app window_manager_minimal_demo w=56 h=18 frames=180 fps=15 -->

Forward all events to the manager in `update!` and render in `view`:

<!-- tachi:noeval -->
```julia
function Tachikoma.update!(m::MyModel, evt::Tachikoma.Event)
    Tachikoma.handle_event!(m.wm, evt)
end

function Tachikoma.view(m::MyModel, f::Tachikoma.Frame)
    Tachikoma.render(m.wm, f.area, f.buffer)
end
```

## Keyboard and focus behavior

Window focus is managed by `WindowManager` itself.

<!-- tachi:noeval -->
```julia
focus_next!(wm)                  # cycle forward
focus_prev!(wm)                  # cycle backward
focused_window(wm)               # current focused window
bring_to_front!(wm, idx)         # promote a window index
window_rect(wm.windows[idx])     # query geometry if needed
```

By default, `Ctrl+J` / `Ctrl+K` cycle focus forward/backward. Pass `focus_shortcuts=false` to disable them and handle focus yourself.

## Mouse and input forwarding

The manager keeps one interaction model for all windows:

- `mouse_press` on the title bar drags the window
- `mouse_press` on corner handles resizes the window
- scroll wheel (`mouse_scroll_up/down`) is forwarded to the active content widget if possible
- clicking the title bar close glyph closes closeable windows
- clicking content forwards to the underlying widget after hit-testing

Content widgets keep their own key and mouse bindings — the manager forwards events transparently.

## Layout helpers

Use layout commands when you want automatic repositioning:

- `tile!(wm, area; animate=true, duration=15)`
- `cascade!(wm, area; animate=true, duration=15)`

These commands compute new geometry for all managed windows in a deterministic order, then optionally animate transitions.

## Opacity

Windows support semi-transparency via the `opacity` parameter (0.0 = fully transparent, 1.0 = fully opaque). When a window overlaps other content, both its background and the underlying foreground text are composited: the background blends toward the window's color and the foreground fades proportionally, so content behind the window becomes progressively less visible as opacity increases.

<!-- tachi:app window_opacity_demo w=60 h=18 frames=180 fps=15 -->

The global default is 95% and applies to all new windows. Adjust it at runtime or via the **Ctrl+S** settings overlay:

<!-- tachi:noeval -->
```julia
Tachikoma.set_window_opacity!(0.85)   # set and persist
Tachikoma.window_opacity()             # read current value
```

Per-window `opacity` overrides the global default when specified explicitly.

## Window manager demo

<!-- tachi:app window_manager_demo w=68 h=22 frames=180 fps=15 -->
```julia
import Tachikoma

@kwdef mutable struct _WMAnim <: Tachikoma.Model
    wm::Tachikoma.WindowManager = Tachikoma.WindowManager()
    tick::Int = 0
    area::Union{Tachikoma.Rect, Nothing} = nothing
end

function Tachikoma.update!(m::_WMAnim, evt::Tachikoma.Event)
    if evt isa Tachikoma.KeyEvent && evt.key == :char && m.area !== nothing
        evt.char == 't' && return Tachikoma.tile!(m.wm, m.area; animate=true, duration=15)
        evt.char == 'c' && return Tachikoma.cascade!(m.wm, m.area; animate=true, duration=15)
        evt.char == 'f' && return Tachikoma.focus_next!(m.wm)
    end
    Tachikoma.handle_event!(m.wm, evt)
end

function _ensure_demo_windows!(wm::Tachikoma.WindowManager)
    isempty(wm.windows) || return
    push!(wm, Tachikoma.FloatingWindow(
        id=:log,
        title="Log",
        x=3, y=2, width=30, height=10, opacity=0.85,
        border_color=Tachikoma.ColorRGB(0x80, 0xb0, 0xe0),
        content=Tachikoma.ScrollPane(["Log entry $i" for i in 1:40]; following=true)
    ))
    push!(wm, Tachikoma.FloatingWindow(
        id=:stats,
        title="Stats",
        x=18, y=9, width=32, height=10, opacity=0.9,
        border_color=Tachikoma.ColorRGB(0x90, 0xd0, 0x80),
        on_render=(area, buf, focused, frame) -> begin
            # area::Rect  = content region inside the border
            # buf::Buffer = draw target
            # frame       = current Frame (nothing when called without a Frame context)
            s = focused ? Tachikoma.tstyle(:accent) : Tachikoma.tstyle(:text_dim)
            Tachikoma.set_string!(buf, area.x+1, area.y,   "focused: $focused", s)
            Tachikoma.set_string!(buf, area.x+1, area.y+1, "size: $(area.width)×$(area.height)", s)
            Tachikoma.set_string!(buf, area.x+1, area.y+2, "pos: $(area.x),$(area.y)", s)
        end
    ))
    push!(wm, Tachikoma.FloatingWindow(
        id=:notes,
        title="Notes",
        x=38, y=4, width=26, height=12, opacity=0.8,
        border_color=Tachikoma.ColorRGB(0xd0, 0xa0, 0xff),
        content=Tachikoma.ScrollPane(["Note $i" for i in 1:20]; following=true)
    ))
end

function Tachikoma.view(m::_WMAnim, f::Tachikoma.Frame)
    m.tick += 1
    m.area = f.area
    _ensure_demo_windows!(m.wm)
    Tachikoma.render(m.wm, f.area, f.buffer; tick=m.tick)
end

Tachikoma.app(_WMAnim())
```

## API summary

- `WindowManager()`
- `WindowManager(focus_shortcuts::Bool)`
- `push!(wm, window)`
- `deleteat!(wm, idx)`
- `focus_next!(wm)`, `focus_prev!(wm)`
- `focused_window(wm)`
- `bring_to_front!(wm, idx)`
- `handle_event!(wm, evt::Event)`
- `step!(wm, area; layout_interval=0, layout_tile_at=1, layout_cascade_at=23, layout_animate=true, layout_duration=12)`
- `tick(wm)`
- `tile!(wm, area; animate=true, duration=15)`
- `cascade!(wm, area; animate=true, duration=15)`
- `window_opacity()`, `set_window_opacity!(v)`
- `FloatingWindow(; id, title, x, y, width, height, content, box, opacity, bg_color, border_color, resizable=true, closeable=false, on_close=nothing, on_render=nothing)` — `on_render` signature: `(inner::Rect, buf::Buffer, focused::Bool, frame) -> nothing`; `frame` is `nothing` when called outside a Frame context
