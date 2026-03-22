@testset "TabBar styles" begin

    @testset "BracketTabs rendering" begin
        tabs = TabBar(["Alpha", "Beta", "Gamma"]; active=2, focused=true,
                      tab_style=TabBarStyle(decoration=BracketTabs()))
        tb = T.TestBackend(40, 1)
        render(tabs, T.Rect(1, 1, 40, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("[Beta]", row)
        @test !occursin("[Alpha]", row)
        @test occursin("Alpha", row)
        @test occursin("Gamma", row)
    end

    @testset "PlainTabs rendering" begin
        tabs = TabBar(["Foo", "Bar", "Baz"]; active=1,
                      tab_style=TabBarStyle(decoration=PlainTabs()))
        tb = T.TestBackend(30, 1)
        render(tabs, T.Rect(1, 1, 30, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("Foo", row)
        @test occursin("Bar", row)
        @test !occursin("[", row)
        @test !occursin("]", row)
    end

    @testset "PlainTabs custom separator" begin
        tabs = TabBar(["A", "B", "C"]; active=2,
                      tab_style=TabBarStyle(decoration=PlainTabs(), separator=" · "))
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("·", row)
    end

    @testset "BoxTabs rendering" begin
        tabs = TabBar(["Tab1", "Tab2", "Tab3"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(40, 3)
        render(tabs, T.Rect(1, 1, 40, 3), tb.buf)
        row1 = T.row_text(tb, 1)
        row2 = T.row_text(tb, 2)
        row3 = T.row_text(tb, 3)
        @test occursin("┌", row1)
        @test occursin("─", row1)
        @test occursin("┐", row1)
        @test occursin("Tab1", row2)
        @test occursin("Tab2", row2)
        @test occursin("│", row2)
        @test occursin("─", row3)
    end

    @testset "BoxTabs active tab open bottom" begin
        tabs = TabBar(["A", "B"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(20, 3)
        render(tabs, T.Rect(1, 1, 20, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        a_pos = findfirst("A", row2)
        @test a_pos !== nothing
        if a_pos !== nothing
            c = T.char_at(tb, first(a_pos), 3)
            @test c == Char(' ')
        end
    end

    @testset "BoxTabs inactive tab closed bottom" begin
        tabs = TabBar(["A", "B"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(20, 3)
        render(tabs, T.Rect(1, 1, 20, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        b_pos = findfirst("B", row2)
        @test b_pos !== nothing
        if b_pos !== nothing
            c = T.char_at(tb, first(b_pos), 3)
            @test c == '─'
        end
    end

    @testset "BoxTabs heavy border" begin
        tabs = TabBar(["X", "Y"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs(box=BOX_HEAVY)))
        tb = T.TestBackend(20, 3)
        render(tabs, T.Rect(1, 1, 20, 3), tb.buf)
        row1 = T.row_text(tb, 1)
        @test occursin("┏", row1)
        @test occursin("━", row1)
        row2 = T.row_text(tb, 2)
        @test occursin("┃", row2)
    end

    @testset "BoxTabs double border" begin
        tabs = TabBar(["X", "Y"]; active=2,
                      tab_style=TabBarStyle(decoration=BoxTabs(box=BOX_DOUBLE)))
        tb = T.TestBackend(20, 3)
        render(tabs, T.Rect(1, 1, 20, 3), tb.buf)
        row1 = T.row_text(tb, 1)
        @test occursin("╔", row1)
        @test occursin("═", row1)
    end

    @testset "BoxTabs falls back when height < 3" begin
        tabs = TabBar(["A", "B"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("[A]", row)
    end

    @testset "Overflow BracketTabs" begin
        labels = ["Tab$i" for i in 1:20]
        tabs = TabBar(labels; active=10, tab_style=TabBarStyle())
        tb = T.TestBackend(30, 1)
        render(tabs, T.Rect(1, 1, 30, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("…", row)
        @test occursin("Tab10", row)
    end

    @testset "Overflow BoxTabs" begin
        labels = ["Tab$i" for i in 1:20]
        tabs = TabBar(labels; active=10,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(30, 3)
        render(tabs, T.Rect(1, 1, 30, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        @test occursin("…", row2)
        @test occursin("Tab10", row2)
    end

    @testset "Overflow PlainTabs" begin
        labels = ["Tab$i" for i in 1:20]
        tabs = TabBar(labels; active=10,
                      tab_style=TabBarStyle(decoration=PlainTabs()))
        tb = T.TestBackend(30, 1)
        render(tabs, T.Rect(1, 1, 30, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("…", row)
        @test occursin("Tab10", row)
    end

    @testset "handle_key! across styles" begin
        for dec in (BracketTabs(), BoxTabs(), PlainTabs())
            tabs = TabBar(["A", "B", "C"]; active=1, focused=true,
                          tab_style=TabBarStyle(decoration=dec))
            @test handle_key!(tabs, T.KeyEvent(:right, Char(0)))
            @test value(tabs) == 2
            @test handle_key!(tabs, T.KeyEvent(:left, Char(0)))
            @test value(tabs) == 1
            @test handle_key!(tabs, T.KeyEvent(:left, Char(0)))
            @test value(tabs) == 3
        end
    end

    @testset "handle_key! respects focused" begin
        tabs = TabBar(["A", "B"]; active=1, focused=false, tab_style=TabBarStyle())
        @test !handle_key!(tabs, T.KeyEvent(:right, Char(0)))
        @test value(tabs) == 1
    end

    @testset "set_value! clamps" begin
        tabs = TabBar(["A", "B", "C"]; tab_style=TabBarStyle())
        set_value!(tabs, 5)
        @test value(tabs) == 3
        set_value!(tabs, 0)
        @test value(tabs) == 1
        set_value!(tabs, 2)
        @test value(tabs) == 2
    end

    @testset "handle_mouse! BracketTabs" begin
        tabs = TabBar(["Foo", "Bar"]; active=1, tab_style=TabBarStyle())
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        row = T.row_text(tb, 1)
        bar_pos = findfirst("Bar", row)
        @test bar_pos !== nothing
        if bar_pos !== nothing
            result = handle_mouse!(tabs, T.MouseEvent(first(bar_pos), 1, T.mouse_left))
            @test result == :changed
            @test value(tabs) == 2
        end
    end

    @testset "handle_mouse! BoxTabs" begin
        tabs = TabBar(["AA", "BB"]; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(20, 3)
        render(tabs, T.Rect(1, 1, 20, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        bb_pos = findfirst("BB", row2)
        @test bb_pos !== nothing
        if bb_pos !== nothing
            result = handle_mouse!(tabs, T.MouseEvent(first(bb_pos), 2, T.mouse_left))
            @test result == :changed
            @test value(tabs) == 2
        end
    end

    @testset "handle_mouse! ignores non-left" begin
        tabs = TabBar(["A", "B"]; active=1, tab_style=TabBarStyle())
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        @test handle_mouse!(tabs, T.MouseEvent(5, 1, T.mouse_right)) == :none
        @test value(tabs) == 1
    end

    @testset "handle_mouse! active tab returns :none" begin
        tabs = TabBar(["A", "B"]; active=1, tab_style=TabBarStyle())
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        @test handle_mouse!(tabs, T.MouseEvent(2, 1, T.mouse_left)) == :none
    end

    @testset "tab_height" begin
        @test tab_height(BracketTabs()) == 1
        @test tab_height(PlainTabs()) == 1
        @test tab_height(BoxTabs()) == 3
    end

    @testset "empty labels" begin
        tabs = TabBar(String[]; tab_style=TabBarStyle())
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        @test value(tabs) == 1
    end

    @testset "single tab" begin
        tabs = TabBar(["Only"]; active=1, tab_style=TabBarStyle())
        tb = T.TestBackend(20, 1)
        render(tabs, T.Rect(1, 1, 20, 1), tb.buf)
        row = T.row_text(tb, 1)
        @test occursin("[Only]", row)
    end

    @testset "Span labels with BoxTabs" begin
        labels = Vector{T.TabLabel}([
            [Span("Tab", tstyle(:primary)), Span("1", tstyle(:accent))],
            [Span("Tab", tstyle(:primary)), Span("2", tstyle(:accent))],
        ])
        tabs = TabBar(labels; active=1,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(30, 3)
        render(tabs, T.Rect(1, 1, 30, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        @test occursin("Tab1", row2)
        @test occursin("Tab2", row2)
    end

    @testset "explicit TabBarStyle" begin
        tabs = TabBar(["A", "B"]; tab_style=TabBarStyle(inactive=tstyle(:text), active=tstyle(:primary)))
        @test value(tabs) == 1
        @test tabs.tab_style.active == tstyle(:primary)
        @test tabs.tab_style.inactive == tstyle(:text)
    end

    @testset "switch active and re-render BoxTabs" begin
        tabs = TabBar(["A", "B", "C"]; active=1, focused=true,
                      tab_style=TabBarStyle(decoration=BoxTabs()))
        tb = T.TestBackend(30, 3)

        # Render with tab 1 active
        render(tabs, T.Rect(1, 1, 30, 3), tb.buf)
        row2 = T.row_text(tb, 2)
        a_pos = findfirst("A", row2)

        # Switch to tab 2
        handle_key!(tabs, T.KeyEvent(:right, Char(0)))
        @test value(tabs) == 2

        # Re-render
        tb2 = T.TestBackend(30, 3)
        render(tabs, T.Rect(1, 1, 30, 3), tb2.buf)

        # Tab B should now have open bottom
        row2_new = T.row_text(tb2, 2)
        b_pos = findfirst("B", row2_new)
        @test b_pos !== nothing
        if b_pos !== nothing
            c = T.char_at(tb2, first(b_pos), 3)
            @test c == Char(' ')
        end
    end
end
