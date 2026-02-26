    @testset "Animation" begin
        @testset "Easing functions" begin
            # All easing functions should map 0→0 and 1→1
            easings = [
                T.linear, T.ease_in_quad, T.ease_out_quad, T.ease_in_out_quad,
                T.ease_in_cubic, T.ease_out_cubic, T.ease_in_out_cubic,
                T.ease_out_elastic, T.ease_out_bounce, T.ease_out_back,
            ]
            for f in easings
                @test f(0.0) ≈ 0.0 atol=1e-10
                @test f(1.0) ≈ 1.0 atol=1e-10
            end

            # Monotonic at midpoint (sanity check values are in [0,1]-ish range)
            @test 0.0 <= T.ease_in_quad(0.5) <= 1.0
            @test 0.0 <= T.ease_out_quad(0.5) <= 1.0
            @test 0.0 <= T.ease_in_out_quad(0.5) <= 1.0
            @test 0.0 <= T.ease_in_cubic(0.5) <= 1.0
            @test 0.0 <= T.ease_out_cubic(0.5) <= 1.0
            @test 0.0 <= T.ease_in_out_cubic(0.5) <= 1.0
            @test 0.0 <= T.ease_out_bounce(0.5) <= 1.0
        end

        @testset "Tween" begin
            tw = T.tween(0.0, 100.0; duration=10, easing=T.linear)
            @test T.value(tw) ≈ 0.0
            @test !T.done(tw)

            for _ in 1:5
                T.advance!(tw)
            end
            @test T.value(tw) ≈ 50.0

            for _ in 1:5
                T.advance!(tw)
            end
            @test T.value(tw) ≈ 100.0
            @test T.done(tw)

            T.reset!(tw)
            @test T.value(tw) ≈ 0.0
            @test !T.done(tw)
        end

        @testset "Tween zero duration" begin
            tw = T.tween(0.0, 42.0; duration=0)
            @test T.value(tw) ≈ 42.0
        end

        @testset "Tween loop" begin
            tw = T.tween(0.0, 10.0; duration=5, easing=T.linear, loop=:loop)
            for _ in 1:5
                T.advance!(tw)
            end
            @test !T.done(tw)
            @test tw.elapsed == 0  # reset after completing
        end

        @testset "Tween pingpong" begin
            tw = T.tween(0.0, 10.0; duration=5, easing=T.linear, loop=:pingpong)
            for _ in 1:5
                T.advance!(tw)
            end
            @test !T.done(tw)
            @test tw.from == 10.0  # swapped
            @test tw.to == 0.0
        end

        @testset "Spring" begin
            s = T.Spring(10.0; value=0.0)
            @test s.value ≈ 0.0
            @test s.target ≈ 10.0
            @test !T.settled(s)

            # Advance many steps — should converge
            for _ in 1:600
                T.advance!(s)
            end
            @test T.settled(s)
            @test s.value ≈ 10.0 atol=0.01

            # Retarget
            T.retarget!(s, 20.0)
            @test s.target ≈ 20.0
            @test !T.settled(s)
        end

        @testset "Spring damping modes" begin
            s_crit = T.Spring(1.0; value=0.0, damping=:critical)
            s_over = T.Spring(1.0; value=0.0, damping=:over)
            s_under = T.Spring(1.0; value=0.0, damping=:under)
            @test s_crit.damping ≈ 2.0 * sqrt(180.0)
            @test s_over.damping ≈ 2.5 * sqrt(180.0)
            @test s_under.damping ≈ 1.2 * sqrt(180.0)

            # Numeric damping
            s_num = T.Spring(1.0; value=0.0, damping=5.0)
            @test s_num.damping ≈ 5.0
        end

        @testset "Timeline sequence" begin
            tw1 = T.tween(0.0, 1.0; duration=5, easing=T.linear)
            tw2 = T.tween(0.0, 1.0; duration=5, easing=T.linear)
            tl = T.sequence(tw1, tw2)

            @test length(tl.entries) == 2
            @test tl.entries[1].start_frame == 0
            @test tl.entries[2].start_frame == 5
            @test !T.done(tl)

            for _ in 1:10
                T.advance!(tl)
            end
            @test T.done(tl)
        end

        @testset "Timeline stagger" begin
            tweens = [T.tween(0.0, 1.0; duration=5) for _ in 1:3]
            tl = T.stagger(tweens...; delay=2)
            @test tl.entries[1].start_frame == 0
            @test tl.entries[2].start_frame == 2
            @test tl.entries[3].start_frame == 4
        end

        @testset "Timeline parallel" begin
            tweens = [T.tween(0.0, 1.0; duration=5) for _ in 1:3]
            tl = T.parallel(tweens...)
            @test all(e -> e.start_frame == 0, tl.entries)
        end

        @testset "Timeline loop" begin
            tw = T.tween(0.0, 1.0; duration=3, easing=T.linear)
            tl = T.Timeline([T.TimelineEntry(tw, 0)]; loop=true)
            @test !T.done(tl)  # looping timelines never report done

            for _ in 1:10
                T.advance!(tl)
            end
            @test !T.done(tl)
        end

        @testset "Animator" begin
            a = T.Animator()
            tw = T.tween(0.0, 100.0; duration=10, easing=T.linear)
            T.animate!(a, :x, tw)

            s = T.Spring(50.0; value=0.0)
            T.animate!(a, :y, s)

            @test T.val(a, :x) ≈ 0.0

            T.tick!(a)
            @test T.val(a, :x) > 0.0
            @test T.val(a, :y) > 0.0

            @test_throws ErrorException T.val(a, :nonexistent)
        end

        @testset "Noise functions" begin
            # 1D noise
            @test 0.0 <= T.noise(0.0) <= 1.0
            @test 0.0 <= T.noise(3.7) <= 1.0
            # Deterministic
            @test T.noise(1.5) == T.noise(1.5)
            # Different inputs give different outputs
            @test T.noise(0.0) != T.noise(0.5)

            # 2D noise
            @test 0.0 <= T.noise(1.0, 2.0) <= 1.0
            @test T.noise(1.0, 2.0) == T.noise(1.0, 2.0)
        end

        @testset "FBM" begin
            @test 0.0 <= T.fbm(1.0) <= 1.0
            @test 0.0 <= T.fbm(1.0, 2.0) <= 1.0
            # Zero octaves returns 0.5
            @test T.fbm(1.0; octaves=0) == 0.5
            @test T.fbm(1.0, 2.0; octaves=0) == 0.5
        end

        @testset "Tick-driven effects" begin
            # Enable animations for these tests
            old = T.ANIMATIONS_ENABLED[]
            T.ANIMATIONS_ENABLED[] = true

            @test 0.3 <= T.pulse(0) <= 1.0
            @test 0.0 <= T.breathe(0) <= 1.0
            @test 0.0 <= T.shimmer(10, 5) <= 1.0
            @test -0.5 <= T.jitter(10, 1) <= 0.5
            @test 0.9 <= T.flicker(10) <= 1.0
            @test 0.0 <= T.drift(10) <= 1.0
            @test T.glow(5, 5, 5.0, 5.0) ≈ 1.0  # at center

            # Disabled animations return defaults
            T.ANIMATIONS_ENABLED[] = false
            @test T.pulse(10) == 1.0
            @test T.breathe(10) == 1.0
            @test T.shimmer(10, 5) == 0.5
            @test T.jitter(10, 1) == 0.0
            @test T.flicker(10) == 1.0
            @test T.drift(10) == 0.5

            T.ANIMATIONS_ENABLED[] = old
        end

        @testset "Color manipulation" begin
            red = T.ColorRGB(255, 0, 0)

            bright = T.brighten(red, 0.5)
            @test bright.r > red.r || bright.r == 255
            @test bright.g > 0
            @test bright.b > 0

            dimmed = T.dim_color(red, 0.5)
            @test dimmed.r < red.r
            @test dimmed.g == 0
            @test dimmed.b == 0

            # Identity cases
            @test T.brighten(red, 0.0) == red
            @test T.dim_color(red, 0.0) == red

            # Extremes
            @test T.brighten(red, 1.0) == T.ColorRGB(0xff, 0xff, 0xff)
            @test T.dim_color(red, 1.0) == T.ColorRGB(0x00, 0x00, 0x00)

            # Color256 variants delegate to RGB
            c256 = T.Color256(196)
            @test T.brighten(c256, 0.5) isa T.ColorRGB
            @test T.dim_color(c256, 0.5) isa T.ColorRGB
        end

        @testset "Hue shift" begin
            red = T.ColorRGB(255, 0, 0)
            shifted = T.hue_shift(red, 120.0)
            # Red shifted 120° should be roughly green
            @test shifted.g > shifted.r
            @test shifted.g > shifted.b

            # 360° rotation should return approximately the same color
            full = T.hue_shift(red, 360.0)
            @test full.r ≈ red.r atol=2
            @test full.g ≈ red.g atol=2
            @test full.b ≈ red.b atol=2

            # Color256 variant
            @test T.hue_shift(T.Color256(196), 60.0) isa T.ColorRGB
        end

        @testset "Glow" begin
            @test T.glow(5, 5, 5.0, 5.0) ≈ 1.0
            @test T.glow(100, 100, 5.0, 5.0) ≈ 0.0
            # Midpoint
            g = T.glow(5, 5, 5.0, 5.0; radius=10.0)
            @test g ≈ 1.0
        end
    end
