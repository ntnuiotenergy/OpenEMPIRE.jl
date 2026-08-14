#!/usr/bin/env julia

include(joinpath(@__DIR__, "natural_gas_parity_julia.jl"))

function solve_hydrogen_parity_fixture(
    fixture_dir::AbstractString,
    output_path::AbstractString,
)
    scalar = _read_scalar_parameters(joinpath(fixture_dir, "parameters.csv"))
    hours = collect(CSV.File(joinpath(fixture_dir, "hours.csv")))
    hour_count = length(hours)
    periods = OpenEMPIRE.create_timestruct(
        1, 1, 1, hour_count, 0, 0, 1;
        operational_hours_per_year = hour_count,
    )
    gas_sets = OpenEMPIRE.NaturalGasSets(
        Node = ["A", "B", "C"],
        Terminal = ["DomesticProduction"],
        TerminalsOfNode = [("B", "DomesticProduction")],
        OnshoreNode = ["A", "B", "C"],
    )
    hydrogen_sets = OpenEMPIRE.HydrogenSets(
        ProductionNode = ["A", "B", "C"],
        Generator = ["HydrogenCCGT"],
        ReformerLocation = ["B"],
        ReformerPlant = ["SMR_CCS"],
        Storage = ["Cavern"],
        StoragesOfNode = [("B", "Cavern")],
        TerminalNode = ["A"],
        Terminal = ["PipelineH2Import"],
        TerminalsOfNode = [("A", "PipelineH2Import")],
        CO2SequestrationNode = ["C"],
        DirectionalLink = [("A", "B"), ("B", "C")],
        CO2DirectionalLink = [("B", "C")],
    )
    sets = OpenEMPIRE.EmpireSets(
        Node = ["A", "B", "C"],
        Generator = ["Grid", "HydrogenCCGT"],
        Technology = ["GridTechnology", "HydrogenTechnology"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [
            ("GridTechnology", "Grid"),
            ("HydrogenTechnology", "HydrogenCCGT"),
        ],
        GeneratorsOfNode = [
            ("A", "Grid"),
            ("B", "Grid"),
            ("C", "HydrogenCCGT"),
        ],
        NaturalGas = gas_sets,
        Hydrogen = hydrogen_sets,
    )
    gas = OpenEMPIRE.NaturalGasParams(
        terminalCost = Dict(
            ("B", "DomesticProduction", 1, 1) =>
                scalar["gas_terminal_cost_eur_per_ton"],
        ),
        terminalCapacity = Dict(
            ("B", "DomesticProduction", 1) =>
                scalar["gas_terminal_capacity_ton_per_hour"],
        ),
        storageCapacity = Dict(node => 0.0 for node in ("A", "B", "C")),
        reserves = Dict("B" => scalar["gas_terminal_reserve_ton"]),
        transportDemand = Dict((node, 1) => 0.0 for node in ("A", "B", "C")),
        transportCurtailCost = scalar["transport_shed_cost_eur_per_ton"],
        mwhPerTon = scalar["natural_gas_mwh_per_ton"],
    )
    plant = "SMR_CCS"
    terminal = "PipelineH2Import"
    hydrogen = OpenEMPIRE.HydrogenParams(
        electrolyzerCapitalCost = Dict(1 => 0.0),
        electrolyzerFixedOMCost = Dict(1 => 0.0),
        electrolyzerPowerUse = Dict(1 => scalar["electrolyzer_power_use_mwh_per_ton"]),
        electrolyzerLifetime = 20.0,
        reformerCapitalCost = Dict((plant, 1) => 0.0),
        reformerFixedOMCost = Dict((plant, 1) => 0.0),
        reformerVariableOMCost = Dict(
            (plant, 1) => scalar["reformer_variable_cost_eur_per_ton"],
        ),
        reformerEfficiency = Dict((plant, 1) => scalar["reformer_efficiency"]),
        reformerElectricityUse = Dict(
            (plant, 1) => scalar["reformer_electricity_mwh_per_ton"],
        ),
        reformerEmissionFactor = Dict((plant, 1) => 0.0),
        reformerCO2CaptureFactor = Dict(
            (plant, 1) => scalar["reformer_co2_capture_ton_per_ton_h2"],
        ),
        reformerLifetime = Dict(plant => 20.0),
        pipelineCapitalCost = Dict(1 => 0.0),
        pipelineOMCostPerKM = Dict(1 => 0.0),
        pipelineCompressorPowerUsage =
            scalar["hydrogen_pipeline_distance_power_mwh_per_ton_km"],
        storageCapitalCost = Dict(("Cavern", 1) => 0.0),
        storageFixedOMCost = Dict(("Cavern", 1) => 0.0),
        storageLifetime = Dict("Cavern" => 30.0),
        storageMaxCapacity = Dict(
            ("B", "Cavern") => scalar["hydrogen_storage_capacity_ton"],
        ),
        terminalInitialCapacity = Dict(("A", terminal, 1) => 0.0),
        terminalCapitalCost = Dict(("A", terminal, 1) => 0.0),
        terminalFixedOMCost = Dict(("A", terminal, 1) => 0.0),
        terminalPrice = Dict(
            ("A", terminal, 1) => scalar["hydrogen_terminal_cost_eur_per_ton"],
        ),
        terminalLifetime = Dict(terminal => 20.0),
        electricityTransportDemand = Dict(
            (node, 1) => 0.0 for node in ("A", "B", "C")
        ),
        hydrogenTransportDemand = Dict(
            (node, 1) => (
                node == "B" ?
                scalar["hydrogen_transport_demand_ton_per_hour"] *
                8760 * scalar["hydrogen_mwh_per_ton"] :
                0.0
            ) for node in ("A", "B", "C")
        ),
        generatorCO2Captured = Dict("Grid" => 0.0, "HydrogenCCGT" => 0.0),
        co2StorageMaxCapacity = Dict(
            ("C", 1) => scalar["co2_sequestration_capacity_ton_per_hour"],
        ),
        co2MaxSequestrationCapacity = Dict("C" => 1000.0),
        co2StorageSiteCapitalCost = Dict("C" => 0.0),
        co2StorageSiteFixedOMCost = Dict("C" => 0.0),
        co2PipelineCapitalCost = 0.0,
        co2PipelineFixedOMCost = 0.0,
        co2PipelineElectricityUsage = scalar["co2_pipeline_power_mwh_per_ton"],
        co2PipelineLifetime = 40.0,
        hydrogenMWhPerTon = scalar["hydrogen_mwh_per_ton"],
        storageInitialFraction = scalar["hydrogen_storage_initial_fraction"],
        storageCompressionMWhPerTon =
            scalar["hydrogen_storage_compression_mwh_per_ton"],
        pipelineCompressorStaticMWhPerTon =
            scalar["hydrogen_pipeline_static_power_mwh_per_ton"],
        pipelineLifetime = 40.0,
        pipelineLeakageFractionPerKM = scalar["hydrogen_pipeline_leakage_per_km"],
        reformerRampFractionPerHour = scalar["reformer_ramp_fraction_per_hour"],
    )
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        genEfficiency = Dict(
            "Grid" => FixedProfile(1.0),
            "HydrogenCCGT" => FixedProfile(scalar["hydrogen_generator_efficiency"]),
        ),
        # The fixture pins genInstalledCap for Grid and HydrogenCCGT. Maximum
        # installed capacity is keyed by (node, technology) and defaults to zero, so
        # the base investment constraints would make those pins infeasible. The
        # workbench avoided this by gating the base builders too, but that gating
        # lives in the unmerged out-of-sample stack; giving the fixture headroom is
        # equivalent here and keeps this branch free of that dependency.
        genMaxInstalledCap = Dict(
            (node, technology) => FixedProfile(1.0e6)
            for node in ("A", "B", "C")
            for technology in ("GridTechnology", "HydrogenTechnology")
        ),
        genCapAvail = Dict(
            ("A", "Grid") => FixedProfile(1.0),
            ("B", "Grid") => FixedProfile(1.0),
            ("C", "HydrogenCCGT") => FixedProfile(1.0),
        ),
        genCO2Content = Dict("Grid" => 0.0, "HydrogenCCGT" => 0.0),
        genMargCost = Dict(
            "Grid" => FixedProfile(scalar["grid_marginal_cost_eur_per_mwh"]),
            "HydrogenCCGT" => FixedProfile(
                scalar["hydrogen_generator_marginal_cost_eur_per_mwh"],
            ),
        ),
        sload = Dict(
            node => _single_scenario_profile(
                Float64[getproperty(row, Symbol("Load$(node)_MW")) for row in hours],
            ) for node in ("A", "B", "C")
        ),
        nodeLostLoadCost = Dict(
            node => FixedProfile(scalar["lost_load_cost_eur_per_mwh"])
            for node in ("A", "B", "C")
        ),
        transmissionLength = Dict(
            ("A", "B") => scalar["hydrogen_pipeline_length_km"],
            ("B", "C") => scalar["hydrogen_pipeline_length_km"],
        ),
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        NaturalGas = gas,
        Hydrogen = hydrogen,
    )

    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(
        model, sets, periods; natural_gas = true, hydrogen = true,
    )
    OpenEMPIRE.create_constraints(
        model,
        sets,
        params,
        periods;
        natural_gas = true,
        hydrogen = true,
        include_investment_constraints = false,
    )
    strategic_period = only(collect(strat_periods(periods)))
    for variable_name in (
        :genInvCap,
        :electrolyzerCapBuilt,
        :reformerCapBuilt,
        :hydrogenPipelineCapBuilt,
        :hydrogenStorageCapBuilt,
        :hydrogenImportCapBuilt,
        :co2PipelineCapBuilt,
        :co2SequestrationCapBuilt,
    )
        for variable in model[variable_name]
            JuMP.fix(variable, 0.0; force = true)
        end
    end
    JuMP.fix(model[:genInstalledCap]["A", "Grid", strategic_period], scalar["grid_capacity_mw"]; force = true)
    JuMP.fix(model[:genInstalledCap]["B", "Grid", strategic_period], scalar["grid_capacity_mw"]; force = true)
    JuMP.fix(model[:genInstalledCap]["C", "HydrogenCCGT", strategic_period], scalar["hydrogen_generator_capacity_mw"]; force = true)
    for node in ("A", "B", "C")
        capacity = node == "A" ? scalar["electrolyzer_capacity_mw"] : 0.0
        JuMP.fix(model[:electrolyzerCapInstalled][node, strategic_period], capacity; force = true)
    end
    JuMP.fix(model[:reformerCapInstalled]["B", plant, strategic_period], scalar["reformer_capacity_mwh_h2_per_hour"]; force = true)
    for corridor in (("A", "B"), ("B", "C"))
        JuMP.fix(model[:hydrogenPipelineCapInstalled][corridor..., strategic_period], scalar["hydrogen_pipeline_capacity_ton_per_hour"]; force = true)
    end
    JuMP.fix(model[:hydrogenStorageCapInstalled]["B", "Cavern", strategic_period], scalar["hydrogen_storage_capacity_ton"]; force = true)
    JuMP.fix(model[:hydrogenImportCapInstalled]["A", terminal, strategic_period], scalar["hydrogen_terminal_capacity_ton_per_hour"]; force = true)
    JuMP.fix(model[:co2PipelineCapInstalled]["B", "C", strategic_period], scalar["co2_pipeline_capacity_ton_per_hour"]; force = true)
    JuMP.fix(model[:co2SequestrationCapInstalled]["C", strategic_period], scalar["co2_sequestration_capacity_ton_per_hour"]; force = true)

    discounter = OpenEMPIRE.Discounter(0.05, 1, periods)
    OpenEMPIRE.create_objective(
        model,
        sets,
        params,
        periods,
        discounter;
        natural_gas = true,
        hydrogen = true,
    )
    JuMP.optimize!(model)
    JuMP.termination_status(model) == JuMP.MOI.OPTIMAL || error(
        "Julia Hydrogen fixture did not solve: $(JuMP.termination_status(model))",
    )
    components = OpenEMPIRE.objective_component_values(
        model, sets, params, periods, discounter,
    )
    output_rows = NamedTuple[]
    push!(output_rows, _metric_row("objective_total", 0, "all", JuMP.objective_value(model)))
    push!(output_rows, _metric_row("objective_generator_operation", 0, "all", components.generator_operation))
    push!(output_rows, _metric_row("objective_gas_import", 0, "all", components.natural_gas_terminal_import))
    push!(output_rows, _metric_row("objective_hydrogen_import", 0, "all", components.hydrogen_terminal_import))
    push!(output_rows, _metric_row("objective_reformer_operation", 0, "all", components.hydrogen_reformer_operation))
    push!(output_rows, _metric_row("objective_transport_shedding", 0, "all", components.hydrogen_transport_shedding))
    for (hour, operational_period) in enumerate(periods)
        for node in ("A", "B")
            push!(output_rows, _metric_row("grid_generation", hour, node, JuMP.value(model[:genOperational][node, "Grid", operational_period])))
        end
        push!(output_rows, _metric_row("hydrogen_generation", hour, "C", JuMP.value(model[:genOperational]["C", "HydrogenCCGT", operational_period])))
        push!(output_rows, _metric_row("gas_import", hour, "B", JuMP.value(model[:ngTerminalImport]["B", "DomesticProduction", operational_period])))
        push!(output_rows, _metric_row("electrolyzer_power", hour, "A", JuMP.value(model[:electrolyzerElectricity]["A", operational_period])))
        push!(output_rows, _metric_row("electrolyzer_hydrogen", hour, "A", JuMP.value(model[:electrolyzerHydrogen]["A", operational_period])))
        push!(output_rows, _metric_row("hydrogen_import", hour, "A", JuMP.value(model[:hydrogenImportTon]["A", terminal, operational_period])))
        push!(output_rows, _metric_row("reformer_hydrogen", hour, "B", JuMP.value(model[:reformerHydrogenTon]["B", plant, operational_period])))
        push!(output_rows, _metric_row("reformer_gas", hour, "B", JuMP.value(model[:reformerNaturalGas]["B", plant, operational_period])))
        for (label, from, to) in (("A->B", "A", "B"), ("B->C", "B", "C"))
            push!(output_rows, _metric_row("hydrogen_pipeline", hour, label, JuMP.value(model[:hydrogenPipelineFlow][from, to, operational_period])))
        end
        push!(output_rows, _metric_row("storage_level", hour, "B", JuMP.value(model[:hydrogenStorageLevel]["B", "Cavern", operational_period])))
        push!(output_rows, _metric_row("storage_charge", hour, "B", JuMP.value(model[:hydrogenStorageCharge]["B", "Cavern", operational_period])))
        push!(output_rows, _metric_row("storage_discharge", hour, "B", JuMP.value(model[:hydrogenStorageDischarge]["B", "Cavern", operational_period])))
        push!(output_rows, _metric_row("transport_hydrogen_met", hour, "B", JuMP.value(model[:transportHydrogenDemandMet]["B", operational_period])))
        push!(output_rows, _metric_row("transport_hydrogen_shed", hour, "B", JuMP.value(model[:transportHydrogenDemandShed]["B", operational_period])))
        push!(output_rows, _metric_row("hydrogen_for_power", hour, "C", JuMP.value(model[:hydrogenForPower]["C", "HydrogenCCGT", operational_period])))
        push!(output_rows, _metric_row("co2_pipeline", hour, "B->C", JuMP.value(model[:co2PipelineFlow]["B", "C", operational_period])))
        push!(output_rows, _metric_row("co2_sequestered", hour, "C", JuMP.value(model[:co2Sequestered]["C", operational_period])))
    end
    mkpath(dirname(output_path))
    CSV.write(output_path, output_rows)
    println("Julia Hydrogen parity output: $output_path")
    return output_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error(
        "Usage: julia --project=. scripts/hydrogen_parity_julia.jl FIXTURE_DIR OUTPUT.csv",
    )
    solve_hydrogen_parity_fixture(ARGS[1], ARGS[2])
end
