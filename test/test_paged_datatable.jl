    # ═════════════════════════════════════════════════════════════════
    # PagedDataTable
    # ═════════════════════════════════════════════════════════════════

    # ── Test provider (uses InMemoryPagedProvider from core) ─────

    function make_test_provider(n::Int=100)
        cols = [
            T.PagedColumn("Name"),
            T.PagedColumn("Score"; align=T.col_right, format=v -> "$(v)pt", col_type=:numeric),
            T.PagedColumn("Status"),
        ]
        names   = ["item_$i" for i in 1:n]
        scores  = [i * 10 for i in 1:n]
        statuses = [i % 3 == 0 ? "active" : "idle" for i in 1:n]
        data = Vector{Any}[collect(Any, names), collect(Any, scores), collect(Any, statuses)]
        T.InMemoryPagedProvider(cols, data)
    end

    # ── Provider protocol ──────────────────────────────────────────

    @testset "PagedDataTable: provider protocol" begin
        p = make_test_provider(100)
        @test length(T.column_defs(p)) == 3
        @test T.supports_search(p) == true
        @test T.supports_filter(p) == true

        req = T.PageRequest(1, 10, 0, T.sort_none, Dict{Int,T.ColumnFilter}(), "")
        result = T.fetch_page(p, req)
        @test result.total_count == 100
        @test length(result.rows) == 10
        @test result.rows[1][1] == "item_1"
    end

    @testset "PagedDataTable: provider sorting" begin
        p = make_test_provider(20)
        req = T.PageRequest(1, 20, 2, T.sort_desc, Dict{Int,T.ColumnFilter}(), "")
        result = T.fetch_page(p, req)
        @test result.rows[1][2] == 200  # highest score first
        @test result.rows[end][2] == 10
    end

    @testset "PagedDataTable: provider search" begin
        p = make_test_provider(100)
        req = T.PageRequest(1, 100, 0, T.sort_none, Dict{Int,T.ColumnFilter}(), "item_1")
        result = T.fetch_page(p, req)
        @test result.total_count >= 1
        @test all(r -> occursin("item_1", string(r[1])), result.rows)
    end

    @testset "PagedDataTable: provider filter (contains)" begin
        p = make_test_provider(100)
        filters = Dict{Int,T.ColumnFilter}(3 => T.ColumnFilter(T.filter_contains, "active"))
        req = T.PageRequest(1, 100, 0, T.sort_none, filters, "")
        result = T.fetch_page(p, req)
        @test all(r -> r[3] == "active", result.rows)
    end

    @testset "PagedDataTable: provider filter (numeric gt)" begin
        p = make_test_provider(100)
        filters = Dict{Int,T.ColumnFilter}(2 => T.ColumnFilter(T.filter_gt, "500"))
        req = T.PageRequest(1, 100, 0, T.sort_none, filters, "")
        result = T.fetch_page(p, req)
        @test result.total_count > 0
        @test all(r -> r[2] > 500, result.rows)
    end

    @testset "PagedDataTable: provider filter (numeric lte)" begin
        p = make_test_provider(100)
        filters = Dict{Int,T.ColumnFilter}(2 => T.ColumnFilter(T.filter_lte, "100"))
        req = T.PageRequest(1, 100, 0, T.sort_none, filters, "")
        result = T.fetch_page(p, req)
        @test result.total_count > 0
        @test all(r -> r[2] <= 100, result.rows)
    end

    @testset "PagedDataTable: provider filter (text eq)" begin
        p = make_test_provider(100)
        filters = Dict{Int,T.ColumnFilter}(1 => T.ColumnFilter(T.filter_eq, "item_5"))
        req = T.PageRequest(1, 100, 0, T.sort_none, filters, "")
        result = T.fetch_page(p, req)
        @test result.total_count == 1
        @test result.rows[1][1] == "item_5"
    end

    @testset "PagedDataTable: provider filter (text neq)" begin
        p = make_test_provider(10)
        filters = Dict{Int,T.ColumnFilter}(3 => T.ColumnFilter(T.filter_neq, "active"))
        req = T.PageRequest(1, 100, 0, T.sort_none, filters, "")
        result = T.fetch_page(p, req)
        @test all(r -> r[3] != "active", result.rows)
    end

    # ── Filter capabilities ──────────────────────────────────────────

    @testset "PagedDataTable: filter capabilities" begin
        p = make_test_provider(10)
        caps = T.filter_capabilities(p)
        @test T.filter_contains in caps.text_ops
        @test T.filter_gt in caps.numeric_ops
        @test T.filter_lte in caps.numeric_ops
    end

    @testset "PagedDataTable: filter_op_label" begin
        @test T.filter_op_label(T.filter_contains) == "contains"
        @test T.filter_op_label(T.filter_eq) == "="
        @test T.filter_op_label(T.filter_gt) == ">"
        @test T.filter_op_label(T.filter_lte) == "≤"
        @test T.filter_op_label(T.filter_regex) == "regex"
    end

    # ── Widget construction ────────────────────────────────────────

    @testset "PagedDataTable: construction" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)
        @test pdt.page == 1
        @test pdt.page_size == 10
        @test pdt.total_count == 50
        @test length(pdt.rows) == 10
        @test pdt.selected == 1
        @test length(pdt.columns) == 3
    end

    @testset "PagedDataTable: value/set_value!" begin
        pdt = T.PagedDataTable(make_test_provider(20); page_size=10)
        @test T.value(pdt) == 1
        T.set_value!(pdt, 5)
        @test T.value(pdt) == 5
        T.set_value!(pdt, 100)
        @test T.value(pdt) == 10  # clamped to page size
    end

    @testset "PagedDataTable: focusable" begin
        pdt = T.PagedDataTable(make_test_provider(10))
        @test T.focusable(pdt) == true
    end

    # ── Rendering ──────────────────────────────────────────────────

    @testset "PagedDataTable: basic render" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        T.render(pdt, T.Rect(1, 1, 60, 20), buf)
        # Should render without error and cache content area
        @test pdt.last_content_area.width > 0
    end

    @testset "PagedDataTable: render with block" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10,
                                block=T.Block(title="Test"))
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        T.render(pdt, T.Rect(1, 1, 60, 20), buf)
        @test pdt.last_content_area.width > 0
    end

    @testset "PagedDataTable: render footer shows page info" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=25)
        buf = T.Buffer(T.Rect(1, 1, 80, 20))
        T.render(pdt, T.Rect(1, 1, 80, 20), buf)
        @test pdt.last_prev_rect.width > 0
        @test pdt.last_next_rect.width > 0
        @test !isempty(pdt.last_page_size_rects)
    end

    # ── Keyboard navigation ────────────────────────────────────────

    @testset "PagedDataTable: row navigation" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)
        @test pdt.selected == 1

        T.handle_key!(pdt, T.KeyEvent(:down, '\0'))
        @test pdt.selected == 2

        T.handle_key!(pdt, T.KeyEvent(:up, '\0'))
        @test pdt.selected == 1

        # At top → stays at 1 (no wrap, no page change)
        T.handle_key!(pdt, T.KeyEvent(:up, '\0'))
        @test pdt.selected == 1
        @test pdt.page == 1

        # Navigate to bottom of page
        for _ in 1:9
            T.handle_key!(pdt, T.KeyEvent(:down, '\0'))
        end
        @test pdt.selected == 10

        # At bottom → stays at 10 (no wrap, no page change)
        T.handle_key!(pdt, T.KeyEvent(:down, '\0'))
        @test pdt.page == 1
        @test pdt.selected == 10
    end

    @testset "PagedDataTable: page navigation" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=10)
        @test pdt.page == 1

        T.handle_key!(pdt, T.KeyEvent(:pagedown, '\0'))
        @test pdt.page == 2

        T.handle_key!(pdt, T.KeyEvent(:pageup, '\0'))
        @test pdt.page == 1

        # Home/End
        T.handle_key!(pdt, T.KeyEvent(:end_key, '\0'))
        @test pdt.page == 10

        T.handle_key!(pdt, T.KeyEvent(:home, '\0'))
        @test pdt.page == 1
    end

    @testset "PagedDataTable: page bounds" begin
        pdt = T.PagedDataTable(make_test_provider(25); page_size=10)
        # Page 1 → pageup should stay at 1
        T.handle_key!(pdt, T.KeyEvent(:pageup, '\0'))
        @test pdt.page == 1

        # Go to last page → pagedown should stay
        T.handle_key!(pdt, T.KeyEvent(:end_key, '\0'))
        @test pdt.page == 3
        T.handle_key!(pdt, T.KeyEvent(:pagedown, '\0'))
        @test pdt.page == 3
    end

    # ── Sorting ────────────────────────────────────────────────────

    @testset "PagedDataTable: sort by column" begin
        pdt = T.PagedDataTable(make_test_provider(20); page_size=20)

        # Sort by score (col 2) ascending
        T.handle_key!(pdt, T.KeyEvent(:char, '2'))
        @test pdt.sort_col == 2
        @test pdt.sort_dir == T.sort_asc
        @test pdt.rows[1][2] == 10  # lowest score

        # Sort descending
        T.handle_key!(pdt, T.KeyEvent(:char, '2'))
        @test pdt.sort_dir == T.sort_desc
        @test pdt.rows[1][2] == 200  # highest score

        # Back to none
        T.handle_key!(pdt, T.KeyEvent(:char, '2'))
        @test pdt.sort_dir == T.sort_none
    end

    # ── Search ─────────────────────────────────────────────────────

    @testset "PagedDataTable: search toggle" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)

        # Toggle search on
        T.handle_key!(pdt, T.KeyEvent(:char, '/'))
        @test pdt.search_visible == true

        # Escape closes
        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
        @test pdt.search_visible == false
    end

    @testset "PagedDataTable: search apply" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=100)

        T.handle_key!(pdt, T.KeyEvent(:char, '/'))
        # Type "item_1" into search input
        for c in "item_1"
            T.handle_key!(pdt, T.KeyEvent(:char, c))
        end
        T.handle_key!(pdt, T.KeyEvent(:enter, '\0'))

        @test pdt.search_query == "item_1"
        @test pdt.search_visible == false
        @test pdt.total_count >= 1
        @test pdt.total_count < 100  # filtered down
    end

    # ── Filter modal ───────────────────────────────────────────────

    @testset "PagedDataTable: filter modal toggle" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)

        T.handle_key!(pdt, T.KeyEvent(:char, 'f'))
        @test pdt.filter_modal.visible == true

        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
        @test pdt.filter_modal.visible == false
    end

    @testset "PagedDataTable: filter modal apply contains" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=100)

        # Open filter modal
        T.handle_key!(pdt, T.KeyEvent(:char, 'f'))
        @test pdt.filter_modal.visible == true
        @test pdt.filter_modal.col_cursor == 1  # first filterable col

        # Move to value input (Tab → operator, Tab → value)
        T.handle_key!(pdt, T.KeyEvent(:tab, '\0'))
        T.handle_key!(pdt, T.KeyEvent(:tab, '\0'))
        @test pdt.filter_modal.section == 3

        # Type filter value
        for c in "item_5"
            T.handle_key!(pdt, T.KeyEvent(:char, c))
        end
        T.handle_key!(pdt, T.KeyEvent(:enter, '\0'))

        @test pdt.filter_modal.visible == false
        @test haskey(pdt.filters, 1)
        @test pdt.filters[1].op == T.filter_contains
        @test pdt.filters[1].value == "item_5"
        @test pdt.total_count < 100
    end

    @testset "PagedDataTable: filter modal clear with x" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=100)

        # Set a filter first
        pdt.filters[1] = T.ColumnFilter(T.filter_contains, "item_5")
        T.pdt_fetch!(pdt)
        count_filtered = pdt.total_count

        # Open filter and clear
        T.handle_key!(pdt, T.KeyEvent(:char, 'f'))
        @test pdt.filter_modal.col_cursor == 1
        T.handle_key!(pdt, T.KeyEvent(:char, 'x'))
        @test !haskey(pdt.filters, 1)
    end

    @testset "PagedDataTable: filter modal section navigation" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)

        T.handle_key!(pdt, T.KeyEvent(:char, 'f'))
        @test pdt.filter_modal.section == 1

        T.handle_key!(pdt, T.KeyEvent(:tab, '\0'))
        @test pdt.filter_modal.section == 2

        T.handle_key!(pdt, T.KeyEvent(:tab, '\0'))
        @test pdt.filter_modal.section == 3

        T.handle_key!(pdt, T.KeyEvent(:tab, '\0'))
        @test pdt.filter_modal.section == 1  # wraps

        T.handle_key!(pdt, T.KeyEvent(:backtab, '\0'))
        @test pdt.filter_modal.section == 3  # wraps back

        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
    end

    @testset "PagedDataTable: filter modal render" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)
        pdt.filter_modal.visible = true
        pdt.filter_modal.col_cursor = 1
        pdt.filter_modal.available_ops = [T.filter_contains, T.filter_eq, T.filter_neq]

        buf = T.Buffer(T.Rect(1, 1, 60, 25))
        T.render(pdt, T.Rect(1, 1, 60, 25), buf)
        # Should render without error
        @test pdt.last_content_area.width > 0
    end

    # ── Page size ──────────────────────────────────────────────────

    @testset "PagedDataTable: page size change" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=50,
                                page_sizes=[25, 50, 100])

        # Page size is changed programmatically (e.g. from settings modal)
        T.pdt_set_page_size!(pdt, 25)
        @test pdt.page_size == 25

        T.pdt_set_page_size!(pdt, 100)
        @test pdt.page_size == 100
    end

    # ── Provider switching ──────────────────────────────────────

    @testset "PagedDataTable: pdt_set_provider!" begin
        p1 = make_test_provider(100)
        pdt = T.PagedDataTable(p1; page_size=10)
        @test pdt.total_count == 100

        # Set a filter and sort to verify reset
        pdt.filters[1] = T.ColumnFilter(T.filter_contains, "test")
        pdt.sort_col = 2
        pdt.sort_dir = T.sort_asc

        # Switch to a different provider
        p2 = make_test_provider(50)
        T.pdt_set_provider!(pdt, p2)
        @test pdt.provider === p2
        @test pdt.total_count == 50
        @test pdt.page == 1
        @test isempty(pdt.filters)
        @test pdt.search_query == ""
        @test pdt.sort_col == 0
        @test pdt.sort_dir == T.sort_none
    end

    # ── Go to page ────────────────────────────────────────────────

    @testset "PagedDataTable: goto page" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=10)
        @test pdt.page == 1

        # Open goto input
        T.handle_key!(pdt, T.KeyEvent(:char, 'g'))
        @test pdt.goto_visible

        # Type "5" and press Enter
        T.handle_key!(pdt, T.KeyEvent(:char, '5'))
        T.handle_key!(pdt, T.KeyEvent(:enter, '\0'))
        @test !pdt.goto_visible
        @test pdt.page == 5

        # Goto with value clamped to max page
        T.handle_key!(pdt, T.KeyEvent(:char, 'g'))
        T.handle_key!(pdt, T.KeyEvent(:char, '9'))
        T.handle_key!(pdt, T.KeyEvent(:char, '9'))
        T.handle_key!(pdt, T.KeyEvent(:enter, '\0'))
        @test pdt.page == 10  # max page for 100 rows / 10 per page

        # Escape cancels without changing page
        T.handle_key!(pdt, T.KeyEvent(:char, 'g'))
        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
        @test !pdt.goto_visible
        @test pdt.page == 10  # unchanged
    end

    # ── Detail view ────────────────────────────────────────────────

    @testset "PagedDataTable: detail view" begin
        detail_called = Ref(false)
        function test_detail(cols, row_data)
            detail_called[] = true
            [c.name => string(row_data[i]) for (i, c) in enumerate(cols)]
        end

        pdt = T.PagedDataTable(make_test_provider(20); page_size=10,
                                detail_fn=test_detail)

        # Open detail
        T.handle_key!(pdt, T.KeyEvent(:char, 'd'))
        @test pdt.show_detail == true
        @test pdt.detail_row == 1

        # Scroll in detail
        T.handle_key!(pdt, T.KeyEvent(:down, '\0'))
        @test pdt.detail_scroll == 1

        T.handle_key!(pdt, T.KeyEvent(:up, '\0'))
        @test pdt.detail_scroll == 0

        # Close detail
        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
        @test pdt.show_detail == false

        # Render with detail open (test modal rendering)
        pdt.show_detail = true
        pdt.detail_row = 1
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        T.render(pdt, T.Rect(1, 1, 60, 20), buf)
        @test detail_called[]
    end

    @testset "PagedDataTable: default detail_fn" begin
        pdt = T.PagedDataTable(make_test_provider(10); page_size=10)
        T.handle_key!(pdt, T.KeyEvent(:char, 'd'))
        @test pdt.show_detail == true  # uses built-in default detail

        # Render detail overlay to verify it works
        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        T.render(pdt, T.Rect(1, 1, 60, 20), buf)
        @test pdt.last_content_area.width > 0

        T.handle_key!(pdt, T.KeyEvent(:escape, '\0'))
        @test pdt.show_detail == false
    end

    # ── Mouse ──────────────────────────────────────────────────────

    @testset "PagedDataTable: mouse before render returns false" begin
        pdt = T.PagedDataTable(make_test_provider(10); page_size=10)
        evt = T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, false, false)
        @test T.handle_mouse!(pdt, evt) == false
    end

    @testset "PagedDataTable: mouse footer prev/next" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=10)
        buf = T.Buffer(T.Rect(1, 1, 80, 20))
        T.render(pdt, T.Rect(1, 1, 80, 20), buf)

        # Click next button
        r = pdt.last_next_rect
        if r.width > 0
            evt = T.MouseEvent(r.x, r.y, T.mouse_left, T.mouse_press, false, false, false)
            T.handle_mouse!(pdt, evt)
            @test pdt.page == 2

            # Click prev button
            r2 = pdt.last_prev_rect
            evt2 = T.MouseEvent(r2.x, r2.y, T.mouse_left, T.mouse_press, false, false, false)
            T.handle_mouse!(pdt, evt2)
            @test pdt.page == 1
        end
    end

    @testset "PagedDataTable: mouse page size click" begin
        pdt = T.PagedDataTable(make_test_provider(100); page_size=50,
                                page_sizes=[25, 50, 100])
        buf = T.Buffer(T.Rect(1, 1, 80, 20))
        T.render(pdt, T.Rect(1, 1, 80, 20), buf)

        # Find the "25" page size rect
        for (rect, ps) in pdt.last_page_size_rects
            if ps == 25
                evt = T.MouseEvent(rect.x, rect.y, T.mouse_left, T.mouse_press, false, false, false)
                T.handle_mouse!(pdt, evt)
                @test pdt.page_size == 25
                break
            end
        end
    end

    # ── Column resize ──────────────────────────────────────────────

    @testset "PagedDataTable: column border positions cached" begin
        pdt = T.PagedDataTable(make_test_provider(10); page_size=10)
        buf = T.Buffer(T.Rect(1, 1, 60, 15))
        T.render(pdt, T.Rect(1, 1, 60, 15), buf)
        @test !isempty(pdt.last_col_positions)
    end

    # ── Horizontal scroll ──────────────────────────────────────────

    @testset "PagedDataTable: horizontal scroll" begin
        # Create provider with many columns
        cols = [T.PagedColumn("Col$i") for i in 1:10]
        data = [collect(Any, ["v$(i)_$r" for r in 1:5]) for i in 1:10]
        p = T.InMemoryPagedProvider(cols, data)

        pdt = T.PagedDataTable(p; page_size=5)
        # Render to set up cached areas
        buf = T.Buffer(T.Rect(1, 1, 40, 10))
        T.render(pdt, T.Rect(1, 1, 40, 10), buf)

        @test pdt.col_offset == 0
        T.handle_key!(pdt, T.KeyEvent(:right, '\0'))
        @test pdt.col_offset >= 0  # may or may not scroll depending on width
    end

    # ── Empty provider ─────────────────────────────────────────────

    @testset "PagedDataTable: empty provider" begin
        cols = [T.PagedColumn("A"), T.PagedColumn("B")]
        data = [Any[], Any[]]
        p = T.InMemoryPagedProvider(cols, data)
        pdt = T.PagedDataTable(p; page_size=10)

        @test pdt.total_count == 0
        @test pdt.selected == 0

        buf = T.Buffer(T.Rect(1, 1, 40, 10))
        T.render(pdt, T.Rect(1, 1, 40, 10), buf)
        # Should not crash
    end

    # ── Search render ──────────────────────────────────────────────

    @testset "PagedDataTable: search bar render" begin
        pdt = T.PagedDataTable(make_test_provider(50); page_size=10)
        pdt.search_visible = true

        buf = T.Buffer(T.Rect(1, 1, 60, 20))
        T.render(pdt, T.Rect(1, 1, 60, 20), buf)
        # Should render without error with search bar visible
        @test pdt.last_content_area.width > 0
    end

    # ── Default supports_* ─────────────────────────────────────────

    @testset "PagedDataTable: default supports returns false" begin
        struct BareProvider <: T.PagedDataProvider end
        @test T.supports_search(BareProvider()) == false
        @test T.supports_filter(BareProvider()) == false
    end

    # ── apply_filter unit tests ──────────────────────────────────

    @testset "PagedDataTable: apply_filter numeric" begin
        @test T.apply_filter(T.filter_gt, "50", 100, :numeric) == true
        @test T.apply_filter(T.filter_gt, "50", 30, :numeric) == false
        @test T.apply_filter(T.filter_gte, "50", 50, :numeric) == true
        @test T.apply_filter(T.filter_lt, "50", 30, :numeric) == true
        @test T.apply_filter(T.filter_lt, "50", 80, :numeric) == false
        @test T.apply_filter(T.filter_lte, "50", 50, :numeric) == true
        @test T.apply_filter(T.filter_eq, "50", 50, :numeric) == true
        @test T.apply_filter(T.filter_eq, "50", 51, :numeric) == false
        @test T.apply_filter(T.filter_neq, "50", 51, :numeric) == true
        # Invalid numeric filter value → don't exclude
        @test T.apply_filter(T.filter_gt, "abc", 100, :numeric) == true
        # Non-numeric cell value → exclude
        @test T.apply_filter(T.filter_gt, "50", "hello", :numeric) == false
    end

    @testset "PagedDataTable: apply_filter text" begin
        @test T.apply_filter(T.filter_contains, "hello", "Hello World", :text) == true
        @test T.apply_filter(T.filter_contains, "xyz", "Hello World", :text) == false
        @test T.apply_filter(T.filter_eq, "hello", "Hello", :text) == true
        @test T.apply_filter(T.filter_eq, "hello", "Hello World", :text) == false
        @test T.apply_filter(T.filter_neq, "hello", "world", :text) == true
        @test T.apply_filter(T.filter_neq, "hello", "Hello", :text) == false
    end

    # ── col_type on PagedColumn ──────────────────────────────────

    @testset "PagedDataTable: PagedColumn col_type" begin
        col_text = T.PagedColumn("Name")
        @test col_text.col_type == :text

        col_num = T.PagedColumn("Score"; col_type=:numeric)
        @test col_num.col_type == :numeric
    end
