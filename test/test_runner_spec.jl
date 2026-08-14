include(joinpath(@__DIR__, "..", "scripts", "run_julia_empire.jl"))

function _runner_spec_error(f)
    try
        f()
    catch err
        return err
    end
    return nothing
end

function test_resolve_julia_run_spec()
    mktempdir() do root
        source = joinpath(root, "source")
        scenario_dir = joinpath(source, "ScenarioData")
        mkpath(scenario_dir)
        sampling_key = joinpath(scenario_dir, "sampling_key.csv")
        write(
            sampling_key,
            "Period,Scenario,Season,Year,Month,Hour\n1,1,winter,2020,1,4\n",
        )

        config_file = joinpath(root, "run.yaml")
        config =
            YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
        config["use_scenario_generation"] = false
        config["use_fixed_sample"] = false
        YAML.write_file(config_file, config)

        results_root = joinpath(root, "results")
        options = _parse_args([
            source,
            "--config=$config_file",
            "--results=$results_root",
            "--format=csv",
            "--solver=none",
            "--seed=17",
            "--no-optimize",
            "--fixed-sample",
        ])
        spec = _resolve_run_spec(options)

        @test spec isa JuliaRunSpec
        @test spec.dataset == source
        @test spec.original_data_folder == source
        @test spec.original_config_file == config_file
        @test spec.data_folder == joinpath(spec.result_dir, "Input", "csv")
        @test spec.config_file == joinpath(spec.result_dir, "Input", "config.yaml")
        @test spec.input_format == :csv
        @test spec.solver_name == "none"
        @test spec.optimizer === nothing
        @test spec.optimizer_attributes == ()
        @test spec.seed == 17
        @test spec.fixed_sample == "true"
        @test !spec.generate_only
        @test !spec.optimize
        @test !spec.out_of_sample
        @test isempty(spec.fixed_investment_dir)
        @test !spec.perf_enabled
        @test spec.manifest_path == joinpath(spec.result_dir, "run_manifest.yaml")
        @test read(joinpath(spec.data_folder, "ScenarioData", "sampling_key.csv"), String) ==
              read(sampling_key, String)

        staged_config = YAML.load_file(spec.config_file)
        @test staged_config["use_scenario_generation"] == true
        @test staged_config["use_fixed_sample"] == true
        source_config = YAML.load_file(config_file)
        @test source_config["use_scenario_generation"] == false
        @test source_config["use_fixed_sample"] == false

        manifest = _initial_manifest(spec)
        @test manifest["out_of_sample"]["enabled"] == false
        @test manifest["out_of_sample"]["staged_fixed_investment_dir"] === nothing
        @test manifest["input_staging"]["staged_data_folder"] == spec.data_folder

        invalid_options = _parse_args([
            source,
            "--config=$config_file",
            "--results=$(joinpath(root, "invalid-results"))",
            "--out-of-sample=true",
        ])
        err = _runner_spec_error(() -> _resolve_run_spec(invalid_options))
        @test err isa ArgumentError
        @test occursin("--fixed-investment-dir", sprint(showerror, err))

        generate_options = _parse_args([
            source,
            "--config=$config_file",
            "--results=$(joinpath(root, "generate-results"))",
            "--generate-only",
            "--out-of-sample=true",
            "--solver=none",
        ])
        generate_err = _runner_spec_error(
            () -> _resolve_run_spec(generate_options),
        )
        @test generate_err isa ArgumentError
        @test occursin("--generate-only", sprint(showerror, generate_err))
    end

    return nothing
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
        write(
            joinpath(source_scenario_dir, "sloadRaw.csv"),
            "stale generated data\n",
        )

        tree_root = joinpath(root, "oos_tree7")
        tree_scenario_dir = joinpath(tree_root, "ScenarioData")
        mkpath(tree_scenario_dir)
        for filename in _OOS_SCENARIO_FILENAMES
            write(joinpath(tree_scenario_dir, filename), "tree data: $filename\n")
        end
        write(
            joinpath(tree_scenario_dir, "sampling_key.csv"),
            "tree sampling key\n",
        )
        tree_files = Dict{String, Any}(
            filename => Dict(
                "sha256" => _sha256_file(
                    joinpath(tree_scenario_dir, filename),
                ),
            ) for filename in _OOS_TREE_FILENAMES
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
        config =
            YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
        config["use_scenario_generation"] = true
        config["use_fixed_sample"] = true
        YAML.write_file(config_file, config)
        fixed_input = joinpath(fixed_result, "Input")
        mkpath(fixed_input)
        cp(config_file, joinpath(fixed_input, "config.yaml"))
        write(
            joinpath(fixed_result, "summary.txt"),
            "OpenEMPIRE.jl run summary\noptimize=true\ntermination_status=OPTIMAL\n",
        )
        options = _parse_args([
            source,
            "--config=$config_file",
            "--results=$(joinpath(root, "results"))",
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
        @test spec.fixed_investment_dir ==
              joinpath(spec.result_dir, "Input", "fixed_investments")
        @test length(readdir(spec.fixed_investment_dir)) == 10
        @test isfile(
            joinpath(
                spec.fixed_investment_dir,
                "fixed_investment_provenance.yaml",
            ),
        )
        @test isfile(joinpath(spec.fixed_investment_dir, "source_config.yaml"))

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
        @test manifest["out_of_sample"]["fixed_investment_compatibility"]["status"] ==
              "compatible"
        @test manifest["out_of_sample"]["fixed_investment_metadata"]["provenance"]["kind"] ==
              "reconstructed_legacy_run"
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

    return nothing
end

function test_reject_incomplete_oos_runner_options()
    options = _parse_args(["--scenario-data-root=tree"])
    @test_throws ArgumentError _validate_out_of_sample_options(
        options,
        false,
        "auto",
    )

    options = _parse_args(["--out-of-sample=true", "--scenario-data-root=tree"])
    @test_throws ArgumentError _validate_out_of_sample_options(
        options,
        false,
        "auto",
    )

    options = _parse_args([
        "--out-of-sample=true",
        "--fixed-investment-dir=results",
        "--scenario-data-root=tree",
    ])
    @test_throws ArgumentError _validate_out_of_sample_options(
        options,
        true,
        "auto",
    )
    @test_throws ArgumentError _validate_out_of_sample_options(
        options,
        false,
        "true",
    )

    return nothing
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
    @test occursin(
        "result_count=$(infeasible_result.result_count)",
        failure_message,
    )
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
    not_optimized_manifest =
        Dict{String, Any}("timings" => Dict{String, Any}())
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
    @test not_optimized_manifest["solution"]["termination_status"] ==
          "not_optimized"
    @test not_optimized_manifest["solution"]["objective_value"] ==
          "not_optimized"

    return nothing
end
