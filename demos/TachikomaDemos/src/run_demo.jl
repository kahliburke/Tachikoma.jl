# run_demo.jl -- one launcher, two backends.
#
# Every demo ends on `app(SomeModel(); fps = n)`. Routing that one call
# through `run_demo` gives every demo a browser option for free: `:console`
# hands the model to `app` as before, `:webterminal` serves it over a WebSocket
# through DualUIWeb, and the demo body never has to know which.
#
# The web half lives in a package extension (TachikomaDemosHTTPExt),
# loaded only when HTTP is present. Until then `:webterminal` fails with a
# sentence, so the demos still run with nothing but Tachikoma.

"""
The backend a bare `run_demo(model)` uses when none is passed. Set for the
duration of a call by the function form of `run_demo` (and by `launcher`);
a `Ref` rather than a scoped value so the demos stay on Julia 1.10.
Internal.
"""
const _DEMO_BACKEND = Ref(:console)

"""
The port a `:webterminal` demo binds, set by the function form of `run_demo` so it
reaches the server without passing through the demo function (which does not
take a `port`). Internal.
"""
const _DEMO_PORT = Ref(8000)

"""
    _demo_web(model; kwargs...)

Serve `model` in the browser. This is the `::Any` FALLBACK -- the error
shown when DualUIWeb is not loaded. The extension ADDS a more specific
`::Model` method (so it never overwrites this one, which precompilation
forbids), and that method wins whenever DualUIWeb is present. Internal.
"""
_demo_web(::Any; kwargs...) = error(
    "run_demo(...; backend = :webterminal) needs HTTP: `using HTTP`. " *
    "It serves the demo in the browser over a WebSocket.")

"""
    run_demo(model::Model; fps = 60, backend = <current>, kwargs...)

Run a demo's model on `backend`: `:console` (the default) hands it to
[`app`](@ref); `:webterminal` serves it in the browser over HTTP/WebSockets. This is
the one call every demo ends on, so every demo gains a web option.

The default `backend` is whatever the enclosing `run_demo(demo_function;
backend = ...)` or `launcher(; backend = ...)` set, so a demo body can just
write `run_demo(MyModel(); fps = 30)` and inherit the caller's choice.
"""
function run_demo(model::Model; fps::Int = 60,
                  backend::Symbol = _DEMO_BACKEND[], kwargs...)
    backend === :webterminal && return _demo_web(model; port = _DEMO_PORT[], kwargs...)
    return app(model; fps = fps, kwargs...)
end

"""
    run_demo(demo::Function, args...; backend = :console, kwargs...)

Run a demo FUNCTION on `backend`. Sets the backend for the demo's own
`run_demo(model)` call, invokes it, and restores the previous default.

    run_demo(fps_demo; backend = :webterminal)             # in the browser
    run_demo(fps_demo; backend = :webterminal, port = 9000)
    run_demo(snake)                                # in the terminal

`port` is a web option, so it is captured here and handed to the server
rather than forwarded to `demo` (which takes no `port`). Everything else in
`args`/`kwargs` goes to `demo`.
"""
function run_demo(demo::Function, args...; backend::Symbol = :console,
                  port::Int = _DEMO_PORT[], kwargs...)
    old_b, old_p = _DEMO_BACKEND[], _DEMO_PORT[]
    _DEMO_BACKEND[], _DEMO_PORT[] = backend, port
    try
        return demo(args...; kwargs...)
    finally
        _DEMO_BACKEND[], _DEMO_PORT[] = old_b, old_p
    end
end

"""
    browser(demo, args...; kwargs...)

Shorthand for `run_demo(demo; backend = :webterminal, ...)`: run a demo in the
browser.

    browser(fps_demo)
"""
browser(demo::Function, args...; kwargs...) =
    run_demo(demo, args...; backend = :webterminal, kwargs...)
