#!/usr/bin/env julia

using OpenEMPIRE

const _OOS_EXPERIMENT_OPTIONS = Set([
    "dataset",
    "config",
    "format",
    "num-trees",
    "seed-start",
    "output",
    "resume",
])

function _parse_oos_experiment_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "num-trees" => "1",
        "seed-start" => "1",
        "output" => "",
        "resume" => "true",
    )

    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            key in _OOS_EXPERIMENT_OPTIONS || throw(ArgumentError(
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

function _oos_experiment_input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _oos_experiment_bool(value, option)
    lowercase(value) == "true" && return true
    lowercase(value) == "false" && return false
    throw(ArgumentError("--$option must be true or false, got: $value"))
end

function _oos_experiment_data_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _default_oos_experiment_path(
    dataset::AbstractString,
    seed_start::Int,
    num_trees::Int,
)
    dataset_name = basename(normpath(dataset))
    return joinpath(
        "OutOfSample",
        dataset_name,
        "experiment_seed$(seed_start)_$(num_trees)trees",
    )
end

function main(args = ARGS)
    options = _parse_oos_experiment_args(args)
    dataset = options["dataset"]
    data_folder = _oos_experiment_data_folder(dataset)
    config_file = options["config"]
    input_format = _oos_experiment_input_format(options["format"])
    num_trees = parse(Int, options["num-trees"])
    seed_start = parse(Int, options["seed-start"])
    resume = _oos_experiment_bool(options["resume"], "resume")
    output = isempty(strip(options["output"])) ?
             _default_oos_experiment_path(dataset, seed_start, num_trees) :
             options["output"]

    println("Preparing OOS scenario-tree experiment")
    println("Dataset:    $data_folder")
    println("Config:     $config_file")
    println("Trees:      $num_trees")
    println("Seed start: $seed_start")
    println("Resume:     $resume")
    println("Output:     $output")

    experiment_dir = OpenEMPIRE.prepare_oos_experiment(
        config_file,
        data_folder,
        output;
        num_trees,
        seed_start,
        input_format,
        resume,
        progress = println,
    )
    println("OOS experiment prepared at: $experiment_dir")
    println("Manifest: $(joinpath(experiment_dir, "experiment.yaml"))")
    return experiment_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
