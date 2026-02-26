module InputTester

using Tachikoma
using MCPRepl.MCPReplBridge: BridgeTool, serve

include("tools.jl")
include("tui.jl")

"""
    run()

Launch the Input Tester TUI with BridgeTools registered.

The TUI shows all keyboard/mouse events in real time while BridgeTools let
an MCP agent query event state programmatically.

Run from a Kitty-capable terminal:
    julia --project=test/input_tester -e 'using InputTester; InputTester.run()'
"""
function run()
    model = InputTesterModel()
    tools = create_tools(model)
    serve(tools=tools, allow_mirror=false, force=true)
    Tachikoma.app(model; fps=60, default_bindings=false)
end

export run

end # module InputTester
