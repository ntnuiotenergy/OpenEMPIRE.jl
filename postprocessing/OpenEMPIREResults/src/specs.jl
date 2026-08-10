"""
Plot specifications.

Two families of result CSV live side by side in a run's output directory:

  * **Report tables** (`results_output_gen.csv`, `results_output_EuropeSummary.csv`, …)
    hold scenario- and season-weighted annual quantities, and label periods
    `"2020-2025"`.
  * **Raw variable dumps** (`genInvCap.csv`, `genOperational.csv`, …) hold one row
    per JuMP variable with integer period indices and no weighting at all.

Prefer the report tables: summing a raw dump over exported hours does not give
annual generation, and presenting it as though it does is how a dashboard starts
lying. Raw dumps are used only where no report table covers the quantity, and are
labelled as diagnostics.
"""

function _available_result_plot_specs(output_dir::AbstractString, input_dir::Union{Nothing, AbstractString})
    specs = NamedTuple[]
    node_coordinates = _read_node_coordinates(input_dir)
    transmission_line_types = _read_transmission_line_types(input_dir)

    gen_report = joinpath(output_dir, "results_output_gen.csv")
    stor_report = joinpath(output_dir, "results_output_stor.csv")
    transmission_report = joinpath(output_dir, "results_output_transmission.csv")
    europe_summary = joinpath(output_dir, "results_output_EuropeSummary.csv")
    curtailed = joinpath(output_dir, "results_output_curtailed_prod.csv")

    # --- Headline: what the system produces, and what it costs ----------------

    if isfile(gen_report)
        push!(specs, _stacked_bar_spec(
            gen_report,
            "Annual Generation by Technology",
            :Period,
            :GeneratorType,
            :genExpectedAnnualProduction_GWh,
            "Expected annual production [GWh]";
            filename = "generation_mix.html",
            series_mapper = _generator_family,
            note = "Scenario- and season-weighted expected annual production. This is the generation mix; the operational diagnostic further down is not.",
        ))
        push!(specs, _stacked_bar_spec(
            gen_report,
            "Installed Generation Capacity",
            :Period,
            :GeneratorType,
            :genInstalledCap_MW,
            "Installed capacity [MW]";
            filename = "generator_installed_capacity.html",
            series_mapper = _generator_family,
            note = "Existing capacity plus investments still within their lifetime in each period.",
        ))
        push!(specs, _stacked_bar_spec(
            gen_report,
            "New Generation Investment",
            :Period,
            :GeneratorType,
            :genInvCap_MW,
            "New investment capacity [MW]";
            filename = "generator_investment_capacity.html",
            series_mapper = _generator_family,
            note = "Capacity the model chooses to build in each strategic period.",
        ))
        push!(specs, _capacity_factor_spec(
            gen_report;
            filename = "generator_capacity_factor.html",
        ))
        push!(specs, _node_investment_bar_spec(
            gen_report,
            "New Generation Investment by Node",
            :Period,
            :Node,
            :GeneratorType,
            :genInvCap_MW,
            "New investment capacity [MW]";
            filename = "generator_investment_capacity_by_node.html",
            series_mapper = _generator_family,
            note = "Where new generation capacity is built. Nodes with no investment in any period are omitted.",
        ))
    end

    cost_spec = _investment_cost_spec(gen_report, stor_report, transmission_report; filename = "discounted_investment_cost.html")
    cost_spec === nothing || push!(specs, cost_spec)

    # --- System-level outcomes -------------------------------------------------

    if isfile(europe_summary)
        emission_spec = _emission_spec(europe_summary; filename = "co2_emissions.html")
        emission_spec === nothing || push!(specs, emission_spec)

        push!(specs, _scenario_series_spec(
            europe_summary,
            "Average Electricity Price",
            :AvgELPrice_EuroPerMWh,
            "Average price [EUR/MWh]";
            filename = "electricity_price.html",
            note = "Load-weighted average of the flow-balance dual across nodes and hours, one series per scenario.",
        ))
        push!(specs, _scenario_series_spec(
            europe_summary,
            "Curtailed Renewable Generation",
            :TotAnnualCurtailedRES_GWh,
            "Curtailed RES [GWh]";
            filename = "curtailed_res.html",
            note = "Available renewable energy not used, by scenario.",
        ))
        losses_spec = _losses_spec(europe_summary; filename = "system_losses.html")
        losses_spec === nothing || push!(specs, losses_spec)
    end

    if isfile(curtailed)
        push!(specs, _stacked_bar_spec(
            curtailed,
            "Curtailment by Technology",
            :Period,
            :RESGeneratorType,
            :ExpectedAnnualCurtailment_GWh,
            "Expected annual curtailment [GWh]";
            filename = "curtailment_by_technology.html",
            series_mapper = _generator_family,
            note = "Which renewable technologies are being curtailed, expected annual volumes.",
        ))
    end

    # --- Storage ---------------------------------------------------------------

    if isfile(stor_report)
        push!(specs, _stacked_bar_spec(
            stor_report,
            "Installed Storage Power Capacity",
            :Period,
            :StorageType,
            :storPWInstalledCap_MW,
            "Installed storage power [MW]";
            filename = "storage_power_capacity.html",
            note = "Maximum charge/discharge rate of installed storage.",
        ))
        push!(specs, _stacked_bar_spec(
            stor_report,
            "Installed Storage Energy Capacity",
            :Period,
            :StorageType,
            :storENInstalledCap_MWh,
            "Installed storage energy [MWh]";
            filename = "storage_energy_capacity.html",
            note = "Storage volume.",
        ))
        push!(specs, _stacked_bar_spec(
            stor_report,
            "Annual Storage Discharge",
            :Period,
            :StorageType,
            :ExpectedAnnualDischargeVolume_GWh,
            "Expected annual discharge [GWh]";
            filename = "storage_discharge.html",
            note = "How much the installed storage is actually used.",
        ))
    end

    # --- Transmission ----------------------------------------------------------

    if isfile(transmission_report)
        push!(specs, _corridor_spec(
            transmission_report,
            "Installed Transmission Capacity by Corridor",
            :transmissionInstalledCap_MW,
            "Installed capacity [MW]";
            filename = "transmission_installed_capacity.html",
            note = "Largest corridors by installed capacity. Corridors that never carry capacity are omitted.",
        ))
        push!(specs, _corridor_spec(
            transmission_report,
            "Annual Transmission Volume by Corridor",
            :transmissionExpectedAnnualVolume_GWh,
            "Expected annual volume [GWh]";
            filename = "transmission_volume.html",
            note = "Energy actually moved across each corridor, expected annual volumes.",
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
            note = "Modelled interconnectors by period. Line width is scaled by installed capacity and colour indicates line type.",
        )
        map_spec === nothing || push!(specs, map_spec)
    end

    # --- Diagnostics -----------------------------------------------------------
    #
    # Raw, unweighted variable dumps. Kept because they are useful when chasing an
    # implausible result, but explicitly marked so they are not read as annual
    # quantities.

    load_shed = joinpath(output_dir, "loadShed.csv")
    if _raw_dump_is_plottable(load_shed, "Load Shedding (diagnostic)")
        push!(specs, _stacked_bar_spec(
            load_shed,
            "Load Shedding (diagnostic)",
            :Period,
            :Node,
            :loadShed,
            "Sum over exported hours [MWh]";
            filename = "load_shed.html",
            note = "Diagnostic: raw sum over exported operational rows, not scenario- or season-weighted. Any non-zero value is worth investigating.",
        ))
    end

    gen_operation = joinpath(output_dir, "genOperational.csv")
    if _raw_dump_is_plottable(gen_operation, "Operational Generation (diagnostic)")
        push!(specs, _stacked_bar_spec(
            gen_operation,
            "Operational Generation (diagnostic)",
            :Period,
            :Generator,
            :genOperational,
            "Sum over exported hours [MWh]";
            filename = "generator_operational.html",
            series_mapper = _generator_family,
            note = "Diagnostic: raw sum over exported operational rows. For annual generation use the generation mix plot at the top.",
        ))
    end

    return specs
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

    co2_cap = joinpath(input_dir, "General", "CO2cap.csv")
    if isfile(co2_cap)
        push!(specs, _single_line_spec(
            co2_cap,
            "Input CO2 Cap",
            1,
            2,
            "CO2 cap [Mt]";
            filename = "input_co2_cap.html",
            series_name = "CO2 cap",
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


# ---------------------------------------------------------------------------
# Generic builders
# ---------------------------------------------------------------------------

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
        x_title::AbstractString = "Period",
    )
    grouped = _group_sum(csv_path, x_col, series_col, value_col; series_mapper)
    x_values = _sort_categories(unique(first.(keys(grouped))))
    series_values = _sort_categories(unique(last.(keys(grouped))))
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (x, series), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end
    layout = _layout(title, x_title, y_title; barmode = "stack", x_values = x_values)
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
    grouped = Dict{Tuple{String, String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (_category(row[period_col]), string(row[node_col]), string(series_mapper(string(row[series_col]))))
        grouped[key] = get(grouped, key, 0.0) + _number(row[value_col])
    end

    # Nodes that never receive an investment contribute only empty columns, and on
    # a European dataset they dominate the axis. Drop them.
    active_nodes = Set(node for ((_, node, _), value) in grouped if abs(value) > 1.0e-9)
    isempty(active_nodes) && return (
        filename = filename, title = title, traces = String[],
        layout = _layout(title, "Period / Node", y_title; barmode = "stack"), note = note,
    )

    periods = _sort_categories(unique(period for (period, _, _) in keys(grouped)))
    nodes = sort!(collect(active_nodes))
    period_nodes = [(period, node) for period in periods for node in nodes]
    x_labels = ["$period / $node" for (period, node) in period_nodes]
    series_values = _sort_categories(unique(series for (_, _, series) in keys(grouped)))

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

"""
    _corridor_spec(csv_path, title, value_col, y_title; max_corridors)

One line per transmission corridor over periods.

A European dataset has several hundred corridors; drawing them all produces an
unreadable plot and an unusable legend, so only the `max_corridors` largest are
drawn and the note records how many were dropped.
"""
function _corridor_spec(
        csv_path::AbstractString,
        title::AbstractString,
        value_col::Symbol,
        y_title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
        max_corridors::Int = 25,
    )
    grouped = Dict{Tuple{String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        corridor = string(row.BetweenNode, "-", row.AndNode)
        key = (_category(row.Period), corridor)
        grouped[key] = get(grouped, key, 0.0) + _number(row[value_col])
    end

    x_values = _sort_categories(unique(first.(keys(grouped))))

    peak = Dict{String, Float64}()
    for ((_, corridor), value) in grouped
        peak[corridor] = max(get(peak, corridor, 0.0), abs(value))
    end
    ranked = sort!([corridor for (corridor, value) in peak if value > 1.0e-9]; by = corridor -> -peak[corridor])
    shown = first(ranked, max_corridors)
    dropped = length(ranked) - length(shown)

    traces = String[]
    for corridor in shown
        y_values = [get(grouped, (x, corridor), 0.0) for x in x_values]
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = corridor,
            type = "scatter",
            mode = "lines+markers",
            color = _series_color(corridor),
            hovertemplate = _hover_template(y_title),
        ))
    end

    full_note = dropped > 0 ?
        strip(string(note, " Showing the ", length(shown), " largest of ", length(ranked), " corridors; ", dropped, " smaller ones are omitted.")) :
        note
    layout = _layout(title, "Period", y_title; x_values = x_values)
    return (filename = filename, title = title, traces = traces, layout = layout, note = String(full_note))
end

"""
    _scenario_series_spec(csv_path, title, value_col, y_title)

One line per scenario over periods, from `results_output_EuropeSummary.csv`.

Keeping scenarios separate rather than averaging them is the point: the spread
between them is what a stochastic run is for.
"""
function _scenario_series_spec(
        csv_path::AbstractString,
        title::AbstractString,
        value_col::Symbol,
        y_title::AbstractString;
        filename::AbstractString,
        note::AbstractString = "",
        scale::Float64 = 1.0,
    )
    grouped = Dict{Tuple{String, String}, Float64}()
    for row in _read_csv_section(csv_path, 1)
        grouped[(_category(row.Period), string(row.Scenario))] = _number(row[value_col]) * scale
    end
    isempty(grouped) && return nothing

    x_values = _sort_categories(unique(first.(keys(grouped))))
    scenarios = _sort_categories(unique(last.(keys(grouped))))

    traces = String[]
    for scenario in scenarios
        y_values = [get(grouped, (x, scenario), 0.0) for x in x_values]
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = scenario,
            type = "scatter",
            mode = "lines+markers",
            color = _series_color(scenario),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout(title, "Period", y_title; x_values = x_values)
    return (filename = filename, title = title, traces = traces, layout = layout, note = note)
end

"""
    _emission_spec(europe_summary_path)

CO2 emissions per scenario against the cap, both in Mt.

The cap is the binding constraint in most runs, so showing emissions without it
hides the only thing the reader wants to check.
"""
function _emission_spec(csv_path::AbstractString; filename::AbstractString)
    emissions = Dict{Tuple{String, String}, Float64}()
    caps = Dict{String, Float64}()
    for row in _read_csv_section(csv_path, 1)
        period = _category(row.Period)
        emissions[(period, string(row.Scenario))] = _number(row.AnnualCO2emission_Ton) / 1.0e6
        caps[period] = _number(row.CO2Cap_Ton) / 1.0e6
    end
    isempty(emissions) && return nothing

    x_values = _sort_categories(unique(first.(keys(emissions))))
    scenarios = _sort_categories(unique(last.(keys(emissions))))
    y_title = "Annual CO2 [Mt]"

    traces = String[]
    for scenario in scenarios
        y_values = [get(emissions, (x, scenario), 0.0) for x in x_values]
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = scenario,
            type = "bar",
            color = _series_color(scenario),
            hovertemplate = _hover_template(y_title),
        ))
    end

    cap_values = [get(caps, x, 0.0) for x in x_values]
    if _has_nonzero(cap_values)
        push!(traces, _trace(
            ;
            x = x_values,
            y = cap_values,
            name = "CO2 cap",
            type = "scatter",
            mode = "lines+markers",
            color = "#d62728",
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout("CO2 Emissions vs Cap", "Period", y_title; barmode = "group", x_values = x_values)
    note = _has_nonzero(cap_values) ?
        "Emissions per scenario against the emission cap. Bars at the cap line mean the constraint is binding." :
        "Emissions per scenario. No emission cap is active in this run, so a CO2 price applies instead."
    return (filename = filename, title = "CO2 Emissions vs Cap", traces = traces, layout = layout, note = note)
end

"""
    _losses_spec(europe_summary_path)

Transmission and storage losses per period, averaged over scenarios.
"""
function _losses_spec(csv_path::AbstractString; filename::AbstractString)
    totals = Dict{Tuple{String, String}, Float64}()
    counts = Dict{String, Int}()
    for row in _read_csv_section(csv_path, 1)
        period = _category(row.Period)
        counts[period] = get(counts, period, 0) + 1
        for (name, column) in (
                ("Transmission losses", :AnnualLossesTransmission_GWh),
                ("Storage charge/discharge losses", :TotAnnualLossesChargeDischarge_GWh),
            )
            key = (period, name)
            totals[key] = get(totals, key, 0.0) + _number(row[column])
        end
    end
    isempty(totals) && return nothing

    x_values = _sort_categories(collect(keys(counts)))
    y_title = "Expected annual losses [GWh]"
    traces = String[]
    for name in ("Transmission losses", "Storage charge/discharge losses")
        y_values = [get(totals, (x, name), 0.0) / max(get(counts, x, 1), 1) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = name,
            type = "bar",
            color = _series_color(name),
            hovertemplate = _hover_template(y_title),
        ))
    end
    isempty(traces) && return nothing

    layout = _layout("System Losses", "Period", y_title; barmode = "stack", x_values = x_values)
    return (
        filename = filename, title = "System Losses", traces = traces, layout = layout,
        note = "Mean across scenarios of transmission and storage losses.",
    )
end

"""
    _investment_cost_spec(gen_report, stor_report, transmission_report)

Discounted investment cost per period, split by asset class.

Reads the three report tables rather than the objective decomposition so the plot
still appears when only some of them were written.
"""
function _investment_cost_spec(
        gen_report::AbstractString,
        stor_report::AbstractString,
        transmission_report::AbstractString;
        filename::AbstractString,
    )
    sources = (
        ("Generation", gen_report, :DiscountedInvestmentCost_Euro),
        ("Storage", stor_report, :DiscountedInvestmentCostPWEN_EuroPerMWMWh),
        ("Transmission", transmission_report, :DiscountedInvestmentCost_Euro),
    )

    totals = Dict{Tuple{String, String}, Float64}()
    for (name, path, column) in sources
        isfile(path) || continue
        for row in CSV.File(path; normalizenames = false)
            key = (_category(row.Period), name)
            totals[key] = get(totals, key, 0.0) + _number(row[column]) / 1.0e6
        end
    end
    isempty(totals) && return nothing

    x_values = _sort_categories(unique(first.(keys(totals))))
    y_title = "Discounted investment cost [MEUR]"
    traces = String[]
    for (name, _, _) in sources
        y_values = [get(totals, (x, name), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = name,
            type = "bar",
            color = _series_color(name),
            hovertemplate = _hover_template(y_title),
        ))
    end
    isempty(traces) && return nothing

    layout = _layout("Discounted Investment Cost", "Period", y_title; barmode = "stack", x_values = x_values)
    return (
        filename = filename, title = "Discounted Investment Cost", traces = traces, layout = layout,
        note = "Investment cost by asset class, discounted to the start of the horizon. These are the same figures that enter the objective.",
    )
end

"""
    _capacity_factor_spec(gen_report)

Capacity-weighted mean capacity factor per technology and period.

A plain mean over rows would weight a 10 MW plant the same as a 10 GW one, so the
factor is recomputed from summed production and summed capacity.
"""
function _capacity_factor_spec(csv_path::AbstractString; filename::AbstractString)
    production = Dict{Tuple{String, String}, Float64}()
    capacity = Dict{Tuple{String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (_category(row.Period), _generator_family(string(row.GeneratorType)))
        production[key] = get(production, key, 0.0) + _number(row.genExpectedAnnualProduction_GWh) * 1000
        capacity[key] = get(capacity, key, 0.0) + _number(row.genInstalledCap_MW)
    end

    x_values = _sort_categories(unique(first.(keys(capacity))))
    series_values = _sort_categories(unique(last.(keys(capacity))))
    y_title = "Capacity factor [-]"

    traces = String[]
    for series in series_values
        y_values = [
            let installed = get(capacity, (x, series), 0.0)
                installed <= 1.0e-9 ? 0.0 : get(production, (x, series), 0.0) / (installed * 8760)
            end
            for x in x_values
        ]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(series),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout("Capacity Factor by Technology", "Period", y_title; barmode = "group", x_values = x_values)
    return (
        filename = filename, title = "Capacity Factor by Technology", traces = traces, layout = layout,
        note = "Expected annual production divided by installed capacity times 8760, aggregated over nodes so large plants weigh more than small ones.",
    )
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
    points = Tuple{String, Float64}[]
    for row in CSV.File(csv_path; normalizenames = false)
        push!(points, (_category(row[x_col]), _number(row[value_col])))
    end
    sort!(points; by = point -> _category_sort_key(first(point)))
    x_labels = first.(points)
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
    grouped = _group_sum(csv_path, x_col, series_col, value_col)

    x_values = _sort_categories(unique(first.(keys(grouped))))
    series_values = _sort_categories(unique(last.(keys(grouped))))
    traces = String[]
    for series in series_values
        y_values = [get(grouped, (x, series), 0.0) for x in x_values]
        _has_nonzero(y_values) || continue
        push!(traces, _trace(
            ;
            x = x_values,
            y = y_values,
            name = series,
            type = "bar",
            color = _series_color(_generator_family(series)),
            hovertemplate = _hover_template(y_title),
        ))
    end

    layout = _layout(title, "Period", y_title; barmode = "group", x_values = x_values)
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
        grouped[(node, series)] = get(grouped, (node, series), 0.0) + _number(row[value_col])
    end

    nodes = sort!(collect(unique(first.(keys(grouped)))))
    series_values = _sort_categories(unique(last.(keys(grouped))))
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
