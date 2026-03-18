    # ═════════════════════════════════════════════════════════════════
    # parse_ansi / Paragraph ANSI integration Tests
    # ═════════════════════════════════════════════════════════════════

    @testset "parse_ansi: plain text (no escapes)" begin
        spans = T.parse_ansi("hello world")
        @test length(spans) == 1
        @test spans[1].content == "hello world"
        @test spans[1].style == T.RESET
    end

    @testset "parse_ansi: empty string" begin
        spans = T.parse_ansi("")
        @test length(spans) >= 1
    end

    @testset "parse_ansi: bold" begin
        spans = T.parse_ansi("\e[1mbold\e[0m")
        @test spans[1].style.bold == true
        @test spans[1].content == "bold"
    end

    @testset "parse_ansi: standard foreground colors" begin
        spans = T.parse_ansi("\e[31mred\e[32mgreen\e[0m")
        @test spans[1].style.fg == T.Color256(1)  # red = color 1
        @test spans[1].content == "red"
        @test spans[2].style.fg == T.Color256(2)  # green = color 2
        @test spans[2].content == "green"
    end

    @testset "parse_ansi: bright foreground colors" begin
        spans = T.parse_ansi("\e[91mbright red\e[0m")
        @test spans[1].style.fg == T.Color256(9)  # bright red = 8+1
        @test spans[1].content == "bright red"
    end

    @testset "parse_ansi: background colors" begin
        spans = T.parse_ansi("\e[44mblue bg\e[0m")
        @test spans[1].style.bg == T.Color256(4)
        @test spans[1].content == "blue bg"
    end

    @testset "parse_ansi: 256-color foreground" begin
        spans = T.parse_ansi("\e[38;5;208morange\e[0m")
        @test spans[1].style.fg == T.Color256(208)
        @test spans[1].content == "orange"
    end

    @testset "parse_ansi: 256-color background" begin
        spans = T.parse_ansi("\e[48;5;17mnavy\e[0m")
        @test spans[1].style.bg == T.Color256(17)
        @test spans[1].content == "navy"
    end

    @testset "parse_ansi: 24-bit RGB foreground" begin
        spans = T.parse_ansi("\e[38;2;255;128;0morange\e[0m")
        @test spans[1].style.fg == T.ColorRGB(0xff, 0x80, 0x00)
    end

    @testset "parse_ansi: 24-bit RGB background" begin
        spans = T.parse_ansi("\e[48;2;0;0;255mblue\e[0m")
        @test spans[1].style.bg == T.ColorRGB(0x00, 0x00, 0xff)
    end

    @testset "parse_ansi: combined attributes" begin
        spans = T.parse_ansi("\e[1;3;4;31mbold italic underline red\e[0m")
        s = spans[1].style
        @test s.bold == true
        @test s.italic == true
        @test s.underline == true
        @test s.fg == T.Color256(1)
    end

    @testset "parse_ansi: reset clears all" begin
        spans = T.parse_ansi("\e[1;31mbold red\e[0mnormal")
        @test spans[1].style.bold == true
        @test spans[1].style.fg == T.Color256(1)
        @test spans[2].style == T.RESET
        @test spans[2].content == "normal"
    end

    @testset "parse_ansi: bare ESC[m is reset" begin
        spans = T.parse_ansi("\e[31mred\e[mnormal")
        @test spans[2].style == T.RESET
    end

    @testset "parse_ansi: dim, strikethrough, attribute resets" begin
        spans = T.parse_ansi("\e[2;9mdim+strike\e[22;29mnormal")
        @test spans[1].style.dim == true
        @test spans[1].style.strikethrough == true
        @test spans[2].style.dim == false
        @test spans[2].style.strikethrough == false
    end

    @testset "parse_ansi: reverse video (SGR 7/27)" begin
        # Reverse swaps fg and bg in the output style
        spans = T.parse_ansi("\e[31;42;7mreversed\e[0m")
        @test spans[1].style.fg == T.Color256(2)  # bg green → fg
        @test spans[1].style.bg == T.Color256(1)  # fg red → bg
        @test spans[1].content == "reversed"
    end

    @testset "parse_ansi: reverse off (SGR 27)" begin
        spans = T.parse_ansi("\e[31;7mrev\e[27mnormal")
        # reversed: fg=NoColor (was bg), bg=Color256(1) (was fg red)
        @test spans[1].style.bg == T.Color256(1)
        # after reverse off: fg=Color256(1), bg=NoColor
        @test spans[2].style.fg == T.Color256(1)
        @test spans[2].style.bg isa T.NoColor
    end

    @testset "parse_ansi: default color reset (39/49)" begin
        spans = T.parse_ansi("\e[31;42mcolored\e[39mfg reset\e[49mbg reset")
        @test spans[1].style.fg == T.Color256(1)
        @test spans[1].style.bg == T.Color256(2)
        @test spans[2].style.fg isa T.NoColor
        @test spans[2].style.bg == T.Color256(2)
        @test spans[3].style.bg isa T.NoColor
    end

    @testset "parse_ansi: non-SGR escapes are stripped" begin
        # Cursor movement, title set, etc. should be ignored
        spans = T.parse_ansi("before\e[2Aafter")  # cursor up
        text = join(s.content for s in spans)
        @test text == "beforeafter"
    end

    @testset "parse_ansi: mixed text and multiple sequences" begin
        s = "\e[1mA\e[0m B \e[32mC\e[0m"
        spans = T.parse_ansi(s)
        text = join(sp.content for sp in spans)
        @test text == "A B C"
    end

    @testset "parse_ansi: bright background colors" begin
        spans = T.parse_ansi("\e[103mbright yellow bg\e[0m")
        @test spans[1].style.bg == T.Color256(11)  # bright yellow = 8+3
    end

    # ── Paragraph auto-detection of ANSI ────────────────────────────

    @testset "Paragraph: auto-parses ANSI strings" begin
        p = T.Paragraph("\e[31mhello\e[0m world")
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, p)
        @test rstrip(T.row_text(tb, 1)) == "hello world"
        # 'h' should be red (Color256(1))
        @test T.style_at(tb, 1, 1).fg == T.Color256(1)
        # 'w' should have default fg
        @test T.style_at(tb, 7, 1).fg isa T.NoColor
    end

    @testset "Paragraph: plain text still works" begin
        p = T.Paragraph("no escapes here")
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, p)
        @test rstrip(T.row_text(tb, 1)) == "no escapes here"
    end

    @testset "Paragraph: ANSI with block" begin
        p = T.Paragraph("\e[32mOK\e[0m", block=T.Block(title="Status"))
        tb = T.TestBackend(20, 5)
        T.render_widget!(tb, p)
        @test T.find_text(tb, "Status") !== nothing
        @test T.find_text(tb, "OK") !== nothing
    end

    @testset "Paragraph: ANSI with word wrap" begin
        p = T.Paragraph("\e[31mhello world foo bar\e[0m", wrap=T.word_wrap)
        tb = T.TestBackend(10, 5)
        T.render_widget!(tb, p)
        @test rstrip(T.row_text(tb, 1)) == "hello"
        @test rstrip(T.row_text(tb, 2)) == "world foo"
    end

    # ── ScrollPane ANSI support ─────────────────────────────────────

    @testset "ScrollPane: renders ANSI strings" begin
        sp = T.ScrollPane(["\e[31mred line\e[0m", "plain line"])
        tb = T.TestBackend(20, 4)
        T.render_widget!(tb, sp)
        @test T.style_at(tb, 1, 1).fg == T.Color256(1)  # red
        @test rstrip(T.row_text(tb, 1)) == "red line"
        @test rstrip(T.row_text(tb, 2)) == "plain line"
    end

    @testset "ScrollPane: ANSI with word wrap" begin
        sp = T.ScrollPane(["\e[32mhello world\e[0m"], word_wrap=true)
        tb = T.TestBackend(6, 4)
        T.render_widget!(tb, sp)
        @test T.style_at(tb, 1, 1).fg == T.Color256(2)  # green
    end

    # ── Per-widget opt-out ──────────────────────────────────────────

    @testset "Paragraph: ansi=false strips escapes" begin
        p = T.Paragraph("\e[31mred\e[0m", ansi=false)
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, p)
        # Not parsed as red — gets the default text style
        @test T.style_at(tb, 1, 1).fg != T.Color256(1)
        # Escape sequences stripped — shows clean text "red"
        @test rstrip(T.row_text(tb, 1)) == "red"
    end

    @testset "Paragraph: raw=true shows literal escapes" begin
        p = T.Paragraph("\e[31mred\e[0m", raw=true)
        tb = T.TestBackend(30, 3)
        T.render_widget!(tb, p)
        # ESC replaced with ␛, bracket codes visible
        row = rstrip(T.row_text(tb, 1))
        @test occursin("␛[31m", row)
        @test occursin("red", row)
        @test occursin("␛[0m", row)
    end

    @testset "Paragraph: raw=true with char_wrap sizes correctly" begin
        # "␛[31mX␛[0m" = 11 display columns
        p = T.Paragraph("\e[31mX\e[0m", raw=true, wrap=T.char_wrap)
        tb = T.TestBackend(6, 4)
        T.render_widget!(tb, p)
        # Should wrap correctly — first line fits "␛[31mX" (6 cols)
        row1 = rstrip(T.row_text(tb, 1))
        row2 = rstrip(T.row_text(tb, 2))
        @test length(row1) > 0
        @test length(row2) > 0
        full = row1 * row2
        @test occursin("␛[31m", full)
    end

    @testset "ScrollPane: ansi=false skips parsing" begin
        sp = T.ScrollPane(["\e[31mred\e[0m"], ansi=false)
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, sp)
        @test T.style_at(tb, 1, 1).fg != T.Color256(1)
    end

    # ── Global default ──────────────────────────────────────────────

    @testset "Global ansi_enabled! controls default" begin
        # Disable globally
        T.set_ansi_enabled!(false)
        p = T.Paragraph("\e[31mred\e[0m")
        tb = T.TestBackend(20, 3)
        T.render_widget!(tb, p)
        @test T.style_at(tb, 1, 1).fg != T.Color256(1)  # not parsed as red

        # Per-widget override still works
        p2 = T.Paragraph("\e[31mred\e[0m", ansi=true)
        tb2 = T.TestBackend(20, 3)
        T.render_widget!(tb2, p2)
        @test T.style_at(tb2, 1, 1).fg == T.Color256(1)  # red

        # Restore default
        T.set_ansi_enabled!(true)
    end
