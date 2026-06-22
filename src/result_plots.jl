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

function write_result_plots(
        result_dir::AbstractString;
        output_dir::AbstractString = joinpath(result_dir, "Output"),
        plot_dir::AbstractString = joinpath(result_dir, "Plots"),
        input_dir::Union{Nothing, AbstractString} = nothing,
    )
    mkpath(plot_dir)

    result_specs = _available_result_plot_specs(output_dir)
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
    input_html_plots = html_plots[(n_result_specs + 1):end]
    _write_dashboard_html(dashboard_path, result_html_plots, input_html_plots)
    return dashboard_path
end

function _available_result_plot_specs(output_dir::AbstractString)
    specs = NamedTuple[]

    gen_investment = joinpath(output_dir, "genInvCap.csv")
    if isfile(gen_investment)
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
    end

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

    gen_operation = joinpath(output_dir, "genOperational.csv")
    if isfile(gen_operation)
        push!(specs, _stacked_bar_spec(
            gen_operation,
            "Operational Generation Over Exported Hours",
            :Period,
            :Generator,
            :genOperational,
            "Sum over exported operational hours [MW-hour rows]";
            filename = "generator_operational.html",
            series_mapper = _generator_family,
            note = "Diagnostic plot: this sums raw exported operational rows and is not scenario/season weighted annual generation.",
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

    return specs
end

function _available_input_plot_specs(input_dir::AbstractString)
    specs = NamedTuple[]

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
        push!(traces, _trace(; x = x_labels, y = y_values, name = series, type = "bar", color = _series_color(series)))
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
        push!(traces, _trace(; x = x_labels, y = y_values, name = series, type = "bar", color = _series_color(series)))
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
        push!(traces, _trace(
            ;
            x = x_labels,
            y = y_values,
            name = series,
            type = "scatter",
            mode = "lines+markers",
            color = _series_color(series),
        ))
    end
    layout = _layout(title, "Period", y_title; x_values = x_labels)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
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
    traces = [_trace(; x = x_labels, y = y_values, name = series_name, type = "scatter", mode = "lines+markers")]
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
        push!(traces, _trace(; x = x_labels, y = y_values, name = series, type = "bar", color = _series_color(_generator_family(series))))
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
        push!(traces, _trace(; x = nodes, y = y_values, name = series, type = "bar", color = _series_color(series)))
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
    )
    fields = [
        "\"x\": $(_js_array(x))",
        "\"y\": $(_js_array(y))",
        "\"name\": $(_js_string(name))",
        "\"type\": $(_js_string(type))",
    ]
    mode === nothing || push!(fields, "\"mode\": $(_js_string(mode))")
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
