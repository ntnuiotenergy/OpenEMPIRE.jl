#!/usr/bin/env julia

using CSV
using JuMP
using OpenEMPIRE
using TimeStruct

length(ARGS) == 3 || error(
    "usage: check_internalempire_solution_feasibility.jl " *
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

const STRATEGIC_COMPONENTS = Set([
    "genInvCap",
    "genInstalledCap",
    "transmissionInvCap",
    "transmissionInstalledCap",
    "storPWInvCap",
    "storPWInstalledCap",
    "storENInvCap",
    "storENInstalledCap",
    "offshoreConvInvCap",
    "offshoreConvInstalledCap",
])
const OPERATIONAL_COMPONENTS = Dict(
    "genOperational" => "genOperational",
    "transmissionOperational" => "transmissionOperational",
    "storCharge" => "storCharge",
    "storDischarge" => "storDischarge",
    "storOperational" => "storOperational",
    "loadShed" => "loadShed",
    "ng_terminalImport" => "ngTerminalImport",
    "ng_transmission" => "ngTransmission",
    "ng_forPower" => "ngForPower",
    "ng_storageOperational" => "ngStorageOperational",
    "ng_chargeStorage" => "ngStorageCharge",
    "ng_dischargeStorage" => "ngStorageDischarge",
)

function parse_variable_name(name)
    matched = match(r"^([^\[]+)\[(.*)\]$", name)
    matched === nothing && return name, String[]
    indices = [strip(index, ['\'', '"']) for index in split(matched.captures[2], ',')]
    return matched.captures[1], indices
end

function julia_variable(model, component, indices)
    if component in STRATEGIC_COMPONENTS
        parsed = Any[indices[1:end-1]...]
        if startswith(component, "transmission") && parsed[2] < parsed[1]
            parsed[1], parsed[2] = parsed[2], parsed[1]
        end
        push!(parsed, strategic_periods[parse(Int, indices[end])])
        return model[Symbol(component)][parsed...]
    end

    target = get(OPERATIONAL_COMPONENTS, component, nothing)
    target === nothing && return nothing
    prefix = indices[1:end-4]
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

# InternalEMPIRE writes emissions directly in its four cap rows. Julia lifts the
# same expression into nodeEmission variables, so reconstruct those auxiliary
# values from the imported generation before checking the lifted rows.
for ((n, sp, scenario_index), node_emission) in model[:nodeEmission].data
    emissions = sum(
        multiple_strat(sp, time) *
        OpenEMPIRE.co2_content(params, generator) *
        (3.6 / params.genEfficiency[generator][sp]) *
        get(variable_values, model[:genOperational][n, generator, time], 0.0)
        for generator in OpenEMPIRE.generators(sets, n)
        for representative in repr_periods(sp)
        for (index, scenario) in enumerate(opscenarios(representative))
        if index == scenario_index
        for time in scenario;
        init = 0.0
    )
    variable_values[node_emission] = emissions
end

missing = [variable for variable in all_variables(model) if !haskey(variable_values, variable)]
println("mapped=$(length(variable_values)) model_variables=$(num_variables(model)) missing=$(length(missing))")
println("unmapped_internal_components=$(sort!(collect(unmapped_components)))")
isempty(missing) || println("first_missing=$(name.(missing[1:min(end, 20)]))")
for variable in missing
    variable_values[variable] = 0.0
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

for (family, stats) in sort!(collect(family_stats); by = first)
    println(
        "$family: rows=$(stats.count) >1e-6=$(stats.above_1e6) " *
        ">1e-4=$(stats.above_1e4) >1e-2=$(stats.above_1e2) " *
        "max=$(stats.maximum) at=$(stats.at)",
    )
end
