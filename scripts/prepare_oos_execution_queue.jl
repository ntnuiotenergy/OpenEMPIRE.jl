#!/usr/bin/env julia

using OpenEMPIRE

const _OOS_QUEUE_OPTIONS = Set([
    "dataset",
    "config",
    "format",
    "solver",
    "experiment",
    "fixed-investment-dir",
    "results",
    "queue-file",
    "julia-command",
    "resume",
])

function _parse_oos_queue_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "HiGHS",
        "experiment" => "",
        "fixed-investment-dir" => "",
        "results" => "",
        "queue-file" => "",
        "julia-command" => "julia",
        "resume" => "true",
    )

    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            key in _OOS_QUEUE_OPTIONS || throw(ArgumentError(
                "Unsupported option: --$key",
            ))
            options[key] = value
        elseif !startswith(arg, "--")
            options["dataset"] = arg
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end
    return options
end

function _oos_queue_cli_input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _oos_queue_cli_bool(value, option)
    lowercase(value) == "true" && return true
    lowercase(value) == "false" && return false
    throw(ArgumentError("--$option must be true or false, got: $value"))
end

function _default_oos_queue_results(experiment::AbstractString)
    experiment_name = basename(normpath(experiment))
    return joinpath("results", "julia_oos_runs", experiment_name)
end

function main(args = ARGS)
    options = _parse_oos_queue_args(args)
    experiment = strip(options["experiment"])
    fixed_investment_dir = strip(options["fixed-investment-dir"])
    isempty(experiment) && throw(ArgumentError("--experiment is required"))
    isempty(fixed_investment_dir) && throw(ArgumentError(
        "--fixed-investment-dir is required",
    ))

    results = isempty(strip(options["results"])) ?
              _default_oos_queue_results(experiment) :
              options["results"]
    queue_file = isempty(strip(options["queue-file"])) ?
                 joinpath(experiment, "execution.yaml") :
                 options["queue-file"]
    input_format = _oos_queue_cli_input_format(options["format"])
    resume = _oos_queue_cli_bool(options["resume"], "resume")

    println("Preparing OOS execution queue (no jobs will be started)")
    println("Experiment:        $experiment")
    println("Fixed investments: $fixed_investment_dir")
    println("Dataset:           $(options["dataset"])")
    println("Config:            $(options["config"])")
    println("Solver:            $(options["solver"])")
    println("Results:           $results")
    println("Queue:             $queue_file")
    println("Resume:            $resume")

    manifest_file = OpenEMPIRE.prepare_oos_execution_queue(
        experiment,
        fixed_investment_dir;
        dataset = options["dataset"],
        config_file = options["config"],
        results_root = results,
        input_format,
        solver = options["solver"],
        queue_file,
        julia_command = options["julia-command"],
        resume,
    )
    println("Execution queue written to: $manifest_file")
    return manifest_file
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
