#!/usr/bin/env julia

using CSV
using JuMP
using OpenEMPIRE
using TimeStruct

length(ARGS) == 3 || error(
    "usage: check_internalempire_hydrogen_solution_feasibility.jl " *
    "IE_RAW_SOLUTION.csv CONFIG.yaml DATASET",
)

solution_file, config_file, data_folder = ARGS
model, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    input_format = :csv,
)
strategic_periods = collect(strat_periods(periods))
gas_count = params.NaturalGas.gasScenarioCount
time_lookup = Dict{Tuple{Int, Int, Int, Int}, Any}()
OpenEMPIRE._foreach_operational_context(params, periods) do period_index,
    _, combined_scenario, _, _, hour, time
    weather = OpenEMPIRE.weather_scenario_index(combined_scenario, gas_count)
    gas = OpenEMPIRE.gas_scenario_index(combined_scenario, gas_count)
    time_lookup[(period_index, weather, gas, hour)] = time
end

const STRATEGIC_COMPONENTS = Dict(
    "genInvCap" => "genInvCap",
    "genInstalledCap" => "genInstalledCap",
    "transmissionInvCap" => "transmissionInvCap",
    "transmissionInstalledCap" => "transmissionInstalledCap",
    "storPWInvCap" => "storPWInvCap",
    "storPWInstalledCap" => "storPWInstalledCap",
    "storENInvCap" => "storENInvCap",
    "storENInstalledCap" => "storENInstalledCap",
    "offshoreConvInvCap" => "offshoreConvInvCap",
    "offshoreConvInstalledCap" => "offshoreConvInstalledCap",
    "H2ImportCapBuilt" => "hydrogenImportCapBuilt",
    "H2ImportTotalCap" => "hydrogenImportCapInstalled",
    "elyzerCapBuilt" => "electrolyzerCapBuilt",
    "elyzerTotalCap" => "electrolyzerCapInstalled",
    "ReformerCapBuilt" => "reformerCapBuilt",
    "ReformerTotalCap" => "reformerCapInstalled",
    "hydrogenPipelineBuilt" => "hydrogenPipelineCapBuilt",
    "repurposedPipelineBuilt" => "hydrogenRepurposedGasPipelineCapBuilt",
    "totalHydrogenPipelineCapacity" => "hydrogenPipelineCapInstalled",
    "hydrogenStorageBuilt" => "hydrogenStorageCapBuilt",
    "hydrogenTotalStorage" => "hydrogenStorageCapInstalled",
    "CO2PipelineBuilt" => "co2PipelineCapBuilt",
    "totalCO2PipelineCapacity" => "co2PipelineCapInstalled",
    "CO2SiteCapacityDeveloped" => "co2SequestrationCapBuilt",
)

const UNDIRECTED_STRATEGIC = Set([
    "transmissionInvCap",
    "transmissionInstalledCap",
    "hydrogenPipelineBuilt",
    "totalHydrogenPipelineCapacity",
    "CO2PipelineBuilt",
    "totalCO2PipelineCapacity",
])

const OPERATIONAL_COMPONENTS = Dict(
    "genOperational" => ("genOperational", false),
    "transmissionOperational" => ("transmissionOperational", false),
    "storCharge" => ("storCharge", false),
    "storDischarge" => ("storDischarge", false),
    "storOperational" => ("storOperational", false),
    "loadShed" => ("loadShed", false),
    "ng_terminalImport" => ("ngTerminalImport", false),
    "ng_transmission" => ("ngTransmission", false),
    "ng_forPower" => ("ngForPower", false),
    "ng_storageOperational" => ("ngStorageOperational", false),
    "ng_chargeStorage" => ("ngStorageCharge", false),
    "ng_dischargeStorage" => ("ngStorageDischarge", false),
    "transport_naturalGasDemandMet" => ("transportNaturalGasDemandMet", false),
    "transport_naturalGasDemandShed" => ("transportNaturalGasDemandShed", false),
    "hydrogenProducedElectro_ton" => ("electrolyzerHydrogen", false),
    "powerForHydrogen" => ("electrolyzerElectricity", false),
    "hydrogenProducedReformer_ton" => ("reformerHydrogenTon", false),
    "hydrogenProducedReformer_MWh" => ("reformerHydrogenMWh", false),
    "ng_forHydrogen" => ("reformerNaturalGas", false),
    "H2Imported_ton" => ("hydrogenImportTon", false),
    "H2Imported_MWh" => ("hydrogenImportMWh", false),
    "hydrogenSentPipeline" => ("hydrogenPipelineFlow", false),
    "hydrogenStorageOperational" => ("hydrogenStorageLevel", false),
    "hydrogenChargeStorage" => ("hydrogenStorageCharge", false),
    "hydrogenDischargeStorage" => ("hydrogenStorageDischarge", false),
    "hydrogen_storage_compression_power" => ("hydrogenStorageCompressionPower", false),
    "hydrogenForPower" => ("hydrogenForPower", true),
    "transport_electricityDemandMet" => ("transportElectricityDemandMet", false),
    "transport_electricityDemandShed" => ("transportElectricityDemandShed", false),
    "transport_hydrogenDemandMet" => ("transportHydrogenDemandMet", false),
    "transport_hydrogenDemandShed" => ("transportHydrogenDemandShed", false),
    "CO2sentPipeline" => ("co2PipelineFlow", false),
    "CO2sequestered" => ("co2Sequestered", false),
)

function parse_variable_name(name)
    matched = match(r"^([^\[]+)\[(.*)\]$", name)
    matched === nothing && return name, String[]
    indices = [strip(index, ['\'', '"']) for index in split(matched.captures[2], ',')]
    return matched.captures[1], indices
end

function julia_variable(model, component, indices)
    target = get(STRATEGIC_COMPONENTS, component, nothing)
    if target !== nothing
        parsed = Any[indices[1:end-1]...]
        if component in UNDIRECTED_STRATEGIC && parsed[2] < parsed[1]
            parsed[1], parsed[2] = parsed[2], parsed[1]
        end
        push!(parsed, strategic_periods[parse(Int, indices[end])])
        return model[Symbol(target)][parsed...]
    end

    operational = get(OPERATIONAL_COMPONENTS, component, nothing)
    operational === nothing && return nothing
    target, reverse_first_pair = operational
    prefix = Any[indices[1:end-4]...]
    reverse_first_pair && reverse!(prefix)
    hour = parse(Int, indices[end-3])
    period = parse(Int, indices[end-2])
    weather = parse(Int, replace(indices[end-1], "scenario" => ""))
    gas = parse(Int, indices[end])
    time = time_lookup[(period, weather, gas, hour)]
    return model[Symbol(target)][prefix..., time]
end

variable_values = Dict{JuMP.VariableRef, Float64}()
unmapped_components = Set{String}()
for row in CSV.File(solution_file)
    component, indices = parse_variable_name(String(row.variable))
    variable = try
        julia_variable(model, component, indices)
    catch error
        if error isa KeyError || error isa BoundsError
            nothing
        else
            rethrow()
        end
    end
    if !(variable isa JuMP.VariableRef)
        push!(unmapped_components, component)
    else
        variable_values[variable] = Float64(row.value)
    end
end

# Julia lifts three cumulative expressions into explicit auxiliary variables.
for ((from, to, sp), installed) in pairs(model[:hydrogenRepurposedGasPipelineCapInstalled].data)
    variable_values[installed] = sum(
        get(variable_values, model[:hydrogenRepurposedGasPipelineCapBuilt][from, to, candidate], 0.0)
        for candidate in strategic_periods
        if OpenEMPIRE.duration_aggr(candidate, sp, strategic_periods) <=
           params.Hydrogen.pipelineLifetime - duration_strat(sp);
        init = 0.0,
    )
end
for ((node, sp), installed) in pairs(model[:co2SequestrationCapInstalled].data)
    variable_values[installed] = sum(
        get(variable_values, model[:co2SequestrationCapBuilt][node, candidate], 0.0)
        for candidate in strategic_periods if candidate <= sp;
        init = 0.0,
    )
end

# InternalEMPIRE writes emissions directly in its cap rows. Julia lifts the same
# expression into nodeEmission variables, including reformer emissions.
strategic_index = Dict(period => index for (index, period) in enumerate(strategic_periods))
for ((node, sp, scenario_index), node_emission) in pairs(model[:nodeEmission].data)
    emissions = sum(
        multiple_strat(sp, time) *
        OpenEMPIRE.co2_content(params, generator) *
        (3.6 / params.genEfficiency[generator][sp]) *
        get(variable_values, model[:genOperational][node, generator, time], 0.0)
        for generator in OpenEMPIRE.generators(sets, node)
        for representative in repr_periods(sp)
        for (index, scenario) in enumerate(opscenarios(representative))
        if index == scenario_index
        for time in scenario;
        init = 0.0,
    )
    if node in OpenEMPIRE.hydrogen_sets(sets).ReformerLocation
        emissions += sum(
            multiple_strat(sp, time) *
            params.Hydrogen.reformerEmissionFactor[(plant, strategic_index[sp])] *
            get(variable_values, model[:reformerHydrogenTon][node, plant, time], 0.0)
            for plant in OpenEMPIRE.hydrogen_sets(sets).ReformerPlant
            for representative in repr_periods(sp)
            for (index, scenario) in enumerate(opscenarios(representative))
            if index == scenario_index
            for time in scenario;
            init = 0.0,
        )
    end
    variable_values[node_emission] = emissions
end

missing = [variable for variable in all_variables(model) if !haskey(variable_values, variable)]
println("mapped=$(length(variable_values)) model_variables=$(num_variables(model)) missing=$(length(missing))")
println("unmapped_internal_components=$(sort!(collect(unmapped_components)))")
isempty(missing) || println("first_missing=$(name.(missing[1:min(end, 20)]))")
for variable in missing
    variable_values[variable] = 0.0
end

function internal_hydrogen_electricity_demand(node, time)
    hydrogen = OpenEMPIRE.hydrogen_sets(sets)
    hparams = params.Hydrogen
    context = model.ext[:sector_period_context]
    period = context[time].strategic
    demand = 0.0
    if node in hydrogen.ProductionNode
        demand += get(variable_values, model[:electrolyzerElectricity][node, time], 0.0)
        for storage in hydrogen.Storage
            (node, storage) in hydrogen.StoragesOfNode || continue
            demand += get(
                variable_values,
                model[:hydrogenStorageCompressionPower][node, storage, time],
                0.0,
            )
        end
        for (from, to) in hydrogen.Corridor
            node in (from, to) || continue
            coefficient = 0.5 * (
                hparams.pipelineCompressorStaticMWhPerTon +
                OpenEMPIRE._hydrogen_pipeline_length(params, from, to) *
                hparams.pipelineCompressorPowerUsage
            )
            demand += coefficient * (
                get(variable_values, model[:hydrogenPipelineFlow][from, to, time], 0.0) +
                get(variable_values, model[:hydrogenPipelineFlow][to, from, time], 0.0)
            )
        end
        for (from, to) in unique(
            OpenEMPIRE.Arc[minmax(a, b) for (a, b) in hydrogen.CO2DirectionalLink],
        )
            node in (from, to) || continue
            demand += 0.5 * hparams.co2PipelineElectricityUsage * (
                get(variable_values, model[:co2PipelineFlow][from, to, time], 0.0) +
                get(variable_values, model[:co2PipelineFlow][to, from, time], 0.0)
            )
        end
        if node in hydrogen.ReformerLocation
            for plant in hydrogen.ReformerPlant
                demand += hparams.reformerElectricityUse[(plant, period)] *
                          get(variable_values, model[:reformerHydrogenTon][node, plant, time], 0.0)
            end
        end
    end
    if node in OpenEMPIRE.natural_gas_onshore_nodes(sets)
        demand += get(variable_values, model[:transportElectricityDemandMet][node, time], 0.0)
    end
    return demand
end

electricity_differences = NamedTuple[]
for node in OpenEMPIRE.nodes(sets), time in periods
    julia_demand = JuMP.value(
        variable -> variable_values[variable],
        OpenEMPIRE.hydrogen_electricity_demand(model, sets, params, node, time),
    )
    internal_demand = internal_hydrogen_electricity_demand(node, time)
    difference = julia_demand - internal_demand
    abs(difference) > 1.0e-8 && push!(
        electricity_differences,
        (; absolute = abs(difference), difference, node, time, julia_demand, internal_demand),
    )
end
sort!(electricity_differences; by = row -> row.absolute, rev = true)
println("hydrogen_electricity_differences=$(length(electricity_differences))")
for row in electricity_differences[1:min(end, 20)]
    println("hydrogen_electricity_difference=$row")
end

internal_load_file = joinpath(dirname(solution_file), "tabs", "data_electric_load.csv")
if isfile(internal_load_file)
    load_differences = NamedTuple[]
    for row in CSV.File(internal_load_file)
        node = String(row.Node)
        period = occursin("2030-2035", String(row.Period)) ? 2 : 1
        weather = parse(Int, replace(String(row.Scenario), "scenario" => ""))
        gas = Int(row.GasScenario)
        hour = Int(row.Hour)
        time = time_lookup[(period, weather, gas, hour)]
        internal_load = Float64(row[Symbol("Electric load [MW]")])
        julia_load = OpenEMPIRE.load(params, node, time)
        difference = julia_load - internal_load
        abs(difference) > 1.0e-8 && push!(
            load_differences,
            (; absolute = abs(difference), difference, node, time, julia_load, internal_load),
        )
    end
    sort!(load_differences; by = row -> row.absolute, rev = true)
    println("electric_load_differences=$(length(load_differences))")
    for row in load_differences[1:min(end, 20)]
        println("electric_load_difference=$row")
    end
end

function violation(value, set)
    if set isa MOI.LessThan
        return max(0.0, value - set.upper)
    elseif set isa MOI.GreaterThan
        return max(0.0, set.lower - value)
    elseif set isa MOI.EqualTo
        return abs(value - set.value)
    end
    error("Unsupported constraint set $(typeof(set))")
end

family_stats = Dict{String, NamedTuple}()
for (function_type, set_type) in list_of_constraint_types(model)
    for constraint in all_constraints(model, function_type, set_type)
        object = constraint_object(constraint)
        constraint_value = JuMP.value(variable -> variable_values[variable], object.func)
        residual = violation(constraint_value, object.set)
        family = first(split(name(constraint), '['; limit = 2))
        current = get(
            family_stats,
            family,
            (count = 0, above_1e6 = 0, above_1e4 = 0, above_1e2 = 0, maximum = 0.0, at = ""),
        )
        family_stats[family] = (
            count = current.count + 1,
            above_1e6 = current.above_1e6 + (residual > 1e-6),
            above_1e4 = current.above_1e4 + (residual > 1e-4),
            above_1e2 = current.above_1e2 + (residual > 1e-2),
            maximum = max(current.maximum, residual),
            at = residual > current.maximum ? name(constraint) : current.at,
        )
    end
end

imported_objective = JuMP.value(
    variable -> variable_values[variable],
    JuMP.objective_function(model),
)
println("imported_objective=$imported_objective")
for (family, stats) in sort!(collect(family_stats); by = first)
    println(
        "$family: rows=$(stats.count) >1e-6=$(stats.above_1e6) " *
        ">1e-4=$(stats.above_1e4) >1e-2=$(stats.above_1e2) " *
        "max=$(stats.maximum) at=$(stats.at)",
    )
end
