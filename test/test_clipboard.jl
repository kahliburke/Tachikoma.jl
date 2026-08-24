# test_clipboard.jl -- clipboard backend selection and OSC 52 encoding.
#
# The native backend shells out to whatever helper the machine happens to
# have, so these tests exercise the parts that are decidable without one:
# backend selection, the escape sequence, and the guarantee that a copy on a
# machine with no clipboard at all still returns instead of throwing.

@testset "clipboard" begin
    @testset "backend selection" begin
        saved = T.clipboard_backend()
        try
            @test T.set_clipboard_backend!(:osc52) === :osc52
            @test T.clipboard_backend() === :osc52
            @test_throws ArgumentError T.set_clipboard_backend!(:pbcopy)
            @test T.clipboard_backend() === :osc52   # unchanged by the failed set
        finally
            T.set_clipboard_backend!(saved)
        end
    end

    @testset "TACHIKOMA_CLIPBOARD sets the backend" begin
        saved = T.clipboard_backend()
        saved_env = get(ENV, "TACHIKOMA_CLIPBOARD", nothing)
        try
            ENV["TACHIKOMA_CLIPBOARD"] = "osc52"
            T.load_clipboard_backend!()
            @test T.clipboard_backend() === :osc52

            # An unrecognised value is ignored rather than disabling the
            # clipboard outright.
            T.set_clipboard_backend!(:native)
            ENV["TACHIKOMA_CLIPBOARD"] = "wl-copy"
            T.load_clipboard_backend!()
            @test T.clipboard_backend() === :native
        finally
            saved_env === nothing ? delete!(ENV, "TACHIKOMA_CLIPBOARD") :
                                    (ENV["TACHIKOMA_CLIPBOARD"] = saved_env)
            T.set_clipboard_backend!(saved)
        end
    end

    @testset "osc52 sequence" begin
        seq = T.osc52_sequence("hello")
        @test seq == "\e]52;c;aGVsbG8=\a"

        # Non-ASCII survives: box drawing is most of what a copied pane is.
        @test T.osc52_sequence("│─┐") == string("\e]52;c;", Base64.base64encode("│─┐"), "\a")

        @test startswith(T.osc52_sequence("x"; selection = 'p'), "\e]52;p;")

        # Oversized payloads are refused, not truncated -- a half-copied pane
        # is worse than a reported failure.
        @test T.osc52_sequence("a"^(T.OSC52_MAX_BASE64)) === nothing
    end

    @testset "osc52 writes to the given sink" begin
        sink = IOBuffer()
        @test T.clipboard_copy!("hello"; io = sink, backend = :osc52) === :osc52
        @test String(take!(sink)) == "\e]52;c;aGVsbG8=\a"
    end

    @testset "osc52 reports failure on an oversized payload" begin
        sink = IOBuffer()
        @test T.clipboard_copy!("a"^(T.OSC52_MAX_BASE64); io = sink, backend = :osc52) === :none
        @test isempty(take!(sink))
    end

    @testset ":none disables copying" begin
        sink = IOBuffer()
        @test T.clipboard_copy!("hello"; io = sink, backend = :none) === :none
        @test isempty(take!(sink))
        # Empty text is a no-op regardless of backend.
        @test T.clipboard_copy!(""; io = sink, backend = :osc52) === :none
        @test isempty(take!(sink))
    end

    @testset "auto prefers osc52 when the terminal is elsewhere" begin
        # A helper program would put the text on this machine's clipboard,
        # which is not the machine the user is looking at.
        sink = IOBuffer()
        @test T.clipboard_copy!("hello"; io = sink, backend = :auto, remote = true) === :osc52
        @test String(take!(sink)) == "\e]52;c;aGVsbG8=\a"
    end

    @testset "auto falls back to osc52 when no helper works" begin
        # Force the native side to have nothing to run, so :auto must fall
        # through. This is the Wayland-with-no-wl-clipboard case.
        sink = IOBuffer()
        result = withenv("PATH" => "") do
            T.clipboard_copy!("hello"; io = sink, backend = :auto, remote = false)
        end
        @test result === :osc52
        @test String(take!(sink)) == "\e]52;c;aGVsbG8=\a"
    end

    @testset "native reports failure instead of throwing" begin
        result = withenv("PATH" => "") do
            T.clipboard_copy!("hello"; io = IOBuffer(), backend = :native)
        end
        @test result === :none
    end

    @testset "clipboard_commands prefers wl-copy under Wayland" begin
        if Sys.islinux() || (Sys.isunix() && !Sys.isapple())
            wl = withenv("WAYLAND_DISPLAY" => "wayland-0") do
                first(T.clipboard_commands()).exec[1]
            end
            @test wl == "wl-copy"
            x = withenv("WAYLAND_DISPLAY" => nothing) do
                first(T.clipboard_commands()).exec[1]
            end
            @test x == "xclip"
            # Either way both families remain reachable -- an XWayland bridge
            # or a missing helper decides which one actually works.
            names = withenv("WAYLAND_DISPLAY" => "wayland-0") do
                [c.exec[1] for c in T.clipboard_commands()]
            end
            @test "xclip" in names && "xsel" in names
        else
            @test !isempty(T.clipboard_commands())
        end
    end

    @testset "Terminal method routes osc52 to the terminal's io" begin
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 5, cols = 20)) do t
            take!(sink)  # drop setup escapes
            @test T.clipboard_copy!(t, "hello") === :osc52   # injected io ⇒ remote
            @test occursin("\e]52;c;aGVsbG8=\a", String(take!(copy(sink))))
        end
    end

    @testset "notification text names the backend used" begin
        @test T._clipboard_notification(:native) == "Copied to clipboard"
        @test occursin("OSC 52", T._clipboard_notification(:osc52))
        @test T._clipboard_notification(:none) == "Clipboard unavailable"
    end
end
