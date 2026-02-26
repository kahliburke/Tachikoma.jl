    @testset "Scripting" begin
        @testset "EventScript construction" begin
            es = T.EventScript((1.0, T.key('r')), (2.0, T.key('b')))
            @test length(es.entries) == 2
            @test es.entries[1][1] == 1.0
            @test es.entries[2][1] == 2.0
        end

        @testset "EventScript flattens vectors" begin
            es = T.EventScript(
                (1.0, T.key('a')),
                T.rep(T.key('r'), 3),
                (0.5, T.key('b')),
            )
            # 1 + 3 + 1 = 5 entries
            @test length(es.entries) == 5
        end

        @testset "EventScript callable (fps conversion)" begin
            es = T.EventScript((1.0, T.key('a')), (0.5, T.key('b')))
            result = es(60)
            @test length(result) == 2
            @test result[1] == (60, T.key('a'))
            @test result[2] == (90, T.key('b'))
        end

        @testset "pause produces Wait (skipped in output)" begin
            es = T.EventScript((1.0, T.key('a')), T.pause(2.0), (1.0, T.key('b')))
            @test length(es.entries) == 3
            result = es(10)
            # Wait entries are skipped, so only 2 events
            @test length(result) == 2
            @test result[1] == (10, T.key('a'))
            @test result[2] == (40, T.key('b'))  # 1.0 + 2.0 + 1.0 = 4.0s
        end

        @testset "seq" begin
            s = T.seq(T.key(:up), T.key(:down); gap=0.5)
            @test length(s) == 2
            @test s[1][1] == 0.5
            @test s[2][1] == 0.5
        end

        @testset "rep" begin
            r = T.rep(T.key('x'), 4; gap=0.25)
            @test length(r) == 4
            @test all(e -> e[1] == 0.25, r)
        end

        @testset "chars" begin
            c = T.chars("Hi"; pace=0.1)
            @test length(c) == 2
            @test c[1][1] == 0.1
            @test c[1][2] == T.KeyEvent('H')
            @test c[2][2] == T.KeyEvent('i')
        end

        @testset "key constructors" begin
            @test T.key(:enter).key == :enter
            @test T.key('z').char == 'z'
        end
    end
