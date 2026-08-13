#!/usr/bin/env julia

using OpenEMPIRE

function _parse_oos_tree_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "seed" => "1",
        "output" => "",
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

function _oos_tree_input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _oos_tree_data_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _default_oos_tree_path(dataset::AbstractString)
    dataset_name = basename(normpath(dataset))
    return joinpath("OutOfSample", dataset_name, "oos_tree1")
end

function main(args = ARGS)
    options = _parse_oos_tree_args(args)
    dataset = options["dataset"]
    data_folder = _oos_tree_data_folder(dataset)
    config_file = options["config"]
    input_format = _oos_tree_input_format(options["format"])
    seed = parse(Int, options["seed"])
    output = isempty(strip(options["output"])) ?
             _default_oos_tree_path(dataset) : options["output"]

    println("Generating one OOS scenario tree")
    println("Dataset: $data_folder")
    println("Config:  $config_file")
    println("Seed:    $seed")
    println("Output:  $output")

    tree_dir = OpenEMPIRE.generate_oos_scenario_tree(
        config_file,
        data_folder,
        output;
        input_format,
        seed,
    )
    println("OOS scenario tree written to: $tree_dir")
    println("Metadata written to: $(joinpath(tree_dir, "metadata.yaml"))")
    return tree_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
