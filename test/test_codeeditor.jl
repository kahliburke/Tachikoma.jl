    # ═════════════════════════════════════════════════════════════════
    # CodeEditor
    # ═════════════════════════════════════════════════════════════════

    @testset "CodeEditor: basic editing" begin
        ce = T.CodeEditor(; text="hello", focused=true)
        @test T.text(ce) == "hello"
        @test ce.cursor_row == 1
        @test ce.cursor_col == 5

        # Insert char
        T.handle_key!(ce, T.KeyEvent('!'))
        @test T.text(ce) == "hello!"

        # Enter splits line
        ce2 = T.CodeEditor(; text="ab", focused=true)
        ce2.cursor_col = 1  # after 'a'
        T.handle_key!(ce2, T.KeyEvent(:enter))
        @test length(ce2.lines) == 2
        @test String(ce2.lines[1]) == "a"
        @test String(ce2.lines[2]) == "b"

        # Backspace joins lines
        T.handle_key!(ce2, T.KeyEvent(:home))
        T.handle_key!(ce2, T.KeyEvent(:backspace))
        @test length(ce2.lines) == 1
        @test T.text(ce2) == "ab"
    end

    @testset "CodeEditor: text extraction and clear" begin
        ce = T.CodeEditor(; text="line1\nline2\nline3")
        @test T.text(ce) == "line1\nline2\nline3"
        T.clear!(ce)
        @test T.text(ce) == ""
        @test ce.cursor_row == 1
        @test ce.cursor_col == 0
    end

    @testset "CodeEditor: auto-indent after function" begin
        ce = T.CodeEditor(; text="function foo()", focused=true)
        ce.cursor_col = length(ce.lines[1])
        T.handle_key!(ce, T.KeyEvent(:enter))
        @test ce.cursor_row == 2
        @test ce.cursor_col == ce.tab_width  # indented
        @test T._leading_spaces(ce.lines[2]) == ce.tab_width
    end

    @testset "CodeEditor: auto-indent after if/for/while" begin
        for keyword in ["if x > 0", "for i in 1:10", "while true"]
            ce = T.CodeEditor(; text=keyword, focused=true)
            ce.cursor_col = length(ce.lines[1])
            T.handle_key!(ce, T.KeyEvent(:enter))
            @test ce.cursor_col == ce.tab_width
        end
    end

    @testset "CodeEditor: auto-indent preserves existing" begin
        ce = T.CodeEditor(; text="    x = 1", focused=true)
        ce.cursor_col = length(ce.lines[1])
        T.handle_key!(ce, T.KeyEvent(:enter))
        # Should preserve 4 spaces of indent
        @test T._leading_spaces(ce.lines[2]) == 4
    end

    @testset "CodeEditor: tab inserts spaces" begin
        ce = T.CodeEditor(; text="x", focused=true, tab_width=4)
        ce.cursor_col = 0
        T.handle_key!(ce, T.KeyEvent(:tab))
        @test T.text(ce) == "    x"
        @test ce.cursor_col == 4
    end

    @testset "CodeEditor: backtab removes leading spaces" begin
        ce = T.CodeEditor(; text="        x", focused=true, tab_width=4)
        ce.cursor_col = 8
        T.handle_key!(ce, T.KeyEvent(:backtab))
        @test T.text(ce) == "    x"
        @test ce.cursor_col == 4

        # Second backtab
        T.handle_key!(ce, T.KeyEvent(:backtab))
        @test T.text(ce) == "x"
        @test ce.cursor_col == 0

        # Third backtab is no-op
        T.handle_key!(ce, T.KeyEvent(:backtab))
        @test T.text(ce) == "x"
    end

    @testset "CodeEditor: tokenizer basics" begin
        tokens = T.tokenize_line(collect("function foo(x::Int)"))
        @test length(tokens) >= 5
        @test tokens[1].kind == T.tok_keyword    # function
        @test tokens[2].kind == T.tok_identifier  # foo
        @test tokens[3].kind == T.tok_punctuation  # (

        # Find the Int token
        int_tok = findfirst(t -> String(collect("function foo(x::Int)")[t.start:t.stop]) == "Int", tokens)
        @test int_tok !== nothing
        @test tokens[int_tok].kind == T.tok_type
    end

    @testset "CodeEditor: tokenizer strings and comments" begin
        tokens = T.tokenize_line(collect("x = \"hello\" # comment"))
        kinds = [t.kind for t in tokens]
        @test T.tok_string in kinds
        @test T.tok_comment in kinds
        @test T.tok_identifier in kinds
    end

    @testset "CodeEditor: tokenizer numbers" begin
        tokens = T.tokenize_line(collect("42 3.14 0xff"))
        @test all(t.kind == T.tok_number for t in tokens)
    end

    @testset "CodeEditor: tokenizer keywords and bools" begin
        tokens = T.tokenize_line(collect("if true end false"))
        kinds = [t.kind for t in tokens]
        @test kinds[1] == T.tok_keyword   # if
        @test kinds[2] == T.tok_bool      # true
        @test kinds[3] == T.tok_keyword   # end
        @test kinds[4] == T.tok_bool      # false
    end

    @testset "CodeEditor: tokenizer macros and symbols" begin
        tokens = T.tokenize_line(collect("@time :foo"))
        @test tokens[1].kind == T.tok_macro
        @test tokens[2].kind == T.tok_symbol
    end

    @testset "CodeEditor: render with line numbers" begin
        ce = T.CodeEditor(; text="abc\ndef", focused=true, show_line_numbers=true)
        ce.cursor_row = 1
        ce.cursor_col = 0
        tb = T.TestBackend(40, 10)
        T.render_widget!(tb, ce)
        # Line number 1 should appear
        row1 = T.row_text(tb, 1)
        @test occursin("1", row1)
        @test occursin("│", row1)
        @test occursin("abc", row1)
        # Line number 2
        row2 = T.row_text(tb, 2)
        @test occursin("2", row2)
        @test occursin("def", row2)
    end

    @testset "CodeEditor: render without line numbers" begin
        ce = T.CodeEditor(; text="abc", focused=true, show_line_numbers=false)
        ce.cursor_row = 1
        ce.cursor_col = 0
        tb = T.TestBackend(40, 5)
        T.render_widget!(tb, ce)
        row1 = T.row_text(tb, 1)
        @test occursin("abc", row1)
        # No gutter separator
        @test !occursin("│", row1)
    end

    @testset "CodeEditor: unfocused ignores keys" begin
        ce = T.CodeEditor(; text="x", focused=false)
        @test !T.handle_key!(ce, T.KeyEvent('a'))
        @test T.text(ce) == "x"
    end

    @testset "CodeEditor: delete key" begin
        ce = T.CodeEditor(; text="abc", focused=true)
        ce.cursor_col = 0
        T.handle_key!(ce, T.KeyEvent(:delete))
        @test T.text(ce) == "bc"

        # Delete at end of line joins with next
        ce2 = T.CodeEditor(; text="ab\ncd", focused=true)
        ce2.cursor_row = 1
        ce2.cursor_col = 2
        T.handle_key!(ce2, T.KeyEvent(:delete))
        @test T.text(ce2) == "abcd"
        @test length(ce2.lines) == 1
    end

    @testset "CodeEditor: navigation keys" begin
        ce = T.CodeEditor(; text="abc\ndef\nghi", focused=true)
        ce.cursor_row = 1
        ce.cursor_col = 0

        # Right
        T.handle_key!(ce, T.KeyEvent(:right))
        @test ce.cursor_col == 1

        # Down
        T.handle_key!(ce, T.KeyEvent(:down))
        @test ce.cursor_row == 2
        @test ce.cursor_col == 1

        # Up
        T.handle_key!(ce, T.KeyEvent(:up))
        @test ce.cursor_row == 1

        # End
        T.handle_key!(ce, T.KeyEvent(:end_key))
        @test ce.cursor_col == 3

        # Home
        T.handle_key!(ce, T.KeyEvent(:home))
        @test ce.cursor_col == 0

        # Left wraps to previous line
        T.handle_key!(ce, T.KeyEvent(:down))
        T.handle_key!(ce, T.KeyEvent(:home))
        T.handle_key!(ce, T.KeyEvent(:left))
        @test ce.cursor_row == 1
        @test ce.cursor_col == 3

        # Right wraps to next line
        T.handle_key!(ce, T.KeyEvent(:right))
        @test ce.cursor_row == 2
        @test ce.cursor_col == 0
    end

    @testset "CodeEditor: set_text!" begin
        ce = T.CodeEditor(; text="old")
        T.set_text!(ce, "new\ntext")
        @test T.text(ce) == "new\ntext"
        @test ce.cursor_row == 2
        @test ce.cursor_col == 4
        @test length(ce.token_cache) == 2
    end

    @testset "CodeEditor: auto-dedent on typing end" begin
        ce = T.CodeEditor(; text="function foo()\n    ", focused=true)
        ce.cursor_row = 2
        ce.cursor_col = 4
        for c in "end"
            T.handle_key!(ce, T.KeyEvent(c))
        end
        # Should have dedented: "end" not "    end"
        @test T._leading_spaces(ce.lines[2]) == 0
    end

    @testset "CodeEditor: focusable" begin
        ce = T.CodeEditor()
        @test T.focusable(ce)
    end

    # ═════════════════════════════════════════════════════════════════
    # CodeEditor: Modal editing, undo/redo, search
    # ═════════════════════════════════════════════════════════════════

    @testset "CodeEditor: mode transitions" begin
        # Default mode is :insert
        ce = T.CodeEditor(; text="hello", focused=true)
        @test T.editor_mode(ce) == :insert

        # Escape → normal
        T.handle_key!(ce, T.KeyEvent(:escape))
        @test T.editor_mode(ce) == :normal

        # i → insert
        T.handle_key!(ce, T.KeyEvent('i'))
        @test T.editor_mode(ce) == :insert

        # Escape → normal, then a → insert (cursor moves right)
        T.handle_key!(ce, T.KeyEvent(:escape))
        ce.cursor_col = 2
        T.handle_key!(ce, T.KeyEvent('a'))
        @test T.editor_mode(ce) == :insert
        @test ce.cursor_col == 3

        # A → insert at end of line
        T.handle_key!(ce, T.KeyEvent(:escape))
        T.handle_key!(ce, T.KeyEvent('A'))
        @test T.editor_mode(ce) == :insert
        @test ce.cursor_col == length(ce.lines[ce.cursor_row])

        # I → insert at first non-space
        ce2 = T.CodeEditor(; text="    hello", focused=true)
        T.handle_key!(ce2, T.KeyEvent(:escape))
        T.handle_key!(ce2, T.KeyEvent('I'))
        @test T.editor_mode(ce2) == :insert
        @test ce2.cursor_col == 4

        # o → open line below + insert
        ce3 = T.CodeEditor(; text="hello", focused=true)
        T.handle_key!(ce3, T.KeyEvent(:escape))
        ce3.cursor_row = 1
        ce3.cursor_col = 0
        T.handle_key!(ce3, T.KeyEvent('o'))
        @test T.editor_mode(ce3) == :insert
        @test ce3.cursor_row == 2
        @test length(ce3.lines) == 2

        # O → open line above + insert
        ce4 = T.CodeEditor(; text="hello", focused=true)
        T.handle_key!(ce4, T.KeyEvent(:escape))
        ce4.cursor_row = 1
        ce4.cursor_col = 0
        T.handle_key!(ce4, T.KeyEvent('O'))
        @test T.editor_mode(ce4) == :insert
        @test ce4.cursor_row == 1
        @test length(ce4.lines) == 2
    end

    @testset "CodeEditor: mode kwarg" begin
        ce = T.CodeEditor(; text="hello", focused=true, mode=:normal)
        @test T.editor_mode(ce) == :normal
    end

    @testset "CodeEditor: normal mode escape clamps cursor" begin
        ce = T.CodeEditor(; text="abc", focused=true)
        ce.cursor_col = 3  # one past end (insert mode valid)
        T.handle_key!(ce, T.KeyEvent(:escape))
        @test ce.cursor_col == 2  # clamped to last char
    end

    @testset "CodeEditor: normal movement h/l/j/k" begin
        ce = T.CodeEditor(; text="abcde\nfghij\nklmno", focused=true, mode=:normal)
        ce.cursor_row = 2
        ce.cursor_col = 2

        # h → left
        T.handle_key!(ce, T.KeyEvent('h'))
        @test ce.cursor_col == 1

        # l → right
        T.handle_key!(ce, T.KeyEvent('l'))
        @test ce.cursor_col == 2

        # j → down
        T.handle_key!(ce, T.KeyEvent('j'))
        @test ce.cursor_row == 3

        # k → up
        T.handle_key!(ce, T.KeyEvent('k'))
        @test ce.cursor_row == 2

        # h at col 0 stays at 0
        ce.cursor_col = 0
        T.handle_key!(ce, T.KeyEvent('h'))
        @test ce.cursor_col == 0
    end

    @testset "CodeEditor: normal movement 0, \$, ^" begin
        ce = T.CodeEditor(; text="   hello world", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 5

        # 0 → start of line
        T.handle_key!(ce, T.KeyEvent('0'))
        @test ce.cursor_col == 0

        # $ → end of line
        T.handle_key!(ce, T.KeyEvent('$'))
        @test ce.cursor_col == length(ce.lines[1]) - 1

        # ^ → first non-space
        T.handle_key!(ce, T.KeyEvent('^'))
        @test ce.cursor_col == 3
    end

    @testset "CodeEditor: normal movement w/b/e" begin
        ce = T.CodeEditor(; text="hello world foo", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        # w → next word start
        T.handle_key!(ce, T.KeyEvent('w'))
        @test ce.cursor_col == 6  # 'w' of 'world'

        # w again
        T.handle_key!(ce, T.KeyEvent('w'))
        @test ce.cursor_col == 12  # 'f' of 'foo'

        # b → prev word start
        T.handle_key!(ce, T.KeyEvent('b'))
        @test ce.cursor_col == 6  # 'w' of 'world'

        # e → end of word
        ce.cursor_col = 0
        T.handle_key!(ce, T.KeyEvent('e'))
        @test ce.cursor_col == 4  # 'o' of 'hello'
    end

    @testset "CodeEditor: normal movement gg/G" begin
        ce = T.CodeEditor(; text="line1\nline2\nline3", focused=true, mode=:normal)
        ce.cursor_row = 2
        ce.cursor_col = 0

        # G → last line
        T.handle_key!(ce, T.KeyEvent('G'))
        @test ce.cursor_row == 3

        # gg → first line
        T.handle_key!(ce, T.KeyEvent('g'))
        T.handle_key!(ce, T.KeyEvent('g'))
        @test ce.cursor_row == 1
    end

    @testset "CodeEditor: normal editing x" begin
        ce = T.CodeEditor(; text="abcde", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 2

        T.handle_key!(ce, T.KeyEvent('x'))
        @test T.text(ce) == "abde"
        @test ce.cursor_col == 2  # stays or clamps

        # x yanks character
        @test ce.yank_buffer == [['c']]
        @test !ce.yank_is_linewise
    end

    @testset "CodeEditor: normal editing dd" begin
        ce = T.CodeEditor(; text="line1\nline2\nline3", focused=true, mode=:normal)
        ce.cursor_row = 2
        ce.cursor_col = 0

        T.handle_key!(ce, T.KeyEvent('d'))
        T.handle_key!(ce, T.KeyEvent('d'))
        @test length(ce.lines) == 2
        @test T.text(ce) == "line1\nline3"
        @test ce.yank_is_linewise
    end

    @testset "CodeEditor: normal editing D" begin
        ce = T.CodeEditor(; text="abcdef", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 2

        T.handle_key!(ce, T.KeyEvent('D'))
        @test T.text(ce) == "ab"
    end

    @testset "CodeEditor: normal editing C" begin
        ce = T.CodeEditor(; text="abcdef", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 3

        T.handle_key!(ce, T.KeyEvent('C'))
        @test T.text(ce) == "abc"
        @test T.editor_mode(ce) == :insert
    end

    @testset "CodeEditor: normal editing J" begin
        ce = T.CodeEditor(; text="hello\n  world", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        T.handle_key!(ce, T.KeyEvent('J'))
        @test T.text(ce) == "hello world"
        @test length(ce.lines) == 1
    end

    @testset "CodeEditor: normal editing ~" begin
        ce = T.CodeEditor(; text="Hello", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        T.handle_key!(ce, T.KeyEvent('~'))
        @test ce.lines[1][1] == 'h'  # toggled H→h
        @test ce.cursor_col == 1  # advanced
    end

    @testset "CodeEditor: normal editing r+char" begin
        ce = T.CodeEditor(; text="abcde", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 2

        T.handle_key!(ce, T.KeyEvent('r'))
        T.handle_key!(ce, T.KeyEvent('X'))
        @test T.text(ce) == "abXde"
    end

    @testset "CodeEditor: undo/redo" begin
        ce = T.CodeEditor(; text="hello", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        # x deletes 'h', undo restores it
        T.handle_key!(ce, T.KeyEvent('x'))
        @test T.text(ce) == "ello"
        T.handle_key!(ce, T.KeyEvent('u'))
        @test T.text(ce) == "hello"

        # Ctrl+R → redo
        T.handle_key!(ce, T.KeyEvent(:ctrl, 'r'))
        @test T.text(ce) == "ello"

        # Undo again, then new edit clears redo
        T.handle_key!(ce, T.KeyEvent('u'))
        @test T.text(ce) == "hello"
        T.handle_key!(ce, T.KeyEvent('x'))  # deletes 'h'
        @test isempty(ce.redo_stack)
    end

    @testset "CodeEditor: Ctrl+Z undo in insert mode" begin
        ce = T.CodeEditor(; text="abc", focused=true)
        ce.cursor_row = 1
        ce.cursor_col = 3

        # Type a char
        T.handle_key!(ce, T.KeyEvent('d'))
        @test T.text(ce) == "abcd"

        # Ctrl+Z undoes
        T.handle_key!(ce, T.KeyEvent(:ctrl, 'z'))
        @test T.text(ce) == "abc"
    end

    @testset "CodeEditor: yank/paste yy + p" begin
        ce = T.CodeEditor(; text="line1\nline2\nline3", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        # yy yanks line
        T.handle_key!(ce, T.KeyEvent('y'))
        T.handle_key!(ce, T.KeyEvent('y'))
        @test ce.yank_is_linewise
        @test ce.yank_buffer == [collect("line1")]

        # p pastes below
        T.handle_key!(ce, T.KeyEvent('p'))
        @test length(ce.lines) == 4
        @test T.text(ce) == "line1\nline1\nline2\nline3"
    end

    @testset "CodeEditor: dd + p restore" begin
        ce = T.CodeEditor(; text="aaa\nbbb\nccc", focused=true, mode=:normal)
        ce.cursor_row = 2
        ce.cursor_col = 0

        # dd deletes line 2
        T.handle_key!(ce, T.KeyEvent('d'))
        T.handle_key!(ce, T.KeyEvent('d'))
        @test T.text(ce) == "aaa\nccc"

        # p pastes it back
        T.handle_key!(ce, T.KeyEvent('p'))
        @test T.text(ce) == "aaa\nccc\nbbb"
    end

    @testset "CodeEditor: x yanks char, p pastes" begin
        ce = T.CodeEditor(; text="abcde", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        T.handle_key!(ce, T.KeyEvent('x'))
        @test T.text(ce) == "bcde"

        # Move to end and paste
        T.handle_key!(ce, T.KeyEvent('$'))
        T.handle_key!(ce, T.KeyEvent('p'))
        @test T.text(ce) == "bcdea"
    end

    @testset "CodeEditor: search mode" begin
        ce = T.CodeEditor(; text="foo bar foo baz", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        # / enters search
        T.handle_key!(ce, T.KeyEvent('/'))
        @test T.editor_mode(ce) == :search

        # Type query
        for c in "foo"
            T.handle_key!(ce, T.KeyEvent(c))
        end
        @test length(ce.search_matches) == 2
        @test ce.search_matches[1] == (1, 1)
        @test ce.search_matches[2] == (1, 9)

        # Enter confirms
        T.handle_key!(ce, T.KeyEvent(:enter))
        @test T.editor_mode(ce) == :normal
        @test ce.cursor_col == 0  # first match

        # n goes to next match
        T.handle_key!(ce, T.KeyEvent('n'))
        @test ce.cursor_col == 8  # second match (0-based)

        # N goes to prev match
        T.handle_key!(ce, T.KeyEvent('N'))
        @test ce.cursor_col == 0
    end

    @testset "CodeEditor: search escape cancels" begin
        ce = T.CodeEditor(; text="hello world", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 0

        T.handle_key!(ce, T.KeyEvent('/'))
        for c in "world"
            T.handle_key!(ce, T.KeyEvent(c))
        end
        @test !isempty(ce.search_matches)

        # Escape cancels
        T.handle_key!(ce, T.KeyEvent(:escape))
        @test T.editor_mode(ce) == :normal
        @test isempty(ce.search_matches)
    end

    @testset "CodeEditor: Ctrl+F enters search" begin
        ce = T.CodeEditor(; text="hello", focused=true)
        T.handle_key!(ce, T.KeyEvent(:ctrl, 'f'))
        @test T.editor_mode(ce) == :search
    end

    @testset "CodeEditor: cc changes line" begin
        ce = T.CodeEditor(; text="    hello", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 4

        T.handle_key!(ce, T.KeyEvent('c'))
        T.handle_key!(ce, T.KeyEvent('c'))
        @test T.editor_mode(ce) == :insert
        # Line should be cleared to just indentation
        @test T.text(ce) == "    "
        @test ce.cursor_col == 4
    end

    @testset "CodeEditor: arrow keys in normal mode" begin
        ce = T.CodeEditor(; text="abcde\nfghij", focused=true, mode=:normal)
        ce.cursor_row = 1
        ce.cursor_col = 2

        T.handle_key!(ce, T.KeyEvent(:down))
        @test ce.cursor_row == 2

        T.handle_key!(ce, T.KeyEvent(:up))
        @test ce.cursor_row == 1

        T.handle_key!(ce, T.KeyEvent(:right))
        @test ce.cursor_col == 3

        T.handle_key!(ce, T.KeyEvent(:left))
        @test ce.cursor_col == 2
    end

