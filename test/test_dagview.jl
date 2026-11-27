using Tachikoma
using Test

const _T = Tachikoma

function _dag_pipeline()
    [
        DAGNode(:a, "checkout"; status=task_done, detail="fetched HEAD"),
        DAGNode(:b, "build"; deps=[:a], status=task_done, subtitle="2m"),
        DAGNode(:c, "lint"; deps=[:a], status=task_error),
        DAGNode(:d, "test"; deps=[:b], status=task_running, detail="412/980 passed"),
        DAGNode(:e, "deploy"; deps=[:d, :c]),
    ]
end

_dag_rows(tb, h) = join([row_text(tb, y) for y in 1:h], "\n")

function _dag_render(dv, w=120, h=24)
    tb = TestBackend(w, h)
    render_widget!(tb, dv)
    tb
end

# Screen cell on the label row of node `id`, from the last render.
function _dag_cell(dv, id)
    lay = dv._layout
    i = lay.index[id]
    (dv._origin[1] + lay.x[i] + 2, dv._origin[2] + lay.port[i])
end

_move(x, y) = MouseEvent(x, y, mouse_none, mouse_move, false, false, false)
_press(x, y) = MouseEvent(x, y, mouse_left, mouse_press, false, false, false)

@testset "DAGView" begin
    @testset "layering follows dependencies" begin
        dv = DAGView(_dag_pipeline())
        _dag_render(dv)
        lay = dv._layout
        L(id) = lay.layer[lay.index[id]]
        @test L(:a) == 1
        @test L(:b) == 2
        @test L(:d) == 3
        @test L(:e) == 4
        # lint has no other dependents, but isn't a source: it stays next to checkout
        @test L(:c) == 2
        @test all(lay.x[lay.index[:b]] > lay.x[lay.index[:a]] for _ in 1:1)
    end

    @testset "sources are pulled toward their first dependent" begin
        nodes = [DAGNode(:a, "a"), DAGNode(:b, "b"; deps=[:a]), DAGNode(:c, "c"; deps=[:b]),
                 DAGNode(:late, "late input"), DAGNode(:d, "d"; deps=[:c, :late])]
        dv = DAGView(nodes)
        _dag_render(dv)
        lay = dv._layout
        @test lay.layer[lay.index[:late]] == lay.layer[lay.index[:d]] - 1
    end

    @testset "invalid graphs" begin
        cyc = [DAGNode(:a, "a"; deps=[:b]), DAGNode(:b, "b"; deps=[:a])]
        @test_throws ArgumentError _dag_render(DAGView(cyc))
        @test_throws ArgumentError _dag_render(DAGView([DAGNode(:a, "a"; deps=[:zz])]))
        @test_throws ArgumentError _dag_render(DAGView([DAGNode(:a, "a"), DAGNode(:a, "b")]))
        @test_throws ArgumentError _dag_render(DAGView([DAGNode(:a, "a"; deps=[:a])]))
        @test_throws ArgumentError DAGView(DAGNode[]; h_gap=2)
    end

    @testset "renders nodes, connectors and status" begin
        dv = DAGView(_dag_pipeline(); tick=0)
        tb = _dag_render(dv)
        txt = _dag_rows(tb, 24)
        for label in ("checkout", "build", "lint", "test", "deploy", "2m")
            @test occursin(label, txt)
        end
        @test occursin('▶', txt)           # arrowheads
        @test occursin('✓', txt) && occursin('✗', txt)
        @test occursin('├', txt)           # source port / fan-out junction
    end

    @testset "empty graph" begin
        dv = DAGView(DAGNode[])
        tb = _dag_render(dv, 40, 10)
        @test strip(_dag_rows(tb, 10)) == ""
        @test handle_key!(dv, KeyEvent(:right)) == false
    end

    @testset "dashed links and icons" begin
        nodes = [DAGNode(:model, "model"; icon='✦'),
                 DAGNode(:src, "source"),
                 DAGNode(:a, "summarize"; deps=[:src], links=[:model], icon='∞')]
        dv = DAGView(nodes)
        txt = _dag_rows(_dag_render(dv), 24)
        @test occursin('╌', txt)                        # dashed run
        @test occursin('✦', txt) && occursin('∞', txt)
        @test dv._layout.dashed == [false, true]
    end

    @testset "hover shows a tooltip" begin
        dv = DAGView(_dag_pipeline())
        _dag_render(dv)
        x, y = _dag_cell(dv, :d)
        @test node_at(dv, x, y) == :d
        @test handle_mouse!(dv, _move(x, y))
        @test hovered_node(dv).id == :d
        txt = _dag_rows(_dag_render(dv), 24)
        @test occursin("412/980 passed", txt)
        @test occursin("running", txt)
        # Moving off the node clears hover
        handle_mouse!(dv, _move(1, 1))
        @test hovered_node(dv) === nothing
        @test !occursin("412/980 passed", _dag_rows(_dag_render(dv), 24))
    end

    @testset "click selects" begin
        dv = DAGView(_dag_pipeline())
        _dag_render(dv)
        x, y = _dag_cell(dv, :c)
        @test handle_mouse!(dv, _press(x, y))
        @test value(dv) == :c
        @test selected_node(dv).label == "lint"
    end

    @testset "keyboard follows edges" begin
        dv = DAGView(_dag_pipeline(); selected=:a)
        _dag_render(dv)
        @test handle_key!(dv, KeyEvent(:right))
        first_step = dv.selected
        @test first_step in (:b, :c)
        handle_key!(dv, KeyEvent(:left))
        @test dv.selected == :a
        set_value!(dv, :d)
        handle_key!(dv, KeyEvent(:right))
        @test dv.selected == :e
        # Back the way we came, even though lint is also upstream of deploy
        handle_key!(dv, KeyEvent(:left))
        @test dv.selected == :d
        handle_key!(dv, KeyEvent(:home))
        @test dv.selected == :a
        @test handle_key!(dv, KeyEvent(:tab)) == false
    end

    @testset "zoom changes level of detail" begin
        dv = DAGView(_dag_pipeline())
        _dag_render(dv)
        @test dv._layout.node_h == 4              # subtitle row present
        @test handle_key!(dv, KeyEvent('-'))
        _dag_render(dv)
        @test dv.zoom == 2 && dv._layout.node_h == 3
        zoom!(dv, -1)
        tb = _dag_render(dv)
        @test dv._layout.node_h == 1
        @test occursin("checkout", _dag_rows(tb, 24))
        @test zoom!(dv, -1) == false               # already at the minimum
        @test handle_key!(dv, KeyEvent('+'))
        @test dv.zoom == 2
        # Ctrl+wheel zooms
        _dag_render(dv)
        x, y = _dag_cell(dv, :b)
        handle_mouse!(dv, MouseEvent(x, y, mouse_scroll_up, mouse_press, false, false, true))
        @test dv.zoom == 3
    end

    @testset "overflow scrolls and pans" begin
        nodes = [DAGNode(Symbol("n$i"), "stage $i"; deps=i == 1 ? Symbol[] : [Symbol("n$(i-1)")])
                 for i in 1:8]
        dv = DAGView(nodes; selected=:n1)
        tb = _dag_render(dv, 60, 12)
        @test occursin('🬋', row_text(tb, 12))     # horizontal scrollbar
        @test dv.offset_x == 0
        # Selecting the last node scrolls it into view
        set_value!(dv, :n8)
        _dag_render(dv, 60, 12)
        @test dv.offset_x > 0
        x, y = _dag_cell(dv, :n8)
        @test 1 <= x <= 60
        # Drag on empty space pans
        ox = dv.offset_x
        handle_mouse!(dv, _press(2, 2))
        handle_mouse!(dv, MouseEvent(12, 2, mouse_left, mouse_drag, false, false, false))
        handle_mouse!(dv, MouseEvent(12, 2, mouse_left, mouse_release, false, false, false))
        @test dv.offset_x == ox - 10
        # Graph that fits is centered and has no scrollbars
        small = DAGView(nodes[1:2])
        tb = _dag_render(small, 100, 12)
        @test !occursin('🬋', _dag_rows(tb, 12))
        @test !occursin('█', _dag_rows(tb, 12))
    end

    @testset "status changes don't re-run layout" begin
        dv = DAGView(_dag_pipeline())
        _dag_render(dv)
        lay = dv._layout
        dv[:e].status = task_done
        _dag_render(dv)
        @test dv._layout === lay
        push!(dv[:e].deps, :b)
        _dag_render(dv)
        @test dv._layout !== lay
        @test haskey(dv, :e) && !haskey(dv, :zz)
        @test_throws KeyError dv[:zz]
    end

    @testset "dragged nodes extend the content extent" begin
        dv = DAGView(_dag_pipeline())
        tb = _dag_render(dv, 200, 40)
        lay = dv._layout
        # Baseline: nothing dragged → the extent is exactly the layout bbox.
        @test _T._dag_extent(dv, lay) == (0, 0, lay.width, lay.height)

        # Drag the right-most node (e) 30 cells right. The target stays inside
        # the (200×40) view, so the drag registers.
        x, y = _dag_cell(dv, :e)
        @test handle_mouse!(dv, _press(x, y))
        @test handle_mouse!(dv, MouseEvent(x + 30, y, mouse_left, mouse_drag, false, false, false))
        @test handle_mouse!(dv, MouseEvent(x + 30, y, mouse_left, mouse_release, false, false, false))
        # The extent grows past the layout bbox (the old invisible frame).
        minx, miny, ew, eh = _T._dag_extent(dv, lay)
        @test minx == 0 && miny == 0
        @test ew > lay.width
        # The node re-renders fully with proper box corners at its dragged spot.
        # It is selected (press selects), so its box is the HEAVY set (┏┓┗┛).
        tb = _dag_render(dv, 200, 40)
        i = lay.index[:e]
        off = dv.node_offsets[:e]
        sx = dv._origin[1] + lay.x[i] + off[1]
        sy = dv._origin[2] + lay.y[i] + off[2]
        @test char_at(tb, sx, sy) == '┏'
        @test char_at(tb, sx + lay.node_w - 1, sy) == '┓'
        @test char_at(tb, sx, sy + lay.node_h - 1) == '┗'
        @test char_at(tb, sx + lay.node_w - 1, sy + lay.node_h - 1) == '┛'
        @test node_at(dv, sx + 2, sy + 1) == :e

        # Drag node (a) 25 left and 3 up — its column is centered at lay.y[a]=2,
        # so it needs three rows of lift to push the extent miny below 0.
        x, y = _dag_cell(dv, :a)
        @test handle_mouse!(dv, _press(x, y))
        @test handle_mouse!(dv, MouseEvent(x - 25, y - 3, mouse_left, mouse_drag, false, false, false))
        @test handle_mouse!(dv, MouseEvent(x - 25, y - 3, mouse_left, mouse_release, false, false, false))
        minx, miny, ew, eh = _T._dag_extent(dv, lay)
        @test minx < 0 && miny < 0
        @test ew > lay.width
        tb = _dag_render(dv, 200, 40)
        i = lay.index[:a]
        off = dv.node_offsets[:a]
        # Screen pos of the node's box top-left: origin is the extent's top-left,
        # so add the (negative) minx/miny back to the raw content coords.
        sx = dv._origin[1] + lay.x[i] + off[1] - minx
        sy = dv._origin[2] + lay.y[i] + off[2] - miny
        @test sx == dv._origin[1] && sy == dv._origin[2]
        @test char_at(tb, sx, sy) == '┏'
        @test char_at(tb, sx, sy + lay.node_h - 1) == '┗'
        @test node_at(dv, sx + 2, sy + 1) == :a
        # The extent (not the static layout) drives the scrollbars: ew > 100
        # even though lay.width < 100, so a horizontal scrollbar must appear.
        tb = _dag_render(dv, 100, 40)
        @test dv._layout === lay                     # no relayout from drags
        @test occursin('🬋', row_text(tb, 40))
    end

    @testset "re-routed edges keep proper junction glyphs" begin
        # A dragged node re-routes its edges live (they bypass the precomputed
        # cells). Bends must still render as ╭╰╮╯ corners, crossings and T-joins
        # as ├┤┬┴┼ junctions — never as raw ─ / │ strokes.
        corners = Set("╭╰╮╯")
        function screen_cell(dv, tb, cx, cy)
            minx, miny, _, _ = _T._dag_extent(dv, dv._layout)
            char_at(tb, dv._origin[1] + cx - minx, dv._origin[2] + cy - miny)
        end
        function reroute(dv, lay, u, v)
            ou = get(dv.node_offsets, u, (0, 0)); ov = get(dv.node_offsets, v, (0, 0))
            iu, iv = lay.index[u], lay.index[v]
            sx = lay.x[iu] + lay.node_w + ou[1]; sy = lay.port[iu] + ou[2]
            ex = lay.x[iv] + ov[1] - 1;           ey = lay.port[iv] + ov[2]
            lhs = ex < sx
            if lhs
                sx = lay.x[iu] + ou[1] - 1
                ex = lay.x[iv] + lay.node_w + ov[1]
            end
            mx = (sx + ex) ÷ 2
            (sx, sy, ex, ey, mx, lhs)
        end

        # ── Bends: an isolated a → b edge re-routed by dragging a down turns
        # upward from the dragged port, bending at (mx, sy) and (mx, ey); both
        # bends must be true corners.
        nodes = [DAGNode(:a, "a"), DAGNode(:b, "b"; deps=[:a])]
        dv = DAGView(nodes)
        _dag_render(dv, 160, 40)
        lay = dv._layout
        dv.node_offsets[:a] = (0, 10)
        tb = _dag_render(dv, 160, 40)
        sx, sy, ex, ey, mx, lhs = reroute(dv, lay, :a, :b)
        @test sy > ey
        @test screen_cell(dv, tb, mx, sy) in corners
        @test screen_cell(dv, tb, mx, ey) in corners

        # ── Shared column: two children of one dragged node route through the
        # same mx, so their vertical runs merge into ONE vline. The source-side
        # bends are still corners, but the lower child's bend where its hline
        # T's into the shared vline becomes a ├-style junction — never a raw ─.
        nodes3 = [DAGNode(:a, "a"), DAGNode(:b, "b"; deps=[:a]), DAGNode(:c, "c"; deps=[:a])]
        dv3 = DAGView(nodes3)
        _dag_render(dv3, 160, 40)
        lay3 = dv3._layout
        dv3.node_offsets[:a] = (0, 10)
        tb3 = _dag_render(dv3, 160, 40)
        jx = Set("├┤┬┴┼")
        s1 = reroute(dv3, lay3, :a, :b)
        s2 = reroute(dv3, lay3, :a, :c)
        @test s1[5] == s2[5]                       # both edges share the column
        @test screen_cell(dv3, tb3, s1[5], s1[2]) in corners   # source bends
        @test screen_cell(dv3, tb3, s2[5], s2[2]) in corners
        tb_side = s1[4] < s2[4] ? (s1, s2) : (s2, s1)
        @test screen_cell(dv3, tb3, tb_side[1][5], tb_side[1][4]) in corners  # upper child
        g3 = screen_cell(dv3, tb3, tb_side[2][5], tb_side[2][4])              # lower child
        @test g3 in corners || g3 in jx            # corner or T-join, never ─ │

        # ── Crossing: x → y re-routes over the static p → q lane. The expected
        # glyph is the exact bit-union of both edges' cells; a cell shared by a
        # vertical and a horizontal run must merge into a ┼ (interior N|S +
        # E|W), never an overwrite by raw strokes. The drag magnitude is swept
        # so the check works for any layout rows.
        nodes2 = [DAGNode(:x, "x"), DAGNode(:y, "y"; deps=[:x]),
                  DAGNode(:p, "p"), DAGNode(:q, "q"; deps=[:p])]
        dv2 = DAGView(nodes2)
        _dag_render(dv2, 160, 40)
        lay2 = dv2._layout
        ei_pq = findfirst(((u, v),) -> u == lay2.index[:p] && v == lay2.index[:q], lay2.edges)
        @test ei_pq !== nothing
        static_cells = lay2.edge_cells[ei_pq]
        crossed = false
        saw_pipe = false
        junction_chars = Set("├┤┬┴┼")
        for dy in 2:24
            dv2.node_offsets[:x] = (0, dy)
            tb2 = _dag_render(dv2, 160, 40)
            sx, sy, ex, ey, mx, lhs = reroute(dv2, lay2, :x, :y)
            uc = _T._DagCells()
            _T._dag_add_hline!(uc, sy, sx, mx)
            _T._dag_add_vline!(uc, mx, sy, ey)
            _T._dag_add_hline!(uc, ey, mx, ex)
            _T._dag_or!(uc, sx, sy, lhs ? _T._DAG_E : _T._DAG_W)
            _T._dag_or!(uc, ex, ey, lhs ? _T._DAG_W : _T._DAG_E)
            # Re-routed vertical interior meeting the static horizontal lane:
            # the shared cell must merge into a junction (├┤┬┴┼), never a raw ─.
            hits = [p for p in keys(uc)
                    if (uc[p] & (_T._DAG_N | _T._DAG_S)) != 0x00 &&
                       (get(static_cells, p, 0x00) & (_T._DAG_E | _T._DAG_W)) != 0x00]
            isempty(hits) && continue
            crossed = true
            for p in hits
                bits = static_cells[p] | uc[p]
                @test count_ones(bits) >= 3
                @test screen_cell(dv2, tb2, p[1], p[2]) == _T._DAG_GLYPHS[Int(bits) + 1]
                @test screen_cell(dv2, tb2, p[1], p[2]) in junction_chars
                screen_cell(dv2, tb2, p[1], p[2]) == '┼' && (saw_pipe = true)
            end
            for p in keys(uc)                      # every re-routed cell matches
                p == (ex, ey) && continue          # the arrowhead overwrites its cell
                bits = get(static_cells, p, 0x00) | uc[p]
                @test screen_cell(dv2, tb2, p[1], p[2]) == _T._DAG_GLYPHS[Int(bits) + 1]
            end
            @test screen_cell(dv2, tb2, ex, ey) == '▶'
            saw_pipe && break
        end
        @test crossed
        @test saw_pipe
    end
end

@testset "Mouse motion tracking" begin
    @test occursin("\e[?1003h", _T.MOUSE_ON)
    @test occursin("\e[?1003l", _T.MOUSE_OFF)

    s = _T.TermScreen(24, 80)
    move = MouseEvent(5, 5, mouse_none, mouse_move, false, false, false)
    drag = MouseEvent(5, 5, mouse_left, mouse_drag, false, false, false)
    press = MouseEvent(5, 5, mouse_left, mouse_press, false, false, false)
    @test s.mouse_tracking == 0

    # A child that asks for button tracking gets drags but not bare motion
    s.mouse_tracking = 1002; s.mouse_reporting = true
    @test _T._mouse_wanted(s, press)
    @test _T._mouse_wanted(s, drag)
    @test !_T._mouse_wanted(s, move)
    s.mouse_tracking = 1000
    @test !_T._mouse_wanted(s, drag)
    s.mouse_tracking = 1003
    @test _T._mouse_wanted(s, move)
end
