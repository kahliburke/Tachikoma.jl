# Host stream-guard hook (Kaimon #67). A raw-mode TUI run from a gate REPL whose
# stdout is a non-TTY capture wrapper wedges the host REPL on exit; an embedding
# host installs a guard via `set_stream_guard!` so `with_terminal` runs the whole
# lifecycle with the real streams restored. Here we unit-test the guard plumbing
# (`set_stream_guard!` + `_run_guarded`) without needing a real terminal.
@testset "Stream guard hook (#67)" begin
    saved = T._STREAM_GUARD[]
    try
        # No guard installed → body runs directly and its value propagates.
        T.set_stream_guard!(nothing)
        @test T._STREAM_GUARD[] === nothing
        @test T._run_guarded(() -> 42) == 42

        # A guard wraps the body: it must invoke the thunk exactly once and pass
        # the thunk's return value back out.
        calls = Ref(0)
        inner_ran = Ref(false)
        guard = function (thunk)
            calls[] += 1
            r = thunk()
            r
        end
        T.set_stream_guard!(guard)
        @test T._STREAM_GUARD[] === guard
        @test T._run_guarded(() -> (inner_ran[]=true; 7)) == 7
        @test calls[] == 1
        @test inner_ran[]

        # Clearing restores the direct path.
        T.set_stream_guard!(nothing)
        @test T._STREAM_GUARD[] === nothing
        @test T._run_guarded(() -> :ok) === :ok
    finally
        T._STREAM_GUARD[] = saved
    end
end
