    @testset "PhyloTree generation deterministic" begin
        p = T.PHYLO_PRESETS[1]
        t1 = T._generate_phylo_tree(p)
        t2 = T._generate_phylo_tree(p)
        @test length(t1.branches) == length(t2.branches)
        @test t1.max_depth == t2.max_depth
        for i in eachindex(t1.branches)
            @test t1.branches[i].start_angle == t2.branches[i].start_angle
            @test t1.branches[i].end_radius == t2.branches[i].end_radius
        end
    end

    @testset "PhyloTree presets produce branches" begin
        for (i, p) in enumerate(T.PHYLO_PRESETS)
            tree = T._generate_phylo_tree(p)
            @test length(tree.branches) > 0
            @test tree.max_depth == p.max_depth
        end
    end

    @testset "PhyloTreeBackground renders to buffer" begin
        bg = T.PhyloTreeBackground(preset=1)
        buf = T.Buffer(T.Rect(1, 1, 40, 20))
        area = T.Rect(1, 1, 40, 20)

        T.render_background!(bg, buf, area, 10;
                             brightness=0.5, saturation=0.5, speed=1.0)

        non_empty = count(c -> c.char != ' ', buf.content)
        @test non_empty > 0
    end

    @testset "PhyloTreeBackground preset clamping" begin
        bg = T.PhyloTreeBackground(preset=999)
        buf = T.Buffer(T.Rect(1, 1, 20, 10))
        T.render_background!(bg, buf, T.Rect(1, 1, 20, 10), 5)
        @test true
    end

    @testset "PhyloTreeBackground keyword constructor" begin
        bg = T.PhyloTreeBackground(preset=3)
        @test bg.preset_idx == 3
        @test length(bg.tree.branches) > 0
    end

    @testset "PhyloTree render determinism" begin
        bg = T.PhyloTreeBackground(preset=2)
        buf1 = T.Buffer(T.Rect(1, 1, 30, 15))
        buf2 = T.Buffer(T.Rect(1, 1, 30, 15))
        area = T.Rect(1, 1, 30, 15)

        T.render_background!(bg, buf1, area, 42;
                             brightness=0.5, saturation=0.5, speed=1.0)
        T.render_background!(bg, buf2, area, 42;
                             brightness=0.5, saturation=0.5, speed=1.0)

        for i in eachindex(buf1.content)
            @test buf1.content[i].char == buf2.content[i].char
        end
    end

    @testset "PhyloTree small area no crash" begin
        bg = T.PhyloTreeBackground(preset=1)
        buf = T.Buffer(T.Rect(1, 1, 3, 1))
        T.render_background!(bg, buf, T.Rect(1, 1, 3, 1), 1)
        @test true
    end

    @testset "CladoTree generation deterministic" begin
        p = T.CLADO_PRESETS[1]
        t1 = T._generate_clado_tree(p)
        t2 = T._generate_clado_tree(p)
        @test length(t1.branches) == length(t2.branches)
        @test t1.max_depth == t2.max_depth
        @test length(t1.branches) > 0
        for i in eachindex(t1.branches)
            @test t1.branches[i].angle1 == t2.branches[i].angle1
            @test t1.branches[i].trait == t2.branches[i].trait
        end
    end

    @testset "CladoTree presets produce branches" begin
        for p in T.CLADO_PRESETS
            tree = T._generate_clado_tree(p)
            @test length(tree.branches) > 0
            @test tree.max_depth == p.max_depth
        end
    end

    @testset "CladogramBackground renders to buffer" begin
        bg = T.CladogramBackground(preset=1)
        buf = T.Buffer(T.Rect(1, 1, 40, 20))
        area = T.Rect(1, 1, 40, 20)
        T.render_background!(bg, buf, area, 10;
                             brightness=0.5, saturation=0.5, speed=1.0)
        non_empty = count(c -> c.char != ' ', buf.content)
        @test non_empty > 0
    end

    @testset "CladogramBackground preset clamping" begin
        bg = T.CladogramBackground(preset=999)
        buf = T.Buffer(T.Rect(1, 1, 20, 10))
        T.render_background!(bg, buf, T.Rect(1, 1, 20, 10), 5)
        @test true
    end

    @testset "CladogramBackground keyword constructor" begin
        bg = T.CladogramBackground(preset=3)
        @test bg.preset_idx == 3
        @test length(bg.tree.branches) > 0
    end

    @testset "CladoTree render determinism" begin
        bg = T.CladogramBackground(preset=2)
        buf1 = T.Buffer(T.Rect(1, 1, 30, 15))
        buf2 = T.Buffer(T.Rect(1, 1, 30, 15))
        area = T.Rect(1, 1, 30, 15)
        T.render_background!(bg, buf1, area, 42;
                             brightness=0.5, saturation=0.5, speed=1.0)
        T.render_background!(bg, buf2, area, 42;
                             brightness=0.5, saturation=0.5, speed=1.0)
        for i in eachindex(buf1.content)
            @test buf1.content[i].char == buf2.content[i].char
        end
    end

    @testset "CladoTree small area no crash" begin
        bg = T.CladogramBackground(preset=1)
        buf = T.Buffer(T.Rect(1, 1, 3, 1))
        T.render_background!(bg, buf, T.Rect(1, 1, 3, 1), 1)
        @test true
    end

