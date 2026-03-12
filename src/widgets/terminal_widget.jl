# ═══════════════════════════════════════════════════════════════════════
# TerminalWidget ── embedded terminal emulator widget
#
# Spawns a subprocess in a PTY, parses its ANSI output into a screen
# buffer, and renders it as a Tachikoma widget. Keyboard input is
# forwarded back to the subprocess as ANSI escape sequences.
# ═══════════════════════════════════════════════════════════════════════

# ── VT Parser States ─────────────────────────────────────────────────

@enum _VTState _vt_ground _vt_escape _vt_csi _vt_osc _vt_charset

# ── Terminal Screen Buffer ───────────────────────────────────────────

mutable struct TermScreen
    cells::Matrix{Cell}       # (rows, cols) grid
    rows::Int
    cols::Int
    cursor_row::Int           # 1-based
    cursor_col::Int           # 1-based
    cursor_visible::Bool
    current_style::Style      # SGR state applied to next character
    scroll_top::Int           # 1-based, inclusive
    scroll_bottom::Int        # 1-based, inclusive
    scrollback::Vector{Vector{Cell}}
    scrollback_limit::Int
    autowrap::Bool            # wrap at right margin
    origin_mode::Bool         # cursor relative to scroll region
    onlcr::Bool               # LF implies CR (for in-process REPLs where OPOST is off)
    # Saved cursor (ESC 7 / ESC 8)
    saved_cursor_row::Int
    saved_cursor_col::Int
    saved_style::Style
    # Alternate screen buffer (DECSET 1049 / 47 / 1047)
    alt_active::Bool
    saved_cells::Union{Matrix{Cell}, Nothing}
    saved_main_cursor_row::Int
    saved_main_cursor_col::Int
    saved_main_style::Style
    saved_scrollback::Union{Vector{Vector{Cell}}, Nothing}
    # Mouse reporting modes (DECSET 1000/1002/1006)
    mouse_reporting::Bool
    mouse_sgr::Bool
    # Cursor key mode (DECSET 1) and bracketed paste (DECSET 2004)
    cursor_key_mode::Bool     # true = application mode (ESC O A), false = normal (ESC [ A)
    bracketed_paste::Bool     # true = DECSET 2004 enabled
    focus_events::Bool        # true = DECSET 1004 enabled
end

function TermScreen(rows::Int, cols::Int; scrollback_limit::Int=1000, onlcr::Bool=false)
    cells = fill(Cell(), rows, cols)
    TermScreen(cells, rows, cols, 1, 1, true,
               RESET, 1, rows,
               Vector{Cell}[], scrollback_limit,
               true, false, onlcr,
               1, 1, RESET,
               # alternate screen buffer
               false, nothing, 1, 1, RESET, nothing,
               # mouse reporting
               false, false,
               # cursor key mode, bracketed paste, focus events
               false, false, false)
end

# ── Screen Buffer Operations ────────────────────────────────────────

function _screen_scroll_up!(s::TermScreen, n::Int=1)
    for _ in 1:n
        # Save top line to scrollback (skip in alternate buffer — standard behavior)
        if s.scroll_top == 1 && !s.alt_active
            line = s.cells[1, :]
            push!(s.scrollback, line)
            while length(s.scrollback) > s.scrollback_limit
                popfirst!(s.scrollback)
            end
        end
        # Shift lines up within scroll region
        for row in s.scroll_top:(s.scroll_bottom - 1)
            for col in 1:s.cols
                s.cells[row, col] = s.cells[row + 1, col]
            end
        end
        # Clear bottom line of scroll region
        for col in 1:s.cols
            s.cells[s.scroll_bottom, col] = Cell()
        end
    end
end

function _screen_scroll_down!(s::TermScreen, n::Int=1)
    for _ in 1:n
        for row in s.scroll_bottom:-1:(s.scroll_top + 1)
            for col in 1:s.cols
                s.cells[row, col] = s.cells[row - 1, col]
            end
        end
        for col in 1:s.cols
            s.cells[s.scroll_top, col] = Cell()
        end
    end
end

function _screen_putchar!(s::TermScreen, ch::Char)
    w = textwidth(ch)
    w <= 0 && return  # ignore zero-width chars

    # Handle autowrap: if cursor is past the right margin
    if s.cursor_col > s.cols
        if s.autowrap
            s.cursor_col = 1
            if s.cursor_row == s.scroll_bottom
                _screen_scroll_up!(s)
            elseif s.cursor_row < s.rows
                s.cursor_row += 1
            end
        else
            s.cursor_col = s.cols
        end
    end

    # Write character at cursor
    if s.cursor_row >= 1 && s.cursor_row <= s.rows &&
       s.cursor_col >= 1 && s.cursor_col <= s.cols
        s.cells[s.cursor_row, s.cursor_col] = Cell(ch, s.current_style)
        # Wide char: place pad in next column
        if w == 2 && s.cursor_col < s.cols
            s.cells[s.cursor_row, s.cursor_col + 1] = Cell(WIDE_CHAR_PAD, s.current_style)
        end
    end

    s.cursor_col += w
end

function _screen_erase_line!(s::TermScreen, mode::Int)
    row = s.cursor_row
    (row < 1 || row > s.rows) && return
    if mode == 0       # cursor to end
        for col in s.cursor_col:s.cols
            s.cells[row, col] = Cell()
        end
    elseif mode == 1   # start to cursor
        for col in 1:s.cursor_col
            s.cells[row, col] = Cell()
        end
    elseif mode == 2   # whole line
        for col in 1:s.cols
            s.cells[row, col] = Cell()
        end
    end
end

function _screen_erase_display!(s::TermScreen, mode::Int)
    if mode == 0       # cursor to end
        _screen_erase_line!(s, 0)
        for row in (s.cursor_row + 1):s.rows
            for col in 1:s.cols
                s.cells[row, col] = Cell()
            end
        end
    elseif mode == 1   # start to cursor
        for row in 1:(s.cursor_row - 1)
            for col in 1:s.cols
                s.cells[row, col] = Cell()
            end
        end
        _screen_erase_line!(s, 1)
    elseif mode == 2 || mode == 3   # all (3 also clears scrollback)
        for row in 1:s.rows
            for col in 1:s.cols
                s.cells[row, col] = Cell()
            end
        end
        mode == 3 && empty!(s.scrollback)
    end
end

function _screen_erase_chars!(s::TermScreen, n::Int)
    row = s.cursor_row
    (row < 1 || row > s.rows) && return
    for col in s.cursor_col:min(s.cursor_col + n - 1, s.cols)
        s.cells[row, col] = Cell()
    end
end

function _screen_insert_lines!(s::TermScreen, n::Int)
    for _ in 1:n
        if s.cursor_row >= s.scroll_top && s.cursor_row <= s.scroll_bottom
            for row in s.scroll_bottom:-1:(s.cursor_row + 1)
                for col in 1:s.cols
                    s.cells[row, col] = s.cells[row - 1, col]
                end
            end
            for col in 1:s.cols
                s.cells[s.cursor_row, col] = Cell()
            end
        end
    end
end

function _screen_delete_lines!(s::TermScreen, n::Int)
    for _ in 1:n
        if s.cursor_row >= s.scroll_top && s.cursor_row <= s.scroll_bottom
            for row in s.cursor_row:(s.scroll_bottom - 1)
                for col in 1:s.cols
                    s.cells[row, col] = s.cells[row + 1, col]
                end
            end
            for col in 1:s.cols
                s.cells[s.scroll_bottom, col] = Cell()
            end
        end
    end
end

function _screen_insert_chars!(s::TermScreen, n::Int)
    row = s.cursor_row
    (row < 1 || row > s.rows) && return
    for col in s.cols:-1:(s.cursor_col + n)
        s.cells[row, col] = s.cells[row, col - n]
    end
    for col in s.cursor_col:min(s.cursor_col + n - 1, s.cols)
        s.cells[row, col] = Cell()
    end
end

function _screen_delete_chars!(s::TermScreen, n::Int)
    row = s.cursor_row
    (row < 1 || row > s.rows) && return
    for col in s.cursor_col:(s.cols - n)
        s.cells[row, col] = s.cells[row, col + n]
    end
    for col in max(s.cursor_col, s.cols - n + 1):s.cols
        s.cells[row, col] = Cell()
    end
end

function _screen_move_cursor!(s::TermScreen, row::Int, col::Int)
    s.cursor_row = clamp(row, 1, s.rows)
    s.cursor_col = clamp(col, 1, s.cols)
end

function _screen_resize!(s::TermScreen, rows::Int, cols::Int)
    rows < 1 && (rows = 1)
    cols < 1 && (cols = 1)
    (rows == s.rows && cols == s.cols) && return

    new_cells = fill(Cell(), rows, cols)
    # Copy existing content
    for row in 1:min(rows, s.rows)
        for col in 1:min(cols, s.cols)
            new_cells[row, col] = s.cells[row, col]
        end
    end
    s.cells = new_cells
    s.rows = rows
    s.cols = cols
    s.cursor_row = clamp(s.cursor_row, 1, rows)
    s.cursor_col = clamp(s.cursor_col, 1, cols)
    s.scroll_top = 1
    s.scroll_bottom = rows
end

# ── Alternate Screen Buffer ─────────────────────────────────────────

function _enter_alt_screen!(s::TermScreen, save_cursor::Bool)
    s.alt_active && return  # already in alt screen
    # Save main buffer state
    s.saved_cells = copy(s.cells)
    s.saved_scrollback = copy(s.scrollback)
    if save_cursor  # mode 1049 saves cursor
        s.saved_main_cursor_row = s.cursor_row
        s.saved_main_cursor_col = s.cursor_col
        s.saved_main_style = s.current_style
    end
    # Switch to alt buffer: clear screen, no scrollback
    s.alt_active = true
    for row in 1:s.rows, col in 1:s.cols
        s.cells[row, col] = Cell()
    end
    s.cursor_row = 1
    s.cursor_col = 1
    s.scroll_top = 1
    s.scroll_bottom = s.rows
end

function _leave_alt_screen!(s::TermScreen, restore_cursor::Bool)
    s.alt_active || return  # not in alt screen
    s.alt_active = false
    # Restore main buffer
    if s.saved_cells !== nothing
        s.cells = s.saved_cells
        s.saved_cells = nothing
    end
    if s.saved_scrollback !== nothing
        s.scrollback = s.saved_scrollback
        s.saved_scrollback = nothing
    end
    if restore_cursor  # mode 1049 restores cursor
        s.cursor_row = s.saved_main_cursor_row
        s.cursor_col = s.saved_main_cursor_col
        s.current_style = s.saved_main_style
    end
    s.scroll_top = 1
    s.scroll_bottom = s.rows
end

# ── SGR Parser ───────────────────────────────────────────────────────

function _parse_sgr!(s::TermScreen, params::Vector{Int})
    isempty(params) && (s.current_style = RESET; return)
    i = 1
    st = s.current_style
    fg = st.fg
    bg = st.bg
    bold = st.bold
    dim = st.dim
    italic = st.italic
    underline = st.underline
    strikethrough = st.strikethrough
    while i <= length(params)
        p = params[i]
        if p == 0
            fg = NoColor(); bg = NoColor()
            bold = false; dim = false; italic = false; underline = false
            strikethrough = false
        elseif p == 1;  bold = true
        elseif p == 2;  dim = true
        elseif p == 3;  italic = true
        elseif p == 4;  underline = true
        elseif p == 7   # reverse video — swap fg/bg
            fg, bg = bg, fg
        elseif p == 9;  strikethrough = true
        elseif p == 22; bold = false; dim = false
        elseif p == 23; italic = false
        elseif p == 24; underline = false
        elseif p == 27  # reverse off — ignore (would need tracking)
        elseif p == 29; strikethrough = false
        elseif p >= 30 && p <= 37
            fg = Color256(p - 30)
        elseif p == 38  # extended fg
            if i + 1 <= length(params)
                if params[i+1] == 5 && i + 2 <= length(params)
                    fg = Color256(params[i+2])
                    i += 2
                elseif params[i+1] == 2 && i + 4 <= length(params)
                    fg = ColorRGB(UInt8(clamp(params[i+2], 0, 255)),
                                  UInt8(clamp(params[i+3], 0, 255)),
                                  UInt8(clamp(params[i+4], 0, 255)))
                    i += 4
                end
            end
        elseif p == 39; fg = NoColor()
        elseif p >= 40 && p <= 47
            bg = Color256(p - 40)
        elseif p == 48  # extended bg
            if i + 1 <= length(params)
                if params[i+1] == 5 && i + 2 <= length(params)
                    bg = Color256(params[i+2])
                    i += 2
                elseif params[i+1] == 2 && i + 4 <= length(params)
                    bg = ColorRGB(UInt8(clamp(params[i+2], 0, 255)),
                                  UInt8(clamp(params[i+3], 0, 255)),
                                  UInt8(clamp(params[i+4], 0, 255)))
                    i += 4
                end
            end
        elseif p == 49; bg = NoColor()
        elseif p >= 90 && p <= 97
            fg = Color256(p - 90 + 8)
        elseif p >= 100 && p <= 107
            bg = Color256(p - 100 + 8)
        end
        i += 1
    end
    s.current_style = Style(fg=fg, bg=bg, bold=bold, dim=dim,
                            italic=italic, underline=underline,
                            strikethrough=strikethrough)
end

# ── CSI Dispatch ─────────────────────────────────────────────────────

function _parse_csi_params(raw::Vector{UInt8})
    # Check for private mode prefix (?, >, !)
    private = UInt8(0)
    start = 1
    if !isempty(raw) && raw[1] in (UInt8('?'), UInt8('>'), UInt8('!'))
        private = raw[1]
        start = 2
    end
    params = Int[]
    current = 0
    has_digit = false
    for i in start:length(raw)
        b = raw[i]
        if b >= UInt8('0') && b <= UInt8('9')
            current = current * 10 + Int(b - UInt8('0'))
            has_digit = true
        elseif b == UInt8(';')
            push!(params, has_digit ? current : 0)
            current = 0
            has_digit = false
        elseif b == UInt8(':')
            # Colon-separated sub-params (used in some SGR variants) — treat as semicolon
            push!(params, has_digit ? current : 0)
            current = 0
            has_digit = false
        end
    end
    push!(params, has_digit ? current : 0)
    (private, params)
end

function _dispatch_csi!(s::TermScreen, param_buf::Vector{UInt8}, final::UInt8, title_callback)
    private, params = _parse_csi_params(param_buf)
    p1 = isempty(params) ? 0 : params[1]
    p2 = length(params) >= 2 ? params[2] : 0

    if private == UInt8('?')
        # DECSET / DECRST
        if final == UInt8('h')       # set
            for p in params
                p == 1  && (s.cursor_key_mode = true)    # DECCKM
                p == 25 && (s.cursor_visible = true)
                p == 7  && (s.autowrap = true)
                p == 6  && (s.origin_mode = true)
                # Alternate screen buffer
                if p == 1049 || p == 47 || p == 1047
                    _enter_alt_screen!(s, p == 1049)
                end
                # Mouse reporting
                (p == 1000 || p == 1002) && (s.mouse_reporting = true)
                p == 1006 && (s.mouse_sgr = true)
                p == 1004 && (s.focus_events = true)
                p == 2004 && (s.bracketed_paste = true)
            end
        elseif final == UInt8('l')   # reset
            for p in params
                p == 1  && (s.cursor_key_mode = false)   # DECCKM
                p == 25 && (s.cursor_visible = false)
                p == 7  && (s.autowrap = false)
                p == 6  && (s.origin_mode = false)
                # Alternate screen buffer
                if p == 1049 || p == 47 || p == 1047
                    _leave_alt_screen!(s, p == 1049)
                end
                # Mouse reporting
                (p == 1000 || p == 1002) && (s.mouse_reporting = false)
                p == 1006 && (s.mouse_sgr = false)
                p == 1004 && (s.focus_events = false)
                p == 2004 && (s.bracketed_paste = false)
            end
        end
        return
    end

    # '>' private marker — DA2, Kitty key encoding, xterm version query, etc.
    if private == UInt8('>')
        # Silently ignore all '>' sequences (DA2, xterm queries, Kitty protocol)
        # Responding to DA2 can cause echo feedback issues in embedded PTYs
        return
    end

    # '=' private marker — Kitty keyboard protocol (CSI = flags ; mode u) — safely ignore
    if private == UInt8('=')
        return
    end

    n = max(1, p1)  # default to 1 for most movement commands

    if final == UInt8('A')       # CUU — cursor up
        _screen_move_cursor!(s, s.cursor_row - n, s.cursor_col)
    elseif final == UInt8('B')   # CUD — cursor down
        _screen_move_cursor!(s, s.cursor_row + n, s.cursor_col)
    elseif final == UInt8('C')   # CUF — cursor forward
        _screen_move_cursor!(s, s.cursor_row, s.cursor_col + n)
    elseif final == UInt8('D')   # CUB — cursor back
        _screen_move_cursor!(s, s.cursor_row, s.cursor_col - n)
    elseif final == UInt8('H') || final == UInt8('f')  # CUP / HVP
        row = max(1, p1)
        col = max(1, p2)
        _screen_move_cursor!(s, row, col)
    elseif final == UInt8('J')   # ED — erase display
        _screen_erase_display!(s, p1)
    elseif final == UInt8('K')   # EL — erase line
        _screen_erase_line!(s, p1)
    elseif final == UInt8('L')   # IL — insert lines
        _screen_insert_lines!(s, n)
    elseif final == UInt8('M')   # DL — delete lines
        _screen_delete_lines!(s, n)
    elseif final == UInt8('P')   # DCH — delete chars
        _screen_delete_chars!(s, n)
    elseif final == UInt8('@')   # ICH — insert chars
        _screen_insert_chars!(s, n)
    elseif final == UInt8('X')   # ECH — erase chars
        _screen_erase_chars!(s, n)
    elseif final == UInt8('S')   # SU — scroll up
        _screen_scroll_up!(s, n)
    elseif final == UInt8('T')   # SD — scroll down
        _screen_scroll_down!(s, n)
    elseif final == UInt8('G')   # CHA — cursor to column
        _screen_move_cursor!(s, s.cursor_row, n)
    elseif final == UInt8('d')   # VPA — cursor to row
        _screen_move_cursor!(s, n, s.cursor_col)
    elseif final == UInt8('m')   # SGR
        _parse_sgr!(s, params)
    elseif final == UInt8('r')   # DECSTBM — set scroll region
        top = max(1, p1)
        bot = p2 == 0 ? s.rows : min(p2, s.rows)
        if top < bot
            s.scroll_top = top
            s.scroll_bottom = bot
        end
        _screen_move_cursor!(s, 1, 1)
    elseif final == UInt8('s')   # SCP — save cursor
        s.saved_cursor_row = s.cursor_row
        s.saved_cursor_col = s.cursor_col
        s.saved_style = s.current_style
    elseif final == UInt8('u')   # RCP — restore cursor
        s.cursor_row = s.saved_cursor_row
        s.cursor_col = s.saved_cursor_col
        s.current_style = s.saved_style
    elseif final == UInt8('c')   # DA1 — primary device attributes
        # Intentionally no response — writing to PTY stdin corrupts
        # subprocess input parsers (Ink/React-based TUI apps like Claude Code).
        # Apps handle missing DA1 responses via timeout.
    elseif final == UInt8('b')   # REP — repeat previous char
        # Not commonly used, skip for now
    elseif final == UInt8('n')   # DSR — device status report
        # Intentionally no response — same reason as DA1.
        # CPR responses written to stdin are misinterpreted as keyboard
        # input by subprocess TUI frameworks.
    elseif final == UInt8('t')   # window manipulation — ignore
    elseif final == UInt8('h') || final == UInt8('l')
        # SM/RM mode set/reset (non-private) — ignore
    end
end

# ── VT State Machine ────────────────────────────────────────────────

function _vt_feed!(tw, data::AbstractVector{UInt8})
    # Prepend any leftover bytes from a previous chunk boundary
    if !isempty(tw.vt_utf8_carry)
        data = vcat(tw.vt_utf8_carry, data)
        empty!(tw.vt_utf8_carry)
    end
    screen = tw.screen
    i = 1
    while i <= length(data)
        b = data[i]

        if tw.vt_state == _vt_ground
            if b >= 0x20 && b <= 0x7e
                # Printable ASCII
                _screen_putchar!(screen, Char(b))
                tw.vt_prev_char = Char(b)
            elseif b >= 0x80
                # UTF-8 start byte — determine expected sequence length
                if b < 0xc0
                    # Continuation byte without start — skip
                elseif b < 0xe0
                    # 2-byte sequence
                    if i + 1 <= length(data)
                        cp = (UInt32(b & 0x1f) << 6) | UInt32(data[i+1] & 0x3f)
                        ch = Char(cp)
                        _screen_putchar!(screen, ch)
                        tw.vt_prev_char = ch
                        i += 1
                    else
                        # Incomplete — carry remaining bytes to next chunk
                        append!(tw.vt_utf8_carry, @view data[i:end])
                        return
                    end
                elseif b < 0xf0
                    # 3-byte sequence
                    if i + 2 <= length(data)
                        cp = (UInt32(b & 0x0f) << 12) |
                             (UInt32(data[i+1] & 0x3f) << 6) |
                              UInt32(data[i+2] & 0x3f)
                        ch = Char(cp)
                        _screen_putchar!(screen, ch)
                        tw.vt_prev_char = ch
                        i += 2
                    else
                        append!(tw.vt_utf8_carry, @view data[i:end])
                        return
                    end
                else
                    # 4-byte sequence
                    if i + 3 <= length(data)
                        cp = (UInt32(b & 0x07) << 18) |
                             (UInt32(data[i+1] & 0x3f) << 12) |
                             (UInt32(data[i+2] & 0x3f) << 6) |
                              UInt32(data[i+3] & 0x3f)
                        ch = Char(cp)
                        _screen_putchar!(screen, ch)
                        tw.vt_prev_char = ch
                        i += 3
                    else
                        append!(tw.vt_utf8_carry, @view data[i:end])
                        return
                    end
                end
            elseif b == 0x1b  # ESC
                tw.vt_state = _vt_escape
            elseif b == 0x0a || b == 0x0b || b == 0x0c  # LF, VT, FF
                screen.onlcr && (screen.cursor_col = 1)
                if screen.cursor_row == screen.scroll_bottom
                    _screen_scroll_up!(screen)
                elseif screen.cursor_row < screen.rows
                    screen.cursor_row += 1
                end
            elseif b == 0x0d  # CR
                screen.cursor_col = 1
            elseif b == 0x08  # BS
                screen.cursor_col > 1 && (screen.cursor_col -= 1)
            elseif b == 0x09  # HT (tab)
                next_tab = ((screen.cursor_col - 1) ÷ 8 + 1) * 8 + 1
                screen.cursor_col = min(next_tab, screen.cols)
            elseif b == 0x07  # BEL — ignore
            end

        elseif tw.vt_state == _vt_escape
            if b == UInt8('[')
                tw.vt_state = _vt_csi
                empty!(tw.vt_params)
            elseif b == UInt8(']')
                tw.vt_state = _vt_osc
                empty!(tw.vt_osc_buf)
            elseif b == UInt8('7')  # DECSC — save cursor
                screen.saved_cursor_row = screen.cursor_row
                screen.saved_cursor_col = screen.cursor_col
                screen.saved_style = screen.current_style
                tw.vt_state = _vt_ground
            elseif b == UInt8('8')  # DECRC — restore cursor
                screen.cursor_row = screen.saved_cursor_row
                screen.cursor_col = screen.saved_cursor_col
                screen.current_style = screen.saved_style
                tw.vt_state = _vt_ground
            elseif b == UInt8('M')  # RI — reverse index
                if screen.cursor_row == screen.scroll_top
                    _screen_scroll_down!(screen)
                elseif screen.cursor_row > 1
                    screen.cursor_row -= 1
                end
                tw.vt_state = _vt_ground
            elseif b == UInt8('D')  # IND — index (cursor down / scroll)
                if screen.cursor_row == screen.scroll_bottom
                    _screen_scroll_up!(screen)
                elseif screen.cursor_row < screen.rows
                    screen.cursor_row += 1
                end
                tw.vt_state = _vt_ground
            elseif b == UInt8('E')  # NEL — next line
                screen.cursor_col = 1
                if screen.cursor_row == screen.scroll_bottom
                    _screen_scroll_up!(screen)
                elseif screen.cursor_row < screen.rows
                    screen.cursor_row += 1
                end
                tw.vt_state = _vt_ground
            elseif b == UInt8('c')  # RIS — full reset
                _screen_erase_display!(screen, 2)
                _screen_move_cursor!(screen, 1, 1)
                screen.current_style = RESET
                screen.scroll_top = 1
                screen.scroll_bottom = screen.rows
                screen.autowrap = true
                screen.cursor_visible = true
                screen.cursor_key_mode = false
                screen.bracketed_paste = false
                screen.focus_events = false
                screen.origin_mode = false
                tw.vt_state = _vt_ground
            elseif b == UInt8('(') || b == UInt8(')') || b == UInt8('*') || b == UInt8('+')
                # Character set designation — consume next byte and ignore
                tw.vt_state = _vt_charset
            elseif b == UInt8('P') || b == UInt8('_') || b == UInt8('^') || b == UInt8('X')
                # DCS, APC, PM, SOS — consume until ST, use OSC state for simplicity
                tw.vt_state = _vt_osc
                empty!(tw.vt_osc_buf)
            else
                # Unknown ESC sequence — return to ground
                tw.vt_state = _vt_ground
            end

        elseif tw.vt_state == _vt_csi
            if b >= 0x30 && b <= 0x3f
                # Parameter byte (digits, ;, ?, >, !)
                push!(tw.vt_params, b)
            elseif b >= 0x20 && b <= 0x2f
                # Intermediate byte — store with params
                push!(tw.vt_params, b)
            elseif b >= 0x40 && b <= 0x7e
                # Final byte — dispatch
                _dispatch_csi!(screen, tw.vt_params, b, tw.title_callback)
                tw.vt_state = _vt_ground
            else
                # Invalid — abort CSI
                tw.vt_state = _vt_ground
            end

        elseif tw.vt_state == _vt_osc
            if b == 0x07  # BEL — OSC terminator
                _handle_osc!(tw)
                tw.vt_state = _vt_ground
            elseif b == 0x1b
                # Check for ST (ESC \)
                if i + 1 <= length(data) && data[i + 1] == UInt8('\\')
                    _handle_osc!(tw)
                    i += 1
                    tw.vt_state = _vt_ground
                else
                    push!(tw.vt_osc_buf, b)
                end
            else
                push!(tw.vt_osc_buf, b)
            end

        elseif tw.vt_state == _vt_charset
            # Consume the charset designation byte and return to ground
            tw.vt_state = _vt_ground
        end

        i += 1
    end
end

function _handle_osc!(tw)
    isempty(tw.vt_osc_buf) && return
    s = String(copy(tw.vt_osc_buf))
    # OSC 0;title / OSC 1;title / OSC 2;title — set window title
    m = match(r"^[012];(.+)$", s)
    if m !== nothing && tw.title_callback !== nothing
        tw.title_callback(m.captures[1])
        return
    end
    # OSC 8 — hyperlink: "8;params;URL" (params typically empty or "id=...")
    m = match(r"^8;([^;]*);(.*)$", s)
    if m !== nothing
        url = m.captures[2]
        st = tw.screen.current_style
        tw.screen.current_style = Style(fg=st.fg, bg=st.bg, bold=st.bold,
            dim=st.dim, italic=st.italic, underline=st.underline,
            strikethrough=st.strikethrough, hyperlink=url)
    end
end

# ── Input Encoding (KeyEvent → ANSI bytes) ───────────────────────────

function _encode_key(evt::KeyEvent; enter_as_lf::Bool=false,
                     cursor_key_mode::Bool=false)::Vector{UInt8}
    k = evt.key
    k == :enter     && return enter_as_lf ? UInt8[0x0a] : UInt8[0x0d]
    k == :backspace && return UInt8[0x7f]
    k == :tab       && return UInt8[0x09]
    k == :escape    && return UInt8[0x1b]
    # Arrow keys: application mode (DECCKM) sends ESC O x, normal sends ESC [ x
    if cursor_key_mode
        k == :up    && return Vector{UInt8}(codeunits("\eOA"))
        k == :down  && return Vector{UInt8}(codeunits("\eOB"))
        k == :right && return Vector{UInt8}(codeunits("\eOC"))
        k == :left  && return Vector{UInt8}(codeunits("\eOD"))
        k == :home  && return Vector{UInt8}(codeunits("\eOH"))
        k == :end_key && return Vector{UInt8}(codeunits("\eOF"))
    else
        k == :up    && return Vector{UInt8}(codeunits("\e[A"))
        k == :down  && return Vector{UInt8}(codeunits("\e[B"))
        k == :right && return Vector{UInt8}(codeunits("\e[C"))
        k == :left  && return Vector{UInt8}(codeunits("\e[D"))
        k == :home  && return Vector{UInt8}(codeunits("\e[H"))
        k == :end_key && return Vector{UInt8}(codeunits("\e[F"))
    end
    k == :insert    && return Vector{UInt8}(codeunits("\e[2~"))
    k == :delete    && return Vector{UInt8}(codeunits("\e[3~"))
    k == :pageup    && return Vector{UInt8}(codeunits("\e[5~"))
    k == :pagedown  && return Vector{UInt8}(codeunits("\e[6~"))
    k == :backtab   && return Vector{UInt8}(codeunits("\e[Z"))
    k == :f1        && return Vector{UInt8}(codeunits("\eOP"))
    k == :f2        && return Vector{UInt8}(codeunits("\eOQ"))
    k == :f3        && return Vector{UInt8}(codeunits("\eOR"))
    k == :f4        && return Vector{UInt8}(codeunits("\eOS"))
    k == :f5        && return Vector{UInt8}(codeunits("\e[15~"))
    k == :f6        && return Vector{UInt8}(codeunits("\e[17~"))
    k == :f7        && return Vector{UInt8}(codeunits("\e[18~"))
    k == :f8        && return Vector{UInt8}(codeunits("\e[19~"))
    k == :f9        && return Vector{UInt8}(codeunits("\e[20~"))
    k == :f10       && return Vector{UInt8}(codeunits("\e[21~"))
    k == :f11       && return Vector{UInt8}(codeunits("\e[23~"))
    k == :f12       && return Vector{UInt8}(codeunits("\e[24~"))
    k == :ctrl_c    && return UInt8[0x03]
    if k == :ctrl && evt.char != '\0'
        # Ctrl+letter: the events.jl parser maps control bytes via +0x60,
        # so we reverse: byte = lowercase(char) - 0x60
        c = UInt8(lowercase(evt.char))
        c >= 0x61 && c <= 0x7a && return UInt8[c - 0x60]
        # Ctrl+special: try direct mapping
        evt.char == '@' && return UInt8[0x00]
        evt.char == '[' && return UInt8[0x1b]
        evt.char == '{' && return UInt8[0x1b]  # Ctrl+[ via Tachikoma mapping
        evt.char == ']' && return UInt8[0x1d]
        evt.char == '}' && return UInt8[0x1d]  # Ctrl+] via Tachikoma mapping
        evt.char == '\\' && return UInt8[0x1c]
        evt.char == '^' && return UInt8[0x1e]
        evt.char == '_' && return UInt8[0x1f]
        return UInt8[]
    end
    if k == :char
        return Vector{UInt8}(codeunits(string(evt.char)))
    end
    UInt8[]  # unknown key
end

# ── SGR Mouse Encoding ──────────────────────────────────────────────

function _encode_mouse_sgr(evt::MouseEvent, cx::Int, cy::Int)::Vector{UInt8}
    # SGR encoding: \e[<Cb;Cx;CyM (press/drag) or \e[<Cb;Cx;Cym (release)
    # Cb: 0=left, 1=middle, 2=right, 32+btn=drag, 64=scroll-up, 65=scroll-down
    cb = if evt.button == mouse_left;          0
    elseif evt.button == mouse_middle;         1
    elseif evt.button == mouse_right;          2
    elseif evt.button == mouse_none;           35  # move (no button)
    elseif evt.button == mouse_scroll_up;      64
    elseif evt.button == mouse_scroll_down;    65
    elseif evt.button == mouse_scroll_left;    66
    elseif evt.button == mouse_scroll_right;   67
    else;                                      0
    end

    if evt.action == mouse_drag
        cb += 32
    end

    # Modifier bits
    evt.shift && (cb |= 4)
    evt.alt   && (cb |= 8)
    evt.ctrl  && (cb |= 16)

    suffix = evt.action == mouse_release ? 'm' : 'M'
    Vector{UInt8}(codeunits("\e[<$(cb);$(cx);$(cy)$(suffix)"))
end

# ── TerminalWidget ───────────────────────────────────────────────────

"""
    TerminalWidget(cmd; rows=24, cols=80, scrollback_limit=1000)

Embedded terminal emulator widget. Spawns `cmd` in a PTY and renders its
output. Use as standalone or as `content` inside a `FloatingWindow`.

    TerminalWidget()                           # Julia REPL
    TerminalWidget(["/bin/bash"])              # bash shell
    TerminalWidget(["julia", "--banner=no"])   # Julia without banner

Forward events in your `update!`:

    handle_key!(tw, evt)    # keyboard → PTY
    handle_mouse!(tw, evt)  # scroll wheel → scrollback

Render in your `view`:

    render(tw, area, buf)   # drains PTY output + renders screen
"""
mutable struct TerminalWidget
    pty::PTY
    screen::TermScreen
    # VT parser state
    vt_state::_VTState
    vt_params::Vector{UInt8}
    vt_osc_buf::Vector{UInt8}
    vt_prev_char::Char
    vt_utf8_carry::Vector{UInt8}   # partial UTF-8 bytes from chunk boundary
    # Scrollback view
    scroll_offset::Int        # 0 = live view, >0 = scrolled back
    # Widget state
    last_area::Rect
    show_scrollbar::Bool
    focused::Bool
    title_callback::Union{Function, Nothing}
    # Exit lifecycle
    exited::Bool
    on_exit::Union{Function, Nothing}
    # Internal
    _last_cols::Int
    _last_rows::Int
    _sb_state::ScrollbarState
    _wake_fn::Union{Function, Nothing}   # called after data is VT-processed
    enter_as_lf::Bool                    # send LF (not CR) for Enter — for in-process REPLs
end

function TerminalWidget(cmd::Vector{String};
        rows::Int=24, cols::Int=80,
        show_scrollbar::Bool=true,
        focused::Bool=true,
        title_callback::Union{Function, Nothing}=nothing,
        scrollback_limit::Int=1000,
        on_exit::Union{Function, Nothing}=nothing,
        env::Union{Dict{String,String}, Nothing}=nothing)
    pty = pty_spawn(cmd; rows, cols, env)
    screen = TermScreen(rows, cols; scrollback_limit)
    tw = TerminalWidget(pty, screen,
                   _vt_ground, UInt8[], UInt8[], ' ', UInt8[],
                   0,
                   Rect(), show_scrollbar, focused, title_callback,
                   false, on_exit,
                   cols, rows, ScrollbarState(), nothing, false)
    _wire_push_data!(tw)
    tw
end

function TerminalWidget(; on_exit::Union{Function, Nothing}=nothing, kwargs...)
    julia_exe = first(Base.julia_cmd().exec)
    TerminalWidget([julia_exe, "--banner=no"]; on_exit, kwargs...)
end

"""
    TerminalWidget(pty::PTY; ...)

Create a TerminalWidget from a pre-existing PTY (e.g., from `pty_pair`).
Used by `REPLWidget` for in-process REPL rendering.
"""
function TerminalWidget(pty::PTY;
        show_scrollbar::Bool=true,
        focused::Bool=true,
        title_callback::Union{Function, Nothing}=nothing,
        scrollback_limit::Int=1000,
        onlcr::Bool=false,
        enter_as_lf::Bool=false,
        on_exit::Union{Function, Nothing}=nothing)
    screen = TermScreen(pty.rows, pty.cols; scrollback_limit, onlcr)
    tw = TerminalWidget(pty, screen,
                   _vt_ground, UInt8[], UInt8[], ' ', UInt8[],
                   0,
                   Rect(), show_scrollbar, focused, title_callback,
                   false, on_exit,
                   pty.cols, pty.rows, ScrollbarState(), nothing, enter_as_lf)
    _wire_push_data!(tw)
    tw
end

"""
    _wire_push_data!(tw::TerminalWidget)

Set up the PTY `on_data` callback to immediately drain the output channel
into the VT parser. This eliminates the pull-based delay where data sat in
the channel until the next `render()` → `drain!()` cycle.
"""
function _wire_push_data!(tw::TerminalWidget)
    tw.pty.on_data = let tw = tw
        () -> begin
            # Drain all available chunks from the channel right now
            while isready(tw.pty.output)
                data = try take!(tw.pty.output) catch; break end
                _vt_feed!(tw, data)
            end
            # Signal the app loop to render the updated screen
            tw._wake_fn !== nothing && tw._wake_fn()
        end
    end
end

"""
    set_wake!(tw::TerminalWidget, notify::Function)

Store the app-loop wake function. Called by model-level `set_wake!`.
"""
function set_wake!(tw::TerminalWidget, notify::Function)
    tw._wake_fn = notify
end

focusable(::TerminalWidget) = true

"""
    drain!(tw::TerminalWidget) → Bool

Drain any remaining buffered output from the PTY channel and feed it
through the VT parser. Most data is already processed eagerly by the
`on_data` callback; this handles stragglers and process exit detection.
Called automatically by `render`.
"""
function drain!(tw::TerminalWidget)::Bool
    tw.exited && return false
    total = 0
    while isready(tw.pty.output)
        data = try
            take!(tw.pty.output)
        catch
            break  # channel closed
        end
        _vt_feed!(tw, data)
        total += length(data)
    end
    if total == 0 && !tw.pty.alive
        pty_alive(tw.pty)  # update alive status
    end
    # Detect process exit: feed message through VT parser and fire callback
    if !tw.exited && !tw.pty.alive
        tw.exited = true
        _vt_feed!(tw, Vector{UInt8}(codeunits("\r\n\x1b[90m[process exited]\x1b[0m\r\n")))
        tw.on_exit !== nothing && tw.on_exit()
        return true
    end
    total > 0
end

function render(tw::TerminalWidget, rect::Rect, buf::Buffer)
    (rect.width < 1 || rect.height < 1) && return

    text_width = tw.show_scrollbar ? rect.width - 1 : rect.width
    text_height = rect.height

    # Detect resize
    if text_width != tw._last_cols || text_height != tw._last_rows
        tw._last_cols = text_width
        tw._last_rows = text_height
        _screen_resize!(tw.screen, text_height, text_width)
        tw.pty.alive && pty_resize!(tw.pty, text_height, text_width)
    end

    # Drain any remaining buffered data
    drain!(tw)

    tw.last_area = rect
    screen = tw.screen

    if tw.scroll_offset == 0
        # Live view — render screen cells directly
        for row in 1:min(screen.rows, text_height)
            for col in 1:min(screen.cols, text_width)
                cell = screen.cells[row, col]
                set!(buf, rect.x + col - 1, rect.y + row - 1, cell)
            end
        end
        # Draw cursor
        if tw.focused && screen.cursor_visible &&
           screen.cursor_row >= 1 && screen.cursor_row <= text_height &&
           screen.cursor_col >= 1 && screen.cursor_col <= text_width
            cx = rect.x + screen.cursor_col - 1
            cy = rect.y + screen.cursor_row - 1
            existing = screen.cells[screen.cursor_row, screen.cursor_col]
            # Invert colors for cursor block
            cursor_fg = existing.style.bg isa NoColor ? Color256(0) : existing.style.bg
            cursor_bg = existing.style.fg isa NoColor ? Color256(7) : existing.style.fg
            set!(buf, cx, cy, Cell(existing.char, Style(fg=cursor_fg, bg=cursor_bg,
                bold=existing.style.bold, dim=existing.style.dim,
                italic=existing.style.italic, underline=existing.style.underline,
                strikethrough=existing.style.strikethrough)))
        end
    else
        # Scrollback view
        sb = screen.scrollback
        sb_len = length(sb)
        # Total virtual lines: scrollback + screen
        # When scrolled, show lines from scrollback_end - scroll_offset
        first_sb_line = sb_len - tw.scroll_offset + 1
        for display_row in 1:text_height
            source_line = first_sb_line + display_row - 1
            if source_line >= 1 && source_line <= sb_len
                # Scrollback line
                line = sb[source_line]
                for col in 1:min(length(line), text_width)
                    set!(buf, rect.x + col - 1, rect.y + display_row - 1, line[col])
                end
            elseif source_line > sb_len
                # Screen line
                screen_row = source_line - sb_len
                if screen_row >= 1 && screen_row <= screen.rows
                    for col in 1:min(screen.cols, text_width)
                        set!(buf, rect.x + col - 1, rect.y + display_row - 1,
                             screen.cells[screen_row, col])
                    end
                end
            end
        end
    end

    # Scrollbar
    if tw.show_scrollbar && !isempty(screen.scrollback)
        total = length(screen.scrollback) + screen.rows
        sb_rect = Rect(rect.x + text_width, rect.y, 1, rect.height)
        tw._sb_state.rect = sb_rect
        visible_offset = length(screen.scrollback) - tw.scroll_offset
        sb = Scrollbar(total, text_height, max(0, visible_offset))
        render(sb, sb_rect, buf)
    else
        tw._sb_state.rect = Rect()
    end

end

function handle_key!(tw::TerminalWidget, evt::KeyEvent)::Bool
    tw.focused || return false

    # Scrollback navigation
    if tw.scroll_offset > 0
        if evt.key == :pageup
            tw.scroll_offset = min(tw.scroll_offset + tw.last_area.height,
                                    length(tw.screen.scrollback))
            return true
        elseif evt.key == :pagedown
            tw.scroll_offset = max(0, tw.scroll_offset - tw.last_area.height)
            return true
        elseif evt.key in (:left_shift, :right_shift, :left_ctrl, :right_ctrl,
                           :left_alt, :right_alt, :left_super, :right_super,
                           :left_hyper, :right_hyper, :left_meta, :right_meta,
                           :caps_lock, :scroll_lock, :num_lock)
            # Modifier-only keys: stay in scrollback (allows copy/paste)
            return false
        else
            # Any other key returns to live view and forwards to PTY
            tw.scroll_offset = 0
        end
    elseif evt.key == :pageup
        # Enter scrollback from live view
        tw.scroll_offset = min(tw.last_area.height,
                                length(tw.screen.scrollback))
        tw.scroll_offset > 0 && return true
    end

    # Forward to PTY
    tw.pty.alive || return false
    encoded = _encode_key(evt; enter_as_lf=tw.enter_as_lf,
                          cursor_key_mode=tw.screen.cursor_key_mode)
    if !isempty(encoded)
        pty_write(tw.pty, encoded)
        return true
    end
    false
end

function handle_mouse!(tw::TerminalWidget, evt::MouseEvent)::Bool
    sb_len = length(tw.screen.scrollback)

    # ── Scrollbar click/drag ──
    was_dragging = tw._sb_state.dragging
    frac = handle_scrollbar_mouse!(tw._sb_state, evt)
    if frac !== nothing
        # frac 0 = top (fully scrolled back), frac 1 = bottom (live view)
        tw.scroll_offset = round(Int, (1.0 - frac) * sb_len)
        return true
    end
    was_dragging && !tw._sb_state.dragging && return true

    Base.contains(tw.last_area, evt.x, evt.y) || return false

    # ── Mouse forwarding to PTY (when subprocess has requested it) ──
    if tw.screen.mouse_reporting && tw.pty.alive && tw.scroll_offset == 0
        text_width = tw.show_scrollbar ? tw.last_area.width - 1 : tw.last_area.width
        # Translate to content-relative coordinates (1-based)
        cx = evt.x - tw.last_area.x + 1
        cy = evt.y - tw.last_area.y + 1
        if cx >= 1 && cx <= text_width && cy >= 1 && cy <= tw.last_area.height
            seq = _encode_mouse_sgr(evt, cx, cy)
            if !isempty(seq)
                pty_write(tw.pty, seq)
                return true
            end
        end
    end

    # ── Scroll wheel (only when subprocess is NOT capturing mouse) ──
    if evt.button == mouse_scroll_up
        tw.scroll_offset = min(tw.scroll_offset + 3, sb_len)
        return true
    elseif evt.button == mouse_scroll_down
        tw.scroll_offset = max(0, tw.scroll_offset - 3)
        return true
    end
    false
end

"""
    close!(tw::TerminalWidget)

Close the PTY and terminate the child process. Call this in your
model's cleanup.
"""
function close!(tw::TerminalWidget)
    pty_close!(tw.pty)
end
