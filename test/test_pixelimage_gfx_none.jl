using Tachikoma
const T = Tachikoma

println("Terminal: ", get(ENV, "TERM_PROGRAM", get(ENV, "TERM", "unknown")))
println()

T.detect_cell_pixels!()

println("Cell pixels:   ", T.CELL_PX[])
println("Text area px:  ", T.TEXT_AREA_PX[])
println("Sixel area px: ", T.SIXEL_AREA_PX[])
println()

# Kitty graphics probe (needs raw mode + stdin reading)
T.set_raw_mode!(true)
Base.start_reading(stdin)
kitty_gfx = T._detect_kitty_graphics!(stdout)
kitty_kbd = T._detect_kitty_keyboard!(stdout)
Base.stop_reading(stdin)
T.set_raw_mode!(false)

println("Kitty graphics: ", kitty_gfx)
println("Kitty keyboard: ", kitty_kbd)
println()

proto = kitty_gfx ? T.gfx_kitty : T.SIXEL_AREA_PX[].w > 0 ? T.gfx_sixel : T.gfx_none
println("Would use: ", proto)
