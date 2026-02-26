    # ═════════════════════════════════════════════════════════════════
    # Unified value() / set_value!() round-trips
    # ═════════════════════════════════════════════════════════════════

    @testset "value/set_value! round-trip: TextInput" begin
        ti = T.TextInput(text="hello")
        @test T.value(ti) == "hello"
        T.set_value!(ti, "world")
        @test T.value(ti) == "world"
    end

    @testset "value/set_value! round-trip: TextArea" begin
        ta = T.TextArea(text="line1\nline2")
        @test T.value(ta) == "line1\nline2"
        T.set_value!(ta, "new")
        @test T.value(ta) == "new"
    end

    @testset "value/set_value! round-trip: CodeEditor" begin
        ce = T.CodeEditor(text="x = 1")
        @test T.value(ce) == "x = 1"
        T.set_value!(ce, "y = 2")
        @test T.value(ce) == "y = 2"
    end

    @testset "value/set_value! round-trip: Checkbox" begin
        cb = T.Checkbox("test"; checked=false)
        @test T.value(cb) == false
        T.set_value!(cb, true)
        @test T.value(cb) == true
    end

    @testset "value/set_value! round-trip: RadioGroup" begin
        rg = T.RadioGroup(["A", "B", "C"]; selected=1)
        @test T.value(rg) == 1
        T.set_value!(rg, 3)
        @test T.value(rg) == 3
        # Clamping
        T.set_value!(rg, 99)
        @test T.value(rg) == 3
    end

    @testset "value/set_value! round-trip: DropDown" begin
        dd = T.DropDown(["X", "Y", "Z"]; selected=1)
        @test T.value(dd) == "X"
        T.set_value!(dd, 2)
        @test T.value(dd) == "Y"
    end

    @testset "value/set_value! round-trip: SelectableList" begin
        lst = T.SelectableList(["a", "b", "c"]; selected=1)
        @test T.value(lst) == 1
        T.set_value!(lst, 2)
        @test T.value(lst) == 2
        # Clamping
        T.set_value!(lst, 100)
        @test T.value(lst) == 3
    end

    @testset "value/set_value! round-trip: DataTable" begin
        cols = [T.DataColumn("N", [1, 2, 3])]
        dt = T.DataTable(cols; selected=1)
        @test T.value(dt) == 1
        T.set_value!(dt, 2)
        @test T.value(dt) == 2
    end

    @testset "value: TreeView" begin
        root = T.TreeNode("root"; children=[
            T.TreeNode("child1"),
            T.TreeNode("child2"),
        ])
        tv = T.TreeView(root; selected=2)
        @test T.value(tv) == 2
    end

    @testset "value: Form" begin
        ti = T.TextInput(text="alice")
        cb = T.Checkbox("ok"; checked=true)
        form = T.Form([T.FormField("Name", ti), T.FormField("OK", cb)])
        vals = T.value(form)
        @test vals["Name"] == "alice"
        @test vals["OK"] == true
    end

    @testset "valid: default true" begin
        @test T.valid(T.Checkbox("x")) == true
        @test T.valid(T.RadioGroup(["a"])) == true
    end

    @testset "valid: TextInput with validator" begin
        v = s -> length(s) < 2 ? "Too short" : nothing
        ti = T.TextInput(validator=v)
        T.handle_key!(ti, T.KeyEvent('a'))
        @test !T.valid(ti)
        T.handle_key!(ti, T.KeyEvent('b'))
        @test T.valid(ti)
    end

    # ═════════════════════════════════════════════════════════════════
    # Interactive SelectableList
    # ═════════════════════════════════════════════════════════════════

    @testset "SelectableList navigation" begin
        lst = T.SelectableList(["a", "b", "c", "d", "e"]; selected=1)
        @test T.handle_key!(lst, T.KeyEvent(:down)) == true
        @test lst.selected == 2
        @test T.handle_key!(lst, T.KeyEvent(:up)) == true
        @test lst.selected == 1
        # Wrap at top
        @test T.handle_key!(lst, T.KeyEvent(:up)) == true
        @test lst.selected == 5
        # Wrap at bottom
        @test T.handle_key!(lst, T.KeyEvent(:down)) == true
        @test lst.selected == 1
    end

    @testset "SelectableList home/end/pageup/pagedown" begin
        lst = T.SelectableList(string.(1:20); selected=10)
        T.handle_key!(lst, T.KeyEvent(:home))
        @test lst.selected == 1
        T.handle_key!(lst, T.KeyEvent(:end_key))
        @test lst.selected == 20
        T.handle_key!(lst, T.KeyEvent(:pageup))
        @test lst.selected == 10
        T.handle_key!(lst, T.KeyEvent(:pagedown))
        @test lst.selected == 20
    end

    @testset "SelectableList focusable" begin
        lst = T.SelectableList(["x"])
        @test T.focusable(lst) == true
    end

    # ═════════════════════════════════════════════════════════════════
    # Interactive TreeView
    # ═════════════════════════════════════════════════════════════════

    @testset "TreeView navigation" begin
        root = T.TreeNode("root"; children=[
            T.TreeNode("a"; children=[T.TreeNode("a1"), T.TreeNode("a2")]),
            T.TreeNode("b"),
        ])
        tv = T.TreeView(root; selected=1)
        @test T.focusable(tv) == true
        # Down moves to next
        T.handle_key!(tv, T.KeyEvent(:down))
        @test tv.selected == 2  # "a"
        # Right on expanded node moves to first child
        T.handle_key!(tv, T.KeyEvent(:right))
        @test tv.selected == 3  # "a1"
    end

    @testset "TreeView collapse/expand" begin
        root = T.TreeNode("root"; children=[
            T.TreeNode("a"; children=[T.TreeNode("a1")]),
        ])
        tv = T.TreeView(root; selected=2)  # "a"
        # Left collapses expanded node
        T.handle_key!(tv, T.KeyEvent(:left))
        @test root.children[1].expanded == false
        # Right expands collapsed node
        T.handle_key!(tv, T.KeyEvent(:right))
        @test root.children[1].expanded == true
        # Enter toggles
        T.handle_key!(tv, T.KeyEvent(:enter))
        @test root.children[1].expanded == false
    end

    @testset "TreeView wrap around" begin
        root = T.TreeNode("root"; children=[T.TreeNode("a")])
        tv = T.TreeView(root; selected=1)
        # Up from first wraps to last
        T.handle_key!(tv, T.KeyEvent(:up))
        @test tv.selected == 2
        # Down from last wraps to first
        T.handle_key!(tv, T.KeyEvent(:down))
        @test tv.selected == 1
    end

    # ═════════════════════════════════════════════════════════════════
    # Accessor functions for terminal Refs
    # ═════════════════════════════════════════════════════════════════

    @testset "Terminal accessor functions" begin
        @test T.cell_pixels() isa NamedTuple
        @test T.text_area_pixels() isa NamedTuple
        @test T.text_area_cells() isa NamedTuple
        @test T.sixel_scale() isa NamedTuple
        @test T.sixel_area_pixels() isa NamedTuple
    end

    # ═════════════════════════════════════════════════════════════════
    # .tach format roundtrip
    # ═════════════════════════════════════════════════════════════════

    @testset ".tach write/load roundtrip" begin
        w, h = 10, 5
        ncells = w * h

        # Build two frames with different cell content and styles
        cells1 = [T.Cell('A', T.Style(fg=T.Color256(196), bg=T.NoColor(),
                          bold=true, dim=false, italic=false, underline=false))
                  for _ in 1:ncells]
        cells2 = [T.Cell('Z', T.Style(fg=T.ColorRGB(0xff, 0x80, 0x00),
                          bg=T.Color256(16),
                          bold=false, dim=true, italic=true, underline=true))
                  for _ in 1:ncells]
        cell_snapshots = [cells1, cells2]
        timestamps = [0.0, 0.5]

        # Build pixel data: one frame with a 2x3 pixel region, one empty
        px = Matrix{T.ColorRGB}(undef, 2, 3)
        for r in 1:2, c in 1:3
            px[r, c] = T.ColorRGB(UInt8(r * 40), UInt8(c * 60), UInt8(100))
        end
        pixel_snapshots = [[(1, 2, px)], T.PixelSnapshot[]]

        tach_file = tempname() * ".tach"
        try
            T.write_tach(tach_file, w, h, cell_snapshots, timestamps, pixel_snapshots)

            # File should exist and have the TACH magic
            @test isfile(tach_file)
            open(tach_file) do f
                magic = read(f, 4)
                @test magic == UInt8['T', 'A', 'C', 'H']
            end

            # Load and verify roundtrip
            lw, lh, lsnaps, lts, lpixels = T.load_tach(tach_file)
            @test lw == w
            @test lh == h
            @test length(lsnaps) == 2
            @test length(lts) == 2
            @test lts[1] ≈ 0.0
            @test lts[2] ≈ 0.5

            # Verify cell data matches exactly
            for j in 1:ncells
                @test lsnaps[1][j].char == cells1[j].char
                @test lsnaps[1][j].style == cells1[j].style
                @test lsnaps[2][j].char == cells2[j].char
                @test lsnaps[2][j].style == cells2[j].style
            end

            # Verify pixel data
            @test length(lpixels[1]) == 1
            @test length(lpixels[2]) == 0
            row, col, lpx = lpixels[1][1]
            @test row == 1
            @test col == 2
            @test size(lpx) == (2, 3)
            for r in 1:2, c in 1:3
                @test lpx[r, c] == px[r, c]
            end
        finally
            rm(tach_file; force=true)
        end
    end

    @testset ".tach NoColor cells roundtrip" begin
        w, h = 4, 2
        ncells = w * h
        cells = [T.Cell(' ', T.Style()) for _ in 1:ncells]
        cell_snapshots = [cells]
        timestamps = [0.0]
        pixel_snapshots = [T.PixelSnapshot[]]

        tach_file = tempname() * ".tach"
        try
            T.write_tach(tach_file, w, h, cell_snapshots, timestamps, pixel_snapshots)
            lw, lh, lsnaps, lts, lpixels = T.load_tach(tach_file)
            @test lw == w
            @test lh == h
            for j in 1:ncells
                @test lsnaps[1][j] == cells[j]
            end
        finally
            rm(tach_file; force=true)
        end
    end

    @testset "CastRecorder no frames field" begin
        rec = T.CastRecorder()
        @test !rec.active
        @test isempty(rec.timestamps)
        @test isempty(rec.cell_snapshots)
        @test isempty(rec.pixel_snapshots)
        # Verify no 'frames' field exists
        @test !hasfield(T.CastRecorder, :frames)
    end

    @testset "start_recording! uses .tach extension" begin
        rec = T.CastRecorder()
        T.start_recording!(rec, 80, 24)
        @test endswith(rec.filename, ".tach")
        @test rec.active
        rec.active = false  # cleanup
    end

    # ═════════════════════════════════════════════════════════════════
    # Extension convenience loaders
    # ═════════════════════════════════════════════════════════════════

    @testset "Extension convenience loaders" begin
        @test T._pkg_available("ColorTypes", T._COLORTYPES_UUID)
        @test T._pkg_available("FreeTypeAbstraction", T._FREETYPEABSTRACTION_UUID)
        @test !T._pkg_available("FakePackage", Base.UUID("00000000-0000-0000-0000-000000000000"))
        # GIF extension starts unloaded (weakdeps); enable_gif() loads it
        @test T.enable_gif() === nothing
        @test T.gif_extension_loaded()
        @test T.enable_gif() === nothing   # idempotent no-op
        # Tables extension
        @test T.enable_tables() === nothing
        @test T.tables_extension_loaded()
        @test T.enable_tables() === nothing   # idempotent no-op
    end
