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
    _write_csv(joinpath(dataset, "General", "seasScale.csv"), "Season,seasonScale\nwinter,3\nspring,4\n")
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
        @test params.seasScale["winter"] == 3.0
        @test OpenEMPIRE.season_scale(params, 1) == 1.0

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

function test_python_style_operational_weights()
    periods = OpenEMPIRE.create_timestruct(1, 5, 4, 2, 2, 1, 2)
    sp = first(strat_periods(periods))
    representatives = collect(repr_periods(sp))
    first_time = first(first(opscenarios(first(representatives))))
    discounter = Discounter(0.05, 1, periods)

    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        seasScale = Dict("winter" => 3.0, "spring" => 4.0),
        seasonNames = ["winter", "spring", "summer", "fall", "peak1", "peak2"],
        regularSeasonCount = 4,
    )

    op_discount = sum((1 + 0.05)^(-j) for j in 0:4)

    @test OpenEMPIRE.season_scale(params, 1) == 3.0
    @test OpenEMPIRE.season_scale(params, 3) == 1.0
    @test OpenEMPIRE.regular_season_count(params, length(representatives)) == 4
    @test OpenEMPIRE.operational_discount_scale(params, sp) ≈ op_discount
    @test OpenEMPIRE.seasonal_probability_weight(params, 1, first_time) ≈
          3.0 * probability(first_time)
    @test OpenEMPIRE.operational_objective_weight(params, sp, 1, first_time, discounter) ≈
          objective_weight(sp, discounter) * op_discount * 3.0 * probability(first_time)
end

function test_write_solution_csv_tables()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["gas"],
        Storage = ["battery"],
        Technology = ["thermal"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("A", "B", "HVDC"), ("B", "A", "HVDC")],
        GeneratorsOfTechnology = [("thermal", "gas")],
        GeneratorsOfNode = [("A", "gas")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))
    first_time = first(periods)
    params = OpenEMPIRE.EmpireParams(
        seasonNames = ["winter"],
        regularSeasonCount = 1,
    )

    emp = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(emp)
    OpenEMPIRE.create_variables(emp, sets, periods)
    @constraint(emp, emp[:genInvCap]["A", "gas", sp] == 3.0)
    @constraint(emp, emp[:genOperational]["A", "gas", first_time] == 4.0)
    @objective(emp, Min, emp[:genInvCap]["A", "gas", sp])
    optimize!(emp)

    @test JuMP.is_solved_and_feasible(emp)

    mktempdir() do result_dir
        output_dir = OpenEMPIRE.write_solution_tables(result_dir, emp, sets, params, periods)
        expected_files = [
            "genInstalledCap.csv",
            "genInvCap.csv",
            "genOperational.csv",
            "loadShed.csv",
            "storCharge.csv",
            "storDischarge.csv",
            "storENInstalledCap.csv",
            "storENInvCap.csv",
            "storPWInstalledCap.csv",
            "storPWInvCap.csv",
            "storageOperational.csv",
            "transmisionInvCap.csv",
            "transmisionOperational.csv",
            "transmissionInstalledCap.csv",
        ]

        @test sort(readdir(output_dir)) == expected_files
        @test all(endswith(file, ".csv") for file in readdir(output_dir))

        gen_inv = collect(CSV.File(joinpath(output_dir, "genInvCap.csv")))
        @test propertynames(first(gen_inv)) == [:Node, :Generator, :Period, :genInvCap]
        @test length(gen_inv) == 1
        @test gen_inv[1].Node == "A"
        @test gen_inv[1].Generator == "gas"
        @test gen_inv[1].Period == 1
        @test gen_inv[1].genInvCap ≈ 3.0

        gen_operational = collect(CSV.File(joinpath(output_dir, "genOperational.csv")))
        @test propertynames(first(gen_operational)) ==
              [:Node, :Generator, :Period, :Scenario, :Season, :Hour, :genOperational]
        @test length(gen_operational) == 2
        @test gen_operational[1].Season == "winter"
        @test gen_operational[1].Scenario == 1
        @test gen_operational[1].Hour == 1
        @test gen_operational[1].genOperational ≈ 4.0
    end
end
