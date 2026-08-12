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
    attributes = _optimizer_attributes(
        "Gurobi",
        Dict(
            "solver_method" => 2,
            "solver_barconvtol" => 1.0e-8,
            "solver_feasibilitytol" => "1e-9",
        ),
        Dict("gurobi-method" => "", "gurobi-crossover" => ""),
    )
    @test attributes == (
        "Method" => 2,
        "BarConvTol" => 1.0e-8,
        "FeasibilityTol" => 1.0e-9,
    )
    @test_throws ArgumentError _optimizer_attributes(
        "Gurobi",
        Dict("solver_barconvtol" => "not-a-number"),
        Dict("gurobi-method" => "", "gurobi-crossover" => ""),
    )

    full_hydrogen_config = YAML.load_file(
        joinpath(@__DIR__, "..", "config", "run_int_full_hydrogen.yaml"),
    )
    @test full_hydrogen_config["forecast_horizon_year"] == 2055
    @test full_hydrogen_config["number_of_scenarios"] == 5
    @test full_hydrogen_config["length_of_regular_season"] == 168
    @test full_hydrogen_config["natural_gas"] === true
    @test full_hydrogen_config["hydrogen"] === true
    full_hydrogen_attributes = _optimizer_attributes(
        "Gurobi",
        full_hydrogen_config,
        Dict("gurobi-method" => "", "gurobi-crossover" => ""),
    )
    @test full_hydrogen_attributes == (
        "Method" => 2,
        "Crossover" => 0,
        "Presolve" => 1,
        "NumericFocus" => 1,
        "BarHomogeneous" => 1,
        "BarConvTol" => 1.0e-8,
        "FeasibilityTol" => 1.0e-9,
    )

    full_industry_config = YAML.load_file(
        joinpath(@__DIR__, "..", "config", "run_int_full_industry.yaml"),
    )
    full_industry_attributes = _optimizer_attributes(
        "Gurobi",
        full_industry_config,
        Dict("gurobi-method" => "", "gurobi-crossover" => ""),
    )
    @test ("Seed" => 2) in full_industry_attributes

    mktempdir() do root
        model = Model(HiGHS.Optimizer)
        set_silent(model)
        @variable(model, quoted_name[1:2] >= 0)
        @constraint(model, quoted_name[1] + quoted_name[2] >= 3)
        @objective(model, Min, quoted_name[1] + 2 * quoted_name[2])
        optimize!(model)
        raw_solution_path = _write_raw_solution(model, joinpath(root, "raw_solution.csv"))
        raw_solution = read(raw_solution_path, String)
        @test startswith(raw_solution, "variable,value\n")
        @test occursin("\"quoted_name[1]\",", raw_solution)
        @test occursin("\"quoted_name[2]\",", raw_solution)
    end

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
