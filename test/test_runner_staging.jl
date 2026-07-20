include(joinpath(@__DIR__, "..", "scripts", "run_julia_empire.jl"))

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
        write(config_file, "use_scenario_generation: true\nuse_fixed_sample: true\n")
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
        @test spec.scenario_tree_metadata["seed"] == 7
        @test spec.scenario_tree_checksums_verified
        @test spec.scenario_tree_metadata_file ==
              joinpath(spec.result_dir, "Input", "oos_tree_metadata.yaml")
        @test isfile(spec.scenario_tree_metadata_file)
        @test spec.original_scenario_data_root == tree_root
        @test spec.original_fixed_investment_dir == fixed_result
        @test spec.fixed_investment_dir == joinpath(spec.result_dir, "Input", "fixed_investments")
        @test isdir(spec.fixed_investment_dir)
        @test length(readdir(spec.fixed_investment_dir)) == 8

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
