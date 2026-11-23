# ═══════════════════════════════════════════════════════════════════════
# Pipeline Graph ── DAGView with a live CI run, a workflow, and a large graph
#
# [1] CI pipeline: jobs start when their dependencies finish; some fail and
#     skip everything downstream. [r] restarts the run.
# [2] Workflow: nodes with kind icons, and dashed links to a shared model node.
# [3] Large graph: a generated DAG for trying zoom, scroll and pan.
#
# Hover a node for its tooltip, click or use arrows to select, +/- or
# Ctrl+wheel to zoom, drag empty space to pan.
# ═══════════════════════════════════════════════════════════════════════

# ── CI pipeline: a simulated run ──

const _CI_JOBS = [
    # id, label, deps, duration (s), failure chance
    (:checkout, "checkout",      Symbol[],                            2, 0.0),
    (:deps,     "install deps",  [:checkout],                         6, 0.0),
    (:lint,     "lint",          [:checkout],                         3, 0.15),
    (:build,    "build",         [:deps],                             8, 0.05),
    (:fixtures, "fetch fixtures", Symbol[],                           4, 0.0),
    (:unit,     "unit tests",    [:build],                            9, 0.1),
    (:integ,    "integration",   [:build, :fixtures],                 12, 0.3),
    (:docs,     "docs",          [:build],                            5, 0.0),
    (:package,  "package",       [:unit, :integ, :lint],              4, 0.0),
    (:deploy,   "deploy staging", [:package, :docs],                  5, 0.05),
    (:smoke,    "smoke tests",   [:deploy],                           4, 0.1),
]

mutable struct _CIJob
    duration::Float64
    fail::Float64
    started::Float64
    elapsed::Float64
    log::Vector{String}
end

_fmt_secs(s) = s < 60 ? "$(round(Int, s))s" : "$(floor(Int, s ÷ 60))m $(lpad(round(Int, s % 60), 2, '0'))s"

function _ci_nodes()
    [DAGNode(id, label; deps, detail="waiting for: " * (isempty(deps) ? "nothing" : join(deps, ", ")))
     for (id, label, deps, _, _) in _CI_JOBS]
end

function _ci_jobs()
    Dict(id => _CIJob(dur * (0.7 + 0.6rand()), p, 0.0, 0.0, String[])
         for (id, _, _, dur, p) in _CI_JOBS)
end

const _CI_LOG_LINES = Dict(
    :checkout => ["fetching origin", "HEAD is now at 3f2a9c1"],
    :deps     => ["resolving 142 packages", "downloading artifacts", "precompiling"],
    :lint     => ["checking 87 files", "formatting ok"],
    :build    => ["compiling core", "compiling plugins", "linking"],
    :fixtures => ["pulling fixtures bundle", "unpacking 3.1k files"],
    :unit     => ["running 980 tests", "412/980 passed", "855/980 passed"],
    :integ    => ["starting database", "running migrations", "running 64 scenarios"],
    :docs     => ["building reference pages", "checking links"],
    :package  => ["bundling", "signing artifacts"],
    :deploy   => ["uploading release", "rolling restart 3/3"],
    :smoke    => ["probing health endpoints", "checking login flow"],
)

# Advance the simulated run to time `t` (seconds).
function _ci_step!(dv::DAGView, jobs, t)
    for nd in dv.nodes
        j = jobs[nd.id]
        if nd.status == task_pending
            dstat = [dv[d].status for d in nd.deps]
            if any(s -> s in (task_error, task_skipped), dstat)
                nd.status = task_skipped
                nd.subtitle = "skipped"
                nd.detail = "skipped: an upstream job failed"
            elseif all(==(task_done), dstat)
                nd.status = task_running
                j.started = t
            end
        elseif nd.status == task_running
            j.elapsed = t - j.started
            lines = _CI_LOG_LINES[nd.id]
            k = clamp(ceil(Int, j.elapsed / j.duration * length(lines)), 1, length(lines))
            nd.subtitle = _fmt_secs(j.elapsed)
            nd.detail = join(lines[1:k], "\n")
            if j.elapsed >= j.duration
                if rand() < j.fail
                    nd.status = task_error
                    nd.detail = join(lines, "\n") * "\nerror: exited with status 1"
                else
                    nd.status = task_done
                    nd.detail = join(lines, "\n") * "\nfinished in " * _fmt_secs(j.duration)
                end
                nd.subtitle = _fmt_secs(j.duration)
            end
        end
    end
end

# ── Workflow: icons and dashed links ──

function _workflow_nodes()
    [
        DAGNode(:trigger, "Schedule"; icon='⏰', status=task_done, subtitle="every day 08:00",
                detail="Cron trigger.\nNext run: tomorrow 08:00"),
        DAGNode(:settings, "Settings"; icon='✎', deps=[:trigger], status=task_done,
                subtitle="candidates=3", detail="Static values passed downstream."),
        DAGNode(:history, "Push history"; icon='⚡', deps=[:settings], status=task_done,
                subtitle="getAll: row", detail="Reads the last 30 days of posted items."),
        DAGNode(:trending, "Trending feed"; icon='⚡', deps=[:settings], status=task_done,
                subtitle="getAll: row", detail="Fetches the last 24h of trending items."),
        DAGNode(:filter, "Filter seen"; icon='⧉', deps=[:history, :trending], status=task_done,
                detail="Drops anything already posted."),
        DAGNode(:rank, "Rank top"; icon='⧉', deps=[:filter], status=task_done,
                detail="Scores by stars/day and keeps the top N."),
        DAGNode(:fetch, "Fetch README"; icon='◎', deps=[:rank], status=task_done,
                subtitle="HTTP GET", detail="GET /readme for each candidate."),
        DAGNode(:model, "Chat model"; icon='✦', status=task_done, subtitle="shared",
                detail="Language model used by the summarize, describe and translate steps.\nDrawn with dashed links: they use it, they don't wait on it."),
        DAGNode(:summarize, "Summarize"; icon='∞', deps=[:fetch], links=[:model],
                status=task_done, detail="One paragraph per item."),
        DAGNode(:merge, "Merge markdown"; icon='⧉', deps=[:summarize], status=task_done),
        DAGNode(:save, "Save posted"; icon='⚡', deps=[:summarize], status=task_done,
                subtitle="create: row"),
        DAGNode(:html, "Markdown→HTML"; icon='M', deps=[:merge], status=task_running),
        DAGNode(:email, "Send email"; icon='✉', deps=[:html], status=task_pending),
        DAGNode(:describe, "Describe"; icon='∞', deps=[:merge], links=[:model],
                status=task_running, detail="Writing release description…"),
        DAGNode(:create, "Create file"; icon='⎇', deps=[:describe], status=task_pending,
                subtitle="create: file"),
        DAGNode(:translate, "Translate"; icon='∞', deps=[:merge], links=[:model],
                status=task_error, detail="error: rate limited (429)\nretry in 30s"),
        DAGNode(:describe_t, "Describe (tr)"; icon='∞', deps=[:translate], links=[:model],
                status=task_skipped),
        DAGNode(:create_t, "Create file (tr)"; icon='⎇', deps=[:describe_t], status=task_skipped),
    ]
end

# ── Large generated graph ──

function _big_nodes(; layers=9, width=7, seed=7)
    rng_state = seed
    rnd() = (rng_state = (rng_state * 1103515245 + 12345) % 2^31; rng_state / 2^31)
    nodes = DAGNode[]
    prev = Symbol[]
    for l in 1:layers
        cur = Symbol[]
        n = max(1, round(Int, width * (0.4 + 0.6rnd())))
        for k in 1:n
            id = Symbol("n$(l)_$(k)")
            deps = Symbol[]
            if !isempty(prev)
                for _ in 1:(1 + round(Int, 1.4rnd()))
                    d = prev[1 + floor(Int, rnd() * length(prev))]
                    d in deps || push!(deps, d)
                end
            end
            st = l <= 3 ? task_done : l == 4 ? (rnd() < 0.5 ? task_running : task_done) : task_pending
            push!(nodes, DAGNode(id, "stage $(l).$(k)"; deps, status=st,
                                 detail="layer $l, item $k\ndepends on: " *
                                        (isempty(deps) ? "nothing" : join(deps, ", "))))
            push!(cur, id)
        end
        prev = cur
    end
    nodes
end

# ── Model ──

@kwdef mutable struct DAGDemoModel <: Model
    quit::Bool = false
    tick::Int = 0
    mode::Int = 1
    ci::DAGView = DAGView(_ci_nodes(); selected=:checkout, focused=true)
    jobs::Dict{Symbol,_CIJob} = _ci_jobs()
    run_start::Float64 = time()
    paused_at::Union{Float64,Nothing} = nothing
    workflow::DAGView = DAGView(_workflow_nodes(); selected=:summarize, focused=true)
    big::DAGView = DAGView(_big_nodes(); selected=:n1_1, focused=true, zoom=2)
end

should_quit(m::DAGDemoModel) = m.quit

_dag_current(m::DAGDemoModel) = m.mode == 1 ? m.ci : m.mode == 2 ? m.workflow : m.big

function _ci_restart!(m::DAGDemoModel)
    sel = m.ci.selected
    m.ci.nodes = _ci_nodes()
    m.ci.selected = sel
    m.jobs = _ci_jobs()
    m.run_start = time()
    m.paused_at = nothing
end

function update!(m::DAGDemoModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end
    if evt.key == :char
        c = evt.char
        if c in ('1', '2', '3')
            m.mode = c - '0'
            return
        elseif c == 'r' && m.mode == 1
            _ci_restart!(m)
            return
        elseif c == ' ' && m.mode == 1
            if m.paused_at === nothing
                m.paused_at = time()
            else
                m.run_start += time() - m.paused_at
                m.paused_at = nothing
            end
            return
        elseif c == 'l'
            dv = _dag_current(m)
            dv.highlight_lineage = !dv.highlight_lineage
            return
        end
    end
    handle_key!(_dag_current(m), evt)
end

function update!(m::DAGDemoModel, evt::MouseEvent)
    handle_mouse!(_dag_current(m), evt)
end

function _dag_detail_spans(dv::DAGView)
    nd = selected_node(dv)
    nd === nothing && return [Span("Select a node.", tstyle(:text_dim))]
    deps = [dv[d].label for d in nd.deps]
    links = [dv[d].label for d in nd.links]
    users = [x.label for x in dv.nodes if nd.id in x.deps]
    linked = [x.label for x in dv.nodes if nd.id in x.links]
    glyph = nd.status == task_done ? ("✓ done", :success) :
            nd.status == task_error ? ("✗ failed", :error) :
            nd.status == task_running ? ("● running", :primary) :
            nd.status == task_skipped ? ("⊘ skipped", :text_dim) : ("○ pending", :text_dim)
    sp = Span[
        Span(nd.label, tstyle(:title, bold=true)), Span("\n"),
        Span(glyph[1], tstyle(glyph[2], bold=true)),
        Span(isempty(nd.subtitle) ? "" : "  " * nd.subtitle, tstyle(:text_dim)), Span("\n\n"),
    ]
    section(name, xs) = isempty(xs) || append!(sp, [Span(name * "\n", tstyle(:primary, bold=true)),
                                                    Span(join(("  " * x for x in xs), "\n") * "\n\n", tstyle(:text))])
    section("needs", deps)
    section("uses", links)
    section("needed by", users)
    section("used by", linked)
    if nd.detail !== nothing
        push!(sp, Span("detail\n", tstyle(:primary, bold=true)))
        push!(sp, Span(string(nd.detail), tstyle(:text_dim)))
    end
    sp
end

function view(m::DAGDemoModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    if m.mode == 1
        t = (m.paused_at === nothing ? time() : m.paused_at) - m.run_start
        _ci_step!(m.ci, m.jobs, t)
    end
    dv = _dag_current(m)
    dv.tick = m.tick

    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(1)]), f.area)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(34)]), rows[2])

    # Header: mode tabs
    tabs = ["1 CI pipeline", "2 Workflow", "3 Large graph"]
    x = rows[1].x + 1
    set_string!(buf, x, rows[1].y, "Pipeline Graph", tstyle(:title, bold=true))
    x += 17
    for (i, t) in enumerate(tabs)
        st = i == m.mode ? tstyle(:accent, bold=true, underline=true) : tstyle(:text_dim)
        set_string!(buf, x, rows[1].y, t, st)
        x += length(t) + 3
    end

    title = if m.mode == 1
        t = (m.paused_at === nothing ? time() : m.paused_at) - m.run_start
        (m.paused_at === nothing ? "" : "paused · ") * "t+" * _fmt_secs(t)
    else
        "$(length(dv.nodes)) nodes"
    end
    dv.block = Block(title="DAGView", title_right="zoom $(dv.zoom) · " * title,
                     border_style=tstyle(:border_focus))
    render(dv, cols[1], buf)

    # Side panel: details of the selected node
    side = render(Block(title="Selected", border_style=tstyle(:border)), cols[2], buf)
    render(Paragraph(_dag_detail_spans(dv); wrap=word_wrap),
           Rect(side.x + 1, side.y, max(0, side.width - 2), side.height), buf)

    keys = m.mode == 1 ? "  [r]estart [space] pause" : ""
    render(StatusBar(
        left=[Span(" ←→↑↓ navigate  +/- zoom  [l]ineage  hover: details  drag: pan" * keys,
                   tstyle(:text_dim))],
        right=[Span("[1-3] graph  [q] quit ", tstyle(:text_dim))],
    ), rows[3], buf)
end

function dag_demo(; theme_name=nothing)
    theme_name !== nothing && set_theme!(theme_name)
    app(DAGDemoModel(); fps=30)
end
