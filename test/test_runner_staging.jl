include(joinpath(@__DIR__, "..", "scripts", "run_julia_empire.jl"))

function test_natural_gas_manifest_input_provenance()
    mktempdir() do root
        for relative in (
            joinpath("NaturalGas", "TerminalCost_stochastic.csv"),
            joinpath("Sets", "NaturalGasNodes.csv"),
            joinpath("Transport", "NaturalGasDemand.csv"),
        )
            path = joinpath(root, relative)
            mkpath(dirname(path))
            write(path, "fixture:$relative\n")
        end
        provenance_path = joinpath(root, "conversion_manifest.json")
        write(provenance_path, "{\"schema_version\":1}\n")
        config = Dict{String, Any}(
            "natural_gas" => true,
            "number_of_scenarios" => 2,
            "number_of_gas_scenarios" => 3,
        )
        info = _natural_gas_input_info(root, config)
        @test info["enabled"]
        @test info["weather_scenarios"] == 2
        @test info["gas_scenarios"] == 3
        @test info["combined_scenarios"] == 6
        @test [file["path"] for file in info["files"]] == [
            joinpath("NaturalGas", "TerminalCost_stochastic.csv"),
            joinpath("Sets", "NaturalGasNodes.csv"),
            joinpath("Transport", "NaturalGasDemand.csv"),
        ]
        @test all(
            length(file["sha256"]) == 64 for file in info["files"]
        )
        @test info["conversion_provenance"]["path"] == provenance_path
        @test length(info["conversion_provenance"]["sha256"]) == 64

        disabled = _natural_gas_input_info(
            joinpath(root, "missing-gas-inputs"),
            Dict{String, Any}(
                "natural_gas" => false,
                "number_of_scenarios" => 2,
                "number_of_gas_scenarios" => 99,
            ),
        )
        @test disabled == Dict{String, Any}(
            "enabled" => false,
            "gas_scenarios" => 1,
            "files" => Any[],
            "conversion_provenance" => nothing,
        )
    end
end

function test_stage_run_inputs_copies_without_mutating_source()
    mktempdir() do root
        source = joinpath(root, "source")
        scenario_dir = joinpath(source, "ScenarioData")
        sets_dir = joinpath(source, "Sets")
        mkpath(scenario_dir)
        mkpath(sets_dir)

        source_key = joinpath(scenario_dir, "sampling_key.csv")
        source_set = joinpath(sets_dir, "Node.csv")
        config_file = joinpath(root, "run.yaml")
        write(source_key, "Period,Scenario,Season,Year,Month,Hour\n1,1,winter,2020,1,4\n")
        write(source_set, "Node\nA\n")
        write(config_file, "use_scenario_generation: true\n")

        result_dir = joinpath(root, "result")
        staged_data, staged_config, staged_fixed_investments, staged_scenario_metadata =
            _stage_run_inputs(result_dir, source, config_file)

        @test staged_data == joinpath(result_dir, "Input", "csv")
        @test staged_config == joinpath(result_dir, "Input", "config.yaml")
        @test isempty(staged_fixed_investments)
        @test isempty(staged_scenario_metadata)
        @test read(joinpath(staged_data, "ScenarioData", "sampling_key.csv"), String) == read(source_key, String)
        @test read(staged_config, String) == read(config_file, String)

        write(joinpath(staged_data, "ScenarioData", "sampling_key.csv"), "changed\n")
        write(joinpath(staged_data, "ScenarioData", "sloadRaw.csv"), "generated\n")
        write(staged_config, "use_scenario_generation: false\n")

        @test read(source_key, String) == "Period,Scenario,Season,Year,Month,Hour\n1,1,winter,2020,1,4\n"
        @test !isfile(joinpath(source, "ScenarioData", "sloadRaw.csv"))
        @test read(config_file, String) == "use_scenario_generation: true\n"
    end
end

function _write_runner_fixed_investment_files(output_dir)
    mkpath(output_dir)
    for filename in (
        "genInvCap.csv",
        "transmisionInvCap.csv",
        "storPWInvCap.csv",
        "storENInvCap.csv",
        "genInstalledCap.csv",
        "transmissionInstalledCap.csv",
        "storPWInstalledCap.csv",
        "storENInstalledCap.csv",
    )
        write(joinpath(output_dir, filename), "$filename\n")
    end
    return output_dir
end

function test_resolve_single_tree_oos_run_spec()
    mktempdir() do root
        source = joinpath(root, "source")
        source_scenario_dir = joinpath(source, "ScenarioData")
        mkpath(source_scenario_dir)
        write(joinpath(source_scenario_dir, "electricload.csv"), "source raw data\n")
        write(joinpath(source_scenario_dir, "sloadRaw.csv"), "stale generated data\n")

        tree_root = joinpath(root, "oos_tree7")
        tree_scenario_dir = joinpath(tree_root, "ScenarioData")
        mkpath(tree_scenario_dir)
        for filename in _OOS_SCENARIO_FILENAMES
            write(joinpath(tree_scenario_dir, filename), "tree data: $filename\n")
        end
        write(joinpath(tree_scenario_dir, "sampling_key.csv"), "tree sampling key\n")
        tree_files = Dict{String, Any}(
            filename => Dict("sha256" => _sha256_file(joinpath(tree_scenario_dir, filename)))
            for filename in OpenEMPIRE._OOS_TREE_FILENAMES
        )
        YAML.write_file(
            joinpath(tree_root, "metadata.yaml"),
            Dict(
                "tree" => "oos_tree7",
                "seed" => 7,
                "files" => tree_files,
            ),
        )

        fixed_result = joinpath(root, "investment_run")
        _write_runner_fixed_investment_files(joinpath(fixed_result, "output"))

        config_file = joinpath(root, "run.yaml")
        config = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
        config["use_scenario_generation"] = true
        config["use_fixed_sample"] = true
        YAML.write_file(config_file, config)
        input_dir = joinpath(fixed_result, "Input")
        mkpath(input_dir)
        cp(config_file, joinpath(input_dir, "config.yaml"))
        write(
            joinpath(fixed_result, "summary.txt"),
            "OpenEMPIRE.jl run summary\noptimize=true\ntermination_status=OPTIMAL\n",
        )
        results_root = joinpath(root, "results")
        options = _parse_args([
            source,
            "--config=$config_file",
            "--results=$results_root",
            "--solver=none",
            "--no-optimize",
            "--out-of-sample=true",
            "--fixed-investment-dir=$fixed_result",
            "--scenario-data-root=$tree_root",
        ])

        spec = _resolve_run_spec(options)

        @test spec.out_of_sample
        @test spec.scenario_tree == "oos_tree7"
        @test _scenario_tree_identity(
            "/remote/stage/oos_tree1",
            Dict("tree" => "oos_tree1", "staged_from_tree" => "oos_tree7"),
        ) == "oos_tree7"
        @test spec.scenario_tree_metadata["seed"] == 7
        @test spec.scenario_tree_checksums_verified
        @test spec.scenario_tree_metadata_file ==
              joinpath(spec.result_dir, "Input", "oos_tree_metadata.yaml")
        @test isfile(spec.scenario_tree_metadata_file)
        @test spec.original_scenario_data_root == tree_root
        @test spec.original_fixed_investment_dir == fixed_result
        @test spec.fixed_investment_dir == joinpath(spec.result_dir, "Input", "fixed_investments")
        @test isdir(spec.fixed_investment_dir)
        @test length(readdir(spec.fixed_investment_dir)) == 10
        @test isfile(joinpath(spec.fixed_investment_dir, "fixed_investment_provenance.yaml"))
        @test isfile(joinpath(spec.fixed_investment_dir, "source_config.yaml"))
        manifest = _initial_manifest(spec)
        @test manifest["out_of_sample"]["fixed_investment_compatibility"]["status"] ==
              "compatible"
        @test manifest["out_of_sample"]["fixed_investment_metadata"]["provenance"]["kind"] ==
              "reconstructed_legacy_run"

        staged_scenario_dir = joinpath(spec.data_folder, "ScenarioData")
        for filename in _OOS_SCENARIO_FILENAMES
            @test read(joinpath(staged_scenario_dir, filename), String) ==
                  "tree data: $filename\n"
        end
        @test read(joinpath(staged_scenario_dir, "sampling_key.csv"), String) ==
              "tree sampling key\n"
        @test !isfile(joinpath(staged_scenario_dir, "electricload.csv"))

        staged_config = YAML.load_file(spec.config_file)
        @test staged_config["use_scenario_generation"] == false
        @test staged_config["use_fixed_sample"] == false

        @test read(joinpath(source_scenario_dir, "sloadRaw.csv"), String) ==
              "stale generated data\n"
        @test YAML.load_file(config_file)["use_scenario_generation"] == true

        manifest = _initial_manifest(spec)
        @test manifest["out_of_sample"]["enabled"] == true
        @test manifest["out_of_sample"]["scenario_tree"] == "oos_tree7"
        @test manifest["out_of_sample"]["scenario_seed"] == 7
        @test manifest["out_of_sample"]["scenario_checksums_verified"] == true
        @test manifest["out_of_sample"]["scenario_metadata"]["tree"] == "oos_tree7"
        @test manifest["out_of_sample"]["base_investment_run"] == fixed_result
        @test manifest["out_of_sample"]["investments_fixed"] == false
        @test manifest["input_staging"]["scenario_data_source"] == tree_root
        @test manifest["sampling_key"]["sha256"] == _sha256_file(
            joinpath(staged_scenario_dir, "sampling_key.csv"),
        )

        tree_files["sloadRaw.csv"]["sha256"] = "incorrect"
        YAML.write_file(
            joinpath(tree_root, "metadata.yaml"),
            Dict("seed" => 7, "files" => tree_files),
        )
        @test_throws ArgumentError _scenario_tree_metadata(tree_root)
    end
end

function test_reject_incomplete_oos_runner_options()
    options = _parse_args(["--scenario-data-root=tree"])
    @test_throws ArgumentError _validate_out_of_sample_options(options, false, "auto")

    options = _parse_args(["--out-of-sample=true", "--scenario-data-root=tree"])
    @test_throws ArgumentError _validate_out_of_sample_options(options, false, "auto")

    options = _parse_args([
        "--out-of-sample=true",
        "--fixed-investment-dir=results",
        "--scenario-data-root=tree",
    ])
    @test_throws ArgumentError _validate_out_of_sample_options(options, true, "auto")
    @test_throws ArgumentError _validate_out_of_sample_options(options, false, "true")
end

function test_reject_mismatched_oos_tree_config()
    mktempdir() do root
        tree_dir = joinpath(root, "full-year-tree")
        mkpath(tree_dir)
        config = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
        full_year_config = OpenEMPIRE._internalempire_full_year_config(config)
        metadata_config = Dict{String, Any}(
            key => full_year_config[key] for key in OpenEMPIRE._OOS_TREE_CONFIG_KEYS
            if haskey(full_year_config, key)
        )
        YAML.write_file(
            joinpath(tree_dir, "metadata.yaml"),
            Dict{String, Any}(
                "evaluation_mode" => "chronological_full_year",
                "config" => metadata_config,
                "chronology" => Dict{String, Any}(
                    "formulation" => "internalempire_24x365",
                    "tree_index" => 1,
                    "tree_count" => 24,
                    "source_hour_start" => 1,
                    "source_hour_end" => 365,
                    "source_hours" => 365,
                    "model_operational_hours" => 366,
                    "representative_periods" => 2,
                    "operational_scenarios" => 1,
                    "winter_hour_multiplicity" => 8759 / 365,
                    "dummy_peak" => true,
                    "dummy_peak_hours" => 1,
                    "dummy_peak_results_ignored" => true,
                    "storage_cycle_boundaries_per_strategic_period" => 2,
                ),
            ),
        )
        matching_config_file = joinpath(root, "matching.yaml")
        YAML.write_file(matching_config_file, full_year_config)
        @test _validate_oos_tree_execution_config(matching_config_file, tree_dir) === nothing

        mismatched_config = deepcopy(full_year_config)
        mismatched_config["length_of_regular_season"] = 8760
        mismatched_config_file = joinpath(root, "mismatched.yaml")
        YAML.write_file(mismatched_config_file, mismatched_config)
        @test_throws ArgumentError _validate_oos_tree_execution_config(
            mismatched_config_file,
            tree_dir,
        )

        single_chronology_config = OpenEMPIRE._chronological_oos_config(config, 8760)
        single_chronology_tree = joinpath(root, "single-chronology-tree")
        mkpath(single_chronology_tree)
        YAML.write_file(
            joinpath(single_chronology_tree, "metadata.yaml"),
            Dict{String, Any}(
                "evaluation_mode" => "chronological_full_year",
                "config" => Dict{String, Any}(
                    key => single_chronology_config[key] for
                    key in OpenEMPIRE._OOS_TREE_CONFIG_KEYS if
                    haskey(single_chronology_config, key)
                ),
                "chronology" => Dict{String, Any}(
                    "formulation" => "single_chronology",
                    "operational_hours" => 8760,
                    "representative_periods" => 1,
                    "operational_scenarios" => 1,
                    "expected_hour_multiplicity" => 1,
                    "dummy_peak" => false,
                    "storage_cycle_boundaries_per_strategic_period" => 1,
                ),
            ),
        )
        single_chronology_config_file = joinpath(root, "single-chronology.yaml")
        YAML.write_file(single_chronology_config_file, single_chronology_config)
        @test _validate_oos_tree_execution_config(
            single_chronology_config_file,
            single_chronology_tree,
        ) === nothing

        legacy_tree = joinpath(root, "legacy-tree")
        mkpath(legacy_tree)
        YAML.write_file(joinpath(legacy_tree, "metadata.yaml"), Dict("seed" => 1))
        @test _validate_oos_tree_execution_config(matching_config_file, legacy_tree) === nothing
    end
end

function test_runner_solver_result_extraction()
    infeasible = Model(HiGHS.Optimizer)
    set_silent(infeasible)
    @variable(infeasible, x)
    @constraint(infeasible, x >= 1)
    @constraint(infeasible, x <= 0)
    @objective(infeasible, Min, x)
    optimize!(infeasible)

    components_called = Ref(false)
    infeasible_result = _extract_solver_result(infeasible) do
        components_called[] = true
        (test_component = 1.0,)
    end
    @test string(infeasible_result.termination) == "INFEASIBLE"
    @test string(infeasible_result.primal_status) == "NO_SOLUTION"
    @test infeasible_result.result_count >= 0
    @test !infeasible_result.has_values
    @test !infeasible_result.solved_and_feasible
    @test infeasible_result.objective === nothing
    @test infeasible_result.objective_components === nothing
    @test !components_called[]

    failure_message = _solver_failure_message(infeasible_result)
    @test occursin("termination=INFEASIBLE", failure_message)
    @test occursin("result_count=$(infeasible_result.result_count)", failure_message)
    manifest = Dict{String, Any}("timings" => Dict{String, Any}())
    succeeded, recorded_error = _finalize_run_manifest!(
        manifest,
        merge(infeasible_result, (; solve_seconds = 0.1)),
        true;
        summary_path = "/tmp/summary.txt",
        scenario_artifact = nothing,
        perf_enabled = false,
        wall_seconds = 1.23456,
        end_time = DateTime(2026, 7, 21, 13),
    )
    @test !succeeded
    @test recorded_error == failure_message
    @test manifest["status"] == "failed"
    @test manifest["error"] == failure_message
    @test manifest["end_time"] == "2026-07-21T13:00:00"
    @test manifest["timings"]["wall_seconds"] == 1.235
    @test manifest["solution"] == Dict{String, Any}(
        "termination_status" => "INFEASIBLE",
        "primal_status" => "NO_SOLUTION",
        "dual_status" => string(infeasible_result.dual_status),
        "result_count" => infeasible_result.result_count,
        "has_values" => false,
        "is_solved_and_feasible" => false,
        "objective_value" => nothing,
        "objective_components" => nothing,
    )
    mktempdir() do root
        manifest_file = joinpath(root, "run_manifest.yaml")
        _write_run_manifest(manifest_file, manifest)
        loaded = YAML.load_file(manifest_file)
        @test loaded["status"] == "failed"
        @test loaded["solution"]["termination_status"] == "INFEASIBLE"
        @test loaded["solution"]["objective_value"] === nothing
    end

    optimal = Model(HiGHS.Optimizer)
    set_silent(optimal)
    @variable(optimal, y >= 1)
    @objective(optimal, Min, y)
    optimize!(optimal)
    components_called[] = false
    optimal_result = _extract_solver_result(optimal) do
        components_called[] = true
        (test_component = value(y),)
    end
    @test string(optimal_result.termination) == "OPTIMAL"
    @test optimal_result.result_count == 1
    @test optimal_result.has_values
    @test optimal_result.solved_and_feasible
    @test optimal_result.objective ≈ 1.0
    @test optimal_result.objective_components.test_component ≈ 1.0
    @test components_called[]
    @test _solver_run_state(optimal_result, true) == (true, nothing)

    not_optimized = (
        termination = nothing,
        primal_status = nothing,
        dual_status = nothing,
        result_count = 0,
        has_values = false,
        solved_and_feasible = false,
        objective = nothing,
        objective_components = nothing,
        solve_seconds = 0.0,
    )
    not_optimized_manifest = Dict{String, Any}("timings" => Dict{String, Any}())
    succeeded, recorded_error = _finalize_run_manifest!(
        not_optimized_manifest,
        not_optimized,
        false;
        summary_path = "/tmp/summary.txt",
        scenario_artifact = nothing,
        perf_enabled = false,
        wall_seconds = 0.1,
    )
    @test succeeded
    @test recorded_error === nothing
    @test not_optimized_manifest["status"] == "complete"
    @test not_optimized_manifest["solution"]["termination_status"] == "not_optimized"
    @test not_optimized_manifest["solution"]["objective_value"] == "not_optimized"
end
