_hydrogen_node_generators(sets) = [
    (node, generator)
    for (node, generator) in node_generators(sets)
    if generator in hydrogen_generators(sets)
]

const HydrogenFlowDemand = Tuple{String, String, Float64}

struct HydrogenElectricityContext
    productionNodes::Set{String}
    reformerLocations::Set{String}
    onshoreNodes::Set{String}
    storagesByNode::Dict{String, Vector{String}}
    hydrogenFlowsByNode::Dict{String, Vector{HydrogenFlowDemand}}
    co2FlowsByNode::Dict{String, Vector{HydrogenFlowDemand}}
end

function _hydrogen_electricity_context!(emp::JuMP.Model, sets, par)
    cached = get(emp.ext, :hydrogen_electricity_context, nothing)
    cached isa HydrogenElectricityContext && return cached
    hydrogen = hydrogen_sets(sets)
    params = par.Hydrogen
    storages_by_node = Dict{String, Vector{String}}(
        node => String[] for node in nodes(sets)
    )
    for (node, storage) in hydrogen.StoragesOfNode
        push!(storages_by_node[node], storage)
    end
    hydrogen_flows_by_node = Dict{String, Vector{HydrogenFlowDemand}}(
        node => HydrogenFlowDemand[] for node in nodes(sets)
    )
    h2_links = Set(hydrogen.DirectionalLink)
    for (from, to) in hydrogen.Corridor
        coefficient = 0.5 * (
            params.pipelineCompressorStaticMWhPerTon +
            _hydrogen_pipeline_length(par, from, to) * params.pipelineCompressorPowerUsage
        )
        for (a, b) in ((from, to), (to, from))
            (a, b) in h2_links || continue
            flow = (a, b, coefficient)
            push!(hydrogen_flows_by_node[from], flow)
            push!(hydrogen_flows_by_node[to], flow)
        end
    end
    co2_flows_by_node = Dict{String, Vector{HydrogenFlowDemand}}(
        node => HydrogenFlowDemand[] for node in nodes(sets)
    )
    co2_links = Set(hydrogen.CO2DirectionalLink)
    for (from, to) in unique(Arc[minmax(a, b) for (a, b) in hydrogen.CO2DirectionalLink])
        for (a, b) in ((from, to), (to, from))
            (a, b) in co2_links || continue
            flow = (a, b, 0.5 * params.co2PipelineElectricityUsage)
            push!(co2_flows_by_node[from], flow)
            push!(co2_flows_by_node[to], flow)
        end
    end
    context = HydrogenElectricityContext(
        Set(hydrogen.ProductionNode),
        Set(hydrogen.ReformerLocation),
        Set(natural_gas_onshore_nodes(sets)),
        storages_by_node,
        hydrogen_flows_by_node,
        co2_flows_by_node,
    )
    emp.ext[:hydrogen_electricity_context] = context
    return context
end

"""
    create_hydrogen_variables!(model, sets, params, periods)

Declare the deterministic Hydrogen and CO₂ subsystem variables using sparse
indices only. No variables are added when the public Hydrogen gate is disabled.
"""
function create_hydrogen_variables!(emp::JuMP.Model, sets, periods)
    has_hydrogen(sets) ||
        throw(ArgumentError("hydrogen=true requires non-empty Hydrogen sets"))

    hydrogen = hydrogen_sets(sets)
    strategic_periods = strat_periods(periods)
    production_nodes = hydrogen.ProductionNode
    reformer_pairs = [(node, plant) for node in hydrogen.ReformerLocation
                      for plant in hydrogen.ReformerPlant]
    storage_pairs = hydrogen.StoragesOfNode
    terminal_pairs = hydrogen.TerminalsOfNode
    h2_corridors = hydrogen.Corridor
    gas_corridors = hydrogen.RepurposableGasCorridor
    co2_corridors = unique(Arc[minmax(from, to) for (from, to) in hydrogen.CO2DirectionalLink])

    @variable(emp, electrolyzerCapBuilt[production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, electrolyzerCapInstalled[production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, reformerCapBuilt[production_nodes, hydrogen.ReformerPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, reformerCapInstalled[production_nodes, hydrogen.ReformerPlant, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenPipelineCapBuilt[production_nodes, production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenPipelineCapInstalled[production_nodes, production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenRepurposedGasPipelineCapBuilt[production_nodes, production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenRepurposedGasPipelineCapInstalled[production_nodes, production_nodes, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageCapBuilt[production_nodes, hydrogen.Storage, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageCapInstalled[production_nodes, hydrogen.Storage, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenImportCapBuilt[hydrogen.TerminalNode, hydrogen.Terminal, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenImportCapInstalled[hydrogen.TerminalNode, hydrogen.Terminal, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2PipelineCapBuilt[nodes(sets), nodes(sets), strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2PipelineCapInstalled[nodes(sets), nodes(sets), strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2SequestrationCapBuilt[hydrogen.CO2SequestrationNode, strategic_periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2SequestrationCapInstalled[hydrogen.CO2SequestrationNode, strategic_periods] >= 0; container = IndexedVarArray)

    for node in production_nodes, strategic_period in strategic_periods
        unsafe_insertvar!(electrolyzerCapBuilt, node, strategic_period)
        unsafe_insertvar!(electrolyzerCapInstalled, node, strategic_period)
    end
    for (node, plant) in reformer_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(reformerCapBuilt, node, plant, strategic_period)
        unsafe_insertvar!(reformerCapInstalled, node, plant, strategic_period)
    end
    for (from, to) in h2_corridors, strategic_period in strategic_periods
        unsafe_insertvar!(hydrogenPipelineCapBuilt, from, to, strategic_period)
        unsafe_insertvar!(hydrogenPipelineCapInstalled, from, to, strategic_period)
    end
    for (from, to) in gas_corridors, strategic_period in strategic_periods
        unsafe_insertvar!(hydrogenRepurposedGasPipelineCapBuilt, from, to, strategic_period)
        unsafe_insertvar!(hydrogenRepurposedGasPipelineCapInstalled, from, to, strategic_period)
    end
    for (node, storage) in storage_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(hydrogenStorageCapBuilt, node, storage, strategic_period)
        unsafe_insertvar!(hydrogenStorageCapInstalled, node, storage, strategic_period)
    end
    for (node, terminal) in terminal_pairs, strategic_period in strategic_periods
        unsafe_insertvar!(hydrogenImportCapBuilt, node, terminal, strategic_period)
        unsafe_insertvar!(hydrogenImportCapInstalled, node, terminal, strategic_period)
    end
    for (from, to) in co2_corridors, strategic_period in strategic_periods
        unsafe_insertvar!(co2PipelineCapBuilt, from, to, strategic_period)
        unsafe_insertvar!(co2PipelineCapInstalled, from, to, strategic_period)
    end
    for node in hydrogen.CO2SequestrationNode, strategic_period in strategic_periods
        unsafe_insertvar!(co2SequestrationCapBuilt, node, strategic_period)
        unsafe_insertvar!(co2SequestrationCapInstalled, node, strategic_period)
    end

    @variable(emp, electrolyzerElectricity[production_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, electrolyzerHydrogen[production_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, reformerHydrogenTon[production_nodes, hydrogen.ReformerPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, reformerHydrogenMWh[production_nodes, hydrogen.ReformerPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, reformerNaturalGas[production_nodes, hydrogen.ReformerPlant, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenImportTon[hydrogen.TerminalNode, hydrogen.Terminal, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenImportMWh[hydrogen.TerminalNode, hydrogen.Terminal, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenPipelineFlow[production_nodes, production_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageLevel[production_nodes, hydrogen.Storage, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageCharge[production_nodes, hydrogen.Storage, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageDischarge[production_nodes, hydrogen.Storage, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenStorageCompressionPower[production_nodes, hydrogen.Storage, periods] >= 0; container = IndexedVarArray)
    @variable(emp, hydrogenForPower[production_nodes, hydrogen.Generator, periods] >= 0; container = IndexedVarArray)
    onshore_nodes = natural_gas_onshore_nodes(sets)
    @variable(emp, transportElectricityDemandMet[onshore_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, transportElectricityDemandShed[onshore_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, transportHydrogenDemandMet[onshore_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, transportHydrogenDemandShed[onshore_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2PipelineFlow[nodes(sets), nodes(sets), periods] >= 0; container = IndexedVarArray)
    @variable(emp, co2Sequestered[hydrogen.CO2SequestrationNode, periods] >= 0; container = IndexedVarArray)

    for node in production_nodes, operational_period in periods
        unsafe_insertvar!(electrolyzerElectricity, node, operational_period)
        unsafe_insertvar!(electrolyzerHydrogen, node, operational_period)
    end
    for node in onshore_nodes, operational_period in periods
        unsafe_insertvar!(transportElectricityDemandMet, node, operational_period)
        unsafe_insertvar!(transportElectricityDemandShed, node, operational_period)
        unsafe_insertvar!(transportHydrogenDemandMet, node, operational_period)
        unsafe_insertvar!(transportHydrogenDemandShed, node, operational_period)
    end
    for (node, plant) in reformer_pairs, operational_period in periods
        unsafe_insertvar!(reformerHydrogenTon, node, plant, operational_period)
        unsafe_insertvar!(reformerHydrogenMWh, node, plant, operational_period)
        unsafe_insertvar!(reformerNaturalGas, node, plant, operational_period)
    end
    for (node, terminal) in terminal_pairs, operational_period in periods
        unsafe_insertvar!(hydrogenImportTon, node, terminal, operational_period)
        unsafe_insertvar!(hydrogenImportMWh, node, terminal, operational_period)
    end
    for (from, to) in hydrogen.DirectionalLink, operational_period in periods
        unsafe_insertvar!(hydrogenPipelineFlow, from, to, operational_period)
    end
    for (node, storage) in storage_pairs, operational_period in periods
        unsafe_insertvar!(hydrogenStorageLevel, node, storage, operational_period)
        unsafe_insertvar!(hydrogenStorageCharge, node, storage, operational_period)
        unsafe_insertvar!(hydrogenStorageDischarge, node, storage, operational_period)
        unsafe_insertvar!(hydrogenStorageCompressionPower, node, storage, operational_period)
    end
    for (node, generator) in _hydrogen_node_generators(sets), operational_period in periods
        unsafe_insertvar!(hydrogenForPower, node, generator, operational_period)
    end
    for (from, to) in hydrogen.CO2DirectionalLink, operational_period in periods
        unsafe_insertvar!(co2PipelineFlow, from, to, operational_period)
    end
    for node in hydrogen.CO2SequestrationNode, operational_period in periods
        unsafe_insertvar!(co2Sequestered, node, operational_period)
    end
    return nothing
end

_hydrogen_period_index(context, operational_period) = context[operational_period].strategic

function _hydrogen_pipeline_length(par, from, to)
    value = get(par.transmissionLength, (from, to), nothing)
    value === nothing && (value = get(par.transmissionLength, (to, from), nothing))
    value === nothing && throw(ArgumentError(
        "Hydrogen/CO2 corridor ($from, $to) has no transmissionLength input",
    ))
    return value
end

function hydrogen_electricity_demand(emp, sets, par, node, operational_period)
    haskey(JuMP.object_dictionary(emp), :electrolyzerElectricity) ||
        return JuMP.AffExpr(0.0)
    hydrogen = hydrogen_sets(sets)
    params = par.Hydrogen
    context = emp.ext[:sector_period_context]
    period = _hydrogen_period_index(context, operational_period)
    electricity = emp.ext[:hydrogen_electricity_context]::HydrogenElectricityContext
    demand = JuMP.AffExpr(0.0)
    if node in electricity.productionNodes
        JuMP.add_to_expression!(demand, 1.0, emp[:electrolyzerElectricity][node, operational_period])
        for storage in electricity.storagesByNode[node]
            JuMP.add_to_expression!(
                demand,
                1.0,
                emp[:hydrogenStorageCompressionPower][node, storage, operational_period],
            )
        end
        node in electricity.onshoreNodes && JuMP.add_to_expression!(
            demand, 1.0, emp[:transportElectricityDemandMet][node, operational_period],
        )
    end
    if node in electricity.reformerLocations
        for plant in hydrogen.ReformerPlant
            JuMP.add_to_expression!(
                demand,
                params.reformerElectricityUse[(plant, period)],
                emp[:reformerHydrogenTon][node, plant, operational_period],
            )
        end
    end
    h2_flow = emp[:hydrogenPipelineFlow]
    for (from, to, coefficient) in electricity.hydrogenFlowsByNode[node]
        JuMP.add_to_expression!(
            demand, coefficient, h2_flow[from, to, operational_period],
        )
    end
    co2_flow = emp[:co2PipelineFlow]
    for (from, to, coefficient) in electricity.co2FlowsByNode[node]
        JuMP.add_to_expression!(
            demand, coefficient, co2_flow[from, to, operational_period],
        )
    end
    return demand
end

function _hydrogen_active_investments(variable, key, strategic_period, strategic_periods, lifetime)
    return sum(
        variable[key..., candidate]
        for candidate in strategic_periods
        if duration_aggr(candidate, strategic_period, strategic_periods) <=
           lifetime - duration_strat(strategic_period);
        init = 0.0,
    )
end

"""Add deterministic InternalEMPIRE-compatible Hydrogen and CO₂ constraints."""
function create_hydrogen_constraints!(
    emp::JuMP.Model,
    sets,
    par,
    periods;
    include_investment_constraints::Bool = true,
)
    hydrogen = hydrogen_sets(sets)
    params = par.Hydrogen
    strategic_periods = collect(strat_periods(periods))
    context = _sector_period_context(emp, periods, par.NaturalGas.gasScenarioCount)
    period_index = Dict(period => index for (index, period) in enumerate(strategic_periods))
    production_nodes = hydrogen.ProductionNode
    reformer_pairs = [(node, plant) for node in hydrogen.ReformerLocation
                      for plant in hydrogen.ReformerPlant]
    storage_pairs = hydrogen.StoragesOfNode
    terminal_pairs = hydrogen.TerminalsOfNode
    h2_link_set = Set(hydrogen.DirectionalLink)
    co2_link_set = Set(hydrogen.CO2DirectionalLink)
    co2_corridors = unique(Arc[minmax(from, to) for (from, to) in hydrogen.CO2DirectionalLink])

    @constraint(
        emp,
        hydrogen_for_power[
            (node, generator) in _hydrogen_node_generators(sets),
            operational_period in periods,
        ],
        emp[:genOperational][node, generator, operational_period] ==
            par.genEfficiency[generator][operational_period] *
            params.hydrogenMWhPerTon *
            emp[:hydrogenForPower][node, generator, operational_period],
    )
    @constraint(
        emp,
        hydrogen_electrolyzer_conversion[node in production_nodes, operational_period in periods],
        emp[:electrolyzerHydrogen][node, operational_period] ==
            emp[:electrolyzerElectricity][node, operational_period] /
            params.electrolyzerPowerUse[context[operational_period].strategic],
    )
    @constraint(
        emp,
        hydrogen_electrolyzer_capacity[
            node in production_nodes,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:electrolyzerElectricity][node, operational_period] <=
            emp[:electrolyzerCapInstalled][node, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_reformer_ton_mwh[
            (node, plant) in reformer_pairs,
            operational_period in periods,
        ],
        emp[:reformerHydrogenTon][node, plant, operational_period] ==
            emp[:reformerHydrogenMWh][node, plant, operational_period] /
            params.hydrogenMWhPerTon,
    )
    @constraint(
        emp,
        hydrogen_reformer_natural_gas[
            (node, plant) in reformer_pairs,
            operational_period in periods,
        ],
        par.NaturalGas.mwhPerTon *
        emp[:reformerNaturalGas][node, plant, operational_period] ==
            emp[:reformerHydrogenMWh][node, plant, operational_period] /
            params.reformerEfficiency[(plant, context[operational_period].strategic)],
    )
    @constraint(
        emp,
        hydrogen_reformer_capacity[
            (node, plant) in reformer_pairs,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:reformerHydrogenMWh][node, plant, operational_period] <=
            emp[:reformerCapInstalled][node, plant, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_reformer_ramp[
            (node, plant) in reformer_pairs,
            strategic_period in strategic_periods,
            (previous, operational_period) in withprev(strategic_period);
            !isnothing(previous)
        ],
        emp[:reformerHydrogenMWh][node, plant, operational_period] -
        emp[:reformerHydrogenMWh][node, plant, previous] <=
            params.reformerRampFractionPerHour *
            emp[:reformerCapInstalled][node, plant, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_pipeline_capacity[
            (from, to) in hydrogen.DirectionalLink,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:hydrogenPipelineFlow][from, to, operational_period] <=
            emp[:hydrogenPipelineCapInstalled][minmax(from, to)..., strategic_period],
    )
    @constraint(
        emp,
        hydrogen_storage_compression[
            (node, storage) in storage_pairs,
            operational_period in periods,
        ],
        emp[:hydrogenStorageCompressionPower][node, storage, operational_period] ==
            params.storageCompressionMWhPerTon *
            emp[:hydrogenStorageCharge][node, storage, operational_period],
    )
    @constraint(
        emp,
        hydrogen_storage_balance[
            (node, storage) in storage_pairs,
            strategic_period in strategic_periods,
            (previous, operational_period) in withprev(strategic_period),
        ],
        (isnothing(previous) ?
            params.storageInitialFraction *
            emp[:hydrogenStorageCapInstalled][node, storage, strategic_period] :
            emp[:hydrogenStorageLevel][node, storage, previous]) +
        emp[:hydrogenStorageCharge][node, storage, operational_period] -
        emp[:hydrogenStorageDischarge][node, storage, operational_period] ==
            emp[:hydrogenStorageLevel][node, storage, operational_period],
    )
    @constraint(
        emp,
        hydrogen_storage_cyclic[
            (node, storage) in storage_pairs,
            strategic_period in strategic_periods,
            scenario in opscenarios(strategic_period),
        ],
        emp[:hydrogenStorageLevel][node, storage, last(scenario)] ==
            params.storageInitialFraction *
            emp[:hydrogenStorageCapInstalled][node, storage, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_storage_capacity[
            (node, storage) in storage_pairs,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:hydrogenStorageLevel][node, storage, operational_period] <=
            emp[:hydrogenStorageCapInstalled][node, storage, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_import_ton_mwh[
            (node, terminal) in terminal_pairs,
            operational_period in periods,
        ],
        emp[:hydrogenImportMWh][node, terminal, operational_period] ==
            params.hydrogenMWhPerTon *
            emp[:hydrogenImportTon][node, terminal, operational_period],
    )
    @constraint(
        emp,
        hydrogen_import_capacity[
            (node, terminal) in terminal_pairs,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:hydrogenImportTon][node, terminal, operational_period] <=
            emp[:hydrogenImportCapInstalled][node, terminal, strategic_period],
    )
    @constraint(
        emp,
        meet_transport_electricity_demand[node in natural_gas_onshore_nodes(sets), operational_period in periods],
        emp[:transportElectricityDemandMet][node, operational_period] +
        emp[:transportElectricityDemandShed][node, operational_period] >=
            params.electricityTransportDemand[(node, context[operational_period].strategic)] /
            params.hoursPerYear,
    )
    @constraint(
        emp,
        meet_transport_hydrogen_demand[node in natural_gas_onshore_nodes(sets), operational_period in periods],
        emp[:transportHydrogenDemandMet][node, operational_period] +
        emp[:transportHydrogenDemandShed][node, operational_period] >=
            params.hydrogenTransportDemand[(node, context[operational_period].strategic)] /
            (params.hoursPerYear * params.hydrogenMWhPerTon),
    )
    @constraint(
        emp,
        hydrogen_flow_balance[node in production_nodes, operational_period in periods],
        emp[:electrolyzerHydrogen][node, operational_period] +
        sum(
            emp[:reformerHydrogenTon][node, plant, operational_period]
            for plant in hydrogen.ReformerPlant if node in hydrogen.ReformerLocation;
            init = 0.0,
        ) +
        sum(
            emp[:hydrogenImportTon][node, terminal, operational_period]
            for terminal in get(hydrogen.TerminalsByNode, node, String[]);
            init = 0.0,
        ) +
        sum(
            (1 - params.pipelineLeakageFractionPerKM * _hydrogen_pipeline_length(par, source, node)) *
            emp[:hydrogenPipelineFlow][source, node, operational_period]
            for source in get(hydrogen.Incoming, node, String[]);
            init = 0.0,
        ) +
        sum(
            emp[:hydrogenStorageDischarge][node, storage, operational_period]
            for storage in hydrogen.Storage if (node, storage) in storage_pairs;
            init = 0.0,
        ) ==
        sum(
            emp[:hydrogenForPower][node, generator, operational_period]
            for generator in generators(sets, node) if generator in hydrogen.Generator;
            init = 0.0,
        ) +
        sum(
            emp[:hydrogenPipelineFlow][node, destination, operational_period]
            for destination in get(hydrogen.Outgoing, node, String[]);
            init = 0.0,
        ) +
        sum(
            emp[:hydrogenStorageCharge][node, storage, operational_period]
            for storage in hydrogen.Storage if (node, storage) in storage_pairs;
            init = 0.0,
        ) +
        (node in natural_gas_onshore_nodes(sets) ?
         emp[:transportHydrogenDemandMet][node, operational_period] : 0.0) +
        industry_hydrogen_demand(emp, sets, par, node, operational_period),
    )

    @constraint(
        emp,
        co2_pipeline_capacity[
            (from, to) in hydrogen.CO2DirectionalLink,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:co2PipelineFlow][from, to, operational_period] <=
            emp[:co2PipelineCapInstalled][minmax(from, to)..., strategic_period],
    )
    @constraint(
        emp,
        co2_sequestration_hourly_capacity[
            node in hydrogen.CO2SequestrationNode,
            strategic_period in strategic_periods,
            operational_period in strategic_period,
        ],
        emp[:co2Sequestered][node, operational_period] <=
            emp[:co2SequestrationCapInstalled][node, strategic_period],
    )
    @constraint(
        emp,
        co2_flow_balance[node in natural_gas_onshore_nodes(sets), operational_period in periods],
        sum(
            get(params.generatorCO2Captured, generator, 0.0) * 3.6 /
            par.genEfficiency[generator][operational_period] *
            emp[:genOperational][node, generator, operational_period]
            for generator in generators(sets, node);
            init = 0.0,
        ) +
        sum(
            params.reformerCO2CaptureFactor[(plant, context[operational_period].strategic)] *
            emp[:reformerHydrogenTon][node, plant, operational_period]
            for plant in hydrogen.ReformerPlant if node in hydrogen.ReformerLocation;
            init = 0.0,
        ) +
        industry_captured_co2(emp, sets, par, node, operational_period) +
        sum(
            emp[:co2PipelineFlow][source, node, operational_period]
            for (source, destination) in hydrogen.CO2DirectionalLink if destination == node;
            init = 0.0,
        ) ==
        sum(
            emp[:co2PipelineFlow][node, destination, operational_period]
            for (source, destination) in hydrogen.CO2DirectionalLink if source == node;
            init = 0.0,
        ) +
        (node in hydrogen.CO2SequestrationNode ?
            emp[:co2Sequestered][node, operational_period] : 0.0),
    )

    total_constraints = JuMP.ConstraintRef[]
    for node in hydrogen.CO2SequestrationNode
        for weather_scenario in 1:par.NaturalGas.weatherScenarioCount
            total = JuMP.AffExpr(0.0)
            for strategic_period in strategic_periods
                for representative_period in repr_periods(strategic_period)
                    scenario = _operational_scenario_at(representative_period, weather_scenario)
                    for operational_period in scenario
                        JuMP.add_to_expression!(
                            total,
                            1.0e-4 * duration_strat(strategic_period) *
                            multiple_strat(strategic_period, operational_period),
                            emp[:co2Sequestered][node, operational_period],
                        )
                    end
                end
            end
            push!(total_constraints, @constraint(
                emp,
                total <= 1.0e-4 * params.co2MaxSequestrationCapacity[node],
                base_name = "co2_total_sequestration[$node,$weather_scenario]",
            ))
        end
    end
    emp[:co2_total_sequestration] = total_constraints

    include_investment_constraints || return nothing
    electrolyzer_built = emp[:electrolyzerCapBuilt]
    reformer_built = emp[:reformerCapBuilt]
    h2_pipeline_built = emp[:hydrogenPipelineCapBuilt]
    repurposed_built = emp[:hydrogenRepurposedGasPipelineCapBuilt]
    storage_built = emp[:hydrogenStorageCapBuilt]
    import_built = emp[:hydrogenImportCapBuilt]
    co2_pipeline_built = emp[:co2PipelineCapBuilt]
    @constraint(
        emp,
        hydrogen_electrolyzer_installed[node in production_nodes, strategic_period in strategic_periods],
        _hydrogen_active_investments(
            electrolyzer_built, (node,), strategic_period, strategic_periods,
            params.electrolyzerLifetime,
        ) == emp[:electrolyzerCapInstalled][node, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_reformer_installed[
            (node, plant) in reformer_pairs,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            reformer_built, (node, plant), strategic_period, strategic_periods,
            params.reformerLifetime[plant],
        ) == emp[:reformerCapInstalled][node, plant, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_repurposed_installed[
            (from, to) in hydrogen.RepurposableGasCorridor,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            repurposed_built, (from, to), strategic_period, strategic_periods,
            params.pipelineLifetime,
        ) == emp[:hydrogenRepurposedGasPipelineCapInstalled][from, to, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_pipeline_installed[
            (from, to) in hydrogen.Corridor,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            h2_pipeline_built, (from, to), strategic_period, strategic_periods,
            params.pipelineLifetime,
        ) + params.repurposeEnergyFlowFactor *
        par.NaturalGas.mwhPerTon / params.hydrogenMWhPerTon * sum(
            emp[:hydrogenRepurposedGasPipelineCapInstalled][a, b, strategic_period]
            for (a, b) in ((from, to), (to, from))
            if (a, b) in hydrogen.RepurposableGasCorridor;
            init = 0.0,
        ) == emp[:hydrogenPipelineCapInstalled][from, to, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_repurpose_capacity[
            (from, to) in hydrogen.RepurposableGasCorridor,
            strategic_period in strategic_periods,
        ],
        repurposed_built[from, to, strategic_period] <=
            natural_gas_pipeline_capacity(par, from, to),
    )
    @constraint(
        emp,
        hydrogen_storage_installed[
            (node, storage) in storage_pairs,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            storage_built, (node, storage), strategic_period, strategic_periods,
            params.storageLifetime[storage],
        ) == emp[:hydrogenStorageCapInstalled][node, storage, strategic_period],
    )
    @constraint(
        emp,
        hydrogen_storage_max[
            (node, storage) in storage_pairs,
            strategic_period in strategic_periods,
        ],
        1.0e-3 * emp[:hydrogenStorageCapInstalled][node, storage, strategic_period] <=
            1.0e-3 * params.storageMaxCapacity[(node, storage)],
    )
    @constraint(
        emp,
        hydrogen_import_installed[
            (node, terminal) in terminal_pairs,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            import_built, (node, terminal), strategic_period, strategic_periods,
            params.terminalLifetime[terminal],
        ) == emp[:hydrogenImportCapInstalled][node, terminal, strategic_period],
    )
    @constraint(
        emp,
        co2_pipeline_installed[
            (from, to) in co2_corridors,
            strategic_period in strategic_periods,
        ],
        _hydrogen_active_investments(
            co2_pipeline_built, (from, to), strategic_period, strategic_periods,
            params.co2PipelineLifetime,
        ) == emp[:co2PipelineCapInstalled][from, to, strategic_period],
    )
    @constraint(
        emp,
        co2_sequestration_installed[
            node in hydrogen.CO2SequestrationNode,
            strategic_period in strategic_periods,
        ],
        sum(
            emp[:co2SequestrationCapBuilt][node, candidate]
            for candidate in strategic_periods if candidate <= strategic_period;
            init = 0.0,
        ) == emp[:co2SequestrationCapInstalled][node, strategic_period],
    )
    return @constraint(
        emp,
        co2_sequestration_max_installed[
            node in hydrogen.CO2SequestrationNode,
            strategic_period in strategic_periods,
        ],
        emp[:co2SequestrationCapInstalled][node, strategic_period] <=
            params.co2StorageMaxCapacity[(node, period_index[strategic_period])],
    )
end

function _internalempire_investment_cost(
    capital_cost,
    fixed_om,
    lifetime,
    strategic_period,
    strategic_periods,
    wacc,
    discount_rate,
)
    annualized =
        wacc / (1 - (1 + wacc)^(1 - lifetime)) * capital_cost + fixed_om
    remaining_years = sum(
        duration_strat(period) for period in strategic_periods
        if period >= strategic_period;
        init = 0.0,
    )
    active_years = min(remaining_years, lifetime)
    return annualized *
           (1 - (1 + discount_rate)^(-active_years)) /
           (1 - 1 / (1 + discount_rate))
end

function hydrogen_objective_expressions(emp, sets, par, periods, discounter)
    hydrogen = hydrogen_sets(sets)
    params = par.Hydrogen
    strategic_periods = collect(strat_periods(periods))
    context = _sector_period_context(emp, periods, par.NaturalGas.gasScenarioCount)
    period_index = Dict(period => index for (index, period) in enumerate(strategic_periods))
    wacc_value = wacc(par)
    discount = discount_rate(par)
    investment = JuMP.AffExpr(0.0)
    for strategic_period in strategic_periods
        index = period_index[strategic_period]
        weight = objective_weight(strategic_period, discounter)
        electrolyzer_cost = _internalempire_investment_cost(
            params.electrolyzerCapitalCost[index],
            params.electrolyzerFixedOMCost[index],
            params.electrolyzerLifetime,
            strategic_period,
            strategic_periods,
            wacc_value,
            discount,
        )
        for node in hydrogen.ProductionNode
            JuMP.add_to_expression!(
                investment, weight * electrolyzer_cost,
                emp[:electrolyzerCapBuilt][node, strategic_period],
            )
        end
        for node in hydrogen.ReformerLocation, plant in hydrogen.ReformerPlant
            cost = _internalempire_investment_cost(
                params.reformerCapitalCost[(plant, index)],
                params.reformerFixedOMCost[(plant, index)],
                params.reformerLifetime[plant],
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:reformerCapBuilt][node, plant, strategic_period],
            )
        end
        for (from, to) in hydrogen.Corridor
            length_km = _hydrogen_pipeline_length(par, from, to)
            cost = _internalempire_investment_cost(
                length_km * params.pipelineCapitalCost[index],
                length_km * params.pipelineOMCostPerKM[index],
                params.pipelineLifetime,
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:hydrogenPipelineCapBuilt][from, to, strategic_period],
            )
        end
        for (from, to) in hydrogen.RepurposableGasCorridor
            length_km = _hydrogen_pipeline_length(par, from, to)
            cost = params.repurposeCostFactor * _internalempire_investment_cost(
                length_km * params.pipelineCapitalCost[index],
                length_km * params.pipelineOMCostPerKM[index],
                params.pipelineLifetime,
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:hydrogenRepurposedGasPipelineCapBuilt][from, to, strategic_period],
            )
        end
        for (node, storage) in hydrogen.StoragesOfNode
            cost = _internalempire_investment_cost(
                params.storageCapitalCost[(storage, index)],
                params.storageFixedOMCost[(storage, index)],
                params.storageLifetime[storage],
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:hydrogenStorageCapBuilt][node, storage, strategic_period],
            )
        end
        for (node, terminal) in hydrogen.TerminalsOfNode
            cost = _internalempire_investment_cost(
                params.terminalCapitalCost[(node, terminal, index)],
                params.terminalFixedOMCost[(node, terminal, index)],
                params.terminalLifetime[terminal],
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:hydrogenImportCapBuilt][node, terminal, strategic_period],
            )
        end
        for (from, to) in unique(Arc[minmax(a, b) for (a, b) in hydrogen.CO2DirectionalLink])
            length_km = _hydrogen_pipeline_length(par, from, to)
            cost = _internalempire_investment_cost(
                length_km * params.co2PipelineCapitalCost,
                length_km * params.co2PipelineFixedOMCost,
                params.co2PipelineLifetime,
                strategic_period,
                strategic_periods,
                wacc_value,
                discount,
            )
            JuMP.add_to_expression!(
                investment, weight * cost,
                emp[:co2PipelineCapBuilt][from, to, strategic_period],
            )
        end
        remaining_years = sum(
            duration_strat(period) for period in strategic_periods
            if period >= strategic_period;
            init = 0.0,
        )
        site_multiplier =
            (1 - (1 + discount)^(-remaining_years)) /
            (1 - 1 / (1 + discount))
        for node in hydrogen.CO2SequestrationNode
            annual = wacc_value * params.co2StorageSiteCapitalCost[node] +
                     params.co2StorageSiteFixedOMCost[node]
            JuMP.add_to_expression!(
                investment, weight * annual * site_multiplier,
                emp[:co2SequestrationCapBuilt][node, strategic_period],
            )
        end
    end

    terminal_import = JuMP.AffExpr(0.0)
    reformer_operation = JuMP.AffExpr(0.0)
    transport_shedding = JuMP.AffExpr(0.0)
    for operational_period in periods
        index = context[operational_period].strategic
        weight = objective_weight(operational_period, discounter; type = "avg_year")
        for (node, terminal) in hydrogen.TerminalsOfNode
            JuMP.add_to_expression!(
                terminal_import,
                weight * params.terminalPrice[(node, terminal, index)],
                emp[:hydrogenImportTon][node, terminal, operational_period],
            )
        end
        for node in hydrogen.ReformerLocation, plant in hydrogen.ReformerPlant
            marginal = params.reformerVariableOMCost[(plant, index)] +
                       co2_price(par, operational_period) *
                       params.reformerEmissionFactor[(plant, index)]
            JuMP.add_to_expression!(
                reformer_operation, weight * marginal,
                emp[:reformerHydrogenTon][node, plant, operational_period],
            )
        end
        for node in natural_gas_onshore_nodes(sets)
            JuMP.add_to_expression!(
                transport_shedding,
                weight * par.NaturalGas.transportCurtailCost,
                emp[:transportElectricityDemandShed][node, operational_period],
            )
            JuMP.add_to_expression!(
                transport_shedding,
                weight * par.NaturalGas.transportCurtailCost,
                emp[:transportHydrogenDemandShed][node, operational_period],
            )
        end
    end
    return (; investment, terminal_import, reformer_operation, transport_shedding)
end
