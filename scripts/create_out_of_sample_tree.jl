#!/usr/bin/env julia

using Dates
using OpenEMPIRE
using Random
using YAML

function _parse_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "num-trees" => "1",
        "seed" => "1",
        "out-of-sample-root" => "OutOfSample",
        "version" => "",
    )

    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
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

function _copy_scenario_data!(data_folder, target_tree_folder)
    source_dir = joinpath(data_folder, "ScenarioData")
    target_dir = joinpath(target_tree_folder, "ScenarioData")
    mkpath(target_dir)

    # `generate_scenarios` writes into the dataset ScenarioData folder first.
    # Copy those generated files into an InternalEMPIRE-style OOS tree folder.
    files = (
        "sloadRaw.csv",
        "maxRegHydroGenRaw.csv",
        "genCapAvailStochRaw.csv",
        "sampling_key.csv",
    )

    for file in files
        source_file = joinpath(source_dir, file)
        isfile(source_file) || throw(ArgumentError("Missing generated scenario file: $source_file"))
        cp(source_file, joinpath(target_dir, file); force = true)
    end

    return target_dir
end

function _write_metadata(path, metadata)
    mkpath(dirname(path))
    YAML.write_file(path, metadata)
    return path
end

function main(args = ARGS)
    options = _parse_args(args)

    dataset = options["dataset"]
    version = isempty(strip(options["version"])) ? dataset : strip(options["version"])
    data_folder = joinpath("data", dataset)
    config_file = options["config"]
    input_format = _input_format(options["format"])
    num_trees = parse(Int, options["num-trees"])
    seed_start = parse(Int, options["seed"])
    oos_root = options["out-of-sample-root"]

    isdir(data_folder) || throw(ArgumentError("Dataset folder not found: $data_folder"))
    isfile(config_file) || throw(ArgumentError("Config file not found: $config_file"))
    num_trees >= 1 || throw(ArgumentError("--num-trees must be at least 1"))

    println("================================================")
    println("OpenEMPIRE.jl OOS scenario tree generation")
    println("================================================")
    println("Dataset:     $dataset")
    println("Version:     $version")
    println("Data folder: $data_folder")
    println("Config file: $config_file")
    println("Input format: $input_format")
    println("Num trees:   $num_trees")
    println("Seed start:  $seed_start")
    println("OOS root:    $oos_root")
    println("Start time:  $(now())")
    println("================================================")

    config = YAML.load_file(config_file)
    oos_version_dir = joinpath(oos_root, version)
    mkpath(oos_version_dir)

    for tree_index in 1:num_trees
        tree_name = "oos_tree$tree_index"
        tree_folder = joinpath(oos_version_dir, tree_name)
        seed = seed_start + tree_index - 1

        tick = time()
        println("Generating $tree_name with seed $seed")

        OpenEMPIRE.generate_scenarios(
            config_file,
            data_folder;
            input_format = input_format,
            scenario_rng = MersenneTwister(seed),
        )

        scenario_dir = _copy_scenario_data!(data_folder, tree_folder)

        metadata_path = _write_metadata(
            joinpath(tree_folder, "metadata.yaml"),
            Dict(
                "dataset" => dataset,
                "version" => version,
                "tree" => tree_name,
                "seed" => seed,
                "config_file" => config_file,
                "source_data_folder" => data_folder,
                "scenario_data_folder" => scenario_dir,
                "created_at" => string(now()),
                "number_of_scenarios" => get(config, "number_of_scenarios", nothing),
                "forecast_horizon_year" => get(config, "forecast_horizon_year", nothing),
                "length_of_regular_season" => get(config, "length_of_regular_season", nothing),
            ),
        )

        tock = time()
        println("Scenario generation of $tree_name took [sec]: $(round(tock - tick; digits = 2))")
        println("Scenario data written to: $scenario_dir")
        println("Metadata written to: $metadata_path")
    end

    println("End time: $(now())")
    println("OOS scenario trees written under: $oos_version_dir")
end

main()
