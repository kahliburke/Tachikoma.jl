# Compiled Binaries with juliac

Julia 1.12+ ships with `juliac`, a tool for ahead-of-time (AOT) compilation of Julia programs into standalone native binaries. Tachikoma apps can be compiled this way, producing executables that launch instantly with no JIT warmup.

## Quick Start

Create an entry point file with the `(@main)` macro:

```julia
# myapp.jl
using Tachikoma
@tachikoma_app

@kwdef mutable struct Counter <: Model
    quit::Bool = false
    count::Int = 0
end

should_quit(m::Counter) = m.quit

function update!(m::Counter, e::KeyEvent)
    e.key == :escape && (m.quit = true)
    e.key == :up && (m.count += 1)
    e.key == :down && (m.count -= 1)
end

function view(m::Counter, f::Frame)
    chunks = split_layout(Layout(Vertical, [Percent(100)]), f.area)
    b = Block(title="Counter (↑/↓ to change, Esc to quit)")
    inner = render(b, chunks[1], f.buffer)
    buf = f.buffer
    text = "Count: $(m.count)"
    for (i, ch) in enumerate(text)
        x = inner.x + i - 1
        x <= inner.x + inner.width - 1 || break
        set_char!(buf, x, inner.y, ch, tstyle(:primary))
    end
end

(@main)(ARGS) = (app(Counter()); return 0)
```

Compile it:

```bash
julia --project=. share/julia/juliac/juliac.jl \
    --experimental --output-exe myapp myapp.jl
```

The `--project` flag should point at your project's environment (wherever your `Project.toml` lives). The `juliac.jl` script is bundled with Julia at `share/julia/juliac/juliac.jl` inside your Julia installation directory.

Run the binary:

```bash
./myapp
```

## Requirements

- **Julia 1.12+** — juliac is bundled starting with Julia 1.12.
- **`(@main)(ARGS)` entry point** — juliac requires this macro as the program's entry point. A bare `main()` function won't work.
- **Return an integer** — the `(@main)` function must return an `Int` exit code.

## What You Get

Binaries compiled without `--trim` include the full Julia runtime and weigh approximately 200MB. They link against `libjulia` and use the standard Julia garbage collector. The main advantage is **instant startup** — no compilation latency on first launch.

The `--trim` flag aggressively removes unused code for smaller binaries, but Tachikoma currently produces too many verifier errors with trim enabled. This may improve in future Julia releases.

## Compiling a Multi-Demo Launcher

Existing Tachikoma apps work with juliac without modification — the only thing needed is a thin entry point file. The [TachikomaDemos](https://github.com/kahliburke/Tachikoma.jl/tree/main/demos/TachikomaDemos) launcher includes a demo selection screen, animated logo, and multiple full apps (dashboard, FPS stress test, Game of Life, and more). The entire launcher compiles into a single binary with a two-line wrapper:

```julia
# launcher.jl
using TachikomaDemos
(@main)(ARGS) = (TachikomaDemos.launcher(); return 0)
```

```bash
julia --project=demos/TachikomaDemos \
    share/julia/juliac/juliac.jl \
    --experimental --output-exe tachikoma-demos launcher.jl
```

The resulting `tachikoma-demos` binary launches instantly into the demo picker with all demos fully functional — sixel graphics, animations, async tasks, and all.

Individual demos can be compiled the same way:

```julia
# fps.jl
using TachikomaDemos
(@main)(ARGS) = (TachikomaDemos.fps_demo(); return 0)
```

## Writing juliac-Compatible Code

### Use Variadic ccall for `ioctl`

On macOS/BSD, `ioctl` is a variadic C function. On ARM64 (Apple Silicon), variadic arguments use a different calling convention than fixed arguments. Without `...` in the ccall signature, pointer arguments are passed in the wrong register, causing `EFAULT` or segfaults. Always use the variadic form:

<!-- tachi:noeval -->
```julia
buf = zeros(UInt16, 4)
GC.@preserve buf begin
    p = pointer(buf)
    ret = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}...), fd, request, p)
end
rows, cols, xpixel, ypixel = Int(buf[1]), Int(buf[2]), Int(buf[3]), Int(buf[4])
```

The `Ptr{Cvoid}...` tells Julia this is a variadic argument, ensuring correct ABI on all architectures. Wrap buffers in `GC.@preserve` to prevent the GC from collecting them during the foreign call.

### Avoid `invokelatest`

`Base.invokelatest` prevents juliac from tracing the call graph, which blocks `--trim` and can cause issues at runtime. Tachikoma's API is designed so that all method dispatch is resolved at load time — extension methods from `using` are available before `app()` runs, so `invokelatest` is not needed.

### Multi-Package Projects

If your app depends on packages beyond Tachikoma, point `--project` at the environment that has all dependencies:

```bash
julia --project=demos/TachikomaDemos \
    share/julia/juliac/juliac.jl \
    --experimental --output-exe launcher launcher.jl
```

## Recording

The built-in recording feature (`Ctrl+R` to start/stop) saves `.tach` files from compiled binaries. GIF rendering is not available at runtime in compiled mode because the GIF extension relies on dynamic package loading, but `.tach` files capture the full recording and can be converted to GIF from a normal Julia session:

<!-- tachi:noeval -->
```julia
using Tachikoma
enable_gif()  # loads FreeTypeAbstraction + ColorTypes

w, h, cells, ts, pixels = load_tach("tachikoma_recording.tach")
export_gif_from_snapshots("recording.gif", w, h, cells, ts;
    pixel_snapshots=pixels,
    font_path=discover_mono_fonts()[2].path)  # pick a monospace font
```

A monospace font is required to render text into the GIF. `discover_mono_fonts()` returns all monospace fonts found on your system — index 1 is "(none)", so index 2 onward are real fonts. You can also pass an explicit path like `font_path="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"`.

See [Recording & Export](./recording) for full details on font selection, SVG export, and other options.

## What Works

- **GC** — the compiled binary uses Julia's standard garbage collector. Memory usage is bounded and stable.
- **Multithreading** — `Threads.@spawn` and all of Tachikoma's async task infrastructure work correctly.
- **Sixel graphics** — pixel rendering, braille canvas, and sixel image output all function in compiled binaries.
- **Terminal detection** — cell size detection via ioctl, escape sequences, and sixel geometry all work.
- **All widgets** — the full widget library renders correctly in compiled mode.

## Notes

- Compilation takes several minutes for a full Tachikoma app. You only pay this cost once per build.
- Linker warnings like `ignoring duplicate libraries: '-ljulia'` are harmless and can be ignored.
- The `--trim` flag for smaller binaries is not yet compatible with Tachikoma. This is expected to improve in future Julia releases.
