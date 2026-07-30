const FINITE_RESERVE_TERMINALS = Set(("domesticproduction", "pipelineimport"))
const NaturalGasPeriodContext = NamedTuple{
    (:strategic, :weather, :gas),
    Tuple{Int, Int, Int},
}

_natural_gas_onshore_nodes(sets) =
    [node for node in natural_gas_nodes(sets) if node in natural_gas_onshore_nodes(sets)]

_natural_gas_node_generators(sets) = [
    (node, generator)
    for (node, generator) in node_generators(sets)
    if generator in natural_gas_generators(sets)
]

function _natural_gas_period_maps(periods, gas_scenario_count::Int)
    period_type = eltype(periods)
    context = Dict{period_type, NaturalGasPeriodContext}()
    for (period_index, strategic_period) in enumerate(strat_periods(periods))
        for representative_period in repr_periods(strategic_period)
            for (combined_scenario, scenario) in
                enumerate(opscenarios(representative_period))
                weather = weather_scenario_index(combined_scenario, gas_scenario_count)
                gas = gas_scenario_index(combined_scenario, gas_scenario_count)
                for operational_period in scenario
                    context[operational_period] = (
                        strategic = period_index,
                        weather = weather,
                        gas = gas,
                    )
                end
            end
        end
    end
    return context
end

function _operational_scenario_at(representative_period, scenario_index::Int)
    for (index, scenario) in enumerate(opscenarios(representative_period))
        index == scenario_index && return scenario
    end
    throw(BoundsError(opscenarios(representative_period), scenario_index))
end

"""
    create_natural_gas_variables!(model, sets, periods)

Declare and sparsely index the deterministic natural-gas operational variables.
"""
function create_natural_gas_variables!(emp::JuMP.Model, sets, periods)
    has_natural_gas(sets) ||
        throw(ArgumentError("natural_gas=true requires non-empty natural-gas sets"))

    gas_nodes = natural_gas_nodes(sets)
    gas_links = natural_gas_links(sets)
    terminal_nodes = natural_gas_terminal_nodes(sets)
    gas_generators = _natural_gas_node_generators(sets)
    onshore_nodes = _natural_gas_onshore_nodes(sets)

    @variable(
        emp,
        ngTerminalImport[gas_nodes, natural_gas_terminals(sets), periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(
        emp,
        ngTransmission[gas_nodes, gas_nodes, periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(
        emp,
        ngForPower[natural_gas_nodes(sets), natural_gas_generators(sets), periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(
        emp,
        ngStorageOperational[gas_nodes, periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(emp, ngStorageCharge[gas_nodes, periods] >= 0; container = IndexedVarArray)
    @variable(
        emp,
        ngStorageDischarge[gas_nodes, periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(
        emp,
        transportNaturalGasDemandMet[gas_nodes, periods] >= 0;
        container = IndexedVarArray,
    )
    @variable(
        emp,
        transportNaturalGasDemandShed[gas_nodes, periods] >= 0;
        container = IndexedVarArray,
    )

    for (node, terminal) in terminal_nodes, operational_period in periods
        unsafe_insertvar!(ngTerminalImport, node, terminal, operational_period)
    end
    for (from, to) in gas_links, operational_period in periods
        unsafe_insertvar!(ngTransmission, from, to, operational_period)
    end
    for (node, generator) in gas_generators, operational_period in periods
        unsafe_insertvar!(ngForPower, node, generator, operational_period)
    end
    for node in gas_nodes, operational_period in periods
        unsafe_insertvar!(ngStorageOperational, node, operational_period)
        unsafe_insertvar!(ngStorageCharge, node, operational_period)
        unsafe_insertvar!(ngStorageDischarge, node, operational_period)
    end
    for node in onshore_nodes, operational_period in periods
        unsafe_insertvar!(transportNaturalGasDemandMet, node, operational_period)
        unsafe_insertvar!(transportNaturalGasDemandShed, node, operational_period)
    end
    return nothing
end

function natural_gas_pipeline_electricity_demand(
    emp::JuMP.Model,
    sets,
    par,
    node,
    operational_period,
)
    haskey(JuMP.object_dictionary(emp), :ngTransmission) ||
        return JuMP.AffExpr(0.0)
    transmission = emp[:ngTransmission]
    power_per_ton = par.NaturalGas.pipelinePowerDemandPerTon
    return sum(
        power_per_ton * transmission[node, destination, operational_period]
        for destination in natural_gas_outgoing(sets, node);
        init = JuMP.AffExpr(0.0),
    )
end

function _create_natural_gas_reserve_constraints!(
    emp::JuMP.Model,
    sets,
    par,
    periods,
)
    terminal_import = emp[:ngTerminalImport]
    gas = par.NaturalGas
    constraints = JuMP.ConstraintRef[]
    for (node, terminal) in natural_gas_terminal_nodes(sets)
        lowercase(terminal) in FINITE_RESERVE_TERMINALS || continue
        for weather_scenario in 1:gas.weatherScenarioCount
            for gas_scenario in 1:gas.gasScenarioCount
                total_import = JuMP.AffExpr(0.0)
                for strategic_period in strat_periods(periods)
                    for representative_period in repr_periods(strategic_period)
                        combined_scenario =
                            (weather_scenario - 1) * gas.gasScenarioCount +
                            gas_scenario
                        scenario = _operational_scenario_at(
                            representative_period,
                            combined_scenario,
                        )
                        for operational_period in scenario
                            total_import +=
                                duration_strat(strategic_period) *
                                multiple_strat(strategic_period, operational_period) *
                                duration(operational_period) *
                                terminal_import[
                                    node,
                                    terminal,
                                    operational_period,
                                ]
                        end
                    end
                end
                push!(
                    constraints,
                    @constraint(
                        emp,
                        total_import <= natural_gas_reserves(par, node),
                    ),
                )
            end
        end
    end
    emp[:natural_gas_max_reserves] = constraints
    return constraints
end

"""
    create_natural_gas_constraints!(model, sets, params, periods)

Add InternalEMPIRE-compatible gas conversion, terminal, reserve, storage,
pipeline, transport-demand, and nodal-balance constraints.
"""
function create_natural_gas_constraints!(emp::JuMP.Model, sets, par, periods)
    gas = par.NaturalGas
    period_context = _natural_gas_period_maps(periods, gas.gasScenarioCount)
    gas_nodes = natural_gas_nodes(sets)
    gas_generators = _natural_gas_node_generators(sets)
    onshore_nodes = _natural_gas_onshore_nodes(sets)

    terminal_import = emp[:ngTerminalImport]
    transmission = emp[:ngTransmission]
    for_power = emp[:ngForPower]
    storage = emp[:ngStorageOperational]
    charge = emp[:ngStorageCharge]
    discharge = emp[:ngStorageDischarge]
    transport_met = emp[:transportNaturalGasDemandMet]
    transport_shed = emp[:transportNaturalGasDemandShed]
    generation = emp[:genOperational]

    @constraint(
        emp,
        natural_gas_for_power[
            (node, generator) in gas_generators,
            operational_period in periods,
        ],
        gas.mwhPerTon * for_power[node, generator, operational_period] ==
            generation[node, generator, operational_period] /
            par.genEfficiency[generator][operational_period],
    )
    @constraint(
        emp,
        natural_gas_terminal_capacity_limit[
            (node, terminal) in natural_gas_terminal_nodes(sets),
            operational_period in periods,
        ],
        terminal_import[node, terminal, operational_period] <=
            natural_gas_terminal_capacity(
                par,
                node,
                terminal,
                period_context[operational_period].strategic,
            ),
    )
    _create_natural_gas_reserve_constraints!(emp, sets, par, periods)

    @constraint(
        emp,
        natural_gas_storage_balance[
            node in gas_nodes,
            strategic_period in strat_periods(periods),
            (previous, operational_period) in withprev(strategic_period),
        ],
        (
            isnothing(previous) ?
            gas.storageInitialFraction * natural_gas_storage_capacity(par, node) :
            storage[node, previous]
        ) +
        gas.storageChargeEfficiency * charge[node, operational_period] -
        discharge[node, operational_period] ==
        storage[node, operational_period],
    )
    @constraint(
        emp,
        natural_gas_storage_cyclic[
            node in gas_nodes,
            strategic_period in strat_periods(periods),
            scenario in opscenarios(strategic_period),
        ],
        storage[node, last(scenario)] ==
            gas.storageInitialFraction * natural_gas_storage_capacity(par, node),
    )
    @constraint(
        emp,
        natural_gas_storage_max_capacity[
            node in gas_nodes,
            operational_period in periods,
        ],
        storage[node, operational_period] <=
            natural_gas_storage_capacity(par, node),
    )
    @constraint(
        emp,
        natural_gas_pipeline_capacity_limit[
            (from, to) in natural_gas_links(sets),
            operational_period in periods,
        ],
        transmission[from, to, operational_period] <=
            natural_gas_pipeline_capacity(par, from, to),
    )
    @constraint(
        emp,
        meet_transport_natural_gas_demand[
            node in onshore_nodes,
            operational_period in periods,
        ],
        transport_met[node, operational_period] +
        transport_shed[node, operational_period] >=
        natural_gas_transport_demand(
            par,
            node,
            period_context[operational_period].strategic,
        ) /
        (8760 * gas.mwhPerTon),
    )
    @constraint(
        emp,
        natural_gas_flow_balance[node in gas_nodes, operational_period in periods],
        sum(
            terminal_import[node, terminal, operational_period]
            for terminal in natural_gas_terminals(sets, node);
            init = 0.0,
        ) +
        sum(
            transmission[source, node, operational_period]
            for source in natural_gas_incoming(sets, node);
            init = 0.0,
        ) +
        gas.storageDischargeEfficiency * discharge[node, operational_period] ==
        sum(
            for_power[node, generator, operational_period]
            for generator in generators(sets, node)
            if generator in natural_gas_generators(sets);
            init = 0.0,
        ) +
        sum(
            transmission[node, destination, operational_period]
            for destination in natural_gas_outgoing(sets, node);
            init = 0.0,
        ) +
        charge[node, operational_period] +
        (
            node in natural_gas_onshore_nodes(sets) ?
            transport_met[node, operational_period] : 0.0
        ),
    )
    return nothing
end

function natural_gas_objective_expressions(
    emp::JuMP.Model,
    sets,
    par,
    periods,
    discounter,
)
    haskey(JuMP.object_dictionary(emp), :ngTerminalImport) ||
        return (terminal_import = JuMP.AffExpr(0.0), transport_shedding = JuMP.AffExpr(0.0))
    terminal_import = emp[:ngTerminalImport]
    transport_shed = emp[:transportNaturalGasDemandShed]
    gas = par.NaturalGas
    period_context = _natural_gas_period_maps(periods, gas.gasScenarioCount)

    terminal_import_cost = sum(
        objective_weight(operational_period, discounter; type = "avg_year") *
        natural_gas_terminal_cost(
            par,
            node,
            terminal,
            period_context[operational_period].strategic,
            period_context[operational_period].gas,
        ) *
        terminal_import[node, terminal, operational_period]
        for (node, terminal) in natural_gas_terminal_nodes(sets)
        for operational_period in periods;
        init = JuMP.AffExpr(0.0),
    )
    transport_shedding_cost = sum(
        objective_weight(operational_period, discounter; type = "avg_year") *
        gas.transportCurtailCost *
        transport_shed[node, operational_period]
        for node in _natural_gas_onshore_nodes(sets)
        for operational_period in periods;
        init = JuMP.AffExpr(0.0),
    )
    return (
        terminal_import = terminal_import_cost,
        transport_shedding = transport_shedding_cost,
    )
end
