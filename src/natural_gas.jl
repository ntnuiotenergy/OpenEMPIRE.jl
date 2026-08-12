"""
Terminal types whose cumulative imports are bounded by a finite reserve at the
node. Matched case-insensitively, as InternalEMPIRE does.
"""
const FINITE_RESERVE_TERMINALS = Set(("domesticproduction", "pipelineimport"))

# Reserve and storage rows carry tonne-scale right-hand sides (reserves reach
# ~5.6e8 t) against ~7.3e3 coefficients. InternalEMPIRE divides both sides of
# these rows by 1e3 for conditioning; mirroring that keeps the coefficient range
# comparable and the feasible set identical.
const NATURAL_GAS_ROW_SCALE = 1.0e-3

const OperationalPeriodContext = NamedTuple{
    (:strategic, :weather, :gas),
    Tuple{Int, Int, Int},
}

is_finite_reserve_terminal(terminal) = lowercase(terminal) in FINITE_RESERVE_TERMINALS

_natural_gas_onshore_nodes(sets) =
    [node for node in natural_gas_nodes(sets) if node in natural_gas_onshore_nodes(sets)]

_natural_gas_node_generators(sets) = [
    (node, generator)
    for (node, generator) in node_generators(sets)
    if generator in natural_gas_generators(sets)
]

function _sector_period_maps(periods, gas_scenario_count::Int)
    period_type = eltype(periods)
    context = Dict{period_type, OperationalPeriodContext}()
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

"""
    _natural_gas_period_context(emp, periods, gas_scenario_count)

Return the cached operational-period context for `emp`, building it on first use.

Constraint building, the objective, and objective-component reporting all need
the same map; without caching it is rebuilt three times per model (about 8 MiB
per build at 19,440 operational periods).
"""
function _sector_period_context(
    emp::JuMP.Model,
    periods,
    gas_scenario_count::Int,
)
    context_type = Dict{eltype(periods), OperationalPeriodContext}
    cached = get(emp.ext, :sector_period_context, nothing)
    cached isa context_type && return cached
    context = _sector_period_maps(periods, gas_scenario_count)::context_type
    emp.ext[:sector_period_context] = context
    return context
end

const NaturalGasPeriodContext = OperationalPeriodContext
_natural_gas_period_maps(periods, gas_scenario_count::Int) =
    _sector_period_maps(periods, gas_scenario_count)
_natural_gas_period_context(emp::JuMP.Model, periods, gas_scenario_count::Int) =
    _sector_period_context(emp, periods, gas_scenario_count)

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
function create_natural_gas_variables!(
    emp::JuMP.Model, sets, periods; transport_demand::Bool = false,
)
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
    # Only populate the transport variables when transport demand is modelled. Left
    # populated with the demand constraint off, they are free and unconstrained: at
    # full scale that is ~1.77 million degenerate columns, which stalled the barrier
    # (Solstorm 6511 terminated sub-optimal with a 2.3% duality gap).
    if transport_demand
        for node in onshore_nodes, operational_period in periods
            unsafe_insertvar!(transportNaturalGasDemandMet, node, operational_period)
            unsafe_insertvar!(transportNaturalGasDemandShed, node, operational_period)
        end
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
        is_finite_reserve_terminal(terminal) || continue
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
                            # LeapYearsInvestment * seasScale, matching
                            # InternalEMPIRE's naturalGas_max_reserves_rule.
                            #
                            # Accumulated in place: `total_import += coef * var`
                            # rebuilds the expression each iteration, so this row --
                            # which spans every operational period -- would be
                            # O(n^2). At 19,440 periods that is seconds and gigabytes
                            # per row.
                            JuMP.add_to_expression!(
                                total_import,
                                NATURAL_GAS_ROW_SCALE *
                                duration_strat(strategic_period) *
                                multiple_strat(strategic_period, operational_period),
                                terminal_import[node, terminal, operational_period],
                            )
                        end
                    end
                end
                # Named so the rows are identifiable in an exported LP and in solver
                # diagnostics (IIS). Anonymous rows are invisible to any LP-level
                # comparison against the Python reference.
                push!(
                    constraints,
                    @constraint(
                        emp,
                        total_import <=
                        NATURAL_GAS_ROW_SCALE * natural_gas_reserves(par, node),
                        base_name = "natural_gas_max_reserves[$node,$terminal,$weather_scenario,$gas_scenario]",
                    ),
                )
            end
        end
    end
    emp[:natural_gas_max_reserves] = constraints
    return constraints
end

"""
    create_natural_gas_constraints!(model, sets, params, periods; transport_demand = false)

Add InternalEMPIRE-compatible gas conversion, terminal, reserve, storage,
pipeline, transport-demand, and nodal-balance constraints.

Transport demand is part of InternalEMPIRE's hydrogen block, not its natural-gas
module: `transport_naturalGasDemandMet`/`Shed`, and the constraint that meets that
demand, are all declared inside `if hydrogen is True:` (`empire.py:1703` and `:2441`).
Running the reference with `NaturalGas=True, hydrogen=False` therefore has no transport
natural-gas demand at all.

The port matches that placement so a gas-only run is comparable. Left on, the port
carries a demand the reference does not and sheds it at the 100 000 EUR/MWh curtailment
price, which on `full_model_int` was 56% of the objective.

Whether transport genuinely belongs to hydrogen is a question for InternalEMPIRE --
natural-gas transport demand has no obvious dependence on hydrogen — so this is a
faithful port of the reference's structure, not an endorsement of it.
"""
function create_natural_gas_constraints!(
    emp::JuMP.Model, sets, par, periods; transport_demand::Bool = false,
)
    gas = par.NaturalGas
    period_context = _natural_gas_period_context(emp, periods, gas.gasScenarioCount)
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
        NATURAL_GAS_ROW_SCALE * (
            (
                isnothing(previous) ?
                gas.storageInitialFraction * natural_gas_storage_capacity(par, node) :
                storage[node, previous]
            ) +
            gas.storageChargeEfficiency * charge[node, operational_period] -
            discharge[node, operational_period]
        ) ==
        NATURAL_GAS_ROW_SCALE * storage[node, operational_period],
    )
    @constraint(
        emp,
        natural_gas_storage_cyclic[
            node in gas_nodes,
            strategic_period in strat_periods(periods),
            scenario in opscenarios(strategic_period),
        ],
        NATURAL_GAS_ROW_SCALE * storage[node, last(scenario)] ==
            NATURAL_GAS_ROW_SCALE *
            gas.storageInitialFraction *
            natural_gas_storage_capacity(par, node),
    )
    @constraint(
        emp,
        natural_gas_storage_max_capacity[
            node in gas_nodes,
            operational_period in periods,
        ],
        NATURAL_GAS_ROW_SCALE * storage[node, operational_period] <=
            NATURAL_GAS_ROW_SCALE * natural_gas_storage_capacity(par, node),
    )
    @constraint(
        emp,
        natural_gas_pipeline_capacity_limit[
            (from, to) in natural_gas_links(sets),
            operational_period in periods,
        ],
        transmission[from, to, operational_period] +
        (haskey(JuMP.object_dictionary(emp), :hydrogenRepurposedGasPipelineCapInstalled) &&
         (from, to) in hydrogen_sets(sets).RepurposableGasCorridor ?
            emp[:hydrogenRepurposedGasPipelineCapInstalled][
                from,
                to,
                collect(strat_periods(periods))[period_context[operational_period].strategic],
            ] : 0.0) <= natural_gas_pipeline_capacity(par, from, to),
    )
    transport_demand && @constraint(
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
        (haskey(JuMP.object_dictionary(emp), :reformerNaturalGas) &&
         node in hydrogen_sets(sets).ReformerLocation ?
            sum(
                emp[:reformerNaturalGas][node, plant, operational_period]
                for plant in hydrogen_sets(sets).ReformerPlant;
                init = 0.0,
            ) : 0.0) +
        sum(
            transmission[node, destination, operational_period]
            for destination in natural_gas_outgoing(sets, node);
            init = 0.0,
        ) +
        charge[node, operational_period] +
        (
            transport_demand && node in natural_gas_onshore_nodes(sets) ?
            transport_met[node, operational_period] : 0.0
        ) + industry_natural_gas_demand(emp, sets, par, node, operational_period),
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
    period_context = _natural_gas_period_context(emp, periods, gas.gasScenarioCount)

    # `sum` over a generator folds left, so each step copies the whole partial
    # expression: an n-term sum costs O(n^2). Over every operational period that
    # is the dominant cost of the post-solve diagnostics. `add_to_expression!`
    # appends in place. See the same note in `objective_component_expressions`.
    terminal_import_cost = JuMP.AffExpr(0.0)
    for (node, terminal) in natural_gas_terminal_nodes(sets),
        operational_period in periods

        context = period_context[operational_period]
        JuMP.add_to_expression!(
            terminal_import_cost,
            objective_weight(operational_period, discounter; type = "avg_year") *
            natural_gas_terminal_cost(par, node, terminal, context.strategic, context.gas),
            terminal_import[node, terminal, operational_period],
        )
    end
    transport_shedding_cost = JuMP.AffExpr(0.0)
    for node in _natural_gas_onshore_nodes(sets), operational_period in periods
        JuMP.add_to_expression!(
            transport_shedding_cost,
            objective_weight(operational_period, discounter; type = "avg_year") *
            gas.transportCurtailCost,
            transport_shed[node, operational_period],
        )
    end
    return (
        terminal_import = terminal_import_cost,
        transport_shedding = transport_shedding_cost,
    )
end
