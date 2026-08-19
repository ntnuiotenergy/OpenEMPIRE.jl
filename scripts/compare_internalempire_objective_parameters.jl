#!/usr/bin/env julia

using CSV
using OpenEMPIRE
using TimeStruct
using YAML

length(ARGS) in (3, 4) || error(
    "usage: compare_internalempire_objective_parameters.jl " *
    "IE_PARAMETERS.csv CONFIG.yaml DATASET [IE_PROCESSED_LOAD.csv]",
)

parameter_file, config_file, data_folder = ARGS[1:3]
config = YAML.load_file(config_file)
_, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    input_format = :csv,
)
strategic_periods = collect(strat_periods(periods))
discounter = Discounter(params.discountRate, 1, periods)

function julia_value(parameter, key, period_index)
    strategic_period = isempty(period_index) ? nothing : strategic_periods[parse(Int, period_index)]
    if parameter == "genMargCost"
        return params.genMargCost[key][strategic_period]
    elseif parameter == "genInvCost"
        return OpenEMPIRE.gen_invest_cost(params, key, strategic_period)
    elseif parameter == "storENInvCost"
        return OpenEMPIRE.stor_en_invest_cost(params, key, strategic_period)
    elseif parameter == "storPWInvCost"
        return OpenEMPIRE.stor_pw_invest_cost(params, key, strategic_period)
    elseif parameter == "transmissionInvCost"
        node_from, node_to = split(key, "|"; limit = 2)
        return OpenEMPIRE.trans_invest_cost(params, node_from, node_to, strategic_period)
    elseif parameter == "discount_multiplier"
        return objective_weight(strategic_period, discounter)
    elseif parameter == "operationalDiscountrate"
        years = Int(round(duration_strat(first(strategic_periods))))
        return sum((1 + params.discountRate)^(-year) for year in 0:(years - 1))
    elseif parameter == "sceProbab"
        return 1 / OpenEMPIRE.weather_scenario_count(config)
    elseif parameter == "GasSceProbab"
        return 1 / OpenEMPIRE.gas_scenario_count(config)
    elseif parameter == "seasScale"
        representative_index = findfirst(==(key), params.seasonNames)
        representative = collect(repr_periods(first(strategic_periods)))[representative_index]
        return multiple_strat(first(strategic_periods), first(first(opscenarios(representative))))
    elseif parameter == "ng_terminalCost"
        node, terminal, gas_scenario = split(key, "|"; limit = 3)
        return OpenEMPIRE.natural_gas_terminal_cost(
            params,
            node,
            terminal,
            parse(Int, period_index),
            parse(Int, gas_scenario),
        )
    elseif parameter == "ng_pipelinePowerDemandPerTon"
        return params.NaturalGas.pipelinePowerDemandPerTon
    end
    return nothing
end

differences = Dict{String, Vector{NamedTuple}}()
for row in CSV.File(parameter_file; types = String)
    parameter = String(row.parameter)
    parameter in (
        "genMargCost",
        "genInvCost",
        "storENInvCost",
        "storPWInvCost",
        "transmissionInvCost",
        "discount_multiplier",
        "operationalDiscountrate",
        "sceProbab",
        "GasSceProbab",
        "seasScale",
        "ng_terminalCost",
        "ng_pipelinePowerDemandPerTon",
    ) || continue
    internal_value = parse(Float64, row.value)
    key = coalesce(row.key, "")
    period = coalesce(row.period, "")
    port_value = julia_value(parameter, key, period)
    absolute = abs(port_value - internal_value)
    scale = max(abs(port_value), abs(internal_value), 1.0)
    push!(
        get!(differences, parameter, NamedTuple[]),
        (;
            key,
            period,
            internal_value,
            port_value,
            absolute,
            relative = absolute / scale,
        ),
    )
end

for parameter in sort!(collect(keys(differences)))
    rows = differences[parameter]
    sort!(rows; by = row -> row.absolute, rev = true)
    maximum_row = first(rows)
    differing = count(row -> row.absolute > 1e-9 * max(abs(row.internal_value), 1.0), rows)
    println(
        "$parameter: entries=$(length(rows)) differing=$differing " *
        "max_abs=$(maximum_row.absolute) max_rel=$(maximum_row.relative) " *
        "at=$(maximum_row.key)|$(maximum_row.period) " *
        "internal=$(maximum_row.internal_value) julia=$(maximum_row.port_value)",
    )
end

function compare_processed_load(load_file, config, params, periods)
    load_rows = collect(CSV.File(load_file))
    period_labels = unique(String(row.Period) for row in load_rows)
    period_indices = Dict(label => index for (index, label) in enumerate(period_labels))
    time_lookup = Dict{Tuple{Int, Int, Int, String, Int}, Any}()
    OpenEMPIRE._foreach_operational_context(params, periods) do period_index,
        _, combined_scenario, _, season, hour, time
        gas_count = OpenEMPIRE.gas_scenario_count(config)
        weather = OpenEMPIRE.weather_scenario_index(combined_scenario, gas_count)
        gas = OpenEMPIRE.gas_scenario_index(combined_scenario, gas_count)
        time_lookup[(period_index, weather, gas, season, hour)] = time
    end

    maximum_absolute = 0.0
    maximum_relative = 0.0
    maximum_key = nothing
    differing = 0
    for row in load_rows
        period_index = period_indices[String(row.Period)]
        weather = parse(Int, replace(String(row.Scenario), "scenario" => ""))
        gas = Int(row.GasScenario)
        season = String(row.Season)
        hour = Int(row.Hour)
        node = String(row.Node)
        internal_value = Float64(row.var"Electric load [MW]")
        port_value = OpenEMPIRE.load(
            params,
            node,
            time_lookup[(period_index, weather, gas, season, hour)],
        )
        absolute = abs(port_value - internal_value)
        relative = absolute / max(abs(port_value), abs(internal_value), 1.0)
        differing += absolute > 1e-9 * max(abs(internal_value), 1.0)
        if absolute > maximum_absolute
            maximum_absolute = absolute
            maximum_relative = relative
            maximum_key = (node, period_index, weather, gas, season, hour, internal_value, port_value)
        end
    end
    println(
        "processed_load: entries=$(length(load_rows)) differing=$differing " *
        "max_abs=$maximum_absolute max_rel=$maximum_relative at=$maximum_key",
    )
    return nothing
end

if length(ARGS) == 4
    compare_processed_load(ARGS[4], config, params, periods)
end
