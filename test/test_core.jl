    @testset "Rect" begin
        r = T.Rect(1, 1, 80, 24)
        @test T.right(r) == 80
        @test T.bottom(r) == 24
        @test T.area(r) == 1920
        @test T.inner(r) == T.Rect(2, 2, 78, 22)

        tiny = T.Rect(1, 1, 1, 1)
        @test T.inner(tiny) == T.Rect(1, 1, 0, 0)
    end

    @testset "Style" begin
        s = T.Style(fg=T.Color256(179))
        @test s == T.Style(fg=T.Color256(179))
        @test s != T.RESET
        @test T.RESET == T.Style()
    end

    @testset "Buffer" begin
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        @test length(buf.content) == 50

        T.set_string!(buf, 1, 1, "hello")
        @test buf.content[1].char == 'h'
        @test buf.content[5].char == 'o'

        T.set_char!(buf, 3, 2, 'X', T.Style(fg=T.KOKAKU.primary))
        i = T.buf_index(buf, 3, 2)
        @test buf.content[i].char == 'X'

        # Out of bounds is silently ignored
        T.set_char!(buf, 99, 99, 'Z')
        @test true

        T.reset!(buf)
        @test buf.content[1].char == ' '
    end

    @testset "Layout" begin
        r = T.Rect(1, 1, 100, 24)

        # Even split
        rects = T.split_layout(
            T.Layout(T.Horizontal,
                     [T.Percent(50), T.Percent(50)]), r)
        @test length(rects) == 2
        @test rects[1].width == 50
        @test rects[2].width == 50
        @test rects[2].x == 51

        # Fixed + Fill
        rects2 = T.split_layout(
            T.Layout(T.Vertical,
                     [T.Fixed(3), T.Fill()]), r)
        @test rects2[1].height == 3
        @test rects2[2].height == 21
        @test rects2[2].y == 4

        # Three-way with mixed constraints
        rects3 = T.split_layout(
            T.Layout(T.Horizontal,
                     [T.Fixed(10), T.Fill(), T.Fixed(10)]), r)
        @test rects3[1].width == 10
        @test rects3[3].width == 10
        @test rects3[2].width == 80
    end

    @testset "Theme" begin
        T.set_theme!(T.KOKAKU)
        @test T.theme().name == "kokaku"
        T.set_theme!(T.ESPER)
        @test T.theme().name == "esper"

        # New themes
        T.set_theme!(T.MOTOKO)
        @test T.theme().name == "motoko"
        T.set_theme!(T.KANEDA)
        @test T.theme().name == "kaneda"
        T.set_theme!(T.NEUROMANCER)
        @test T.theme().name == "neuromancer"
        T.set_theme!(T.CATPPUCCIN)
        @test T.theme().name == "catppuccin"

        # Symbol-based set_theme!
        T.set_theme!(:kokaku)
        @test T.theme().name == "kokaku"
        T.set_theme!(:motoko)
        @test T.theme().name == "motoko"

        # ALL_THEMES tuple
        @test length(T.ALL_THEMES) == 11

        T.set_theme!(T.KOKAKU)  # restore
    end

    @testset "Block" begin
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        block = T.Block(title="test",
                        border_style=T.RESET,
                        title_style=T.RESET)
        inner = T.render(block, buf.area, buf)
        @test inner == T.Rect(2, 2, 18, 3)
        @test buf.content[1].char == '╭'
        ti = T.buf_index(buf, 20, 1)
        @test buf.content[ti].char == '╮'
    end

    # Gauge, Sparkline, Table — tested in test_widgets_coverage.jl

    @testset "SelectableList" begin
        buf = T.Buffer(T.Rect(1, 1, 30, 6))
        lst = T.SelectableList(
            ["alpha", "beta", "gamma", "delta"];
            selected=2,
        )
        T.render(lst, T.Rect(1, 1, 30, 6), buf)
        # Selected item (beta) should have marker on row 2
        idx = T.buf_index(buf, 1, 2)
        @test buf.content[idx].char == T.MARKER
        # Non-selected row 1 should not have marker
        idx1 = T.buf_index(buf, 1, 1)
        @test buf.content[idx1].char != T.MARKER
    end

    # Table selection, Table backward compat, TabBar, StatusBar — tested in test_widgets_coverage.jl

    @testset "TextInput" begin
        input = T.TextInput(text="hello", label=">> ")
        @test T.text(input) == "hello"
        @test input.cursor == 5

        # Type a character
        T.handle_key!(input, T.KeyEvent('!'))
        @test T.text(input) == "hello!"
        @test input.cursor == 6

        # Backspace
        T.handle_key!(input, T.KeyEvent(:backspace))
        @test T.text(input) == "hello"
        @test input.cursor == 5

        # Move left
        T.handle_key!(input, T.KeyEvent(:left))
        @test input.cursor == 4

        # Insert in middle
        T.handle_key!(input, T.KeyEvent('X'))
        @test T.text(input) == "hellXo"
        @test input.cursor == 5

        # Home / End
        T.handle_key!(input, T.KeyEvent(:home))
        @test input.cursor == 0
        T.handle_key!(input, T.KeyEvent(:end_key))
        @test input.cursor == 6

        # Delete at cursor position
        T.handle_key!(input, T.KeyEvent(:home))
        T.handle_key!(input, T.KeyEvent(:delete))
        @test T.text(input) == "ellXo"

        # Clear
        T.clear!(input)
        @test T.text(input) == ""
        @test input.cursor == 0

        # set_text!
        T.set_text!(input, "new")
        @test T.text(input) == "new"
        @test input.cursor == 3
    end

    @testset "TextInput render" begin
        input = T.TextInput(text="abc", label="> ")
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        T.render(input, T.Rect(1, 1, 20, 1), buf)
        # Label "> " at positions 1-2
        @test buf.content[1].char == '>'
        @test buf.content[2].char == ' '
        # Text "abc" starts at position 3
        @test buf.content[3].char == 'a'
        @test buf.content[5].char == 'c'
    end

    @testset "TextInput unfocused ignores keys" begin
        input = T.TextInput(text="test", focused=false)
        result = T.handle_key!(input, T.KeyEvent('x'))
        @test !result
        @test T.text(input) == "test"
    end

    @testset "Modal" begin
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        modal = T.Modal(
            title="Delete?",
            message="This cannot be undone.",
            confirm_label="Delete",
            cancel_label="Cancel",
            selected=:cancel,
        )
        T.render(modal, T.Rect(1, 1, 60, 20), buf)
        # Should have heavy border somewhere in the center
        found_heavy = false
        for c in buf.content
            if c.char == '┏' || c.char == '┓'
                found_heavy = true
                break
            end
        end
        @test found_heavy
    end

    @testset "Modal confirm selected" begin
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        modal = T.Modal(selected=:confirm)
        T.render(modal, T.Rect(1, 1, 60, 20), buf)
        # Should render without error
        @test true
    end

    @testset "Canvas" begin
        c = T.Canvas(10, 5)
        @test size(c.dots) == (10, 5)
        @test all(c.dots .== 0x00)

        # Set a point in dot-space
        T.set_point!(c, 0, 0)  # top-left of cell (1,1)
        @test c.dots[1, 1] != 0x00

        # Unset it
        T.unset_point!(c, 0, 0)
        @test c.dots[1, 1] == 0x00

        # Line drawing
        T.line!(c, 0, 0, 19, 19)
        @test any(c.dots .!= 0x00)

        # Clear
        T.clear!(c)
        @test all(c.dots .== 0x00)
    end

    @testset "Canvas render" begin
        c = T.Canvas(5, 3)
        T.set_point!(c, 0, 0)
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        T.render(c, T.Rect(1, 1, 5, 3), buf)
        # Cell (1,1) should be a braille character (not space)
        @test buf.content[1].char != ' '
        # Should be in braille range
        @test UInt32(buf.content[1].char) >= 0x2800
        @test UInt32(buf.content[1].char) <= 0x28FF
    end

    @testset "Canvas out of bounds" begin
        c = T.Canvas(5, 3)
        # These should not crash
        T.set_point!(c, -1, -1)
        T.set_point!(c, 100, 100)
        T.unset_point!(c, -1, -1)
        @test true
    end

    @testset "BarChart" begin
        buf = T.Buffer(T.Rect(1, 1, 40, 5))
        bars = [
            T.BarEntry("cpu", 75.0),
            T.BarEntry("mem", 45.0),
            T.BarEntry("disk", 90.0),
        ]
        bc = T.BarChart(bars; max_val=100.0)
        T.render(bc, T.Rect(1, 1, 40, 5), buf)
        # Labels should appear (right-aligned in label column)
        # Find 'c' from "cpu" somewhere in first row
        found_label = false
        for i in 1:40
            if buf.content[i].char == 'c'
                found_label = true
                break
            end
        end
        @test found_label
        # Should have bar characters
        found_bar = false
        for i in 1:40
            if buf.content[i].char == '█'
                found_bar = true
                break
            end
        end
        @test found_bar
    end

    @testset "BarChart empty" begin
        buf = T.Buffer(T.Rect(1, 1, 40, 5))
        bc = T.BarChart(T.BarEntry[])
        T.render(bc, T.Rect(1, 1, 40, 5), buf)
        @test true  # should not crash
    end

    @testset "Calendar" begin
        buf = T.Buffer(T.Rect(1, 1, 25, 10))
        cal = T.Calendar(2024, 1; today=15)
        T.render(cal, T.Rect(1, 1, 25, 10), buf)
        # Header should contain "January"
        row1 = String([buf.content[i].char for i in 1:25])
        @test occursin("January", row1)
    end

    @testset "Calendar default" begin
        # Default constructor should not crash
        cal = T.Calendar()
        buf = T.Buffer(T.Rect(1, 1, 25, 10))
        T.render(cal, T.Rect(1, 1, 25, 10), buf)
        @test true
    end

    # Scrollbar, BigText — tested in test_widgets_coverage.jl

    @testset "TreeView" begin
        root = T.TreeNode("root", [
            T.TreeNode("child1", [
                T.TreeNode("leaf1"),
                T.TreeNode("leaf2"),
            ]),
            T.TreeNode("child2"),
        ])
        buf = T.Buffer(T.Rect(1, 1, 40, 10))
        tv = T.TreeView(root; selected=2)
        T.render(tv, T.Rect(1, 1, 40, 10), buf)
        # Root should appear on line 1
        # Find 'r' from "root" in row 1
        @test buf.content[T.buf_index(buf, 2, 1)].char == 'r' ||
              buf.content[T.buf_index(buf, 3, 1)].char == 'r' ||
              buf.content[T.buf_index(buf, 1, 1)].char == '▾'
    end

    @testset "TreeView no root" begin
        root = T.TreeNode("root", [
            T.TreeNode("a"),
            T.TreeNode("b"),
        ])
        buf = T.Buffer(T.Rect(1, 1, 30, 5))
        tv = T.TreeView(root; show_root=false)
        T.render(tv, T.Rect(1, 1, 30, 5), buf)
        # "a" should be on first line, not "root"
        found_a = false
        for i in 1:30
            buf.content[i].char == 'a' && (found_a = true; break)
        end
        @test found_a
    end

    @testset "TreeView visible count" begin
        root = T.TreeNode("r", [
            T.TreeNode("a", [T.TreeNode("x")]),
            T.TreeNode("b"),
        ])
        tv = T.TreeView(root)
        @test T.tree_visible_count(tv) == 4  # r, a, x, b
    end

    # ProgressList — tested in test_widgets_coverage.jl

