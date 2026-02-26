    @testset "Style & Themes" begin
        @testset "tstyle" begin
            s = T.tstyle(:primary)
            @test s isa T.Style
            @test s.fg == T.theme().primary
            @test !s.bold

            s2 = T.tstyle(:accent, bold=true, dim=true)
            @test s2.fg == T.theme().accent
            @test s2.bold
            @test s2.dim
        end

        @testset "set_theme! by symbol" begin
            old = T.theme()
            T.set_theme!(:motoko)
            @test T.theme().name == "motoko"
            T.set_theme!(:kaneda)
            @test T.theme().name == "kaneda"
            T.set_theme!(old)
        end

        @testset "set_theme! unknown" begin
            @test_throws ErrorException T.set_theme!(:nonexistent)
        end

        @testset "ALL_THEMES coverage" begin
            @test length(T.ALL_THEMES) == 11
            names = [t.name for t in T.ALL_THEMES]
            @test "kokaku" in names
            @test "esper" in names
            @test "iceberg" in names
        end

        @testset "write_style round-trip" begin
            io = IOBuffer()
            s = T.Style(fg=T.Color256(196), bg=T.ColorRGB(10, 20, 30),
                        bold=true, dim=true, italic=true, underline=true)
            T.write_style(io, s)
            output = String(take!(io))
            @test contains(output, "\e[0m")
            @test contains(output, "\e[38;5;196m")
            @test contains(output, "\e[48;2;10;20;30m")
            @test contains(output, "\e[1m")
            @test contains(output, "\e[2m")
            @test contains(output, "\e[3m")
            @test contains(output, "\e[4m")
        end

        @testset "write_fg/write_bg" begin
            io = IOBuffer()
            T.write_fg(io, T.NoColor())
            @test length(take!(io)) == 0

            T.write_fg(io, T.Color256(42))
            @test contains(String(take!(io)), "38;5;42")

            T.write_fg(io, T.ColorRGB(1, 2, 3))
            @test contains(String(take!(io)), "38;2;1;2;3")

            T.write_bg(io, T.NoColor())
            @test length(take!(io)) == 0

            T.write_bg(io, T.Color256(42))
            @test contains(String(take!(io)), "48;5;42")

            T.write_bg(io, T.ColorRGB(1, 2, 3))
            @test contains(String(take!(io)), "48;2;1;2;3")
        end

        @testset "hex_to_color256" begin
            # Pure red should map to xterm red
            c = T.hex_to_color256(0xff0000)
            @test c isa T.Color256

            # Pure white should map to 231 (brightest in cube)
            c = T.hex_to_color256(0xffffff)
            @test c.code == 231

            # Gray should map to grayscale ramp
            c = T.hex_to_color256(0x808080)
            @test c isa T.Color256
        end

        @testset "DecayParams" begin
            d = T.DecayParams()
            @test d.decay == 0.0
            @test d.jitter == 0.0

            d2 = T.DecayParams(0.5, 0.1, 0.05, 0.2)
            @test d2.decay == 0.5
            @test d2.noise_scale == 0.2
        end

        @testset "animations_enabled toggle" begin
            old = T.ANIMATIONS_ENABLED[]
            T.ANIMATIONS_ENABLED[] = true
            @test T.animations_enabled()
            T.ANIMATIONS_ENABLED[] = false
            @test !T.animations_enabled()
            T.ANIMATIONS_ENABLED[] = old
        end

        @testset "render_backend" begin
            @test T.render_backend() isa T.RenderBackend
        end

        @testset "GraphicsProtocol" begin
            @test T.graphics_protocol() isa T.GraphicsProtocol
        end
    end
