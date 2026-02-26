# ═══════════════════════════════════════════════════════════════════════
# CodeEditor ── code editor with line numbers, syntax highlighting,
#               and auto-indentation for Julia
# ═══════════════════════════════════════════════════════════════════════

# ── Token types ─────────────────────────────────────────────────────

@enum TokenKind begin
    tok_keyword
    tok_type
    tok_number
    tok_string
    tok_comment
    tok_operator
    tok_punctuation
    tok_macro
    tok_symbol
    tok_bool
    tok_builtin
    tok_identifier
end

struct Token
    start::Int      # 1-based start index in the line
    stop::Int       # 1-based end index (inclusive)
    kind::TokenKind
end

# ── Julia keyword / builtin sets ────────────────────────────────────

const _JULIA_KEYWORDS = Set([
    "function", "end", "if", "else", "elseif", "for", "while", "do",
    "begin", "let", "try", "catch", "finally", "return", "break",
    "continue", "struct", "mutable", "abstract", "primitive", "type",
    "module", "baremodule", "using", "import", "export", "macro",
    "quote", "in", "isa", "where", "const", "local", "global",
    "outer", "new",
])

const _JULIA_BOOLS = Set(["true", "false"])
const _JULIA_BUILTINS = Set(["nothing", "missing", "Inf", "NaN", "pi"])

const _OPERATOR_CHARS = Set("=+-*/<>!&|^~%\\÷")
const _PUNCTUATION_CHARS = Set("()[]{}.,;:")

# Two-char operators (first char => set of valid second chars)
const _TWO_CHAR_OPS = Dict(
    '=' => Set("=>"),
    '!' => Set("="),
    '<' => Set("=:"),
    '>' => Set("=>"),
    '-' => Set(">"),
    '|' => Set(">|"),
    '&' => Set("&"),
    ':' => Set(":"),
    '+' => Set("="),
    '*' => Set("="),
    '/' => Set("="),
    '^' => Set("="),
    '~' => Set(),
    '%' => Set("="),
    '\\' => Set(),
    '÷' => Set("="),
)

# ── Tokenizer ───────────────────────────────────────────────────────

function tokenize_line(chars::Vector{Char})::Vector{Token}
    tokens = Token[]
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]

        # Skip whitespace
        if c == ' ' || c == '\t'
            i += 1
            continue
        end

        # Comment: # to end of line
        if c == '#'
            push!(tokens, Token(i, n, tok_comment))
            break
        end

        # String literal
        if c == '"'
            j = i + 1
            while j <= n
                if chars[j] == '\\' && j + 1 <= n
                    j += 2
                elseif chars[j] == '"'
                    break
                else
                    j += 1
                end
            end
            stop = min(j, n)
            push!(tokens, Token(i, stop, tok_string))
            i = stop + 1
            continue
        end

        # Char literal: 'x' or '\x'
        if c == '\''
            if i + 2 <= n && chars[i+2] == '\''
                push!(tokens, Token(i, i+2, tok_string))
                i += 3
                continue
            elseif i + 3 <= n && chars[i+1] == '\\' && chars[i+3] == '\''
                push!(tokens, Token(i, i+3, tok_string))
                i += 4
                continue
            end
            # Otherwise treat as operator
            push!(tokens, Token(i, i, tok_operator))
            i += 1
            continue
        end

        # Macro: @identifier
        if c == '@' && i + 1 <= n && (isletter(chars[i+1]) || chars[i+1] == '_')
            j = i + 1
            while j <= n && (isletter(chars[j]) || isdigit(chars[j]) || chars[j] == '_' || chars[j] == '!')
                j += 1
            end
            push!(tokens, Token(i, j - 1, tok_macro))
            i = j
            continue
        end

        # Symbol: :identifier (but not ::)
        if c == ':' && i + 1 <= n && isletter(chars[i+1])
            if i > 1 && chars[i-1] == ':'
                push!(tokens, Token(i, i, tok_punctuation))
                i += 1
                continue
            end
            j = i + 1
            while j <= n && (isletter(chars[j]) || isdigit(chars[j]) || chars[j] == '_')
                j += 1
            end
            push!(tokens, Token(i, j - 1, tok_symbol))
            i = j
            continue
        end

        # Number
        if isdigit(c) || (c == '.' && i + 1 <= n && isdigit(chars[i+1]))
            j = i
            # Hex/oct/bin prefix
            if c == '0' && j + 1 <= n && chars[j+1] in ('x', 'o', 'b')
                j += 2
                while j <= n && (isdigit(chars[j]) || chars[j] in ('a','b','c','d','e','f',
                                                                      'A','B','C','D','E','F') || chars[j] == '_')
                    j += 1
                end
            else
                saw_dot = (c == '.')
                j += 1
                while j <= n
                    ch = chars[j]
                    if isdigit(ch) || ch == '_'
                        j += 1
                    elseif ch == '.' && !saw_dot
                        saw_dot = true
                        j += 1
                    elseif ch in ('e', 'E') && j + 1 <= n
                        j += 1
                        if j <= n && chars[j] in ('+', '-')
                            j += 1
                        end
                    else
                        break
                    end
                end
            end
            push!(tokens, Token(i, j - 1, tok_number))
            i = j
            continue
        end

        # Identifier / keyword
        if isletter(c) || c == '_'
            j = i + 1
            while j <= n && (isletter(chars[j]) || isdigit(chars[j]) || chars[j] == '_' || chars[j] == '!')
                j += 1
            end
            word = String(chars[i:j-1])
            kind = if word in _JULIA_KEYWORDS
                tok_keyword
            elseif word in _JULIA_BOOLS
                tok_bool
            elseif word in _JULIA_BUILTINS
                tok_builtin
            elseif !isempty(word) && isuppercase(word[1])
                tok_type
            else
                tok_identifier
            end
            push!(tokens, Token(i, j - 1, kind))
            i = j
            continue
        end

        # Operator
        if c in _OPERATOR_CHARS
            j = i
            if haskey(_TWO_CHAR_OPS, c) && i + 1 <= n && chars[i+1] in _TWO_CHAR_OPS[c]
                j = i + 1
            end
            push!(tokens, Token(i, j, tok_operator))
            i = j + 1
            continue
        end

        # Punctuation
        if c in _PUNCTUATION_CHARS
            push!(tokens, Token(i, i, tok_punctuation))
            i += 1
            continue
        end

        # Fallback: treat as identifier
        push!(tokens, Token(i, i, tok_identifier))
        i += 1
    end
    tokens
end

# ── Style mapping ──────────────────────────────────────────────────

function _token_style(kind::TokenKind)
    if kind == tok_keyword
        tstyle(:primary, bold=true)
    elseif kind == tok_type
        tstyle(:warning)
    elseif kind == tok_number
        tstyle(:accent)
    elseif kind == tok_string
        tstyle(:success)
    elseif kind == tok_comment
        tstyle(:text_dim, italic=true)
    elseif kind == tok_macro
        tstyle(:secondary, bold=true)
    elseif kind == tok_symbol
        tstyle(:accent, italic=true)
    elseif kind == tok_bool
        tstyle(:accent, bold=true)
    elseif kind == tok_builtin
        tstyle(:text_dim, italic=true)
    elseif kind == tok_operator
        tstyle(:text_bright)
    elseif kind == tok_punctuation
        tstyle(:text_dim)
    else
        tstyle(:text)
    end
end

# ── CodeEditor struct ──────────────────────────────────────────────

mutable struct CodeEditor
    lines::Vector{Vector{Char}}
    cursor_row::Int
    cursor_col::Int
    scroll_offset::Int
    h_scroll::Int
    token_cache::Vector{Vector{Token}}
    dirty_lines::Set{Int}
    show_line_numbers::Bool
    tab_width::Int
    style::Style
    gutter_style::Style
    cursor_style::Style
    block::Union{Block, Nothing}
    focused::Bool
    tick::Union{Int, Nothing}

    # Modal editing
    mode::Symbol                          # :insert, :normal, :search
    pending_key::Union{Char, Nothing}     # multi-key: d, g, y, c, r

    # Undo/Redo
    undo_stack::Vector{Tuple{Vector{Vector{Char}}, Int, Int}}  # (lines, row, col)
    redo_stack::Vector{Tuple{Vector{Vector{Char}}, Int, Int}}
    last_edit_was_char::Bool              # group consecutive char inserts

    # Yank buffer
    yank_buffer::Vector{Vector{Char}}
    yank_is_linewise::Bool

    # Search
    search_query::Vector{Char}
    search_matches::Vector{Tuple{Int, Int}}  # (row, col) 1-based
    search_match_idx::Int
end

"""
    CodeEditor(; text="", mode=:insert, focused=true, tick=nothing, ...)

Syntax-highlighted code editor with Vim-style modal editing (`mode=:normal`/`:insert`),
line numbers, undo/redo, and Julia tokenization.
"""
function CodeEditor(;
    text::String="",
    show_line_numbers::Bool=true,
    tab_width::Int=4,
    style::Style=tstyle(:text),
    gutter_style::Style=tstyle(:text_dim),
    cursor_style::Style=Style(; fg=Color256(0), bg=tstyle(:accent).fg),
    block::Union{Block, Nothing}=nothing,
    focused::Bool=true,
    tick::Union{Int, Nothing}=nothing,
    mode::Symbol=:insert,
)
    ls = [collect(l) for l in Base.split(text, '\n'; keepempty=true)]
    isempty(ls) && (ls = [Char[]])
    row = length(ls)
    col = length(ls[end])
    cache = [tokenize_line(l) for l in ls]
    CodeEditor(ls, row, col, 0, 0, cache, Set{Int}(), show_line_numbers,
               tab_width, style, gutter_style, cursor_style, block, focused, tick,
               mode, nothing,
               Tuple{Vector{Vector{Char}}, Int, Int}[],
               Tuple{Vector{Vector{Char}}, Int, Int}[],
               false,
               Vector{Char}[], false,
               Char[], Tuple{Int, Int}[], 0)
end

focusable(::CodeEditor) = true
value(w::CodeEditor) = text(w)
set_value!(w::CodeEditor, s::String) = set_text!(w, s)

"""Return the current editor mode (`:insert`, `:normal`, or `:search`)."""
editor_mode(ce::CodeEditor) = ce.mode

# ── Helpers ────────────────────────────────────────────────────────

function text(ce::CodeEditor)
    join(String.(ce.lines), '\n')
end

function clear!(ce::CodeEditor)
    empty!(ce.lines)
    push!(ce.lines, Char[])
    ce.cursor_row = 1
    ce.cursor_col = 0
    ce.scroll_offset = 0
    ce.h_scroll = 0
    ce.token_cache = [Token[]]
    empty!(ce.dirty_lines)
end

function set_text!(ce::CodeEditor, s::String)
    ce.lines = [collect(l) for l in Base.split(s, '\n'; keepempty=true)]
    isempty(ce.lines) && push!(ce.lines, Char[])
    ce.cursor_row = length(ce.lines)
    ce.cursor_col = length(ce.lines[end])
    ce.scroll_offset = 0
    ce.h_scroll = 0
    ce.token_cache = [tokenize_line(l) for l in ce.lines]
    empty!(ce.dirty_lines)
end

function _mark_dirty!(ce::CodeEditor, row::Int)
    push!(ce.dirty_lines, row)
end

function _ensure_tokens!(ce::CodeEditor)
    # Resize cache if lines were added/removed
    while length(ce.token_cache) < length(ce.lines)
        push!(ce.token_cache, Token[])
        push!(ce.dirty_lines, length(ce.token_cache))
    end
    while length(ce.token_cache) > length(ce.lines)
        pop!(ce.token_cache)
    end
    for row in ce.dirty_lines
        if row >= 1 && row <= length(ce.lines)
            ce.token_cache[row] = tokenize_line(ce.lines[row])
        end
    end
    empty!(ce.dirty_lines)
end

# ── Auto-indent ────────────────────────────────────────────────────

const _BLOCK_OPENERS = Set([
    "function", "if", "for", "while", "do", "begin", "let", "try",
    "struct", "module", "macro", "else", "elseif", "catch", "finally",
    "quote", "baremodule", "mutable", "abstract",
])

const _DEDENT_KEYWORDS = Set(["end", "else", "elseif", "catch", "finally"])

function _leading_spaces(line::Vector{Char})
    count = 0
    for c in line
        c == ' ' ? (count += 1) : break
    end
    count
end

function _line_stripped(line::Vector{Char})
    strip(String(line))
end

function _should_indent(line::Vector{Char})
    s = _line_stripped(line)
    isempty(s) && return false
    # Check if line ends with " do"
    endswith(s, " do") && return true
    # Check first word
    first_word = first(Base.split(s))
    # Handle "mutable struct" etc
    first_word in _BLOCK_OPENERS && return true
    false
end

function _compute_indent(ce::CodeEditor, row::Int)
    indent = _leading_spaces(ce.lines[row])
    if _should_indent(ce.lines[row])
        indent += ce.tab_width
    end
    indent
end

function _auto_dedent!(ce::CodeEditor, row::Int)
    line = ce.lines[row]
    s = _line_stripped(line)
    s in _DEDENT_KEYWORDS || return false
    current_indent = _leading_spaces(line)
    current_indent >= ce.tab_width || return false
    # Remove tab_width spaces from front
    to_remove = ce.tab_width
    deleteat!(line, 1:to_remove)
    ce.cursor_col = max(0, ce.cursor_col - to_remove)
    _mark_dirty!(ce, row)
    true
end

# ── Undo/Redo ─────────────────────────────────────────────────────

function _snapshot(ce::CodeEditor)
    (map(copy, ce.lines), ce.cursor_row, ce.cursor_col)
end

function _push_undo!(ce::CodeEditor; force::Bool=false)
    if force || !ce.last_edit_was_char
        push!(ce.undo_stack, _snapshot(ce))
        length(ce.undo_stack) > 100 && popfirst!(ce.undo_stack)
        empty!(ce.redo_stack)
    end
end

function _undo!(ce::CodeEditor)
    isempty(ce.undo_stack) && return
    push!(ce.redo_stack, _snapshot(ce))
    (lines, row, col) = pop!(ce.undo_stack)
    ce.lines = lines
    ce.cursor_row = row
    ce.cursor_col = col
    ce.token_cache = [tokenize_line(l) for l in ce.lines]
    empty!(ce.dirty_lines)
    ce.last_edit_was_char = false
end

function _redo!(ce::CodeEditor)
    isempty(ce.redo_stack) && return
    push!(ce.undo_stack, _snapshot(ce))
    (lines, row, col) = pop!(ce.redo_stack)
    ce.lines = lines
    ce.cursor_row = row
    ce.cursor_col = col
    ce.token_cache = [tokenize_line(l) for l in ce.lines]
    empty!(ce.dirty_lines)
    ce.last_edit_was_char = false
end

# ── Word Motion Helpers ───────────────────────────────────────────

_is_word_char(c::Char) = isletter(c) || isdigit(c) || c == '_'

function _next_word_start(ce::CodeEditor)
    row, col = ce.cursor_row, ce.cursor_col
    line = ce.lines[row]
    n = length(line)
    # col is 0-based; chars are 1-based
    pos = col + 1  # 1-based position
    if pos <= n
        # Skip current word class
        if _is_word_char(line[pos])
            while pos <= n && _is_word_char(line[pos]); pos += 1; end
        elseif line[pos] != ' ' && line[pos] != '\t'
            while pos <= n && !_is_word_char(line[pos]) && line[pos] != ' ' && line[pos] != '\t'; pos += 1; end
        end
        # Skip whitespace
        while pos <= n && (line[pos] == ' ' || line[pos] == '\t'); pos += 1; end
    end
    if pos > n && row < length(ce.lines)
        # Wrap to next line, first non-space
        ce.cursor_row = row + 1
        next_line = ce.lines[ce.cursor_row]
        pos2 = 1
        while pos2 <= length(next_line) && (next_line[pos2] == ' ' || next_line[pos2] == '\t'); pos2 += 1; end
        ce.cursor_col = pos2 - 1
    else
        ce.cursor_col = min(pos - 1, max(n - 1, 0))
    end
end

function _prev_word_start(ce::CodeEditor)
    row, col = ce.cursor_row, ce.cursor_col
    line = ce.lines[row]
    pos = col  # 0-based, so chars[pos] is 1-based pos
    if pos <= 0 && row > 1
        ce.cursor_row = row - 1
        ce.cursor_col = max(length(ce.lines[ce.cursor_row]) - 1, 0)
        return
    end
    # Skip whitespace backwards
    while pos > 0 && (line[pos] == ' ' || line[pos] == '\t'); pos -= 1; end
    if pos <= 0
        ce.cursor_col = 0
        return
    end
    # Skip word class backwards
    if _is_word_char(line[pos])
        while pos > 1 && _is_word_char(line[pos - 1]); pos -= 1; end
    else
        while pos > 1 && !_is_word_char(line[pos - 1]) && line[pos - 1] != ' ' && line[pos - 1] != '\t'; pos -= 1; end
    end
    ce.cursor_col = pos - 1
end

function _end_of_word(ce::CodeEditor)
    row, col = ce.cursor_row, ce.cursor_col
    line = ce.lines[row]
    n = length(line)
    pos = col + 2  # advance one (1-based)
    if pos > n && row < length(ce.lines)
        ce.cursor_row = row + 1
        line = ce.lines[ce.cursor_row]
        n = length(line)
        pos = 1
    end
    # Skip whitespace
    while pos <= n && (line[pos] == ' ' || line[pos] == '\t'); pos += 1; end
    # Skip through word class
    if pos <= n
        if _is_word_char(line[pos])
            while pos + 1 <= n && _is_word_char(line[pos + 1]); pos += 1; end
        else
            while pos + 1 <= n && !_is_word_char(line[pos + 1]) && line[pos + 1] != ' ' && line[pos + 1] != '\t'; pos += 1; end
        end
    end
    ce.cursor_col = min(pos - 1, max(n - 1, 0))
end

# ── Key handling ───────────────────────────────────────────────────

function handle_key!(ce::CodeEditor, evt::KeyEvent)::Bool
    ce.focused || return false

    # Ctrl+Z → undo (any mode)
    if evt.key == :ctrl && evt.char == 'z'
        _undo!(ce)
        return true
    end

    # Ctrl+R → redo (any mode)
    if evt.key == :ctrl && evt.char == 'r'
        _redo!(ce)
        return true
    end

    # Ctrl+F → enter search (from insert or normal)
    if evt.key == :ctrl && evt.char == 'f' && ce.mode != :search
        ce.mode = :search
        empty!(ce.search_query)
        empty!(ce.search_matches)
        ce.search_match_idx = 0
        return true
    end

    if ce.mode == :insert
        return _handle_insert_key!(ce, evt)
    elseif ce.mode == :normal
        return _handle_normal_key!(ce, evt)
    elseif ce.mode == :search
        return _handle_search_key!(ce, evt)
    end
    false
end

# ── Insert mode ───────────────────────────────────────────────────

function _handle_insert_key!(ce::CodeEditor, evt::KeyEvent)::Bool

    if evt.key == :escape
        ce.mode = :normal
        ce.last_edit_was_char = false
        # Clamp col for normal mode (cursor stays on last char)
        line_len = length(ce.lines[ce.cursor_row])
        ce.cursor_col = min(ce.cursor_col, max(line_len - 1, 0))
        return true
    end

    if evt.key == :char
        _push_undo!(ce)
        insert!(ce.lines[ce.cursor_row], ce.cursor_col + 1, evt.char)
        ce.cursor_col += 1
        _mark_dirty!(ce, ce.cursor_row)
        _auto_dedent!(ce, ce.cursor_row)
        ce.last_edit_was_char = true
        return true

    elseif evt.key == :enter
        _push_undo!(ce; force=true)
        ce.last_edit_was_char = false
        line = ce.lines[ce.cursor_row]
        left = line[1:ce.cursor_col]
        right_part = line[ce.cursor_col+1:end]
        ce.lines[ce.cursor_row] = left
        _mark_dirty!(ce, ce.cursor_row)

        indent = _compute_indent(ce, ce.cursor_row)
        new_line = vcat(fill(' ', indent), right_part)
        insert!(ce.lines, ce.cursor_row + 1, new_line)
        ce.cursor_row += 1
        ce.cursor_col = indent
        _mark_dirty!(ce, ce.cursor_row)
        return true

    elseif evt.key == :backspace
        _push_undo!(ce; force=true)
        ce.last_edit_was_char = false
        if ce.cursor_col > 0
            deleteat!(ce.lines[ce.cursor_row], ce.cursor_col)
            ce.cursor_col -= 1
            _mark_dirty!(ce, ce.cursor_row)
        elseif ce.cursor_row > 1
            prev_len = length(ce.lines[ce.cursor_row - 1])
            append!(ce.lines[ce.cursor_row - 1], ce.lines[ce.cursor_row])
            deleteat!(ce.lines, ce.cursor_row)
            ce.cursor_row -= 1
            ce.cursor_col = prev_len
            _mark_dirty!(ce, ce.cursor_row)
        end
        return true

    elseif evt.key == :delete
        _push_undo!(ce; force=true)
        ce.last_edit_was_char = false
        line = ce.lines[ce.cursor_row]
        if ce.cursor_col < length(line)
            deleteat!(line, ce.cursor_col + 1)
            _mark_dirty!(ce, ce.cursor_row)
        elseif ce.cursor_row < length(ce.lines)
            append!(ce.lines[ce.cursor_row], ce.lines[ce.cursor_row + 1])
            deleteat!(ce.lines, ce.cursor_row + 1)
            _mark_dirty!(ce, ce.cursor_row)
        end
        return true

    elseif evt.key == :tab
        _push_undo!(ce; force=true)
        ce.last_edit_was_char = false
        for _ in 1:ce.tab_width
            insert!(ce.lines[ce.cursor_row], ce.cursor_col + 1, ' ')
            ce.cursor_col += 1
        end
        _mark_dirty!(ce, ce.cursor_row)
        return true

    elseif evt.key == :backtab
        _push_undo!(ce; force=true)
        ce.last_edit_was_char = false
        line = ce.lines[ce.cursor_row]
        leading = _leading_spaces(line)
        to_remove = min(ce.tab_width, leading)
        to_remove > 0 || return true
        deleteat!(line, 1:to_remove)
        ce.cursor_col = max(0, ce.cursor_col - to_remove)
        _mark_dirty!(ce, ce.cursor_row)
        return true

    elseif evt.key == :left
        ce.last_edit_was_char = false
        if ce.cursor_col > 0
            ce.cursor_col -= 1
        elseif ce.cursor_row > 1
            ce.cursor_row -= 1
            ce.cursor_col = length(ce.lines[ce.cursor_row])
        end
        return true

    elseif evt.key == :right
        ce.last_edit_was_char = false
        line = ce.lines[ce.cursor_row]
        if ce.cursor_col < length(line)
            ce.cursor_col += 1
        elseif ce.cursor_row < length(ce.lines)
            ce.cursor_row += 1
            ce.cursor_col = 0
        end
        return true

    elseif evt.key == :up
        ce.last_edit_was_char = false
        if ce.cursor_row > 1
            ce.cursor_row -= 1
            ce.cursor_col = min(ce.cursor_col, length(ce.lines[ce.cursor_row]))
        end
        return true

    elseif evt.key == :down
        ce.last_edit_was_char = false
        if ce.cursor_row < length(ce.lines)
            ce.cursor_row += 1
            ce.cursor_col = min(ce.cursor_col, length(ce.lines[ce.cursor_row]))
        end
        return true

    elseif evt.key == :home
        ce.last_edit_was_char = false
        ce.cursor_col = 0
        return true

    elseif evt.key == :end_key
        ce.last_edit_was_char = false
        ce.cursor_col = length(ce.lines[ce.cursor_row])
        return true

    elseif evt.key == :pageup
        ce.last_edit_was_char = false
        ce.cursor_row = max(1, ce.cursor_row - 20)
        ce.cursor_col = min(ce.cursor_col, length(ce.lines[ce.cursor_row]))
        return true

    elseif evt.key == :pagedown
        ce.last_edit_was_char = false
        ce.cursor_row = min(length(ce.lines), ce.cursor_row + 20)
        ce.cursor_col = min(ce.cursor_col, length(ce.lines[ce.cursor_row]))
        return true
    end
    false
end

# ── Normal mode ───────────────────────────────────────────────────

function _handle_normal_key!(ce::CodeEditor, evt::KeyEvent)::Bool
    line = ce.lines[ce.cursor_row]
    line_len = length(line)

    # Handle pending multi-key commands
    if ce.pending_key !== nothing
        pk = ce.pending_key
        ce.pending_key = nothing

        if pk == 'd' && evt.key == :char && evt.char == 'd'
            # dd → delete line (yank)
            _push_undo!(ce; force=true)
            ce.yank_buffer = [copy(ce.lines[ce.cursor_row])]
            ce.yank_is_linewise = true
            if length(ce.lines) == 1
                ce.lines[1] = Char[]
                ce.cursor_col = 0
            else
                deleteat!(ce.lines, ce.cursor_row)
                ce.cursor_row = min(ce.cursor_row, length(ce.lines))
                ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
            end
            _ensure_tokens!(ce)
            return true
        elseif pk == 'y' && evt.key == :char && evt.char == 'y'
            # yy → yank line
            ce.yank_buffer = [copy(ce.lines[ce.cursor_row])]
            ce.yank_is_linewise = true
            return true
        elseif pk == 'c' && evt.key == :char && evt.char == 'c'
            # cc → change line (clear + insert)
            _push_undo!(ce; force=true)
            indent = _leading_spaces(ce.lines[ce.cursor_row])
            ce.lines[ce.cursor_row] = fill(' ', indent)
            ce.cursor_col = indent
            ce.mode = :insert
            _mark_dirty!(ce, ce.cursor_row)
            return true
        elseif pk == 'r' && evt.key == :char
            # r + char → replace char under cursor
            if line_len > 0
                _push_undo!(ce; force=true)
                pos = ce.cursor_col + 1
                if pos >= 1 && pos <= line_len
                    ce.lines[ce.cursor_row][pos] = evt.char
                    _mark_dirty!(ce, ce.cursor_row)
                end
            end
            return true
        elseif pk == 'g' && evt.key == :char && evt.char == 'g'
            # gg → first line
            ce.cursor_row = 1
            ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[1]) - 1, 0))
            return true
        end
        # Unknown second key — ignore
        return true
    end

    # Arrow keys in normal mode
    if evt.key == :left
        ce.cursor_col = max(ce.cursor_col - 1, 0)
        return true
    elseif evt.key == :right
        ce.cursor_col = min(ce.cursor_col + 1, max(line_len - 1, 0))
        return true
    elseif evt.key == :up
        if ce.cursor_row > 1
            ce.cursor_row -= 1
            ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
        end
        return true
    elseif evt.key == :down
        if ce.cursor_row < length(ce.lines)
            ce.cursor_row += 1
            ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
        end
        return true
    elseif evt.key == :home
        ce.cursor_col = 0
        return true
    elseif evt.key == :end_key
        ce.cursor_col = max(line_len - 1, 0)
        return true
    end

    evt.key == :char || return false
    c = evt.char

    # Mode entry from normal
    if c == 'i'
        ce.mode = :insert
        return true
    elseif c == 'a'
        ce.mode = :insert
        ce.cursor_col = min(ce.cursor_col + 1, line_len)
        return true
    elseif c == 'A'
        ce.mode = :insert
        ce.cursor_col = line_len
        return true
    elseif c == 'I'
        ce.mode = :insert
        # First non-space
        sp = _leading_spaces(line)
        ce.cursor_col = min(sp, line_len)
        return true
    elseif c == 'o'
        # Open line below + insert
        _push_undo!(ce; force=true)
        indent = _leading_spaces(line)
        new_line = fill(' ', indent)
        insert!(ce.lines, ce.cursor_row + 1, new_line)
        ce.cursor_row += 1
        ce.cursor_col = indent
        ce.mode = :insert
        _mark_dirty!(ce, ce.cursor_row)
        return true
    elseif c == 'O'
        # Open line above + insert
        _push_undo!(ce; force=true)
        indent = _leading_spaces(line)
        new_line = fill(' ', indent)
        insert!(ce.lines, ce.cursor_row, new_line)
        ce.cursor_col = indent
        ce.mode = :insert
        _mark_dirty!(ce, ce.cursor_row)
        return true

    # Movement
    elseif c == 'h'
        ce.cursor_col = max(ce.cursor_col - 1, 0)
        return true
    elseif c == 'l'
        ce.cursor_col = min(ce.cursor_col + 1, max(line_len - 1, 0))
        return true
    elseif c == 'j'
        if ce.cursor_row < length(ce.lines)
            ce.cursor_row += 1
            ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
        end
        return true
    elseif c == 'k'
        if ce.cursor_row > 1
            ce.cursor_row -= 1
            ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
        end
        return true
    elseif c == 'w'
        _next_word_start(ce)
        # Clamp for normal mode
        cur_len = length(ce.lines[ce.cursor_row])
        ce.cursor_col = min(ce.cursor_col, max(cur_len - 1, 0))
        return true
    elseif c == 'b'
        _prev_word_start(ce)
        return true
    elseif c == 'e'
        _end_of_word(ce)
        return true
    elseif c == '0'
        ce.cursor_col = 0
        return true
    elseif c == '$'
        ce.cursor_col = max(line_len - 1, 0)
        return true
    elseif c == '^'
        sp = _leading_spaces(line)
        ce.cursor_col = min(sp, max(line_len - 1, 0))
        return true
    elseif c == 'G'
        ce.cursor_row = length(ce.lines)
        ce.cursor_col = min(ce.cursor_col, max(length(ce.lines[ce.cursor_row]) - 1, 0))
        return true

    # Editing (single-key)
    elseif c == 'x'
        if line_len > 0
            _push_undo!(ce; force=true)
            pos = ce.cursor_col + 1
            if pos >= 1 && pos <= line_len
                ce.yank_buffer = [Char[line[pos]]]
                ce.yank_is_linewise = false
                deleteat!(ce.lines[ce.cursor_row], pos)
                new_len = length(ce.lines[ce.cursor_row])
                ce.cursor_col = min(ce.cursor_col, max(new_len - 1, 0))
                _mark_dirty!(ce, ce.cursor_row)
            end
        end
        return true
    elseif c == 'D'
        # Delete cursor to end of line
        if line_len > 0
            _push_undo!(ce; force=true)
            pos = ce.cursor_col + 1
            if pos <= line_len
                ce.yank_buffer = [line[pos:end]]
                ce.yank_is_linewise = false
                deleteat!(ce.lines[ce.cursor_row], pos:line_len)
                new_len = length(ce.lines[ce.cursor_row])
                ce.cursor_col = max(new_len - 1, 0)
                _mark_dirty!(ce, ce.cursor_row)
            end
        end
        return true
    elseif c == 'C'
        # Delete to end + insert mode
        _push_undo!(ce; force=true)
        pos = ce.cursor_col + 1
        if pos <= line_len
            deleteat!(ce.lines[ce.cursor_row], pos:line_len)
            _mark_dirty!(ce, ce.cursor_row)
        end
        ce.mode = :insert
        return true
    elseif c == 'J'
        # Join line with next
        if ce.cursor_row < length(ce.lines)
            _push_undo!(ce; force=true)
            next_line = ce.lines[ce.cursor_row + 1]
            # Strip leading whitespace from next line
            stripped_start = 1
            while stripped_start <= length(next_line) && (next_line[stripped_start] == ' ' || next_line[stripped_start] == '\t')
                stripped_start += 1
            end
            # Add a space separator if current line is non-empty
            if line_len > 0 && stripped_start <= length(next_line)
                push!(ce.lines[ce.cursor_row], ' ')
            end
            append!(ce.lines[ce.cursor_row], next_line[stripped_start:end])
            deleteat!(ce.lines, ce.cursor_row + 1)
            _mark_dirty!(ce, ce.cursor_row)
            _ensure_tokens!(ce)
        end
        return true
    elseif c == '~'
        # Toggle case at cursor
        if line_len > 0
            _push_undo!(ce; force=true)
            pos = ce.cursor_col + 1
            if pos >= 1 && pos <= line_len
                ch = line[pos]
                ce.lines[ce.cursor_row][pos] = isuppercase(ch) ? lowercase(ch) : uppercase(ch)
                ce.cursor_col = min(ce.cursor_col + 1, max(line_len - 1, 0))
                _mark_dirty!(ce, ce.cursor_row)
            end
        end
        return true
    elseif c == 'p'
        # Paste after
        if !isempty(ce.yank_buffer)
            _push_undo!(ce; force=true)
            if ce.yank_is_linewise
                for (i, yline) in enumerate(ce.yank_buffer)
                    insert!(ce.lines, ce.cursor_row + i, copy(yline))
                end
                ce.cursor_row += 1
                ce.cursor_col = min(_leading_spaces(ce.lines[ce.cursor_row]), max(length(ce.lines[ce.cursor_row]) - 1, 0))
                _ensure_tokens!(ce)
            else
                chars = ce.yank_buffer[1]
                pos = ce.cursor_col + 2  # after cursor
                pos = min(pos, line_len + 1)
                for (i, ch) in enumerate(chars)
                    insert!(ce.lines[ce.cursor_row], pos + i - 1, ch)
                end
                ce.cursor_col = pos + length(chars) - 2
                ce.cursor_col = max(ce.cursor_col, 0)
                _mark_dirty!(ce, ce.cursor_row)
            end
        end
        return true
    elseif c == 'P'
        # Paste before
        if !isempty(ce.yank_buffer)
            _push_undo!(ce; force=true)
            if ce.yank_is_linewise
                for (i, yline) in enumerate(ce.yank_buffer)
                    insert!(ce.lines, ce.cursor_row + i - 1, copy(yline))
                end
                ce.cursor_col = min(_leading_spaces(ce.lines[ce.cursor_row]), max(length(ce.lines[ce.cursor_row]) - 1, 0))
                _ensure_tokens!(ce)
            else
                chars = ce.yank_buffer[1]
                pos = ce.cursor_col + 1  # at cursor
                for (i, ch) in enumerate(chars)
                    insert!(ce.lines[ce.cursor_row], pos + i - 1, ch)
                end
                ce.cursor_col = pos + length(chars) - 2
                ce.cursor_col = max(ce.cursor_col, 0)
                _mark_dirty!(ce, ce.cursor_row)
            end
        end
        return true

    # Multi-key commands (set pending)
    elseif c == 'd' || c == 'y' || c == 'c' || c == 'r' || c == 'g'
        ce.pending_key = c
        return true

    # Undo/Redo
    elseif c == 'u'
        _undo!(ce)
        return true

    # Search
    elseif c == '/'
        ce.mode = :search
        empty!(ce.search_query)
        empty!(ce.search_matches)
        ce.search_match_idx = 0
        return true
    elseif c == 'n'
        # Next search match
        if !isempty(ce.search_matches)
            ce.search_match_idx = mod1(ce.search_match_idx + 1, length(ce.search_matches))
            (mr, mc) = ce.search_matches[ce.search_match_idx]
            ce.cursor_row = mr
            ce.cursor_col = mc - 1
        end
        return true
    elseif c == 'N'
        # Prev search match
        if !isempty(ce.search_matches)
            ce.search_match_idx = mod1(ce.search_match_idx - 1, length(ce.search_matches))
            (mr, mc) = ce.search_matches[ce.search_match_idx]
            ce.cursor_row = mr
            ce.cursor_col = mc - 1
        end
        return true
    end

    false
end

# ── Search mode ───────────────────────────────────────────────────

function _update_search_matches!(ce::CodeEditor)
    empty!(ce.search_matches)
    ce.search_match_idx = 0
    isempty(ce.search_query) && return
    query = ce.search_query
    qlen = length(query)
    for (ri, line) in enumerate(ce.lines)
        n = length(line)
        for ci in 1:(n - qlen + 1)
            match = true
            for qi in 1:qlen
                if line[ci + qi - 1] != query[qi]
                    match = false
                    break
                end
            end
            if match
                push!(ce.search_matches, (ri, ci))
            end
        end
    end
    # Auto-select first match at or after cursor
    if !isempty(ce.search_matches)
        ce.search_match_idx = 1
        for (i, (mr, mc)) in enumerate(ce.search_matches)
            if mr > ce.cursor_row || (mr == ce.cursor_row && mc - 1 >= ce.cursor_col)
                ce.search_match_idx = i
                break
            end
        end
    end
end

function _handle_search_key!(ce::CodeEditor, evt::KeyEvent)::Bool
    if evt.key == :escape
        ce.mode = :normal
        empty!(ce.search_matches)
        ce.search_match_idx = 0
        return true
    elseif evt.key == :enter
        # Confirm search — jump to current match, return to normal
        if !isempty(ce.search_matches) && ce.search_match_idx >= 1
            (mr, mc) = ce.search_matches[ce.search_match_idx]
            ce.cursor_row = mr
            ce.cursor_col = mc - 1
        end
        ce.mode = :normal
        return true
    elseif evt.key == :backspace
        if !isempty(ce.search_query)
            pop!(ce.search_query)
            _update_search_matches!(ce)
        end
        return true
    elseif evt.key == :char
        push!(ce.search_query, evt.char)
        _update_search_matches!(ce)
        return true
    end
    false
end

function _in_search_match(ce::CodeEditor, row::Int, col::Int)
    qlen = length(ce.search_query)
    qlen == 0 && return false
    for (mr, mc) in ce.search_matches
        mr == row && col >= mc && col < mc + qlen && return true
    end
    false
end

# ── Render ─────────────────────────────────────────────────────────

function _gutter_width(ce::CodeEditor, line_count::Int)
    ce.show_line_numbers || return 0
    ndigits(max(line_count, 1)) + 1  # +1 for │ separator
end

function _token_at(tokens::Vector{Token}, col::Int)
    for tok in tokens
        if col >= tok.start && col <= tok.stop
            return tok
        end
    end
    nothing
end

function render(ce::CodeEditor, rect::Rect, buf::Buffer)
    # Apply block if present
    area = if ce.block !== nothing
        render(ce.block, rect, buf)
    else
        rect
    end
    (area.width < 1 || area.height < 1) && return

    _ensure_tokens!(ce)

    line_count = length(ce.lines)
    gw = _gutter_width(ce, line_count)
    code_width = area.width - gw
    code_width < 1 && return

    # Reserve bottom row for search bar when in search mode
    search_bar = ce.mode == :search && area.height >= 2
    vis_height = search_bar ? area.height - 1 : area.height

    # Auto-scroll vertically
    if ce.cursor_row - 1 < ce.scroll_offset
        ce.scroll_offset = ce.cursor_row - 1
    elseif ce.cursor_row > ce.scroll_offset + vis_height
        ce.scroll_offset = ce.cursor_row - vis_height
    end

    # Auto-scroll horizontally
    if ce.cursor_col < ce.h_scroll
        ce.h_scroll = ce.cursor_col
    elseif ce.cursor_col >= ce.h_scroll + code_width
        ce.h_scroll = ce.cursor_col - code_width + 1
    end

    # Animated cursor
    cur_style = ce.cursor_style
    if ce.focused && ce.tick !== nothing && animations_enabled()
        base_bg = to_rgb(cur_style.bg)
        br = breathe(ce.tick; period=70)
        cur_bg = brighten(base_bg, br * 0.25)
        cur_style = Style(fg=cur_style.fg, bg=cur_bg)
    end

    # Search highlight style (yellow bg, black fg)
    search_style = Style(; fg=Color256(0), bg=Color256(226))

    for vi in 1:vis_height
        li = ce.scroll_offset + vi
        y = area.y + vi - 1

        # Gutter
        if ce.show_line_numbers
            gutter_x = area.x
            sep_x = area.x + gw - 1
            if li <= line_count
                num_str = string(li)
                # Right-align number
                pad = gw - 1 - length(num_str)
                nx = gutter_x + pad
                gs = if ce.focused && li == ce.cursor_row
                    tstyle(:text_bright)
                else
                    ce.gutter_style
                end
                for (ci, ch) in enumerate(num_str)
                    set_char!(buf, nx + ci - 1, y, ch, gs)
                end
                set_char!(buf, sep_x, y, '│', ce.gutter_style)
            else
                # Empty gutter for lines past end
                set_char!(buf, sep_x, y, '│', ce.gutter_style)
            end
        end

        li > line_count && continue

        line = ce.lines[li]
        tokens = li <= length(ce.token_cache) ? ce.token_cache[li] : Token[]
        code_x = area.x + gw

        for ci in 1:code_width
            char_idx = ce.h_scroll + ci
            x = code_x + ci - 1
            x > right(area) && break

            is_cursor = ce.focused && li == ce.cursor_row &&
                        char_idx == ce.cursor_col + 1

            if char_idx >= 1 && char_idx <= length(line)
                ch = line[char_idx]
                char_style = if is_cursor
                    cur_style
                elseif _in_search_match(ce, li, char_idx)
                    search_style
                else
                    tok = _token_at(tokens, char_idx)
                    tok !== nothing ? _token_style(tok.kind) : ce.style
                end
                set_char!(buf, x, y, ch, char_style)
            elseif is_cursor
                set_char!(buf, x, y, ' ', cur_style)
            end
        end

        # Cursor at position 0 (before all text)
        if ce.focused && li == ce.cursor_row && ce.cursor_col == 0 && ce.h_scroll == 0
            cx = code_x
            if !isempty(line)
                set_char!(buf, cx, y, line[1], cur_style)
            else
                set_char!(buf, cx, y, ' ', cur_style)
            end
        end
    end

    # Search bar
    if search_bar
        sy = area.y + vis_height
        sx = area.x
        bar_style = tstyle(:warning)
        set_char!(buf, sx, sy, '/', bar_style)
        qstr = String(ce.search_query)
        for (i, ch) in enumerate(qstr)
            xi = sx + i
            xi > right(area) && break
            set_char!(buf, xi, sy, ch, bar_style)
        end
        # Cursor block after query
        cursor_x = sx + length(qstr) + 1
        if cursor_x <= right(area)
            set_char!(buf, cursor_x, sy, ' ', cur_style)
        end
        # Match count
        if !isempty(ce.search_matches)
            info = " [$(ce.search_match_idx)/$(length(ce.search_matches))]"
            info_x = cursor_x + 1
            for (i, ch) in enumerate(info)
                xi = info_x + i - 1
                xi > right(area) && break
                set_char!(buf, xi, sy, ch, tstyle(:text_dim))
            end
        end
    end
end
