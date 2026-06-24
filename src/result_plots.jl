"""
    write_result_plots(result_dir; output_dir=joinpath(result_dir, "Output"), plot_dir=joinpath(result_dir, "Plots"))

Create a small HTML dashboard from the result CSV files currently written by
`write_solution_tables`.
"""
const RESULT_SERIES_COLORS = Dict(
    "Bio" => "#2ca02c",
    "Bio cofiring" => "#8c564b",
    "Bio cofiring CCS" => "#6b8e23",
    "Coal" => "#4d4d4d",
    "Coal CCS" => "#7f7f7f",
    "Gas" => "#bc6c25",
    "Gas CCS" => "#dda15e",
    "Geothermal" => "#9467bd",
    "Hydro regulated" => "#1f77b4",
    "Hydro run-of-river" => "#17becf",
    "Lignite" => "#6c584c",
    "Lignite CCS" => "#a98467",
    "Nuclear" => "#d62728",
    "Oil" => "#111111",
    "Solar" => "#ffbf00",
    "Waste" => "#8c564b",
    "Wave" => "#2b8cbe",
    "Wind offshore" => "#6baed6",
    "Wind onshore" => "#74c476",
    "HydroPumpStorage" => "#1f77b4",
    "Li-Ion_BESS" => "#ff7f0e",
    "CCS" => "#7f7f7f",
    "Existing" => "#9e9e9e",
)

const TRANSMISSION_TYPE_COLORS = Dict(
    "HVAC_OverheadLine" => "#32213A",
    "HVDC_Cable" => "#2E86AB",
)

function write_result_plots(
        result_dir::AbstractString;
        output_dir::AbstractString = joinpath(result_dir, "Output"),
        plot_dir::AbstractString = joinpath(result_dir, "Plots"),
        input_dir::Union{Nothing, AbstractString} = nothing,
    )
    mkpath(plot_dir)

    result_specs = _available_result_plot_specs(output_dir, input_dir)
    input_specs = NamedTuple[]
    if input_dir !== nothing
        input_specs = _available_input_plot_specs(input_dir)
    end
    plot_specs = vcat(result_specs, input_specs)
    isempty(plot_specs) && throw(ArgumentError("No supported result CSV files found in $output_dir"))

    html_plots = NamedTuple[]
    for spec in plot_specs
        path = joinpath(plot_dir, spec.filename)
        _write_plotly_html(path, spec.title, spec.traces, spec.layout)
        push!(html_plots, spec)
    end

    dashboard_path = joinpath(plot_dir, "dashboard.html")
    n_result_specs = length(result_specs)
    result_html_plots = html_plots[1:n_result_specs]
    input_html_plots = n_result_specs < length(html_plots) ? html_plots[(n_result_specs + 1):end] : NamedTuple[]
    _write_dashboard_html(dashboard_path, result_html_plots, input_html_plots)
    return dashboard_path
end

function _available_result_plot_specs(output_dir::AbstractString, input_dir::Union{Nothing, AbstractString})
    specs = NamedTuple[]
    node_coordinates = _read_node_coordinates(input_dir)
    transmission_line_types = _read_transmission_line_types(input_dir)

    gen_investment = joinpath(output_dir, "genInvCap.csv")
    gen_capacity = joinpath(output_dir, "genInstalledCap.csv")
    if isfile(gen_capacity)
        push!(specs, _stacked_bar_spec(
            gen_capacity,
            "Installed Generation Capacity",
            :Period,
            :Generator,
            :genInstalledCap,
            "Installed capacity [MW]";
            filename = "generator_installed_capacity.html",
            series_mapper = _generator_family,
            note = "Installed capacity includes existing capacity and previous/new investments that are available in the period.",
        ))
    end

    if isfile(gen_investment)
        push!(specs, _node_investment_bar_spec(
            gen_investment,
            "New Generation Investment Capacity by Node",
            :Period,
            :Node,
            :Generator,
            :genInvCap,
            "New investment capacity [MW]";
            filename = "generator_investment_capacity_by_node.html",
            series_mapper = _generator_family,
            note = "Splits new generation investments by node to show where capacity is built.",
        ))
        push!(specs, _stacked_bar_spec(
            gen_investment,
            "New Generation Investment Capacity",
            :Period,
            :Generator,
            :genInvCap,
            "New investment capacity [MW]";
            filename = "generator_investment_capacity.html",
            series_mapper = _generator_family,
            note = "Shows capacity the model chooses to build in each strategic period.",
        ))
    end

    stor_power = joinpath(output_dir, "storPWInstalledCap.csv")
    if isfile(stor_power)
        push!(specs, _stacked_bar_spec(
            stor_power,
            "Installed Storage Power Capacity",
            :Period,
            :Storage,
            :storPWInstalledCap,
            "Installed storage power [MW]";
            filename = "storage_power_capacity.html",
            note = "Power capacity is the maximum charge/discharge rate of storage.",
        ))
    end

    stor_energy = joinpath(output_dir, "storENInstalledCap.csv")
    if isfile(stor_energy)
        push!(specs, _stacked_bar_spec(
            stor_energy,
            "Installed Storage Energy Capacity",
            :Period,
            :Storage,
            :storENInstalledCap,
            "Installed storage energy [MWh]";
            filename = "storage_energy_capacity.html",
            note = "Energy capacity is the storage volume.",
        ))
    end

    transmission_capacity = joinpath(output_dir, "transmissionInstalledCap.csv")
    if isfile(transmission_capacity)
        map_spec = _transmission_map_spec(
            transmission_capacity,
            node_coordinates,
            transmission_line_types,
            "Installed Transmission Capacity Map";
            filename = "transmission_installed_capacity_map.html",
            note = "Shows modelled interconnectors by selected period. Line width is scaled by installed capacity and color indicates line type when available.",
        )
        map_spec === nothing || push!(specs, map_spec)
        push!(specs, _line_spec(
            transmission_capacity,
            "Installed Transmission Capacity",
            :Period,
            (:FromNode, :ToNode),
            :transmissionInstalledCap,
            "Installed transmission capacity [MW]";
            filename = "transmission_installed_capacity.html",
            note = "Shows total installed transmission capacity on each modelled corridor.",
        ))
    end

    load_shed = joinpath(output_dir, "loadShed.csv")
    if isfile(load_shed)
        push!(specs, _stacked_bar_spec(
            load_shed,
            "Load Shedding Over Exported Hours",
            :Period,
            :Node,
            :loadShed,
            "Sum over exported operational hours [MW-hour rows]";
            filename = "load_shed.html",
        ))
    end

    gen_operation = joinpath(output_dir, "genOperational.csv")
    if isfile(gen_operation)
        push!(specs, _stacked_bar_spec(
            gen_operation,
            "Operational Generation Diagnostic",
            :Period,
            :Generator,
            :genOperational,
            "Sum over exported operational hours [MW-hour rows]";
            filename = "generator_operational.html",
            series_mapper = _generator_family,
            note = "Diagnostic plot: this sums raw exported operational rows and is not scenario/season weighted annual generation.",
        ))
    end

    return specs
end

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

function _available_input_plot_specs(input_dir::AbstractString)
    specs = NamedTuple[]
    node_coordinates = _read_node_coordinates(input_dir)
    transmission_line_types = _read_transmission_line_types(input_dir)

    input_transmission_map = _input_transmission_map_spec(
        input_dir,
        node_coordinates,
        transmission_line_types;
        filename = "input_transmission_map.html",
    )
    input_transmission_map === nothing || push!(specs, input_transmission_map)

    co2_price = joinpath(input_dir, "General", "CO2price.csv")
    if isfile(co2_price)
        push!(specs, _single_line_spec(
            co2_price,
            "Input CO2 Price",
            1,
            2,
            "CO2 price [EUR/tCO2]";
            filename = "input_co2_price.html",
            series_name = "CO2 price",
        ))
    end

    capital_cost = joinpath(input_dir, "Generator", "genCapitalCost.csv")
    if isfile(capital_cost)
        push!(specs, _multi_series_bar_spec(
            capital_cost,
            "Input Generator Capital Cost",
            2,
            1,
            3,
            "Capital cost [EUR/kW]";
            filename = "input_generator_capital_cost.html",
        ))
    end

    max_installed_capacity = joinpath(input_dir, "Generator", "genMaxInstalledCapRaw.csv")
    if isfile(max_installed_capacity)
        push!(specs, _node_technology_bar_spec(
            max_installed_capacity,
            "Input Maximum Installed Generation Capacity",
            1,
            2,
            3,
            "Maximum installed capacity [MW]";
            filename = "input_max_installed_generation_capacity.html",
        ))
    end

    return specs
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

function _stacked_bar_spec(
        csv_path::AbstractString,
        title::AbstractString,
        x_col::Symbol,
        series_col::Symbol,
        value_col::Symbol,
        y_title::AbstractString;
        filename::AbstractString,
        series_mapper = identity,
        note::AbstractString = "",
    )
    grouped = _group_sum(csv_path, x_col, series_col, value_col; series_mapper)
    x_values = sort!(collect(unique(first.(keys(grouped)))))
    series_values = sort!(collect(unique(last.(keys(grouped)))))
    x_labels = string.(x_values)
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (x, series), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_labels,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end
    layout = _layout(title, "Period", y_title; barmode = "stack", x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _node_investment_bar_spec(
        csv_path::AbstractString,
        title::AbstractString,
        period_col::Symbol,
        node_col::Symbol,
        series_col::Symbol,
        value_col::Symbol,
        y_title::AbstractString;
        filename::AbstractString,
        series_mapper = identity,
        note::AbstractString = "",
    )
    grouped = Dict{Tuple{Int, String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        period = Int(row[period_col])
        node = string(row[node_col])
        series = string(series_mapper(string(row[series_col])))
        key = (period, node, series)
        grouped[key] = get(grouped, key, 0.0) + Float64(row[value_col])
    end

    period_nodes = sort!(collect(unique((period, node) for (period, node, _) in keys(grouped))))
    x_labels = ["P$(period) / $node" for (period, node) in period_nodes]
    series_values = sort!(collect(unique(series for (_, _, series) in keys(grouped))))

    traces = String[]
    for series in series_values
        y_values = [get(grouped, (period, node, series), 0.0) for (period, node) in period_nodes]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_labels,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout(title, "Period / Node", y_title; barmode = "stack", x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _line_spec(
        csv_path::AbstractString,
        title::AbstractString,
        x_col::Symbol,
        series_cols::Tuple{Symbol, Symbol},
        value_col::Symbol,
        y_title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
    )
    grouped = Dict{Tuple{Int, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        x = Int(row[x_col])
        series = string(row[series_cols[1]], "-", row[series_cols[2]])
        grouped[(x, series)] = get(grouped, (x, series), 0.0) + Float64(row[value_col])
    end

    x_values = sort!(collect(unique(first.(keys(grouped)))))
    series_values = sort!(collect(unique(last.(keys(grouped)))))
    x_labels = string.(x_values)
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (x, series), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_labels,
            y = y_values,
            name = series,
            type = "scatter",
            mode = "lines+markers",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end
    layout = _layout(title, "Period", y_title; x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
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

function _single_line_spec(
        csv_path::AbstractString,
        title::AbstractString,
        x_col::Integer,
        value_col::Integer,
        y_title::AbstractString;
        filename::AbstractString,
        series_name::AbstractString,
        note::AbstractString = "",
    )
    points = Tuple{Int, Float64}[]
    for row in CSV.File(csv_path; normalizenames = false)
        push!(points, (Int(row[x_col]), Float64(row[value_col])))
    end
    sort!(points)
    x_labels = string.(first.(points))
    y_values = last.(points)
    traces = [_trace(; x = x_labels, y = y_values, name = series_name, type = "scatter", mode = "lines+markers", hovertemplate = _hover_template(y_title))]
    layout = _layout(title, "Period", y_title; x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _multi_series_bar_spec(
        csv_path::AbstractString,
        title::AbstractString,
        x_col::Integer,
        series_col::Integer,
        value_col::Integer,
        y_title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
    )
    grouped = Dict{Tuple{Int, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (Int(row[x_col]), string(row[series_col]))
        grouped[key] = Float64(row[value_col])
    end

    x_values = sort!(collect(unique(first.(keys(grouped)))))
    x_labels = string.(x_values)
    series_values = sort!(collect(unique(last.(keys(grouped)))))
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (x, series), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_labels,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(_generator_family(series)),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout(title, "Period", y_title; barmode = "group", x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _node_technology_bar_spec(
        csv_path::AbstractString,
        title::AbstractString,
        node_col::Integer,
        series_col::Integer,
        value_col::Integer,
        y_title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
    )
    grouped = Dict{Tuple{String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        node = string(row[node_col])
        series = _generator_family(string(row[series_col]))
        grouped[(node, series)] = get(grouped, (node, series), 0.0) + Float64(row[value_col])
    end

    nodes = sort!(collect(unique(first.(keys(grouped)))))
    series_values = sort!(collect(unique(last.(keys(grouped)))))
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (node, series), 0.0) for node in nodes]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = nodes,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout(title, "Node", y_title; barmode = "stack", x_values = nodes)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

function _group_sum(
        csv_path::AbstractString,
        x_col::Symbol,
        series_col::Symbol,
        value_col::Symbol;
        series_mapper = identity,
    )
    grouped = Dict{Tuple{Int, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (Int(row[x_col]), string(series_mapper(string(row[series_col]))))
        grouped[key] = get(grouped, key, 0.0) + Float64(row[value_col])
    end
    return grouped
end

function _read_arc_period_values(
        csv_path::AbstractString,
        from_col::Symbol,
        to_col::Symbol,
        period_col::Symbol,
        value_col::Symbol,
    )
    values = Dict{Tuple{String, String, Int}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        from_node = string(row[from_col])
        to_node = string(row[to_col])
        period = Int(row[period_col])
        values[(from_node, to_node, period)] = Float64(row[value_col])
    end
    return values
end

function _read_arc_values(csv_path::AbstractString, from_col::Symbol, to_col::Symbol, value_col::Symbol)
    values = Dict{Tuple{String, String}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        values[(string(row[from_col]), string(row[to_col]))] = Float64(row[value_col])
    end
    return values
end

function _corridor_key(from_node::AbstractString, to_node::AbstractString)
    return from_node <= to_node ? (String(from_node), String(to_node)) : (String(to_node), String(from_node))
end

function _value_for_corridor_period(values::Dict{Tuple{String, String, Int}, Float64}, from_node::AbstractString, to_node::AbstractString, period::Integer)
    return get(values, (String(from_node), String(to_node), Int(period)), get(values, (String(to_node), String(from_node), Int(period)), 0.0))
end

function _value_for_corridor(values::Dict{Tuple{String, String}, Float64}, from_node::AbstractString, to_node::AbstractString)
    return get(values, (String(from_node), String(to_node)), get(values, (String(to_node), String(from_node)), 0.0))
end

function _line_type_for_corridor(transmission_line_types::Dict{Tuple{String, String}, String}, from_node::AbstractString, to_node::AbstractString)
    return get(transmission_line_types, (String(from_node), String(to_node)), get(transmission_line_types, (String(to_node), String(from_node)), "Unknown"))
end

function _generator_family(generator::AbstractString)
    lowercase_generator = lowercase(generator)
    contains(lowercase_generator, "windoffshore") && return "Wind offshore"
    contains(lowercase_generator, "wind_offshr") && return "Wind offshore"
    contains(lowercase_generator, "windonshore") && return "Wind onshore"
    contains(lowercase_generator, "wind_onshr") && return "Wind onshore"
    contains(lowercase_generator, "solar") && return "Solar"
    contains(lowercase_generator, "hydrorun") && return "Hydro run-of-river"
    contains(lowercase_generator, "hydro_ror") && return "Hydro run-of-river"
    contains(lowercase_generator, "hydroregulated") && return "Hydro regulated"
    contains(lowercase_generator, "hydro_reg") && return "Hydro regulated"
    contains(lowercase_generator, "nuclear") && return "Nuclear"
    contains(lowercase_generator, "wave") && return "Wave"
    contains(lowercase_generator, "geo") && return "Geothermal"
    contains(lowercase_generator, "waste") && return "Waste"
    contains(lowercase_generator, "bio10cofiringccs") && return "Bio cofiring CCS"
    contains(lowercase_generator, "bio10cofiring") && return "Bio cofiring"
    contains(lowercase_generator, "cofire") && return "Bio cofiring"
    contains(lowercase_generator, "bio") && return "Bio"
    contains(lowercase_generator, "gas") && contains(lowercase_generator, "ccs") && return "Gas CCS"
    contains(lowercase_generator, "gas") && return "Gas"
    contains(lowercase_generator, "coal") && contains(lowercase_generator, "ccs") && return "Coal CCS"
    contains(lowercase_generator, "coal") && return "Coal"
    contains(lowercase_generator, "lignite") && contains(lowercase_generator, "ccs") && return "Lignite CCS"
    contains(lowercase_generator, "liginite") && contains(lowercase_generator, "ccs") && return "Lignite CCS"
    contains(lowercase_generator, "lignite") && return "Lignite"
    contains(lowercase_generator, "liginite") && return "Lignite"
    contains(lowercase_generator, "oil") && return "Oil"
    lowercase_generator == "ccs" && return "CCS"
    lowercase_generator == "existing" && return "Existing"
    return String(generator)
end

function _series_color(series::AbstractString)
    return get(RESULT_SERIES_COLORS, series, _fallback_color(series))
end

function _transmission_type_color(line_type::AbstractString)
    return get(TRANSMISSION_TYPE_COLORS, line_type, "#2E86AB")
end

function _has_nonzero(values)
    return any(value -> abs(Float64(value)) > 1.0e-9, values)
end

function _hover_template(y_title::AbstractString)
    unit = _unit_suffix(y_title)
    value = isempty(unit) ? "%{y:,.1f}" : "%{y:,.1f} $unit"
    return "%{x}<br>%{fullData.name}: $value<extra></extra>"
end

function _unit_suffix(y_title::AbstractString)
    start_index = findfirst('[', y_title)
    end_index = findfirst(']', y_title)
    (start_index === nothing || end_index === nothing || end_index <= start_index) && return ""
    return y_title[nextind(y_title, start_index):prevind(y_title, end_index)]
end

function _format_value(value::Real)
    return string(round(Float64(value); digits = 2))
end

function _fallback_color(series::AbstractString)
    palette = (
        "#1f77b4",
        "#ff7f0e",
        "#2ca02c",
        "#d62728",
        "#9467bd",
        "#8c564b",
        "#e377c2",
        "#7f7f7f",
        "#bcbd22",
        "#17becf",
    )
    index = mod(sum(Int(c) for c in series), length(palette)) + 1
    return palette[index]
end

function _trace(
        ;
        x,
        y,
        name::AbstractString,
        type::AbstractString,
        mode::Union{Nothing, AbstractString} = nothing,
        color::Union{Nothing, AbstractString} = nothing,
        hovertemplate::Union{Nothing, AbstractString} = nothing,
    )
    fields = [
        "\"x\": $(_js_array(x))",
        "\"y\": $(_js_array(y))",
        "\"name\": $(_js_string(name))",
        "\"type\": $(_js_string(type))",
    ]
    mode === nothing || push!(fields, "\"mode\": $(_js_string(mode))")
    hovertemplate === nothing || push!(fields, "\"hovertemplate\": $(_js_string(hovertemplate))")
    if color !== nothing
        if type == "bar"
            push!(fields, "\"marker\": {\"color\": $(_js_string(color))}")
        else
            push!(fields, "\"line\": {\"color\": $(_js_string(color))}")
            push!(fields, "\"marker\": {\"color\": $(_js_string(color))}")
        end
    end
    return "{" * join(fields, ", ") * "}"
end

function _scattergeo_trace(
        ;
        lon,
        lat,
        name::AbstractString,
        mode::AbstractString,
        text = nothing,
        line_color::Union{Nothing, AbstractString} = nothing,
        line_width::Union{Nothing, Real} = nothing,
        marker_color::Union{Nothing, AbstractString} = nothing,
        marker_size::Union{Nothing, Real} = nothing,
        textposition::Union{Nothing, AbstractString} = nothing,
        hoverinfo::Union{Nothing, AbstractString} = nothing,
        visible::Bool = true,
    )
    fields = [
        "\"type\": \"scattergeo\"",
        "\"lon\": $(_js_array(lon))",
        "\"lat\": $(_js_array(lat))",
        "\"name\": $(_js_string(name))",
        "\"mode\": $(_js_string(mode))",
    ]
    text === nothing || push!(fields, "\"text\": $(_js_array(text))")
    textposition === nothing || push!(fields, "\"textposition\": $(_js_string(textposition))")
    hoverinfo === nothing || push!(fields, "\"hoverinfo\": $(_js_string(hoverinfo))")
    visible || push!(fields, "\"visible\": false")
    if line_color !== nothing || line_width !== nothing
        line_fields = String[]
        line_color === nothing || push!(line_fields, "\"color\": $(_js_string(line_color))")
        line_width === nothing || push!(line_fields, "\"width\": $(_js_value(line_width))")
        push!(fields, "\"line\": {" * join(line_fields, ", ") * "}")
    end
    if marker_color !== nothing || marker_size !== nothing
        marker_fields = String[]
        marker_color === nothing || push!(marker_fields, "\"color\": $(_js_string(marker_color))")
        marker_size === nothing || push!(marker_fields, "\"size\": $(_js_value(marker_size))")
        push!(fields, "\"marker\": {" * join(marker_fields, ", ") * "}")
    end
    return "{" * join(fields, ", ") * "}"
end

function _layout(
        title::AbstractString,
        x_title::AbstractString,
        y_title::AbstractString;
        barmode::Union{Nothing, AbstractString} = nothing,
        x_values = nothing,
    )
    xaxis_fields = [
        "\"title\": $(_js_string(x_title))",
        "\"type\": \"category\"",
    ]
    x_values === nothing || push!(xaxis_fields, "\"categoryarray\": $(_js_array(x_values))")
    fields = [
        "\"title\": $(_js_string(title))",
        "\"xaxis\": {" * join(xaxis_fields, ", ") * "}",
        "\"yaxis\": {\"title\": $(_js_string(y_title))}",
        "\"legend\": {\"orientation\": \"h\"}",
        "\"margin\": {\"l\": 70, \"r\": 20, \"t\": 70, \"b\": 70}",
    ]
    barmode === nothing || push!(fields, "\"barmode\": $(_js_string(barmode))")
    return "{" * join(fields, ", ") * "}"
end

function _geo_layout(
        title::AbstractString,
        periods::AbstractVector{<:Integer} = Int[],
        period_trace_indices::Dict{Int, Vector{Int}} = Dict{Int, Vector{Int}}(),
        trace_count::Integer = 0,
        base_title::AbstractString = title,
        active_period::Integer = isempty(periods) ? 0 : last(periods),
    )
    updatemenus = isempty(periods) ? nothing : _period_dropdown(periods, period_trace_indices, trace_count, base_title, active_period)
    fields = [
        "\"title\": $(_js_string(title))",
        "\"geo\": {\"scope\": \"europe\", \"showland\": true, \"landcolor\": \"#f5f5f5\", \"showcountries\": true, \"countrycolor\": \"#bbbbbb\", \"projection\": {\"type\": \"natural earth\"}}",
        "\"legend\": {\"orientation\": \"h\"}",
        "\"margin\": {\"l\": 20, \"r\": 20, \"t\": 70, \"b\": 20}",
    ]
    updatemenus === nothing || push!(fields, "\"updatemenus\": $updatemenus")
    return "{" * join(fields, ", ") * "}"
end

function _period_dropdown(
        periods::AbstractVector{<:Integer},
        period_trace_indices::Dict{Int, Vector{Int}},
        trace_count::Integer,
        base_title::AbstractString,
        active_period::Integer,
    )
    buttons = String[]
    for period in periods
        visible = falses(trace_count)
        for trace_index in get(period_trace_indices, Int(period), Int[])
            visible[trace_index] = true
        end
        push!(
            buttons,
            "{" *
            join([
                "\"label\": $(_js_string("Period $period"))",
                "\"method\": \"update\"",
                "\"args\": [{\"visible\": $(_js_array(visible))}, {\"title\": $(_js_string("$base_title - Period $period"))}]",
            ], ", ") *
            "}",
        )
    end
    return "[" * "{" * join([
        "\"buttons\": [" * join(buttons, ", ") * "]",
        "\"direction\": \"down\"",
        "\"showactive\": true",
        "\"active\": $(findfirst(==(active_period), periods) - 1)",
        "\"x\": 0.02",
        "\"xanchor\": \"left\"",
        "\"y\": 1.08",
        "\"yanchor\": \"top\"",
    ], ", ") * "}" * "]"
end

function _write_plotly_html(path::AbstractString, title::AbstractString, traces, layout::AbstractString)
    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>$(_html_escape(title))</title>
      <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
      <style>
        body { font-family: system-ui, sans-serif; margin: 24px; }
        #plot { width: 100%; height: 760px; }
      </style>
    </head>
    <body>
      <div id="plot"></div>
      <script>
        const data = [$(join(traces, ","))];
        const layout = $layout;
        Plotly.newPlot("plot", data, layout, {responsive: true});
      </script>
    </body>
    </html>
    """
    write(path, html)
    return path
end

function _plot_sections(plots, start_index::Integer)
    sections = String[]
    scripts = String[]
    for (offset, plot) in enumerate(plots)
        index = start_index + offset - 1
        div_id = "plot-$index"
        push!(
            sections,
            """
            <section>
              <h2>$(_html_escape(plot.title))</h2>
              <p><a href=\"$(_html_escape(plot.filename))\">Open standalone plot</a></p>
              $(_note_html(plot.note))
              <div id="$div_id" class="plot"></div>
            </section>
            """,
        )
        push!(
            scripts,
            """
            Plotly.newPlot("$div_id", [$(join(plot.traces, ","))], $(plot.layout), {responsive: true});
            """,
        )
    end
    return join(sections, "\n"), join(scripts, "\n")
end

function _write_dashboard_html(path::AbstractString, result_plots, input_plots)
    result_sections, result_scripts = _plot_sections(result_plots, 1)
    input_sections, input_scripts = _plot_sections(input_plots, length(result_plots) + 1)
    input_button = isempty(input_plots) ? "" : "<button class=\"tab-button\" onclick=\"showTab('inputs', event)\">Inputs</button>"

    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OpenEMPIRE Results Dashboard</title>
      <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
      <style>
        body { font-family: system-ui, sans-serif; margin: 24px; color: #222; }
        h1 { margin-bottom: 8px; }
        h2 { margin: 0 0 4px; font-size: 18px; }
        .tabs { display: flex; gap: 8px; border-bottom: 1px solid #ddd; margin-top: 24px; }
        .tab-button { background: #f7f7f7; border: 1px solid #ddd; border-bottom: none; padding: 10px 14px; cursor: pointer; }
        .tab-button.active { background: #fff; font-weight: 700; }
        .tab-panel { display: none; }
        .tab-panel.active { display: block; }
        section { border-top: 1px solid #ddd; padding-top: 24px; margin-top: 24px; }
        section p { margin: 0; }
        .note { margin-top: 8px; color: #555; max-width: 960px; }
        .plot { width: 100%; height: 680px; }
      </style>
    </head>
    <body>
      <h1>OpenEMPIRE Results Dashboard</h1>
      <div class="tabs">
        <button class="tab-button active" onclick="showTab('results', event)">Results</button>
        $input_button
      </div>
      <div id="results" class="tab-panel active">
      $result_sections
      </div>
      <div id="inputs" class="tab-panel">
      $input_sections
      </div>
      <script>
      function showTab(tabName, event) {
        for (const panel of document.querySelectorAll('.tab-panel')) {
          panel.classList.remove('active');
        }
        for (const button of document.querySelectorAll('.tab-button')) {
          button.classList.remove('active');
        }
        document.getElementById(tabName).classList.add('active');
        event.currentTarget.classList.add('active');
        window.dispatchEvent(new Event('resize'));
      }
      $result_scripts
      $input_scripts
      </script>
    </body>
    </html>
    """
    write(path, html)
    return path
end

_js_array(values) = "[" * join((_js_value(v) for v in values), ", ") * "]"
_js_value(value::AbstractString) = _js_string(value)
_js_value(value::Integer) = string(value)
_js_value(value::Real) = isfinite(value) ? string(Float64(value)) : "null"
_js_string(value::AbstractString) = "\"" * replace(value, "\\" => "\\\\", "\"" => "\\\"") * "\""

function _html_escape(value::AbstractString)
    return replace(value, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
end

_note_html(note::AbstractString) = isempty(note) ? "" : "<p class=\"note\">$(_html_escape(note))</p>"
