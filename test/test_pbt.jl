    # ═════════════════════════════════════════════════════════════════
    # Property-based tests (Supposition.jl)
    # ═════════════════════════════════════════════════════════════════

    # -- Generators --------------------------------------------------

    ratio_gen = @composed function _ratio(n=Data.Integers(0, 100), d=Data.Integers(1, 100))
        T.Ratio(n, d)
    end

    constraint_gen = Data.OneOf(
        map(T.Fixed,   Data.Integers(0, 5000)),
        map(T.Fill,    Data.Integers(1, 100)),
        map(T.Percent, Data.Integers(1, 100)),
        map(T.Min,     Data.Integers(0, 5000)),
        map(T.Max,     Data.Integers(0, 5000)),
        ratio_gen,
    )

    rgb_gen = @composed function _rgb(
            r=Data.Integers{UInt8}(),
            g=Data.Integers{UInt8}(),
            b=Data.Integers{UInt8}())
        T.ColorRGB(r, g, b)
    end

    unit_float = map(x -> x / 1000.0, Data.Integers(0, 1000))

    @testset "PBT: constraint serialization roundtrip" begin
        Supposition.@check function constraint_rt(c=constraint_gen)
            s = T._serialize_constraint(c)
            c2 = T._deserialize_constraint(s)
            typeof(c2) == typeof(c) || return false
            if c isa T.Fixed;   return c2.size == c.size; end
            if c isa T.Fill;    return c2.weight == c.weight; end
            if c isa T.Percent; return c2.pct == c.pct; end
            if c isa T.Min;     return c2.size == c.size; end
            if c isa T.Max;     return c2.size == c.size; end
            if c isa T.Ratio;   return c2.num == c.num && c2.den == c.den; end
            false
        end
    end

    @testset "PBT: constraints vector roundtrip" begin
        cs_gen = Data.Vectors(constraint_gen; min_size=1, max_size=8)
        Supposition.@check function constraints_rt(cs=cs_gen)
            typed = T.Constraint[c for c in cs]
            s = T._serialize_constraints(typed)
            cs2 = T._deserialize_constraints(s)
            length(cs2) == length(cs) || return false
            all(typeof(a) == typeof(b) for (a, b) in zip(cs, cs2))
        end
    end

    @testset "PBT: layout fingerprint determinism" begin
        dir_gen = Data.SampledFrom([T.Horizontal, T.Vertical])
        cs_gen = Data.Vectors(constraint_gen; min_size=1, max_size=6)
        Supposition.@check function fp_deterministic(dir=dir_gen, cs=cs_gen)
            rl = T.ResizableLayout(dir, T.Constraint[c for c in cs])
            T._layout_fingerprint(rl) == T._layout_fingerprint(rl)
        end
    end

    @testset "PBT: color_lerp endpoints" begin
        Supposition.@check function lerp_at_zero(a=rgb_gen, b=rgb_gen)
            c = T.color_lerp(a, b, 0.0)
            c == a
        end
        Supposition.@check function lerp_at_one(a=rgb_gen, b=rgb_gen)
            c = T.color_lerp(a, b, 1.0)
            c == b
        end
    end

    @testset "PBT: color_lerp stays in range" begin
        Supposition.@check function lerp_in_range(a=rgb_gen, b=rgb_gen, t=unit_float)
            c = T.color_lerp(a, b, t)
            0x00 <= c.r <= 0xff && 0x00 <= c.g <= 0xff && 0x00 <= c.b <= 0xff
        end
    end

    @testset "PBT: brighten/dim_color stay in range" begin
        Supposition.@check function brighten_range(c=rgb_gen, t=unit_float)
            b = T.brighten(c, t)
            0x00 <= b.r <= 0xff && 0x00 <= b.g <= 0xff && 0x00 <= b.b <= 0xff
        end
        Supposition.@check function dim_range(c=rgb_gen, t=unit_float)
            d = T.dim_color(c, t)
            0x00 <= d.r <= 0xff && 0x00 <= d.g <= 0xff && 0x00 <= d.b <= 0xff
        end
    end

    @testset "PBT: brighten/dim at zero is identity" begin
        Supposition.@check function brighten_zero(c=rgb_gen)
            T.brighten(c, 0.0) == c
        end
        Supposition.@check function dim_zero(c=rgb_gen)
            T.dim_color(c, 0.0) == c
        end
    end

    @testset "PBT: hue_shift 360 is identity" begin
        Supposition.@check function hue_360(c=rgb_gen)
            shifted = T.hue_shift(c, 360.0)
            abs(Int(shifted.r) - Int(c.r)) <= 1 &&
            abs(Int(shifted.g) - Int(c.g)) <= 1 &&
            abs(Int(shifted.b) - Int(c.b)) <= 1
        end
    end

    @testset "PBT: Rect contains corners" begin
        rect_gen = @composed function _rect(
                x=Data.Integers(1, 100),
                y=Data.Integers(1, 100),
                w=Data.Integers(1, 200),
                h=Data.Integers(1, 200))
            T.Rect(x, y, w, h)
        end
        Supposition.@check function contains_topleft(r=rect_gen)
            Base.contains(r, r.x, r.y)
        end
        Supposition.@check function contains_bottomright(r=rect_gen)
            Base.contains(r, T.right(r), T.bottom(r))
        end
        Supposition.@check function inner_fits(r=rect_gen)
            i = T.inner(r)
            i.x >= r.x && i.y >= r.y &&
            T.right(i) <= T.right(r) && T.bottom(i) <= T.bottom(r)
        end
    end

    @testset "PBT: split_layout preserves total size" begin
        cs_gen = Data.Vectors(constraint_gen; min_size=1, max_size=6)
        Supposition.@check function split_total_h(cs=cs_gen)
            w = 200
            r = T.Rect(1, 1, w, 24)
            layout = T.Layout(T.Horizontal, T.Constraint[c for c in cs])
            rects = T.split_layout(layout, r)
            length(rects) == length(cs) || return false
            total = sum(rect.width for rect in rects)
            total <= w
        end
        Supposition.@check function split_total_v(cs=cs_gen)
            h = 200
            r = T.Rect(1, 1, 80, h)
            layout = T.Layout(T.Vertical, T.Constraint[c for c in cs])
            rects = T.split_layout(layout, r)
            length(rects) == length(cs) || return false
            total = sum(rect.height for rect in rects)
            total <= h
        end
    end

    @testset "PBT: noise always in [0,1]" begin
        float_gen = map(x -> x / 100.0, Data.Integers(-1000, 1000))
        Supposition.@check function noise_range(x=float_gen)
            0.0 <= T.noise(x) <= 1.0
        end
        Supposition.@check function noise_2d_range(x=float_gen, y=float_gen)
            0.0 <= T.noise(x, y) <= 1.0
        end
        Supposition.@check function fbm_range(x=float_gen)
            0.0 <= T.fbm(x) <= 1.0
        end
    end

