    # ═════════════════════════════════════════════════════════════════
    # ResizableLayout
    # ═════════════════════════════════════════════════════════════════

    @testset "ResizableLayout construction" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill(), T.Fixed(20)])
        @test length(rl.constraints) == 3
        @test length(rl.original_constraints) == 3
        @test rl.min_pane_size == 3
        @test rl.hover_border == 0
        @test rl.drag.status == T.drag_idle
    end

    @testset "ResizableLayout split_layout" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        area = T.Rect(1, 1, 80, 24)
        rects = T.split_layout(rl, area)
        @test length(rects) == 2
        @test rects[1].width == 30
        @test rects[2].width == 50
        @test rl.rects === rects
        @test rl.last_area === area
    end

    @testset "ResizableLayout border detection" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fixed(20), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))
        # Border 1 is at right(rects[1]) = 20
        @test T._find_border(rl, 20) == 1
        @test T._find_border(rl, 19) == 1  # ±1 hit zone
        @test T._find_border(rl, 21) == 1
        # Border 2 is at right(rects[2]) = 40
        @test T._find_border(rl, 40) == 2
        # Far away = no border
        @test T._find_border(rl, 60) == 0
    end

    @testset "ResizableLayout drag Fixed+Fixed" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fixed(50)])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))

        # Start drag at border (x=30)
        press = T.MouseEvent(30, 10, T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_resize!(rl, press)
        @test rl.drag.status == T.drag_active

        # Drag right by 10
        drag_evt = T.MouseEvent(40, 10, T.mouse_left, T.mouse_drag, false, false, false)
        @test T.handle_resize!(rl, drag_evt)

        # Release
        release = T.MouseEvent(40, 10, T.mouse_left, T.mouse_release, false, false, false)
        @test T.handle_resize!(rl, release)
        @test rl.drag.status == T.drag_idle

        # Constraints should have updated
        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[2] isa T.Fixed
        @test rl.constraints[1].size == 40
        @test rl.constraints[2].size == 40
    end

    @testset "ResizableLayout drag Fixed+Fill" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))

        press = T.MouseEvent(30, 10, T.mouse_left, T.mouse_press, false, false, false)
        T.handle_resize!(rl, press)

        drag_evt = T.MouseEvent(40, 10, T.mouse_left, T.mouse_drag, false, false, false)
        T.handle_resize!(rl, drag_evt)

        release = T.MouseEvent(40, 10, T.mouse_left, T.mouse_release, false, false, false)
        T.handle_resize!(rl, release)

        # Fixed grows, Fill stays Fill
        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[1].size == 40
        @test rl.constraints[2] isa T.Fill
    end

    @testset "ResizableLayout drag min_pane_size enforcement" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(10), T.Fixed(10)]; min_pane_size=5)
        T.split_layout(rl, T.Rect(1, 1, 20, 24))

        press = T.MouseEvent(10, 10, T.mouse_left, T.mouse_press, false, false, false)
        T.handle_resize!(rl, press)

        # Try to drag so far right that right pane would be < min_pane_size
        drag_evt = T.MouseEvent(18, 10, T.mouse_left, T.mouse_drag, false, false, false)
        T.handle_resize!(rl, drag_evt)

        release = T.MouseEvent(18, 10, T.mouse_left, T.mouse_release, false, false, false)
        T.handle_resize!(rl, release)

        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[2] isa T.Fixed
        @test rl.constraints[2].size >= 5
    end

    @testset "ResizableLayout reset" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))

        # Drag to modify
        press = T.MouseEvent(30, 10, T.mouse_left, T.mouse_press, false, false, false)
        T.handle_resize!(rl, press)
        drag_evt = T.MouseEvent(40, 10, T.mouse_left, T.mouse_drag, false, false, false)
        T.handle_resize!(rl, drag_evt)
        release = T.MouseEvent(40, 10, T.mouse_left, T.mouse_release, false, false, false)
        T.handle_resize!(rl, release)

        @test rl.constraints[1].size == 40

        T.reset_layout!(rl)
        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[1].size == 30
        @test rl.constraints[2] isa T.Fill
    end

    @testset "ResizableLayout vertical" begin
        rl = T.ResizableLayout(T.Vertical, [T.Fixed(10), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))
        @test rl.rects[1].height == 10
        @test rl.rects[2].height == 14

        # Border at bottom(rects[1]) = 10
        @test T._find_border(rl, 10) == 1

        press = T.MouseEvent(40, 10, T.mouse_left, T.mouse_press, false, false, false)
        T.handle_resize!(rl, press)

        drag_evt = T.MouseEvent(40, 15, T.mouse_left, T.mouse_drag, false, false, false)
        T.handle_resize!(rl, drag_evt)

        release = T.MouseEvent(40, 15, T.mouse_left, T.mouse_release, false, false, false)
        T.handle_resize!(rl, release)

        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[1].size == 15
    end

    @testset "ResizableLayout render_resize_handles!" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 5))
        buf = T.Buffer(T.Rect(1, 1, 40, 5))

        # No hover or drag — should not change buffer
        T.render_resize_handles!(buf, rl)
        @test buf.content[T.buf_index(buf, 20, 1)].char == ' '

        # Set hover
        rl.hover_border = 1
        T.render_resize_handles!(buf, rl)
        @test buf.content[T.buf_index(buf, 20, 1)].char == '│'
    end

    @testset "ResizableLayout hover tracking" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))

        move_on = T.MouseEvent(20, 5, T.mouse_none, T.mouse_move, false, false, false)
        T.handle_resize!(rl, move_on)
        @test rl.hover_border == 1

        move_off = T.MouseEvent(10, 5, T.mouse_none, T.mouse_move, false, false, false)
        T.handle_resize!(rl, move_off)
        @test rl.hover_border == 0
    end

    @testset "ResizableLayout Percent+Percent drag" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Percent(50), T.Percent(50)])
        T.split_layout(rl, T.Rect(1, 1, 100, 24))

        press = T.MouseEvent(50, 10, T.mouse_left, T.mouse_press, false, false, false)
        T.handle_resize!(rl, press)

        drag_evt = T.MouseEvent(60, 10, T.mouse_left, T.mouse_drag, false, false, false)
        T.handle_resize!(rl, drag_evt)

        release = T.MouseEvent(60, 10, T.mouse_left, T.mouse_release, false, false, false)
        T.handle_resize!(rl, release)

        @test rl.constraints[1] isa T.Percent
        @test rl.constraints[2] isa T.Percent
        @test rl.constraints[1].pct + rl.constraints[2].pct == 100
        @test rl.constraints[1].pct > 50
    end

    @testset "ResizableLayout click outside returns false" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))

        # Click well outside layout area
        outside = T.MouseEvent(20, 15, T.mouse_left, T.mouse_press, false, false, false)
        @test !T.handle_resize!(rl, outside)
    end

    @testset "ResizableLayout Alt+click border rotates direction" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))
        @test rl.direction == T.Horizontal

        # Alt+click on border at x=20
        evt = T.MouseEvent(20, 5, T.mouse_left, T.mouse_press, false, true, false)
        @test T.handle_resize!(rl, evt)
        @test rl.direction == T.Vertical

        # Alt+click again rotates back
        T.split_layout(rl, T.Rect(1, 1, 40, 10))
        evt2 = T.MouseEvent(20, 5, T.mouse_left, T.mouse_press, false, true, false)
        # After rotation to Vertical, border detection uses y axis;
        # need to find a border in the new direction
        # Just rotate via internal helper to test toggle
        T._rotate_direction!(rl)
        @test rl.direction == T.Horizontal
    end

    @testset "ResizableLayout Alt+drag swaps panes" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fixed(20)])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))

        # Alt+click in pane 1 (x=10) to start swap
        press = T.MouseEvent(10, 5, T.mouse_left, T.mouse_press, false, true, false)
        @test T.handle_resize!(rl, press)
        @test rl.drag.status == T.drag_swap
        @test rl.drag.source_pane == 1

        # Drag (consumed)
        drag_evt = T.MouseEvent(30, 5, T.mouse_left, T.mouse_drag, false, true, false)
        @test T.handle_resize!(rl, drag_evt)

        # Release in pane 2 (x=30) → swap
        release = T.MouseEvent(30, 5, T.mouse_left, T.mouse_release, false, true, false)
        @test T.handle_resize!(rl, release)
        @test rl.drag.status == T.drag_idle

        # Constraints should be swapped
        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[2] isa T.Fixed
        @test rl.constraints[1].size == 20  # same size, but swapped identity
        @test rl.constraints[2].size == 20
    end

    @testset "ResizableLayout Alt+drag swap different constraints" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(15), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))

        # Alt+click in pane 1, release in pane 2
        press = T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, true, false)
        T.handle_resize!(rl, press)
        release = T.MouseEvent(30, 5, T.mouse_left, T.mouse_release, false, true, false)
        T.handle_resize!(rl, release)

        # Constraints swapped: Fill is now first, Fixed second
        @test rl.constraints[1] isa T.Fill
        @test rl.constraints[2] isa T.Fixed
        @test rl.constraints[2].size == 15
    end

    @testset "ResizableLayout Alt+drag release on same pane is no-op" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(15), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 40, 10))

        press = T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, true, false)
        T.handle_resize!(rl, press)
        release = T.MouseEvent(5, 5, T.mouse_left, T.mouse_release, false, true, false)
        T.handle_resize!(rl, release)

        # No swap — constraints unchanged
        @test rl.constraints[1] isa T.Fixed
        @test rl.constraints[2] isa T.Fill
    end

    # ═════════════════════════════════════════════════════════════════
    # Layout persistence
    # ═════════════════════════════════════════════════════════════════

    @testset "Constraint serialization roundtrip" begin
        for (c, expected) in [
            (T.Fixed(30),   "F30"),
            (T.Fill(1),     "L1"),
            (T.Fill(2),     "L2"),
            (T.Percent(50), "P50"),
            (T.Min(5),      "N5"),
            (T.Max(10),     "X10"),
            (T.Ratio(1, 3), "R1/3"),
            (T.Ratio(2, 5), "R2/5"),
        ]
            s = T._serialize_constraint(c)
            @test s == expected
            c2 = T._deserialize_constraint(s)
            @test typeof(c2) == typeof(c)
            if c isa T.Fixed;   @test c2.size == c.size; end
            if c isa T.Fill;    @test c2.weight == c.weight; end
            if c isa T.Percent; @test c2.pct == c.pct; end
            if c isa T.Min;     @test c2.size == c.size; end
            if c isa T.Max;     @test c2.size == c.size; end
            if c isa T.Ratio;   @test c2.num == c.num && c2.den == c.den; end
        end
    end

    @testset "Constraints (plural) serialization roundtrip" begin
        cs = T.Constraint[T.Fixed(30), T.Fill(1), T.Percent(25)]
        s = T._serialize_constraints(cs)
        @test s == "F30,L1,P25"
        cs2 = T._deserialize_constraints(s)
        @test length(cs2) == 3
        @test cs2[1] isa T.Fixed && cs2[1].size == 30
        @test cs2[2] isa T.Fill && cs2[2].weight == 1
        @test cs2[3] isa T.Percent && cs2[3].pct == 25

        # Empty roundtrip
        @test T._deserialize_constraints("") == T.Constraint[]
    end

    @testset "Layout fingerprint" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        fp = T._layout_fingerprint(rl)
        @test fp == "H|F30,L1"

        rl2 = T.ResizableLayout(T.Vertical, [T.Percent(50), T.Percent(50)])
        fp2 = T._layout_fingerprint(rl2)
        @test fp2 == "V|P50,P50"
    end

    @testset "Layout pref save/load roundtrip" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        T.split_layout(rl, T.Rect(1, 1, 80, 24))

        # Simulate a drag: modify constraints
        rl.constraints[1] = T.Fixed(40)
        # Simulate a rotation
        rl.direction = T.Vertical

        T._save_layout_pref!("_TestModel", "vlayout", rl)

        # Create a fresh RL with same original definition
        rl2 = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        @test T._load_layout_pref!("_TestModel", "vlayout", rl2)
        @test rl2.direction == T.Vertical
        @test rl2.constraints[1] isa T.Fixed
        @test rl2.constraints[1].size == 40
        @test rl2.constraints[2] isa T.Fill
    end

    @testset "Layout pref safe failure on mismatch" begin
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        rl.constraints[1] = T.Fixed(40)
        T._save_layout_pref!("_TestModel", "mismatch", rl)

        # Fresh RL with DIFFERENT original definition
        rl2 = T.ResizableLayout(T.Horizontal, [T.Fixed(20), T.Fill()])
        @test !T._load_layout_pref!("_TestModel", "mismatch", rl2)
        # Should keep defaults
        @test rl2.direction == T.Horizontal
        @test rl2.constraints[1] isa T.Fixed
        @test rl2.constraints[1].size == 20
    end

    @testset "Layout pref safe failure no prefs" begin
        # Non-existent key should return false
        rl = T.ResizableLayout(T.Horizontal, [T.Fixed(30), T.Fill()])
        @test !T._load_layout_pref!("_NoSuchModel", "nofield", rl)
    end

    @testset "Layout prefs model discovery" begin
        # _save/_load_layout_prefs! discover ResizableLayout fields automatically
        mutable struct _LayoutTestModel <: T.Model
            vlayout::T.ResizableLayout
            hlayout::T.ResizableLayout
            other::Int
        end
        m = _LayoutTestModel(
            T.ResizableLayout(T.Vertical, [T.Fixed(10), T.Fill()]),
            T.ResizableLayout(T.Horizontal, [T.Percent(30), T.Percent(70)]),
            42,
        )
        # Modify state
        m.vlayout.constraints[1] = T.Fixed(15)
        m.hlayout.direction = T.Vertical

        T._save_layout_prefs!(m)

        # Create fresh model with same layout definitions
        m2 = _LayoutTestModel(
            T.ResizableLayout(T.Vertical, [T.Fixed(10), T.Fill()]),
            T.ResizableLayout(T.Horizontal, [T.Percent(30), T.Percent(70)]),
            0,
        )
        T._load_layout_prefs!(m2)
        @test m2.vlayout.constraints[1] isa T.Fixed
        @test m2.vlayout.constraints[1].size == 15
        @test m2.hlayout.direction == T.Vertical
    end

    # ═════════════════════════════════════════════════════════════════
    # list_hit / list_scroll
    # ═════════════════════════════════════════════════════════════════

    @testset "list_hit basic" begin
        area = T.Rect(5, 10, 20, 5)
        # Click on row 1 (y=10) with offset=0
        evt = T.MouseEvent(10, 10, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_hit(evt, area, 0, 10) == 1

        # Click on row 3 (y=12) with offset=0
        evt2 = T.MouseEvent(10, 12, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_hit(evt2, area, 0, 10) == 3

        # Click on row 3 (y=12) with offset=5
        @test T.list_hit(evt2, area, 5, 10) == 8
    end

    @testset "list_hit outside area" begin
        area = T.Rect(5, 10, 20, 5)
        # Click above
        evt = T.MouseEvent(10, 8, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_hit(evt, area, 0, 10) == 0

        # Click to the left
        evt2 = T.MouseEvent(3, 10, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_hit(evt2, area, 0, 10) == 0
    end

    @testset "list_hit non-press ignored" begin
        area = T.Rect(5, 10, 20, 5)
        # Right click
        evt = T.MouseEvent(10, 10, T.mouse_right, T.mouse_press, false, false, false)
        @test T.list_hit(evt, area, 0, 10) == 0

        # Drag
        evt2 = T.MouseEvent(10, 10, T.mouse_left, T.mouse_drag, false, false, false)
        @test T.list_hit(evt2, area, 0, 10) == 0
    end

    @testset "list_hit beyond n_items" begin
        area = T.Rect(5, 10, 20, 5)
        # Only 2 items, click row 3
        evt = T.MouseEvent(10, 12, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_hit(evt, area, 0, 2) == 0
    end

    @testset "list_scroll" begin
        # Scroll up from offset 5
        evt_up = T.MouseEvent(10, 10, T.mouse_scroll_up, T.mouse_press, false, false, false)
        @test T.list_scroll(evt_up, 5, 20, 10) == 4

        # Scroll down from offset 5
        evt_dn = T.MouseEvent(10, 10, T.mouse_scroll_down, T.mouse_press, false, false, false)
        @test T.list_scroll(evt_dn, 5, 20, 10) == 6

        # Scroll up at 0 stays 0
        @test T.list_scroll(evt_up, 0, 20, 10) == 0

        # Scroll down at max stays at max
        @test T.list_scroll(evt_dn, 10, 20, 10) == 10

        # Non-scroll event returns offset unchanged
        evt_click = T.MouseEvent(10, 10, T.mouse_left, T.mouse_press, false, false, false)
        @test T.list_scroll(evt_click, 5, 20, 10) == 5
    end

    @testset "render_canvas helpers" begin
        # Canvas path
        c = T.Canvas(5, 3)
        T.set_point!(c, 0, 0)
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        frame = T.Frame(buf, T.Rect(1, 1, 10, 5), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render_canvas(c, T.Rect(1, 1, 5, 3), frame)
        @test UInt32(buf.content[1].char) >= 0x2800

        # PixelCanvas path
        sc = T.PixelCanvas(5, 3)
        T.set_point!(sc, 0, 0)
        buf2 = T.Buffer(T.Rect(1, 1, 10, 5))
        frame2 = T.Frame(buf2, T.Rect(1, 1, 10, 5), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render_canvas(sc, T.Rect(1, 1, 5, 3), frame2)
        @test length(frame2.gfx_regions) == 1
    end

