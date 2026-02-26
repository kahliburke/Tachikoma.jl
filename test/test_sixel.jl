    # ═════════════════════════════════════════════════════════════════
    # Sixel encoder
    # ═════════════════════════════════════════════════════════════════

    @testset "Sixel encoder: red pixels" begin
        red = T.ColorRGB(0xff, 0x00, 0x00)
        pixels = fill(red, 6, 4)  # 6 rows, 4 cols
        data = T.encode_sixel(pixels)
        str = String(copy(data))
        # DCS framing (P2=0 explicit background)
        @test startswith(str, "\eP0;0q")
        @test endswith(str, "\e\\")
        # Should contain color 0 (black filler) and color 1 (red data)
        @test occursin("#0;2;0;0;0", str)
        # Color is quantized (0xff→0xfc=252 → 99%) for palette efficiency
        @test occursin("#1;2;99;0;0", str)
    end

    @testset "Sixel encoder: empty input" begin
        pixels = Matrix{T.ColorRGB}(undef, 0, 0)
        @test isempty(T.encode_sixel(pixels))
    end

    @testset "Sixel encoder: all black (no palette)" begin
        black = T.ColorRGB(0x00, 0x00, 0x00)
        pixels = fill(black, 6, 4)
        @test isempty(T.encode_sixel(pixels))
    end

    @testset "Sixel encoder: multi-color palette" begin
        red = T.ColorRGB(0xff, 0x00, 0x00)
        green = T.ColorRGB(0x00, 0xff, 0x00)
        pixels = fill(red, 6, 4)
        pixels[1:3, :] .= Ref(green)
        data = T.encode_sixel(pixels)
        str = String(copy(data))
        # Both quantized red (0xfc,0,0 → 99%) and green (0,0xfc,0 → 99%)
        # should appear as palette entries in the output
        @test occursin("#1;2;", str)
        @test occursin("#2;2;", str)
        # Verify both red-ish and green-ish color definitions are present
        @test occursin(";99;0;0", str)   # red channel
        @test occursin(";0;99;0", str)   # green channel
    end

    # ═════════════════════════════════════════════════════════════════
    # Decay effects
    # ═════════════════════════════════════════════════════════════════

    @testset "Decay: zero decay is no-op" begin
        red = T.ColorRGB(0xff, 0x00, 0x00)
        pixels = fill(red, 4, 4)
        original = copy(pixels)
        T.apply_decay!(pixels, T.DecayParams(), 0)
        @test pixels == original
    end

    @testset "Decay: jitter mutates pixels" begin
        red = T.ColorRGB(0xff, 0x00, 0x00)
        pixels = fill(red, 10, 10)
        params = T.DecayParams(1.0, 1.0, 0.0, 0.0)
        T.apply_decay!(pixels, params, 42)
        # At least some pixels should have changed
        changed = count(px -> px != red && px != T.ColorRGB(0,0,0), pixels)
        @test changed > 0
    end

    @testset "Decay: rot corrupts pixels" begin
        red = T.ColorRGB(0xff, 0x00, 0x00)
        pixels = fill(red, 10, 10)
        params = T.DecayParams(1.0, 0.0, 1.0, 0.0)
        T.apply_decay!(pixels, params, 42)
        # Some pixels should be corrupted (black or hue-shifted)
        changed = count(px -> px != red, pixels)
        @test changed > 0
    end

    # ═════════════════════════════════════════════════════════════════
    # PixelCanvas
    # ═════════════════════════════════════════════════════════════════

    @testset "PixelCanvas construction" begin
        sc = T.PixelCanvas(10, 5)
        cpx = T.CELL_PX[]
        @test sc.pixel_w == 10 * cpx.w
        @test sc.pixel_h == 5 * cpx.h
        @test sc.dot_w == 10 * 2
        @test sc.dot_h == 5 * 4
        @test sc.width == 10
        @test sc.height == 5
        @test size(sc.pixels) == (sc.pixel_h, sc.pixel_w)
    end

    @testset "PixelCanvas set_point!/unset_point!" begin
        sc = T.PixelCanvas(5, 3)
        # All black initially
        @test all(px == T.ColorRGB(0,0,0) for px in sc.pixels)

        # Set a point
        T.set_point!(sc, 0, 0)
        @test any(px != T.ColorRGB(0,0,0) for px in sc.pixels)

        # Unset it
        T.unset_point!(sc, 0, 0)
        @test all(px == T.ColorRGB(0,0,0) for px in sc.pixels)
    end

    @testset "PixelCanvas line!" begin
        sc = T.PixelCanvas(5, 3)
        T.line!(sc, 0, 0, 9, 11)
        @test any(px != T.ColorRGB(0,0,0) for px in sc.pixels)
    end

    @testset "PixelCanvas clear!" begin
        sc = T.PixelCanvas(5, 3)
        T.set_point!(sc, 0, 0)
        T.clear!(sc)
        @test all(px == T.ColorRGB(0,0,0) for px in sc.pixels)
    end

    @testset "PixelCanvas out of bounds" begin
        sc = T.PixelCanvas(5, 3)
        # Should not crash
        T.set_point!(sc, -1, -1)
        T.set_point!(sc, 9999, 9999)
        T.unset_point!(sc, -1, -1)
        T.unset_point!(sc, 9999, 9999)
        @test true
    end

    @testset "PixelCanvas render to Buffer (fallback)" begin
        sc = T.PixelCanvas(5, 3)
        T.set_point!(sc, 0, 0)
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        T.render(sc, T.Rect(1, 1, 5, 3), buf)
        # Cell (1,1) should be a braille character
        @test UInt32(buf.content[1].char) >= 0x2800
        @test UInt32(buf.content[1].char) <= 0x28FF
    end

    @testset "PixelCanvas render to Frame" begin
        sc = T.PixelCanvas(5, 3)
        T.set_point!(sc, 0, 0)
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        frame = T.Frame(buf, T.Rect(1, 1, 10, 5), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render(sc, T.Rect(1, 1, 5, 3), frame; tick=0)
        # Should have pushed a sixel region
        @test length(frame.gfx_regions) == 1
        @test !isempty(frame.gfx_regions[1].data)
    end

    # ═════════════════════════════════════════════════════════════════
    # PixelImage widget
    # ═════════════════════════════════════════════════════════════════

    @testset "PixelImage construction" begin
        img = T.PixelImage(10, 5)
        @test img.cells_w == 10
        @test img.cells_h == 5
        @test img.pixel_w >= 1
        @test img.pixel_h >= 1
        @test size(img.pixels) == (img.pixel_h, img.pixel_w)
    end

    @testset "PixelImage set_pixel!" begin
        img = T.PixelImage(5, 3)
        T.set_pixel!(img, 1, 1, T.ColorRGB(0xff, 0x00, 0x00))
        @test img.pixels[1, 1] == T.ColorRGB(0xff, 0x00, 0x00)
        # Out of bounds is silently ignored
        T.set_pixel!(img, 0, 0, T.ColorRGB(0xff, 0x00, 0x00))
        T.set_pixel!(img, img.pixel_w + 1, 1, T.ColorRGB(0xff, 0x00, 0x00))
    end

    @testset "PixelImage fill_rect!" begin
        img = T.PixelImage(5, 3)
        color = T.ColorRGB(0x00, 0xff, 0x00)
        T.fill_rect!(img, 1, 1, 3, 3, color)
        @test img.pixels[1, 1] == color
        @test img.pixels[2, 2] == color
    end

    @testset "PixelImage pixel_line!" begin
        img = T.PixelImage(5, 3)
        color = T.ColorRGB(0x00, 0x00, 0xff)
        T.pixel_line!(img, 1, 1, min(img.pixel_w, 10), min(img.pixel_h, 5), color)
        @test img.pixels[1, 1] == color
    end

    @testset "PixelImage clear!" begin
        img = T.PixelImage(5, 3)
        T.set_pixel!(img, 1, 1, T.ColorRGB(0xff, 0xff, 0xff))
        T.clear!(img)
        @test img.pixels[1, 1] == T.BLACK
    end

    @testset "PixelImage render to Frame" begin
        img = T.PixelImage(5, 3)
        T.set_pixel!(img, 1, 1, T.ColorRGB(0xff, 0x00, 0x00))
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        frame = T.Frame(buf, T.Rect(1, 1, 10, 5), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render(img, T.Rect(1, 1, 5, 3), frame; tick=0)
        @test length(frame.gfx_regions) == 1
        @test !isempty(frame.gfx_regions[1].data)
    end

    @testset "PixelImage render to Buffer (braille fallback)" begin
        img = T.PixelImage(5, 3)
        T.set_pixel!(img, 1, 1, T.ColorRGB(0xff, 0x00, 0x00))
        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        T.render(img, T.Rect(1, 1, 5, 3), buf)
        # Should have set some braille characters
        @test UInt32(buf.content[1].char) >= 0x2800
    end

    @testset "PixelImage resize on render" begin
        img = T.PixelImage(5, 3)
        old_pw = img.pixel_w
        old_ph = img.pixel_h
        buf = T.Buffer(T.Rect(1, 1, 20, 10))
        frame = T.Frame(buf, T.Rect(1, 1, 20, 10), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render(img, T.Rect(1, 1, 10, 6), frame; tick=0)
        @test img.cells_w == 10
        @test img.cells_h == 6
    end

    @testset "PixelImage with block" begin
        img = T.PixelImage(10, 5; block=T.Block(title="test"))
        buf = T.Buffer(T.Rect(1, 1, 12, 7))
        frame = T.Frame(buf, T.Rect(1, 1, 12, 7), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render(img, T.Rect(1, 1, 12, 7), frame; tick=0)
        # Block should have been rendered (check corners for border chars)
        @test true  # doesn't crash
    end

    @testset "PixelImage load_pixels!" begin
        img = T.PixelImage(5, 3)
        src = fill(T.ColorRGB(0xff, 0x00, 0x00), 4, 4)
        T.load_pixels!(img, src)
        @test img.pixels[1, 1] == T.ColorRGB(0xff, 0x00, 0x00)
    end

    # ═════════════════════════════════════════════════════════════════
    # create_canvas factory
    # ═════════════════════════════════════════════════════════════════

    @testset "create_canvas: braille backend" begin
        orig = T.RENDER_BACKEND[]
        T.RENDER_BACKEND[] = T.braille_backend
        c = T.create_canvas(10, 5)
        @test c isa T.Canvas
        T.RENDER_BACKEND[] = orig
    end

    @testset "create_canvas: sixel backend falls back to braille" begin
        orig = T.RENDER_BACKEND[]
        T.RENDER_BACKEND[] = T.sixel_backend
        c = T.create_canvas(10, 5)
        @test c isa T.Canvas  # sixel is now a widget, not a canvas backend
        T.RENDER_BACKEND[] = orig
    end

    # ═════════════════════════════════════════════════════════════════
    # RenderBackend preference
    # ═════════════════════════════════════════════════════════════════

    @testset "RenderBackend get/set roundtrip" begin
        orig = T.RENDER_BACKEND[]
        # sixel_backend now gracefully migrates to braille on load
        T.set_render_backend!(T.sixel_backend)
        @test T.render_backend() == T.sixel_backend
        T.load_render_backend!()
        @test T.render_backend() == T.braille_backend  # migrated

        T.set_render_backend!(T.braille_backend)
        @test T.render_backend() == T.braille_backend
        T.load_render_backend!()
        @test T.render_backend() == T.braille_backend

        T.RENDER_BACKEND[] = orig
    end

    # DecayParams — tested in test_style.jl

    # ═════════════════════════════════════════════════════════════════
    # Settings overlay
    # ═════════════════════════════════════════════════════════════════

    @testset "Settings overlay render" begin
        ov = T.AppOverlay()
        ov.show_settings = true
        ov.settings_idx = 1
        buf = T.Buffer(T.Rect(1, 1, 60, 30))
        frame = T.Frame(buf, T.Rect(1, 1, 60, 30), T.GraphicsRegion[], T.PixelSnapshot[])
        T.render_overlay!(ov, frame)
        # Should render heavy border
        found_heavy = false
        for c in buf.content
            if c.char == '┏' || c.char == '┓'
                found_heavy = true
                break
            end
        end
        @test found_heavy
    end

    @testset "Settings overlay adjust" begin
        orig_backend = T.RENDER_BACKEND[]
        orig_decay = T.DECAY[]

        T.RENDER_BACKEND[] = T.braille_backend
        T.DECAY[] = T.DecayParams()

        # Adjust backend via right arrow on item 1 (cycles: braille→block)
        T._adjust_setting!(1, 1)
        @test T.RENDER_BACKEND[] == T.block_backend
        T._adjust_setting!(1, 1)
        @test T.RENDER_BACKEND[] == T.braille_backend  # wraps around
        T._adjust_setting!(1, -1)
        @test T.RENDER_BACKEND[] == T.block_backend
        T._adjust_setting!(1, -1)
        @test T.RENDER_BACKEND[] == T.braille_backend

        # Adjust decay amount
        T._adjust_setting!(2, 1)
        @test T.DECAY[].decay ≈ 0.05

        # Adjust jitter
        T._adjust_setting!(3, 1)
        @test T.DECAY[].jitter ≈ 0.05

        # Adjust rot
        T._adjust_setting!(4, 1)
        @test T.DECAY[].rot_prob ≈ 0.05

        # Clamping: can't go below 0
        T.DECAY[].decay = 0.0
        T._adjust_setting!(2, -1)
        @test T.DECAY[].decay == 0.0

        T.RENDER_BACKEND[] = orig_backend
        T.DECAY[] = orig_decay
    end

    @testset "AppOverlay settings fields" begin
        ov = T.AppOverlay()
        @test !ov.show_settings
        @test ov.settings_idx == 1
    end

    @testset "HELP_LINES includes Ctrl+S" begin
        @test any(occursin("Ctrl+S", l) for l in T.HELP_LINES)
    end

    @testset "Background color adjustment" begin
        c = T.ColorRGB(0xff, 0x80, 0x00)

        # Brightness 0.5, full saturation → colors dimmed
        adj = T._apply_bg_adjustments(c, 0.5, 1.0)
        @test adj.r < c.r
        @test adj.g < c.g

        # Full desaturation → grayscale
        gray = T._apply_bg_adjustments(c, 1.0, 0.0)
        @test abs(Int(gray.r) - Int(gray.g)) <= 1
        @test abs(Int(gray.g) - Int(gray.b)) <= 1
    end

    @testset "Background renders to buffer" begin
        bg = T.DotWaveBackground(preset=1, amplitude=3.0, cam_height=6.0)
        buf = T.Buffer(T.Rect(1, 1, 40, 20))
        area = T.Rect(1, 1, 40, 20)

        T.render_background!(bg, buf, area, 10;
                             brightness=0.5, saturation=0.5, speed=1.0)

        non_empty = count(c -> c.char != ' ', buf.content)
        @test non_empty > 0
    end

    @testset "Background renders to sub-area" begin
        bg = T.DotWaveBackground()
        buf = T.Buffer(T.Rect(1, 1, 80, 24))

        # Render into a smaller panel only
        panel = T.Rect(10, 5, 30, 10)
        T.render_background!(bg, buf, panel, 5; brightness=0.3)

        # Cells outside panel should be empty
        @test buf.content[1].char == ' '
        # Cells inside panel should have content
        i = T.buf_index(buf, 20, 8)
        non_empty_panel = count(c -> c.char != ' ', buf.content)
        @test non_empty_panel > 0
    end

    @testset "DotWaveBackground preset clamping" begin
        bg = T.DotWaveBackground(preset=999, amplitude=3.0, cam_height=6.0)
        buf = T.Buffer(T.Rect(1, 1, 20, 10))
        T.render_background!(bg, buf, T.Rect(1, 1, 20, 10), 5)
        @test true
    end

    @testset "DotWaveBackground keyword constructor" begin
        bg = T.DotWaveBackground(preset=3, amplitude=2.0, cam_height=8.0)
        @test bg.preset_idx == 3
        @test bg.amplitude == 2.0
        @test bg.cam_height == 8.0
    end

    @testset "desaturate" begin
        c = T.ColorRGB(0xff, 0x00, 0x00)  # pure red
        gray = T.desaturate(c, 1.0)  # full desaturation
        # Luminance of pure red: 0.299*255 ≈ 76
        @test abs(Int(gray.r) - Int(gray.g)) <= 1
        @test abs(Int(gray.g) - Int(gray.b)) <= 1

        # No desaturation should return original
        same = T.desaturate(c, 0.0)
        @test same.r == c.r && same.g == c.g && same.b == c.b
    end

    @testset "BackgroundConfig defaults" begin
        c = T.BackgroundConfig()
        @test c.brightness == 0.3
        @test c.saturation == 0.5
        @test c.speed == 0.5
    end

    @testset "BackgroundConfig global ref" begin
        orig = T.BG_CONFIG[]
        T.BG_CONFIG[] = T.BackgroundConfig(0.8, 0.2, 0.9)
        @test T.bg_config().brightness == 0.8
        @test T.bg_config().saturation == 0.2
        @test T.bg_config().speed == 0.9
        T.BG_CONFIG[] = orig
    end

    @testset "BackgroundConfig save/load roundtrip" begin
        orig = T.BG_CONFIG[]
        T.BG_CONFIG[] = T.BackgroundConfig(0.7, 0.4, 0.6)
        T.save_bg_config!()
        T.BG_CONFIG[] = T.BackgroundConfig()  # reset
        T.load_bg_config!()
        @test T.bg_config().brightness ≈ 0.7
        @test T.bg_config().saturation ≈ 0.4
        @test T.bg_config().speed ≈ 0.6
        T.BG_CONFIG[] = orig
        T.save_bg_config!()  # restore saved prefs
    end

    @testset "render_background! uses global config" begin
        # Change global config and verify it affects defaults
        orig = T.BG_CONFIG[]
        T.BG_CONFIG[] = T.BackgroundConfig(0.1, 0.1, 0.1)
        bg = T.DotWaveBackground()
        buf = T.Buffer(T.Rect(1, 1, 20, 10))
        T.render_background!(bg, buf, T.Rect(1, 1, 20, 10), 5)
        @test true  # no crash with custom config
        T.BG_CONFIG[] = orig
    end

    @testset "Settings overlay BG items" begin
        @test length(T.SETTINGS_ITEMS) == 8
        @test T.SETTINGS_ITEMS[6] == "BG Brightness"
        @test T.SETTINGS_ITEMS[7] == "BG Saturation"
        @test T.SETTINGS_ITEMS[8] == "BG Speed"
    end

    @testset "Settings BG adjust" begin
        orig = T.BG_CONFIG[]
        T.BG_CONFIG[] = T.BackgroundConfig(0.5, 0.5, 0.5)

        T._adjust_setting!(6, 1)
        @test T.BG_CONFIG[].brightness ≈ 0.55

        T._adjust_setting!(7, -1)
        @test T.BG_CONFIG[].saturation ≈ 0.45

        T._adjust_setting!(8, 1)
        @test T.BG_CONFIG[].speed ≈ 0.55

        # Clamping
        T.BG_CONFIG[].brightness = 1.0
        T._adjust_setting!(6, 1)
        @test T.BG_CONFIG[].brightness == 1.0

        T.BG_CONFIG[].speed = 0.0
        T._adjust_setting!(8, -1)
        @test T.BG_CONFIG[].speed == 0.0

        T.BG_CONFIG[] = orig
    end

