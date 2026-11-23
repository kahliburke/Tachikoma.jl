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
