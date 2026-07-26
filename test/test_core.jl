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

    @testset "Buffer wide characters" begin
        # set_string! places wide char + pad sentinel correctly
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你好")
        @test buf.content[1].char == '你'
        @test buf.content[2].char == T.WIDE_CHAR_PAD
        @test buf.content[3].char == '好'
        @test buf.content[4].char == T.WIDE_CHAR_PAD

        # set_char! overwriting leading cell cleans up orphaned pad
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你")
        @test buf.content[2].char == T.WIDE_CHAR_PAD
        T.set_char!(buf, 1, 1, 'A')
        @test buf.content[1].char == 'A'
        @test buf.content[2].char == ' '  # pad cleaned up

        # set_char! overwriting pad cell cleans up broken leading char
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你")
        T.set_char!(buf, 2, 1, 'B')
        @test buf.content[1].char == ' '  # leading cell cleaned up
        @test buf.content[2].char == 'B'

        # Wide char at boundary is skipped (pad doesn't fit)
        buf = T.Buffer(T.Rect(1, 1, 5, 1))
        T.set_string!(buf, 1, 1, "abc你")
        @test buf.content[1].char == 'a'
        @test buf.content[2].char == 'b'
        @test buf.content[3].char == 'c'
        # '你' needs cols 4-5 but clip=right(area)=5, col=4, col+1=5 ≤ 5 → fits
        @test buf.content[4].char == '你'
        @test buf.content[5].char == T.WIDE_CHAR_PAD

        # Wide char truly at boundary — pad would overflow
        buf = T.Buffer(T.Rect(1, 1, 4, 1))
        T.set_string!(buf, 1, 1, "abc你")
        @test buf.content[1].char == 'a'
        @test buf.content[2].char == 'b'
        @test buf.content[3].char == 'c'
        @test buf.content[4].char == ' '  # wide char skipped, space placed

        # Multiple wide chars in sequence
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你好世")
        @test buf.content[1].char == '你'
        @test buf.content[2].char == T.WIDE_CHAR_PAD
        @test buf.content[3].char == '好'
        @test buf.content[4].char == T.WIDE_CHAR_PAD
        @test buf.content[5].char == '世'
        @test buf.content[6].char == T.WIDE_CHAR_PAD

        # buffer_to_text skips pad sentinels
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "A你B")
        text = T.buffer_to_text(buf, T.Rect(1, 1, 10, 1))
        @test text == "A你B"

        # Overwrite wide char with another wide char
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你")
        T.set_string!(buf, 1, 1, "好")
        @test buf.content[1].char == '好'
        @test buf.content[2].char == T.WIDE_CHAR_PAD

        # set_string! starting on a pad cell cleans up leading char
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "你")
        @test buf.content[1].char == '你'
        T.set_string!(buf, 2, 1, "X")
        @test buf.content[1].char == ' '  # leading cell cleaned up
        @test buf.content[2].char == 'X'
    end

    @testset "truncate_to_width (display-width, not char count)" begin
        # No truncation when it already fits (by DISPLAY width).
        @test T.truncate_to_width("hello", 5) == "hello"
        @test T.truncate_to_width("開門", 4) == "開門"      # 2 wide chars = 4 cols, fits exactly
        # ASCII truncation reserves a column for the ellipsis.
        @test T.truncate_to_width("hello", 3) == "he…"       # "he"=2 + "…"=1
        # A wide (CJK) string is measured in columns: "開門記" is 6 cols, not 3 chars.
        @test T.truncate_to_width("開門記", 4) == "開…"       # 開=2 + …=1 ≤ 4; 門 would push to 4>3 budget
        @test textwidth(T.truncate_to_width("開門記世界", 6)) <= 6
        # Never exceeds the budget for mixed content.
        @test textwidth(T.truncate_to_width("a開b門c", 4)) <= 4
        # Degenerate widths.
        @test T.truncate_to_width("abc", 0) == ""
        @test T.truncate_to_width("", 5) == ""
    end

    @testset "set_string! strips control chars (no terminal smear)" begin
        # C0 controls (\r, \n, \b) and DEL have no glyph; flushed raw they move the
        # terminal cursor and smear the row. _strip_controls replaces them with spaces
        # so they can never reach a cell. (_strip_ansi only removes ESC sequences.)
        @test T._strip_controls("abc") == "abc"            # clean → untouched
        @test T._strip_controls("a\rb\nc") == "a b c"      # CR/LF → spaces
        @test T._strip_controls("x\x7fy\x08z") == "x y z"  # DEL + backspace → spaces

        # A raw \r in cell content must never survive into the buffer.
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "ab\rcd")
        txt = T.buffer_to_text(buf, T.Rect(1, 1, 10, 1))
        @test !occursin('\r', txt)
        @test txt == "ab cd"

        # A trailing newline doesn't jump the cursor to the next row.
        buf2 = T.Buffer(T.Rect(1, 1, 10, 2))
        T.set_string!(buf2, 1, 1, "hi\nthere")
        @test T.buffer_to_text(buf2, T.Rect(1, 1, 10, 2)) == "hi there"
    end

    @testset "Buffer zero-width graphemes" begin
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "ṅx")
        @test buf.content[1].char == 'n'
        @test buf.content[1].suffix == "̇"
        @test buf.content[2].char == 'x'
        @test T.buffer_to_text(buf, T.Rect(1, 1, 10, 1)) == "ṅx"

        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.set_string!(buf, 1, 1, "a\u0307b")
        @test buf.content[1].char == 'a'
        @test buf.content[1].suffix == "\u0307"
        @test buf.content[2].char == 'b'
        @test buf.content[3].char == ' '
    end

    @testset "DataTable wide-char (CJK) column alignment" begin
        # Regression: a right-aligned CJK cell was padded by CHAR count (avail-length),
        # shoving it past the column's right edge so the trailing glyph clipped at
        # max_x — the layout-shear seen with a 開門 session label. With display-width
        # padding both glyphs stay inside the column.
        col = T.DataColumn("s", Any["開門"]; width=6, align=T.col_right)
        dt = T.DataTable([col]; show_scrollbar=false)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(dt, T.Rect(1, 1, 20, 5), buf)
        @test occursin("開門", T.buffer_to_text(buf, T.Rect(1, 1, 20, 5)))  # both glyphs (pre-fix: 門 clipped)

        # Auto-width column must size to display width, not char count, so a wide
        # value isn't under-budgeted and truncated when it would otherwise fit.
        col2 = T.DataColumn("s", Any["世界"])   # width=0 → auto
        dt2 = T.DataTable([col2]; show_scrollbar=false)
        buf2 = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(dt2, T.Rect(1, 1, 20, 5), buf2)
        @test occursin("世界", T.buffer_to_text(buf2, T.Rect(1, 1, 20, 5)))
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
        T.set_theme!(:julia_dark)
        @test T.theme().name == "julia_dark"

        # ALL_THEMES tuple (12 dark + 14 light)
        @test length(T.ALL_THEMES) == 26

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

    @testset "BarChart multibyte label truncation (Tachikoma#36)" begin
        # Long multibyte labels must truncate by character, not byte. Sweep
        # buffer widths so the truncation boundary lands at every byte offset
        # within the multibyte run (em-dash is 3 bytes → boundaries cycle).
        bars = [T.BarEntry("—————————————————————————————", 75.0),
                T.BarEntry("café — résumé — naïve — über", 45.0)]
        # Force truncation with an explicit (small) label column, swept so the
        # cut boundary lands at every byte offset within the multibyte run.
        for lw in 3:12
            bc = T.BarChart(bars; max_val=100.0, label_width=lw, show_values=false)
            buf = T.Buffer(T.Rect(1, 1, 40, 5))
            @test (T.render(bc, T.Rect(1, 1, 40, 5), buf); true)
        end
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
