# ═══════════════════════════════════════════════════════════════════════
# Calendar ── compact month calendar view
# ═══════════════════════════════════════════════════════════════════════

using Dates

struct Calendar
    year::Int
    month::Int
    today::Int                     # day to highlight (0 = none)
    marked::Set{Int}               # additional highlighted days
    block::Union{Block, Nothing}
    header_style::Style
    day_style::Style
    today_style::Style
    marked_style::Style
    dim_style::Style
end

function Calendar(year::Int, month::Int;
    today=0,
    marked=Set{Int}(),
    block=nothing,
    header_style=tstyle(:title, bold=true),
    day_style=tstyle(:text),
    today_style=tstyle(:accent, bold=true),
    marked_style=tstyle(:warning),
    dim_style=tstyle(:text_dim, dim=true),
)
    Calendar(year, month, today, Set{Int}(marked), block,
             header_style, day_style, today_style,
             marked_style, dim_style)
end

function Calendar(; kwargs...)
    d = Dates.today()
    Calendar(Dates.year(d), Dates.month(d);
             today=Dates.day(d), kwargs...)
end

intrinsic_size(::Calendar) = (22, 9)

function render(cal::Calendar, rect::Rect, buf::Buffer)
    content = if cal.block !== nothing
        render(cal.block, rect, buf)
    else
        rect
    end
    (content.width < 22 || content.height < 2) && return

    y = content.y
    x0 = content.x

    # Month/year header
    header = Dates.monthname(cal.month) * " " * string(cal.year)
    hx = center(content, length(header), 1).x
    set_string!(buf, hx, y, header, cal.header_style)
    y += 1

    # Day-of-week header
    y > bottom(content) && return
    dow = ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
    for (i, d) in enumerate(dow)
        set_string!(buf, x0 + (i - 1) * 3, y, d, cal.dim_style)
    end
    y += 1

    # Calendar grid
    first_day = Date(cal.year, cal.month, 1)
    # Monday = 1 ... Sunday = 7
    start_dow = Dates.dayofweek(first_day)
    days_in_month = Dates.daysinmonth(first_day)

    col = start_dow - 1  # 0-based column (Mon=0)
    for day in 1:days_in_month
        y > bottom(content) && break
        cx = x0 + col * 3

        style = if day == cal.today
            cal.today_style
        elseif day in cal.marked
            cal.marked_style
        else
            cal.day_style
        end

        ds = lpad(string(day), 2)
        set_string!(buf, cx, y, ds, style)

        col += 1
        if col >= 7
            col = 0
            y += 1
        end
    end
end
