module TachikomaDemosHTTPExt

import TachikomaDemos: _demo_web
import HTTP
import Tachikoma

const HTML_PAGE = """
<!DOCTYPE html>
<html>
  <head>
    <title>Tachikoma Web</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm/css/xterm.css" />
    <script src="https://cdn.jsdelivr.net/npm/xterm/lib/xterm.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit/lib/xterm-addon-fit.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-image/lib/xterm-addon-image.js"></script>
    <style>
      body { margin: 0; padding: 0; background-color: black; height: 100vh; overflow: hidden; }
      #terminal-container { width: 100%; height: 100%; }
      .xterm-viewport { overflow: hidden !important; }
      ::-webkit-scrollbar { display: none; }
    </style>
  </head>
  <body>
    <div id="terminal-container"></div>
    <script>
      const term = new Terminal({
        cursorBlink: true,
        macOptionIsMeta: true,
        scrollback: 0
      });
      const fitAddon = new FitAddon.FitAddon();
      const imageAddon = new ImageAddon.ImageAddon();
      term.loadAddon(fitAddon);
      term.loadAddon(imageAddon);
      term.open(document.getElementById('terminal-container'));
      fitAddon.fit();

      let ws;
      function connect() {
        const wsProtocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = wsProtocol + '//' + location.host + '/ws';
        ws = new WebSocket(wsUrl);
        ws.binaryType = 'arraybuffer';

        ws.onopen = () => {
          term.reset();
          ws.send("R " + term.cols + " " + term.rows);
          // Only attach handlers once
          if (!window._termHandlersAttached) {
            term.onData(data => {
              if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send("D" + data);
              }
            });
            term.attachCustomKeyEventHandler(e => {
              const isHelp = e.key === '?' || e.key === '/' || (e.shiftKey && e.code === 'Comma') || e.code === 'Slash';
              if ((e.ctrlKey || e.metaKey) && isHelp) {
                if (e.type === 'keydown') {
                  if (ws && ws.readyState === WebSocket.OPEN) {
                    ws.send("D\x1f");
                  }
                }
                return false;
              }
              return true;
            });
            window.addEventListener('resize', () => {
              fitAddon.fit();
              if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send("R " + term.cols + " " + term.rows);
              }
            });
            window._termHandlersAttached = true;
          }
        };

        ws.onmessage = (evt) => {
          if (typeof evt.data === 'string') {
            term.write(evt.data);
          } else {
            term.write(new Uint8Array(evt.data));
          }
        };

        ws.onclose = () => {
          setTimeout(connect, 200);
        };
      }
      connect();
    </script>
  </body>
</html>
"""

struct WSIO <: IO
    ws::HTTP.WebSockets.WebSocket
end
Base.write(io::WSIO, b::UInt8) = write(io, [b])
Base.write(io::WSIO, a::Vector{UInt8}) = (HTTP.WebSockets.send(io.ws, a); length(a))
Base.write(io::WSIO, s::String) = (HTTP.WebSockets.send(io.ws, s); sizeof(s))
Base.flush(io::WSIO) = nothing
Base.isopen(io::WSIO) = HTTP.WebSockets.isopen(io.ws)
Base.close(io::WSIO) = close(io.ws)

function _demo_web(model::Tachikoma.Model; port::Int = 8000, kwargs...)
    live_server = Ref{Any}(nothing)
    app_task = Ref{Task}()
    
    server = HTTP.listen!("127.0.0.1", port) do http
        if HTTP.WebSockets.isupgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                out_io = WSIO(ws)
                
                # Input pipe
                inp = Base.BufferStream()
                
                live_term = Ref{Any}(nothing)
                
                app_task[] = Threads.@spawn begin
                    try
                        println("Starting app task for model: ", typeof(model))
                        Tachikoma.app(model; io=out_io, input=inp, tty_size=(rows=24, cols=80), on_terminal = t -> (live_term[] = t), kwargs...)
                        println("App task finished for model: ", typeof(model))
                    catch e
                        e isa InterruptException || @error "App error" exception=(e, catch_backtrace())
                    finally
                        try close(inp) catch end
                        try close(ws) catch end
                        # If the app genuinely wanted to quit (e.g. Esc, or a demo was selected),
                        # close the server so the caller (like `launcher`) can proceed.
                        # Otherwise (e.g. user refreshed page), leave the server running to accept reconnects.
                        try
                            if Base.invokelatest(Tachikoma.should_quit, model)
                                println("Model wants to quit. Closing server.")
                                @async close(live_server[])
                            else
                                println("Model didn't want to quit (connection lost). Server stays up.")
                            end
                        catch e
                            @error "Error in should_quit check" exception=(e, catch_backtrace())
                        end
                    end
                end

                # Read from websocket
                try
                    for msg in ws
                        s = String(msg)
                        if startswith(s, "R ")
                            println("Received resize: ", s)
                            parts = split(s, ' ')
                            if length(parts) == 3
                                cols = parse(Int, parts[2])
                                rows = parse(Int, parts[3])
                                if live_term[] !== nothing
                                    Tachikoma.set_size!(live_term[], (rows=rows, cols=cols))
                                end
                            end
                        elseif startswith(s, "D")
                            write(inp, s[2:end])
                            # BufferStream doesn't need flush, but we can call it if needed, wait, BufferStream doesn't have flush, wait, yes it does?
                            # flush(inp)
                        end
                    end
                catch e
                    e isa EOFError || e isa Base.IOError || @error "WS error" exception=(e, catch_backtrace())
                finally
                    println("Websocket closed.")
                    try close(inp) catch end
                    # Avoid throwto which can deadlock with close(server)
                    # The app task will eventually exit when it reads EOF from inp
                end
            end
        else
            HTTP.setstatus(http, 200)
            HTTP.setheader(http, "Content-Type" => "text/html")
            HTTP.startwrite(http)
            write(http, HTML_PAGE)
        end
    end
    
    live_server[] = server
    
    println("Demo in the browser at http://127.0.0.1:$port")
    println("Ctrl-C to stop.")
    try
        wait(server)
    catch e
        e isa InterruptException || rethrow()
    finally
        close(server)
    end
    return nothing
end

end # module
