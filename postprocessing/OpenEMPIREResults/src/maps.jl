function _read_node_coordinates(input_dir::Union{Nothing, AbstractString})
    coords = Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}}()
    input_dir === nothing && return coords

    coords_path = joinpath(input_dir, "Sets", "Coords.csv")
    isfile(coords_path) || return coords

    for row in CSV.File(coords_path; normalizenames = false)
        coords[string(row.Location)] = (lat = Float64(row.Latitude), lon = Float64(row.Longitude))
    end
    return coords
end

function _read_transmission_line_types(input_dir::Union{Nothing, AbstractString})
    line_types = Dict{Tuple{String, String}, String}()
    input_dir === nothing && return line_types

    line_types_path = joinpath(input_dir, "Sets", "TransmissionTypeOfDirectionalLink.csv")
    isfile(line_types_path) || return line_types

    for row in CSV.File(line_types_path; normalizenames = false)
        from_node = string(row.FromNode)
        to_node = string(row.ToNode)
        line_types[(from_node, to_node)] = string(row.LineType)
    end
    return line_types
end


"""
    _corridor_traces(corridors, node_coordinates)

Collapse per-corridor line segments into a handful of `scattergeo` traces.

One trace per corridor is the obvious encoding and it does not survive a European
dataset: `europe_v51` has 190 corridors, so the map carried 190 legend rows and
the legend swamped the plot it was supposed to explain.

Plotly draws disconnected segments in a single trace when the coordinate arrays
are broken with `nothing`, so corridors are grouped by line type and capacity
band instead. That trades continuous line width for a banded width — a reader
cannot measure a capacity off line thickness anyway, and the exact figure is
still in the hover.

`corridors` is a vector of named tuples with `from_node`, `to_node`, `capacity`,
`line_type` and `hover`.
"""
function _corridor_traces(
        corridors,
        node_coordinates::Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}};
        visible::Bool = true,
    )
    isempty(corridors) && return String[], Set{String}()

    capacities = sort!([corridor.capacity for corridor in corridors])
    edges = _capacity_band_edges(capacities)

    # (line_type, band) => accumulated segment arrays
    groups = Dict{Tuple{String, Int}, NamedTuple{(:lons, :lats, :texts), Tuple{Vector{Any}, Vector{Any}, Vector{Any}}}}()
    nodes_on_map = Set{String}()

    for corridor in corridors
        from_coord = get(node_coordinates, corridor.from_node, nothing)
        to_coord = get(node_coordinates, corridor.to_node, nothing)
        (from_coord === nothing || to_coord === nothing) && continue

        band = _capacity_band(corridor.capacity, edges)
        group = get!(groups, (corridor.line_type, band)) do
            (lons = Any[], lats = Any[], texts = Any[])
        end
        # `nothing` renders as a JSON null, which breaks the line between segments.
        append!(group.lons, Any[from_coord.lon, to_coord.lon, nothing])
        append!(group.lats, Any[from_coord.lat, to_coord.lat, nothing])
        append!(group.texts, Any[corridor.hover, corridor.hover, ""])

        push!(nodes_on_map, corridor.from_node)
        push!(nodes_on_map, corridor.to_node)
    end

    traces = String[]
    for key in sort!(collect(keys(groups)))
        line_type, band = key
        group = groups[key]
        push!(
            traces,
            _scattergeo_trace(
                ;
                lon = group.lons,
                lat = group.lats,
                # A single band carries no useful range, so the line type stands
                # alone rather than trailing an empty bracket.
                name = _band_trace_name(line_type, band, edges),
                mode = "lines",
                line_color = _transmission_type_color(line_type),
                line_width = _CAPACITY_BAND_WIDTHS[band],
                text = group.texts,
                hoverinfo = "text",
                visible,
            ),
        )
    end
    return traces, nodes_on_map
end

const _CAPACITY_BAND_WIDTHS = (1.0, 2.5, 4.5, 7.0)

"""
Quantile cut points for the capacity bands.

Quantiles rather than fixed fractions of the maximum: interconnector capacity is
heavily skewed, so even splits of the range leave every corridor but a handful in
the bottom band and the width encoding says nothing.
"""
function _capacity_band_edges(sorted_capacities::Vector{Float64})
    isempty(sorted_capacities) && return Float64[]
    n = length(sorted_capacities)
    edges = [sorted_capacities[max(1, min(n, ceil(Int, n * q)))] for q in (0.25, 0.5, 0.75)]
    # Ties collapse quantiles onto each other, which would create bands no
    # corridor can fall into and label them with an empty range. Deduping leaves
    # fewer, honest bands — one band when every corridor has the same capacity.
    unique!(edges)
    return filter(edge -> edge < sorted_capacities[end], edges)
end

function _capacity_band(capacity::Real, edges::Vector{Float64})
    for (index, edge) in enumerate(edges)
        capacity <= edge && return index
    end
    return length(edges) + 1
end

function _band_trace_name(line_type::AbstractString, band::Int, edges::Vector{Float64})
    label = _capacity_band_label(band, edges)
    return isempty(label) ? String(line_type) : "$line_type $label"
end

function _capacity_band_label(band::Int, edges::Vector{Float64})
    isempty(edges) && return ""
    lower = band == 1 ? 0.0 : edges[band - 1]
    band > length(edges) && return "(> $(_format_capacity(lower)))"
    upper = edges[band]
    # A zero upper edge is not an empty band: europe_v51 has corridors the model
    # may build on but which carry no existing capacity, and a quarter of them
    # makes 0.0 the first quantile.
    upper == 0 && return "(none existing)"
    lower == 0 && return "(up to $(_format_capacity(upper)))"
    return "($(_format_capacity(lower))-$(_format_capacity(upper)))"
end

_format_capacity(value::Real) = value >= 1000 ? "$(round(value / 1000; digits = 1)) GW" : "$(round(value; digits = 0)) MW"

"""
    _node_trace(nodes, node_coordinates)

Node markers with names on hover only.

`markers+text` prints all 49 labels permanently, and central Europe is dense
enough that they overlap into an unreadable mass.
"""
function _node_trace(nodes, node_coordinates; visible::Bool = true)
    sorted_nodes = sort!(collect(nodes))
    return _scattergeo_trace(
        ;
        lon = [node_coordinates[node].lon for node in sorted_nodes],
        lat = [node_coordinates[node].lat for node in sorted_nodes],
        name = "Nodes",
        mode = "markers",
        text = sorted_nodes,
        marker_color = "#1f78b4",
        marker_size = 7,
        hoverinfo = "text",
        visible,
    )
end

"""
    _node_bounds(node_coordinates)

Latitude/longitude range covering the nodes, with a margin.

`geo.scope = "europe"` frames a region far larger than any EMPIRE dataset, so the
network was drawn into a corner of the canvas surrounded by empty map.
"""
function _node_bounds(node_coordinates::Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}})
    isempty(node_coordinates) && return nothing
    lats = [coord.lat for coord in values(node_coordinates)]
    lons = [coord.lon for coord in values(node_coordinates)]
    lat_margin = max(1.5, 0.08 * (maximum(lats) - minimum(lats)))
    lon_margin = max(1.5, 0.08 * (maximum(lons) - minimum(lons)))
    return (
        lat = (minimum(lats) - lat_margin, maximum(lats) + lat_margin),
        lon = (minimum(lons) - lon_margin, maximum(lons) + lon_margin),
    )
end


function _input_transmission_map_spec(
        input_dir::AbstractString,
        node_coordinates::Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}},
        transmission_line_types::Dict{Tuple{String, String}, String};
        filename::AbstractString,
    )
    isempty(node_coordinates) && return nothing

    init_capacity = _read_arc_period_values(
        joinpath(input_dir, "Transmission", "transmissionInitCap.csv"),
    )
    max_built_capacity = _read_arc_period_values(
        joinpath(input_dir, "Transmission", "transmissionMaxBuiltCap.csv"),
    )
    lengths = _read_arc_values(
        joinpath(input_dir, "Transmission", "transmissionLength.csv"),
    )
    efficiencies = _read_arc_values(
        joinpath(input_dir, "Transmission", "lineEfficiency.csv"),
    )

    isempty(transmission_line_types) && return nothing
    periods = sort!(collect(unique(period for (_, _, period) in keys(init_capacity))))
    period = isempty(periods) ? 1 : first(periods)

    corridors = NamedTuple[]
    for (from_node, to_node) in sort!(collect(unique(_corridor_key(from, to) for (from, to) in keys(transmission_line_types))))
        line_type = _line_type_for_corridor(transmission_line_types, from_node, to_node)
        initial = _value_for_corridor_period(init_capacity, from_node, to_node, period)
        max_built = _value_for_corridor_period(max_built_capacity, from_node, to_node, period)
        line_length = _value_for_corridor(lengths, from_node, to_node)
        efficiency = _value_for_corridor(efficiencies, from_node, to_node)
        push!(
            corridors,
            (
                from_node = from_node,
                to_node = to_node,
                # Existing capacity, not `max(initial, max_built)`. The max-build
                # column is a uniform blanket cap (20 GW on every corridor in
                # europe_v51), so banding on it puts every line in one band and
                # the width says nothing. Initial capacity actually varies.
                capacity = initial,
                line_type = line_type,
                hover = "$from_node-$to_node<br>Type: $line_type<br>Initial capacity: $(_format_value(initial)) MW<br>Max build capacity: $(_format_value(max_built)) MW<br>Length: $(_format_value(line_length)) km<br>Efficiency: $(_format_value(efficiency))",
            ),
        )
    end

    line_traces, nodes_on_map = _corridor_traces(corridors, node_coordinates)
    isempty(line_traces) && return nothing

    traces = vcat([_node_trace(nodes_on_map, node_coordinates)], line_traces)
    title = "Input Transmission Assumptions"
    layout = _geo_layout(title; bounds = _node_bounds(node_coordinates))
    return (
        filename = filename,
        title = title,
        traces = traces,
        layout = layout,
        note = "Input transmission assumptions. Corridors are grouped by line type and capacity band; the exact capacity, length and efficiency are in the hover. Capacities are from the first input period.",
    )
end


function _transmission_map_spec(
        csv_path::AbstractString,
        node_coordinates::Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}},
        transmission_line_types::Dict{Tuple{String, String}, String},
        title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
    )
    isempty(node_coordinates) && return nothing

    rows = collect(CSV.File(csv_path; normalizenames = false))
    isempty(rows) && return nothing

    periods = sort!(collect(unique(Int(row.Period) for row in rows)))
    max_capacity = maximum(Float64(row.transmissionInstalledCap) for row in rows)
    latest_period = maximum(periods)

    traces = String[]
    period_trace_indices = Dict{Int, Vector{Int}}()
    for period in periods
        period_rows = [row for row in rows if Int(row.Period) == period && Float64(row.transmissionInstalledCap) > 1.0]
        isempty(period_rows) && continue

        visible = period == latest_period
        corridors = _transmission_corridors(period_rows, transmission_line_types)
        isempty(corridors) && continue

        period_indices = Int[]
        hover_corridors = [
            (
                from_node = corridor.from_node,
                to_node = corridor.to_node,
                capacity = corridor.capacity,
                line_type = corridor.line_type,
                hover = "$(corridor.from_node)-$(corridor.to_node)<br>Type: $(corridor.line_type)<br>Period: $period<br>Installed capacity: $(round(corridor.capacity; digits = 1)) MW",
            )
            for corridor in corridors
        ]
        line_traces, nodes_on_map = _corridor_traces(hover_corridors, node_coordinates; visible)

        isempty(line_traces) && continue

        push!(traces, _node_trace(nodes_on_map, node_coordinates; visible))
        push!(period_indices, length(traces))
        for trace in line_traces
            push!(traces, trace)
            push!(period_indices, length(traces))
        end
        period_trace_indices[period] = period_indices
    end

    isempty(traces) && return nothing

    visible_periods = sort!(collect(keys(period_trace_indices)))
    layout = _geo_layout(
        "$title - Period $latest_period", visible_periods, period_trace_indices,
        length(traces), title, latest_period; bounds = _node_bounds(node_coordinates),
    )
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _transmission_corridors(period_rows, transmission_line_types::Dict{Tuple{String, String}, String})
    corridors = Dict{Tuple{String, String}, NamedTuple{(:from_node, :to_node, :capacity, :line_type), Tuple{String, String, Float64, String}}}()
    for row in period_rows
        from_node = string(row.FromNode)
        to_node = string(row.ToNode)
        from_to = from_node <= to_node ? (from_node, to_node) : (to_node, from_node)
        line_type = get(transmission_line_types, (from_node, to_node), get(transmission_line_types, (to_node, from_node), "Unknown"))
        capacity = Float64(row.transmissionInstalledCap)
        current = get(corridors, from_to, nothing)
        if current === nothing || capacity > current.capacity
            corridors[from_to] = (from_node = from_to[1], to_node = from_to[2], capacity = capacity, line_type = line_type)
        end
    end
    return sort!(collect(values(corridors)); by = corridor -> (corridor.from_node, corridor.to_node))
end


