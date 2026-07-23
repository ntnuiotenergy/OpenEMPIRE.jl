function test_internalempire_full_year_foundation()
    chunks = OpenEMPIRE._internalempire_full_year_chunks()
    @test length(chunks) == 24
    @test first(chunks) == 1:365
    @test chunks[2] == 366:730
    @test last(chunks) == 8396:8760
    @test [first(chunk) - 1 for chunk in chunks] == collect(0:365:8395)
    @test reduce(vcat, chunks) == collect(1:8760)
    @test all(length(chunk) == 365 for chunk in chunks)

    source_config = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
    config = OpenEMPIRE._internalempire_full_year_config(source_config)
    @test config["number_of_scenarios"] == 1
    @test config["regular_seasons"] == ["winter"]
    @test config["length_of_regular_season"] == 365
    @test config["n_peak_seasons"] == 1
    @test config["len_peak_season"] == 1
    @test config["operational_hours_per_year"] == 8760
    @test config["use_scenario_generation"] == false
    @test config["use_fixed_sample"] == false

    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 365, 1, 1, 1)
    strategic_period = only(collect(strat_periods(periods)))
    representatives = collect(repr_periods(strategic_period))
    @test length(representatives) == 2
    winter = only(collect(opscenarios(representatives[1])))
    dummy_peak = only(collect(opscenarios(representatives[2])))
    @test length(winter) == 365
    @test length(dummy_peak) == 1
    @test all(
        multiple_strat(strategic_period, hour) ≈ (8760 - 1) / 365 for hour in winter
    )
    @test multiple_strat(strategic_period, only(dummy_peak)) ≈ 1.0
    @test all(probability(hour) ≈ 1.0 for hour in strategic_period)
    @test sum(
        multiple_strat(strategic_period, hour) * probability(hour) * duration(hour) for
        hour in strategic_period
    ) ≈ 8760.0
end

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
        @test manifest["full_year_formulation"] == "internalempire_24x365"
        @test manifest["full_year_sample_year"] == 2015
        @test manifest["sample_years"] == fill(2015, 24)
        @test manifest["operational_hours_per_year"] == 8760
        @test manifest["chunk_hours"] == 365
        @test manifest["dummy_peak_hours_per_tree"] == 1
        @test manifest["num_trees"] == 24
        @test manifest["trees"][1]["sample_year"] == 2015
        @test manifest["trees"][1]["source_hour_start"] == 1
        @test manifest["trees"][1]["source_hour_end"] == 365
        @test manifest["trees"][24]["source_hour_start"] == 8396
        @test manifest["trees"][24]["source_hour_end"] == 8760
        @test all(tree["status"] == "complete" for tree in manifest["trees"])

        execution_config_file = manifest["source_config_file"]
        execution_config = YAML.load_file(execution_config_file)
        @test execution_config["number_of_scenarios"] == 1
        @test execution_config["regular_seasons"] == ["winter"]
        @test execution_config["length_of_regular_season"] == 365
        @test execution_config["operational_hours_per_year"] == 8760
        @test execution_config["n_peak_seasons"] == 1
        @test execution_config["len_peak_season"] == 1
        @test execution_config["use_scenario_generation"] == false
        @test execution_config["use_fixed_sample"] == false

        tree_dir = joinpath(prepared, "oos_tree1")
        metadata_file = joinpath(tree_dir, "metadata.yaml")
        metadata = YAML.load_file(metadata_file)
        @test metadata["schema_version"] == 2
        @test metadata["evaluation_mode"] == "chronological_full_year"
        @test metadata["sample_year"] == 2015
        @test metadata["chronology"]["formulation"] == "internalempire_24x365"
        @test metadata["chronology"]["tree_index"] == 1
        @test metadata["chronology"]["source_hour_start"] == 1
        @test metadata["chronology"]["source_hour_end"] == 365
        @test metadata["chronology"]["source_hours"] == 365
        @test metadata["chronology"]["model_operational_hours"] == 366
        @test metadata["chronology"]["representative_periods"] == 2
        @test metadata["chronology"]["winter_hour_multiplicity"] ≈ 8759 / 365
        @test metadata["chronology"]["dummy_peak"] == true
        @test metadata["chronology"]["dummy_peak_results_ignored"] == true
        @test metadata["chronology"]["storage_cycle_boundaries_per_strategic_period"] == 2
        @test metadata["source_config_sha256"] ==
              OpenEMPIRE._oos_sha256_file(execution_config_file)
        @test metadata["generation_source_config_sha256"] ==
              OpenEMPIRE._oos_sha256_file(config_file)
        @test all(
            source["selected_rows"] == 365 && source["source_year_rows"] == 8760 for
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
        @test germany_period1 == collect(1:366)
        @test Set(String(row.Scenario) for row in load_rows) == Set(["scenario1"])
        availability_rows = CSV.File(
            joinpath(tree_dir, "ScenarioData", "genCapAvailStochRaw.csv");
            normalizenames = false,
        )
        generated_ror = [
            Float64(row.GeneratorStochasticAvailabilityRaw) for row in availability_rows if
            String(row.Node) == "Germany" &&
            String(row.IntermitentGenerators) == "Hydrorun-of-the-river" &&
            Int(row.Period) == 1 && Int(row.Operationalhour) <= 365
        ]
        dummy_ror = only([
            Float64(row.GeneratorStochasticAvailabilityRaw) for row in availability_rows if
            String(row.Node) == "Germany" &&
            String(row.IntermitentGenerators) == "Hydrorun-of-the-river" &&
            Int(row.Period) == 1 && Int(row.Operationalhour) == 366
        ])
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
        @test generated_ror ==
              OpenEMPIRE._normalized_scenario_value.(raw_ror.values["DE"][ror_indices[1:365]])
        @test dummy_ror == 0.0
        @test ror_indices == OpenEMPIRE._year_indices(raw_ror, 2015)
        @test !issorted(raw_ror.timestamps[ror_indices])
        @test Set(raw_ror.timestamps[ror_indices]) == Set(
            DateTime(2015, 1, 1) + Hour(offset) for offset in 0:8759
        )
        @test metadata["raw_sources"]["hydroror.csv"]["selection_semantics"] ==
              "internalempire_filtered_source_row_order"
        @test !metadata["raw_sources"]["hydroror.csv"]["timestamps_ordered"]
        @test metadata["raw_sources"]["hydroror.csv"]["non_hourly_row_steps"] > 0
        @test metadata["raw_sources"]["electricload.csv"]["timestamps_ordered"]

        last_tree_dir = joinpath(prepared, "oos_tree24")
        last_metadata = YAML.load_file(joinpath(last_tree_dir, "metadata.yaml"))
        @test last_metadata["chronology"]["tree_index"] == 24
        @test last_metadata["chronology"]["source_hour_start"] == 8396
        @test last_metadata["chronology"]["source_hour_end"] == 8760
        last_availability = CSV.File(
            joinpath(last_tree_dir, "ScenarioData", "genCapAvailStochRaw.csv");
            normalizenames = false,
        )
        last_generated_ror = [
            Float64(row.GeneratorStochasticAvailabilityRaw) for row in last_availability if
            String(row.Node) == "Germany" &&
            String(row.IntermitentGenerators) == "Hydrorun-of-the-river" &&
            Int(row.Period) == 1 && Int(row.Operationalhour) <= 365
        ]
        @test last_generated_ror == OpenEMPIRE._normalized_scenario_value.(
            raw_ror.values["DE"][ror_indices[8396:8760]],
        )
        sampling_key = collect(CSV.File(
            joinpath(last_tree_dir, "ScenarioData", "sampling_key.csv");
            normalizenames = false,
        ))
        @test all(String(row.Season) == "winter" for row in sampling_key)
        @test all(Int(row.Hour) == 8395 for row in sampling_key)

        staged_data = joinpath(root, "staged-tree1")
        cp(source_data, staged_data)
        cp(
            joinpath(tree_dir, "ScenarioData"),
            joinpath(staged_data, "ScenarioData");
            force = true,
        )
        _, periods, model_sets, loaded_params = OpenEMPIRE._prepare_model_inputs(
            execution_config_file,
            staged_data;
            input_format = :csv,
        )
        @test length(periods) == 2 * 366
        winter_load_by_period = Vector{Vector{Float64}}()
        winter_hydro_by_period = Vector{Vector{Float64}}()
        winter_availability_by_period = Vector{Vector{Float64}}()
        for strategic_period in strat_periods(periods)
            representatives = collect(repr_periods(strategic_period))
            @test length(representatives) == 2
            winter = only(collect(opscenarios(representatives[1])))
            dummy_peak = only(collect(opscenarios(representatives[2])))
            @test length(winter) == 365
            @test length(dummy_peak) == 1
            @test all(
                multiple_strat(strategic_period, hour) ≈ 8759 / 365 for hour in winter
            )
            dummy_hour = only(dummy_peak)
            @test multiple_strat(strategic_period, dummy_hour) ≈ 1.0
            @test loaded_params.sloadRaw["Germany"][dummy_hour] == 0.0
            @test loaded_params.maxRegHydroGenRaw["Germany"][dummy_hour] == 1.0
            @test loaded_params.genCapAvail[
                ("Germany", "Hydrorun-of-the-river")
            ][dummy_hour] == 0.0
            push!(
                winter_load_by_period,
                [loaded_params.sloadRaw["Germany"][hour] for hour in winter],
            )
            push!(
                winter_hydro_by_period,
                [loaded_params.maxRegHydroGenRaw["Germany"][hour] for hour in winter],
            )
            push!(
                winter_availability_by_period,
                [
                    loaded_params.genCapAvail[
                        ("Germany", "Hydrorun-of-the-river")
                    ][hour] for hour in winter
                ],
            )
        end
        @test all(profile == first(winter_load_by_period) for profile in winter_load_by_period)
        @test all(profile == first(winter_hydro_by_period) for profile in winter_hydro_by_period)
        @test all(
            profile == first(winter_availability_by_period) for
            profile in winter_availability_by_period
        )
        model, model_periods, _, model_params = OpenEMPIRE.create_model(
            execution_config_file,
            staged_data;
            input_format = :csv,
            include_investment_constraints = false,
            include_string_names = false,
        )
        expected_storage_cycles =
            length(OpenEMPIRE.node_storages(model_sets)) *
            length(strat_periods(model_periods)) * 2
        @test length(collect(eachindex(model[:storage_cyclic]))) == expected_storage_cycles
        for strategic_period in strat_periods(model_periods)
            dummy_peak = only(collect(opscenarios(collect(repr_periods(strategic_period))[2])))
            dummy_hour = only(dummy_peak)
            @test model_params.maxRegHydroGen["Germany"][dummy_hour] == 1.0
        end

        investment_data = joinpath(root, "investment-data")
        cp(source_data, investment_data)
        investment_model, investment_periods, investment_sets, _ = OpenEMPIRE.create_model(
            config_file,
            investment_data;
            optimizer = HiGHS.Optimizer,
            input_format = :csv,
            include_string_names = false,
            scenario_rng = Xoshiro(1),
        )
        JuMP.set_silent(investment_model)
        JuMP.optimize!(investment_model)
        @test JuMP.termination_status(investment_model) == JuMP.MOI.OPTIMAL
        investment_run = joinpath(root, "full-year-investment-run")
        OpenEMPIRE.write_investment_csvs(
            joinpath(investment_run, "Output"),
            investment_model,
            investment_sets,
            investment_periods,
        )
        _write_test_investment_run_evidence(investment_run, config_file)

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

        runner_results = joinpath(root, "runner-results")
        runner_status = main([
            source_data,
            "--config=$execution_config_file",
            "--solver=HiGHS",
            "--seed=1",
            "--out-of-sample=true",
            "--fixed-investment-dir=$investment_run",
            "--scenario-data-root=$tree_dir",
            "--results=$runner_results",
        ])
        @test runner_status == JuMP.MOI.OPTIMAL
        runner_result = only(readdir(runner_results; join = true))
        runner_manifest = YAML.load_file(joinpath(runner_result, "run_manifest.yaml"))
        @test runner_manifest["status"] == "complete"
        @test runner_manifest["out_of_sample"]["enabled"]
        @test runner_manifest["out_of_sample"]["scenario_tree"] == "oos_tree1"
        @test runner_manifest["out_of_sample"]["scenario_checksums_verified"]
        @test runner_manifest["out_of_sample"]["investments_fixed"]
        @test runner_manifest["out_of_sample"]["scenario_metadata"]["chronology"]["formulation"] ==
              "internalempire_24x365"
        @test !runner_manifest["model"]["investment_constraints_included"]
        @test runner_manifest["solution"]["termination_status"] == "OPTIMAL"
        @test runner_manifest["solution"]["is_solved_and_feasible"]
        components = runner_manifest["solution"]["objective_components"]
        @test sum(values(components)) ≈ runner_manifest["solution"]["objective_value"]
        @test runner_manifest["investment_result"]["fixed_investments_sha256"] ==
              runner_manifest["out_of_sample"]["fixed_investment_metadata"]["sha256"]

        validated = OpenEMPIRE.summarize_oos_result(runner_result)
        @test validated.summary.EvaluationMode == "chronological_full_year"
        @test validated.summary.FullYearFormulation == "internalempire_24x365"
        @test validated.summary.FullYearTreeIndex == 1
        @test validated.summary.DummyPeakResultsIgnored
        @test validated.summary.FixedInvestmentsVerified
        @test validated.summary.TerminationStatus == "OPTIMAL"
        @test all(
            row.Season == "winter" for row in validated.ens_by_period_scenario_season
        )
        load_shed_rows = collect(CSV.File(
            joinpath(runner_result, "output", "loadShed.csv");
            normalizenames = false,
        ))
        @test Set(String(row.Season) for row in load_shed_rows) ==
              Set(["winter", "peak1"])
        @test count(row -> String(row.Season) == "winter", load_shed_rows) == 2 * 3 * 365
        @test count(row -> String(row.Season) == "peak1", load_shed_rows) == 2 * 3

        queue_investment_run = joinpath(root, "investment-run")
        _write_investment_csvs(joinpath(queue_investment_run, "Output"))
        _write_test_investment_run_evidence(queue_investment_run, config_file)
        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            prepared,
            queue_investment_run;
            dataset = source_data,
            config_file = execution_config_file,
            results_root = joinpath(root, "results"),
            input_format = :csv,
            solver = "HiGHS",
        )
        queue = YAML.load_file(queue_file)
        @test queue["experiment"]["evaluation_mode"] == "chronological_full_year"
        @test queue["experiment"]["sample_years"] == fill(2015, 24)
        @test length(queue["jobs"]) == 24
        @test [job["tree"] for job in queue["jobs"]] ==
              ["oos_tree$index" for index in 1:24]
        @test queue["jobs"][1]["evaluation_mode"] == "chronological_full_year"
        @test queue["jobs"][1]["sample_year"] == 2015
        @test queue["jobs"][24]["tree"] == "oos_tree24"
        @test "--config=$execution_config_file" in queue["jobs"][1]["command"]
        mismatched_config_file = joinpath(root, "mismatched-full-year.yaml")
        mismatched_config = deepcopy(execution_config)
        mismatched_config["length_of_regular_season"] = 8760
        YAML.write_file(mismatched_config_file, mismatched_config)
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_execution_queue(
            prepared,
            queue_investment_run;
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
