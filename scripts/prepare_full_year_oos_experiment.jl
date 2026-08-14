#!/usr/bin/env julia

using OpenEMPIRE
using YAML

const _FULL_YEAR_OPTIONS = Set([
    "dataset",
    "config",
    "format",
    "sample-years",
    "output",
    "resume",
])

function _parse_full_year_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "sample-years" => "2015",
        "output" => "",
        "resume" => "true",
    )
    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            key in _FULL_YEAR_OPTIONS || throw(ArgumentError(
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

function _full_year_input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _full_year_bool(value, option)
    lowercase(value) == "true" && return true
    lowercase(value) == "false" && return false
    throw(ArgumentError("--$option must be true or false, got: $value"))
end

function _full_year_sample_years(value)
    values = split(value, ",")
    any(isempty, strip.(values)) && throw(ArgumentError(
        "--sample-years must be a comma-separated list of years",
    ))
    return parse.(Int, strip.(values))
end

function _full_year_data_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _default_full_year_path(dataset::AbstractString, sample_years)
    dataset_name = basename(normpath(dataset))
    year_label = join(sample_years, "-")
    return joinpath("OutOfSample", dataset_name, "full_year_$year_label")
end

function main(args = ARGS)
    options = _parse_full_year_args(args)
    dataset = options["dataset"]
    data_folder = _full_year_data_folder(dataset)
    config_file = options["config"]
    input_format = _full_year_input_format(options["format"])
    sample_years = _full_year_sample_years(options["sample-years"])
    resume = _full_year_bool(options["resume"], "resume")
    output = isempty(strip(options["output"])) ?
             _default_full_year_path(dataset, sample_years) : options["output"]

    println("Preparing chronological full-year OOS experiment")
    println("Dataset:     $data_folder")
    println("Base config: $config_file")
    println("Years:       $(join(sample_years, ", "))")
    println("Resume:      $resume")
    println("Output:      $output")

    experiment_dir = OpenEMPIRE.prepare_full_year_oos_experiment(
        config_file,
        data_folder,
        output;
        sample_years,
        input_format,
        resume,
        progress = println,
    )
    manifest = YAML.load_file(joinpath(experiment_dir, "experiment.yaml"))
    println("Full-year OOS experiment prepared at: $experiment_dir")
    println("Execution config: $(manifest["source_config_file"])")
    println("Manifest: $(joinpath(experiment_dir, "experiment.yaml"))")
    return experiment_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
