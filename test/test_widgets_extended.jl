    # ═════════════════════════════════════════════════════════════════
    # ScrollPane
    # ═════════════════════════════════════════════════════════════════

    @testset "ScrollPane: basic string rendering" begin
        sp = T.ScrollPane(["line1", "line2", "line3", "line4", "line5"];
                          following=false)
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(sp, T.Rect(1, 1, 20, 3), buf)
        # First 3 lines visible (offset=0)
        @test buf.content[T.buf_index(buf, 1, 1)].char == 'l'
        @test buf.content[T.buf_index(buf, 5, 1)].char == '1'
        @test buf.content[T.buf_index(buf, 5, 2)].char == '2'
        @test buf.content[T.buf_index(buf, 5, 3)].char == '3'
    end

    @testset "ScrollPane: scrolled rendering" begin
        sp = T.ScrollPane(["line1", "line2", "line3", "line4", "line5"];
                          offset=2, following=false)
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(sp, T.Rect(1, 1, 20, 3), buf)
        # Lines 3-5 visible
        @test buf.content[T.buf_index(buf, 5, 1)].char == '3'
        @test buf.content[T.buf_index(buf, 5, 2)].char == '4'
        @test buf.content[T.buf_index(buf, 5, 3)].char == '5'
    end

    @testset "ScrollPane: auto-follow" begin
        lines = ["line1", "line2", "line3"]
        sp = T.ScrollPane(lines; following=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 2))
        T.render(sp, T.Rect(1, 1, 20, 2), buf)
        # After first render, offset should be at end (3-2=1)
        @test sp.offset == 1

        # Push new lines — offset should snap to new end
        T.push_line!(sp, "line4")
        T.push_line!(sp, "line5")
        T.render(sp, T.Rect(1, 1, 20, 2), buf)
        @test sp.offset == 3  # 5 lines - 2 visible = 3
        @test sp.following
    end

    @testset "ScrollPane: detach on manual scroll" begin
        lines = ["line$i" for i in 1:10]
        sp = T.ScrollPane(lines; following=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        @test sp.following

        evt = T.KeyEvent(:up)
        @test T.handle_key!(sp, evt)
        @test !sp.following
    end

    @testset "ScrollPane: re-attach at end" begin
        lines = ["line$i" for i in 1:10]
        sp = T.ScrollPane(lines; following=false, offset=0)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        @test !sp.following

        evt = T.KeyEvent(:end_key)
        T.handle_key!(sp, evt)
        @test sp.following
        @test sp.offset == 5  # 10 - 5 = 5
    end

    @testset "ScrollPane: reverse mode" begin
        lines = ["old1", "old2", "old3", "new1", "new2"]
        sp = T.ScrollPane(lines; reverse=true, following=false, offset=0)
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(sp, T.Rect(1, 1, 20, 3), buf)
        # offset=0, reverse: newest at top
        # idx for row 1: n - 0 - 1 + 1 = 5 → "new2"
        # idx for row 2: n - 0 - 2 + 1 = 4 → "new1"
        # idx for row 3: n - 0 - 3 + 1 = 3 → "old3"
        @test buf.content[T.buf_index(buf, 1, 1)].char == 'n'  # "new2"
        @test buf.content[T.buf_index(buf, 4, 1)].char == '2'
        @test buf.content[T.buf_index(buf, 4, 2)].char == '1'  # "new1"
        @test buf.content[T.buf_index(buf, 1, 3)].char == 'o'  # "old3"
    end

    @testset "ScrollPane: reverse mode scroll" begin
        lines = ["old1", "old2", "old3", "new1", "new2"]
        sp = T.ScrollPane(lines; reverse=true, following=false, offset=2)
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(sp, T.Rect(1, 1, 20, 3), buf)
        # offset=2, reverse: reveals older lines
        # idx for row 1: 5 - 2 - 1 + 1 = 3 → "old3"
        # idx for row 2: 5 - 2 - 2 + 1 = 2 → "old2"
        # idx for row 3: 5 - 2 - 3 + 1 = 1 → "old1"
        @test buf.content[T.buf_index(buf, 4, 1)].char == '3'  # "old3"
        @test buf.content[T.buf_index(buf, 4, 2)].char == '2'  # "old2"
        @test buf.content[T.buf_index(buf, 4, 3)].char == '1'  # "old1"
    end

    @testset "ScrollPane: styled Span rendering" begin
        red_style = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        lines = [
            [T.Span("hello", red_style)],
            [T.Span("world", red_style)],
        ]
        sp = T.ScrollPane(lines; following=false)
        buf = T.Buffer(T.Rect(1, 1, 20, 2))
        T.render(sp, T.Rect(1, 1, 20, 2), buf)
        @test buf.content[T.buf_index(buf, 1, 1)].char == 'h'
        @test buf.content[T.buf_index(buf, 1, 1)].style.fg == T.ColorRGB(0xff, 0x00, 0x00)
        @test buf.content[T.buf_index(buf, 1, 2)].char == 'w'
    end

    @testset "ScrollPane: scrollbar appears when content exceeds height" begin
        lines = ["line$i" for i in 1:10]
        sp = T.ScrollPane(lines; following=false, show_scrollbar=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        # Scrollbar renders in rightmost column (col 20)
        # Should have thumb '█' or track '│' chars
        scrollbar_col = 20
        found_scrollbar = false
        for row in 1:5
            c = buf.content[T.buf_index(buf, scrollbar_col, row)].char
            if c == '█' || c == '│'
                found_scrollbar = true
                break
            end
        end
        @test found_scrollbar
    end

    @testset "ScrollPane: no scrollbar when content fits" begin
        lines = ["line1", "line2"]
        sp = T.ScrollPane(lines; following=false, show_scrollbar=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        # No scrollbar needed — rightmost col should be empty
        @test buf.content[T.buf_index(buf, 20, 1)].char == ' '
    end

    @testset "ScrollPane: mouse scroll changes offset" begin
        lines = ["line$i" for i in 1:20]
        sp = T.ScrollPane(lines; following=false, offset=5)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)

        evt_down = T.MouseEvent(10, 3, T.mouse_scroll_down, T.mouse_press,
                                false, false, false)
        @test T.handle_mouse!(sp, evt_down)
        @test sp.offset == 6

        evt_up = T.MouseEvent(10, 3, T.mouse_scroll_up, T.mouse_press,
                              false, false, false)
        @test T.handle_mouse!(sp, evt_up)
        @test sp.offset == 5
    end

    @testset "ScrollPane: key handling comprehensive" begin
        lines = ["line$i" for i in 1:20]
        sp = T.ScrollPane(lines; following=false, offset=5)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)

        # Up
        T.handle_key!(sp, T.KeyEvent(:up))
        @test sp.offset == 4
        # Down
        T.handle_key!(sp, T.KeyEvent(:down))
        @test sp.offset == 5
        # Page down
        T.handle_key!(sp, T.KeyEvent(:pagedown))
        @test sp.offset == 10
        # Page up
        T.handle_key!(sp, T.KeyEvent(:pageup))
        @test sp.offset == 5
        # Home
        T.handle_key!(sp, T.KeyEvent(:home))
        @test sp.offset == 0
        # End
        T.handle_key!(sp, T.KeyEvent(:end_key))
        @test sp.offset == 15  # 20 - 5
        # Unhandled key returns false
        @test !T.handle_key!(sp, T.KeyEvent('x'))
    end

    @testset "ScrollPane: callback mode" begin
        called_with = Ref{Any}(nothing)
        function my_render(buf, area, offset)
            called_with[] = (area, offset)
        end
        sp = T.ScrollPane(my_render, 100; following=false, offset=10)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        @test called_with[] !== nothing
        area, offset = called_with[]
        @test offset == 10
        @test area.width > 0
    end

    @testset "ScrollPane: empty content no crash" begin
        sp = T.ScrollPane(String[]; following=false)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(sp, T.Rect(1, 1, 20, 5), buf)
        @test true  # no crash
        # Key handling on empty
        @test T.handle_key!(sp, T.KeyEvent(:down))
        @test sp.offset == 0  # clamped to 0
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 1: Paragraph wrapping + alignment
    # ═════════════════════════════════════════════════════════════════

    @testset "Paragraph word_wrap" begin
        p = T.Paragraph("hello world test"; wrap=T.word_wrap)
        buf = T.Buffer(T.Rect(1, 1, 8, 5))
        T.render(p, T.Rect(1, 1, 8, 5), buf)
        # "hello" fits on line 1 (5 chars <= 8)
        @test buf.content[1].char == 'h'
        # "world" on line 1 too (5+1+5 = 11 > 8) or line 2
        row1 = String([buf.content[i].char for i in 1:8])
        row2 = String([buf.content[T.buf_index(buf, i, 2)].char for i in 1:8])
        @test occursin("hello", row1)
        @test occursin("world", row2) || occursin("world", row1)
    end

    @testset "Paragraph char_wrap" begin
        p = T.Paragraph("abcdefghij"; wrap=T.char_wrap)
        buf = T.Buffer(T.Rect(1, 1, 5, 3))
        T.render(p, T.Rect(1, 1, 5, 3), buf)
        # First 5 chars on row 1
        @test buf.content[1].char == 'a'
        @test buf.content[5].char == 'e'
        # Next 5 on row 2
        @test buf.content[T.buf_index(buf, 1, 2)].char == 'f'
        @test buf.content[T.buf_index(buf, 5, 2)].char == 'j'
    end

    @testset "Paragraph align_center" begin
        p = T.Paragraph("hi"; wrap=T.no_wrap, alignment=T.align_center)
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.render(p, T.Rect(1, 1, 10, 1), buf)
        # "hi" is 2 chars, centered in 10 → offset 4
        @test buf.content[5].char == 'h'
        @test buf.content[6].char == 'i'
    end

    @testset "Paragraph align_right" begin
        p = T.Paragraph("hi"; wrap=T.no_wrap, alignment=T.align_right)
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        T.render(p, T.Rect(1, 1, 10, 1), buf)
        # "hi" right-aligned → at positions 9, 10
        @test buf.content[9].char == 'h'
        @test buf.content[10].char == 'i'
    end

    @testset "Paragraph scroll_offset" begin
        text = "line1\nline2\nline3\nline4\nline5"
        p = T.Paragraph(text; wrap=T.char_wrap, scroll_offset=2)
        buf = T.Buffer(T.Rect(1, 1, 20, 2))
        T.render(p, T.Rect(1, 1, 20, 2), buf)
        # With offset=2, should show line3 and line4
        row1 = String([buf.content[T.buf_index(buf, i, 1)].char for i in 1:5])
        @test occursin("line3", row1)
    end

    @testset "Paragraph backward compat" begin
        # Original no-wrap, no-alignment usage still works
        p = T.Paragraph("hello")
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        T.render(p, T.Rect(1, 1, 20, 1), buf)
        @test buf.content[1].char == 'h'
    end

    @testset "paragraph_line_count" begin
        p = T.Paragraph("hello world"; wrap=T.word_wrap)
        @test T.paragraph_line_count(p, 5) == 2  # "hello" + "world"
        @test T.paragraph_line_count(p, 20) == 1
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 1: Canvas shapes
    # ═════════════════════════════════════════════════════════════════

    @testset "Canvas rect!" begin
        c = T.Canvas(10, 5)
        T.rect!(c, 0, 0, 15, 15)
        @test any(c.dots .!= 0x00)
    end

    @testset "Canvas circle!" begin
        c = T.Canvas(10, 10)
        T.circle!(c, 10, 20, 8)
        @test any(c.dots .!= 0x00)
    end

    @testset "Canvas arc!" begin
        c = T.Canvas(10, 10)
        T.arc!(c, 10, 20, 8, 0.0, 180.0)
        @test any(c.dots .!= 0x00)
    end

    @testset "Canvas shapes on PixelCanvas" begin
        sc = T.PixelCanvas(10, 5)
        T.rect!(sc, 0, 0, 5, 5)
        @test any(px != T.ColorRGB(0,0,0) for px in sc.pixels)
        T.clear!(sc)
        T.circle!(sc, 5, 10, 5)
        @test any(px != T.ColorRGB(0,0,0) for px in sc.pixels)
        T.clear!(sc)
        T.arc!(sc, 5, 10, 5, 0.0, 90.0)
        @test any(px != T.ColorRGB(0,0,0) for px in sc.pixels)
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 1: Layout flex modes
    # ═════════════════════════════════════════════════════════════════

    @testset "Layout align_center" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20), T.Fixed(20)]; align=T.layout_center), r)
        @test length(rects) == 2
        # 40 used, 60 leftover → offset 30
        @test rects[1].x == 31
        @test rects[2].x == 51
    end

    @testset "Layout align_end" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20), T.Fixed(20)]; align=T.layout_end), r)
        # 40 used, 60 leftover → offset 60
        @test rects[1].x == 61
    end

    @testset "Layout space_between" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(10), T.Fixed(10), T.Fixed(10)];
                     align=T.layout_space_between), r)
        @test rects[1].x == 1
        @test rects[1].width == 10
        @test rects[3].width == 10
        # 70 leftover / 2 gaps = 35 each
        @test rects[2].x > 11
        @test rects[3].x > rects[2].x + 10
    end

    @testset "Layout default is layout_start" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20)]), r)
        @test rects[1].x == 1
    end

    @testset "Layout space_around" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(10), T.Fixed(10), T.Fixed(10)];
                     align=T.layout_space_around), r)
        @test length(rects) == 3
        # 70 leftover, 3 items → edge gap ≈ 70/6 ≈ 12, between gap ≈ 70/3 ≈ 23
        edge_left = rects[1].x - 1
        gap_1_2 = rects[2].x - (rects[1].x + rects[1].width)
        gap_2_3 = rects[3].x - (rects[2].x + rects[2].width)
        # Edge gaps should be approximately half of between-item gaps
        @test abs(gap_1_2 - 2 * edge_left) <= 1
        @test abs(gap_1_2 - gap_2_3) <= 1
    end

    @testset "Layout space_evenly" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(10), T.Fixed(10), T.Fixed(10)];
                     align=T.layout_space_evenly), r)
        @test length(rects) == 3
        # 70 leftover, 4 gaps → each ≈ 17-18
        edge_left = rects[1].x - 1
        gap_1_2 = rects[2].x - (rects[1].x + rects[1].width)
        gap_2_3 = rects[3].x - (rects[2].x + rects[2].width)
        edge_right = 100 - (rects[3].x + rects[3].width - 1)
        # All four gaps should be approximately equal
        @test abs(edge_left - gap_1_2) <= 1
        @test abs(gap_1_2 - gap_2_3) <= 1
        @test abs(gap_2_3 - edge_right) <= 2
    end

    @testset "Layout positive spacing" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fill(), T.Fill()]; spacing=10), r)
        @test length(rects) == 2
        # effective_total = 100 - 10 = 90, each Fill gets 45
        @test rects[1].width == 45
        @test rects[2].width == 45
        # Gap between them should be 10
        @test rects[2].x - (rects[1].x + rects[1].width) == 10
    end

    @testset "Layout negative spacing (overlap)" begin
        r = T.Rect(1, 1, 100, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(30), T.Fixed(30)]; spacing=-5), r)
        @test length(rects) == 2
        @test rects[1].width == 30
        @test rects[2].width == 30
        # Items should overlap by 5
        @test rects[2].x == rects[1].x + 30 - 5
    end

    @testset "Layout Ratio constraint" begin
        r = T.Rect(1, 1, 120, 24)
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Ratio(1, 3), T.Ratio(2, 3)]), r)
        @test length(rects) == 2
        @test rects[1].width == 40
        @test rects[2].width == 80
    end

    @testset "Layout split_with_spacers" begin
        r = T.Rect(1, 1, 100, 24)
        layout = T.Layout(T.Horizontal, [T.Fixed(20), T.Fixed(20), T.Fixed(20)]; spacing=5)
        rects, spacers = T.split_with_spacers(layout, r)
        @test length(rects) == 3
        @test length(spacers) == 4   # N+1: leading + 2 between + trailing
        @test spacers[1].width == 0  # leading edge (blocks start at rect.x)
        @test spacers[2].width == 5  # between block 1 and 2
        @test spacers[3].width == 5  # between block 2 and 3
        @test spacers[4].width == 30 # trailing edge (100 - 3*20 - 2*5 = 30)
    end

    @testset "Layout split_with_spacers single item" begin
        r = T.Rect(1, 1, 100, 24)
        layout = T.Layout(T.Horizontal, [T.Fixed(20)]; spacing=5)
        rects, spacers = T.split_with_spacers(layout, r)
        @test length(rects) == 1
        @test length(spacers) == 2   # N+1: leading + trailing
        @test spacers[1].width == 0  # leading edge
        @test spacers[2].width == 80 # trailing edge (100 - 20 = 80)
    end

    @testset "Layout single item edge cases" begin
        r = T.Rect(1, 1, 100, 24)
        # spacing has no effect with single item
        rects = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20)]; spacing=10), r)
        @test rects[1].x == 1
        @test rects[1].width == 20

        # space_around centers single item
        rects2 = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20)]; align=T.layout_space_around), r)
        @test rects2[1].x == 1 + round(Int, 80 / 2)  # leftover/2n where n=1

        # space_evenly centers single item
        rects3 = T.split_layout(
            T.Layout(T.Horizontal, [T.Fixed(20)]; align=T.layout_space_evenly), r)
        @test rects3[1].x == 1 + round(Int, 80 / 2)  # leftover/(n+1) where n=1
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 1: TestBackend
    # ═════════════════════════════════════════════════════════════════

    @testset "TestBackend basic" begin
        tb = T.TestBackend(30, 5)
        p = T.Paragraph("hello world")
        T.render_widget!(tb, p)
        @test T.char_at(tb, 1, 1) == 'h'
        @test T.char_at(tb, 7, 1) == 'w'
        @test T.char_at(tb, 99, 99) == ' '
    end

    @testset "TestBackend row_text and find_text" begin
        tb = T.TestBackend(30, 3)
        p = T.Paragraph("line1\nline2\nfind me here")
        T.render_widget!(tb, p)
        @test startswith(T.row_text(tb, 1), "line1")
        result = T.find_text(tb, "find me")
        @test result !== nothing
        @test result.y == 3
    end

    @testset "TestBackend style_at" begin
        tb = T.TestBackend(20, 1)
        s = T.Style(fg=T.ColorRGB(0xff, 0x00, 0x00))
        p = T.Paragraph([T.Span("red", s)])
        T.render_widget!(tb, p)
        @test T.style_at(tb, 1, 1).fg == T.ColorRGB(0xff, 0x00, 0x00)
        @test T.style_at(tb, 99, 99) == T.RESET
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 2: Separator
    # ═════════════════════════════════════════════════════════════════

    @testset "Separator horizontal" begin
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        sep = T.Separator(direction=T.Horizontal)
        T.render(sep, T.Rect(1, 1, 20, 1), buf)
        @test buf.content[1].char == '─'
        @test buf.content[10].char == '─'
    end

    @testset "Separator vertical" begin
        buf = T.Buffer(T.Rect(1, 1, 1, 10))
        sep = T.Separator(direction=T.Vertical)
        T.render(sep, T.Rect(1, 1, 1, 10), buf)
        @test buf.content[1].char == '│'
    end

    @testset "Separator with label" begin
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        sep = T.Separator(label="test")
        T.render(sep, T.Rect(1, 1, 20, 1), buf)
        # Label should appear centered
        row = String([buf.content[i].char for i in 1:20])
        @test occursin("test", row)
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 2: Checkbox
    # ═════════════════════════════════════════════════════════════════

    @testset "Checkbox toggle" begin
        cb = T.Checkbox("agree"; focused=true)
        @test !cb.checked
        T.handle_key!(cb, T.KeyEvent(:enter))
        @test cb.checked
        T.handle_key!(cb, T.KeyEvent(:enter))
        @test !cb.checked
    end

    @testset "Checkbox render" begin
        cb = T.Checkbox("test"; checked=true)
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        T.render(cb, T.Rect(1, 1, 20, 1), buf)
        @test buf.content[1].char == '☑'
    end

    @testset "Checkbox unfocused ignores" begin
        cb = T.Checkbox("test"; focused=false)
        @test !T.handle_key!(cb, T.KeyEvent(:enter))
        @test !cb.checked
    end

    @testset "checkbox value()" begin
        cb = T.Checkbox("x"; checked=true)
        @test T.value(cb) == true
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 2: RadioGroup
    # ═════════════════════════════════════════════════════════════════

    @testset "RadioGroup navigation and selection" begin
        rg = T.RadioGroup(["A", "B", "C"]; selected=1, focused=true)
        @test rg.selected == 1
        T.handle_key!(rg, T.KeyEvent(:down))
        @test rg.cursor == 2
        T.handle_key!(rg, T.KeyEvent(:enter))
        @test rg.selected == 2
        T.handle_key!(rg, T.KeyEvent(:up))
        @test rg.cursor == 1
    end

    @testset "RadioGroup render" begin
        rg = T.RadioGroup(["A", "B"]; selected=1)
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(rg, T.Rect(1, 1, 20, 3), buf)
        @test buf.content[1].char == '◉'
        @test buf.content[T.buf_index(buf, 1, 2)].char == '○'
    end

    @testset "RadioGroup wrap around" begin
        rg = T.RadioGroup(["A", "B"]; focused=true)
        T.handle_key!(rg, T.KeyEvent(:up))
        @test rg.cursor == 2  # wraps to last
    end

    @testset "radiogroup value()" begin
        rg = T.RadioGroup(["A", "B", "C"]; selected=2)
        @test T.value(rg) == 2
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 2: Button
    # ═════════════════════════════════════════════════════════════════

    @testset "Button render" begin
        btn = T.Button("OK")
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        T.render(btn, T.Rect(1, 1, 20, 1), buf)
        row = String([buf.content[i].char for i in 1:20])
        @test occursin("[ OK ]", row)
    end

    @testset "Button handle_key" begin
        btn = T.Button("Go"; focused=true)
        @test T.handle_key!(btn, T.KeyEvent(:enter))
        @test !T.handle_key!(btn, T.KeyEvent(:up))  # not handled
    end

    @testset "Button unfocused ignores" begin
        btn = T.Button("Go"; focused=false)
        @test !T.handle_key!(btn, T.KeyEvent(:enter))
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 2: Input Validation
    # ═════════════════════════════════════════════════════════════════

    @testset "TextInput validator" begin
        # Validator: must be >= 3 chars
        v = s -> length(s) < 3 ? "Too short" : nothing
        input = T.TextInput(validator=v)
        T.handle_key!(input, T.KeyEvent('a'))
        @test !T.valid(input)
        @test input.error_msg == "Too short"
        T.handle_key!(input, T.KeyEvent('b'))
        T.handle_key!(input, T.KeyEvent('c'))
        @test T.valid(input)
        @test input.error_msg == ""
    end

    @testset "TextInput validator render" begin
        v = s -> isempty(s) ? "Required" : nothing
        input = T.TextInput(validator=v)
        buf = T.Buffer(T.Rect(1, 1, 30, 3))
        # Trigger validation
        T.handle_key!(input, T.KeyEvent(:backspace))
        T.render(input, T.Rect(1, 1, 30, 2), buf)
        # Error should appear on row 2
        row2 = String([buf.content[T.buf_index(buf, i, 2)].char for i in 1:8])
        @test occursin("Required", row2)
    end

    @testset "TextInput no validator" begin
        input = T.TextInput()
        @test T.valid(input)
        T.handle_key!(input, T.KeyEvent('x'))
        @test T.valid(input)
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 3: Scrollable Paragraph
    # ═════════════════════════════════════════════════════════════════

    @testset "Paragraph scroll via keyboard" begin
        text = join(["line$i" for i in 1:20], '\n')
        p = T.Paragraph(text; wrap=T.char_wrap)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(p, T.Rect(1, 1, 20, 5), buf)
        @test p.scroll_offset == 0
        T.handle_key!(p, T.KeyEvent(:down))
        @test p.scroll_offset == 1
        T.handle_key!(p, T.KeyEvent(:up))
        @test p.scroll_offset == 0
        T.handle_key!(p, T.KeyEvent(:pagedown))
        @test p.scroll_offset == 5
    end

    @testset "Paragraph scroll clamped" begin
        p = T.Paragraph("short"; wrap=T.char_wrap, scroll_offset=999)
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(p, T.Rect(1, 1, 20, 5), buf)
        @test p.scroll_offset == 0  # clamped: only 1 line
    end

    @testset "Paragraph no_wrap not scrollable" begin
        p = T.Paragraph("test")
        @test !T.focusable(p)
        @test !T.handle_key!(p, T.KeyEvent(:down))
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 3: DropDown
    # ═════════════════════════════════════════════════════════════════

    @testset "DropDown open/close" begin
        dd = T.DropDown(["A", "B", "C"])
        @test !dd.open
        T.handle_key!(dd, T.KeyEvent(:enter))
        @test dd.open
        T.handle_key!(dd, T.KeyEvent(:escape))
        @test !dd.open
    end

    @testset "DropDown navigate and select" begin
        dd = T.DropDown(["A", "B", "C"])
        T.handle_key!(dd, T.KeyEvent(:enter))  # open
        T.handle_key!(dd, T.KeyEvent(:down))
        @test dd.focused == 2
        T.handle_key!(dd, T.KeyEvent(:enter))  # select
        @test dd.selected == 2
        @test !dd.open
        @test T.value(dd) == "B"
    end

    @testset "DropDown render collapsed" begin
        dd = T.DropDown(["Alpha", "Beta"]; selected=1)
        buf = T.Buffer(T.Rect(1, 1, 20, 1))
        T.render(dd, T.Rect(1, 1, 20, 1), buf)
        row = String([buf.content[i].char for i in 1:20])
        @test occursin("Alpha", row)
    end

    @testset "DropDown render expanded" begin
        dd = T.DropDown(["A", "B", "C"])
        dd.open = true
        buf = T.Buffer(T.Rect(1, 1, 20, 5))
        T.render(dd, T.Rect(1, 1, 20, 5), buf)
        # Items should appear below
        row2 = String([buf.content[T.buf_index(buf, i, 2)].char for i in 1:20])
        @test occursin("A", row2)
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 3: TextArea
    # ═════════════════════════════════════════════════════════════════

    @testset "TextArea basic editing" begin
        ta = T.TextArea(text="hello")
        @test T.text(ta) == "hello"
        T.handle_key!(ta, T.KeyEvent(:enter))
        @test T.text(ta) == "hello\n"
        T.handle_key!(ta, T.KeyEvent('w'))
        @test T.text(ta) == "hello\nw"
    end

    @testset "TextArea multi-line navigation" begin
        ta = T.TextArea(text="abc\ndef")
        @test ta.cursor_row == 2
        T.handle_key!(ta, T.KeyEvent(:up))
        @test ta.cursor_row == 1
        T.handle_key!(ta, T.KeyEvent(:down))
        @test ta.cursor_row == 2
    end

    @testset "TextArea backspace joins lines" begin
        ta = T.TextArea(text="abc\ndef")
        ta.cursor_row = 2
        ta.cursor_col = 0
        T.handle_key!(ta, T.KeyEvent(:backspace))
        @test T.text(ta) == "abcdef"
        @test ta.cursor_row == 1
        @test ta.cursor_col == 3
    end

    @testset "TextArea enter splits line" begin
        ta = T.TextArea(text="abcdef")
        ta.cursor_col = 3
        T.handle_key!(ta, T.KeyEvent(:enter))
        @test T.text(ta) == "abc\ndef"
        @test ta.cursor_row == 2
        @test ta.cursor_col == 0
    end

    @testset "TextArea left wraps to prev line" begin
        ta = T.TextArea(text="abc\ndef")
        ta.cursor_row = 2
        ta.cursor_col = 0
        T.handle_key!(ta, T.KeyEvent(:left))
        @test ta.cursor_row == 1
        @test ta.cursor_col == 3
    end

    @testset "TextArea right wraps to next line" begin
        ta = T.TextArea(text="abc\ndef")
        ta.cursor_row = 1
        ta.cursor_col = 3
        T.handle_key!(ta, T.KeyEvent(:right))
        @test ta.cursor_row == 2
        @test ta.cursor_col == 0
    end

    @testset "TextArea clear! and set_text!" begin
        ta = T.TextArea(text="hello")
        T.clear!(ta)
        @test T.text(ta) == ""
        T.set_text!(ta, "new\ntext")
        @test T.text(ta) == "new\ntext"
        @test ta.cursor_row == 2
    end

    @testset "TextArea render" begin
        ta = T.TextArea(text="abc\ndef")
        buf = T.Buffer(T.Rect(1, 1, 20, 3))
        T.render(ta, T.Rect(1, 1, 20, 3), buf)
        @test buf.content[1].char == 'a'
        @test buf.content[T.buf_index(buf, 1, 2)].char == 'd'
    end

    @testset "TextArea unfocused ignores keys" begin
        ta = T.TextArea(text="test", focused=false)
        @test !T.handle_key!(ta, T.KeyEvent('x'))
        @test T.text(ta) == "test"
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 4: Chart
    # ═════════════════════════════════════════════════════════════════

    @testset "Chart render line" begin
        data = T.DataSeries([(1.0, 1.0), (2.0, 4.0), (3.0, 2.0)];
                            label="test", chart_type=T.chart_line)
        chart = T.Chart([data])
        buf = T.Buffer(T.Rect(1, 1, 40, 15))
        T.render(chart, T.Rect(1, 1, 40, 15), buf)
        # Should render axes
        found_axis = false
        for c in buf.content
            if c.char == '│' || c.char == '─' || c.char == '└'
                found_axis = true
                break
            end
        end
        @test found_axis
        # Should render braille data
        found_braille = false
        for c in buf.content
            code = UInt32(c.char)
            if code >= 0x2800 && code <= 0x28FF && code != 0x2800
                found_braille = true
                break
            end
        end
        @test found_braille
    end

    @testset "Chart render scatter" begin
        data = T.DataSeries([(1.0, 1.0), (5.0, 5.0)]; chart_type=T.chart_scatter)
        chart = T.Chart([data]; show_legend=false)
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(chart, T.Rect(1, 1, 30, 10), buf)
        @test true  # no crash
    end

    @testset "Chart with Float64 vector" begin
        data = T.DataSeries([1.0, 3.0, 2.0, 5.0])
        chart = T.Chart(data)
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(chart, T.Rect(1, 1, 30, 10), buf)
        @test true
    end

    @testset "Chart empty data" begin
        chart = T.Chart(T.DataSeries[])
        buf = T.Buffer(T.Rect(1, 1, 30, 10))
        T.render(chart, T.Rect(1, 1, 30, 10), buf)
        @test true  # no crash
    end

    @testset "Chart multi series" begin
        s1 = T.DataSeries([1.0, 2.0, 3.0]; label="s1",
                          style=T.tstyle(:primary))
        s2 = T.DataSeries([3.0, 1.0, 2.0]; label="s2",
                          style=T.tstyle(:accent))
        chart = T.Chart([s1, s2]; show_legend=true)
        buf = T.Buffer(T.Rect(1, 1, 40, 15))
        T.render(chart, T.Rect(1, 1, 40, 15), buf)
        # Legend should contain series labels
        found_legend = false
        for y in 1:15
            row = String([buf.content[T.buf_index(buf, x, y)].char for x in 1:40])
            if occursin("s1", row) || occursin("s2", row)
                found_legend = true
                break
            end
        end
        @test found_legend
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 5: DataTable
    # ═════════════════════════════════════════════════════════════════

    @testset "DataTable render" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob", "carol"]),
            T.DataColumn("Score", [95, 87, 92]; align=T.col_right),
        ]
        dt = T.DataTable(cols; selected=1)
        buf = T.Buffer(T.Rect(1, 1, 40, 8))
        T.render(dt, T.Rect(1, 1, 40, 8), buf)
        # Header should be rendered (starts at col 2 due to 1-char left margin)
        row1 = String([buf.content[i].char for i in 1:20])
        @test occursin("Name", row1)
        # Separator on row 2 (col 2 = first data column after left margin)
        @test buf.content[T.buf_index(buf, 2, 2)].char == '─'
    end

    @testset "DataTable convenience constructor" begin
        dt = T.DataTable(["A", "B"], [["x", "y"], [1, 2]])
        buf = T.Buffer(T.Rect(1, 1, 30, 6))
        T.render(dt, T.Rect(1, 1, 30, 6), buf)
        row1 = String([buf.content[i].char for i in 1:10])
        @test occursin("A", row1)
    end

    @testset "DataTable keyboard navigation" begin
        cols = [T.DataColumn("X", [1, 2, 3, 4, 5])]
        dt = T.DataTable(cols; selected=1)
        T.handle_key!(dt, T.KeyEvent(:down))
        @test dt.selected == 2
        T.handle_key!(dt, T.KeyEvent(:up))
        @test dt.selected == 1
        T.handle_key!(dt, T.KeyEvent(:end_key))
        @test dt.selected == 5
        T.handle_key!(dt, T.KeyEvent(:home))
        @test dt.selected == 1
    end

    @testset "DataTable sorting" begin
        cols = [
            T.DataColumn("Name", ["bob", "alice", "carol"]),
            T.DataColumn("Val", [2, 1, 3]),
        ]
        dt = T.DataTable(cols)
        T.sort_by!(dt, 2)
        @test dt.sort_dir == T.sort_asc
        @test dt.sort_perm == [2, 1, 3]  # alice=1, bob=2, carol=3
        T.sort_by!(dt, 2)
        @test dt.sort_dir == T.sort_desc
        @test dt.sort_perm == [3, 1, 2]
        T.sort_by!(dt, 2)
        @test dt.sort_dir == T.sort_none
    end

    @testset "DataTable empty" begin
        dt = T.DataTable(T.DataColumn[])
        buf = T.Buffer(T.Rect(1, 1, 30, 5))
        T.render(dt, T.Rect(1, 1, 30, 5), buf)
        @test true
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 5b: DataTable h-scroll, resize, detail view
    # ═════════════════════════════════════════════════════════════════

    @testset "DataTable horizontal scroll" begin
        # Create a table wide enough to need scrolling (8 columns)
        cols = [T.DataColumn("Col$i", ["val_$(i)_$r" for r in 1:5]) for i in 1:8]
        dt = T.DataTable(cols; selected=1)
        # Render in a narrow viewport (40 cols)
        buf = T.Buffer(T.Rect(1, 1, 40, 10))
        T.render(dt, T.Rect(1, 1, 40, 10), buf)

        # Initially col_offset is 0
        @test dt.col_offset == 0

        # Scroll right
        @test T.handle_key!(dt, T.KeyEvent(:right))
        @test dt.col_offset == 1

        # Scroll right more
        T.handle_key!(dt, T.KeyEvent(:right))
        @test dt.col_offset == 2

        # Scroll left
        T.handle_key!(dt, T.KeyEvent(:left))
        @test dt.col_offset == 1

        # Scroll left to beginning
        T.handle_key!(dt, T.KeyEvent(:left))
        @test dt.col_offset == 0

        # Can't scroll past 0
        @test !T.handle_key!(dt, T.KeyEvent(:left))
        @test dt.col_offset == 0
    end

    @testset "DataTable h-scroll renders correctly" begin
        cols = [T.DataColumn("Col$i", ["val_$(i)_$r" for r in 1:3]) for i in 1:8]
        dt = T.DataTable(cols; selected=1)

        # Render at col_offset=0, check Col1 is visible
        buf = T.Buffer(T.Rect(1, 1, 40, 8))
        T.render(dt, T.Rect(1, 1, 40, 8), buf)
        row1 = String([buf.content[T.buf_index(buf, x, 1)].char for x in 1:40])
        @test occursin("Col1", row1)

        # Scroll to col_offset=2, Col1 and Col2 should be gone
        dt.col_offset = 2
        buf = T.Buffer(T.Rect(1, 1, 40, 8))
        T.render(dt, T.Rect(1, 1, 40, 8), buf)
        row1 = String([buf.content[T.buf_index(buf, x, 1)].char for x in 1:40])
        @test occursin("Col3", row1)
        @test !occursin("Col1", row1)
    end

    @testset "DataTable col_widths override" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]; align=T.col_right),
        ]
        dt = T.DataTable(cols; selected=1)
        # Set explicit column widths
        dt.col_widths = [20, 10]
        buf = T.Buffer(T.Rect(1, 1, 40, 6))
        T.render(dt, T.Rect(1, 1, 40, 6), buf)
        # col_widths should be preserved after render
        @test dt.col_widths[1] == 20
        @test dt.col_widths[2] == 10
    end

    @testset "DataTable col_widths initialized on first render" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1)
        @test isempty(dt.col_widths)

        buf = T.Buffer(T.Rect(1, 1, 40, 6))
        T.render(dt, T.Rect(1, 1, 40, 6), buf)
        # After first render, col_widths vector should be sized (all 0 = auto)
        @test length(dt.col_widths) == 2
        @test all(w -> w == 0, dt.col_widths)  # 0 = auto, no user override yet
    end

    @testset "DataTable detail view open/close" begin
        detail_called = Ref(false)
        function test_detail(cols, row)
            detail_called[] = true
            [c.name => T._dt_format_cell(c, row) for c in cols]
        end

        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1, detail_fn=test_detail)

        # Open detail with 'd'
        @test T.handle_key!(dt, T.KeyEvent('d'))
        @test dt.show_detail
        @test dt.detail_row == 1

        # Keys are consumed while detail is open
        @test T.handle_key!(dt, T.KeyEvent(:down))  # consumed, scrolls detail
        @test dt.show_detail  # still open

        # Close with Escape
        @test T.handle_key!(dt, T.KeyEvent(:escape))
        @test !dt.show_detail

        # Open again and close with 'd'
        dt.selected = 2
        T.handle_key!(dt, T.KeyEvent('d'))
        @test dt.show_detail
        @test dt.detail_row == 2
        T.handle_key!(dt, T.KeyEvent('d'))
        @test !dt.show_detail
    end

    @testset "DataTable detail view renders" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1, detail_fn=T.datatable_detail)
        dt.show_detail = true
        dt.detail_row = 1

        buf = T.Buffer(T.Rect(1, 1, 50, 15))
        T.render(dt, T.Rect(1, 1, 50, 15), buf)

        # Look for "Record Detail" in the buffer
        found_detail = false
        for y in 1:15
            row = String([buf.content[T.buf_index(buf, x, y)].char for x in 1:50])
            if occursin("Record Detail", row)
                found_detail = true
                break
            end
        end
        @test found_detail
    end

    @testset "DataTable no detail when detail_fn is nothing" begin
        cols = [T.DataColumn("X", [1, 2, 3])]
        dt = T.DataTable(cols; selected=1)  # no detail_fn
        @test dt.detail_fn === nothing
        # 'd' key should not be handled as detail
        @test !T.handle_key!(dt, T.KeyEvent('d'))
        @test !dt.show_detail
    end

    @testset "DataTable detail view scroll" begin
        cols = [T.DataColumn("Col$i", ["val$i" for _ in 1:3]) for i in 1:10]
        dt = T.DataTable(cols; selected=1, detail_fn=T.datatable_detail)
        dt.show_detail = true
        dt.detail_row = 1
        dt.detail_scroll = 0

        # Scroll down in detail
        T.handle_key!(dt, T.KeyEvent(:down))
        @test dt.detail_scroll == 1
        T.handle_key!(dt, T.KeyEvent(:down))
        @test dt.detail_scroll == 2

        # Scroll up
        T.handle_key!(dt, T.KeyEvent(:up))
        @test dt.detail_scroll == 1
        T.handle_key!(dt, T.KeyEvent(:up))
        @test dt.detail_scroll == 0

        # Can't scroll past 0
        T.handle_key!(dt, T.KeyEvent(:up))
        @test dt.detail_scroll == 0
    end

    @testset "DataTable last_content_area cached" begin
        cols = [T.DataColumn("X", [1, 2, 3])]
        dt = T.DataTable(cols; selected=1)
        area = T.Rect(5, 5, 30, 10)
        buf = T.Buffer(area)
        T.render(dt, area, buf)
        # last_content_area should be updated
        @test dt.last_content_area.width > 0
    end

    @testset "DataTable border positions cached" begin
        cols = [
            T.DataColumn("A", ["x", "y"]),
            T.DataColumn("B", ["1", "2"]),
            T.DataColumn("C", ["a", "b"]),
        ]
        dt = T.DataTable(cols; selected=1)
        buf = T.Buffer(T.Rect(1, 1, 40, 8))
        T.render(dt, T.Rect(1, 1, 40, 8), buf)
        # With 3 columns, there should be 3 border positions (2 between + 1 trailing)
        @test length(dt.last_col_positions) == 3
        # Each entry is (x_position, column_index)
        @test dt.last_col_positions[1][2] == 1
        @test dt.last_col_positions[2][2] == 2
        @test dt.last_col_positions[3][2] == 3
    end

    @testset "DataTable mouse drag resize" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1)
        area = T.Rect(1, 1, 40, 8)
        buf = T.Buffer(area)
        T.render(dt, area, buf)

        # Simulate starting a drag on the first border
        @test length(dt.last_col_positions) >= 1
        border_x, col_idx = dt.last_col_positions[1]
        header_y = dt.last_content_area.y

        # Left press on border → starts drag
        press_evt = T.MouseEvent(border_x, header_y, T.mouse_left, T.mouse_press,
                                 false, false, false)
        @test T.handle_mouse!(dt, press_evt, area)
        @test dt.col_drag == col_idx

        # Drag to the right
        start_w = dt.col_drag_start_w
        drag_evt = T.MouseEvent(border_x + 5, header_y, T.mouse_left, T.mouse_drag,
                                false, false, false)
        @test T.handle_mouse!(dt, drag_evt, area)
        @test dt.col_widths[col_idx] == start_w + 5

        # Release
        release_evt = T.MouseEvent(border_x + 5, header_y, T.mouse_left, T.mouse_release,
                                   false, false, false)
        @test T.handle_mouse!(dt, release_evt, area)
        @test dt.col_drag == 0
    end

    @testset "DataTable mouse drag via convenience overload" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1)
        area = T.Rect(1, 1, 40, 8)
        buf = T.Buffer(area)
        T.render(dt, area, buf)

        # Convenience overload uses cached last_content_area
        border_x, col_idx = dt.last_col_positions[1]
        header_y = dt.last_content_area.y

        # Press, drag, release — all via 2-arg handle_mouse!
        press = T.MouseEvent(border_x, header_y, T.mouse_left, T.mouse_press,
                             false, false, false)
        @test T.handle_mouse!(dt, press)
        @test dt.col_drag == col_idx

        drag = T.MouseEvent(border_x + 3, header_y, T.mouse_left, T.mouse_drag,
                            false, false, false)
        @test T.handle_mouse!(dt, drag)

        release = T.MouseEvent(border_x + 3, header_y, T.mouse_left, T.mouse_release,
                               false, false, false)
        @test T.handle_mouse!(dt, release)
        @test dt.col_drag == 0
    end

    @testset "DataTable drag trailing border resizes last column" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]),
        ]
        dt = T.DataTable(cols; selected=1)
        area = T.Rect(1, 1, 40, 8)
        buf = T.Buffer(area)
        T.render(dt, area, buf)

        # Last border position is the trailing border for the last column
        @test length(dt.last_col_positions) >= 2
        border_x, col_idx = dt.last_col_positions[end]
        @test col_idx == 2  # last column
        header_y = dt.last_content_area.y
        rendered_w = dt.last_widths[2]

        # Drag trailing border to resize last column
        press = T.MouseEvent(border_x, header_y, T.mouse_left, T.mouse_press,
                             false, false, false)
        @test T.handle_mouse!(dt, press, area)
        @test dt.col_drag == 2

        drag = T.MouseEvent(border_x + 4, header_y, T.mouse_left, T.mouse_drag,
                            false, false, false)
        T.handle_mouse!(dt, drag, area)
        @test dt.col_widths[2] == rendered_w + 4

        release = T.MouseEvent(border_x + 4, header_y, T.mouse_left, T.mouse_release,
                               false, false, false)
        T.handle_mouse!(dt, release, area)
        @test dt.col_drag == 0
    end

    @testset "DataTable convenience handle_mouse! before render" begin
        cols = [T.DataColumn("X", [1, 2])]
        dt = T.DataTable(cols)
        # Before any render, last_content_area has width 0 → returns false
        evt = T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, false, false)
        @test !T.handle_mouse!(dt, evt)
    end

    @testset "DataTable datatable_detail helper" begin
        cols = [
            T.DataColumn("Name", ["alice", "bob"]),
            T.DataColumn("Score", [95, 87]; format=v -> "$(v) pts"),
        ]
        result = T.datatable_detail(cols, 1)
        @test result == ["Name" => "alice", "Score" => "95 pts"]
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 5: Tables.jl extension
    # ═════════════════════════════════════════════════════════════════

    @testset "Tables.jl extension" begin
        using Tables
        # Create a simple NamedTuple table
        tbl = (name=["alice", "bob"], score=[95, 87])
        dt = T.DataTable(tbl)
        @test length(dt.columns) == 2
        @test dt.columns[1].name == "name"
        @test dt.columns[2].name == "score"
        @test dt.columns[2].align == T.col_right  # Number → right aligned
        buf = T.Buffer(T.Rect(1, 1, 40, 6))
        T.render(dt, T.Rect(1, 1, 40, 6), buf)
        row1 = String([buf.content[i].char for i in 1:20])
        @test occursin("name", row1)
    end

    @testset "Tables.jl not loaded without using" begin
        # Verify core works without Tables
        dt = T.DataTable(["H"], [["v"]])
        @test length(dt.columns) == 1
    end

    # ═════════════════════════════════════════════════════════════════
    # Batch 6: Form
    # ═════════════════════════════════════════════════════════════════

    @testset "Form render" begin
        fields = [
            T.FormField("Name", T.TextInput(text="Alice")),
            T.FormField("Agree", T.Checkbox("Terms"; checked=true)),
        ]
        form = T.Form(fields)
        buf = T.Buffer(T.Rect(1, 1, 40, 10))
        T.render(form, T.Rect(1, 1, 40, 10), buf)
        # Labels should appear
        found_name = false
        for y in 1:10
            row = String([buf.content[T.buf_index(buf, x, y)].char for x in 1:20])
            if occursin("Name", row)
                found_name = true
                break
            end
        end
        @test found_name
    end

    @testset "Form tab navigation" begin
        ti = T.TextInput(text=""; focused=true)
        cb = T.Checkbox("x"; focused=false)
        fields = [
            T.FormField("F1", ti),
            T.FormField("F2", cb),
        ]
        form = T.Form(fields)
        # Tab moves focus
        T.handle_key!(form, T.KeyEvent(:tab))
        @test !ti.focused
        @test cb.focused
        T.handle_key!(form, T.KeyEvent(:tab))
        # Now on submit button
        @test !cb.focused
    end

    @testset "form valid()" begin
        ti = T.TextInput(text="")
        fields = [T.FormField("Name", ti; required=true)]
        form = T.Form(fields)
        @test !T.valid(form)
        T.set_text!(ti, "Alice")
        @test T.valid(form)
    end

    @testset "form value()" begin
        ti = T.TextInput(text="hello")
        cb = T.Checkbox("x"; checked=true)
        fields = [
            T.FormField("Name", ti),
            T.FormField("Agree", cb),
        ]
        form = T.Form(fields)
        vals = T.value(form)
        @test vals["Name"] == "hello"
        @test vals["Agree"] == true
    end

    @testset "form valid() with validator" begin
        v = s -> length(s) < 3 ? "Too short" : nothing
        ti = T.TextInput(text="ab"; validator=v)
        # Trigger validation
        T.handle_key!(ti, T.KeyEvent(:backspace))
        T.handle_key!(ti, T.KeyEvent('b'))
        fields = [T.FormField("X", ti)]
        form = T.Form(fields)
        @test !T.valid(form)
        T.handle_key!(ti, T.KeyEvent('c'))
        @test T.valid(form)
    end

