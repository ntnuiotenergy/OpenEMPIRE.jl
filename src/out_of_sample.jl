const _OOS_SCENARIO_FILENAMES = (
    "sloadRaw.csv",
    "maxRegHydroGenRaw.csv",
    "genCapAvailStochRaw.csv",
)

const _OOS_TREE_FILENAMES = (_OOS_SCENARIO_FILENAMES..., "sampling_key.csv")
const _OOS_EXPERIMENT_MANIFEST = "experiment.yaml"

const _OOS_TREE_CONFIG_KEYS = (
    "forecast_horizon_year",
    "leap_years_investment",
    "number_of_scenarios",
    "regular_seasons",
    "length_of_regular_season",
    "n_peak_seasons",
    "len_peak_season",
    "time_format",
    "use_fixed_sample",
)

function _oos_sha256_file(path::AbstractString)
    open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function _oos_directory_sha256(root::AbstractString)
    files = String[]
    for (directory, _, filenames) in walkdir(root)
        append!(files, joinpath(directory, filename) for filename in filenames)
    end
    sort!(files; by = path -> relpath(path, root))
    digest_manifest = join(
        ("$(relpath(path, root))\t$(_oos_sha256_file(path))" for path in files),
        "\n",
    )
    return bytes2hex(sha256(digest_manifest))
end

function _oos_tree_file_metadata(scenario_dir::AbstractString)
    return Dict{String, Any}(
        filename => Dict{String, Any}(
            "bytes" => filesize(joinpath(scenario_dir, filename)),
            "sha256" => _oos_sha256_file(joinpath(scenario_dir, filename)),
        ) for filename in _OOS_TREE_FILENAMES
    )
end

function _oos_tree_metadata(
    config,
    config_file::AbstractString,
    data_folder::AbstractString,
    data_sha256::AbstractString,
    tree_dir::AbstractString,
    scenario_dir::AbstractString,
    input_format::Symbol,
    seed::Int,
)
    config_values = Dict{String, Any}()
    for key in _OOS_TREE_CONFIG_KEYS
        haskey(config, key) && (config_values[key] = config[key])
    end

    return Dict{String, Any}(
        "schema_version" => 1,
        "generator" => "OpenEMPIRE.generate_oos_scenario_tree",
        "created_at_utc" => string(now(UTC), "Z"),
        "julia_version" => string(VERSION),
        "openempire_version" => string(pkgversion(@__MODULE__)),
        "tree" => basename(tree_dir),
        "tree_dir" => tree_dir,
        "seed" => seed,
        "input_format" => string(input_format),
        "source_data_folder" => data_folder,
        "source_data_sha256" => data_sha256,
        "source_config_file" => config_file,
        "source_config_sha256" => _oos_sha256_file(config_file),
        "config" => config_values,
        "files" => _oos_tree_file_metadata(scenario_dir),
    )
end

function _generate_oos_scenario_tree_from_staged_data(
    config,
    config_file::AbstractString,
    source_data::AbstractString,
    source_data_sha256::AbstractString,
    staged_data::AbstractString,
    target_tree::AbstractString;
    input_format::Symbol,
    seed::Int,
    progress,
)
    ispath(target_tree) && throw(ArgumentError("OOS tree already exists: $target_tree"))
    target_parent = dirname(target_tree)
    mkpath(target_parent)

    generate_scenarios(
        config_file,
        staged_data;
        input_format,
        scenario_rng = MersenneTwister(seed),
        progress,
    )

    generated_scenario_dir = joinpath(staged_data, "ScenarioData")
    mktempdir(target_parent; prefix = ".oos-tree-") do workspace
        staged_tree = joinpath(workspace, "tree")
        staged_scenario_dir = joinpath(staged_tree, "ScenarioData")
        mkpath(staged_scenario_dir)
        for filename in _OOS_TREE_FILENAMES
            source_file = joinpath(generated_scenario_dir, filename)
            isfile(source_file) || throw(ArgumentError(
                "Scenario generation did not produce required file: $source_file",
            ))
            cp(source_file, joinpath(staged_scenario_dir, filename))
        end

        metadata = _oos_tree_metadata(
            config,
            config_file,
            source_data,
            source_data_sha256,
            target_tree,
            staged_scenario_dir,
            input_format,
            seed,
        )
        YAML.write_file(joinpath(staged_tree, "metadata.yaml"), metadata)
        mv(staged_tree, target_tree)
    end
    return target_tree
end

"""
    generate_oos_scenario_tree(
        config_file,
        data_folder,
        tree_dir;
        input_format = :auto,
        seed = 1,
        progress = nothing,
    )

Generate one out-of-sample scenario tree without modifying `data_folder`.

The dataset is copied to a temporary workspace before [`generate_scenarios`](@ref)
is called. The generated scenario CSVs, sampling key, and reproducibility
metadata are then published atomically under `tree_dir`. An existing `tree_dir`
is never overwritten. Returns the absolute tree path.
"""
function generate_oos_scenario_tree(
    config_file::AbstractString,
    data_folder::AbstractString,
    tree_dir::AbstractString;
    input_format::Symbol = :auto,
    seed::Integer = 1,
    progress = nothing,
)
    source_data = abspath(normpath(data_folder))
    source_config = abspath(normpath(config_file))
    target_tree = abspath(normpath(tree_dir))
    seed_value = Int(seed)

    isdir(source_data) || throw(ArgumentError("Dataset folder does not exist: $data_folder"))
    isfile(source_config) || throw(ArgumentError("Config file does not exist: $config_file"))
    ispath(target_tree) && throw(ArgumentError("OOS tree already exists: $tree_dir"))
    _is_same_or_child_path(target_tree, source_data) && throw(ArgumentError(
        "OOS tree must be outside the source dataset: $tree_dir",
    ))

    config = YAML.load_file(source_config)
    _config_bool(config, "use_scenario_generation", true) || throw(ArgumentError(
        "OOS tree generation requires use_scenario_generation: true",
    ))

    source_data_sha256 = _oos_directory_sha256(source_data)
    target_parent = dirname(target_tree)
    mkpath(target_parent)
    mktempdir(target_parent; prefix = ".oos-source-") do workspace
        staged_data = joinpath(workspace, "data")
        cp(source_data, staged_data)
        _generate_oos_scenario_tree_from_staged_data(
            config,
            source_config,
            source_data,
            source_data_sha256,
            staged_data,
            target_tree;
            input_format,
            seed = seed_value,
            progress,
        )
    end

    return target_tree
end

function _write_oos_experiment_manifest(path::AbstractString, manifest)
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary_path, io
        close(io)
        YAML.write_file(temporary_path, manifest)
        mv(temporary_path, path; force = true)
    end
    return path
end

function _oos_experiment_tree_entry(
    experiment_dir::AbstractString,
    index::Int,
    seed::Int,
)
    tree_name = "oos_tree$index"
    tree_dir = joinpath(experiment_dir, tree_name)
    return Dict{String, Any}(
        "index" => index,
        "name" => tree_name,
        "seed" => seed,
        "path" => tree_dir,
        "status" => "pending",
        "metadata_file" => joinpath(tree_dir, "metadata.yaml"),
        "error" => nothing,
    )
end

function _new_oos_experiment_manifest(
    config_file::AbstractString,
    config_sha256::AbstractString,
    data_folder::AbstractString,
    data_sha256::AbstractString,
    experiment_dir::AbstractString,
    input_format::Symbol,
    seed_start::Int,
    num_trees::Int,
)
    created_at = string(now(UTC), "Z")
    trees = [
        _oos_experiment_tree_entry(experiment_dir, index, seed_start + index - 1) for
        index in 1:num_trees
    ]
    return Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_tree_experiment",
        "status" => "preparing",
        "created_at_utc" => created_at,
        "updated_at_utc" => created_at,
        "source_data_folder" => data_folder,
        "source_data_sha256" => data_sha256,
        "source_config_file" => config_file,
        "source_config_sha256" => config_sha256,
        "input_format" => string(input_format),
        "seed_start" => seed_start,
        "num_trees" => num_trees,
        "trees" => trees,
    )
end

function _validate_oos_experiment_spec(existing, expected)
    keys = (
        "schema_version",
        "kind",
        "source_data_folder",
        "source_data_sha256",
        "source_config_file",
        "source_config_sha256",
        "input_format",
        "seed_start",
        "num_trees",
    )
    for key in keys
        haskey(existing, key) || throw(ArgumentError(
            "Existing OOS experiment manifest is missing required key: $key",
        ))
        existing[key] == expected[key] || throw(ArgumentError(
            "Existing OOS experiment has a different $key: " *
            "$(existing[key]) (expected $(expected[key]))",
        ))
    end
    return nothing
end

function _validate_oos_experiment_tree(
    tree_dir::AbstractString,
    expected_seed::Int,
    expected_data_sha256::AbstractString,
    expected_config_sha256::AbstractString,
    expected_input_format::Symbol,
)
    metadata_file = joinpath(tree_dir, "metadata.yaml")
    isfile(metadata_file) || throw(ArgumentError(
        "Existing OOS tree is missing metadata.yaml: $tree_dir",
    ))
    metadata = YAML.load_file(metadata_file)
    metadata isa AbstractDict || throw(ArgumentError(
        "OOS tree metadata must be a mapping: $metadata_file",
    ))

    expected = Dict{String, Any}(
        "seed" => expected_seed,
        "source_data_sha256" => expected_data_sha256,
        "source_config_sha256" => expected_config_sha256,
        "input_format" => string(expected_input_format),
    )
    for (key, value) in expected
        haskey(metadata, key) || throw(ArgumentError(
            "OOS tree metadata is missing required key '$key': $metadata_file",
        ))
        metadata[key] == value || throw(ArgumentError(
            "OOS tree metadata has unexpected $key in $metadata_file: " *
            "$(metadata[key]) (expected $value)",
        ))
    end

    file_metadata = get(metadata, "files", nothing)
    file_metadata isa AbstractDict || throw(ArgumentError(
        "OOS tree metadata has no valid files mapping: $metadata_file",
    ))
    scenario_dir = joinpath(tree_dir, "ScenarioData")
    for filename in _OOS_TREE_FILENAMES
        scenario_file = joinpath(scenario_dir, filename)
        isfile(scenario_file) || throw(ArgumentError(
            "Existing OOS tree is missing required file: $scenario_file",
        ))
        haskey(file_metadata, filename) || throw(ArgumentError(
            "OOS tree metadata is missing checksum data for $filename: $metadata_file",
        ))
        recorded = file_metadata[filename]
        recorded isa AbstractDict || throw(ArgumentError(
            "Invalid checksum data for $filename in $metadata_file",
        ))
        expected_sha256 = get(recorded, "sha256", nothing)
        actual_sha256 = _oos_sha256_file(scenario_file)
        expected_sha256 == actual_sha256 || throw(ArgumentError(
            "OOS tree checksum mismatch for $scenario_file",
        ))
    end
    return metadata
end

function _mark_oos_experiment_updated!(manifest, status::AbstractString)
    manifest["status"] = status
    manifest["updated_at_utc"] = string(now(UTC), "Z")
    return manifest
end

"""
    prepare_oos_experiment(
        config_file,
        data_folder,
        experiment_dir;
        num_trees,
        seed_start = 1,
        input_format = :auto,
        resume = true,
        progress = nothing,
    )

Prepare a deterministic collection of out-of-sample scenario trees.

Trees are written as `oos_tree1`, `oos_tree2`, and so on, using consecutive
seeds beginning at `seed_start`. `experiment.yaml` records the immutable
experiment specification and the preparation status of every tree. With
`resume = true`, complete trees are checksum-validated and skipped; missing
trees are generated. Existing invalid trees and incompatible manifests are
never overwritten. Returns the absolute experiment directory.

This function only prepares scenario data. It does not start EMPIRE runs or
aggregate solver results.
"""
function prepare_oos_experiment(
    config_file::AbstractString,
    data_folder::AbstractString,
    experiment_dir::AbstractString;
    num_trees::Integer,
    seed_start::Integer = 1,
    input_format::Symbol = :auto,
    resume::Bool = true,
    progress = nothing,
)
    source_data = abspath(normpath(data_folder))
    source_config = abspath(normpath(config_file))
    target_experiment = abspath(normpath(experiment_dir))
    tree_count = Int(num_trees)
    first_seed = Int(seed_start)

    tree_count > 0 || throw(ArgumentError("num_trees must be positive"))
    first_seed >= 0 || throw(ArgumentError("seed_start must be non-negative"))
    try
        Base.checked_add(first_seed, tree_count - 1)
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError("seed_start + num_trees exceeds the supported integer range"))
    end
    isdir(source_data) || throw(ArgumentError(
        "Dataset folder does not exist: $data_folder",
    ))
    isfile(source_config) || throw(ArgumentError(
        "Config file does not exist: $config_file",
    ))
    _is_same_or_child_path(target_experiment, source_data) && throw(ArgumentError(
        "OOS experiment must be outside the source dataset: $experiment_dir",
    ))

    config = YAML.load_file(source_config)
    _config_bool(config, "use_scenario_generation", true) || throw(ArgumentError(
        "OOS experiment preparation requires use_scenario_generation: true",
    ))
    !_config_bool(config, "use_fixed_sample", false) || throw(ArgumentError(
        "OOS experiment preparation requires use_fixed_sample: false so seeds produce " *
        "independent trees",
    ))

    source_data_sha256 = _oos_directory_sha256(source_data)
    source_config_sha256 = _oos_sha256_file(source_config)
    expected_manifest = _new_oos_experiment_manifest(
        source_config,
        source_config_sha256,
        source_data,
        source_data_sha256,
        target_experiment,
        input_format,
        first_seed,
        tree_count,
    )
    manifest_file = joinpath(target_experiment, _OOS_EXPERIMENT_MANIFEST)

    manifest = if ispath(target_experiment)
        isdir(target_experiment) || throw(ArgumentError(
            "OOS experiment path exists but is not a directory: $experiment_dir",
        ))
        if isfile(manifest_file)
            resume || throw(ArgumentError(
                "OOS experiment already exists and resume=false: $experiment_dir",
            ))
            existing = YAML.load_file(manifest_file)
            existing isa AbstractDict || throw(ArgumentError(
                "Existing OOS experiment manifest must be a mapping: $manifest_file",
            ))
            _validate_oos_experiment_spec(existing, expected_manifest)
            expected_manifest["created_at_utc"] = get(
                existing,
                "created_at_utc",
                expected_manifest["created_at_utc"],
            )
            expected_manifest
        else
            isempty(readdir(target_experiment)) || throw(ArgumentError(
                "OOS experiment directory exists without experiment.yaml and is not " *
                "empty: $experiment_dir",
            ))
            expected_manifest
        end
    else
        mkpath(target_experiment)
        expected_manifest
    end

    trees = manifest["trees"]
    for tree in trees
        tree_dir = tree["path"]
        ispath(tree_dir) || continue
        try
            _validate_oos_experiment_tree(
                tree_dir,
                tree["seed"],
                source_data_sha256,
                source_config_sha256,
                input_format,
            )
            tree["status"] = "complete"
        catch error
            tree["status"] = "failed"
            tree["error"] = sprint(showerror, error)
            _mark_oos_experiment_updated!(manifest, "failed")
            _write_oos_experiment_manifest(manifest_file, manifest)
            rethrow()
        end
    end

    if all(tree -> tree["status"] == "complete", trees)
        _mark_oos_experiment_updated!(manifest, "complete")
        _write_oos_experiment_manifest(manifest_file, manifest)
        return target_experiment
    end

    _mark_oos_experiment_updated!(manifest, "preparing")
    _write_oos_experiment_manifest(manifest_file, manifest)
    _report_progress(progress, "Preparing $tree_count OOS scenario trees in $target_experiment")

    mktempdir(dirname(target_experiment); prefix = ".oos-experiment-") do workspace
        staged_data = joinpath(workspace, "data")
        cp(source_data, staged_data)
        for tree in trees
            tree["status"] == "complete" && continue
            tree["status"] = "generating"
            tree["error"] = nothing
            _mark_oos_experiment_updated!(manifest, "preparing")
            _write_oos_experiment_manifest(manifest_file, manifest)
            _report_progress(
                progress,
                "Generating $(tree["name"]) with seed $(tree["seed"])",
            )

            try
                _generate_oos_scenario_tree_from_staged_data(
                    config,
                    source_config,
                    source_data,
                    source_data_sha256,
                    staged_data,
                    tree["path"];
                    input_format,
                    seed = tree["seed"],
                    progress,
                )
                _validate_oos_experiment_tree(
                    tree["path"],
                    tree["seed"],
                    source_data_sha256,
                    source_config_sha256,
                    input_format,
                )
                tree["status"] = "complete"
                _mark_oos_experiment_updated!(manifest, "preparing")
                _write_oos_experiment_manifest(manifest_file, manifest)
            catch error
                tree["status"] = "failed"
                tree["error"] = sprint(showerror, error)
                _mark_oos_experiment_updated!(manifest, "failed")
                _write_oos_experiment_manifest(manifest_file, manifest)
                rethrow()
            end
        end
    end

    _mark_oos_experiment_updated!(manifest, "complete")
    _write_oos_experiment_manifest(manifest_file, manifest)
    return target_experiment
end

"""
    fix_investments_from_results!(model, sets, periods, output_dir; fix_installed_capacities=true)

Read strategic capacity results from a previous run and fix the matching JuMP
variables in `model`.

`output_dir` may point either to a run directory or directly to its `Output`
subdirectory.
"""
function fix_investments_from_results!(
    model::JuMP.Model,
    sets,
    periods::TimeStructure,
    output_dir::AbstractString;
    fix_installed_capacities::Bool = true,
)
    output_dir = _oos_output_dir(output_dir)
    strategic_periods = collect(enumerate(strat_periods(periods)))

    # Fix investment decisions to values from the previous run.
    _fix_generator_capacity!(
        model[:genInvCap],
        sets,
        strategic_periods,
        _read_generator_capacity(output_dir, "genInvCap.csv", "genInvCap"),
        "genInvCap",
    )

    # Accept the old misspelled file/column name for compatibility with
    # previous Julia result folders.
    _fix_transmission_capacity!(
        model[:transmissionInvCap],
        sets,
        strategic_periods,
        _read_transmission_capacity(
            output_dir,
            ("transmissionInvCap.csv", "transmisionInvCap.csv"),
            ("transmissionInvCap", "transmisionInvCap"),
        ),
        "transmissionInvCap",
    )

    _fix_storage_capacity!(
        model[:storPWInvCap],
        sets,
        strategic_periods,
        _read_storage_capacity(output_dir, "storPWInvCap.csv", "storPWInvCap"),
        "storPWInvCap",
    )

    _fix_storage_capacity!(
        model[:storENInvCap],
        sets,
        strategic_periods,
        _read_storage_capacity(output_dir, "storENInvCap.csv", "storENInvCap"),
        "storENInvCap",
    )

    if fix_installed_capacities
        # Fix installed capacities to the same previous-run capacity trajectory.
        _fix_generator_capacity!(
            model[:genInstalledCap],
            sets,
            strategic_periods,
            _read_generator_capacity(output_dir, "genInstalledCap.csv", "genInstalledCap"),
            "genInstalledCap",
        )

        _fix_transmission_capacity!(
            model[:transmissionInstalledCap],
            sets,
            strategic_periods,
            _read_transmission_capacity(
                output_dir,
                ("transmissionInstalledCap.csv",),
                ("transmissionInstalledCap",),
            ),
            "transmissionInstalledCap",
        )

        _fix_storage_capacity!(
            model[:storPWInstalledCap],
            sets,
            strategic_periods,
            _read_storage_capacity(output_dir, "storPWInstalledCap.csv", "storPWInstalledCap"),
            "storPWInstalledCap",
        )

        _fix_storage_capacity!(
            model[:storENInstalledCap],
            sets,
            strategic_periods,
            _read_storage_capacity(output_dir, "storENInstalledCap.csv", "storENInstalledCap"),
            "storENInstalledCap",
        )
    end

    return model
end

function _oos_output_dir(path::AbstractString)
    isdir(path) || throw(ArgumentError("Fixed-investment directory does not exist: $path"))

    for output_folder in ("Output", "output")
        output_path = joinpath(path, output_folder)
        isdir(output_path) && return output_path
    end

    return path
end

function _first_existing_file(output_dir::AbstractString, filenames)
    for filename in filenames
        path = joinpath(output_dir, filename)
        isfile(path) && return path
    end

    throw(ArgumentError(
        "Could not find any of these files in $output_dir: $(join(filenames, ", "))"
    ))
end

_oos_float_value(x) = x isa Real ? Float64(x) : parse(Float64, strip(string(x)))
_oos_int_value(x) = x isa Integer ? Int(x) : parse(Int, strip(string(x)))
_oos_string_value(x) = strip(string(x))

function _oos_row_value(row, columns)
    available = Set(string.(propertynames(row)))

    for column in columns
        if column in available
            return getproperty(row, Symbol(column))
        end
    end

    throw(ArgumentError("Missing value column. Tried: $(join(columns, ", "))"))
end

function _read_generator_capacity(output_dir, filename, value_column)
    path = _first_existing_file(output_dir, (filename,))
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.Node),
            _oos_string_value(row.Generator),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(getproperty(row, Symbol(value_column)))
    end

    return values
end

function _read_transmission_capacity(output_dir, filenames, value_columns)
    path = _first_existing_file(output_dir, filenames)
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.FromNode),
            _oos_string_value(row.ToNode),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(_oos_row_value(row, value_columns))
    end

    return values
end

function _read_storage_capacity(output_dir, filename, value_column)
    path = _first_existing_file(output_dir, (filename,))
    values = Dict{Tuple{String, String, Int}, Float64}()

    for row in CSV.File(path; normalizenames = false)
        key = (
            _oos_string_value(row.Node),
            _oos_string_value(row.Storage),
            _oos_int_value(row.Period),
        )
        values[key] = _oos_float_value(getproperty(row, Symbol(value_column)))
    end

    return values
end

function _fixed_value(values, key, table_name)
    # Missing keys usually mean the OOS run is using different structural data
    # than the in-sample run that produced the fixed investment results.
    value = get(values, key, nothing)

    value === nothing && throw(ArgumentError(
        "Missing fixed OOS value for $table_name at key $key"
    ))

    return value
end

function _fix_generator_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (node, generator) in node_generators(sets)
            key = (node, generator, period_index)
            JuMP.fix(variable[node, generator, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_transmission_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (from_node, to_node) in bidir_arcs(sets)
            key = (from_node, to_node, period_index)
            JuMP.fix(variable[from_node, to_node, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_storage_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()

    for (period_index, sp) in strategic_periods
        for (node, storage) in node_storages(sets)
            key = (node, storage, period_index)
            JuMP.fix(variable[node, storage, sp], _fixed_value(values, key, table_name); force = true)
            push!(used, key)
        end
    end

    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _check_no_extra_oos_keys(values, used, table_name)
    # Extra keys catch the opposite mismatch: the result file has assets that
    # are not part of the current model's sets.
    extra = setdiff(Set(keys(values)), used)

    if !isempty(extra)
        preview = collect(extra)[1:min(end, 10)]
        throw(ArgumentError(
            "Fixed OOS file for $table_name contains keys not present in current model. " *
            "First extra keys: $preview"
        ))
    end

    return nothing
end

const _OOS_INVESTMENT_FILENAMES = (
    ("genInvCap.csv",),
    ("transmissionInvCap.csv", "transmisionInvCap.csv"),
    ("storPWInvCap.csv",),
    ("storENInvCap.csv",),
    ("genInstalledCap.csv",),
    ("transmissionInstalledCap.csv",),
    ("storPWInstalledCap.csv",),
    ("storENInstalledCap.csv",),
)

const _OOS_INVESTMENT_COMPATIBILITY_KEYS = (
    "forecast_horizon_year",
    "leap_years_investment",
    "north_sea",
    "use_emission_cap",
    "discount_rate",
    "wacc",
    "load_change_module",
)

const _OOS_ALLOWED_OPERATIONAL_CONFIG_DIFFERENCES = (
    "use_scenario_generation",
    "use_fixed_sample",
    "number_of_scenarios",
    "regular_seasons",
    "length_of_regular_season",
    "n_peak_seasons",
    "len_peak_season",
    "time_format",
)

function _oos_sha256_file(path::AbstractString)
    open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function _oos_fixed_investment_source_files(path::AbstractString)
    output_dir = _oos_output_dir(path)
    return map(_OOS_INVESTMENT_FILENAMES) do aliases
        source_index = findfirst(
            filename -> isfile(joinpath(output_dir, filename)),
            aliases,
        )
        source_index === nothing && throw(ArgumentError(
            "Fixed-investment directory is missing one of: $(join(aliases, ", "))",
        ))
        joinpath(output_dir, aliases[source_index])
    end
end

function _oos_fixed_capacity_metadata(path::AbstractString)
    run_dir = abspath(normpath(path))
    output_dir = _oos_output_dir(run_dir)
    files = _oos_fixed_investment_source_files(run_dir)
    file_metadata = [
        Dict{String, Any}(
            "name" => basename(file),
            "path" => file,
            "bytes" => filesize(file),
            "sha256" => _oos_sha256_file(file),
        ) for file in files
    ]
    digest_input = join(
        ("$(entry["name"])\t$(entry["sha256"])" for entry in file_metadata),
        "\n",
    )
    return Dict{String, Any}(
        "run_dir" => run_dir,
        "output_dir" => output_dir,
        "sha256" => bytes2hex(sha256(digest_input)),
        "files" => file_metadata,
    )
end

function _oos_investment_run_dir(path::AbstractString)
    normalized = abspath(normpath(path))
    return lowercase(basename(normalized)) == "output" ?
           dirname(normalized) :
           normalized
end

function _oos_structural_config(config)
    defaults = Dict{String, Any}(
        "north_sea" => false,
        "use_emission_cap" => false,
        "load_change_module" => false,
    )
    summary = Dict{String, Any}()
    for key in _OOS_INVESTMENT_COMPATIBILITY_KEYS
        if haskey(config, key)
            summary[key] = config[key]
        elseif haskey(defaults, key)
            summary[key] = defaults[key]
        else
            throw(ArgumentError(
                "Investment configuration is missing required setting '$key'",
            ))
        end
    end
    return summary
end

function _oos_summary_values(path::AbstractString)
    values = Dict{String, String}()
    isfile(path) || return values
    for line in eachline(path)
        occursin('=', line) || continue
        key, value = split(line, "="; limit = 2)
        values[strip(key)] = strip(value)
    end
    return values
end

function _oos_investment_config_file(run_dir::AbstractString)
    candidates = (
        joinpath(run_dir, "Input", "config.yaml"),
        joinpath(run_dir, "source_config.yaml"),
        joinpath(run_dir, "fixed_sample_config.yaml"),
        joinpath(run_dir, "config.yaml"),
    )
    match = findfirst(isfile, candidates)
    match === nothing && throw(ArgumentError(
        "Fixed-investment run has no staged or preserved source config: $run_dir",
    ))
    return candidates[match]
end

function _oos_reconstructed_investment_provenance(
    run_dir::AbstractString,
    capacity_metadata,
)
    config_file = _oos_investment_config_file(run_dir)
    config = YAML.load_file(config_file)
    manifest_file = joinpath(run_dir, "run_manifest.yaml")
    summary_file = joinpath(run_dir, "summary.txt")
    provenance_kind = "reconstructed_legacy_run"
    manifest_sha256 = nothing
    summary_sha256 = nothing

    if isfile(manifest_file)
        manifest = YAML.load_file(manifest_file)
        get(manifest, "status", nothing) == "complete" || throw(ArgumentError(
            "Fixed-investment run manifest is not complete: $manifest_file",
        ))
        oos = get(manifest, "out_of_sample", Dict{String, Any}())
        get(oos, "enabled", false) == false || throw(ArgumentError(
            "An OOS evaluation cannot be used as the source investment run: $run_dir",
        ))
        solution = get(manifest, "solution", nothing)
        solution isa AbstractDict || throw(ArgumentError(
            "Fixed-investment run manifest has no solution evidence: $manifest_file",
        ))
        get(solution, "termination_status", nothing) == "OPTIMAL" ||
            throw(ArgumentError(
                "Fixed-investment run manifest does not prove OPTIMAL termination",
            ))
        get(solution, "is_solved_and_feasible", false) == true ||
            throw(ArgumentError(
                "Fixed-investment run manifest does not prove a feasible solution",
            ))
        manifest_config_sha256 = get(manifest, "config_sha256", nothing)
        manifest_config_sha256 === nothing ||
            manifest_config_sha256 == _oos_sha256_file(config_file) ||
            throw(ArgumentError(
                "Fixed-investment source config does not match its run manifest",
            ))
        investment_result = get(manifest, "investment_result", nothing)
        if investment_result isa AbstractDict
            get(investment_result, "fixed_investments_sha256", nothing) ==
            capacity_metadata["sha256"] || throw(ArgumentError(
                "Fixed-investment tables do not match their run manifest fingerprint",
            ))
            provenance_kind = "verified_run_manifest"
        else
            provenance_kind = "reconstructed_manifest_run"
        end
        recorded_structure = get(manifest, "investment_context", nothing)
        recorded_structure === nothing ||
            recorded_structure == _oos_structural_config(config) ||
            throw(ArgumentError(
                "Fixed-investment structural config does not match its run manifest",
            ))
        manifest_sha256 = _oos_sha256_file(manifest_file)
    else
        summary = _oos_summary_values(summary_file)
        get(summary, "optimize", "") == "true" || throw(ArgumentError(
            "Legacy fixed-investment run does not prove optimize=true: $summary_file",
        ))
        get(summary, "termination_status", "") == "OPTIMAL" ||
            throw(ArgumentError(
                "Legacy fixed-investment run does not prove OPTIMAL termination: $summary_file",
            ))
        summary_sha256 = _oos_sha256_file(summary_file)
    end

    return Dict{String, Any}(
        "schema_version" => 1,
        "kind" => provenance_kind,
        "source_run" => run_dir,
        "source_config_file" => config_file,
        "source_config_sha256" => _oos_sha256_file(config_file),
        "structural_config" => _oos_structural_config(config),
        "fixed_investments_sha256" => capacity_metadata["sha256"],
        "run_manifest_file" => isfile(manifest_file) ? manifest_file : nothing,
        "run_manifest_sha256" => manifest_sha256,
        "summary_file" => isfile(summary_file) ? summary_file : nothing,
        "summary_sha256" => summary_sha256,
    )
end

function _oos_sidecar_investment_provenance(run_dir::AbstractString, capacity_metadata)
    sidecar_candidates = (
        joinpath(run_dir, "fixed_investment_provenance.yaml"),
        joinpath(_oos_output_dir(run_dir), "fixed_investment_provenance.yaml"),
    )
    match = findfirst(isfile, sidecar_candidates)
    match === nothing && return nothing
    sidecar_file = sidecar_candidates[match]
    sidecar = YAML.load_file(sidecar_file)
    sidecar isa AbstractDict || throw(ArgumentError(
        "Fixed-investment provenance sidecar must be a mapping: $sidecar_file",
    ))
    get(sidecar, "fixed_investments_sha256", nothing) ==
    capacity_metadata["sha256"] || throw(ArgumentError(
        "Fixed-investment provenance sidecar has the wrong table fingerprint",
    ))
    source_config = joinpath(dirname(sidecar_file), "source_config.yaml")
    isfile(source_config) || throw(ArgumentError(
        "Fixed-investment provenance sidecar is missing source_config.yaml: $run_dir",
    ))
    get(sidecar, "source_config_sha256", nothing) ==
    _oos_sha256_file(source_config) || throw(ArgumentError(
        "Preserved fixed-investment source config checksum mismatch",
    ))
    preserved_structure = _oos_structural_config(YAML.load_file(source_config))
    preserved_structure == sidecar["structural_config"] || throw(ArgumentError(
        "Preserved fixed-investment structural config mismatch",
    ))
    provenance =
        Dict{String, Any}(String(key) => value for (key, value) in sidecar)
    provenance["staged_provenance_file"] = sidecar_file
    provenance["staged_source_config_file"] = source_config
    return provenance
end

function _oos_fixed_investment_metadata(path::AbstractString)
    capacity_metadata = _oos_fixed_capacity_metadata(path)
    run_dir = _oos_investment_run_dir(path)
    provenance =
        _oos_sidecar_investment_provenance(run_dir, capacity_metadata)
    provenance === nothing && (
        provenance = _oos_reconstructed_investment_provenance(
            run_dir,
            capacity_metadata,
        )
    )
    metadata = copy(capacity_metadata)
    metadata["provenance"] = provenance
    return metadata
end

function validate_oos_fixed_investment_compatibility(
    fixed_metadata,
    execution_config,
)
    provenance = get(fixed_metadata, "provenance", nothing)
    provenance isa AbstractDict || throw(ArgumentError(
        "Fixed-investment metadata has no provenance mapping",
    ))
    source = get(provenance, "structural_config", nothing)
    source isa AbstractDict || throw(ArgumentError(
        "Fixed-investment provenance has no structural configuration",
    ))
    target = _oos_structural_config(execution_config)
    mismatches = String[]
    for key in _OOS_INVESTMENT_COMPATIBILITY_KEYS
        get(source, key, nothing) == target[key] || push!(
            mismatches,
            "$key=$(target[key]) (investment run: $(get(source, key, "missing")))",
        )
    end
    isempty(mismatches) || throw(ArgumentError(
        "OOS config is incompatible with the source investment run: " *
        join(mismatches, "; "),
    ))
    return Dict{String, Any}(
        "status" => "compatible",
        "required_equal" => collect(_OOS_INVESTMENT_COMPATIBILITY_KEYS),
        "allowed_operational_differences" =>
            collect(_OOS_ALLOWED_OPERATIONAL_CONFIG_DIFFERENCES),
        "source_structural_config" => source,
        "execution_structural_config" => target,
    )
end

function _write_oos_fixed_investment_provenance_files(
    source::AbstractString,
    target::AbstractString,
)
    metadata = _oos_fixed_investment_metadata(source)
    provenance = metadata["provenance"]
    source_config_file = get(provenance, "source_config_file", nothing)
    if !(source_config_file isa AbstractString && isfile(source_config_file))
        source_config_file =
            get(provenance, "staged_source_config_file", nothing)
    end
    source_config_file isa AbstractString &&
        isfile(source_config_file) || throw(ArgumentError(
        "Fixed-investment provenance has no readable source configuration",
    ))
    mkpath(target)
    staged_config = joinpath(target, "source_config.yaml")
    cp(source_config_file, staged_config; force = true)
    sidecar = Dict{String, Any}(
        String(key) => value for (key, value) in provenance
        if key ∉ ("staged_provenance_file", "staged_source_config_file")
    )
    sidecar["source_config_sha256"] = _oos_sha256_file(staged_config)
    sidecar["fixed_investments_sha256"] = metadata["sha256"]
    sidecar_file = joinpath(target, "fixed_investment_provenance.yaml")
    YAML.write_file(sidecar_file, sidecar)
    return (
        provenance_file = sidecar_file,
        source_config_file = staged_config,
        metadata = metadata,
    )
end

function stage_oos_fixed_investment_provenance(
    source::AbstractString,
    target::AbstractString,
)
    _write_oos_fixed_investment_provenance_files(source, target)
    return _oos_fixed_investment_metadata(target)
end
