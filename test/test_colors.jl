    @testset "Color utilities" begin
        # to_rgb for 6x6x6 cube
        c = T.Color256(196)  # bright red (in cube: r=5,g=0,b=0)
        rgb = T.to_rgb(c)
        @test rgb.r == 0xff
        @test rgb.g == 0x00
        @test rgb.b == 0x00

        # to_rgb for grayscale
        gray = T.to_rgb(T.Color256(244))
        @test gray.r == gray.g == gray.b

        # color_lerp
        a = T.ColorRGB(0x00, 0x00, 0x00)
        b = T.ColorRGB(0xff, 0xff, 0xff)
        mid = T.color_lerp(a, b, 0.5)
        @test 126 <= Int(mid.r) <= 129  # ~128
        @test mid.r == mid.g == mid.b

        # Endpoints
        @test T.color_lerp(a, b, 0.0) == a
        @test T.color_lerp(a, b, 1.0) == b
    end

    # Noise, fbm, pulse, breathe, shimmer, jitter, flicker, drift, glow,
    # brighten, dim_color, hue_shift — tested in test_animation.jl

    @testset "color_wave" begin
        colors = (T.Color256(196), T.Color256(46), T.Color256(21))
        c = T.color_wave(0, 0, colors)
        @test c isa T.ColorRGB

        # Disabled returns first color
        orig = T.ANIMATIONS_ENABLED[]
        T.ANIMATIONS_ENABLED[] = false
        c_off = T.color_wave(0, 0, colors)
        @test c_off == T.to_rgb(colors[1])
        T.ANIMATIONS_ENABLED[] = orig
    end

    @testset "BigText style_fn" begin
        T.set_theme!(T.KOKAKU)
        buf = T.Buffer(T.Rect(1, 1, 40, 6))
        rect = T.Rect(1, 1, 40, 5)
        # With style_fn, each pixel gets a custom style
        calls = Int[]
        fn = (x, y) -> begin
            push!(calls, x)
            Style(fg=T.ColorRGB(0xff, 0x00, 0x00), bold=true)
        end
        bt = T.BigText("AB"; style_fn=fn)
        T.render(bt, rect, buf)
        @test length(calls) > 0  # style_fn was called
        # Check that red was actually written
        found_red = any(c.style.fg == T.ColorRGB(0xff, 0x00, 0x00) for c in buf.content)
        @test found_red
    end

    @testset "fill_gradient!" begin
        buf = T.Buffer(T.Rect(1, 1, 10, 1))
        c1 = T.ColorRGB(0x00, 0x00, 0x00)
        c2 = T.ColorRGB(0xff, 0xff, 0xff)
        T.fill_gradient!(buf, T.Rect(1, 1, 10, 1), c1, c2)
        # First cell should be dark, last should be bright
        first_bg = buf.content[1].style.bg
        last_bg = buf.content[10].style.bg
        @test first_bg isa T.ColorRGB
        @test last_bg isa T.ColorRGB
        @test first_bg.r < last_bg.r
    end

    @testset "fill_noise!" begin
        buf = T.Buffer(T.Rect(1, 1, 10, 3))
        c1 = T.Color256(0)
        c2 = T.Color256(255)
        T.fill_noise!(buf, T.Rect(1, 1, 10, 3), c1, c2, 0)
        # All cells should have been filled (bg is ColorRGB)
        @test all(c.style.bg isa T.ColorRGB for c in buf.content)
    end

    @testset "border_shimmer!" begin
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        T.border_shimmer!(buf, T.Rect(1, 1, 10, 5), T.Color256(75), 0)
        # Corners should have been drawn
        @test buf.content[1].char == '╭'  # BOX_ROUNDED top-left
        # Border chars should have RGB fg
        @test buf.content[1].style.fg isa T.ColorRGB
    end

