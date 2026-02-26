module TachikomaDemos

using Dates
using Match
using Tachikoma

import Tachikoma: should_quit, update!, view, init!, cleanup!, task_queue

include("theme_demo.jl")
include("rain.jl")
include("dashboard.jl")
include("life.jl")
include("snake.jl")
include("clock.jl")
include("waves.jl")
include("chaos.jl")
include("sysmon.jl")
include("anim_demo.jl")
include("mouse_demo.jl")
include("dotwave.jl")
include("showcase.jl")
include("backend_demo.jl")
include("resize_demo.jl")
include("scrollpane_demo.jl")
include("effects_demo.jl")
include("chart_demo.jl")
include("datatable_demo.jl")
include("form_demo.jl")
include("editor_demo.jl")
include("fps_demo.jl")
include("phylo_demo.jl")
include("clado_demo.jl")
include("sixel_demo.jl")
include("sixel_gallery.jl")
include("async_demo.jl")
include("markdown_demo.jl")
include("launcher.jl")

export demo, rain, dashboard, life, snake, clock, waves, chaos,
       sysmon, anim_demo, mouse_demo, dotwave,
       showcase, backend_demo, resize_demo, scrollpane_demo,
       effects_demo, chart_demo, datatable_demo, form_demo, editor_demo,
       fps_demo, phylo_demo, clado_demo, sixel_demo, sixel_gallery,
       async_demo, markdown_demo, launcher

end
