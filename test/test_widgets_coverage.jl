    # ═════════════════════════════════════════════════════════════════
    # Widget Coverage Tests
    # ═════════════════════════════════════════════════════════════════

    # ─────────────────────────────────────────────────────────────────
    # BigText
    # ─────────────────────────────────────────────────────────────────

    @testset "BigText: basic rendering" begin
        bt = T.BigText("HI")
        tb = T.TestBackend(10, 5)
        T.render_widget!(tb, bt)
        # 'H' glyph row 1 = "█ █", should see fill_char at (1,1)
        @test T.char_at(tb, 1, 1) == '█'
        # Gap between H and I at column 4 (glyph width 3 + gap 1)
        @test T.char_at(tb, 4, 1) == ' '
        # 'I' glyph starts at col 5, row 1 = "███"
        @test T.char_at(tb, 5, 1) == '█'
    end

    @testset "BigText: empty string" begin
        bt = T.BigText("")
        tb = T.TestBackend(20, 5)
        T.render_widget!(tb, bt)
        # Nothing rendered, no crash
        @test T.char_at(tb, 1, 1) == ' '
    end

    @testset "BigText: intrinsic_size" begin
        @test T.intrinsic_size(T.BigText(""))[1] == 0
        @test T.intrinsic_size(T.BigText("A"))[1] == 3           # 1 glyph, 3 wide
        @test T.intrinsic_size(T.BigText("AB"))[1] == 7          # 2*3 + 1 gap
        @test T.intrinsic_size(T.BigText("ABC"))[1] == 11        # 3*3 + 2 gaps
        w, h = T.intrinsic_size(T.BigText("OK"))
        @test w == 7
        @test h == 5
    end

    @testset "BigText: numbers and special chars" begin
        bt = T.BigText("1:2")
        tb = T.TestBackend(15, 5)
        T.render_widget!(tb, bt)
        # '1' glyph row 1 = " █ ", col 2 should be filled
        @test T.char_at(tb, 2, 1) == '█'
    end

    @testset "BigText: truncation when area too narrow" begin
        bt = T.BigText("ABCDEFGHIJ")  # 10 glyphs = 39 cols
        tb = T.TestBackend(10, 5)
        T.render_widget!(tb, bt)
        # Should render what fits without crashing
        @test T.char_at(tb, 1, 1) == '█'  # 'A' starts
    end

    @testset "BigText: area too short in height" begin
        bt = T.BigText("A")
        tb = T.TestBackend(10, 3)
        T.render_widget!(tb, bt)
        # Height < BIGTEXT_GLYPH_H (5), should skip rendering
        @test T.char_at(tb, 1, 1) == ' '
    end

    @testset "BigText: custom fill_char" begin
        bt = T.BigText("I"; fill_char='#')
        tb = T.TestBackend(5, 5)
        T.render_widget!(tb, bt)
        # 'I' glyph row 1 = "███", all should be '#'
        @test T.char_at(tb, 1, 1) == '#'
        @test T.char_at(tb, 2, 1) == '#'
        @test T.char_at(tb, 3, 1) == '#'
    end

    @testset "BigText: lowercase auto-uppercased" begin
        bt = T.BigText("hi")
        @test bt.text == "HI"
    end

    @testset "BigText: style_fn override" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        fn = (x, y) -> red
        bt = T.BigText("A"; style_fn=fn)
        tb = T.TestBackend(5, 5)
        T.render_widget!(tb, bt)
        @test T.style_at(tb, 1, 1).fg == T.ColorRGB(0xff, 0x00, 0x00)
    end

    # ─────────────────────────────────────────────────────────────────
    # Gauge
    # ─────────────────────────────────────────────────────────────────

    @testset "Gauge: boundary values" begin
        for ratio in [0.0, 0.5, 1.0]
            tb = T.TestBackend(40, 1)
            g = T.Gauge(ratio)
            T.render_widget!(tb, g)
            # Label should appear (auto percentage)
            row = T.row_text(tb, 1)
            expected_pct = string(round(Int, ratio * 100)) * "%"
            @test occursin(expected_pct, row)
        end
    end

    @testset "Gauge: clamping negative" begin
        g = T.Gauge(-0.5)
        @test g.ratio == 0.0
        @test g.label == "0%"
    end

    @testset "Gauge: clamping >1.0" begin
        g = T.Gauge(1.5)
        @test g.ratio == 1.0
        @test g.label == "100%"
    end

    @testset "Gauge: custom label" begin
        g = T.Gauge(0.3; label="Loading...")
        @test g.label == "Loading..."
        tb = T.TestBackend(40, 1)
        T.render_widget!(tb, g)
        @test occursin("Loading...", T.row_text(tb, 1))
    end

    @testset "Gauge: filled style rendering" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        g = T.Gauge(0.5; filled_style=red)
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, g)
        # First column should use filled style
        @test T.style_at(tb, 1, 1).fg == T.ColorRGB(0xff, 0x00, 0x00)
    end

    @testset "Gauge: 0% renders all empty" begin
        g = T.Gauge(0.0)
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, g)
        # First cell should be empty marker '░'
        @test T.char_at(tb, 1, 1) == '░'
    end

    @testset "Gauge: 100% renders all filled" begin
        g = T.Gauge(1.0)
        tb = T.TestBackend(10, 1)
        T.render_widget!(tb, g)
        # All cells should be '█' (except where label overwrites)
        @test T.char_at(tb, 1, 1) == '█'
        @test T.char_at(tb, 10, 1) == '█'
    end

    @testset "Gauge: with block border" begin
        g = T.Gauge(0.5; block=T.Block(title="Progress"))
        tb = T.TestBackend(30, 3)
        T.render_widget!(tb, g)
        @test occursin("Progress", T.row_text(tb, 1))
    end

    @testset "Gauge: very narrow area" begin
        g = T.Gauge(0.5)
        tb = T.TestBackend(3, 1)
        T.render_widget!(tb, g)
        # Should render without crash even if label doesn't fit
        @test true
    end

    # ─────────────────────────────────────────────────────────────────
    # Table
    # ─────────────────────────────────────────────────────────────────

    @testset "Table: basic rendering" begin
        tbl = T.Table(["Name", "Age"], [["Alice", "30"], ["Bob", "25"]])
        tb = T.TestBackend(30, 5)
        T.render_widget!(tb, tbl)
        @test occursin("Name", T.row_text(tb, 1))
        @test occursin("Age", T.row_text(tb, 1))
        # Separator on row 2
        @test T.char_at(tb, 1, 2) == '─'
    end

    @testset "Table: empty rows" begin
        tbl = T.Table(["Col1", "Col2"], Vector{String}[])
        tb = T.TestBackend(30, 5)
        T.render_widget!(tb, tbl)
        @test occursin("Col1", T.row_text(tb, 1))
        # No data rows, no crash
        @test T.char_at(tb, 1, 3) == ' '
    end

    @testset "Table: single row" begin
        tbl = T.Table(["X"], [["val"]])
        tb = T.TestBackend(20, 4)
        T.render_widget!(tb, tbl)
        @test occursin("X", T.row_text(tb, 1))
        @test occursin("val", T.row_text(tb, 3))
    end

    @testset "Table: selected row highlighting" begin
        tbl = T.Table(["Name"], [["A"], ["B"], ["C"]]; selected=2)
        tb = T.TestBackend(20, 6)
        T.render_widget!(tb, tbl)
        # Selected row (row 2 data = row 4 visually) should have marker
        @test T.char_at(tb, 1, 4) == T.MARKER
    end

    @testset "Table: column separator" begin
        tbl = T.Table(["A", "B"], [["x", "y"]])
        tb = T.TestBackend(20, 4)
        T.render_widget!(tb, tbl)
        # Find the separator character between columns
        row = T.row_text(tb, 3)
        @test occursin("│", row)
    end

    @testset "Table: row_styles override" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        blue = T.Style(fg=T.ColorRGB(0x00, 0x00, 0xff))
        tbl = T.Table(["X"], [["a"], ["b"]]; row_styles=[red, blue])
        tb = T.TestBackend(10, 5)
        T.render_widget!(tb, tbl)
        # Row 1 data (row 3 visual) should use red style
        @test T.style_at(tb, 1, 3).fg == T.ColorRGB(0xff, 0x00, 0x00)
        # Row 2 data (row 4 visual) should use blue style
        @test T.style_at(tb, 1, 4).fg == T.ColorRGB(0x00, 0x00, 0xff)
    end

    @testset "Table: many rows truncation" begin
        rows = [["row$i"] for i in 1:100]
        tbl = T.Table(["Data"], rows)
        tb = T.TestBackend(20, 5)
        T.render_widget!(tb, tbl)
        # Should only render what fits (header + separator + 3 data rows)
        @test occursin("row1", T.row_text(tb, 3))
        @test occursin("row3", T.row_text(tb, 5))
    end

    @testset "Table: auto column widths" begin
        tbl = T.Table(["Short", "LongerHeader"],
                       [["a", "b"], ["longvalue", "c"]])
        # Widths should be auto-computed
        @test length(tbl.widths) == 2
        @test tbl.widths[1] >= length("longvalue") + 2
        @test tbl.widths[2] >= length("LongerHeader") + 2
    end

    @testset "Table: explicit widths" begin
        tbl = T.Table(["A", "B"], [["x", "y"]]; widths=[10, 15])
        @test tbl.widths == [10, 15]
    end

    @testset "Table: with block" begin
        tbl = T.Table(["Col"], [["val"]]; block=T.Block(title="Data"))
        tb = T.TestBackend(30, 6)
        T.render_widget!(tb, tbl)
        @test occursin("Data", T.row_text(tb, 1))
    end

    # ─────────────────────────────────────────────────────────────────
    # StatusBar
    # ─────────────────────────────────────────────────────────────────

    @testset "StatusBar: left and right spans" begin
        left = [T.Span("MODE: NORMAL")]
        right = [T.Span("Ln 42")]
        bar = T.StatusBar(left=left, right=right)
        tb = T.TestBackend(40, 1)
        T.render_widget!(tb, bar)
        row = T.row_text(tb, 1)
        @test occursin("MODE: NORMAL", row)
        @test occursin("Ln 42", row)
    end

    @testset "StatusBar: left only" begin
        bar = T.StatusBar(left=[T.Span("hello")])
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, bar)
        @test occursin("hello", T.row_text(tb, 1))
    end

    @testset "StatusBar: right only" begin
        bar = T.StatusBar(right=[T.Span("right")])
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, bar)
        row = T.row_text(tb, 1)
        @test occursin("right", row)
        # Right-aligned: should be near the end
        pos = findfirst("right", row)
        @test first(pos) > 10
    end

    @testset "StatusBar: empty spans" begin
        bar = T.StatusBar()
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, bar)
        # All spaces (background fill)
        @test strip(T.row_text(tb, 1)) == ""
    end

    @testset "StatusBar: truncation when narrow" begin
        left = [T.Span("very long left content here")]
        right = [T.Span("right")]
        bar = T.StatusBar(left=left, right=right)
        tb = T.TestBackend(15, 1)
        T.render_widget!(tb, bar)
        # Should render without crash, left takes priority
        row = T.row_text(tb, 1)
        @test startswith(row, "very long left ")
    end

    @testset "StatusBar: style propagation" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        bar = T.StatusBar(left=[T.Span("hi", red)])
        tb = T.TestBackend(10, 1)
        T.render_widget!(tb, bar)
        @test T.style_at(tb, 1, 1).fg == T.ColorRGB(0xff, 0x00, 0x00)
    end

    @testset "StatusBar: multiple left spans" begin
        s1 = T.Span("A")
        s2 = T.Span("B")
        bar = T.StatusBar(left=[s1, s2])
        tb = T.TestBackend(10, 1)
        T.render_widget!(tb, bar)
        @test T.char_at(tb, 1, 1) == 'A'
        @test T.char_at(tb, 2, 1) == 'B'
    end

    # ─────────────────────────────────────────────────────────────────
    # Button
    # ─────────────────────────────────────────────────────────────────

    @testset "Button: focused vs unfocused style" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        blue = T.Style(fg=T.ColorRGB(0x00, 0x00, 0xff))
        btn_focused = T.Button("Go"; focused=true, style=blue, focused_style=red)
        btn_unfocused = T.Button("Go"; focused=false, style=blue, focused_style=red)

        tb1 = T.TestBackend(20, 1)
        T.render_widget!(tb1, btn_focused)
        tb2 = T.TestBackend(20, 1)
        T.render_widget!(tb2, btn_unfocused)

        # Focused button uses focused_style, unfocused uses style
        # Find the 'G' character and check its style
        pos1 = T.find_text(tb1, "Go")
        pos2 = T.find_text(tb2, "Go")
        @test pos1 !== nothing
        @test pos2 !== nothing
        @test T.style_at(tb1, pos1.x, pos1.y).fg == T.ColorRGB(0xff, 0x00, 0x00)
        @test T.style_at(tb2, pos2.x, pos2.y).fg == T.ColorRGB(0x00, 0x00, 0xff)
    end

    @testset "Button: intrinsic_size" begin
        btn = T.Button("OK")
        w, h = T.intrinsic_size(btn)
        @test w == length("OK") + 4  # "[ OK ]"
        @test h == 1
    end

    @testset "Button: focusable" begin
        btn = T.Button("X")
        @test T.focusable(btn)
    end

    @testset "Button: space key handling" begin
        btn = T.Button("X"; focused=true)
        @test T.handle_key!(btn, T.KeyEvent(' '))
    end

    @testset "Button: enter key when focused" begin
        btn = T.Button("X"; focused=true)
        @test T.handle_key!(btn, T.KeyEvent(:enter))
    end

    @testset "Button: unhandled keys" begin
        btn = T.Button("X"; focused=true)
        @test !T.handle_key!(btn, T.KeyEvent(:up))
        @test !T.handle_key!(btn, T.KeyEvent('a'))
    end

    # ─────────────────────────────────────────────────────────────────
    # Sparkline
    # ─────────────────────────────────────────────────────────────────

    @testset "Sparkline: basic rendering" begin
        sp = T.Sparkline([1.0, 3.0, 2.0, 4.0])
        tb = T.TestBackend(10, 3)
        T.render_widget!(tb, sp)
        # Should render some bar characters
        found_bar = false
        for y in 1:3, x in 1:4
            c = T.char_at(tb, x, y)
            if c == '█' || c in T.BARS_V
                found_bar = true
                break
            end
        end
        @test found_bar
    end

    @testset "Sparkline: empty data" begin
        sp = T.Sparkline(Float64[])
        tb = T.TestBackend(10, 3)
        T.render_widget!(tb, sp)
        # No crash, nothing rendered
        @test T.char_at(tb, 1, 1) == ' '
    end

    @testset "Sparkline: single value" begin
        sp = T.Sparkline([5.0])
        tb = T.TestBackend(5, 3)
        T.render_widget!(tb, sp)
        # Single bar at column 1, bottom should be filled
        @test T.char_at(tb, 1, 3) == '█'
    end

    @testset "Sparkline: all zeros" begin
        sp = T.Sparkline([0.0, 0.0, 0.0])
        tb = T.TestBackend(5, 3)
        T.render_widget!(tb, sp)
        # With all zeros, max becomes 1.0, so 0/1 = 0 height → nothing drawn
        @test T.char_at(tb, 1, 3) == ' '
    end

    @testset "Sparkline: overflow (more data than width)" begin
        sp = T.Sparkline(collect(1.0:20.0))
        tb = T.TestBackend(5, 3)
        T.render_widget!(tb, sp)
        # Should show last 5 values (16-20), tallest at col 5
        @test T.char_at(tb, 5, 3) == '█'
    end

    @testset "Sparkline: custom max_val" begin
        sp = T.Sparkline([2.0, 4.0]; max_val=8.0)
        tb = T.TestBackend(5, 4)
        T.render_widget!(tb, sp)
        # 4/8 = 0.5 → half height filled
        # Should have something at bottom but not full height
        @test T.char_at(tb, 2, 4) == '█'
        @test T.char_at(tb, 2, 1) == ' '  # top should be empty
    end

    @testset "Sparkline: with block" begin
        sp = T.Sparkline([1.0, 2.0, 3.0]; block=T.Block(title="Spark"))
        tb = T.TestBackend(20, 5)
        T.render_widget!(tb, sp)
        @test occursin("Spark", T.row_text(tb, 1))
    end

    # ─────────────────────────────────────────────────────────────────
    # TabBar
    # ─────────────────────────────────────────────────────────────────

    @testset "TabBar: basic rendering" begin
        tabs = T.TabBar(["Home", "Settings", "Help"]; active=1)
        tb = T.TestBackend(40, 1)
        T.render_widget!(tb, tabs)
        row = T.row_text(tb, 1)
        @test occursin("[Home]", row)
        @test occursin("Settings", row)
        @test occursin("Help", row)
    end

    @testset "TabBar: active tab styling" begin
        tabs = T.TabBar(["A", "B"]; active=2)
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, tabs)
        row = T.row_text(tb, 1)
        # Active tab B should have brackets
        @test occursin("[B]", row)
        # Inactive tab A should not have brackets
        @test !occursin("[A]", row)
    end

    @testset "TabBar: single tab" begin
        tabs = T.TabBar(["Only"]; active=1)
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, tabs)
        @test occursin("[Only]", T.row_text(tb, 1))
    end

    @testset "TabBar: empty labels" begin
        tabs = T.TabBar(String[]; active=1)
        tb = T.TestBackend(20, 1)
        T.render_widget!(tb, tabs)
        # No crash, nothing rendered
        @test strip(T.row_text(tb, 1)) == ""
    end

    @testset "TabBar: overflow truncation" begin
        tabs = T.TabBar(["Tab1", "Tab2", "Tab3", "Tab4", "Tab5"]; active=1)
        tb = T.TestBackend(15, 1)
        T.render_widget!(tb, tabs)
        # Should render what fits without crashing
        @test occursin("[Tab1]", T.row_text(tb, 1))
    end

    @testset "TabBar: active clamped" begin
        tabs = T.TabBar(["A", "B"]; active=5)
        @test tabs.active == 2  # clamped to max
        tabs2 = T.TabBar(["A", "B"]; active=0)
        @test tabs2.active == 1  # clamped to min
    end

    @testset "TabBar: rich Span labels" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        labels = T.TabLabel[
            [T.Span("Rich", red)],
            "Plain",
        ]
        tabs = T.TabBar(labels; active=1)
        tb = T.TestBackend(30, 1)
        T.render_widget!(tb, tabs)
        row = T.row_text(tb, 1)
        @test occursin("Rich", row)
        @test occursin("Plain", row)
    end

    # ─────────────────────────────────────────────────────────────────
    # Scrollbar
    # ─────────────────────────────────────────────────────────────────

    @testset "Scrollbar: basic rendering" begin
        sb = T.Scrollbar(20, 5, 0)
        buf = T.Buffer(T.Rect(1, 1, 1, 10))
        T.render(sb, T.Rect(1, 1, 1, 10), buf)
        # Should have thumb at top and track below
        found_thumb = false
        found_track = false
        for y in 1:10
            c = buf.content[T.buf_index(buf, 1, y)].char
            if c == '█'
                found_thumb = true
            elseif c == '│'
                found_track = true
            end
        end
        @test found_thumb
        @test found_track
    end

    @testset "Scrollbar: no scroll needed" begin
        sb = T.Scrollbar(5, 10, 0)  # visible > total
        buf = T.Buffer(T.Rect(1, 1, 1, 10))
        T.render(sb, T.Rect(1, 1, 1, 10), buf)
        # Nothing rendered when total <= visible
        @test buf.content[1].char == ' '
    end

    @testset "Scrollbar: position at end" begin
        sb = T.Scrollbar(20, 5, 15)  # max offset
        buf = T.Buffer(T.Rect(1, 1, 1, 10))
        T.render(sb, T.Rect(1, 1, 1, 10), buf)
        # Thumb should be near the bottom
        @test buf.content[T.buf_index(buf, 1, 10)].char == '█'
    end

    @testset "Scrollbar: position at middle" begin
        sb = T.Scrollbar(20, 5, 7)  # roughly middle
        buf = T.Buffer(T.Rect(1, 1, 1, 10))
        T.render(sb, T.Rect(1, 1, 1, 10), buf)
        # Should have track at top, thumb in middle area, track at bottom
        @test buf.content[T.buf_index(buf, 1, 1)].char == '│'
    end

    @testset "Scrollbar: negative offset clamped" begin
        sb = T.Scrollbar(20, 5, -3)
        @test sb.offset == 0
    end

    @testset "Scrollbar: total equals visible" begin
        sb = T.Scrollbar(5, 5, 0)
        buf = T.Buffer(T.Rect(1, 1, 1, 5))
        T.render(sb, T.Rect(1, 1, 1, 5), buf)
        # total == visible → no scrollbar
        @test buf.content[1].char == ' '
    end

    # ─────────────────────────────────────────────────────────────────
    # Separator (additional coverage beyond existing tests)
    # ─────────────────────────────────────────────────────────────────

    @testset "Separator: style propagation" begin
        red = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        sep = T.Separator(style=red)
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.render(sep, T.Rect(1, 1, 10, 1), buf)
        @test buf.content[1].style.fg == T.ColorRGB(0xff, 0x00, 0x00)
    end

    @testset "Separator: custom chars" begin
        sep = T.Separator(char_h='=')
        buf = T.Buffer(T.Rect(1, 1, 5, 1))
        T.render(sep, T.Rect(1, 1, 5, 1), buf)
        @test buf.content[1].char == '='
    end

    @testset "Separator: vertical fills height" begin
        sep = T.Separator(direction=T.Vertical)
        buf = T.Buffer(T.Rect(1, 1, 1, 5))
        T.render(sep, T.Rect(1, 1, 1, 5), buf)
        for y in 1:5
            @test buf.content[T.buf_index(buf, 1, y)].char == '│'
        end
    end

    # ─────────────────────────────────────────────────────────────────
    # BlockCanvas
    # ─────────────────────────────────────────────────────────────────

    @testset "BlockCanvas: basic rendering" begin
        bc = T.BlockCanvas(5, 5)
        T.set_point!(bc, 0, 0)  # top-left dot
        buf = T.Buffer(T.Rect(1, 1, 5, 5))
        T.render(bc, T.Rect(1, 1, 5, 5), buf)
        # Dot at (0,0) → cell (1,1), top-left quadrant = ▘
        @test buf.content[1].char == '▘'
    end

    @testset "BlockCanvas: set_point! and unset_point!" begin
        bc = T.BlockCanvas(3, 3)
        T.set_point!(bc, 0, 0)
        @test bc.dots[1, 1] == 0x01  # top-left bit
        T.set_point!(bc, 1, 0)       # top-right
        @test bc.dots[1, 1] == 0x03  # both top bits
        T.unset_point!(bc, 0, 0)
        @test bc.dots[1, 1] == 0x02  # only top-right remains
    end

    @testset "BlockCanvas: full block" begin
        bc = T.BlockCanvas(1, 1)
        T.set_point!(bc, 0, 0)  # top-left
        T.set_point!(bc, 1, 0)  # top-right
        T.set_point!(bc, 0, 1)  # bottom-left
        T.set_point!(bc, 1, 1)  # bottom-right
        buf = T.Buffer(T.Rect(1, 1, 1, 1))
        T.render(bc, T.Rect(1, 1, 1, 1), buf)
        @test buf.content[1].char == '█'  # full block
    end

    @testset "BlockCanvas: clear!" begin
        bc = T.BlockCanvas(3, 3)
        T.set_point!(bc, 0, 0)
        T.set_point!(bc, 2, 2)
        T.clear!(bc)
        @test all(bc.dots .== 0x00)
    end

    @testset "BlockCanvas: line!" begin
        bc = T.BlockCanvas(5, 5)
        T.line!(bc, 0, 0, 9, 9)  # diagonal through the canvas
        # Should have set some dots along the diagonal
        @test any(bc.dots .!= 0x00)
    end

    @testset "BlockCanvas: rect!" begin
        bc = T.BlockCanvas(5, 5)
        T.rect!(bc, 0, 0, 9, 9)
        # Should have dots on edges
        @test bc.dots[1, 1] != 0x00  # top-left corner
        @test bc.dots[5, 5] != 0x00  # bottom-right corner
    end

    @testset "BlockCanvas: circle!" begin
        bc = T.BlockCanvas(10, 10)
        T.circle!(bc, 10, 10, 5)
        @test any(bc.dots .!= 0x00)
    end

    @testset "BlockCanvas: arc!" begin
        bc = T.BlockCanvas(10, 10)
        T.arc!(bc, 10, 10, 5, 0.0, 180.0)
        @test any(bc.dots .!= 0x00)
    end

    @testset "BlockCanvas: canvas_dot_size" begin
        bc = T.BlockCanvas(10, 8)
        @test T.canvas_dot_size(bc) == (20, 16)
    end

    @testset "BlockCanvas: out of bounds set_point!" begin
        bc = T.BlockCanvas(3, 3)
        # Negative coordinates — should not crash
        T.set_point!(bc, -1, -1)
        @test all(bc.dots .== 0x00)
        # Beyond bounds — should not crash
        T.set_point!(bc, 100, 100)
        @test all(bc.dots .== 0x00)
    end

    @testset "BlockCanvas: quadrant mapping" begin
        bc = T.BlockCanvas(1, 1)
        # Bottom-left only
        T.set_point!(bc, 0, 1)
        buf = T.Buffer(T.Rect(1, 1, 1, 1))
        T.render(bc, T.Rect(1, 1, 1, 1), buf)
        @test buf.content[1].char == '▖'

        # Bottom-right only
        T.clear!(bc)
        T.set_point!(bc, 1, 1)
        buf = T.Buffer(T.Rect(1, 1, 1, 1))
        T.render(bc, T.Rect(1, 1, 1, 1), buf)
        @test buf.content[1].char == '▗'

        # Upper half
        T.clear!(bc)
        T.set_point!(bc, 0, 0)
        T.set_point!(bc, 1, 0)
        buf = T.Buffer(T.Rect(1, 1, 1, 1))
        T.render(bc, T.Rect(1, 1, 1, 1), buf)
        @test buf.content[1].char == '▀'

        # Lower half
        T.clear!(bc)
        T.set_point!(bc, 0, 1)
        T.set_point!(bc, 1, 1)
        buf = T.Buffer(T.Rect(1, 1, 1, 1))
        T.render(bc, T.Rect(1, 1, 1, 1), buf)
        @test buf.content[1].char == '▄'
    end

    # ─────────────────────────────────────────────────────────────────
    # ProgressList
    # ─────────────────────────────────────────────────────────────────

    @testset "ProgressList: all task states" begin
        items = [
            T.ProgressItem("Pending"; status=T.task_pending),
            T.ProgressItem("Running"; status=T.task_running),
            T.ProgressItem("Done"; status=T.task_done),
            T.ProgressItem("Error"; status=T.task_error),
            T.ProgressItem("Skipped"; status=T.task_skipped),
        ]
        pl = T.ProgressList(items; tick=0)
        tb = T.TestBackend(40, 6)
        T.render_widget!(tb, pl)
        # Check status icons
        @test T.char_at(tb, 1, 1) == '○'  # pending
        @test T.char_at(tb, 1, 3) == '✓'  # done
        @test T.char_at(tb, 1, 4) == '✗'  # error
        @test T.char_at(tb, 1, 5) == '–'  # skipped
        # Running uses spinner braille
        c = T.char_at(tb, 1, 2)
        @test c in T.SPINNER_BRAILLE
    end

    @testset "ProgressList: labels rendered" begin
        items = [
            T.ProgressItem("Install packages"; status=T.task_done),
            T.ProgressItem("Run tests"; status=T.task_running),
        ]
        pl = T.ProgressList(items; tick=0)
        tb = T.TestBackend(40, 3)
        T.render_widget!(tb, pl)
        @test occursin("Install packages", T.row_text(tb, 1))
        @test occursin("Run tests", T.row_text(tb, 2))
    end

    @testset "ProgressList: detail text right-aligned" begin
        items = [
            T.ProgressItem("Task"; status=T.task_done, detail="2.3s"),
        ]
        pl = T.ProgressList(items)
        tb = T.TestBackend(40, 1)
        T.render_widget!(tb, pl)
        row = T.row_text(tb, 1)
        @test occursin("2.3s", row)
        # Detail should be right-aligned
        pos = findfirst("2.3s", row)
        @test first(pos) > 20  # should be near the right
    end

    @testset "ProgressList: empty list" begin
        pl = T.ProgressList(T.ProgressItem[])
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, pl)
        @test T.char_at(tb, 1, 1) == ' '
    end

    @testset "ProgressList: many items truncation" begin
        items = [T.ProgressItem("Item $i"; status=T.task_pending) for i in 1:20]
        pl = T.ProgressList(items)
        tb = T.TestBackend(30, 3)
        T.render_widget!(tb, pl)
        # Should only render 3 items (height=3)
        @test occursin("Item 1", T.row_text(tb, 1))
        @test occursin("Item 3", T.row_text(tb, 3))
    end

    @testset "ProgressList: with block" begin
        items = [T.ProgressItem("Test"; status=T.task_done)]
        pl = T.ProgressList(items; block=T.Block(title="Tasks"))
        tb = T.TestBackend(30, 5)
        T.render_widget!(tb, pl)
        @test occursin("Tasks", T.row_text(tb, 1))
    end

    @testset "ProgressList: status_icon" begin
        icon_pending, field_pending = T.status_icon(T.task_pending, nothing)
        @test icon_pending == '○'
        @test field_pending == :pending_style

        icon_done, field_done = T.status_icon(T.task_done, nothing)
        @test icon_done == '✓'
        @test field_done == :done_style

        icon_error, field_error = T.status_icon(T.task_error, nothing)
        @test icon_error == '✗'
        @test field_error == :error_style

        icon_skipped, field_skipped = T.status_icon(T.task_skipped, nothing)
        @test icon_skipped == '–'
        @test field_skipped == :skipped_style
    end

    @testset "ProgressList: spinner animation varies with tick" begin
        icon1, _ = T.status_icon(T.task_running, 0)
        icon2, _ = T.status_icon(T.task_running, 3)
        # Different ticks should produce different spinner frames
        @test icon1 in T.SPINNER_BRAILLE
        @test icon2 in T.SPINNER_BRAILLE
        @test icon1 != icon2
    end

    @testset "ProgressList: done/error label styles" begin
        items = [
            T.ProgressItem("OK"; status=T.task_done),
            T.ProgressItem("Fail"; status=T.task_error),
        ]
        done_style = T.Style(fg=T.ColorRGB(0x00, 0xff, 0x00))
        error_style = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        pl = T.ProgressList(items; done_style=done_style, error_style=error_style)
        tb = T.TestBackend(30, 2)
        T.render_widget!(tb, pl)
        # Label for done item at col 3 (icon + space + label)
        @test T.style_at(tb, 3, 1).fg == T.ColorRGB(0x00, 0xff, 0x00)
        @test T.style_at(tb, 3, 2).fg == T.ColorRGB(0xff, 0x00, 0x00)
    end

    # ─────────────────────────────────────────────────────────────────
    # Paragraph alignment/wrap (verifying indirect coverage)
    # ─────────────────────────────────────────────────────────────────

    @testset "Paragraph: align_left default" begin
        p = T.Paragraph("hi"; wrap=T.no_wrap, alignment=T.align_left)
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.render(p, T.Rect(1, 1, 10, 1), buf)
        @test buf.content[1].char == 'h'
        @test buf.content[2].char == 'i'
    end

    @testset "Paragraph: no_wrap long text truncated" begin
        p = T.Paragraph("abcdefghijklmnop"; wrap=T.no_wrap)
        buf = T.Buffer(T.Rect(1, 1, 5, 1))
        T.render(p, T.Rect(1, 1, 5, 1), buf)
        @test buf.content[1].char == 'a'
        @test buf.content[5].char == 'e'
    end

    @testset "Paragraph: word_wrap preserves words" begin
        p = T.Paragraph("one two three"; wrap=T.word_wrap)
        buf = T.Buffer(T.Rect(1, 1, 6, 3))
        T.render(p, T.Rect(1, 1, 6, 3), buf)
        row1 = String([buf.content[T.buf_index(buf, i, 1)].char for i in 1:6])
        row2 = String([buf.content[T.buf_index(buf, i, 2)].char for i in 1:6])
        # "one" on row1, "two" on row2 (word-wrapped)
        @test occursin("one", row1)
        @test occursin("two", row2)
    end

    # ─────────────────────────────────────────────────────────────────
    # DataTable detail_scroll clamping
    # ─────────────────────────────────────────────────────────────────

    @testset "DataTable: detail_scroll clamped in handle_key!" begin
        cols = [T.DataColumn("A", [1, 2]), T.DataColumn("B", [3, 4])]
        dt = T.DataTable(cols; selected=1, detail_fn=T.datatable_detail)
        dt.show_detail = true
        dt.detail_row = 1
        dt.detail_scroll = 0
        # Scroll down repeatedly — should clamp, not grow unbounded
        for _ in 1:20
            T.handle_key!(dt, T.KeyEvent(:down))
        end
        @test dt.detail_scroll <= length(cols) - 1
    end

    @testset "DataTable: detail_scroll stays at 0 on up from 0" begin
        cols = [T.DataColumn("X", [1])]
        dt = T.DataTable(cols; selected=1, detail_fn=T.datatable_detail)
        dt.show_detail = true
        dt.detail_row = 1
        dt.detail_scroll = 0
        T.handle_key!(dt, T.KeyEvent(:up))
        @test dt.detail_scroll == 0
    end

    # ─────────────────────────────────────────────────────────────────
    # TreeView cache
    # ─────────────────────────────────────────────────────────────────

    @testset "TreeView: cache populated on first access" begin
        root = T.TreeNode("root", [
            T.TreeNode("a"),
            T.TreeNode("b"),
        ])
        tv = T.TreeView(root; selected=1)
        @test tv._flat_dirty
        # Render triggers cache population
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(tv, T.Rect(1, 1, 30, 10), buf)
        @test !tv._flat_dirty
        @test length(tv._flat_cache) == 3  # root + a + b
    end

    @testset "TreeView: cache reused on second render" begin
        root = T.TreeNode("root", [T.TreeNode("child")])
        tv = T.TreeView(root; selected=1)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(tv, T.Rect(1, 1, 20, 5), buf)
        cache_ref = tv._flat_cache
        # Second render without mutation reuses same cache object
        T.render(tv, T.Rect(1, 1, 20, 5), buf)
        @test tv._flat_cache === cache_ref
    end

    @testset "TreeView: collapse invalidates cache" begin
        root = T.TreeNode("root", [
            T.TreeNode("a", [T.TreeNode("a1")]),
        ])
        tv = T.TreeView(root; selected=1, focused=true)
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(tv, T.Rect(1, 1, 30, 10), buf)
        @test length(tv._flat_cache) == 3  # root, a, a1

        # Select "a" (row 2) and collapse via left
        tv.selected = 2
        T.handle_key!(tv, T.KeyEvent(:left))
        @test tv._flat_dirty

        # Re-render: cache should now have 2 rows (a1 hidden)
        T.render(tv, T.Rect(1, 1, 30, 10), buf)
        @test length(tv._flat_cache) == 2
    end

    @testset "TreeView: expand invalidates cache" begin
        child = T.TreeNode("child"; expanded=false)
        root = T.TreeNode("root", [
            T.TreeNode("a", [child]),
        ])
        tv = T.TreeView(root; selected=1, focused=true)
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(tv, T.Rect(1, 1, 30, 10), buf)
        initial_len = length(tv._flat_cache)

        # Select "a" (row 2) and expand child via toggle
        tv.selected = 2
        T.handle_key!(tv, T.KeyEvent(:enter))
        @test tv._flat_dirty
    end

    @testset "TreeView: navigation does not invalidate cache" begin
        root = T.TreeNode("root", [T.TreeNode("a"), T.TreeNode("b")])
        tv = T.TreeView(root; selected=1, focused=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(tv, T.Rect(1, 1, 20, 5), buf)
        @test !tv._flat_dirty

        # Simple up/down navigation should not dirty the cache
        T.handle_key!(tv, T.KeyEvent(:down))
        @test !tv._flat_dirty
        @test tv.selected == 2
        T.handle_key!(tv, T.KeyEvent(:up))
        @test !tv._flat_dirty
        @test tv.selected == 1
    end
