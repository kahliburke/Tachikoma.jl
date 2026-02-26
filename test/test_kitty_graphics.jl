    @testset "Kitty graphics encoder" begin
        @testset "encode_kitty red pixels → valid APC" begin
            # 2×2 red pixels
            pixels = fill(T.ColorRGB(0xff, 0x00, 0x00), 2, 2)
            data = T.encode_kitty(pixels; cols=2, rows=2)
            str = String(copy(data))
            # Must contain APC start
            @test occursin("\e_G", str)
            # Must contain transmit+display, raw RGB, suppress OK
            @test occursin("a=T", str)
            @test occursin("f=24", str)
            @test occursin("q=2", str)
            # Must contain pixel dimensions
            @test occursin("s=2", str)
            @test occursin("v=2", str)
            # Must contain cell placement
            @test occursin("c=2", str)
            @test occursin("r=2", str)
            # Must end with ST
            @test data[end-1] == UInt8('\e') && data[end] == UInt8('\\')
        end

        @testset "encode_kitty all-black → empty" begin
            pixels = fill(T.BLACK, 4, 4)
            data = T.encode_kitty(pixels)
            @test isempty(data)
        end

        @testset "encode_kitty empty matrix → empty" begin
            pixels = Matrix{T.ColorRGB}(undef, 0, 0)
            data = T.encode_kitty(pixels)
            @test isempty(data)
        end

        @testset "encode_kitty inline large image → chunked" begin
            # Force inline path to test chunking
            T._KITTY_SHM_AVAILABLE[] = false
            # Use varied pixel data — uniform fills compress too well with zlib.
            pixels = [T.ColorRGB(UInt8(mod(r * 7 + c * 13, 256)),
                                 UInt8(mod(r * 11 + c * 3, 256)),
                                 UInt8(mod(r * 5 + c * 17, 256)))
                      for r in 1:200, c in 1:200]
            data = T.encode_kitty(pixels)
            str = String(copy(data))
            # Should contain continuation flag m=1 (more chunks)
            @test occursin("m=1;", str)
            # Should contain final chunk flag m=0
            @test occursin("m=0;", str)
            # Count APC sequences
            apc_count = length(collect(eachmatch(r"\e_G", str)))
            @test apc_count > 1
            # Should use inline zlib path
            @test occursin("o=z", str)
            @test !occursin("t=s", str)
            T._KITTY_SHM_AVAILABLE[] = nothing
        end

        @testset "encode_kitty no cols/rows → omits placement" begin
            pixels = fill(T.ColorRGB(0xff, 0xff, 0xff), 1, 1)
            data = T.encode_kitty(pixels)
            str = String(copy(data))
            @test !occursin("c=", str)
            @test !occursin("r=", str)
        end

        @testset "encode_kitty with decay" begin
            pixels = fill(T.ColorRGB(0x80, 0x80, 0x80), 4, 4)
            decay = T.DecayParams(0.5, 0.3, 0.0, 0.15)
            data = T.encode_kitty(pixels; decay=decay, tick=10)
            # Should still produce output (decay modifies but doesn't zero everything)
            @test !isempty(data)
        end
    end

    @testset "Kitty shm helpers" begin
        @testset "_is_ssh_session detection" begin
            saved_conn = get(ENV, "SSH_CONNECTION", nothing)
            saved_tty = get(ENV, "SSH_TTY", nothing)
            delete!(ENV, "SSH_CONNECTION")
            delete!(ENV, "SSH_TTY")

            @test !T._is_ssh_session()

            ENV["SSH_CONNECTION"] = "1.2.3.4 5678 9.10.11.12 22"
            @test T._is_ssh_session()
            delete!(ENV, "SSH_CONNECTION")

            ENV["SSH_TTY"] = "/dev/pts/0"
            @test T._is_ssh_session()
            delete!(ENV, "SSH_TTY")

            # Restore
            saved_conn !== nothing && (ENV["SSH_CONNECTION"] = saved_conn)
            saved_tty !== nothing && (ENV["SSH_TTY"] = saved_tty)
        end

        @testset "_kitty_shm_probe! on POSIX" begin
            T._KITTY_SHM_AVAILABLE[] = nothing
            if !Sys.iswindows()
                @test T._kitty_shm_probe!() == true
                @test T._KITTY_SHM_AVAILABLE[] === true
            end
            T._KITTY_SHM_AVAILABLE[] = nothing
        end

        @testset "_kitty_shm_probe! respects TACHIKOMA_KITTY_SHM=0" begin
            T._KITTY_SHM_AVAILABLE[] = nothing
            ENV["TACHIKOMA_KITTY_SHM"] = "0"
            @test T._kitty_shm_probe!() == false
            delete!(ENV, "TACHIKOMA_KITTY_SHM")
            T._KITTY_SHM_AVAILABLE[] = nothing
        end

        @testset "_kitty_shm_probe! force-enable with TACHIKOMA_KITTY_SHM=1" begin
            T._KITTY_SHM_AVAILABLE[] = nothing
            ENV["TACHIKOMA_KITTY_SHM"] = "1"
            @test T._kitty_shm_probe!() == true
            @test T._KITTY_SHM_AVAILABLE[] === true
            delete!(ENV, "TACHIKOMA_KITTY_SHM")
            T._KITTY_SHM_AVAILABLE[] = nothing
        end

        @testset "_kitty_shm_write returns valid name" begin
            data = UInt8[0xff, 0x00, 0x00, 0x00, 0xff, 0x00]
            name = T._kitty_shm_write(data)
            @test name !== nothing
            @test startswith(something(name, ""), "/tach_k")
            # Cleanup
            if name !== nothing
                ccall(:shm_unlink, Cint, (Cstring,), name)
            end
        end

        @testset "encode_kitty with shm produces t=s header" begin
            T._KITTY_SHM_AVAILABLE[] = nothing
            pixels = fill(T.ColorRGB(0xff, 0x00, 0x00), 2, 2)
            data = T.encode_kitty(pixels; cols=2, rows=2)
            str = String(copy(data))
            if T._KITTY_SHM_AVAILABLE[] === true
                @test occursin("t=s", str)
                @test occursin("S=", str)
                @test !occursin("o=z", str)
                @test !occursin("m=1", str)
                # Clean up shm segment that Kitty would normally unlink
                m = match(r"m=0;(.+?)\e", str)
                if m !== nothing
                    shm_name = String(base64decode(m.captures[1]))
                    ccall(:shm_unlink, Cint, (Cstring,), shm_name)
                end
            end
            T._KITTY_SHM_AVAILABLE[] = nothing
        end

        @testset "encode_kitty falls back when shm disabled" begin
            T._KITTY_SHM_AVAILABLE[] = false
            pixels = fill(T.ColorRGB(0xff, 0x00, 0x00), 2, 2)
            data = T.encode_kitty(pixels; cols=2, rows=2)
            str = String(copy(data))
            @test occursin("o=z", str)
            @test !occursin("t=s", str)
            T._KITTY_SHM_AVAILABLE[] = nothing
        end
    end

    @testset "GraphicsRegion" begin
        @testset "5-arg constructor defaults to sixel" begin
            gr = T.GraphicsRegion(1, 2, 10, 5, UInt8[0x01])
            @test gr.format == T.gfx_fmt_sixel
            @test gr.row == 1
            @test gr.col == 2
            @test gr.width == 10
            @test gr.height == 5
        end

        @testset "6-arg constructor with explicit format" begin
            gr = T.GraphicsRegion(1, 1, 5, 5, UInt8[0x01], T.gfx_fmt_kitty)
            @test gr.format == T.gfx_fmt_kitty
        end

    end

    @testset "GraphicsProtocol enum" begin
        @test T.gfx_none isa T.GraphicsProtocol
        @test T.gfx_sixel isa T.GraphicsProtocol
        @test T.gfx_kitty isa T.GraphicsProtocol
        # Default should be gfx_none in test environment
        @test T.graphics_protocol() == T.gfx_none
    end
