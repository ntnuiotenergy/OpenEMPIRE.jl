function test_full_year_oos_generation()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        source_before = _oos_source_snapshot(source_data)
        experiment_dir = joinpath(root, "full-year")

        prepared = OpenEMPIRE.prepare_full_year_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            sample_years = [2015],
            input_format = :csv,
        )

        @test prepared == abspath(experiment_dir)
        @test _oos_source_snapshot(source_data) == source_before
        manifest = YAML.load_file(joinpath(prepared, "experiment.yaml"))
        @test manifest["status"] == "complete"
        @test manifest["evaluation_mode"] == "chronological_full_year"
        @test manifest["sample_years"] == [2015]
        @test manifest["operational_hours_per_year"] == 8760
        @test manifest["trees"][1]["sample_year"] == 2015

        execution_config_file = manifest["source_config_file"]
        execution_config = YAML.load_file(execution_config_file)
        @test execution_config["number_of_scenarios"] == 1
        @test execution_config["regular_seasons"] == ["full_year"]
        @test execution_config["length_of_regular_season"] == 8760
        @test execution_config["operational_hours_per_year"] == 8760
        @test execution_config["n_peak_seasons"] == 0
        @test execution_config["len_peak_season"] == 0
        @test execution_config["use_scenario_generation"] == false
        @test execution_config["use_fixed_sample"] == false

        tree_dir = joinpath(prepared, "oos_tree1")
        metadata_file = joinpath(tree_dir, "metadata.yaml")
        metadata = YAML.load_file(metadata_file)
        @test metadata["schema_version"] == 2
        @test metadata["evaluation_mode"] == "chronological_full_year"
        @test metadata["sample_year"] == 2015
        @test metadata["chronology"]["operational_hours"] == 8760
        @test metadata["chronology"]["expected_hour_multiplicity"] == 1
        @test metadata["chronology"]["dummy_peak"] == false
        @test metadata["chronology"]["storage_cycle_boundaries_per_strategic_period"] == 1
        @test metadata["source_config_sha256"] ==
              OpenEMPIRE._oos_sha256_file(execution_config_file)
        @test metadata["generation_source_config_sha256"] ==
              OpenEMPIRE._oos_sha256_file(config_file)
        @test all(
            source["selected_rows"] == 8760 for
            source in values(metadata["raw_sources"])
        )

        load_rows = CSV.File(
            joinpath(tree_dir, "ScenarioData", "sloadRaw.csv");
            normalizenames = false,
        )
        germany_period1 = [
            Int(row.Operationalhour) for row in load_rows if
            String(row.Node) == "Germany" && Int(row.Period) == 1
        ]
        @test germany_period1 == collect(1:8760)
        @test Set(String(row.Scenario) for row in load_rows) == Set(["scenario1"])
        availability_rows = CSV.File(
            joinpath(tree_dir, "ScenarioData", "genCapAvailStochRaw.csv");
            normalizenames = false,
        )
        generated_ror = [
            Float64(row.GeneratorStochasticAvailabilityRaw) for row in availability_rows if
            String(row.Node) == "Germany" &&
            String(row.IntermitentGenerators) == "Hydrorun-of-the-river" &&
            Int(row.Period) == 1
        ]
        raw_ror = OpenEMPIRE._read_raw_scenario_table(
            joinpath(source_data, "ScenarioData", "hydroror.csv"),
            OpenEMPIRE._python_dateformat(execution_config["time_format"]),
        )
        ror_indices = OpenEMPIRE._chronological_year_indices(
            raw_ror,
            2015,
            8760;
            require_full_year = true,
            source_name = "hydroror.csv",
        )
        @test generated_ror == OpenEMPIRE._normalized_scenario_value.(
            raw_ror.values["DE"][ror_indices],
        )
        @test raw_ror.timestamps[ror_indices] == [
            DateTime(2015, 1, 1) + Hour(offset) for offset in 0:8759
        ]

        investment_run = joinpath(root, "investment-run")
        _write_investment_csvs(joinpath(investment_run, "Output"))
        _write_test_investment_run_evidence(investment_run, config_file)
        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            prepared,
            investment_run;
            dataset = source_data,
            config_file = execution_config_file,
            results_root = joinpath(root, "results"),
            input_format = :csv,
            solver = "HiGHS",
        )
        queue = YAML.load_file(queue_file)
        @test queue["experiment"]["evaluation_mode"] == "chronological_full_year"
        @test queue["experiment"]["sample_years"] == [2015]
        @test queue["jobs"][1]["evaluation_mode"] == "chronological_full_year"
        @test queue["jobs"][1]["sample_year"] == 2015
        @test "--config=$execution_config_file" in queue["jobs"][1]["command"]
        mismatched_config_file = joinpath(root, "mismatched-full-year.yaml")
        mismatched_config = deepcopy(execution_config)
        mismatched_config["length_of_regular_season"] = 365
        YAML.write_file(mismatched_config_file, mismatched_config)
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_execution_queue(
            prepared,
            investment_run;
            dataset = source_data,
            config_file = mismatched_config_file,
            results_root = joinpath(root, "other-results"),
            queue_file = joinpath(root, "bad-execution.yaml"),
            input_format = :csv,
            solver = "HiGHS",
        )
        @test !isfile(joinpath(root, "bad-execution.yaml"))

        metadata_hash = OpenEMPIRE._oos_sha256_file(metadata_file)
        resumed = OpenEMPIRE.prepare_full_year_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            sample_years = [2015],
            input_format = :csv,
        )
        @test resumed == prepared
        @test OpenEMPIRE._oos_sha256_file(metadata_file) == metadata_hash
        @test _oos_source_snapshot(source_data) == source_before
    end
end

function test_chronological_oos_fixture_semantics()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        experiment_dir = OpenEMPIRE._prepare_chronological_oos_experiment(
            config_file,
            source_data,
            joinpath(root, "fixture");
            sample_years = [2015],
            input_format = :csv,
            resume = true,
            progress = nothing,
            operational_hours = 24,
            require_full_year = false,
        )
        manifest = YAML.load_file(joinpath(experiment_dir, "experiment.yaml"))
        @test manifest["evaluation_mode"] == "chronological_test_fixture"
        execution_config_file = manifest["source_config_file"]

        staged_data = joinpath(root, "staged")
        cp(source_data, staged_data)
        cp(
            joinpath(experiment_dir, "oos_tree1", "ScenarioData"),
            joinpath(staged_data, "ScenarioData");
            force = true,
        )
        _, periods, sets, _ = OpenEMPIRE._prepare_model_inputs(
            execution_config_file,
            staged_data;
            input_format = :csv,
        )
        @test length(periods) == 48
        for strategic_period in strat_periods(periods)
            representatives = collect(repr_periods(strategic_period))
            @test length(representatives) == 1
            scenarios = collect(opscenarios(first(representatives)))
            @test length(scenarios) == 1
            @test length(first(scenarios)) == 24
            @test all(
                multiple_strat(strategic_period, hour) ≈ 1.0 &&
                probability(hour) ≈ 1.0 && duration(hour) ≈ 1.0 for
                hour in first(scenarios)
            )
            @test sum(
                multiple_strat(strategic_period, hour) *
                probability(hour) * duration(hour) for hour in strategic_period
            ) ≈ 24.0
        end

        weights = OpenEMPIRE._oos_time_weights(YAML.load_file(execution_config_file))
        @test length(weights) == 48
        @test all(weight.conditional ≈ 1.0 for weight in values(weights))
        @test all(weight.probability ≈ 1.0 for weight in values(weights))
        @test all(weight.expected ≈ 1.0 for weight in values(weights))

        model, model_periods, model_sets, _ = OpenEMPIRE.create_model(
            execution_config_file,
            staged_data;
            input_format = :csv,
            include_investment_constraints = false,
            include_string_names = false,
        )
        expected_cycles =
            length(OpenEMPIRE.node_storages(model_sets)) * length(strat_periods(model_periods))
        @test length(collect(eachindex(model[:storage_cyclic]))) == expected_cycles
        @test expected_cycles > 0
        @test sets.Node == model_sets.Node

        investment_model, investment_periods, investment_sets, _ =
            OpenEMPIRE.create_model(
                execution_config_file,
                staged_data;
                optimizer = HiGHS.Optimizer,
                input_format = :csv,
                include_string_names = false,
            )
        JuMP.set_silent(investment_model)
        JuMP.optimize!(investment_model)
        @test JuMP.termination_status(investment_model) == JuMP.MOI.OPTIMAL

        investment_run = joinpath(root, "investment-run")
        OpenEMPIRE.write_investment_csvs(
            joinpath(investment_run, "Output"),
            investment_model,
            investment_sets,
            investment_periods,
        )
        oos_model, oos_periods, oos_sets, _ = OpenEMPIRE.create_model(
            execution_config_file,
            staged_data;
            optimizer = HiGHS.Optimizer,
            input_format = :csv,
            include_investment_constraints = false,
            include_string_names = false,
        )
        OpenEMPIRE.fix_investments_from_results!(
            oos_model,
            oos_sets,
            oos_periods,
            investment_run,
        )
        JuMP.set_silent(oos_model)
        JuMP.optimize!(oos_model)
        @test JuMP.termination_status(oos_model) == JuMP.MOI.OPTIMAL
        @test JuMP.is_solved_and_feasible(oos_model)
        @test all(
            JuMP.is_fixed(oos_model[:genInvCap][node, generator, strategic_period]) for
            (node, generator) in OpenEMPIRE.node_generators(oos_sets),
            strategic_period in strat_periods(oos_periods)
        )
    end
end

function test_chronological_source_validation()
    leap_table = OpenEMPIRE.RawScenarioTable(
        ["A"],
        DateTime[],
        Int[],
        Int[],
        Dict("A" => Float64[]),
    )
    @test_throws ArgumentError OpenEMPIRE._chronological_year_indices(
        leap_table,
        2016,
        8760;
        require_full_year = true,
        source_name = "test.csv",
    )

    timestamps = [DateTime(2015, 1, 1), DateTime(2015, 1, 1, 2)]
    gap_table = OpenEMPIRE.RawScenarioTable(
        ["A"],
        timestamps,
        [2015, 2015],
        [1, 1],
        Dict("A" => [1.0, 2.0]),
    )
    @test_throws ArgumentError OpenEMPIRE._chronological_year_indices(
        gap_table,
        2015,
        2;
        require_full_year = false,
        source_name = "test.csv",
    )
end
