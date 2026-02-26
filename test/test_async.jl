@testset "Async tasks" begin
    @testset "TaskEvent type hierarchy and fields" begin
        evt = T.TaskEvent(:test, 42)
        @test evt isa T.Event
        @test evt isa T.TaskEvent{Int}
        @test evt.id == :test
        @test evt.value == 42

        # String payload
        evt2 = T.TaskEvent(:msg, "hello")
        @test evt2 isa T.TaskEvent{String}
        @test evt2.value == "hello"
    end

    @testset "TaskQueue basic lifecycle" begin
        q = T.TaskQueue()
        @test q.active[] == 0
        @test !isready(q.channel)

        T.spawn_task!(q, :add) do
            1 + 2
        end
        # Wait for task to complete
        sleep(0.2)
        @test isready(q.channel)
        results = T.Event[]
        n = T.drain_tasks!(q) do evt
            push!(results, evt)
        end
        @test n == 1
        @test length(results) == 1
        @test results[1] isa T.TaskEvent{Int}
        @test results[1].id == :add
        @test results[1].value == 3
        @test q.active[] == 0
    end

    @testset "Exception handling in spawned task" begin
        q = T.TaskQueue()
        T.spawn_task!(q, :fail) do
            error("boom")
        end
        sleep(0.2)
        results = T.Event[]
        T.drain_tasks!(q) do evt
            push!(results, evt)
        end
        @test length(results) == 1
        @test results[1].id == :fail
        @test results[1].value isa ErrorException
        @test results[1].value.msg == "boom"
        @test q.active[] == 0
    end

    @testset "Concurrent tasks" begin
        q = T.TaskQueue()
        n_tasks = 10
        for i in 1:n_tasks
            T.spawn_task!(q, :concurrent) do
                sleep(0.01)
                i * 10
            end
        end
        # Wait for all tasks
        deadline = time() + 5.0
        while q.active[] > 0 && time() < deadline
            sleep(0.05)
        end
        @test q.active[] == 0

        results = Int[]
        T.drain_tasks!(q) do evt
            push!(results, evt.value)
        end
        @test length(results) == n_tasks
        @test sort(results) == [i * 10 for i in 1:n_tasks]
    end

    @testset "CancelToken" begin
        token = T.CancelToken()
        @test !T.is_cancelled(token)
        T.cancel!(token)
        @test T.is_cancelled(token)
    end

    @testset "spawn_timer! with cancellation" begin
        q = T.TaskQueue()
        token = T.spawn_timer!(q, :tick, 0.05; repeat=true)
        sleep(0.25)
        T.cancel!(token)
        sleep(0.1)
        ticks = 0
        T.drain_tasks!(q) do evt
            @test evt.id == :tick
            @test evt.value isa Float64
            ticks += 1
        end
        @test ticks >= 2   # at least a couple ticks in 250ms at 50ms interval
        @test T.is_cancelled(token)
        # active count should return to 0 after cancel
        deadline = time() + 2.0
        while q.active[] > 0 && time() < deadline
            sleep(0.05)
        end
        @test q.active[] == 0
    end

    @testset "drain_tasks! on empty queue" begin
        q = T.TaskQueue()
        called = false
        n = T.drain_tasks!(q) do evt
            called = true
        end
        @test n == 0
        @test !called
    end

    @testset "task_queue default returns nothing" begin
        @test T.task_queue(_DummyModel()) === nothing
    end

    @testset "RecordingSnapshot isolation" begin
        rec = T.CastRecorder()
        rec.filename = "test.tach"
        rec.width = 80
        rec.height = 24
        # Add some fake data
        cell = T.Cell('A', T.Style())
        push!(rec.cell_snapshots, [cell, cell, cell])
        push!(rec.timestamps, 0.0)
        push!(rec.pixel_snapshots, T.PixelSnapshot[])

        snap = T.snapshot_recording(rec)
        @test snap.filename == "test.tach"
        @test snap.width == 80
        @test snap.height == 24
        @test length(snap.cell_snapshots) == 1
        @test length(snap.timestamps) == 1

        # Clear original — snapshot should be unaffected
        empty!(rec.cell_snapshots)
        empty!(rec.timestamps)
        empty!(rec.pixel_snapshots)

        @test length(snap.cell_snapshots) == 1
        @test length(snap.timestamps) == 1
        @test snap.cell_snapshots[1][1].char == 'A'
    end
end
