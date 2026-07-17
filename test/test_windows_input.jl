# Windows console-input backend: the INPUT_RECORD → event translation is pure byte
# parsing (no Win32 calls), so it's testable on every platform. Byte layout mirrors
# CONSOLE_SCREEN_BUFFER_INFO / KEY_EVENT_RECORD / MOUSE_EVENT_RECORD as validated
# against real records captured on Windows.

# Build a 20-byte INPUT_RECORD (little-endian), matching windows_input.jl's field offsets.
function _mkrec(etype; X = 0, Y = 0, btn = 0, cks = 0, flags = 0, down = 0, vk = 0, ch = 0)
    b = zeros(UInt8, 20)
    put16(i, v) = (b[i] = v & 0xff; b[i+1] = (v >> 8) & 0xff)
    put32(i, v) = (b[i] = v & 0xff; b[i+1] = (v >> 8) & 0xff; b[i+2] = (v >> 16) & 0xff; b[i+3] = (v >> 24) & 0xff)
    put16(1, etype)
    if etype == 2   # MOUSE_EVENT
        put16(5, reinterpret(UInt16, Int16(X))); put16(7, reinterpret(UInt16, Int16(Y)))
        put32(9, btn); put32(13, cks); put32(17, flags)
    else            # KEY_EVENT
        put32(5, down); put16(11, vk); put16(15, ch); put32(17, cks)
    end
    return b
end

@testset "windows console input" begin
    @testset "mouse: press / release / move / drag" begin
        T._WIN_MOUSE_BTN[] = 0
        e = T._win_translate_mouse(_mkrec(2; X = 40, Y = 19, btn = 0x1, flags = 0))
        @test e == T.MouseEvent(41, 20, T.mouse_left, T.mouse_press, false, false, false)   # 0-based → 1-based
        e = T._win_translate_mouse(_mkrec(2; X = 40, Y = 19, btn = 0x0, flags = 0))
        @test e.action == T.mouse_release && e.button == T.mouse_left
        e = T._win_translate_mouse(_mkrec(2; X = 5, Y = 6, btn = 0x0, flags = 0x1))
        @test e == T.MouseEvent(6, 7, T.mouse_none, T.mouse_move, false, false, false)
        T._WIN_MOUSE_BTN[] = 0x1
        e = T._win_translate_mouse(_mkrec(2; X = 7, Y = 8, btn = 0x1, flags = 0x1))
        @test e.action == T.mouse_drag && e.button == T.mouse_left
    end

    @testset "mouse: right / middle buttons" begin
        T._WIN_MOUSE_BTN[] = 0
        @test T._win_translate_mouse(_mkrec(2; btn = 0x2, flags = 0)).button == T.mouse_right
        T._WIN_MOUSE_BTN[] = 0
        @test T._win_translate_mouse(_mkrec(2; btn = 0x4, flags = 0)).button == T.mouse_middle
    end

    @testset "mouse: wheel" begin
        up = T._win_translate_mouse(_mkrec(2; btn = (UInt32(120) << 16), flags = 0x4))
        @test up.button == T.mouse_scroll_up && up.action == T.mouse_press
        down = T._win_translate_mouse(_mkrec(2; btn = reinterpret(UInt32, Int32(-120 << 16)), flags = 0x4))
        @test down.button == T.mouse_scroll_down
        right = T._win_translate_mouse(_mkrec(2; btn = (UInt32(120) << 16), flags = 0x8))
        @test right.button == T.mouse_scroll_right
        left = T._win_translate_mouse(_mkrec(2; btn = reinterpret(UInt32, Int32(-120 << 16)), flags = 0x8))
        @test left.button == T.mouse_scroll_left
    end

    @testset "mouse: modifier keys" begin
        T._WIN_MOUSE_BTN[] = 0
        # SHIFT_PRESSED=0x10, LEFT_CTRL=0x08, LEFT_ALT=0x02
        e = T._win_translate_mouse(_mkrec(2; btn = 0x1, flags = 0, cks = 0x10 | 0x08 | 0x02))
        @test e.shift && e.ctrl && e.alt
    end

    @testset "mouse: redundant no-transition record is skipped" begin
        T._WIN_MOUSE_BTN[] = 0
        @test T._win_translate_mouse(_mkrec(2; btn = 0x0, flags = 0)) === nothing
    end

    @testset "key: characters and specials" begin
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x41, ch = UInt16('a'))) == T.KeyEvent('a')
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x0D)).key == :enter
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x08)).key == :backspace
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x1B)).key == :escape
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x25)).key == :left
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x26)).key == :up
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x27)).key == :right
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x28)).key == :down
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x24)).key == :home
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x23)).key == :end
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x2E)).key == :delete
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x74)).key == :f5
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x7B)).key == :f12
    end

    @testset "key: tab / shift-tab" begin
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x09)).key == :tab
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x09, cks = 0x10)).key == :backtab
    end

    @testset "key: control combinations" begin
        # ctrl reports a control char in uChar: ctrl+c → 0x03, ctrl+a → 0x01
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x43, ch = 0x03, cks = 0x08)).key == :ctrl_c
        e = T._win_translate_key(_mkrec(1; down = 1, vk = 0x41, ch = 0x01, cks = 0x08))
        @test e.key == :ctrl && e.char == 'a'
    end

    @testset "key: ignored records" begin
        @test T._win_translate_key(_mkrec(1; down = 0, vk = 0x41, ch = UInt16('a'))) === nothing  # key-up
        @test T._win_translate_key(_mkrec(1; down = 1, vk = 0x10, ch = 0)) === nothing             # modifier-only
    end
end
