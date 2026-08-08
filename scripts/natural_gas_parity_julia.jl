#!/usr/bin/env julia

using CSV
using HiGHS
using JuMP
using OpenEMPIRE
using TimeStruct

function _read_scalar_parameters(path::AbstractString)
    values = Dict{String, Float64}()
    for row in CSV.File(path)
        values[String(row.Parameter)] = Float64(row.Value)
    end
    return values
end

function _single_scenario_profile(values::Vector{Float64})
    return StrategicProfile([
        RepresentativeProfile([
            ScenarioProfile([OperationalProfile(values)]),
        ]),
    ])
end

function _metric_row(metric, hour, node, value)
    return (
        Metric = String(metric),
        Hour = Int(hour),
        Node = String(node),
        Value = Float64(value),
    )
end

function solve_julia_parity_fixture(
    fixture_dir::AbstractString,
    output_path::AbstractString,
)
    scalar = _read_scalar_parameters(joinpath(fixture_dir, "parameters.csv"))
    hours = collect(CSV.File(joinpath(fixture_dir, "hours.csv")))
    hour_count = length(hours)
    hour_count > 0 || throw(ArgumentError("Parity fixture must contain at least one hour"))

    periods = OpenEMPIRE.create_timestruct(
        1,
        1,
        1,
        hour_count,
        0,
        0,
        1;
        operational_hours_per_year = hour_count,
    )
    gas_sets = OpenEMPIRE.NaturalGasSets(
        Node = ["A", "B"],
        DirectionalLink = [("A", "B")],
        Terminal = ["DomesticProduction"],
        TerminalsOfNode = [("A", "DomesticProduction")],
        OnshoreNode = ["A", "B"],
        Generator = ["GasCCGT"],
    )
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A", "B"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT"), ("B", "GasCCGT")],
        NaturalGas = gas_sets,
    )
    gas = OpenEMPIRE.NaturalGasParams(
        pipelineCapacity = Dict(
            ("A", "B") => scalar["pipeline_capacity_ton_per_hour"],
        ),
        pipelinePowerDemandPerTon = scalar["pipeline_power_mwh_per_ton"],
        terminalCost = Dict(
            ("A", "DomesticProduction", 1, 1) =>
                scalar["terminal_cost_eur_per_ton"],
        ),
        terminalCapacity = Dict(
            ("A", "DomesticProduction", 1) =>
                scalar["terminal_capacity_ton_per_hour"],
        ),
        storageCapacity = Dict(
            "A" => 0.0,
            "B" => scalar["storage_capacity_b_ton"],
        ),
        reserves = Dict("A" => scalar["terminal_reserve_ton"]),
        transportDemand = Dict(
            ("A", 1) => 0.0,
            ("B", 1) =>
                scalar["transport_demand_b_ton_per_hour"] * 8760 *
                scalar["mwh_per_ton"],
        ),
        transportCurtailCost = scalar["transport_shed_cost_eur_per_ton"],
        mwhPerTon = scalar["mwh_per_ton"],
        storageInitialFraction = scalar["storage_initial_fraction"],
    )
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        genEfficiency = Dict(
            "GasCCGT" => FixedProfile(scalar["generator_efficiency"]),
        ),
        genMaxInstalledCap = Dict(
            ("A", "Gas") => FixedProfile(1.0e6),
            ("B", "Gas") => FixedProfile(1.0e6),
        ),
        genCapAvail = Dict(
            ("A", "GasCCGT") => FixedProfile(1.0),
            ("B", "GasCCGT") => FixedProfile(1.0),
        ),
        genCO2Content = Dict("GasCCGT" => 0.0),
        genMargCost = Dict(
            "GasCCGT" =>
                FixedProfile(scalar["generator_marginal_cost_eur_per_mwh"]),
        ),
        sload = Dict(
            "A" => _single_scenario_profile(
                Float64[row.LoadA_MW for row in hours],
            ),
            "B" => _single_scenario_profile(
                Float64[row.LoadB_MW for row in hours],
            ),
        ),
        nodeLostLoadCost = Dict(
            "A" => FixedProfile(scalar["lost_load_cost_eur_per_mwh"]),
            "B" => FixedProfile(scalar["lost_load_cost_eur_per_mwh"]),
        ),
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        NaturalGas = gas,
    )
    issues = OpenEMPIRE.validate(params; sets, periods, strict = false)
    isempty(issues) || throw(ArgumentError(join(issues, "\n")))

    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(model, sets, periods; natural_gas = true)
    OpenEMPIRE.create_constraints(
        model,
        sets,
        params,
        periods;
        natural_gas = true,
        # The Pyomo reference this is compared against models transport demand
        # (natural_gas_parity_python.py), so enable it here too. Full runs leave it off
        # unless hydrogen is modelled -- see create_natural_gas_constraints!.
        gas_transport_demand = true,
    )
    strategic_period = only(collect(strat_periods(periods)))
    for node in ("A", "B")
        JuMP.fix(
            model[:genInstalledCap][node, "GasCCGT", strategic_period],
            scalar["generator_capacity_mw"];
            force = true,
        )
    end
    discounter = OpenEMPIRE.Discounter(0.05, 1, periods)
    OpenEMPIRE.create_objective(
        model,
        sets,
        params,
        periods,
        discounter,
    )
    JuMP.optimize!(model)
    JuMP.termination_status(model) == JuMP.MOI.OPTIMAL ||
        error("Julia parity fixture did not solve to optimality: $(JuMP.termination_status(model))")

    components = OpenEMPIRE.objective_component_values(
        model,
        sets,
        params,
        periods,
        discounter,
    )
    rows = NamedTuple[]
    push!(rows, _metric_row("objective_total", 0, "all", JuMP.objective_value(model)))
    push!(
        rows,
        _metric_row(
            "objective_terminal_import",
            0,
            "all",
            components.natural_gas_terminal_import,
        ),
    )
    push!(
        rows,
        _metric_row(
            "objective_generator_operation",
            0,
            "all",
            components.generator_operation,
        ),
    )
    push!(
        rows,
        _metric_row(
            "objective_transport_shedding",
            0,
            "all",
            components.natural_gas_transport_shedding,
        ),
    )
    for (hour, operational_period) in enumerate(periods)
        push!(
            rows,
            _metric_row(
                "terminal_import",
                hour,
                "A",
                JuMP.value(
                    model[:ngTerminalImport][
                        "A",
                        "DomesticProduction",
                        operational_period,
                    ],
                ),
            ),
        )
        push!(
            rows,
            _metric_row(
                "pipeline_flow",
                hour,
                "A->B",
                JuMP.value(model[:ngTransmission]["A", "B", operational_period]),
            ),
        )
        for node in ("A", "B")
            push!(
                rows,
                _metric_row(
                    "electricity_generation",
                    hour,
                    node,
                    JuMP.value(
                        model[:genOperational][node, "GasCCGT", operational_period],
                    ),
                ),
            )
            push!(
                rows,
                _metric_row(
                    "gas_for_power",
                    hour,
                    node,
                    JuMP.value(
                        model[:ngForPower][node, "GasCCGT", operational_period],
                    ),
                ),
            )
        end
        for metric_container in (
            ("storage_level", :ngStorageOperational),
            ("storage_charge", :ngStorageCharge),
            ("storage_discharge", :ngStorageDischarge),
        )
            push!(
                rows,
                _metric_row(
                    metric_container[1],
                    hour,
                    "B",
                    JuMP.value(model[metric_container[2]]["B", operational_period]),
                ),
            )
        end
        for metric_container in (
            ("transport_demand_met", :transportNaturalGasDemandMet),
            ("transport_demand_shed", :transportNaturalGasDemandShed),
        )
            push!(
                rows,
                _metric_row(
                    metric_container[1],
                    hour,
                    "B",
                    JuMP.value(model[metric_container[2]]["B", operational_period]),
                ),
            )
        end
    end
    mkpath(dirname(output_path))
    CSV.write(output_path, rows)
    println("Julia natural-gas parity output: $output_path")
    return output_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 ||
        error("Usage: julia --project=. scripts/natural_gas_parity_julia.jl FIXTURE_DIR OUTPUT.csv")
    solve_julia_parity_fixture(ARGS[1], ARGS[2])
end
