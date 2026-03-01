@testset "ccall safety — variadic ioctl and GC pressure" begin
    # TIOCGWINSZ is variadic on macOS/BSD. On ARM64, the non-variadic form
    # passes the pointer in the wrong register, causing EFAULT or segfaults.
    # These tests verify the variadic form doesn't segfault under GC pressure,
    # even when ioctl returns -1 (no TTY in CI).

    @static if !Sys.iswindows()
        tiocgwinsz = @static (Sys.isapple() || Sys.isbsd()) ? 0x40087468 : 0x5413

        function ioctl_variadic_stdout()
            buf = zeros(UInt16, 4)
            GC.@preserve buf begin
                p = pointer(buf)
                ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), 1, tiocgwinsz, p)
            end
            ret = ret
            (ret, Int(buf[1]), Int(buf[2]), Int(buf[3]), Int(buf[4]))
        end

        function ioctl_variadic_ref()
            ref = Ref{NTuple{4, UInt16}}((0, 0, 0, 0))
            ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), 1, tiocgwinsz, ref)
            t = ref[]
            (ret, Int(t[1]), Int(t[2]), Int(t[3]), Int(t[4]))
        end

        function ioctl_variadic_uint64()
            ref = Ref{UInt64}(0)
            ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), 1, tiocgwinsz, ref)
            val = ref[]
            (ret, Int(val & 0xFFFF), Int((val >> 16) & 0xFFFF),
             Int((val >> 32) & 0xFFFF), Int((val >> 48) & 0xFFFF))
        end

        @testset "no segfault under GC pressure (1000 calls × 3 variants)" begin
            mismatches = 0
            for i in 1:1000
                r1 = ioctl_variadic_stdout()
                r2 = ioctl_variadic_ref()
                r3 = ioctl_variadic_uint64()
                (r1 == r2 == r3) || (mismatches += 1)
                if i % 100 == 0
                    _ = [rand(100) for _ in 1:50]
                    GC.gc()
                end
            end
            @test mismatches == 0
        end

        @testset "buffer not corrupted by GC" begin
            corruptions = 0
            for _ in 1:100
                buf = zeros(UInt16, 4)
                GC.@preserve buf begin
                    p = pointer(buf)
                    ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), 1, tiocgwinsz, p)
                end
                saved = copy(buf)
                GC.gc(true)
                buf == saved || (corruptions += 1)
            end
            @test corruptions == 0
        end
    else
        @test true  # skip on Windows
    end
end
