@testset "PanelTree (tiling panes)" begin
    mutable struct _PTWidget
        id::Int
    end
    T.render(w::_PTWidget, r, buf) = nothing
    T.handle_key!(w::_PTWidget, e::T.KeyEvent) = true
    T.handle_mouse!(w::_PTWidget, e::T.MouseEvent) = true

    buf = T.Buffer(T.Rect(1, 1, 80, 30))
    pb(x, y, a) = T.MouseEvent(x, y, T.mouse_left, a, false, false, false)
    byid(pt, i) = first(filter(p -> p.content.id == i, T.panes(pt)))

    @testset "combined H+V splits" begin
        pt = T.PanelTree(_PTWidget(1); title="one")
        @test T.pane_count(pt) == 1
        T.split_pane!(pt, _PTWidget(2); horizontal=true)    # columns
        l3 = T.split_pane!(pt, _PTWidget(3); horizontal=false)  # rows under pane 2
        @test T.pane_count(pt) == 3
        @test T.focused_pane(pt) === l3
        @test pt.root isa T.PaneSplit && pt.root.horizontal
        @test pt.root.children[2] isa T.PaneSplit && !pt.root.children[2].horizontal
    end

    @testset "render populates rects" begin
        pt = T.PanelTree(_PTWidget(1))
        T.split_pane!(pt, _PTWidget(2); horizontal=true)
        T.render(pt, buf.area, buf)
        for p in T.panes(pt)
            @test p.rect.width > 0 && p.rect.height > 0
        end
    end

    @testset "drag-dock to a nested split" begin
        pt = T.PanelTree(_PTWidget(1))
        T.split_pane!(pt, _PTWidget(2); horizontal=true)
        T.split_pane!(pt, _PTWidget(3); horizontal=false)
        T.render(pt, buf.area, buf)
        l1 = byid(pt, 1)
        l3 = byid(pt, 3)
        hr = T._pt_handle_rect(l3)
        @test T.handle_mouse!(pt, pb(hr.x + 1, hr.y, T.mouse_press))
        @test pt.grab === l3
        T.handle_mouse!(pt, pb(l1.rect.x + 1, l1.rect.y + l1.rect.height ÷ 2, T.mouse_drag))
        @test pt.drop_zone == :left
        T.handle_mouse!(pt, pb(l1.rect.x + 1, l1.rect.y + l1.rect.height ÷ 2, T.mouse_release))
        @test pt.grab === nothing
        @test T.pane_count(pt) == 3
        p = T._pt_parent(pt.root, l1)
        @test p isa T.PaneSplit && p.horizontal && p.children[1] === l3 && p.children[2] === l1
    end

    @testset "stacked bottom-pane header grabs (not resize)" begin
        pt = T.PanelTree(_PTWidget(1))
        T.split_pane!(pt, _PTWidget(2); horizontal=false)   # vertical: 1 over 2
        T.render(pt, buf.area, buf)
        l2 = byid(pt, 2)
        T.handle_mouse!(pt, pb(l2.rect.x + 3, l2.rect.y, T.mouse_press))  # bottom pane header row
        @test pt.grab === l2
        @test pt.resizing === nothing
        T.cancel_move!(pt)
        # the divider row above it still resizes
        T.render(pt, buf.area, buf)
        T.handle_mouse!(pt, pb(l2.rect.x + 3, l2.rect.y - 1, T.mouse_press))
        @test pt.grab === nothing
        @test pt.resizing !== nothing
    end

    @testset "focus cycle + close" begin
        pt = T.PanelTree(_PTWidget(1))
        T.split_pane!(pt, _PTWidget(2); horizontal=true)
        T.split_pane!(pt, _PTWidget(3); horizontal=true)
        f0 = T.focused_pane(pt)
        T.focus_next!(pt)
        @test T.focused_pane(pt) !== f0
        @test T.close_pane!(pt)
        @test T.pane_count(pt) == 2
        # never closes the last pane
        T.close_pane!(pt)
        @test !T.close_pane!(pt)
        @test T.pane_count(pt) == 1
    end

    @testset "minimal chrome + Model content" begin
        mutable struct _PTModel <: T.Model
            q::Bool
        end
        T.view(m::_PTModel, f) = nothing
        T.update!(m::_PTModel, e::T.KeyEvent) = nothing
        T.update!(m::_PTModel, e::T.MouseEvent) = nothing
        T.should_quit(m::_PTModel) = m.q

        pt = T.PanelTree(_PTModel(false); title="model", chrome=:minimal)
        T.split_pane!(pt, _PTWidget(9); horizontal=true)
        T.render(pt, buf.area, buf)           # minimal chrome path (focus ring)
        @test T.handle_key!(pt, T.KeyEvent('a'))
        # a Model pane prunes when it should_quit
        m = T.focused_content(pt)
    end
end
