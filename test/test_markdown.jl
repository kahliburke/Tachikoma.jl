using CommonMark

# ── Helpers ──────────────────────────────────────────────────────────

function _spans_text(lines)
    join((join(s.content for s in line) for line in lines), "\n")
end

function _is_blank_line_test(spans)
    isempty(spans) || all(s -> isempty(strip(s.content)), spans)
end

# ── Tests ────────────────────────────────────────────────────────────

@testset "Markdown extension" begin

    @testset "markdown_extension_loaded after using CommonMark" begin
        @test T.markdown_extension_loaded()
    end

    @testset "Empty string" begin
        lines = T.markdown_to_spans("", 80)
        @test length(lines) >= 1
    end

    @testset "Single paragraph" begin
        lines = T.markdown_to_spans("Hello world", 80)
        text = _spans_text(lines)
        @test occursin("Hello world", text)
    end

    @testset "Heading levels" begin
        md = "# H1\n\n## H2\n\n### H3"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("# H1", text)
        @test occursin("## H2", text)
        @test occursin("### H3", text)
    end

    @testset "Heading style applied" begin
        lines = T.markdown_to_spans("# Title", 80)
        line = first(l for l in lines if !isempty(l))
        @test any(s -> s.style.bold, line)
    end

    @testset "Bold text" begin
        lines = T.markdown_to_spans("Some **bold** text", 80)
        all_spans = vcat(lines...)
        bold_spans = filter(s -> s.style.bold && occursin("bold", s.content), all_spans)
        @test !isempty(bold_spans)
    end

    @testset "Inline code" begin
        lines = T.markdown_to_spans("Use `code` here", 80)
        all_spans = vcat(lines...)
        code_spans = filter(s -> s.content == "code", all_spans)
        @test !isempty(code_spans)
        # Code spans should have a background color set (not NoColor)
        @test !(code_spans[1].style.bg isa T.NoColor)
    end

    @testset "Code block" begin
        md = "```julia\nfoo()\nbar()\n```"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("foo()", text)
        @test occursin("bar()", text)
        @test occursin("julia", text)
    end

    @testset "Blockquote" begin
        md = "> quoted text"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("│", text)
        @test occursin("quoted text", text)
    end

    @testset "Nested blockquote" begin
        md = "> outer\n> > inner"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("inner", text)
        # Should have double prefix
        inner_line = first(l for l in lines if any(s -> occursin("inner", s.content), l))
        prefix_text = join(s.content for s in inner_line)
        @test count("│", prefix_text) >= 2
    end

    @testset "Unordered list" begin
        md = "- Item A\n- Item B\n- Item C"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("Item A", text)
        @test occursin("Item B", text)
        @test occursin("Item C", text)
        @test occursin("*", text)
    end

    @testset "Ordered list" begin
        md = "1. First\n2. Second\n3. Third"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("1.", text)
        @test occursin("First", text)
        @test occursin("2.", text)
    end

    @testset "Thematic break" begin
        md = "Above\n\n---\n\nBelow"
        lines = T.markdown_to_spans(md, 40)
        all_spans = vcat(lines...)
        hr_spans = filter(s -> occursin("─", s.content), all_spans)
        @test !isempty(hr_spans)
        @test length(hr_spans[1].content) >= 30  # fills width
    end

    @testset "Link text preserved" begin
        md = "Click [here](https://example.com) please"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("here", text)
    end

    @testset "Image fallback" begin
        md = "![Alt text](img.png)"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("[Image:", text)
        @test occursin("Alt text", text)
    end

    @testset "Word wrap at width" begin
        md = "alpha bravo chars delta echo foxt golf hotel india juliet"
        lines = T.markdown_to_spans(md, 20)
        non_blank = filter(l -> !all(s -> isempty(strip(s.content)), l), lines)
        @test length(non_blank) >= 3
        for line in non_blank
            line_len = sum(length(s.content) for s in line)
            @test line_len <= 25  # some tolerance for word boundaries
        end
    end

    @testset "Word wrap preserves all words" begin
        md = "one two three four five six"
        lines = T.markdown_to_spans(md, 10)
        text = _spans_text(lines)
        for word in ["one", "two", "three", "four", "five", "six"]
            @test occursin(word, text)
        end
    end

    @testset "Long single word not dropped" begin
        md = "supercalifragilisticexpialidocious"
        lines = T.markdown_to_spans(md, 10)
        text = _spans_text(lines)
        @test occursin("supercalifragilisticexpialidocious", text)
    end

    @testset "Width=1 does not infinite loop" begin
        lines = T.markdown_to_spans("test", 1)
        @test !isempty(lines)
    end

    @testset "Custom styles" begin
        custom_h1 = T.Style(fg=T.RED.c400, bold=true)
        lines = T.markdown_to_spans("# Red Title", 80; h1_style=custom_h1)
        line = first(l for l in lines if !isempty(l))
        @test any(s -> s.style.fg == T.RED.c400, line)
    end

    @testset "ScrollPane integration" begin
        md = "# Hello\n\nA paragraph.\n\n- Item 1\n- Item 2"
        lines = T.markdown_to_spans(md, 40)
        sp = T.ScrollPane(lines)
        tb = T.TestBackend(60, 20)
        T.render_widget!(tb, sp)
        rendered = T.row_text(tb, 1)
        @test length(strip(rendered)) > 0
    end

    @testset "Multiple paragraphs separated" begin
        md = "Para one.\n\nPara two."
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("Para one", text)
        @test occursin("Para two", text)
        blank_count = count(_is_blank_line_test, lines)
        @test blank_count >= 1
    end

    @testset "Code block with no language" begin
        md = "```\nplain code\n```"
        lines = T.markdown_to_spans(md, 80)
        text = _spans_text(lines)
        @test occursin("plain code", text)
    end

    @testset "Mixed inline formatting" begin
        md = "Normal **bold** and `code` and *emph*"
        lines = T.markdown_to_spans(md, 80)
        all_spans = vcat(lines...)
        @test any(s -> s.content == "bold" && s.style.bold, all_spans)
        @test any(s -> s.content == "code", all_spans)
        @test any(s -> s.content == "emph" && s.style.dim, all_spans)
    end
end

# ── MarkdownPane widget tests ──────────────────────────────────────

@testset "MarkdownPane widget" begin

    @testset "Construction" begin
        mp = T.MarkdownPane("# Hello\n\nWorld")
        @test mp.source == "# Hello\n\nWorld"
        @test mp.pane isa T.ScrollPane
        @test mp.last_width == 80
    end

    @testset "Construction with custom width" begin
        mp = T.MarkdownPane("test"; width=40)
        @test mp.last_width == 40
    end

    @testset "focusable returns true" begin
        mp = T.MarkdownPane("test")
        @test T.focusable(mp) == true
    end

    @testset "Render with TestBackend" begin
        mp = T.MarkdownPane("# Title\n\nSome text here";
            block=T.Block(title="MD"))
        tb = T.TestBackend(60, 15)
        T.render_widget!(tb, mp)
        found = T.find_text(tb, "Title")
        @test found !== nothing
    end

    @testset "set_markdown! updates source" begin
        mp = T.MarkdownPane("old content")
        T.set_markdown!(mp, "new content")
        @test mp.source == "new content"
    end

    @testset "set_markdown! updates width" begin
        mp = T.MarkdownPane("test"; width=80)
        T.set_markdown!(mp, "test"; width=40)
        @test mp.last_width == 40
    end

    @testset "Responsive reflow changes last_width" begin
        mp = T.MarkdownPane("Some long text that should reflow";
            width=80,
            block=T.Block(title="MD"))
        # Render into a narrow area — should trigger reflow
        tb = T.TestBackend(30, 10)
        T.render_widget!(tb, mp)
        # last_width should now reflect the narrower content area
        # 30 - 2 (borders) - 1 (scrollbar) = 27
        @test mp.last_width == 27
    end

    @testset "handle_key! delegation" begin
        mp = T.MarkdownPane("line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10")
        # Render first to set up last_area
        tb = T.TestBackend(40, 5)
        T.render_widget!(tb, mp)
        # Scroll down
        result = T.handle_key!(mp, T.KeyEvent(:down, '\0'))
        @test result == true
    end

    @testset "Custom styles" begin
        custom_h1 = T.Style(fg=T.RED.c400, bold=true)
        mp = T.MarkdownPane("# Red Title"; h1_style=custom_h1)
        @test mp.h1_style.fg == T.RED.c400
    end

    @testset "handle_mouse! delegation" begin
        mp = T.MarkdownPane("test content")
        # Without rendering, mouse events should return false (no area set)
        evt = T.MouseEvent(1, 1, T.mouse_scroll_down, T.mouse_press, false, false, false)
        result = T.handle_mouse!(mp, evt)
        @test result == false
    end
end
