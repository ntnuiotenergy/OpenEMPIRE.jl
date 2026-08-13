function _write_csv(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
end

function _write_toy_csv_dataset(root)
    dataset = joinpath(root, "toy")

    _write_csv(joinpath(dataset, "Sets", "Generator.csv"), "Generator\ngas\nwind\n")
    _write_csv(joinpath(dataset, "Sets", "ThermalGenerators.csv"), "ThermalGenerators\ngas\n")
    _write_csv(joinpath(dataset, "Sets", "HydroGenerator.csv"), "HydroGenerator\n")
    _write_csv(joinpath(dataset, "Sets", "RegHydroGenerator.csv"), "RegHydroGenerator\n")
    _write_csv(joinpath(dataset, "Sets", "Storage.csv"), "Storage\nbattery\n")
    _write_csv(joinpath(dataset, "Sets", "DependentStorage.csv"), "DependentStorage\nbattery\n")
    _write_csv(joinpath(dataset, "Sets", "Technology.csv"), "Technology\nthermal\nrenewable\n")
    _write_csv(joinpath(dataset, "Sets", "Node.csv"), "Node\nA\nB\n")
    _write_csv(joinpath(dataset, "Sets", "DirectionalLink.csv"), "NodeFrom,NodeTo\nA,B\nB,A\n")
    _write_csv(joinpath(dataset, "Sets", "TransmissionType.csv"), "TransmissionType\nHVDC\n")
    _write_csv(
        joinpath(dataset, "Sets", "TransmissionTypeOfDirectionalLink.csv"),
        "NodeFrom,NodeTo,TransmissionType\nA,B,HVDC\nB,A,HVDC\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "GeneratorsOfTechnology.csv"),
        "Technology,Generator\nthermal,gas\nrenewable,wind\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "GeneratorsOfNode.csv"),
        "Node,Generator\nA,gas\nA,wind\nB,wind\n",
    )
    _write_csv(joinpath(dataset, "Sets", "StoragesOfNode.csv"), "Node,Storage\nA,battery\n")

    _write_csv(joinpath(dataset, "Generator", "genCapitalCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,100\nwind,1,200\n")
    _write_csv(joinpath(dataset, "Generator", "genFixedOMCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,10\nwind,1,20\n")
    _write_csv(joinpath(dataset, "Generator", "genVariableOMCost.csv"), "Generator,Value\ngas,5\nwind,0\n")
    _write_csv(joinpath(dataset, "Generator", "genFuelCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,8\nwind,1,0\n")
    _write_csv(joinpath(dataset, "Generator", "CCSCostTSVariable.csv"), "Period,Value\n1,0\n")
    _write_csv(joinpath(dataset, "Generator", "genEfficiency.csv"), "GeneratorTechnology,Period,Value\ngas,1,0.5\nwind,1,1\n")
    _write_csv(joinpath(dataset, "Generator", "genRefInitCap.csv"), "Node,Generator,Value\nA,gas,1\nA,wind,2\n")
    _write_csv(joinpath(dataset, "Generator", "genScaleInitCap.csv"), "GeneratorTechnology,Period,Value\ngas,1,0\nwind,1,0\n")
    _write_csv(joinpath(dataset, "Generator", "genInitCap.csv"), "Node,Generator,Period,Value\nA,gas,1,1\nA,wind,1,2\n")
    _write_csv(joinpath(dataset, "Generator", "genMaxBuiltCap.csv"), "Node,Technology,Period,Value\nA,thermal,1,1000\nA,renewable,1,1000\n")
    _write_csv(joinpath(dataset, "Generator", "genMaxInstalledCapRaw.csv"), "Node,Technology,Value\nA,thermal,1000\nA,renewable,1000\n")
    _write_csv(joinpath(dataset, "Generator", "genRampUpCap.csv"), "Generator,Value\ngas,1\nwind,1\n")
    _write_csv(joinpath(dataset, "Generator", "genCapAvailTypeRaw.csv"), "Generator,Value\ngas,1\nwind,1\n")
    _write_csv(joinpath(dataset, "Generator", "genCO2TypeFactor.csv"), "Generator,Value\ngas,0.2\nwind,0\n")
    _write_csv(joinpath(dataset, "Generator", "genLifetime.csv"), "Generator,Value\ngas,30\nwind,25\n")

    _write_csv(joinpath(dataset, "Transmission", "transmissionInitCap.csv"), "From,To,Period,Value\nA,B,1,1\nB,A,1,1\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionMaxBuiltCap.csv"), "From,To,Period,Value\nA,B,1,100\nB,A,1,100\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionMaxInstalledCapRaw.csv"), "From,To,Period,Value\nA,B,1,100\nB,A,1,100\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionLength.csv"), "From,To,Value\nA,B,10\nB,A,10\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionTypeCapitalCost.csv"), "Type,Period,Value\nHVDC,1,1\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionTypeFixedOMCost.csv"), "Type,Period,Value\nHVDC,1,0\n")
    _write_csv(joinpath(dataset, "Transmission", "lineEfficiency.csv"), "From,To,Value\nA,B,0.95\nB,A,0.95\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionLifetime.csv"), "From,To,Value\nA,B,40\nB,A,40\n")

    _write_csv(joinpath(dataset, "Storage", "storageBleedEff.csv"), "Storage,Value\nbattery,1\n")
    _write_csv(joinpath(dataset, "Storage", "storageChargeEff.csv"), "Storage,Value\nbattery,0.9\n")
    _write_csv(joinpath(dataset, "Storage", "storageDischargeEff.csv"), "Storage,Value\nbattery,0.9\n")
    _write_csv(joinpath(dataset, "Storage", "storagePowToEnergy.csv"), "Storage,Value\nbattery,1\n")
    _write_csv(joinpath(dataset, "Storage", "storENCapitalCost.csv"), "Storage,Period,Value\nbattery,1,1\n")
    _write_csv(joinpath(dataset, "Storage", "storENFixedOMCost.csv"), "Storage,Period,Value\nbattery,1,0\n")
    _write_csv(joinpath(dataset, "Storage", "storENInitCap.csv"), "Node,Storage,Period,Value\nA,battery,1,0\n")
    _write_csv(joinpath(dataset, "Storage", "storENMaxBuiltCap.csv"), "Node,Storage,Period,Value\nA,battery,1,100\n")
    _write_csv(joinpath(dataset, "Storage", "storENMaxInstalledCapRaw.csv"), "Node,Storage,Value\nA,battery,100\n")
    _write_csv(joinpath(dataset, "Storage", "storOperationalInit.csv"), "Storage,Value\nbattery,0\n")
    _write_csv(joinpath(dataset, "Storage", "storPWCapitalCost.csv"), "Storage,Period,Value\nbattery,1,1\n")
    _write_csv(joinpath(dataset, "Storage", "storPWFixedOMCost.csv"), "Storage,Period,Value\nbattery,1,0\n")
    _write_csv(joinpath(dataset, "Storage", "storPWInitCap.csv"), "Node,Storage,Period,Value\nA,battery,1,0\n")
    _write_csv(joinpath(dataset, "Storage", "storPWMaxBuiltCap.csv"), "Node,Storage,Period,Value\nA,battery,1,100\n")
    _write_csv(joinpath(dataset, "Storage", "storPWMaxInstalledCapRaw.csv"), "Node,Storage,Value\nA,battery,100\n")
    _write_csv(joinpath(dataset, "Storage", "storageLifetime.csv"), "Storage,Value\nbattery,15\n")

    _write_csv(joinpath(dataset, "Node", "nodeLostLoadCost.csv"), "Node,Period,Value\nA,1,1000\nB,1,1000\n")
    _write_csv(joinpath(dataset, "Node", "sloadAnnualDemand.csv"), "Node,Period,Value\nA,1,100\nB,1,50\n")
    _write_csv(joinpath(dataset, "Node", "maxHydroNode.csv"), "Node,Value\nA,0\nB,0\n")

    _write_csv(joinpath(dataset, "General", "CO2cap.csv"), "Period,Value\n1,100\n")
    _write_csv(joinpath(dataset, "General", "CO2price.csv"), "Period,Value\n1,10\n")
    mkpath(joinpath(dataset, "ScenarioData"))

    return dataset
end

function test_read_csv_dataset()
    return mktempdir() do root
        dataset = _write_toy_csv_dataset(root)

        @test OpenEMPIRE.available_datasets(; root = root) == ["toy"]
        @test OpenEMPIRE.dataset_path("toy"; root = root) == dataset

        sets = OpenEMPIRE.read_sets_csv(dataset)
        @test OpenEMPIRE.nodes(sets) == ["A", "B"]
        @test isempty(OpenEMPIRE.offshore_nodes(sets))
        @test OpenEMPIRE.generators(sets, "A") == ["gas", "wind"]
        @test Set(OpenEMPIRE.arcs(sets)) == Set([("A", "B"), ("B", "A")])

        params = OpenEMPIRE.read_params_csv(dataset)
        @test params.genVariableOMCost["gas"] == 5.0
        @test params.genRefInitCap[("A", "wind")] == 2.0
        @test params.genCapAvailType["wind"] == 1.0
        @test params.genCO2Content["gas"] == 0.2
        @test params.transmissionLength[("A", "B")] == 10.0
        @test params.storageChargeEff["battery"] == 0.9
        @test params.maxHydroNode["A"] == 0.0
        sets2, params2 = OpenEMPIRE.read_data(dataset; format = :csv)
        @test OpenEMPIRE.nodes(sets2) == OpenEMPIRE.nodes(sets)
        @test params2.genVariableOMCost == params.genVariableOMCost

        csv_dataset = OpenEMPIRE.CsvDataset(root, "toy")
        sets3, _ = OpenEMPIRE.read_data(csv_dataset)
        @test OpenEMPIRE.generators(sets3) == ["gas", "wind"]
    end
end

function test_read_bundled_csv_datasets()
    data_root = joinpath(pkgdir(OpenEMPIRE), "data")

    datasets = OpenEMPIRE.available_datasets(; root = data_root)
    @test "test" in datasets
    @test "europe_v50" in datasets
    @test "europe_v51" in datasets

    test_sets, test_params = OpenEMPIRE.read_data(joinpath(data_root, "test"); format = :csv)
    @test length(OpenEMPIRE.nodes(test_sets)) == 3
    @test length(OpenEMPIRE.generators(test_sets)) == 27
    @test length(test_params.genVariableOMCost) == 27

    europe_sets, europe_params = OpenEMPIRE.read_data(joinpath(data_root, "europe_v51"); format = :csv)
    @test length(OpenEMPIRE.nodes(europe_sets)) == 49
    @test length(OpenEMPIRE.generators(europe_sets)) == 28
    @test length(OpenEMPIRE.arcs(europe_sets)) == 380
    @test length(europe_params.genCapitalCost) == 23
end

# The converted InternalEMPIRE dataset must load through the standard CSV reader
# and be runnable with or without the natural-gas module. InternalEMPIRE prices gas
# endogenously, so its workbook has no fuel cost for any gas technology; the
# converter fills those rows from europe_v51 (base OpenEMPIRE's own values) so a
# module-off run prices gas properly instead of at Pyomo's 0 default.
function test_read_full_model_int_dataset()
    data_root = joinpath(pkgdir(OpenEMPIRE), "data")
    dataset = joinpath(data_root, "full_model_int")
    isdir(dataset) || return

    @test "full_model_int" in OpenEMPIRE.available_datasets(; root = data_root)

    sets, params = OpenEMPIRE.read_data(dataset; format = :csv)
    @test length(OpenEMPIRE.nodes(sets)) == 52
    @test length(OpenEMPIRE.generators(sets)) == 33
    @test length(OpenEMPIRE.arcs(sets)) == 436

    # The workbook carries no fuel cost for these five; the converter supplies the
    # europe_v51 values so the dataset is usable with the gas module off.
    gas_generators = ["GasCCGT", "GasCCS", "GasCCSadv", "GasOCGT", "Gasexisting"]
    for generator in gas_generators
        @test generator in OpenEMPIRE.generators(sets)
        @test haskey(params.genFuelCost, generator)
        @test haskey(params.genEfficiency, generator)
    end

    periods = OpenEMPIRE.create_timestruct(7, 5, 4, 24, 2, 24, 1)

    # Module off: gas is priced from its fuel cost like any other thermal unit.
    # It must never fall through to DEFAULT_GEN_MARGINAL_COST, which would make
    # gas generation free.
    OpenEMPIRE.preprocess_operational_cost(params, sets, periods)
    first_period = first(periods)
    for generator in gas_generators
        @test haskey(params.genMargCost, generator)
        @test params.genMargCost[generator][first_period] > 0
    end

    # A dataset that genuinely omits the fuel cost must still fail loudly rather
    # than silently pricing gas at zero.
    stripped_sets, stripped_params = OpenEMPIRE.read_data(dataset; format = :csv)
    for generator in gas_generators
        delete!(stripped_params.genFuelCost, generator)
    end
    err = try
        OpenEMPIRE.preprocess_operational_cost(stripped_params, stripped_sets, periods)
        nothing
    catch caught
        caught
    end
    @test err isa ArgumentError
    @test any(occursin(generator, err.msg) for generator in gas_generators)
    @test occursin("genFuelCost", err.msg)
end

function test_native_timestruct_operational_weights()
    periods = OpenEMPIRE.create_timestruct(1, 5, 4, 2, 2, 1, 2)
    sp = first(strat_periods(periods))
    representatives = collect(repr_periods(sp))
    first_time = first(first(opscenarios(first(representatives))))
    discounter = Discounter(0.05, 1, periods)

    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        seasonNames = ["winter", "spring", "summer", "fall", "peak1", "peak2"],
        regularSeasonCount = 4,
    )

    op_discount = sum((1 + 0.05)^(-j) for j in 0:4)
    annual_multiple = (8760 - 2) / (4 * 2)

    @test OpenEMPIRE.regular_season_count(params, length(representatives)) == 4
    @test multiple_strat(sp, first_time) ≈ annual_multiple
    @test probability(first_time) == 0.5
    @test objective_weight(first_time, discounter; type = "avg_year") ≈
          objective_weight(sp, discounter) * op_discount * annual_multiple * probability(first_time)
end

function test_write_solution_csv_tables()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("A", "B", "HVDC"), ("B", "A", "HVDC")],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))
    times = collect(periods)
    first_time = times[1]
    second_time = times[2]
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        genInvCost = Dict("Solar" => StrategicProfile([10.0])),
        genMargCost = Dict("Solar" => StrategicProfile([2.0])),
        genEfficiency = Dict("Solar" => StrategicProfile([1.0])),
        genCO2Content = Dict("Solar" => 0.0),
        genCapAvailType = Dict("Solar" => 1.0),
        storPWInvCost = Dict("battery" => StrategicProfile([4.0])),
        storENInvCost = Dict("battery" => StrategicProfile([5.0])),
        storageChargeEff = Dict("battery" => 0.9),
        storageDischargeEff = Dict("battery" => 0.8),
        storageBleedEff = Dict("battery" => 0.95),
        lineEfficiency = Dict(("A", "B") => 0.9, ("B", "A") => 0.85),
    )

    emp = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(emp)
    OpenEMPIRE.create_variables(emp, sets, periods)
    @constraint(emp, emp[:genInvCap]["A", "Solar", sp] == 3.0)
    @constraint(emp, emp[:genInstalledCap]["A", "Solar", sp] == 10.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", first_time] == 4.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", second_time] == 6.0)
    @constraint(emp, emp[:storPWInvCap]["A", "battery", sp] == 2.0)
    @constraint(emp, emp[:storPWInstalledCap]["A", "battery", sp] == 7.0)
    @constraint(emp, emp[:storENInvCap]["A", "battery", sp] == 3.0)
    @constraint(emp, emp[:storENInstalledCap]["A", "battery", sp] == 8.0)
    @constraint(emp, emp[:storCharge]["A", "battery", first_time] == 1.0)
    @constraint(emp, emp[:storCharge]["A", "battery", second_time] == 2.0)
    @constraint(emp, emp[:storDischarge]["A", "battery", first_time] == 5.0)
    @constraint(emp, emp[:storDischarge]["A", "battery", second_time] == 7.0)
    @constraint(emp, emp[:storOperational]["A", "battery", first_time] == 9.0)
    @constraint(emp, emp[:storOperational]["A", "battery", second_time] == 10.0)
    @constraint(emp, emp[:transmissionInvCap]["A", "B", sp] == 11.0)
    @constraint(emp, emp[:transmissionInstalledCap]["A", "B", sp] == 12.0)
    @constraint(emp, emp[:transmissionOperational]["A", "B", first_time] == 13.0)
    @constraint(emp, emp[:transmissionOperational]["A", "B", second_time] == 14.0)
    @constraint(emp, emp[:transmissionOperational]["B", "A", first_time] == 15.0)
    @constraint(emp, emp[:transmissionOperational]["B", "A", second_time] == 16.0)
    @objective(emp, Min, emp[:genInvCap]["A", "Solar", sp])
    optimize!(emp)

    @test JuMP.is_solved_and_feasible(emp)

    mktempdir() do result_dir
        output_dir = OpenEMPIRE.write_solution_tables(result_dir, emp, sets, params, periods)
        @test basename(output_dir) == "output"
        expected_files = [
            "genInstalledCap.csv",
            "genInvCap.csv",
            "genOperational.csv",
            "investment_costs.csv",
            "loadShed.csv",
            "marginal_costs.csv",
            "results_objective.csv",
            "results_output_EuropePlot.csv",
            "results_output_EuropeSummary.csv",
            "results_output_Operational.csv",
            "results_output_curtailed_operational.csv",
            "results_output_curtailed_prod.csv",
            "results_output_gen.csv",
            "results_output_stor.csv",
            "results_output_transmission.csv",
            "results_output_transmission_operational.csv",
            "storCharge.csv",
            "storDischarge.csv",
            "storENInstalledCap.csv",
            "storENInvCap.csv",
            "storPWInstalledCap.csv",
            "storPWInvCap.csv",
            "storageOperational.csv",
            "transmissionInvCap.csv",
            "transmissionInstalledCap.csv",
            "transmissionOperational.csv",
        ]

        @test sort(readdir(output_dir)) == sort(expected_files)
        @test all(endswith(file, ".csv") for file in readdir(output_dir))

        gen_inv = collect(CSV.File(joinpath(output_dir, "genInvCap.csv")))
        @test propertynames(first(gen_inv)) == [:Node, :Generator, :Period, :genInvCap]
        @test length(gen_inv) == 1
        @test gen_inv[1].Node == "A"
        @test gen_inv[1].Generator == "Solar"
        @test gen_inv[1].Period == 1
        @test gen_inv[1].genInvCap ≈ 3.0

        trans_inv = collect(CSV.File(joinpath(output_dir, "transmissionInvCap.csv")))
        @test propertynames(first(trans_inv)) == [:FromNode, :ToNode, :Period, :transmissionInvCap]
        @test trans_inv[1].transmissionInvCap ≈ 11.0

        gen_operational = collect(CSV.File(joinpath(output_dir, "genOperational.csv")))
        @test propertynames(first(gen_operational)) ==
              [:Node, :Generator, :Period, :Scenario, :Season, :Hour, :genOperational]
        @test length(gen_operational) == 2
        @test gen_operational[1].Season == "winter"
        @test gen_operational[1].Scenario == 1
        @test gen_operational[1].Hour == 1
        @test gen_operational[1].genOperational ≈ 4.0

        gen_report = collect(CSV.File(joinpath(output_dir, "results_output_gen.csv")))
        weight = multiple_strat(sp, first_time) * probability(first_time)
        expected_generation = weight * (4.0 + 6.0)
        @test gen_report[1].GeneratorType == "Solar"
        @test gen_report[1].genExpectedCapacityFactor ≈ expected_generation / (10.0 * 8760)
        @test gen_report[1].DiscountedInvestmentCost_Euro ≈
              objective_weight(sp, Discounter(OpenEMPIRE.discount_rate(params), 1, periods)) * 3.0 * 10.0
        @test gen_report[1].genExpectedAnnualProduction_GWh ≈ expected_generation / 1000

        stor_report = collect(CSV.File(joinpath(output_dir, "results_output_stor.csv")))
        @test stor_report[1].ExpectedAnnualDischargeVolume_GWh ≈ weight * (5.0 + 7.0) / 1000
        expected_storage_losses = weight * ((1 - 0.8) * (5.0 + 7.0) + (1 - 0.9) * (1.0 + 2.0))
        @test stor_report[1].ExpectedAnnualLossesChargeDischarge_GWh ≈ expected_storage_losses / 1000

        trans_report = collect(CSV.File(joinpath(output_dir, "results_output_transmission.csv")))
        @test propertynames(first(trans_report)) == [
            :BetweenNode,
            :AndNode,
            :Period,
            :transmissionInvCap_MW,
            :transmissionInstalledCap_MW,
            :DiscountedInvestmentCost_Euro,
            :transmissionExpectedAnnualVolume_GWh,
            :ExpectedAnnualLosses_GWh,
        ]
        @test trans_report[1].transmissionExpectedAnnualVolume_GWh ≈ weight * (13.0 + 14.0 + 15.0 + 16.0) / 1000
        expected_transmission_losses = weight * ((1 - 0.9) * (13.0 + 14.0) + (1 - 0.85) * (15.0 + 16.0))
        @test trans_report[1].ExpectedAnnualLosses_GWh ≈ expected_transmission_losses / 1000

        curtailment = collect(CSV.File(joinpath(output_dir, "results_output_curtailed_prod.csv")))
        @test curtailment[1].ExpectedAnnualCurtailment_GWh ≈ weight * ((10.0 - 4.0) + (10.0 - 6.0)) / 1000

        operational = collect(CSV.File(joinpath(output_dir, "results_output_Operational.csv")))
        @test :Solar_MW in propertynames(first(operational))
    end
end

function test_europe_summary_uses_per_scenario_totals()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = String[],
        Technology = ["Solar"],
        Node = ["A"],
        DirectionalLink = Tuple{String, String}[],
        TransmissionType = String[],
        TransmissionTypeOfDirectionalLink = Tuple{String, String, String}[],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = Tuple{String, String}[],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 2)
    sp = first(strat_periods(periods))
    scenarios = collect(opscenarios(first(repr_periods(sp))))
    scenario_one_times = collect(scenarios[1])
    scenario_two_times = collect(scenarios[2])
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        genInvCost = Dict("Solar" => StrategicProfile([10.0])),
        genMargCost = Dict("Solar" => StrategicProfile([2.0])),
        genEfficiency = Dict("Solar" => StrategicProfile([1.0])),
        genCO2Content = Dict("Solar" => 0.0),
        genCapAvailType = Dict("Solar" => 1.0),
    )

    emp = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(emp)
    OpenEMPIRE.create_variables(emp, sets, periods)
    @constraint(emp, emp[:genInvCap]["A", "Solar", sp] == 0.0)
    @constraint(emp, emp[:genInstalledCap]["A", "Solar", sp] == 100.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", scenario_one_times[1]] == 4.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", scenario_one_times[2]] == 6.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", scenario_two_times[1]] == 10.0)
    @constraint(emp, emp[:genOperational]["A", "Solar", scenario_two_times[2]] == 14.0)
    @objective(emp, Min, emp[:genInvCap]["A", "Solar", sp])
    optimize!(emp)

    @test JuMP.is_solved_and_feasible(emp)

    mktempdir() do result_dir
        output_dir = OpenEMPIRE.write_solution_tables(result_dir, emp, sets, params, periods)

        gen_report = collect(CSV.File(joinpath(output_dir, "results_output_gen.csv")))
        annual_multiple = multiple_strat(sp, first(scenario_one_times))
        expected_generation = annual_multiple * 0.5 * (4.0 + 6.0 + 10.0 + 14.0)
        @test gen_report[1].genExpectedAnnualProduction_GWh ≈ expected_generation / 1000

        europe_summary = collect(CSV.File(IOBuffer(first(split(read(joinpath(output_dir, "results_output_EuropeSummary.csv"), String), "\n\n")))))
        scenario_one = only(row for row in europe_summary if row.Scenario == "scenario1")
        scenario_two = only(row for row in europe_summary if row.Scenario == "scenario2")
        @test scenario_one.AnnualGeneration_GWh ≈ annual_multiple * (4.0 + 6.0) / 1000
        @test scenario_two.AnnualGeneration_GWh ≈ annual_multiple * (10.0 + 14.0) / 1000
    end
end

"""
The CCS fixed transport-and-storage cost is data-driven, and its default is the
historical hardcoded constant.

`ccs_cost_fix` used to be a literal `1149873.72` in `utils.jl` (with a standing TODO
to remove the hardcoding). It is now read from an optional
`Generator/CCSCostTSFixed.csv`. Datasets without that file must behave exactly as
before, or every existing CCS investment cost silently changes.
"""
function test_ccs_fixed_cost_is_data_driven()
    par = OpenEMPIRE.EmpireParams()
    @test par.CCSCostTSFixed === nothing
    @test OpenEMPIRE.ccs_cost_fixed(par) == OpenEMPIRE.DEFAULT_CCS_COST_FIXED
    @test OpenEMPIRE.DEFAULT_CCS_COST_FIXED == 1149873.72

    par.CCSCostTSFixed = 0.0
    @test OpenEMPIRE.ccs_cost_fixed(par) == 0.0
    par.CCSCostTSFixed = 42.5
    @test OpenEMPIRE.ccs_cost_fixed(par) == 42.5

    mktempdir() do root
        path = joinpath(root, "CCSCostTSFixed.csv")
        write(path, "CCS_TSfixed_cost_in_euro_per_tCO2\n1234.5\n")
        @test OpenEMPIRE._read_scalar_csv(path) == 1234.5
        write(path, "header\n")
        @test_throws ArgumentError OpenEMPIRE._read_scalar_csv(path)
    end
end
