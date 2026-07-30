function _write_natural_gas_csv_fixture(dataset; gas_scenarios::Int = 1)
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasNodes.csv"),
        "NaturalGasNodes\nA\nB\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasDirectionalLines.csv"),
        "NodeFrom,NodeTo\nA,B\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasTerminals.csv"),
        "NaturalGasTerminals\nDomesticProduction\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "NaturalGasTerminalsOfNode.csv"),
        "Node,NG_Terminal_Type\nA,DomesticProduction\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "OnshoreNode.csv"),
        "OnshoreNode\nA\nB\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "PipelineCapacity.csv"),
        "FromNode,ToNode,Capacity_(ton/h)\nA,B,100\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "PipelineElectricityUse.csv"),
        "Power_usage_[MWh/ton]\n0.024\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "StorageCapacity.csv"),
        "Node,Storage_(ton)\nA,10\nB,0\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "Reserves.csv"),
        "Node,Reserves_(tons)\nA,1000000\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCapacity.csv"),
        "Node,Terminal,Period,Capacity_(ton/hr)\nA,DomesticProduction,1,100\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCost.csv"),
        "Node,Terminal,Period,Scenario,Cost_(EUR/ton)\n" *
        "A,DomesticProduction,1,1,100\n",
    )
    stochastic_rows = join(
        (
            "A,DomesticProduction,1,$scenario,$(100 * scenario)"
            for scenario in 1:gas_scenarios
        ),
        "\n",
    )
    _write_csv(
        joinpath(dataset, "NaturalGas", "TerminalCost_stochastic.csv"),
        "Node,Terminal,Period,GasScenario,Cost_(EUR/ton)\n" *
        stochastic_rows *
        "\n",
    )
    _write_csv(
        joinpath(dataset, "Transport", "NaturalGasDemand.csv"),
        "Node,Period,Natural_gas_demand_[MWh/yr]\nA,1,0\nB,1,0\n",
    )
    _write_csv(
        joinpath(dataset, "Transport", "CurtailCost.csv"),
        "CurtailCost_(€/MWh)\n100000\n",
    )
    return dataset
end

function _natural_gas_solved_fixture(
    ;
    weather_scenarios::Int = 1,
    gas_scenarios::Int = 1,
    pipeline_power::Float64 = 0.024,
)
    combined_scenarios = weather_scenarios * gas_scenarios
    periods = OpenEMPIRE.create_timestruct(
        1,
        5,
        1,
        1,
        0,
        0,
        combined_scenarios;
        operational_hours_per_year = 1,
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
        ThermalGenerators = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT"), ("B", "GasCCGT")],
        NaturalGas = gas_sets,
    )
    terminal_cost = Dict(
        ("A", "DomesticProduction", 1, scenario) => 100.0 * scenario
        for scenario in 1:gas_scenarios
    )
    gas = OpenEMPIRE.NaturalGasParams(
        pipelineCapacity = Dict(("A", "B") => 100.0),
        pipelinePowerDemandPerTon = pipeline_power,
        terminalCost = terminal_cost,
        terminalCapacity = Dict(("A", "DomesticProduction", 1) => 100.0),
        storageCapacity = Dict("A" => 0.0, "B" => 0.0),
        reserves = Dict("A" => 1.0e9),
        transportDemand = Dict(("A", 1) => 0.0, ("B", 1) => 0.0),
        weatherScenarioCount = weather_scenarios,
        gasScenarioCount = gas_scenarios,
    )
    params = OpenEMPIRE.EmpireParams(
        WACC = 0.05,
        discountRate = 0.05,
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genCapAvail = Dict(
            ("A", "GasCCGT") => FixedProfile(1.0),
            ("B", "GasCCGT") => FixedProfile(1.0),
        ),
        genCO2Content = Dict("GasCCGT" => 0.0),
        genMargCost = Dict("GasCCGT" => FixedProfile(0.0)),
        sload = Dict("A" => FixedProfile(0.0), "B" => FixedProfile(10.0)),
        nodeLostLoadCost = Dict(
            "A" => FixedProfile(1.0e6),
            "B" => FixedProfile(1.0e6),
        ),
        seasonNames = ["winter"],
        regularSeasonCount = 1,
        NaturalGas = gas,
    )

    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)
    OpenEMPIRE.create_variables(model, sets, periods; natural_gas = true)
    OpenEMPIRE.create_constraints(
        model,
        sets,
        params,
        periods;
        natural_gas = true,
        include_investment_constraints = false,
    )
    strategic_period = only(collect(strat_periods(periods)))
    for node in ("A", "B")
        JuMP.fix(
            model[:genInstalledCap][node, "GasCCGT", strategic_period],
            100.0;
            force = true,
        )
    end
    discounter = Discounter(0.05, 1, periods)
    OpenEMPIRE.create_objective(
        model,
        sets,
        params,
        periods,
        discounter;
        natural_gas = true,
    )
    JuMP.optimize!(model)
    return model, periods, sets, params, discounter
end

function test_natural_gas_csv_loading_and_validation()
    mktempdir() do root
        dataset = _write_natural_gas_csv_fixture(
            _write_toy_csv_dataset(root);
            gas_scenarios = 2,
        )
        module_off_sets, _ = OpenEMPIRE.read_data(dataset; format = :csv)
        @test !OpenEMPIRE.has_natural_gas(module_off_sets)

        sets, params = OpenEMPIRE.read_data(
            dataset;
            format = :csv,
            natural_gas = true,
            weather_scenarios = 3,
            gas_scenarios = 2,
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 6)
        @test OpenEMPIRE.has_natural_gas(sets)
        @test OpenEMPIRE.natural_gas_nodes(sets) == ["A", "B"]
        @test OpenEMPIRE.natural_gas_generators(sets) == Set(["gas"])
        @test params.NaturalGas.weatherScenarioCount == 3
        @test params.NaturalGas.gasScenarioCount == 2
        @test params.NaturalGas.terminalCost[
            ("A", "DomesticProduction", 1, 2)
        ] == 200.0
        @test isempty(OpenEMPIRE.validate(params; sets, periods, strict = false))

        malformed_cases = (
            (
                "Node,Reserves_(tons)\nA,1\nA,2\n",
                "Duplicate natural-gas key A",
            ),
            (
                "Node,Reserves_(tons)\nA,NaN\n",
                "value must be finite",
            ),
            (
                "Node,Reserves_(tons)\nA,-1\n",
                "value must be non-negative",
            ),
            (
                "Node,Reserves_(tons)\nA,alphabetic\n",
                "expected a number",
            ),
            (
                "Node,Reserves_(tons)\nA,\n",
                "empty value",
            ),
        )
        reserve_path = joinpath(dataset, "NaturalGas", "Reserves.csv")
        for (content, expected) in malformed_cases
            _write_csv(reserve_path, content)
            error = try
                OpenEMPIRE.read_data(
                    dataset;
                    format = :csv,
                    natural_gas = true,
                    weather_scenarios = 3,
                    gas_scenarios = 2,
                )
                nothing
            catch err
                err
            end
            @test error isa ArgumentError
            @test occursin(expected, sprint(showerror, error))
            @test occursin(reserve_path, sprint(showerror, error))
        end
    end
end

function test_natural_gas_scenario_mapping_and_costs()
    @test OpenEMPIRE.gas_scenario_count(
        Dict(
            "natural_gas" => false,
            "number_of_scenarios" => 3,
            "number_of_gas_scenarios" => 9,
        ),
    ) == 1
    for (weather_count, gas_count) in ((1, 1), (2, 2), (3, 3))
        config = Dict(
            "natural_gas" => true,
            "number_of_scenarios" => weather_count,
            "number_of_gas_scenarios" => gas_count,
        )
        @test OpenEMPIRE.combined_scenario_count(config) ==
              weather_count * gas_count
        @test [
            (
                OpenEMPIRE.weather_scenario_index(index, gas_count),
                OpenEMPIRE.gas_scenario_index(index, gas_count),
            ) for index in 1:(weather_count * gas_count)
        ] == [
            (weather, gas)
            for weather in 1:weather_count for gas in 1:gas_count
        ]
    end

    sets = OpenEMPIRE.EmpireSets(
        Node = ["A"],
        Generator = ["GasCCGT"],
        Technology = ["Gas"],
        TransmissionType = ["AC"],
        GeneratorsOfTechnology = [("Gas", "GasCCGT")],
        GeneratorsOfNode = [("A", "GasCCGT")],
        NaturalGas = OpenEMPIRE.NaturalGasSets(
            Node = ["A"],
            Generator = ["GasCCGT"],
        ),
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 1, 0, 0, 1)
    parameters = OpenEMPIRE.EmpireParams(
        genFuelCost = Dict("GasCCGT" => FixedProfile(8.0)),
        genEfficiency = Dict("GasCCGT" => FixedProfile(0.5)),
        genVariableOMCost = Dict("GasCCGT" => 5.0),
        genCO2Content = Dict("GasCCGT" => 0.2),
        CO2price = FixedProfile(10.0),
    )
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = false,
    )
    @test parameters.genMargCost["GasCCGT"][first(periods)] ≈ 77.0
    OpenEMPIRE.preprocess_operational_cost(
        parameters,
        sets,
        periods;
        natural_gas = true,
    )
    @test parameters.genMargCost["GasCCGT"][first(periods)] ≈ 19.4
end

function test_weather_profiles_replicate_across_gas_scenarios()
    mktempdir() do root
        _write_fixed_sample_scenario_data(root)
        sampling_rows = ["Period,Scenario,Season,Year,Month,Hour"]
        for weather in 1:2
            sample_hour = weather
            for (season, month) in
                (("winter", 1), ("spring", 4), ("summer", 7), ("fall", 10))
                push!(
                    sampling_rows,
                    "1,$weather,$season,2020,$month,$sample_hour",
                )
            end
            push!(sampling_rows, "1,$weather,peak,2020,0,0")
        end
        _write_csv(
            joinpath(root, "ScenarioData", "sampling_key.csv"),
            join(sampling_rows, "\n") * "\n",
        )
        config = Dict{String, Any}(
            "natural_gas" => true,
            "number_of_scenarios" => 2,
            "number_of_gas_scenarios" => 3,
            "regular_seasons" => ["winter", "spring", "summer", "fall"],
            "length_of_regular_season" => 4,
            "n_peak_seasons" => 2,
            "len_peak_season" => 2,
            "use_fixed_sample" => true,
            "time_format" => "%d/%m/%Y %H:%M",
        )
        periods = OpenEMPIRE.create_timestruct(1, 5, 4, 4, 2, 2, 6)
        sets = _scenario_test_sets()
        params = OpenEMPIRE.EmpireParams(
            genCapAvailType = Dict(generator => 0.0 for generator in sets.Generator),
        )
        OpenEMPIRE.generate_scenario_csv!(
            root,
            periods,
            params,
            sets,
            config;
            rng = MersenneTwister(17),
        )
        rows = collect(
            CSV.File(joinpath(root, "ScenarioData", "sloadRaw.csv")),
        )
        values = Dict(
            (Int(row.Operationalhour), String(row.Scenario)) =>
                Float64(row.ElectricLoadRaw_in_MW)
            for row in rows
        )
        for hour in sort!(unique(first(key) for key in keys(values)))
            @test values[(hour, "scenario1")] == values[(hour, "scenario2")] ==
                  values[(hour, "scenario3")]
            @test values[(hour, "scenario4")] == values[(hour, "scenario5")] ==
                  values[(hour, "scenario6")]
        end
        @test any(
            values[(hour, "scenario1")] != values[(hour, "scenario4")]
            for hour in sort!(unique(first(key) for key in keys(values)))
        )
    end
end

function test_natural_gas_model_and_results()
    pipeline_power = 0.024
    model, periods, sets, params, discounter = _natural_gas_solved_fixture(
        weather_scenarios = 2,
        gas_scenarios = 2,
        pipeline_power = pipeline_power,
    )
    @test JuMP.termination_status(model) == JuMP.MOI.OPTIMAL
    @test all(
        JuMP.value(model[:loadShed][node, operational_period]) ≈ 0.0
        for node in OpenEMPIRE.nodes(sets) for operational_period in periods
    )

    expected_pipeline = 10.0 / (0.5 * params.NaturalGas.mwhPerTon)
    expected_compressor_generation = pipeline_power * expected_pipeline
    expected_import =
        expected_pipeline +
        expected_compressor_generation / (0.5 * params.NaturalGas.mwhPerTon)
    for operational_period in periods
        @test JuMP.value(
            model[:ngTransmission]["A", "B", operational_period],
        ) ≈ expected_pipeline
        @test JuMP.value(
            model[:genOperational]["A", "GasCCGT", operational_period],
        ) ≈ expected_compressor_generation
        @test JuMP.value(
            model[:ngTerminalImport][
                "A",
                "DomesticProduction",
                operational_period,
            ],
        ) ≈ expected_import
    end
    @test length(model[:natural_gas_max_reserves]) == 4
    @test length(model[:natural_gas_storage_balance].data) ==
          2 * length(periods)

    components = OpenEMPIRE.objective_component_values(
        model,
        sets,
        params,
        periods,
        discounter,
    )
    @test components.natural_gas_terminal_import ≈ JuMP.objective_value(model)
    @test components.natural_gas_transport_shedding ≈ 0.0

    mktempdir() do output_dir
        OpenEMPIRE.write_natural_gas_csvs(
            output_dir,
            model,
            sets,
            params,
            periods,
        )
        expected_files = (
            "ngTerminalImport.csv",
            "ngTransmission.csv",
            "ngForPower.csv",
            "ngStorage.csv",
            "naturalGasBalance.csv",
            "transportNaturalGas.csv",
            "results_natural_gas_terminals.csv",
            "results_natural_gas_pipeline.csv",
            "results_natural_gas_for_power.csv",
            "results_natural_gas_storage.csv",
            "results_natural_gas_balance.csv",
            "results_transport_naturalGas_operations.csv",
            "naturalGasOperationalDuals.csv",
        )
        @test all(isfile(joinpath(output_dir, file)) for file in expected_files)
        terminal_rows = collect(CSV.File(joinpath(output_dir, "ngTerminalImport.csv")))
        @test Set(Int(row.WeatherScenario) for row in terminal_rows) == Set(1:2)
        @test Set(Int(row.GasScenario) for row in terminal_rows) == Set(1:2)
        balance_rows = collect(CSV.File(joinpath(output_dir, "naturalGasBalance.csv")))
        @test all(abs(Float64(row.BalanceResidual_ton)) <= 1.0e-10 for row in balance_rows)
    end
end

function test_natural_gas_oos_compatibility_and_full_year_streaming()
    source_config = Dict{String, Any}(
        "forecast_horizon_year" => 2025,
        "leap_years_investment" => 5,
        "north_sea" => false,
        "natural_gas" => true,
        "use_emission_cap" => false,
        "discount_rate" => 0.05,
        "wacc" => 0.05,
        "load_change_module" => false,
    )
    fixed_metadata = Dict{String, Any}(
        "provenance" => Dict{String, Any}(
            "structural_config" =>
                OpenEMPIRE._oos_structural_config(source_config),
        ),
    )
    compatible = OpenEMPIRE.validate_oos_fixed_investment_compatibility(
        fixed_metadata,
        source_config,
    )
    @test compatible["status"] == "compatible"
    @test "natural_gas" in compatible["required_equal"]
    module_off = copy(source_config)
    module_off["natural_gas"] = false
    @test_throws ArgumentError OpenEMPIRE.validate_oos_fixed_investment_compatibility(
        fixed_metadata,
        module_off,
    )

    mktempdir() do root
        summaries = NamedTuple[]
        for tree_index in 1:24
            run_dir = joinpath(root, "tree$tree_index")
            lines = [
                "Node,Period,Scenario,WeatherScenario,GasScenario,Season,Hour,NaturalGasForPower_ton",
            ]
            append!(
                lines,
                "A,1,1,1,1,winter,$hour,$(tree_index + hour / 1000)"
                for hour in 1:365
            )
            push!(lines, "A,1,1,1,1,peak1,1,999999")
            _write_csv(
                joinpath(run_dir, "output", "ngForPower.csv"),
                join(lines, "\n") * "\n",
            )
            push!(
                summaries,
                (
                    Tree = "tree$tree_index",
                    Seed = tree_index,
                    RunDirectory = run_dir,
                    FullYearTreeIndex = tree_index,
                ),
            )
        end
        result = OpenEMPIRE._stream_internalempire_full_year_csv(
            summaries,
            "ngForPower.csv",
            joinpath(root, "combined"),
        )
        @test result.rows == 8760
        @test result.dummy_peak_rows_ignored == 24
        rows = collect(CSV.File(result.path))
        @test length(rows) == 8760
        @test Int(first(rows).HourFullYear) == 1
        @test Int(last(rows).HourFullYear) == 8760
        @test all(String(row.Season) == "winter" for row in rows)
        @test all(
            Float64(row.NaturalGasForPower_ton) != 999999.0 for row in rows
        )
    end
end
