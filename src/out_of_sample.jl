const _OOS_SCENARIO_FILENAMES = (
    "sloadRaw.csv",
    "maxRegHydroGenRaw.csv",
    "genCapAvailStochRaw.csv",
)

const _OOS_TREE_FILENAMES = (_OOS_SCENARIO_FILENAMES..., "sampling_key.csv")
const _OOS_EXPERIMENT_MANIFEST = "experiment.yaml"
const _OOS_EXECUTION_MANIFEST = "execution.yaml"

const _OOS_FIXED_INVESTMENT_FILENAMES = (
    ("genInvCap.csv",),
    ("transmissionInvCap.csv", "transmisionInvCap.csv"),
    ("storPWInvCap.csv",),
    ("storENInvCap.csv",),
    ("genInstalledCap.csv",),
    ("transmissionInstalledCap.csv",),
    ("storPWInstalledCap.csv",),
    ("storENInstalledCap.csv",),
)

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

function _oos_fixed_investment_output_dir(path::AbstractString)
    isdir(path) || throw(ArgumentError(
        "Fixed-investment directory does not exist: $path",
    ))
    for output_folder in ("Output", "output")
        output_dir = joinpath(path, output_folder)
        isdir(output_dir) && return output_dir
    end
    return path
end

function _oos_fixed_investment_source_files(path::AbstractString)
    output_dir = _oos_fixed_investment_output_dir(path)
    return map(_OOS_FIXED_INVESTMENT_FILENAMES) do aliases
        source = findfirst(filename -> isfile(joinpath(output_dir, filename)), aliases)
        source === nothing && throw(ArgumentError(
            "Fixed-investment directory is missing one of: $(join(aliases, ", "))",
        ))
        joinpath(output_dir, aliases[source])
    end
end

function _oos_fixed_investment_metadata(path::AbstractString)
    run_dir = abspath(normpath(path))
    output_dir = _oos_fixed_investment_output_dir(run_dir)
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

function _oos_queue_input_format(value)
    value in (:auto, :csv, :xlsx) || throw(ArgumentError(
        "Unsupported input format: $value. Expected :auto, :csv, or :xlsx.",
    ))
    return value
end

function _oos_shell_quote(value::AbstractString)
    isempty(value) && return "''"
    occursin(r"^[A-Za-z0-9_./:@%+=,-]+$", value) && return value
    return "'$(replace(value, "'" => "'\"'\"'"))'"
end

function _oos_command_display(working_directory::AbstractString, command)
    command_text = join((_oos_shell_quote(string(argument)) for argument in command), " ")
    return "cd $(_oos_shell_quote(working_directory)) && $command_text"
end

function _load_complete_oos_experiment(experiment_dir::AbstractString)
    manifest_file = joinpath(experiment_dir, _OOS_EXPERIMENT_MANIFEST)
    isfile(manifest_file) || throw(ArgumentError(
        "OOS experiment is missing experiment.yaml: $experiment_dir",
    ))
    manifest = YAML.load_file(manifest_file)
    manifest isa AbstractDict || throw(ArgumentError(
        "OOS experiment manifest must be a mapping: $manifest_file",
    ))
    get(manifest, "kind", nothing) == "oos_tree_experiment" || throw(ArgumentError(
        "Not an OOS tree experiment manifest: $manifest_file",
    ))
    get(manifest, "status", nothing) == "complete" || throw(ArgumentError(
        "OOS experiment must be complete before preparing execution: $manifest_file",
    ))

    for key in (
        "schema_version",
        "source_data_sha256",
        "source_config_sha256",
        "input_format",
        "seed_start",
        "num_trees",
        "trees",
    )
        haskey(manifest, key) || throw(ArgumentError(
            "OOS experiment manifest is missing required key: $key",
        ))
    end
    trees = manifest["trees"]
    trees isa AbstractVector || throw(ArgumentError(
        "OOS experiment trees must be a sequence: $manifest_file",
    ))
    length(trees) == manifest["num_trees"] || throw(ArgumentError(
        "OOS experiment tree count does not match num_trees: $manifest_file",
    ))
    return manifest_file, manifest
end

function _validated_oos_execution_trees(experiment_dir::AbstractString, manifest)
    input_format = Symbol(manifest["input_format"])
    trees = Dict{String, Any}[]
    for index in 1:manifest["num_trees"]
        entry = manifest["trees"][index]
        entry isa AbstractDict || throw(ArgumentError(
            "OOS experiment tree entry $index must be a mapping",
        ))
        expected_name = "oos_tree$index"
        expected_seed = manifest["seed_start"] + index - 1
        get(entry, "index", nothing) == index || throw(ArgumentError(
            "OOS experiment tree $index has an invalid index",
        ))
        get(entry, "name", nothing) == expected_name || throw(ArgumentError(
            "OOS experiment tree $index must be named $expected_name",
        ))
        get(entry, "seed", nothing) == expected_seed || throw(ArgumentError(
            "OOS experiment tree $index has an invalid seed",
        ))
        get(entry, "status", nothing) == "complete" || throw(ArgumentError(
            "OOS experiment tree $expected_name is not complete",
        ))

        tree_dir = joinpath(experiment_dir, expected_name)
        _validate_oos_experiment_tree(
            tree_dir,
            expected_seed,
            manifest["source_data_sha256"],
            manifest["source_config_sha256"],
            input_format,
        )
        push!(trees, Dict{String, Any}(
            "index" => index,
            "name" => expected_name,
            "seed" => expected_seed,
            "path" => tree_dir,
            "metadata_sha256" => _oos_sha256_file(joinpath(tree_dir, "metadata.yaml")),
        ))
    end
    return trees
end

function _validate_oos_execution_config(config_file::AbstractString, tree_dir::AbstractString)
    config = YAML.load_file(config_file)
    metadata = YAML.load_file(joinpath(tree_dir, "metadata.yaml"))
    tree_config = get(metadata, "config", nothing)
    tree_config isa AbstractDict || throw(ArgumentError(
        "OOS tree metadata has no valid config mapping: $tree_dir",
    ))
    for key in _OOS_TREE_CONFIG_KEYS
        key == "use_fixed_sample" && continue
        haskey(tree_config, key) || continue
        haskey(config, key) || throw(ArgumentError(
            "Execution config is missing OOS scenario setting '$key': $config_file",
        ))
        config[key] == tree_config[key] || throw(ArgumentError(
            "Execution config setting '$key' does not match the OOS trees: " *
            "$(config[key]) (expected $(tree_config[key]))",
        ))
    end
    return config
end

function _oos_execution_job(
    tree,
    julia_command::AbstractString,
    project_dir::AbstractString,
    runner_script::AbstractString,
    dataset_folder::AbstractString,
    config_file::AbstractString,
    input_format::Symbol,
    solver::AbstractString,
    fixed_investment_dir::AbstractString,
    results_root::AbstractString,
)
    tree_results_root = joinpath(results_root, tree["name"])
    command = String[
        julia_command,
        "--project=$project_dir",
        runner_script,
        dataset_folder,
        "--config=$config_file",
        "--format=$(string(input_format))",
        "--solver=$solver",
        "--seed=$(tree["seed"])",
        "--results=$tree_results_root",
        "--out-of-sample=true",
        "--fixed-investment-dir=$fixed_investment_dir",
        "--scenario-data-root=$(tree["path"])",
    ]
    return Dict{String, Any}(
        "index" => tree["index"],
        "tree" => tree["name"],
        "seed" => tree["seed"],
        "scenario_tree" => tree["path"],
        "scenario_metadata_sha256" => tree["metadata_sha256"],
        "status" => "pending",
        "scheduler_job_id" => nothing,
        "submitted_at_utc" => nothing,
        "started_at_utc" => nothing,
        "completed_at_utc" => nothing,
        "result_root" => tree_results_root,
        "result_dir" => nothing,
        "stdout_path" => nothing,
        "stderr_path" => nothing,
        "error" => nothing,
        "command" => command,
        "command_display" => _oos_command_display(project_dir, command),
    )
end

function _oos_execution_queue_status(jobs)
    statuses = Set(job["status"] for job in jobs)
    all(status == "complete" for status in statuses) && return "complete"
    "failed" in statuses && return "attention_required"
    "running" in statuses && return "running"
    "submitted" in statuses && return "submitted"
    return "ready"
end

function _validate_oos_execution_queue_spec(existing, expected)
    keys = (
        "schema_version",
        "kind",
        "experiment",
        "dataset",
        "config",
        "input_format",
        "solver",
        "fixed_investments",
        "runner",
        "results_root",
        "acceptance_criteria",
    )
    for key in keys
        haskey(existing, key) || throw(ArgumentError(
            "Existing OOS execution queue is missing required key: $key",
        ))
        existing[key] == expected[key] || throw(ArgumentError(
            "Existing OOS execution queue has a different $key specification",
        ))
    end
    return nothing
end

function _resume_oos_execution_jobs!(jobs, existing_jobs)
    existing_jobs isa AbstractVector || throw(ArgumentError(
        "Existing OOS execution jobs must be a sequence",
    ))
    length(existing_jobs) == length(jobs) || throw(ArgumentError(
        "Existing OOS execution queue has a different number of jobs",
    ))
    immutable_keys = (
        "index",
        "tree",
        "seed",
        "scenario_tree",
        "scenario_metadata_sha256",
        "result_root",
        "command",
        "command_display",
    )
    state_keys = (
        "status",
        "scheduler_job_id",
        "submitted_at_utc",
        "started_at_utc",
        "completed_at_utc",
        "result_dir",
        "stdout_path",
        "stderr_path",
        "error",
    )
    allowed_statuses = Set(("pending", "submitted", "running", "complete", "failed"))
    for index in eachindex(jobs)
        existing = existing_jobs[index]
        existing isa AbstractDict || throw(ArgumentError(
            "Existing OOS execution job $index must be a mapping",
        ))
        for key in immutable_keys
            get(existing, key, nothing) == jobs[index][key] || throw(ArgumentError(
                "Existing OOS execution job $index has a different $key",
            ))
        end
        status = get(existing, "status", nothing)
        status in allowed_statuses || throw(ArgumentError(
            "Existing OOS execution job $index has unsupported status: $status",
        ))
        for key in state_keys
            jobs[index][key] = get(existing, key, nothing)
        end
    end
    return jobs
end

"""
    prepare_oos_execution_queue(
        experiment_dir,
        fixed_investment_dir;
        dataset,
        config_file,
        results_root,
        input_format = :auto,
        solver = "HiGHS",
        queue_file = joinpath(experiment_dir, "execution.yaml"),
        julia_command = "julia",
        resume = true,
    )

Validate an OOS experiment and fixed-investment run, then write a resumable
execution queue without starting any processes.

Each queue job contains the exact argument vector and display command for the
current Julia runner. Existing job status and scheduler/result fields are
preserved when `resume = true`, provided that all immutable inputs and commands
still match. Returns the absolute queue-manifest path.
"""
function prepare_oos_execution_queue(
    experiment_dir::AbstractString,
    fixed_investment_dir::AbstractString;
    dataset::AbstractString,
    config_file::AbstractString,
    results_root::AbstractString,
    input_format::Symbol = :auto,
    solver::AbstractString = "HiGHS",
    queue_file::AbstractString = joinpath(experiment_dir, _OOS_EXECUTION_MANIFEST),
    julia_command::AbstractString = "julia",
    resume::Bool = true,
)
    target_experiment = abspath(normpath(experiment_dir))
    fixed_investments = abspath(normpath(fixed_investment_dir))
    target_results = abspath(normpath(results_root))
    target_queue = abspath(normpath(queue_file))
    project_dir = abspath(pkgdir(@__MODULE__))
    runner_script = joinpath(project_dir, "scripts", "run_julia_empire.jl")
    source_config = isabspath(config_file) ?
                    abspath(normpath(config_file)) :
                    abspath(normpath(joinpath(project_dir, config_file)))
    dataset_folder = isabspath(dataset) ?
                     abspath(normpath(dataset)) :
                     abspath(normpath(joinpath(project_dir, "data", dataset)))
    format_value = _oos_queue_input_format(input_format)

    solver in ("HiGHS", "Gurobi") || throw(ArgumentError(
        "Unsupported OOS execution solver: $solver. Expected HiGHS or Gurobi.",
    ))
    isempty(strip(julia_command)) && throw(ArgumentError("julia_command cannot be empty"))
    isfile(source_config) || throw(ArgumentError(
        "Execution config file does not exist: $source_config",
    ))
    isdir(dataset_folder) || throw(ArgumentError(
        "Execution dataset folder does not exist: $dataset_folder",
    ))
    isfile(runner_script) || throw(ArgumentError("Julia runner does not exist: $runner_script"))

    experiment_manifest_file, experiment =
        _load_complete_oos_experiment(target_experiment)
    string(format_value) == experiment["input_format"] || throw(ArgumentError(
        "Execution input format does not match the OOS experiment: " *
        "$(string(format_value)) (expected $(experiment["input_format"]))",
    ))
    dataset_sha256 = _oos_directory_sha256(dataset_folder)
    dataset_sha256 == experiment["source_data_sha256"] || throw(ArgumentError(
        "Execution dataset contents do not match the dataset used to generate the OOS trees",
    ))
    trees = _validated_oos_execution_trees(target_experiment, experiment)
    _validate_oos_execution_config(source_config, first(trees)["path"])
    fixed_metadata = _oos_fixed_investment_metadata(fixed_investments)

    created_at = string(now(UTC), "Z")
    jobs = [
        _oos_execution_job(
            tree,
            julia_command,
            project_dir,
            runner_script,
            dataset_folder,
            source_config,
            format_value,
            solver,
            fixed_investments,
            target_results,
        ) for tree in trees
    ]
    queue = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_execution_queue",
        "status" => "ready",
        "created_at_utc" => created_at,
        "updated_at_utc" => created_at,
        "experiment" => Dict{String, Any}(
            "dir" => target_experiment,
            "manifest_file" => experiment_manifest_file,
            "source_data_sha256" => experiment["source_data_sha256"],
            "source_config_sha256" => experiment["source_config_sha256"],
            "seed_start" => experiment["seed_start"],
            "num_trees" => experiment["num_trees"],
        ),
        "dataset" => Dict{String, Any}(
            "folder" => dataset_folder,
            "sha256" => dataset_sha256,
        ),
        "config" => Dict{String, Any}(
            "file" => source_config,
            "sha256" => _oos_sha256_file(source_config),
        ),
        "input_format" => string(format_value),
        "solver" => solver,
        "fixed_investments" => fixed_metadata,
        "runner" => Dict{String, Any}(
            "julia_command" => julia_command,
            "project_dir" => project_dir,
            "script" => runner_script,
            "script_sha256" => _oos_sha256_file(runner_script),
        ),
        "results_root" => target_results,
        "acceptance_criteria" => Dict{String, Any}(
            "run_manifest_status" => "complete",
            "investments_fixed" => true,
            "scenario_checksums_verified" => true,
            "termination_status" => "OPTIMAL",
        ),
        "jobs" => jobs,
    )

    if ispath(target_queue)
        isfile(target_queue) || throw(ArgumentError(
            "OOS execution queue path exists but is not a file: $target_queue",
        ))
        resume || throw(ArgumentError(
            "OOS execution queue already exists and resume=false: $target_queue",
        ))
        existing = YAML.load_file(target_queue)
        existing isa AbstractDict || throw(ArgumentError(
            "Existing OOS execution queue must be a mapping: $target_queue",
        ))
        _validate_oos_execution_queue_spec(existing, queue)
        _resume_oos_execution_jobs!(jobs, get(existing, "jobs", nothing))
        queue["created_at_utc"] = get(existing, "created_at_utc", created_at)
    end

    queue["status"] = _oos_execution_queue_status(jobs)
    queue["updated_at_utc"] = string(now(UTC), "Z")
    _write_oos_experiment_manifest(target_queue, queue)
    return target_queue
end

"""
    fix_investments_from_results!(
        model,
        sets,
        periods,
        result_dir;
        fix_installed_capacities = true,
    )

Read strategic capacity results from a previous run and fix the matching JuMP
variables in `model`.

`result_dir` may point either to a run directory or directly to its `Output`
or `output` subdirectory. By default, both investment and installed-capacity
variables are fixed. Set `fix_installed_capacities = false` to fix only the
investment variables.
"""
function fix_investments_from_results!(
    model::JuMP.Model,
    sets,
    periods::TimeStructure,
    result_dir::AbstractString;
    fix_installed_capacities::Bool = true,
)
    output_dir = _oos_output_dir(result_dir)
    strategic_periods = collect(enumerate(strat_periods(periods)))

    _fix_generator_capacity!(
        model[:genInvCap],
        sets,
        strategic_periods,
        _read_generator_capacity(output_dir, "genInvCap.csv", "genInvCap"),
        "genInvCap",
    )
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
            _read_storage_capacity(
                output_dir,
                "storPWInstalledCap.csv",
                "storPWInstalledCap",
            ),
            "storPWInstalledCap",
        )
        _fix_storage_capacity!(
            model[:storENInstalledCap],
            sets,
            strategic_periods,
            _read_storage_capacity(
                output_dir,
                "storENInstalledCap.csv",
                "storENInstalledCap",
            ),
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
        "Could not find any of these files in $output_dir: $(join(filenames, ", "))",
    ))
end

_oos_float_value(value) = value isa Real ? Float64(value) : parse(Float64, strip(string(value)))
_oos_int_value(value) = value isa Integer ? Int(value) : parse(Int, strip(string(value)))
_oos_string_value(value) = strip(string(value))

function _oos_row_value(row, columns)
    available = Set(string.(propertynames(row)))
    for column in columns
        column in available && return getproperty(row, Symbol(column))
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
    value = get(values, key, nothing)
    value === nothing && throw(ArgumentError("Missing fixed OOS value for $table_name at key $key"))
    return value
end

function _fix_generator_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()
    for (period_index, strategic_period) in strategic_periods
        for (node, generator) in node_generators(sets)
            key = (node, generator, period_index)
            JuMP.fix(
                variable[node, generator, strategic_period],
                _fixed_value(values, key, table_name);
                force = true,
            )
            push!(used, key)
        end
    end
    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_transmission_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()
    for (period_index, strategic_period) in strategic_periods
        for (from_node, to_node) in bidir_arcs(sets)
            key = (from_node, to_node, period_index)
            JuMP.fix(
                variable[from_node, to_node, strategic_period],
                _fixed_value(values, key, table_name);
                force = true,
            )
            push!(used, key)
        end
    end
    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _fix_storage_capacity!(variable, sets, strategic_periods, values, table_name)
    used = Set{Tuple{String, String, Int}}()
    for (period_index, strategic_period) in strategic_periods
        for (node, storage) in node_storages(sets)
            key = (node, storage, period_index)
            JuMP.fix(
                variable[node, storage, strategic_period],
                _fixed_value(values, key, table_name);
                force = true,
            )
            push!(used, key)
        end
    end
    _check_no_extra_oos_keys(values, used, table_name)
    return nothing
end

function _check_no_extra_oos_keys(values, used, table_name)
    extra = setdiff(Set(keys(values)), used)
    isempty(extra) && return nothing

    preview = collect(extra)[1:min(end, 10)]
    throw(ArgumentError(
        "Fixed OOS file for $table_name contains keys not present in the current model. " *
        "First extra keys: $preview",
    ))
end
