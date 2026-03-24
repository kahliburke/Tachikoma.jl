# ═══════════════════════════════════════════════════════════════════════
# ColorTypes Extension Demo ── verify ColorTypes.jl interop
# ═══════════════════════════════════════════════════════════════════════

using ColorTypes
using ColorTypes.FixedPointNumbers: N0f8

struct ColorTest
    desc::String
    ok::Bool
    swatch::Union{ColorRGB, Nothing}
end

@kwdef mutable struct ColorTypesModel <: Model
    quit::Bool = false
    tick::Int = 0
    results::Vector{ColorTest} = ColorTest[]
    ran::Bool = false
end

should_quit(m::ColorTypesModel) = m.quit

function update!(m::ColorTypesModel, evt::KeyEvent)
    (evt.key == :escape || (evt.key == :char && evt.char == 'q')) && (m.quit = true)
end

function _run_tests!(m::ColorTypesModel)
    m.ran && return
    m.ran = true
    t = m.results

    # to_rgb: RGB{N0f8} → ColorRGB
    try
        c = to_rgb(RGB{N0f8}(1.0, 0.0, 0.0))
        push!(t, ColorTest("to_rgb(RGB{N0f8}(1,0,0)) → ($(c.r),$(c.g),$(c.b))",
                            c == ColorRGB(0xff, 0x00, 0x00), c))
    catch e
        push!(t, ColorTest("to_rgb(RGB{N0f8}) → $(sprint(showerror, e))", false, nothing))
    end

    # to_rgb: RGB{Float64} → ColorRGB
    try
        c = to_rgb(RGB(0.5, 0.25, 0.75))
        push!(t, ColorTest("to_rgb(RGB(0.5,0.25,0.75)) → ($(c.r),$(c.g),$(c.b))",
                            c.r == 128 && c.g == 64 && c.b == 191, c))
    catch e
        push!(t, ColorTest("to_rgb(RGB{Float64}) → $(sprint(showerror, e))", false, nothing))
    end

    # to_rgba: RGBA{N0f8} → ColorRGBA
    try
        c = to_rgba(RGBA{N0f8}(0.0, 1.0, 0.0, 0.5))
        push!(t, ColorTest("to_rgba(RGBA(0,1,0,0.5)) → ($(c.r),$(c.g),$(c.b),a=$(c.a))",
                            c.g == 0xff && c.a == 0x80, ColorRGB(c.r, c.g, c.b)))
    catch e
        push!(t, ColorTest("to_rgba(RGBA{N0f8}) → $(sprint(showerror, e))", false, nothing))
    end

    # to_rgba: RGB → ColorRGBA (alpha=0xff)
    try
        c = to_rgba(RGB{N0f8}(0.0, 0.5, 1.0))
        push!(t, ColorTest("to_rgba(RGB(0,0.5,1)) → a=$(c.a)",
                            c.a == 0xff, ColorRGB(c.r, c.g, c.b)))
    catch e
        push!(t, ColorTest("to_rgba(RGB) → $(sprint(showerror, e))", false, nothing))
    end

    # to_colortype: ColorRGB → RGB{N0f8}
    try
        orig = ColorRGB(0xff, 0x80, 0x00)
        c = to_colortype(orig)
        push!(t, ColorTest("to_colortype(ColorRGB(255,128,0)) → $(c)",
                            c == RGB{N0f8}(1.0, reinterpret(N0f8, 0x80), 0.0), orig))
    catch e
        push!(t, ColorTest("to_colortype(ColorRGB) → $(sprint(showerror, e))", false, nothing))
    end

    # to_colortype: ColorRGBA → RGBA{N0f8}
    try
        orig = ColorRGBA(0x40, 0xc0, 0xff, 0x80)
        c = to_colortype(orig)
        push!(t, ColorTest("to_colortype(ColorRGBA(64,192,255,128)) → $(c)",
                            c.g == reinterpret(N0f8, 0xc0), ColorRGB(orig.r, orig.g, orig.b)))
    catch e
        push!(t, ColorTest("to_colortype(ColorRGBA) → $(sprint(showerror, e))", false, nothing))
    end

    # Roundtrip: ColorRGB → RGB{N0f8} → ColorRGB
    try
        orig = ColorRGB(0xab, 0xcd, 0xef)
        back = to_rgb(to_colortype(orig))
        push!(t, ColorTest("Roundtrip (0xAB,0xCD,0xEF) → RGB{N0f8} → ColorRGB",
                            back == orig, orig))
    catch e
        push!(t, ColorTest("Roundtrip → $(sprint(showerror, e))", false, nothing))
    end

    # Roundtrip: ColorRGBA → RGBA{N0f8} → ColorRGBA
    try
        orig = ColorRGBA(0xde, 0xad, 0xbe, 0xef)
        back = to_rgba(to_colortype(orig))
        push!(t, ColorTest("Roundtrip RGBA (0xDE,0xAD,0xBE,a=0xEF)",
                            back == orig, ColorRGB(orig.r, orig.g, orig.b)))
    catch e
        push!(t, ColorTest("Roundtrip RGBA → $(sprint(showerror, e))", false, nothing))
    end
end

function view(m::ColorTypesModel, f::Frame)
    m.tick += 1
    _run_tests!(m)

    buf = f.buffer
    area = f.area

    render(Block(title="ColorTypes Extension"), area, buf)
    content = inner(area)

    passed = count(t -> t.ok, m.results)
    total = length(m.results)
    all_pass = passed == total

    for (i, ct) in enumerate(m.results)
        y = content.y + i - 1
        y > bottom(content) && break

        # Status icon
        icon = ct.ok ? "PASS" : "FAIL"
        s = ct.ok ? tstyle(:success) : tstyle(:error, bold=true)
        set_string!(buf, content.x, y, " $(icon) ", s)

        # Color swatch (2 chars wide)
        if ct.swatch !== nothing
            sw = ct.swatch
            swatch_s = Style(fg=sw, bg=sw)
            set_string!(buf, content.x + 6, y, "  ", swatch_s)
            set_string!(buf, content.x + 9, y, ct.desc, tstyle(:text))
        else
            set_string!(buf, content.x + 6, y, ct.desc, tstyle(:text))
        end
    end

    summary_y = content.y + total + 1
    if summary_y <= bottom(content)
        msg = all_pass ? "All $total tests passed!" : "$passed/$total passed"
        s = all_pass ? tstyle(:success, bold=true) : tstyle(:error, bold=true)
        set_string!(buf, content.x, summary_y, msg, s)
    end

    footer_y = content.y + total + 3
    if footer_y <= bottom(content)
        set_string!(buf, content.x, footer_y, "Press [q] or [Esc] to exit", tstyle(:text_dim))
    end
end

colortypes_demo() = app(ColorTypesModel(); fps=10)
