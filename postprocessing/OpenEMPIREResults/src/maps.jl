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


function _input_transmission_map_spec(
        input_dir::AbstractString,
        node_coordinates::Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}},
        transmission_line_types::Dict{Tuple{String, String}, String};
        filename::AbstractString,
    )
    isempty(node_coordinates) && return nothing

    init_capacity = _read_arc_period_values(
        joinpath(input_dir, "Transmission", "transmissionInitCap.csv"),
        :InterconnectorLinks,
        :ToNode,
        :Period,
        :TransmissionInitialCapacity,
    )
    max_built_capacity = _read_arc_period_values(
        joinpath(input_dir, "Transmission", "transmissionMaxBuiltCap.csv"),
        :InterconnectorLinks,
        :ToNode,
        :Period,
        :TransmissionMaxBuiltCapacity_in_MW,
    )
    lengths = _read_arc_values(
        joinpath(input_dir, "Transmission", "transmissionLength.csv"),
        :FromNode,
        :ToNode,
        :lineLength_in_km,
    )
    efficiencies = _read_arc_values(
        joinpath(input_dir, "Transmission", "lineEfficiency.csv"),
        :FromNode,
        :ToNode,
        :lineEfficiency,
    )

    isempty(transmission_line_types) && return nothing
    traces = String[]
    nodes_on_map = Set{String}()
    line_traces = String[]
    periods = sort!(collect(unique(period for (_, _, period) in keys(init_capacity))))
    period = isempty(periods) ? 1 : first(periods)
    max_capacity = maximum(vcat(collect(values(init_capacity)), collect(values(max_built_capacity)), [1.0]))
    corridors = sort!(collect(unique(_corridor_key(from_node, to_node) for (from_node, to_node) in keys(transmission_line_types))))
    for (from_node, to_node) in corridors
        from_coord = get(node_coordinates, from_node, nothing)
        to_coord = get(node_coordinates, to_node, nothing)
        (from_coord === nothing || to_coord === nothing) && continue

        line_type = _line_type_for_corridor(transmission_line_types, from_node, to_node)
        initial = _value_for_corridor_period(init_capacity, from_node, to_node, period)
        max_built = _value_for_corridor_period(max_built_capacity, from_node, to_node, period)
        length = _value_for_corridor(lengths, from_node, to_node)
        efficiency = _value_for_corridor(efficiencies, from_node, to_node)
        width_basis = max(initial, max_built)
        width = max(1.0, min(8.0, 1.0 + 7.0 * width_basis / max_capacity))

        push!(nodes_on_map, from_node)
        push!(nodes_on_map, to_node)
        push!(
            line_traces,
            _scattergeo_trace(
                ;
                lon = [from_coord.lon, to_coord.lon],
                lat = [from_coord.lat, to_coord.lat],
                name = "$from_node-$to_node",
                mode = "lines",
                line_color = _transmission_type_color(line_type),
                line_width = width,
                text = ["$from_node-$to_node<br>Type: $line_type<br>Initial capacity: $(_format_value(initial)) MW<br>Max build capacity: $(_format_value(max_built)) MW<br>Length: $(_format_value(length)) km<br>Efficiency: $(_format_value(efficiency))"],
                hoverinfo = "text",
            ),
        )
    end

    isempty(line_traces) && return nothing

    sorted_nodes = sort!(collect(nodes_on_map))
    node_trace = _scattergeo_trace(
        ;
        lon = [node_coordinates[node].lon for node in sorted_nodes],
        lat = [node_coordinates[node].lat for node in sorted_nodes],
        name = "Nodes",
        mode = "markers+text",
        text = sorted_nodes,
        marker_color = "#1f78b4",
        marker_size = 9,
        textposition = "bottom center",
        hoverinfo = "text",
    )

    traces = vcat([node_trace], line_traces)
    title = "Input Transmission Assumptions"
    layout = _geo_layout(title)
    return (
        filename = filename,
        title = title,
        traces = traces,
        layout = layout,
        note = "Shows input transmission assumptions. Line width is scaled by initial or maximum build capacity from the first input period.",
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
        nodes_on_map = Set{String}()
        line_traces = String[]
        for corridor in corridors
            from_node = corridor.from_node
            to_node = corridor.to_node
            from_coord = get(node_coordinates, from_node, nothing)
            to_coord = get(node_coordinates, to_node, nothing)
            (from_coord === nothing || to_coord === nothing) && continue

            capacity = corridor.capacity
            line_type = corridor.line_type
            width = max(1.0, min(8.0, 1.0 + 7.0 * capacity / max_capacity))
            push!(nodes_on_map, from_node)
            push!(nodes_on_map, to_node)
            push!(
                line_traces,
                _scattergeo_trace(
                    ;
                    lon = [from_coord.lon, to_coord.lon],
                    lat = [from_coord.lat, to_coord.lat],
                    name = "$from_node-$to_node",
                    mode = "lines",
                    line_color = _transmission_type_color(line_type),
                    line_width = width,
                    text = ["$from_node-$to_node<br>Type: $line_type<br>Period: $period<br>Installed capacity: $(round(capacity; digits = 1)) MW"],
                    hoverinfo = "text",
                    visible,
                ),
            )
        end

        isempty(line_traces) && continue

        sorted_nodes = sort!(collect(nodes_on_map))
        lons = [node_coordinates[node].lon for node in sorted_nodes]
        lats = [node_coordinates[node].lat for node in sorted_nodes]
        node_trace = _scattergeo_trace(
            ;
            lon = lons,
            lat = lats,
            name = "Nodes",
            mode = "markers+text",
            text = sorted_nodes,
            marker_color = "#1f78b4",
            marker_size = 9,
            textposition = "bottom center",
            hoverinfo = "text",
            visible,
        )

        push!(traces, node_trace)
        push!(period_indices, length(traces))
        for trace in line_traces
            push!(traces, trace)
            push!(period_indices, length(traces))
        end
        period_trace_indices[period] = period_indices
    end

    isempty(traces) && return nothing

    visible_periods = sort!(collect(keys(period_trace_indices)))
    layout = _geo_layout("$title - Period $latest_period", visible_periods, period_trace_indices, length(traces), title, latest_period)
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


