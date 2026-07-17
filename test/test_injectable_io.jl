# test_injectable_io.jl -- `T.with_terminal(io = ...)` / `app(io = ...)`.
#
# The claim under test is that frames can be pointed at a sink this process
# did not open, with no terminal involved anywhere: no /dev/tty, no raw mode
# on stdin, no probe escapes written to whatever terminal happens to be
# attached. That is what lets a Tachikoma app be driven by something other
# than a tty -- a websocket, a pipe, a recording.

@testset "injectable io" begin
    @testset "with_terminal renders into an injected sink" begin
        sink = IOBuffer()
        got = T.with_terminal(; io = sink, tty_size = (rows = 10, cols = 40)) do t
            @test t.io === sink
            @test t.size == Rect(1, 1, 40, 10)
            T.draw!(t) do f
                render(Block(title = "hi"), f.area, f.buffer)
            end
            :ran
        end
        @test got === :ran
        out = String(take!(copy(sink)))
        # The alt screen went to OUR buffer, which is the whole point: the
        # frame stream is addressable.
        @test !isempty(out)
        @test occursin("\e[?1049h", out)   # ALT_SCREEN_ON
    end

    @testset "an injected sink demands a size" begin
        # Guessing would put every frame at the wrong dimensions, and the
        # sink cannot be probed. Fail loudly at the call, not visually later.
        @test_throws ArgumentError T.with_terminal(identity; io = IOBuffer())
    end

    @testset "the caller's sink is the caller's to close" begin
        # A websocket outlives any one app; closing it here would take the
        # connection down with the app.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 5, cols = 20)) do t
            nothing
        end
        @test isopen(sink)
        # ...whereas the paths with_terminal opened ITSELF are still its own.
    end

    @testset "the injected size survives draw!" begin
        # The regression this pins: draw! calls check_resize!, which probed
        # terminal_size() whenever remote_tty_path was nothing -- which is
        # exactly the injected-io case. Under the app's own stdout capture
        # that probe reaches a pipe and returns its 80x24 default, so every
        # frame was silently resized to the wrong dimensions while t.size
        # still read correctly.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 7, cols = 33)) do t
            @test t.size == Rect(1, 1, 33, 7)
            T.draw!(t) do f
                @test f.area.width == 33
                @test f.area.height == 7
            end
        end
    end

    @testset "app() drives a real Model into an injected sink" begin
        # The whole point, end to end: a Model/view/update app rendered
        # through app() with no terminal anywhere -- the frames land in a
        # buffer this test owns. A self-quitting model ends the loop, so no
        # input source is needed to make app() return.
        @kwdef mutable struct _Hello <: T.Model
            frames::Int = 0
        end
        T.should_quit(m::_Hello) = m.frames >= 3
        function T.view(m::_Hello, f::T.Frame)
            m.frames += 1
            render(Block(title = "hi from a sink"), f.area, f.buffer)
        end

        sink = IOBuffer()
        model = _Hello()
        # Supply the input source up front. app() only dups fd 0 when
        # INPUT_IO is unset, and under the test harness fd 0 is not a tty
        # (dup'ing it throws EINVAL) -- but a socket-driven caller sets its
        # own input source anyway, which is exactly what this models.
        old_input = T.INPUT_IO[]
        T.INPUT_IO[] = IOBuffer()
        try
            app(model; io = sink, tty_size = (rows = 8, cols = 40), fps = 120)
        finally
            T.INPUT_IO[] = old_input
        end
        out = String(take!(copy(sink)))
        @test model.frames >= 3
        @test occursin("hi from a sink", out)
        @test occursin("\e[?1049h", out)          # alt screen, into OUR sink
        @test occursin('─', out) || occursin('│', out)  # a box was drawn
    end

    @testset "resize! is how an injected sink changes size" begin
        # No tty to probe and no SIGWINCH to catch: the caller who owns the
        # sink is the only one who knows, so it has to say.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 7, cols = 33)) do t
            @test resize!(t, (rows = 12, cols = 50)) == true
            @test t.size == Rect(1, 1, 50, 12)
            T.draw!(t) do f
                @test f.area.width == 50
                @test f.area.height == 12
            end
            # Unchanged size is not a resize -- draw! keys its clear off this.
            @test resize!(t, (rows = 12, cols = 50)) == false
        end
    end
end
