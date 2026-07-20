const _OOS_SCENARIO_FILENAMES = (
    "sloadRaw.csv",
    "maxRegHydroGenRaw.csv",
    "genCapAvailStochRaw.csv",
)

const _OOS_TREE_FILENAMES = (_OOS_SCENARIO_FILENAMES..., "sampling_key.csv")

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
        "source_data_sha256" => _oos_directory_sha256(data_folder),
        "source_config_file" => config_file,
        "source_config_sha256" => _oos_sha256_file(config_file),
        "config" => config_values,
        "files" => _oos_tree_file_metadata(scenario_dir),
    )
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

    target_parent = dirname(target_tree)
    mkpath(target_parent)
    mktempdir(target_parent; prefix = ".oos-tree-") do workspace
        staged_data = joinpath(workspace, "data")
        staged_tree = joinpath(workspace, "tree")
        staged_scenario_dir = joinpath(staged_tree, "ScenarioData")

        cp(source_data, staged_data)
        generate_scenarios(
            source_config,
            staged_data;
            input_format,
            scenario_rng = MersenneTwister(seed_value),
            progress,
        )

        generated_scenario_dir = joinpath(staged_data, "ScenarioData")
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
            source_config,
            source_data,
            target_tree,
            staged_scenario_dir,
            input_format,
            seed_value,
        )
        YAML.write_file(joinpath(staged_tree, "metadata.yaml"), metadata)
        mv(staged_tree, target_tree)
    end

    return target_tree
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
