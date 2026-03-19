@testset "app() error propagation (#20)" begin
    # Model whose view always throws
    mutable struct _ErrorModel <: T.Model
        quit::Bool
        cleanup_called::Bool
    end
    _ErrorModel() = _ErrorModel(false, false)
    T.should_quit(m::_ErrorModel) = m.quit
    function T.view(m::_ErrorModel, f::T.Frame)
        error("intentional view error for testing")
    end
    T.cleanup!(m::_ErrorModel) = (m.cleanup_called = true)

    @testset "error in view surfaces from spawned task" begin
        m = _ErrorModel()
        # Set INPUT_IO to a BufferStream so app() skips the dup(0) call
        # and the stdin monitor has something to wait on.
        fake_input = Base.BufferStream()
        old_input = T.INPUT_IO[]
        T.INPUT_IO[] = fake_input
        try
            task = @async app(m; fps=60, default_bindings=false,
                              tty_out="/dev/null", tty_size=(rows=24, cols=80))
            # Wait for the task to finish (should fail quickly)
            result = timedwait(() -> istaskdone(task), 10.0)
            @test result == :ok  # task completed within timeout
            @test istaskfailed(task)
            # The thrown error should be an ErrorException with our message
            err = task.result
            @test err isa TaskFailedException || err isa ErrorException
            if err isa TaskFailedException
                @test occursin("intentional view error", sprint(showerror, err))
            else
                @test occursin("intentional view error", err.msg)
            end
            # cleanup! should still have been called despite the error
            @test m.cleanup_called
        finally
            close(fake_input)
            T.INPUT_IO[] = old_input
        end
    end

    # Model that quits normally — sanity check that non-error path still works
    mutable struct _QuitModel <: T.Model
        frames::Int
        cleanup_called::Bool
    end
    _QuitModel() = _QuitModel(0, false)
    T.should_quit(m::_QuitModel) = m.frames >= 3
    function T.view(m::_QuitModel, f::T.Frame)
        m.frames += 1
    end
    T.cleanup!(m::_QuitModel) = (m.cleanup_called = true)

    @testset "normal quit still works" begin
        m = _QuitModel()
        fake_input = Base.BufferStream()
        old_input = T.INPUT_IO[]
        T.INPUT_IO[] = fake_input
        try
            task = @async app(m; fps=60, default_bindings=false,
                              tty_out="/dev/null", tty_size=(rows=24, cols=80))
            result = timedwait(() -> istaskdone(task), 10.0)
            @test result == :ok
            @test !istaskfailed(task)
            @test m.cleanup_called
            @test m.frames >= 3
        finally
            close(fake_input)
            T.INPUT_IO[] = old_input
        end
    end
end
