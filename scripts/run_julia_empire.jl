#!/usr/bin/env julia

using Dates
import Gurobi
using HiGHS
using JuMP
using OpenEMPIRE
using Random
using TimeStruct
using YAML

function _parse_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "HiGHS",
        "seed" => "1",
        "results" => joinpath("results", "julia_runs"),
        "optimize" => "true",
        "fixed-sample" => "auto",
        "out-of-sample" => "false",
        "fixed-investment-dir" => "",
        "gurobi-method" => "",
        "gurobi-crossover" => "",
    )

    for arg in args
        if arg == "--no-optimize"
            options["optimize"] = "false"
        elseif arg == "--fixed-sample"
            options["fixed-sample"] = "true"
        elseif startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            options[key] = value
        elseif !startswith(arg, "--")
            options["dataset"] = arg
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end

    return options
end

function _input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _optimizer(value)
    value == "HiGHS" && return HiGHS.Optimizer
    value == "Gurobi" && return Gurobi.Optimizer
    value == "none" && return nothing
    throw(ArgumentError(
        "Unsupported solver: $value. This runner currently supports HiGHS, Gurobi, or none.",
    ))
end

function _optional_int(value, key)
    (value === nothing || ismissing(value)) && return nothing
    value isa Integer && return Int(value)
    text = strip(string(value))
    isempty(text) && return nothing
    try
        return parse(Int, text)
    catch err
        throw(ArgumentError("Unsupported integer value for $key: $value"))
    end
end

function _set_optimizer_attribute!(attributes, name, value)
    parsed = _optional_int(value, name)
    parsed === nothing && return attributes
    for index in eachindex(attributes)
        if first(attributes[index]) == name
            attributes[index] = name => parsed
            return attributes
        end
    end
    push!(attributes, name => parsed)
    return attributes
end

function _optimizer_attributes(value, config, options)
    if value == "Gurobi"
        attributes = Pair{String, Int}[]
        config_attribute_names = (
            "solver_method" => "Method",
            "solver_crossover" => "Crossover",
            "solver_presolve" => "Presolve",
            "solver_threads" => "Threads",
            "solver_scaleflag" => "ScaleFlag",
            "solver_numericfocus" => "NumericFocus",
            "solver_barhomogeneous" => "BarHomogeneous",
        )
        for (config_key, gurobi_name) in config_attribute_names
            _set_optimizer_attribute!(attributes, gurobi_name, get(config, config_key, nothing))
        end
        _set_optimizer_attribute!(attributes, "Method", options["gurobi-method"])
        _set_optimizer_attribute!(attributes, "Crossover", options["gurobi-crossover"])
        return Tuple(attributes)
    end
    return ()
end

function _optimizer_attribute_summary(attributes)
    isempty(attributes) && return "(none)"
    return join(("$name=$value" for (name, value) in attributes), ", ")
end

function _boolean_option(value, name)
    normalized = lowercase(value)
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported $name value: $value. Expected true or false."))
end

function _config_bool(config, key, default)
    value = get(config, key, default)
    value isa Bool && return value
    return _boolean_option(string(value), key)
end

function _config_with_fixed_sample(config_file, result_dir)
    config = YAML.load_file(config_file)
    config["use_scenario_generation"] = true
    config["use_fixed_sample"] = true

    generated_config = joinpath(result_dir, "fixed_sample_config.yaml")
    YAML.write_file(generated_config, config)
    return generated_config
end

function _write_summary(path, lines)
    mkpath(dirname(path))
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return path
end

function _log_line(message)
    println(message)
    flush(stdout)
    return nothing
end

function _progress_logger()
    run_start = time()
    step = Ref(0)
    return function (message)
        step[] += 1
        elapsed = round(time() - run_start; digits = 1)
        _log_line("[progress $(step[]) | +$(elapsed)s | $(now())] $message")
    end
end

function main(args = ARGS)
    options = _parse_args(args)
    dataset = options["dataset"]
    data_folder = joinpath("data", dataset)
    config_file = options["config"]
    format = _input_format(options["format"])
    solver_name = options["solver"]
    optimizer = _optimizer(solver_name)
    seed = parse(Int, options["seed"])
    optimize_model = lowercase(options["optimize"]) in ("true", "1", "yes")
    fixed_sample_option = lowercase(options["fixed-sample"])

    isdir(data_folder) || throw(ArgumentError("Dataset folder not found: $data_folder"))
    isfile(config_file) || throw(ArgumentError("Config file not found: $config_file"))

    timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    result_dir = joinpath(options["results"], "$(timestamp)_$(dataset)")
    mkpath(result_dir)

    if fixed_sample_option != "auto"
        if _boolean_option(fixed_sample_option, "fixed-sample")
            sampling_key = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
            isfile(sampling_key) ||
                throw(ArgumentError("--fixed-sample requires sampling key: $sampling_key"))
            config_file = _config_with_fixed_sample(config_file, result_dir)
        else
            throw(ArgumentError(
                "--fixed-sample=false is not supported by this runner. Use a config file with use_fixed_sample: False instead.",
            ))
        end
    end
    run_config = YAML.load_file(config_file)
    optimizer_attributes = _optimizer_attributes(solver_name, run_config, options)
    deterministic_tiebreak = _config_bool(run_config, "deterministic_operational_tiebreak", false)

    println("================================================")
    println("OpenEMPIRE.jl run")
    println("================================================")
    println("Dataset:      $dataset")
    println("Data folder:  $data_folder")
    println("Config file:  $config_file")
    println("Input format: $format")
    println("Solver:       $solver_name")
    println("Solver attrs: $(_optimizer_attribute_summary(optimizer_attributes))")
    println("Seed:         $seed")
    println("Fixed sample: $fixed_sample_option")
    println("Optimize:     $optimize_model")
    println("Tie-break:    $deterministic_tiebreak")
    println("Result dir:   $result_dir")
    println("Start time:   $(now())")
    println("================================================")
    flush(stdout)

    progress = _progress_logger()
    progress("Runner initialized")

    build_start = time()
    progress("Starting model build")
    emp, periods, sets, params = OpenEMPIRE.create_model(
        config_file,
        data_folder;
        optimizer,
        optimizer_attributes,
        input_format = format,
        scenario_rng = MersenneTwister(seed),
        progress,
    )
    build_seconds = time() - build_start
    println("Model build seconds: $(round(build_seconds; digits = 2))")
    println("Variables: $(JuMP.num_variables(emp))")
    println("Constraints: $(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))")
    flush(stdout)
    progress("Model build finished in $(round(build_seconds; digits = 2)) seconds")
    scenario_artifact = OpenEMPIRE.write_scenario_artifacts(
        result_dir,
        data_folder,
        run_config;
        config_file = config_file,
        dataset = dataset,
        input_format = format,
        seed = seed,
    )
    if scenario_artifact !== nothing
        println("Scenario sampling key archived to: $scenario_artifact")
        flush(stdout)
    end

    if _boolean_option(options["out-of-sample"], "out-of-sample")
        fixed_investment_dir = options["fixed-investment-dir"]

        isempty(fixed_investment_dir) && throw(ArgumentError(
            "--out-of-sample=true requires --fixed-investment-dir=..."
        ))

        progress("Fixing investments from previous result directory")
        OpenEMPIRE.fix_investments_from_results!(
            emp,
            sets,
            periods,
            fixed_investment_dir;
            fix_installed_capacities = true,
        )
    end

    termination = nothing
    objective = nothing
    objective_components = nothing
    tiebreak_diagnostics = nothing
    solve_seconds = 0.0
    if optimize_model
        solve_start = time()
        progress("Starting solver optimization")
        JuMP.optimize!(emp)
        solve_seconds = time() - solve_start
        progress("Solver optimization finished in $(round(solve_seconds; digits = 2)) seconds")
        termination = JuMP.termination_status(emp)
        objective = JuMP.objective_value(emp)
        progress("Computing objective component diagnostics")
        objective_components = OpenEMPIRE.objective_component_values(
            emp,
            sets,
            params,
            periods,
            Discounter(OpenEMPIRE.discount_rate(params), 1, periods),
        )
        if deterministic_tiebreak && JuMP.is_solved_and_feasible(emp)
            progress("Starting deterministic fixed-investment operational tie-break")
            tiebreak_diagnostics = OpenEMPIRE.deterministic_operational_tiebreak!(
                emp,
                sets,
                params,
                periods,
                Discounter(OpenEMPIRE.discount_rate(params), 1, periods);
                cost_absolute_tolerance = Float64(get(run_config, "deterministic_tiebreak_cost_absolute_tolerance", 1.0)),
                cost_relative_tolerance = Float64(get(run_config, "deterministic_tiebreak_cost_relative_tolerance", 1.0e-10)),
                marginal_weight = Float64(get(run_config, "deterministic_tiebreak_marginal_weight", 1.0)),
                power_scale = Float64(get(run_config, "deterministic_tiebreak_power_scale_mw", 1.0e6)),
                energy_scale = Float64(get(run_config, "deterministic_tiebreak_energy_scale_mwh", 1.0e7)),
                investment_round_digits = Int(get(run_config, "deterministic_tiebreak_investment_round_digits", 6)),
            )
            termination = JuMP.termination_status(emp)
            solve_seconds = time() - solve_start
            progress("Deterministic operational tie-break finished")
        end
        println("Solve seconds: $(round(solve_seconds; digits = 2))")
        println("Termination status: $termination")
        println("Objective value: $objective")
        println("Objective components:")
        for (name, value) in pairs(objective_components)
            println("  $name: $value")
        end
        if tiebreak_diagnostics !== nothing
            println("Deterministic tie-break diagnostics:")
            for (name, value) in pairs(tiebreak_diagnostics)
                println("  $name: $value")
            end
        end
        flush(stdout)
        if JuMP.is_solved_and_feasible(emp)
            progress("Writing solution CSV tables")
            output_dir = OpenEMPIRE.write_solution_tables(result_dir, emp, sets, params, periods)
            println("Solution CSVs written to: $output_dir")
            flush(stdout)
            progress("Solution CSV tables written to $output_dir")
        else
            println("Solution CSVs skipped because the solved model is not feasible.")
            flush(stdout)
        end
    end

    component_lines = if objective_components === nothing
        ["objective_component_$name=not_optimized" for name in (
            :generator_investment,
            :storage_investment,
            :transmission_investment,
            :load_shedding,
            :generator_operation,
        )]
    else
        ["objective_component_$name=$value" for (name, value) in pairs(objective_components)]
    end
    tiebreak_lines = if tiebreak_diagnostics === nothing
        ["deterministic_operational_tiebreak=$deterministic_tiebreak"]
    else
        vcat(
            ["deterministic_operational_tiebreak=true"],
            ["deterministic_tiebreak_$name=$value" for (name, value) in pairs(tiebreak_diagnostics)],
        )
    end

    progress("Writing run summary")
    summary_path = _write_summary(
        joinpath(result_dir, "summary.txt"),
        vcat([
            "OpenEMPIRE.jl run summary",
            "dataset=$dataset",
            "data_folder=$data_folder",
            "config_file=$config_file",
            "input_format=$format",
            "solver=$solver_name",
            "solver_attributes=$(_optimizer_attribute_summary(optimizer_attributes))",
            "seed=$seed",
            "fixed_sample=$fixed_sample_option",
            "out_of_sample=$(options["out-of-sample"])",
            "fixed_investment_dir=$(options["fixed-investment-dir"])",
            "optimize=$optimize_model",
            "variables=$(JuMP.num_variables(emp))",
            "constraints=$(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))",
            "build_seconds=$build_seconds",
            "solve_seconds=$solve_seconds",
            "termination_status=$(termination === nothing ? "not_optimized" : string(termination))",
            "objective_value=$(objective === nothing ? "not_optimized" : string(objective))",
            "end_time=$(now())",
        ], component_lines, tiebreak_lines),
    )
    println("Summary written to: $summary_path")
    println("End time: $(now())")
    flush(stdout)
    progress("Run complete")

    return termination
end

main()
