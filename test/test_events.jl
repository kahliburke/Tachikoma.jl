    @testset "KeyEvent" begin
        ke = T.KeyEvent('a')
        @test ke.key == :char
        @test ke.char == 'a'

        esc = T.KeyEvent(:escape)
        @test esc.key == :escape
    end

    @testset "Event hierarchy" begin
        @test T.KeyEvent <: T.Event
        @test T.MouseEvent <: T.Event
        ke = T.KeyEvent('a')
        @test ke isa T.Event
        me = T.MouseEvent(10, 5, T.mouse_left, T.mouse_press, false, false, false)
        @test me isa T.Event
    end

    @testset "SGR mouse parsing" begin
        # Left click at (10, 20)
        params_left = Vector{UInt8}(codeunits("<0;10;20"))
        evt = T.csi_to_key(params_left, 'M')
        @test evt isa T.MouseEvent
        @test evt.x == 10
        @test evt.y == 20
        @test evt.button == T.mouse_left
        @test evt.action == T.mouse_press
        @test !evt.shift && !evt.alt && !evt.ctrl

        # Left release
        evt_rel = T.csi_to_key(params_left, 'm')
        @test evt_rel isa T.MouseEvent
        @test evt_rel.action == T.mouse_release
        @test evt_rel.button == T.mouse_left

        # Right click at (5, 3)
        params_right = Vector{UInt8}(codeunits("<2;5;3"))
        evt_r = T.csi_to_key(params_right, 'M')
        @test evt_r isa T.MouseEvent
        @test evt_r.button == T.mouse_right
        @test evt_r.action == T.mouse_press

        # Middle click
        params_mid = Vector{UInt8}(codeunits("<1;1;1"))
        evt_m = T.csi_to_key(params_mid, 'M')
        @test evt_m isa T.MouseEvent
        @test evt_m.button == T.mouse_middle

        # Scroll up
        params_su = Vector{UInt8}(codeunits("<64;15;10"))
        evt_su = T.csi_to_key(params_su, 'M')
        @test evt_su isa T.MouseEvent
        @test evt_su.button == T.mouse_scroll_up

        # Scroll down
        params_sd = Vector{UInt8}(codeunits("<65;15;10"))
        evt_sd = T.csi_to_key(params_sd, 'M')
        @test evt_sd isa T.MouseEvent
        @test evt_sd.button == T.mouse_scroll_down

        # Ctrl+click (ctrl bit = 16, so Cb = 0 + 16 = 16)
        params_ctrl = Vector{UInt8}(codeunits("<16;8;4"))
        evt_ctrl = T.csi_to_key(params_ctrl, 'M')
        @test evt_ctrl isa T.MouseEvent
        @test evt_ctrl.button == T.mouse_left
        @test evt_ctrl.ctrl
        @test !evt_ctrl.shift && !evt_ctrl.alt

        # Shift+Alt+click (shift=4, alt=8 → Cb = 0 + 4 + 8 = 12)
        params_sa = Vector{UInt8}(codeunits("<12;1;1"))
        evt_sa = T.csi_to_key(params_sa, 'M')
        @test evt_sa isa T.MouseEvent
        @test evt_sa.shift && evt_sa.alt && !evt_sa.ctrl

        # Left drag (base = 32)
        params_drag = Vector{UInt8}(codeunits("<32;20;15"))
        evt_drag = T.csi_to_key(params_drag, 'M')
        @test evt_drag isa T.MouseEvent
        @test evt_drag.button == T.mouse_left
        @test evt_drag.action == T.mouse_drag

        # Malformed input returns KeyEvent(:unknown)
        params_bad = Vector{UInt8}(codeunits("<;10"))
        evt_bad = T.csi_to_key(params_bad, 'M')
        @test evt_bad isa T.KeyEvent
        @test evt_bad.key == :unknown
    end

    @testset "MouseEvent backward compat" begin
        # A model that only handles KeyEvent should silently ignore MouseEvent
        mutable struct _TestKeyOnlyModel <: T.Model
            quit::Bool
        end
        T.should_quit(m::_TestKeyOnlyModel) = m.quit
        m = _TestKeyOnlyModel(false)
        me = T.MouseEvent(1, 1, T.mouse_left, T.mouse_press, false, false, false)
        # Should not error — falls through to default update!(::Model, ::Event)
        T.update!(m, me)
        @test !m.quit  # state unchanged
    end

    @testset "Rect contains" begin
        r = T.Rect(5, 10, 20, 10)
        # Inside
        @test Base.contains(r, 5, 10)   # top-left corner
        @test Base.contains(r, 24, 19)  # bottom-right corner
        @test Base.contains(r, 15, 15)  # middle
        # Outside
        @test !Base.contains(r, 4, 10)  # left of
        @test !Base.contains(r, 25, 10) # right of
        @test !Base.contains(r, 5, 9)   # above
        @test !Base.contains(r, 5, 20)  # below
    end

    @testset "Terminal mouse_enabled" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        @test term.mouse_enabled

        # toggle_mouse! flips state (writes escape codes to stdout)
        redirect_stdout(devnull) do
            T.toggle_mouse!(term)
        end
        @test !term.mouse_enabled

        redirect_stdout(devnull) do
            T.toggle_mouse!(term)
        end
        @test term.mouse_enabled
    end

    @testset "AppOverlay" begin
        ov = T.AppOverlay()
        @test !ov.show_theme
        @test !ov.show_help
        @test ov.theme_idx == 1
    end

    @testset "Default bindings: Ctrl+G mouse toggle" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        # Ctrl+G should toggle mouse and return true
        evt = T.KeyEvent(:ctrl, 'g')
        handled = redirect_stdout(devnull) do
            T.handle_default_binding!(term, ov, _DummyModel(),evt)
        end
        @test handled
        @test !term.mouse_enabled
    end

    @testset "Default bindings: Ctrl+\\ opens theme" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        # Ctrl+\ (byte 0x1c → char '|') opens theme overlay
        evt = T.KeyEvent(:ctrl, '|')
        @test T.handle_default_binding!(term, ov, _DummyModel(),evt)
        @test ov.show_theme

        # Arrow down cycles theme
        ov.theme_idx = 1
        T.set_theme!(T.ALL_THEMES[1])
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:down))
        @test ov.theme_idx == 2
        @test T.theme() === T.ALL_THEMES[2]

        # Arrow up wraps around
        ov.theme_idx = 1
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:up))
        @test ov.theme_idx == length(T.ALL_THEMES)

        # Escape closes
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:escape))
        @test !ov.show_theme

        T.set_theme!(T.KOKAKU)  # restore
    end

    @testset "Default bindings: Ctrl+? opens help" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        # Ctrl+? (byte 0x1f → char '\x7f') opens help
        evt = T.KeyEvent(:ctrl, '\x7f')
        @test T.handle_default_binding!(term, ov, _DummyModel(),evt)
        @test ov.show_help

        # Escape closes
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:escape))
        @test !ov.show_help
    end

    @testset "Default bindings: unhandled returns false" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        # Regular key 'a' is not a default binding
        @test !T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent('a'))
        # Arrow key is not a default binding when no overlay is open
        @test !T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:up))
    end

    @testset "Theme overlay render" begin
        T.set_theme!(T.KOKAKU)
        ov = T.AppOverlay()
        ov.show_theme = true
        ov.theme_idx = 1
        buf = T.Buffer(T.Rect(1, 1, 60, 30))
        frame = T.Frame(buf, T.Rect(1, 1, 60, 30), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render_overlay!(ov, frame)
        # Should render heavy border
        found_heavy = false
        for c in buf.content
            if c.char == '┏' || c.char == '┓'
                found_heavy = true
                break
            end
        end
        @test found_heavy
        T.set_theme!(T.KOKAKU)
    end

    @testset "Help overlay render" begin
        ov = T.AppOverlay()
        ov.show_help = true
        buf = T.Buffer(T.Rect(1, 1, 60, 30))
        frame = T.Frame(buf, T.Rect(1, 1, 60, 30), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render_overlay!(ov, frame)
        # Should render heavy border
        found_heavy = false
        for c in buf.content
            if c.char == '┏' || c.char == '┓'
                found_heavy = true
                break
            end
        end
        @test found_heavy
    end

    @testset "Theme persistence" begin
        # save_theme writes to LocalPreferences.toml
        T.save_theme("esper")
        # load_theme! should set theme from saved preference
        T.load_theme!()
        @test T.theme().name == "esper"

        # Restore
        T.save_theme("kokaku")
        T.load_theme!()
        @test T.theme().name == "kokaku"
    end

    @testset "HELP_LINES" begin
        @test length(T.HELP_LINES) >= 4
        @test any(occursin("Ctrl+A", l) for l in T.HELP_LINES)
        @test any(occursin("Ctrl+G", l) for l in T.HELP_LINES)
        @test any(occursin("Ctrl+\\", l) for l in T.HELP_LINES)
        @test any(occursin("Ctrl+?", l) for l in T.HELP_LINES)
    end

    @testset "Animations preference" begin
        # Save current state
        orig = T.ANIMATIONS_ENABLED[]

        T.ANIMATIONS_ENABLED[] = true
        @test T.animations_enabled()
        T.toggle_animations!()
        @test !T.animations_enabled()
        T.toggle_animations!()
        @test T.animations_enabled()

        # Restore
        T.ANIMATIONS_ENABLED[] = orig
    end

    @testset "Default bindings: Ctrl+S opens settings" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        # Ctrl+S (byte 0x13 → char 's') opens settings
        evt = T.KeyEvent(:ctrl, 's')
        @test T.handle_default_binding!(term, ov, _DummyModel(),evt)
        @test ov.show_settings
        @test ov.settings_idx == 1

        # Arrow down navigates
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:down))
        @test ov.settings_idx == 2

        # Arrow up wraps
        ov.settings_idx = 1
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:up))
        @test ov.settings_idx == length(T.SETTINGS_ITEMS)

        # Escape closes
        T.handle_default_binding!(term, ov, _DummyModel(),T.KeyEvent(:escape))
        @test !ov.show_settings
    end

    @testset "Default bindings: Ctrl+A toggles animations" begin
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), devnull, false, T.gfx_none, nothing)
        ov = T.AppOverlay()

        orig = T.ANIMATIONS_ENABLED[]
        T.ANIMATIONS_ENABLED[] = true
        evt = T.KeyEvent(:ctrl, 'a')
        @test T.handle_default_binding!(term, ov, _DummyModel(),evt)
        @test !T.animations_enabled()
        T.handle_default_binding!(term, ov, _DummyModel(),evt)
        @test T.animations_enabled()
        T.ANIMATIONS_ENABLED[] = orig
    end

    @testset "Terminal io field" begin
        # Default keyword constructor uses stdout
        t = T.Terminal()
        @test t.io === stdout

        # Custom io
        buf_io = IOBuffer()
        t2 = T.Terminal(io=buf_io)
        @test t2.io === buf_io

        # toggle_mouse writes to term.io, not stdout
        io_capture = IOBuffer()
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), io_capture, false, T.gfx_none, nothing)
        T.toggle_mouse!(term)
        output = String(take!(io_capture))
        @test occursin("1000", output)  # mouse escape codes contain 1000
        @test !term.mouse_enabled
    end

    @testset "draw! writes to t.io" begin
        io_capture = IOBuffer()
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, false, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), io_capture, false, T.gfx_none, nothing)
        T.draw!(term) do f
            # render nothing, just test IO routing
        end
        output = String(take!(io_capture))
        # Should contain sync start/end sequences
        @test occursin("2026h", output)  # SYNC_START
        @test occursin("2026l", output)  # SYNC_END
    end

    @testset "check_resize! writes to t.io" begin
        io_capture = IOBuffer()
        sz = T.terminal_size()
        # Make terminal size different from actual to force resize
        rect = T.Rect(1, 1, 10, 5)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, false, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), io_capture, false, T.gfx_none, nothing)
        T.check_resize!(term)
        output = String(take!(io_capture))
        # If terminal size differs from 10x5, it should have written clear screen
        if sz.cols != 10 || sz.rows != 5
            @test occursin("[2J", output)  # CLEAR_SCREEN
        end
    end

    @testset "enter_tui!/leave_tui! write to t.io" begin
        io_capture = IOBuffer()
        sz = T.terminal_size()
        rect = T.Rect(1, 1, sz.cols, sz.rows)
        term = T.Terminal([T.Buffer(rect), T.Buffer(rect)], 1, rect, true, false, NTuple{4,Int}[], 0, 300, T.CastRecorder(), io_capture, false, T.gfx_none, nothing)

        # enter_tui! writes alt screen, cursor hide, mouse enable to t.io
        # (start_input! may fail since stdin isn't a TTY, but escape sequences write first)
        try T.enter_tui!(term) catch end
        enter_output = String(take!(io_capture))
        @test occursin("1049h", enter_output)  # ALT_SCREEN_ON
        @test occursin("?25l", enter_output)    # CURSOR_HIDE

        # leave_tui! writes mouse off, cursor show, alt screen off
        try T.leave_tui!(term) catch end
        leave_output = String(take!(io_capture))
        @test occursin("1049l", leave_output)  # ALT_SCREEN_OFF
        @test occursin("?25h", leave_output)    # CURSOR_SHOW
    end

    @testset "KeyAction enum" begin
        @test T.key_press isa T.KeyAction
        @test T.key_repeat isa T.KeyAction
        @test T.key_release isa T.KeyAction
    end

    @testset "KeyEvent action field" begin
        # Default constructors produce key_press
        ke = T.KeyEvent('a')
        @test ke.action == T.key_press

        ke2 = T.KeyEvent(:up)
        @test ke2.action == T.key_press

        ke3 = T.KeyEvent(:ctrl, 'g')
        @test ke3.action == T.key_press

        # Explicit action constructors
        ke4 = T.KeyEvent(:up, T.key_release)
        @test ke4.key == :up
        @test ke4.action == T.key_release

        ke5 = T.KeyEvent('a', T.key_repeat)
        @test ke5.key == :char
        @test ke5.char == 'a'
        @test ke5.action == T.key_repeat

        # Full 3-arg constructor
        ke6 = T.KeyEvent(:ctrl, 'g', T.key_release)
        @test ke6.key == :ctrl
        @test ke6.char == 'g'
        @test ke6.action == T.key_release
    end

    @testset "Kitty CSI u parsing" begin
        # Simple keypress: 'a' with no modifiers (CSI 97 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97")))
        @test evt.key == :char
        @test evt.char == 'a'
        @test evt.action == T.key_press

        # 'a' with explicit press (CSI 97;1:1 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97;1:1")))
        @test evt.key == :char && evt.char == 'a' && evt.action == T.key_press

        # 'a' repeat (CSI 97;1:2 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97;1:2")))
        @test evt.action == T.key_repeat

        # 'a' release (CSI 97;1:3 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97;1:3")))
        @test evt.action == T.key_release

        # Ctrl+C (CSI 99;5 u → modifiers=5, (5-1)&4=4 → ctrl)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("99;5")))
        @test evt.key == :ctrl_c
        @test evt.action == T.key_press

        # Ctrl+C release (CSI 99;5:3 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("99;5:3")))
        @test evt.key == :ctrl_c
        @test evt.action == T.key_release

        # Ctrl+G (CSI 103;5 u → :ctrl + 'g', matching legacy pattern)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("103;5")))
        @test evt.key == :ctrl
        @test evt.char == 'g'
        @test evt.action == T.key_press

        # Ctrl+\ (CSI 92;5 u → :ctrl + '|', legacy byte 0x1c)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("92;5")))
        @test evt.key == :ctrl
        @test evt.char == '|'
        @test evt.action == T.key_press

        # Ctrl+/ (CSI 47;5 u → :ctrl + '\x7f', legacy byte 0x1f)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("47;5")))
        @test evt.key == :ctrl
        @test evt.char == '\x7f'
        @test evt.action == T.key_press

        # Ctrl+] (CSI 93;5 u → :ctrl + '}', legacy byte 0x1d)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("93;5")))
        @test evt.key == :ctrl
        @test evt.char == '}'
        @test evt.action == T.key_press

        # Escape (CSI 27 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("27")))
        @test evt.key == :escape

        # Enter (CSI 13 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("13")))
        @test evt.key == :enter

        # Tab (CSI 9 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("9")))
        @test evt.key == :tab

        # Shift+Tab → backtab (CSI 9;2 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("9;2")))
        @test evt.key == :backtab

        # Backspace (CSI 127 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("127")))
        @test evt.key == :backspace

        # Space (CSI 32 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("32")))
        @test evt.key == :char && evt.char == ' '

        # Ctrl+Space (CSI 32;5 u)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("32;5")))
        @test evt.key == :ctrl_space

        # Functional keycodes: F1 (57364)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("57364")))
        @test evt.key == :f1

        # Functional keycodes: F12 (57375)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("57375")))
        @test evt.key == :f12

        # Functional keycodes: Delete (57349)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("57349")))
        @test evt.key == :delete

        # Keycode with shifted key sub-param (e.g. 97:65 → base=97='a')
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97:65;1")))
        @test evt.key == :char && evt.char == 'a'

        # Shift+f → uppercase 'F' (CSI 102;2 u, modifier=2 → shift)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("102;2")))
        @test evt.key == :char && evt.char == 'F' && evt.action == T.key_press

        # Shift+a → uppercase 'A'
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("97;2")))
        @test evt.key == :char && evt.char == 'A'

        # Shift+z → uppercase 'Z'
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("122;2")))
        @test evt.key == :char && evt.char == 'Z'

        # Ctrl+Shift+f stays lowercase (CSI 102;6 u, modifier=6 → shift+ctrl)
        # Falls through to printable since ctrl handler requires !shift
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("102;6")))
        @test evt.key == :char && evt.char == 'f'

        # Alt+Shift+f stays lowercase (CSI 102;4 u, modifier=4 → shift+alt)
        evt = T.parse_kitty_key(Vector{UInt8}(codeunits("102;4")))
        @test evt.key == :char && evt.char == 'f'
    end

    @testset "CSI u dispatched from csi_to_key" begin
        evt = T.csi_to_key(Vector{UInt8}(codeunits("97;1:3")), 'u')
        @test evt isa T.KeyEvent
        @test evt.key == :char && evt.char == 'a' && evt.action == T.key_release
    end

    @testset "Action extraction from legacy CSI with Kitty event type" begin
        # Up arrow release: params "1;1:3", final 'A'
        evt = T.csi_to_key(Vector{UInt8}(codeunits("1;1:3")), 'A')
        @test evt.key == :up
        @test evt.action == T.key_release

        # Down arrow repeat: params "1;1:2", final 'B'
        evt = T.csi_to_key(Vector{UInt8}(codeunits("1;1:2")), 'B')
        @test evt.key == :down
        @test evt.action == T.key_repeat

        # Bare arrow (legacy, no params): final 'A'
        evt = T.csi_to_key(UInt8[], 'A')
        @test evt.key == :up
        @test evt.action == T.key_press

        # Delete release: params "3;1:3", final '~'
        evt = T.csi_to_key(Vector{UInt8}(codeunits("3;1:3")), '~')
        @test evt.key == :delete
        @test evt.action == T.key_release

        # F5 press (legacy): params "15", final '~'
        evt = T.csi_to_key(Vector{UInt8}(codeunits("15")), '~')
        @test evt.key == :f5
        @test evt.action == T.key_press
    end

    @testset "Backward compat: SGR mouse still works with new csi_to_key" begin
        params = Vector{UInt8}(codeunits("<0;10;20"))
        evt = T.csi_to_key(params, 'M')
        @test evt isa T.MouseEvent
        @test evt.button == T.mouse_left
    end

