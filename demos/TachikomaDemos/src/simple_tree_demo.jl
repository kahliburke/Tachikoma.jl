# ═══════════════════════════════════════════════════════════════════════
# Simple Tree Demo ── debug of TreeView, displaying node info and row
# 
# arrow keys to navigate, [q] quit
# ═══════════════════════════════════════════════════════════════════════

using Base: @kwdef


function build_tree()
    root = TreeNode("System", 
        [
            TreeNode("Component", 
                [TreeNode("thing"), TreeNode("A"; content=0x32ab), TreeNode("C"; content="content of C")]
            ), 
            TreeNode("Component", 
                [TreeNode("thing"; content="A string of content!"), TreeNode("B"), TreeNode("D"; content="content of D")]
            ), 
            TreeNode("Another component", 
                [TreeNode("thing"; content=-3.4e4), TreeNode("E"; content=Dict("a"=>1,"b"=>2, "c"=>3))]
            )
        ]
    )
    return TreeView(root; indent=4, connector_style=tstyle(:border, dim=true), show_root=false)
end

@kwdef mutable struct TreeState <: Model
    quit::Bool = false
    do_modal::Bool = false
    tick::UInt = 0
    counter::UInt64 = 0
    tree::TreeView = build_tree()
    outer_layout::ResizableLayout = ResizableLayout(Horizontal, [Fixed(30), Fill()])
end

should_quit(m::TreeState) = m.quit

function update!(m::TreeState, event::KeyEvent)
    if event.key == :char && event.char == 'q'
        m.quit = true
        return
    end
    handle_key!(m.tree, event)
end

function update!(m::TreeState, event::MouseEvent)
    handle_mouse!(m.tree, event)
end

function view(m::TreeState, f::Frame)
    m.tick += 1
    rects = split_layout(m.outer_layout, f.area)

    innerL = render(Block(title="Tree", box=BOX_PLAIN), rects[1], f.buffer)
    innerR = render(Block(title="Debug", box=BOX_PLAIN), rects[2], f.buffer)

    node_selection = selected_node(m.tree)
    content_selection = isnothing(node_selection) ? nothing : node_selection.content
    spn = Paragraph("value: $(value(m.tree))\n\nselected node: $(node_selection)\n\nnode content: $(content_selection)", wrap=char_wrap)

    render(m.tree, innerL, f.buffer)
    render(spn, innerR, f.buffer)
end

function simple_tree_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    return app(TreeState(); fps=30)
end
