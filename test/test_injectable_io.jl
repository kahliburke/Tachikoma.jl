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
        # No manual INPUT_IO: with `io`, app() skips the fd-0 dup that would
        # throw EINVAL headless, and `input` is the public way a socket-driven
        # caller feeds keystrokes. An empty buffer is enough here -- the model
        # self-quits.
        app(model; io = sink, tty_size = (rows = 8, cols = 40), fps = 120,
            input = IOBuffer())
        out = String(take!(copy(sink)))
        @test model.frames >= 3
        @test occursin("hi from a sink", out)
        @test occursin("\e[?1049h", out)          # alt screen, into OUR sink
        @test occursin('─', out) || occursin('│', out)  # a box was drawn
    end

    @testset "app(io=...) does not dup fd 0 (no INPUT_IO, no EINVAL)" begin
        # The wart the maintainer flagged: app() dup'd fd 0 unconditionally,
        # and Base.TTY(RawFD(dup(0))) throws EINVAL when fd 0 is not a tty --
        # the headless case. With `io` set, the dup is skipped, so this runs
        # with NOTHING pre-set.
        @kwdef mutable struct _Q <: T.Model; n::Int = 0; end
        T.should_quit(m::_Q) = m.n >= 2
        T.view(m::_Q, f::T.Frame) = (m.n += 1; render(Block(title = "q"), f.area, f.buffer))
        @assert T.INPUT_IO[] === nothing
        sink = IOBuffer()
        @test app(_Q(); io = sink, tty_size = (rows = 5, cols = 20)) === nothing
    end

    @testset "set_size! is how an injected sink changes size" begin
        # No tty to probe and no SIGWINCH to catch: the caller who owns the
        # sink is the only one who knows, so it has to say.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 7, cols = 33)) do t
            @test T.set_size!(t, (rows = 12, cols = 50)) == true
            @test t.size == Rect(1, 1, 50, 12)
            T.draw!(t) do f
                @test f.area.width == 50
                @test f.area.height == 12
            end
            # Unchanged size is not a resize.
            @test T.set_size!(t, (rows = 12, cols = 50)) == false
        end
    end

    @testset "set_size! arms a one-shot clear so a shrink wipes stale glyphs" begin
        # Issue: check_resize! is hard-wired false for external_size, and
        # draw! keys CLEAR_SCREEN off its return -- so an external resize
        # never cleared, leaving glyphs outside a shrunk region on the
        # receiver. set_size! now arms a one-shot clear that check_resize!
        # reports once.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 20, cols = 60)) do t
            T.draw!(t) do f; render(Block(title = "big"), f.area, f.buffer); end
            take!(sink)                              # drain the first frame
            @test T.set_size!(t, (rows = 8, cols = 30)) == true
            @test t.pending_clear == true            # armed
            T.draw!(t) do f; render(Block(title = "small"), f.area, f.buffer); end
            @test t.pending_clear == false           # consumed
            @test occursin("\e[2J", String(take!(sink)))   # CLEAR_SCREEN emitted
            # ...and it does NOT clear again on the next, unchanged frame.
            T.draw!(t) do f; render(Block(title = "small"), f.area, f.buffer); end
            @test !occursin("\e[2J", String(take!(sink)))
        end
    end

    @testset "an explicit input source wins over a host's INPUT_IO" begin
        # A host that installed its own INPUT_IO used to silently win over an
        # explicit `input`, so the app read from the host's source -- or, if
        # that source was empty, took no keys at all with nothing to explain
        # why. The kwarg names the source, so the kwarg wins; the host's
        # source is put back on exit.
        @kwdef mutable struct _In <: T.Model; n::Int = 0; end
        T.should_quit(m::_In) = m.n >= 2
        T.view(m::_In, f::T.Frame) = (m.n += 1; render(Block(title = "in"), f.area, f.buffer))

        host_source = IOBuffer()
        mine = IOBuffer()
        T.INPUT_IO[] = host_source
        try
            seen = Ref{Any}(:unset)
            app(_In(); io = IOBuffer(), tty_size = (rows = 5, cols = 20),
                input = mine, on_terminal = _ -> (seen[] = T.INPUT_IO[]))
            @test seen[] === mine              # the kwarg won while running
            @test T.INPUT_IO[] === host_source # ...and the host got its own back
        finally
            T.INPUT_IO[] = nothing
        end
    end

    @testset "the default path still clears INPUT_IO on exit" begin
        # Unchanged behaviour for the ordinary case: nothing installed going in,
        # nothing left installed coming out.
        @kwdef mutable struct _Def <: T.Model; n::Int = 0; end
        T.should_quit(m::_Def) = m.n >= 2
        T.view(m::_Def, f::T.Frame) = (m.n += 1; render(Block(title = "d"), f.area, f.buffer))
        @test T.INPUT_IO[] === nothing
        app(_Def(); io = IOBuffer(), tty_size = (rows = 5, cols = 20), input = IOBuffer())
        @test T.INPUT_IO[] === nothing
    end

    @testset "teardown does not touch the host's stdin" begin
        # enter_tui! skips raw mode on this process's stdin for an injected sink,
        # so leave_tui! must skip restoring it. The two used to disagree:
        # leave_tui! branched on remote_tty_path, which an injected io leaves
        # `nothing`, so it fell through to set_raw_mode!(false) -- unconditional
        # once stdin is a TTY. An embedding host (a REPL, a gate process) would
        # be dropped out of raw mode every time an app exited.
        #
        # Asserted on the predicate rather than the syscall: set_raw_mode! is a
        # no-op when stdin isn't a TTY, which is exactly the case under CI, so a
        # behavioural test here would pass no matter what the branch did.
        sink = IOBuffer()
        T.with_terminal(; io = sink, tty_size = (rows = 6, cols = 20)) do t
            @test T._is_remote_terminal(t) == true
            @test t.remote_tty_path === nothing   # ...and so is NOT detected by that
        end
        # A terminal this process does own still restores raw mode as before.
        @test T._is_remote_terminal(T.Terminal(io = IOBuffer(),
                                               size = (rows = 6, cols = 20))) == false
        # A tty_out terminal is remote too, and additionally has input to stop.
        @test T._is_remote_terminal(T.Terminal(io = IOBuffer(), size = (rows = 6, cols = 20),
                                               remote_tty_path = "/dev/ttys999")) == true
    end

    @testset "an injected sink does not redirect the process's streams" begin
        # The capture protects a terminal the app SHARES with background `println`s.
        # An injected sink has no such terminal, and the redirect is process-wide --
        # so an embedding host (a notebook worker, a server) that talks to its parent
        # over stdout would lose that stream the moment it ran an app. Note this is
        # NOT covered by the `on_stdout !== nothing` guard inside `_start_capture`:
        # `something(on_stdout, _DISCARD_OUTPUT)` has already replaced it by then.
        sink = IOBuffer()
        before_out, before_err = stdout, stderr
        seen_out, seen_err = Ref{Any}(nothing), Ref{Any}(nothing)
        T.with_terminal(; io = sink, tty_size = (rows = 6, cols = 20)) do t
            seen_out[] = stdout
            seen_err[] = stderr
        end
        @test seen_out[] === before_out
        @test seen_err[] === before_err
        @test stdout === before_out          # and nothing was left swapped out
        @test stderr === before_err
    end

    @testset "an injected sink still captures when the caller asks for the lines" begin
        # Opting in with on_stdout means the caller WANTS the output, so the redirect
        # is theirs to have -- skipping it would silently drop the lines they asked for.
        sink = IOBuffer()
        lines = String[]
        before = stdout
        T.with_terminal(; io = sink, tty_size = (rows = 6, cols = 20),
                        on_stdout = l -> push!(lines, l)) do t
            @test stdout !== before          # redirected, because it was requested
            println("captured please")
            flush(stdout)
        end
        @test stdout === before              # ...and restored afterwards
        @test any(l -> occursin("captured please", l), lines)
    end
end
