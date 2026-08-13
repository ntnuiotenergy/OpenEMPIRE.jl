include(joinpath(@__DIR__, "..", "scripts", "run_julia_empire.jl"))

function _runner_spec_error(f)
    try
        f()
    catch err
        return err
    end
    return nothing
end

function test_gurobi_numeric_attribute_parsing()
    config = Dict{String, Any}(
        "solver_method" => 2,
        "solver_crossover" => 1,
        "solver_presolve" => 2,
        "solver_feasibilitytol" => 1e-8,
        "solver_barconvtol" => "1e-7",
    )
    options = _parse_args([
        "--gurobi-crossover=0",
        "--gurobi-presolve=1",
        "--gurobi-feasibility-tol=1e-9",
        "--gurobi-bar-conv-tol=1e-8",
    ])

    @test _optimizer_attributes("Gurobi", config, options) == (
        "Method" => 2,
        "Crossover" => 0,
        "Presolve" => 1,
        "FeasibilityTol" => 1e-9,
        "BarConvTol" => 1e-8,
    )
    @test_throws ArgumentError _optional_float("not-a-number", "FeasibilityTol")
    @test_throws ArgumentError _parse_args(["--gurobi-preslove=1"])
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
        write(
            config_file,
            "use_scenario_generation: false\nuse_fixed_sample: false\n",
        )

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
        @test manifest["out_of_sample"] == false
        @test manifest["fixed_investment_dir"] == ""
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
        generate_spec = _resolve_run_spec(generate_options)
        @test generate_spec.generate_only
        @test generate_spec.out_of_sample
        @test isempty(generate_spec.fixed_investment_dir)
    end

    return nothing
end
