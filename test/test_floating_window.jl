@testset "FloatingWindow + WindowManager" begin
    mutable struct _MouseSink
        hits::Int
        last_button::T.MouseButton
    end
    _MouseSink() = _MouseSink(0, T.mouse_none)

    mutable struct _KeySink
        hits::Int
    end

    T.handle_mouse!(s::_MouseSink, evt::T.MouseEvent) = begin
        s.hits += 1
        s.last_button = evt.button
        true
    end
    T.handle_key!(s::_KeySink, evt::T.KeyEvent) = begin
        if evt.key == :enter
            s.hits += 1
            return true
        end
        false
    end

    @testset "wheel forwarding to content" begin
        wm = T.WindowManager()
        sink = _MouseSink()
        push!(wm, T.FloatingWindow(x=1, y=1, width=20, height=8, content=sink))
        evt = T.MouseEvent(5, 3, T.mouse_scroll_down, T.mouse_press, false, false, false)
        @test T.handle_mouse!(wm, evt)
        @test sink.hits == 1
        @test sink.last_button == T.mouse_scroll_down
    end

    @testset "content state clears after delete + release" begin
        wm = T.WindowManager()
        sink = _MouseSink()
        push!(wm, T.FloatingWindow(x=1, y=1, width=20, height=8, content=sink))

        press_evt = T.MouseEvent(4, 3, T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_mouse!(wm, press_evt)
        @test wm._content_active
        @test wm._content_win == 1

        deleteat!(wm, 1)
        release_evt = T.MouseEvent(4, 3, T.mouse_left, T.mouse_release, false, false, false)
        @test T.handle_mouse!(wm, release_evt)
        @test !wm._content_active
        @test wm._content_win == 0
    end

    @testset "title drag and corner resize" begin
        wm = T.WindowManager()
        win = T.FloatingWindow(x=1, y=1, width=20, height=8)
        push!(wm, win)

        # Drag from title row
        press_drag = T.MouseEvent(5, 1, T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_mouse!(wm, press_drag)
        @test wm._dragging

        drag_evt = T.MouseEvent(11, 4, T.mouse_left, T.mouse_drag, false, false, false)
        @test T.handle_mouse!(wm, drag_evt)
        @test win.x == 7
        @test win.y == 4

        release_drag = T.MouseEvent(11, 4, T.mouse_left, T.mouse_release, false, false, false)
        @test T.handle_mouse!(wm, release_drag)
        @test !wm._dragging

        # Resize from bottom-right corner
        press_resize = T.MouseEvent(T.right(T.window_rect(win)), T.bottom(T.window_rect(win)),
                                    T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_mouse!(wm, press_resize)
        @test wm._resizing

        drag_resize = T.MouseEvent(T.right(T.window_rect(win)) + 4, T.bottom(T.window_rect(win)) + 2,
                                   T.mouse_left, T.mouse_drag, false, false, false)
        @test T.handle_mouse!(wm, drag_resize)
        @test win.width == 24
        @test win.height == 10

        release_resize = T.MouseEvent(1, 1, T.mouse_left, T.mouse_release, false, false, false)
        @test T.handle_mouse!(wm, release_resize)
        @test !wm._resizing
    end

    @testset "focus/z-order and key delegation" begin
        wm = T.WindowManager()
        push!(wm, T.FloatingWindow(id=:a, x=1, y=1, width=10, height=5))
        push!(wm, T.FloatingWindow(id=:b, x=15, y=1, width=10, height=5))
        sink = _KeySink(0)
        push!(wm, T.FloatingWindow(id=:c, x=30, y=1, width=10, height=5, content=sink))

        @test T.focused_window(wm).id == :c
        @test T.handle_key!(wm, T.KeyEvent(:enter))
        @test sink.hits == 1

        T.focus_next!(wm)
        @test T.focused_window(wm).id == :a
        T.focus_prev!(wm)
        @test T.focused_window(wm).id == :c

        click_b = T.MouseEvent(16, 2, T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_mouse!(wm, click_b)
        @test T.focused_window(wm).id == :b
        @test wm.windows[end].id == :b
    end

    @testset "focus shortcuts default and opt-out" begin
        wm = T.WindowManager()
        push!(wm, T.FloatingWindow(id=:a, x=1, y=1, width=10, height=5))
        push!(wm, T.FloatingWindow(id=:b, x=15, y=1, width=10, height=5))

        @test T.focused_window(wm).id == :b
        # Ctrl+J cycles focus to next window
        @test T.handle_key!(wm, T.KeyEvent(:ctrl, 'j'))
        @test T.focused_window(wm).id == :a

        wm_no_shortcuts = T.WindowManager(focus_shortcuts=false)
        push!(wm_no_shortcuts, T.FloatingWindow(id=:a, x=1, y=1, width=10, height=5))
        push!(wm_no_shortcuts, T.FloatingWindow(id=:b, x=15, y=1, width=10, height=5))
        @test T.focused_window(wm_no_shortcuts).id == :b
        @test !T.handle_key!(wm_no_shortcuts, T.KeyEvent(:ctrl, 'j'))
        @test T.focused_window(wm_no_shortcuts).id == :b

        # Ctrl+K cycles focus to previous window
        @test T.handle_key!(wm, T.KeyEvent(:ctrl, 'k'))
        @test T.focused_window(wm).id == :b
    end

    @testset "tile/cascade layout geometry" begin
        wm = T.WindowManager()
        for i in 1:4
            push!(wm, T.FloatingWindow(id=Symbol("w", i), x=i, y=i, width=12, height=6))
        end
        area = T.Rect(1, 1, 80, 24)

        T.tile!(wm, area; animate=false)
        for w in wm.windows
            @test w.x >= area.x
            @test w.y >= area.y
            @test w.width >= 10
            @test w.height >= 5
        end

        T.cascade!(wm, area; animate=false)
        @test wm.windows[2].x - wm.windows[1].x == 3
        @test wm.windows[2].y - wm.windows[1].y == 2
    end

    @testset "step! handles tick and periodic layout" begin
        wm = T.WindowManager()
        for i in 1:3
            push!(wm, T.FloatingWindow(id=Symbol("w", i), x=1, y=1, width=12, height=6))
        end
        area = T.Rect(1, 1, 60, 20)

        @test T.step!(wm, area; layout_interval=4, layout_tile_at=1, layout_cascade_at=3, layout_animate=false, layout_duration=4) == 1
        @test T.tick(wm) == 1
        @test wm.windows[1].x == 1
        @test wm.windows[1].y == 1

        @test T.step!(wm, area; layout_interval=4, layout_tile_at=1, layout_cascade_at=3, layout_animate=false, layout_duration=4) == 2
        @test wm.windows[1].x == 1
        @test wm.windows[1].y == 1

        @test T.step!(wm, area; layout_interval=4, layout_tile_at=1, layout_cascade_at=3, layout_animate=false, layout_duration=4) == 3
        @test wm.windows[2].x - wm.windows[1].x == 3
        @test wm.windows[2].y - wm.windows[1].y == 2
    end
end
