"""
Hourly dispatch stacks, built from `results_output_Operational.csv`.

This is the one result table the dashboard previously ignored, and it is by far
the largest: `europe_v51` at `run_2060` is 49 nodes x 8 periods x 5 scenarios x
~700 hours. Two consequences shape everything below.

**The file is streamed, not materialised.** `CSV.Rows` reads it row by row and
only the selected scenario is accumulated, so peak memory is the output
(~66 MB for `europe_v51`) rather than the input.

**One page per node, and a period dropdown; scenario is fixed.** A Plotly
dropdown cannot fetch data, so every combination it offers has to be embedded in
the page. Node x period x scenario for `europe_v51` would be 1960 combinations
and several hundred MB. Splitting by node and fixing the scenario leaves 8
combinations per page (~1.4 MB), and the pages are linked from the dashboard
rather than embedded in it.

## Which columns enter the stack

The hourly balance is a signed sum: generation, `storDischarge_MW`, `FlowIn_MW`
and `LoadShed_MW` are positive; `Load_MW`, `storCharge_MW`, `FlowOut_MW` and
`LossesFlowIn_MW` are negative. Summed over those columns each row closes to
~1e-9 MW.

`LossesChargeDischargeBleed_MW` is *excluded*: it is already netted into
`storCharge_MW`/`storDischarge_MW`, and including it throws the balance off by
exactly its own value. `AllGen_MW` and `Net_load_MW` are excluded as identities
(`AllGen_MW` is the sum of the technology columns) and `storEnergyLevel_MWh` as a
state rather than a flow. `test_postprocessing.jl` asserts the balance closes.
"""

# Non-flow columns, and flow columns that would be counted twice.
const _DISPATCH_SKIP_COLUMNS = Set([
    :Node, :Period, :Scenario, :Season, :Hour,
    :AllGen_MW,                     # identity: sum of the technology columns
    :Net_load_MW,                   # identity: -AllGen_MW
    :storEnergyLevel_MWh,           # a state, not a flow
    :AvgCO2_kgCO2perMWh,            # an intensity, not a flow
    :LossesChargeDischargeBleed_MW, # already inside storCharge/storDischarge
])

const _DISPATCH_SUPPLY_LABELS = Dict(
    :storDischarge_MW => "Storage discharge",
    :FlowIn_MW => "Import",
    :LoadShed_MW => "Load shed",
)

const _DISPATCH_SINK_LABELS = Dict(
    :storCharge_MW => "Storage charge",
    :FlowOut_MW => "Export",
    :LossesFlowIn_MW => "Transmission losses",
)

"""
    _dispatch_role(column)

Classify an operational column as `:supply`, `:sink`, `:load`, `:price` or
`:skip`, and give the series label it contributes to. Generation columns are
folded into technology families so the legend matches the rest of the dashboard.
"""
function _dispatch_role(column::Symbol)
    column in _DISPATCH_SKIP_COLUMNS && return (:skip, "")
    column === :Load_MW && return (:load, "Load")
    column === :Price_EURperMWh && return (:price, "Price")
    haskey(_DISPATCH_SUPPLY_LABELS, column) && return (:supply, _DISPATCH_SUPPLY_LABELS[column])
    haskey(_DISPATCH_SINK_LABELS, column) && return (:sink, _DISPATCH_SINK_LABELS[column])

    name = String(column)
    endswith(name, "_MW") || return (:skip, "")
    return (:supply, _generator_family(chop(name; tail = 3)))
end

"""
    _stream_dispatch_rows!(csv_path, values, roles, hours, season_last_hour, nodes, periods)

Accumulate one scenario into the caller's containers, returning
`(scenario, rows_scanned)`.

Kept separate from [`_read_dispatch_data`](@ref) so the `CSV.Rows` object — and
with it the memory mapping of a possibly multi-GB file — is unreachable the
moment this returns.
"""
function _stream_dispatch_rows!(
        csv_path::AbstractString,
        values::Dict{Tuple{String, String, String}, Dict{Int, Float64}},
        roles::Dict{String, Symbol},
        hours::Dict{Tuple{String, String}, Set{Int}},
        season_last_hour::Dict{String, Int},
        nodes::Set{String},
        periods::Set{String},
    )
    rows = CSV.Rows(csv_path; reusebuffer = true)
    # Classify once. `rows.names` is the header; `row.names` would look up a
    # column called "names".
    column_roles = [(column, _dispatch_role(column)...) for column in rows.names]
    filter!(entry -> entry[2] !== :skip, column_roles)

    # Taken from the first data row rather than by scanning the file for the
    # sort-first scenario: that cost a second full pass over the largest table in
    # the run to learn a single string. `src/results.jl` writes the scenario loop
    # in a fixed order, so the first row is deterministic.
    scenario = ""
    scanned = 0

    for row in rows
        scanned += 1
        if scanned % _DISPATCH_PROGRESS_ROWS == 0
            @info "  ... $(scanned) rows scanned"
        end

        if isempty(scenario)
            scenario = string(row.Scenario)
        end
        row.Scenario == scenario || continue

        node = string(row.Node)
        period = string(row.Period)
        hour = _integer(row.Hour)
        season = string(row.Season)

        push!(nodes, node)
        push!(periods, period)
        push!(get!(hours, (node, period), Set{Int}()), hour)
        season_last_hour[season] = max(get(season_last_hour, season, hour), hour)

        for (column, role, label) in column_roles
            value = _number(row[column])
            # Load is stored negative in the CSV; draw it as a positive demand line.
            role === :load && (value = -value)
            roles[label] = role
            series = get!(values, (node, period, label), Dict{Int, Float64}())
            series[hour] = get(series, hour, 0.0) + value
        end
    end

    return scenario, scanned
end

"""
    _read_dispatch_data(csv_path)

Stream `results_output_Operational.csv`, accumulating one scenario.

Returns `nothing` when the file is absent or holds no usable rows. The scenario is
the one on the first data row — deterministic, and reported in the plot note;
embedding every scenario would multiply each page by the scenario count.

Single pass, with a progress heartbeat: this is the largest table a run produces
and a European dataset takes minutes to parse.
"""
function _read_dispatch_data(csv_path::AbstractString)
    isfile(csv_path) || return nothing

    megabytes = round(filesize(csv_path) / 1024^2; digits = 1)
    @info "Building hourly dispatch pages from $(basename(csv_path)) ($(megabytes) MB). Keeping one scenario."

    # (node, period, series) => hour => MW, and the same keyed for load/price.
    values = Dict{Tuple{String, String, String}, Dict{Int, Float64}}()
    roles = Dict{String, Symbol}()
    hours = Dict{Tuple{String, String}, Set{Int}}()
    season_last_hour = Dict{String, Int}()
    nodes = Set{String}()
    periods = Set{String}()

    scenario, scanned = _stream_dispatch_rows!(
        csv_path, values, roles, hours, season_last_hour, nodes, periods,
    )

    # `CSV.Rows` memory-maps the file and Windows keeps it locked until the
    # mapping is collected, so without this the operational CSV cannot be deleted
    # or overwritten for the rest of the session — regenerating a dashboard into
    # an existing run directory would fail. The read lives in its own function so
    # the `CSV.Rows` object is genuinely unreachable here; left as a local of this
    # function it stays rooted in the frame and survives the collection.
    GC.gc()

    @info "Read $(scanned) rows; kept scenario $(isempty(scenario) ? "-" : scenario) across $(length(nodes)) nodes."
    isempty(nodes) && return nothing
    return (
        scenario = scenario,
        nodes = sort!(collect(nodes)),
        periods = _sort_categories(periods),
        values = values,
        roles = roles,
        hours = Dict(key => sort!(collect(value)) for (key, value) in hours),
        season_last_hour = season_last_hour,
    )
end

"""
    _dispatch_specs(csv_path)

One spec per node: a stacked hourly dispatch chart with the demand line, the
price on a secondary axis, season boundaries marked, and a period dropdown.
"""
function _dispatch_specs(csv_path::AbstractString)
    data = _read_dispatch_data(csv_path)
    data === nothing && return NamedTuple[]

    specs = NamedTuple[]
    for node in data.nodes
        spec = _dispatch_spec_for_node(data, node)
        spec === nothing || push!(specs, spec)
    end
    return specs
end

function _dispatch_spec_for_node(data, node::AbstractString)
    node_periods = [period for period in data.periods if haskey(data.hours, (node, period))]
    isempty(node_periods) && return nothing

    # Rank series by total energy across every period so the stack order and the
    # legend stay put as the dropdown changes period.
    totals = Dict{String, Float64}()
    for period in node_periods, (label, role) in data.roles
        role in (:supply, :sink) || continue
        series = get(data.values, (node, period, label), nothing)
        series === nothing && continue
        totals[label] = get(totals, label, 0.0) + sum(abs, values(series))
    end
    # A technology absent from this node contributes a flat zero band; drop it.
    kept = [label for (label, total) in totals if total > _DISPATCH_SERIES_FLOOR]
    isempty(kept) && return nothing
    sort!(kept; by = label -> (-totals[label], label))

    supply = [label for label in kept if data.roles[label] === :supply]
    sink = [label for label in kept if data.roles[label] === :sink]

    traces = String[]
    period_trace_indices = Dict{String, Vector{Int}}()
    active_period = last(node_periods)
    for period in node_periods
        hours = data.hours[(node, period)]
        visible = period == active_period
        indices = Int[]

        for (labels, stackgroup) in ((supply, "supply"), (sink, "sink"))
            for label in labels
                series = get(data.values, (node, period, label), nothing)
                y = series === nothing ? zeros(length(hours)) : [get(series, hour, 0.0) for hour in hours]
                push!(traces, _dispatch_area_trace(hours, y, label, stackgroup, _series_color(label), visible))
                push!(indices, length(traces))
            end
        end

        for (label, dash, color, axis) in (
                ("Load", "solid", "#111111", "y"),
                ("Price", "dot", "#a33", "y2"),
            )
            series = get(data.values, (node, period, label), nothing)
            series === nothing && continue
            y = [get(series, hour, 0.0) for hour in hours]
            push!(traces, _dispatch_line_trace(hours, y, label, color, dash, axis, visible))
            push!(indices, length(traces))
        end

        period_trace_indices[period] = indices
    end

    isempty(traces) && return nothing

    title = "Hourly Dispatch - $node"
    layout = _dispatch_layout(
        "$title ($active_period)",
        title,
        node_periods,
        period_trace_indices,
        length(traces),
        active_period,
        data.season_last_hour,
    )
    return (
        filename = "dispatch_$(_filename_slug(node)).html",
        title = title,
        traces = traces,
        layout = layout,
        note = "Hourly generation stack for $node in $(data.scenario), with demand and the nodal price. " *
            "Positive bands supply the node, negative bands draw from it; the two sum to zero each hour. " *
            "Only $(data.scenario) is shown — a dropdown cannot load data, so every scenario would have to be embedded in this page.",
    )
end

# Below this many MWh summed over all hours and periods a series is a flat zero
# band that only costs legend space.
const _DISPATCH_SERIES_FLOOR = 1.0

# How often the streaming read reports progress. This table is the largest in the
# run and a European dataset takes minutes to parse; without a heartbeat the
# runner looks hung, which is exactly how it was first reported.
const _DISPATCH_PROGRESS_ROWS = 500_000

"""
    _filename_slug(value)

Reduce a node name to something safe to use as a filename. Node names come from
user-supplied CSV and include `.` (`GreatBrit.`) among other things.
"""
function _filename_slug(value::AbstractString)
    io = IOBuffer()
    for character in value
        if isletter(character) || isdigit(character)
            print(io, character)
        elseif character in ('-', '_')
            print(io, character)
        end
    end
    slug = String(take!(io))
    return isempty(slug) ? "node" : slug
end
