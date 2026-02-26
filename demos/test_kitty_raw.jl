#!/usr/bin/env julia
# Kitty shm verification — all 3 squares should be visible
# Run: julia --project demos/test_kitty_raw.jl

using Tachikoma
const T = Tachikoma

# ── Test 1: encode_kitty shm (RED) ─────────────────────────────────
println("Test 1: encode_kitty shm (should be RED)")
T._KITTY_SHM_AVAILABLE[] = nothing
red_pixels = fill(T.ColorRGB(0xff, 0x00, 0x00), 60, 60)
data1 = T.encode_kitty(red_pixels; cols=8, rows=4)
str1 = String(copy(data1))
write(stdout, data1); flush(stdout)
println("  path: ", occursin("t=s", str1) ? "shm" : "inline")
println()

# ── Test 2: encode_kitty inline (BLUE) ────────────────────────────
println("Test 2: encode_kitty inline (should be BLUE)")
T._KITTY_SHM_AVAILABLE[] = false
blue_pixels = fill(T.ColorRGB(0x00, 0x00, 0xff), 60, 60)
data2 = T.encode_kitty(blue_pixels; cols=8, rows=4)
write(stdout, data2); flush(stdout)
T._KITTY_SHM_AVAILABLE[] = nothing
println()

# ── Test 3: encode_kitty shm (GREEN) ──────────────────────────────
println("Test 3: encode_kitty shm (should be GREEN)")
T._KITTY_SHM_AVAILABLE[] = nothing
green_pixels = fill(T.ColorRGB(0x00, 0xff, 0x00), 60, 60)
data3 = T.encode_kitty(green_pixels; cols=8, rows=4)
str3 = String(copy(data3))
write(stdout, data3); flush(stdout)
println("  path: ", occursin("t=s", str3) ? "shm" : "inline")
println()

println("RED=shm  BLUE=inline  GREEN=shm")
println("All 3 colored squares should be visible.")
