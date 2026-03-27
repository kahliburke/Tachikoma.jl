# ── Test helper ──────────────────────────────────────────────────────

"""Mock TerminalWidget-like struct for testing VT parser without a real PTY."""
mutable struct _MockTermWidget
    screen::T.TermScreen
    vt_state::T._VTState
    vt_params::Vector{UInt8}
    vt_osc_buf::Vector{UInt8}
    vt_prev_char::Char
    vt_utf8_carry::Vector{UInt8}
    title_callback::Union{Function, Nothing}
end

function _make_test_tw(screen::T.TermScreen; title_callback=nothing)
    _MockTermWidget(screen, T._vt_ground, UInt8[], UInt8[], ' ', UInt8[], title_callback)
end

@testset "Terminal Widget" begin

    # ── TermScreen basics ────────────────────────────────────────────

    @testset "TermScreen construction" begin
        s = T.TermScreen(24, 80)
        @test s.rows == 24
        @test s.cols == 80
        @test s.cursor_row == 1
        @test s.cursor_col == 1
        @test s.cursor_visible == true
        @test s.current_style == T.RESET
        @test s.scroll_top == 1
        @test s.scroll_bottom == 24
        @test isempty(s.scrollback)
    end

    # ── VT Parser: printable characters ──────────────────────────────

    @testset "VT parser: ASCII text" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("Hello"))
        @test s.cells[1, 1].char == 'H'
        @test s.cells[1, 2].char == 'e'
        @test s.cells[1, 3].char == 'l'
        @test s.cells[1, 4].char == 'l'
        @test s.cells[1, 5].char == 'o'
        @test s.cursor_col == 6
        @test s.cursor_row == 1
    end

    @testset "VT parser: CR and LF" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("AB\r\nCD"))
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 2].char == 'B'
        @test s.cells[2, 1].char == 'C'
        @test s.cells[2, 2].char == 'D'
    end

    @testset "VT parser: backspace" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("AB\x08X"))
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 2].char == 'X'
    end

    @testset "VT parser: tab" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("A\tB"))
        @test s.cells[1, 1].char == 'A'
        @test s.cursor_col == 10  # after B at col 9
        @test s.cells[1, 9].char == 'B'
    end

    # ── VT Parser: CSI cursor movement ───────────────────────────────

    @testset "VT parser: CUP (cursor position)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[5;10H"))
        @test s.cursor_row == 5
        @test s.cursor_col == 10
    end

    @testset "VT parser: CUU/CUD/CUF/CUB" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[10;10H"))
        T._vt_feed!(tw, Vector{UInt8}("\e[3A"))  # up 3
        @test s.cursor_row == 7
        T._vt_feed!(tw, Vector{UInt8}("\e[2B"))  # down 2
        @test s.cursor_row == 9
        T._vt_feed!(tw, Vector{UInt8}("\e[5C"))  # forward 5
        @test s.cursor_col == 15
        T._vt_feed!(tw, Vector{UInt8}("\e[3D"))  # back 3
        @test s.cursor_col == 12
    end

    @testset "VT parser: CHA (cursor horizontal absolute)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[5;20H\e[10G"))
        @test s.cursor_col == 10
        @test s.cursor_row == 5
    end

    # ── VT Parser: erase ─────────────────────────────────────────────

    @testset "VT parser: erase line (EL)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("ABCDEFGH"))
        T._vt_feed!(tw, Vector{UInt8}("\e[5G"))  # cursor to col 5
        T._vt_feed!(tw, Vector{UInt8}("\e[0K"))   # erase cursor to end
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 4].char == 'D'
        @test s.cells[1, 5].char == ' '
        @test s.cells[1, 8].char == ' '
    end

    @testset "VT parser: erase display (ED)" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        # Fill with text
        for r in 1:5
            T._vt_feed!(tw, Vector{UInt8}("\e[$(r);1H"))
            T._vt_feed!(tw, Vector{UInt8}("LINE$(r)"))
        end
        # Erase all
        T._vt_feed!(tw, Vector{UInt8}("\e[2J"))
        for r in 1:5, c in 1:10
            @test s.cells[r, c].char == ' '
        end
    end

    # ── VT Parser: SGR (colors and attributes) ──────────────────────

    @testset "VT parser: SGR bold + color" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;31mX"))
        @test s.cells[1, 1].char == 'X'
        @test s.cells[1, 1].style.bold == true
        @test s.cells[1, 1].style.fg == T.Color256(1)  # red
    end

    @testset "VT parser: SGR 256-color" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[38;5;196mR"))
        @test s.cells[1, 1].style.fg == T.Color256(196)
    end

    @testset "VT parser: SGR RGB color" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[38;2;100;200;50mG"))
        @test s.cells[1, 1].style.fg == T.ColorRGB(100, 200, 50)
    end

    @testset "VT parser: SGR reset" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;31mA\e[0mB"))
        @test s.cells[1, 1].style.bold == true
        @test s.cells[1, 2].style.bold == false
        @test s.cells[1, 2].style.fg isa T.NoColor
    end

    @testset "VT parser: SGR dim, italic, underline" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[2;3;4mX"))
        @test s.cells[1, 1].style.dim == true
        @test s.cells[1, 1].style.italic == true
        @test s.cells[1, 1].style.underline == true
    end

    @testset "VT parser: SGR background colors" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[42mX"))  # green bg
        @test s.cells[1, 1].style.bg == T.Color256(2)
        T._vt_feed!(tw, Vector{UInt8}("\e[48;5;220mY"))  # 256-color bg
        @test s.cells[1, 2].style.bg == T.Color256(220)
        T._vt_feed!(tw, Vector{UInt8}("\e[48;2;10;20;30mZ"))  # RGB bg
        @test s.cells[1, 3].style.bg == T.ColorRGB(10, 20, 30)
    end

    @testset "VT parser: SGR bright colors" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[91mA"))  # bright red fg
        @test s.cells[1, 1].style.fg == T.Color256(9)
        T._vt_feed!(tw, Vector{UInt8}("\e[102mB"))  # bright green bg
        @test s.cells[1, 2].style.bg == T.Color256(10)
    end

    # ── VT Parser: scrolling ─────────────────────────────────────────

    @testset "VT parser: scroll up on LF at bottom" begin
        s = T.TermScreen(3, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("L1\r\nL2\r\nL3\r\nL4"))
        # L1 should have scrolled into scrollback
        @test length(s.scrollback) == 1
        @test s.scrollback[1][1].char == 'L'
        @test s.scrollback[1][2].char == '1'
        # Screen should have L2, L3, L4
        @test s.cells[1, 1].char == 'L'
        @test s.cells[1, 2].char == '2'
        @test s.cells[2, 1].char == 'L'
        @test s.cells[2, 2].char == '3'
        @test s.cells[3, 1].char == 'L'
        @test s.cells[3, 2].char == '4'
    end

    @testset "VT parser: DECSTBM scroll region" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[2;4r"))  # set scroll region rows 2-4
        @test s.scroll_top == 2
        @test s.scroll_bottom == 4
    end

    # ── VT Parser: cursor save/restore ───────────────────────────────

    @testset "VT parser: ESC 7/8 save/restore cursor" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[5;10H"))
        T._vt_feed!(tw, Vector{UInt8}("\e7"))  # save
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1H"))
        @test s.cursor_row == 1
        T._vt_feed!(tw, Vector{UInt8}("\e8"))  # restore
        @test s.cursor_row == 5
        @test s.cursor_col == 10
    end

    @testset "VT parser: CSI s/u save/restore cursor" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[5;10H\e[s"))
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1H\e[u"))
        @test s.cursor_row == 5
        @test s.cursor_col == 10
    end

    # ── VT Parser: reverse index ─────────────────────────────────────

    @testset "VT parser: ESC M reverse index" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1H"))
        T._vt_feed!(tw, Vector{UInt8}("TOP"))
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1H\eM"))  # reverse index at top → scroll down
        @test s.cells[1, 1].char == ' '  # new blank line
        @test s.cells[2, 1].char == 'T'  # old content shifted down
    end

    # ── VT Parser: insert/delete lines and chars ─────────────────────

    @testset "VT parser: insert lines (CSI L)" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1HA\e[2;1HB\e[3;1HC"))
        T._vt_feed!(tw, Vector{UInt8}("\e[2;1H\e[1L"))  # insert 1 line at row 2
        @test s.cells[1, 1].char == 'A'
        @test s.cells[2, 1].char == ' '  # inserted blank
        @test s.cells[3, 1].char == 'B'  # shifted down
    end

    @testset "VT parser: delete chars (CSI P)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("ABCDE"))
        T._vt_feed!(tw, Vector{UInt8}("\e[2G\e[2P"))  # delete 2 chars at col 2
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 2].char == 'D'
        @test s.cells[1, 3].char == 'E'
    end

    @testset "VT parser: insert chars (CSI @)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("ABCDE"))
        T._vt_feed!(tw, Vector{UInt8}("\e[3G\e[2@"))  # insert 2 blanks at col 3
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 2].char == 'B'
        @test s.cells[1, 3].char == ' '  # inserted
        @test s.cells[1, 4].char == ' '  # inserted
        @test s.cells[1, 5].char == 'C'  # shifted right
    end

    # ── VT Parser: DECSET/DECRST ─────────────────────────────────────

    @testset "VT parser: cursor visibility" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        @test s.cursor_visible == true
        T._vt_feed!(tw, Vector{UInt8}("\e[?25l"))  # hide
        @test s.cursor_visible == false
        T._vt_feed!(tw, Vector{UInt8}("\e[?25h"))  # show
        @test s.cursor_visible == true
    end

    # ── VT Parser: line wrapping ─────────────────────────────────────

    @testset "VT parser: autowrap" begin
        s = T.TermScreen(3, 5)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("12345X"))
        @test s.cells[1, 5].char == '5'
        @test s.cells[2, 1].char == 'X'
        @test s.cursor_row == 2
    end

    # ── VT Parser: UTF-8 ────────────────────────────────────────────

    @testset "VT parser: UTF-8 multibyte" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}(codeunits("café")))
        @test s.cells[1, 1].char == 'c'
        @test s.cells[1, 2].char == 'a'
        @test s.cells[1, 3].char == 'f'
        @test s.cells[1, 4].char == 'é'
    end

    @testset "VT parser: zero-width combining marks" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}(codeunits("n\u0307x")))
        @test s.cells[1, 1].char == 'n'
        @test s.cells[1, 1].suffix == "\u0307"
        @test s.cells[1, 2].char == 'x'
        @test s.cursor_col == 3
    end

    @testset "VT parser: precomposed glyph" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}(codeunits("ṅx")))
        @test s.cells[1, 1].char == 'ṅ'
        @test isempty(s.cells[1, 1].suffix)
        @test s.cells[1, 2].char == 'x'
        @test s.cursor_col == 3
    end

    @testset "VT parser: overwrite wide-char pad clears lead" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}(codeunits("你")))
        T._vt_feed!(tw, UInt8[0x08])  # move to pad column
        T._vt_feed!(tw, Vector{UInt8}(codeunits("X")))
        @test s.cells[1, 1].char == ' '
        @test s.cells[1, 2].char == 'X'
    end

    @testset "VT parser: overwrite wide-char lead clears pad" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}(codeunits("你")))
        T._vt_feed!(tw, Vector{UInt8}("\e[1G"))  # move to lead column
        T._vt_feed!(tw, Vector{UInt8}(codeunits("Y")))
        @test s.cells[1, 1].char == 'Y'
        @test s.cells[1, 2].char == ' '
    end

    # ── VT Parser: OSC title ─────────────────────────────────────────

    @testset "VT parser: OSC window title" begin
        s = T.TermScreen(24, 80)
        captured_title = Ref("")
        tw = _make_test_tw(s; title_callback = t -> (captured_title[] = t))
        T._vt_feed!(tw, Vector{UInt8}("\e]0;My Title\x07"))
        @test captured_title[] == "My Title"
    end

    @testset "VT parser: OSC with ST terminator" begin
        s = T.TermScreen(24, 80)
        captured_title = Ref("")
        tw = _make_test_tw(s; title_callback = t -> (captured_title[] = t))
        T._vt_feed!(tw, Vector{UInt8}("\e]2;Other Title\e\\"))
        @test captured_title[] == "Other Title"
    end

    # ── VT Parser: full reset ────────────────────────────────────────

    @testset "VT parser: ESC c full reset" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;31m\e[3;5HX"))
        T._vt_feed!(tw, Vector{UInt8}("\ec"))  # full reset
        @test s.cursor_row == 1
        @test s.cursor_col == 1
        @test s.current_style == T.RESET
        @test s.cells[3, 5].char == ' '  # cleared
    end

    # ── VT Parser: erase chars (CSI X) ───────────────────────────────

    @testset "VT parser: erase chars (CSI X)" begin
        s = T.TermScreen(24, 80)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("ABCDE"))
        T._vt_feed!(tw, Vector{UInt8}("\e[2G\e[3X"))  # erase 3 at col 2
        @test s.cells[1, 1].char == 'A'
        @test s.cells[1, 2].char == ' '
        @test s.cells[1, 3].char == ' '
        @test s.cells[1, 4].char == ' '
        @test s.cells[1, 5].char == 'E'
    end

    # ── VT Parser: scroll commands ───────────────────────────────────

    @testset "VT parser: CSI S (scroll up) and CSI T (scroll down)" begin
        s = T.TermScreen(3, 5)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;1HA\e[2;1HB\e[3;1HC"))
        T._vt_feed!(tw, Vector{UInt8}("\e[1S"))  # scroll up 1
        @test s.cells[1, 1].char == 'B'
        @test s.cells[2, 1].char == 'C'
        @test s.cells[3, 1].char == ' '
        @test length(s.scrollback) == 1
    end

    # ── Screen resize ────────────────────────────────────────────────

    @testset "TermScreen resize" begin
        s = T.TermScreen(5, 10)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("HELLO"))
        T._screen_resize!(s, 3, 8)
        @test s.rows == 3
        @test s.cols == 8
        @test s.cells[1, 1].char == 'H'
        @test s.cells[1, 5].char == 'O'
    end

    @testset "TermScreen resize clamps cursor" begin
        s = T.TermScreen(10, 20)
        T._screen_move_cursor!(s, 8, 15)
        T._screen_resize!(s, 5, 10)
        @test s.cursor_row == 5
        @test s.cursor_col == 10
    end

    # ── Input Encoding ───────────────────────────────────────────────

    @testset "Input encoding: basic keys" begin
        @test T._encode_key(T.KeyEvent(:enter, '\0', T.key_press)) == UInt8[0x0d]
        @test T._encode_key(T.KeyEvent(:backspace, '\0', T.key_press)) == UInt8[0x7f]
        @test T._encode_key(T.KeyEvent(:tab, '\0', T.key_press)) == UInt8[0x09]
        @test T._encode_key(T.KeyEvent(:escape, '\0', T.key_press)) == UInt8[0x1b]
    end

    @testset "Input encoding: arrow keys" begin
        @test T._encode_key(T.KeyEvent(:up, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[A"))
        @test T._encode_key(T.KeyEvent(:down, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[B"))
        @test T._encode_key(T.KeyEvent(:right, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[C"))
        @test T._encode_key(T.KeyEvent(:left, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[D"))
    end

    @testset "Input encoding: printable chars" begin
        @test T._encode_key(T.KeyEvent(:char, 'a', T.key_press)) == Vector{UInt8}(codeunits("a"))
        @test T._encode_key(T.KeyEvent(:char, 'Z', T.key_press)) == Vector{UInt8}(codeunits("Z"))
        @test T._encode_key(T.KeyEvent(:char, '5', T.key_press)) == Vector{UInt8}(codeunits("5"))
    end

    @testset "Input encoding: ctrl keys" begin
        @test T._encode_key(T.KeyEvent(:ctrl, 'c', T.key_press)) == UInt8[0x03]
        @test T._encode_key(T.KeyEvent(:ctrl, 'd', T.key_press)) == UInt8[0x04]
        @test T._encode_key(T.KeyEvent(:ctrl, 'a', T.key_press)) == UInt8[0x01]
        @test T._encode_key(T.KeyEvent(:ctrl, 'z', T.key_press)) == UInt8[0x1a]
        @test T._encode_key(T.KeyEvent(:ctrl_c, '\0', T.key_press)) == UInt8[0x03]
    end

    @testset "Input encoding: function keys" begin
        @test T._encode_key(T.KeyEvent(:f1, '\0', T.key_press)) == Vector{UInt8}(codeunits("\eOP"))
        @test T._encode_key(T.KeyEvent(:f5, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[15~"))
        @test T._encode_key(T.KeyEvent(:f12, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[24~"))
    end

    @testset "Input encoding: navigation keys" begin
        @test T._encode_key(T.KeyEvent(:home, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[H"))
        @test T._encode_key(T.KeyEvent(:end_key, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[F"))
        @test T._encode_key(T.KeyEvent(:pageup, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[5~"))
        @test T._encode_key(T.KeyEvent(:pagedown, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[6~"))
        @test T._encode_key(T.KeyEvent(:delete, '\0', T.key_press)) == Vector{UInt8}(codeunits("\e[3~"))
    end

    # ── Scrollback ───────────────────────────────────────────────────

    @testset "Scrollback limit" begin
        s = T.TermScreen(3, 10; scrollback_limit=5)
        tw = _make_test_tw(s)
        for i in 1:10
            T._vt_feed!(tw, Vector{UInt8}("Line$i\r\n"))
        end
        @test length(s.scrollback) <= 5
    end

    # ── Widget render (screen → buffer) ──────────────────────────────

    @testset "Screen to buffer rendering" begin
        s = T.TermScreen(3, 5)
        tw = _make_test_tw(s)
        T._vt_feed!(tw, Vector{UInt8}("\e[1;31mHi"))

        buf = T.Buffer(T.Rect(1, 1, 10, 5))
        for row in 1:s.rows
            for col in 1:s.cols
                T.set!(buf, col, row, s.cells[row, col])
            end
        end
        c = buf.content[T.buf_index(buf, 1, 1)]
        @test c.char == 'H'
        @test c.style.fg == T.Color256(1)
        @test buf.content[T.buf_index(buf, 2, 1)].char == 'i'
    end

end
