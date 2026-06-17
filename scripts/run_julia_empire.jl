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
        "config" => joinpath("data", "test_excel", "testrun.yaml"),
        "format" => "csv",
        "solver" => "HiGHS",
        "seed" => "1",
        "results" => joinpath("results", "julia_runs"),
        "optimize" => "true",
        "fixed-sample" => "auto",
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

function _boolean_option(value, name)
    normalized = lowercase(value)
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported $name value: $value. Expected true or false."))
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

    println("================================================")
    println("OpenEMPIRE.jl run")
    println("================================================")
    println("Dataset:      $dataset")
    println("Data folder:  $data_folder")
    println("Config file:  $config_file")
    println("Input format: $format")
    println("Solver:       $solver_name")
    println("Seed:         $seed")
    println("Fixed sample: $fixed_sample_option")
    println("Optimize:     $optimize_model")
    println("Result dir:   $result_dir")
    println("Start time:   $(now())")
    println("================================================")

    build_start = time()
    emp, periods, sets, params = OpenEMPIRE.create_model(
        config_file,
        data_folder;
        optimizer,
        input_format = format,
        scenario_rng = MersenneTwister(seed),
    )
    build_seconds = time() - build_start
    println("Model build seconds: $(round(build_seconds; digits = 2))")
    println("Variables: $(JuMP.num_variables(emp))")
    println("Constraints: $(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))")

    termination = nothing
    objective = nothing
    objective_components = nothing
    solve_seconds = 0.0
    if optimize_model
        solve_start = time()
        JuMP.optimize!(emp)
        solve_seconds = time() - solve_start
        termination = JuMP.termination_status(emp)
        objective = JuMP.objective_value(emp)
        objective_components = OpenEMPIRE.objective_component_values(
            emp,
            sets,
            params,
            periods,
            Discounter(OpenEMPIRE.discount_rate(params), 1, periods),
        )
        println("Solve seconds: $(round(solve_seconds; digits = 2))")
        println("Termination status: $termination")
        println("Objective value: $objective")
        println("Objective components:")
        for (name, value) in pairs(objective_components)
            println("  $name: $value")
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

    summary_path = _write_summary(
        joinpath(result_dir, "summary.txt"),
        vcat([
            "OpenEMPIRE.jl run summary",
            "dataset=$dataset",
            "data_folder=$data_folder",
            "config_file=$config_file",
            "input_format=$format",
            "solver=$solver_name",
            "seed=$seed",
            "fixed_sample=$fixed_sample_option",
            "optimize=$optimize_model",
            "variables=$(JuMP.num_variables(emp))",
            "constraints=$(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))",
            "build_seconds=$build_seconds",
            "solve_seconds=$solve_seconds",
            "termination_status=$(termination === nothing ? "not_optimized" : string(termination))",
            "objective_value=$(objective === nothing ? "not_optimized" : string(objective))",
            "end_time=$(now())",
        ], component_lines),
    )
    println("Summary written to: $summary_path")
    println("End time: $(now())")

    return termination
end

main()
