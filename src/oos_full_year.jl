const _OOS_FULL_YEAR_HOURS = 8760
const _OOS_FULL_YEAR_CHUNK_HOURS = 365
const _OOS_FULL_YEAR_TREE_COUNT = div(_OOS_FULL_YEAR_HOURS, _OOS_FULL_YEAR_CHUNK_HOURS)
const _OOS_FULL_YEAR_DUMMY_PEAK_HOURS = 1
const _OOS_FULL_YEAR_CONFIG = "full_year_config.yaml"
const _OOS_CHRONOLOGICAL_MODE = "chronological_full_year"
const _OOS_CHRONOLOGICAL_FIXTURE_MODE = "chronological_test_fixture"

function _internalempire_full_year_chunks()
    _OOS_FULL_YEAR_TREE_COUNT * _OOS_FULL_YEAR_CHUNK_HOURS == _OOS_FULL_YEAR_HOURS ||
        error("Full-year hours must be exactly divisible into InternalEMPIRE chunks")
    return [
        ((tree_index - 1) * _OOS_FULL_YEAR_CHUNK_HOURS + 1):(tree_index * _OOS_FULL_YEAR_CHUNK_HOURS) for
        tree_index in 1:_OOS_FULL_YEAR_TREE_COUNT
    ]
end

function _internalempire_full_year_config(source_config)
    config = deepcopy(source_config)
    config["number_of_scenarios"] = 1
    config["regular_seasons"] = ["winter"]
    config["length_of_regular_season"] = _OOS_FULL_YEAR_CHUNK_HOURS
    config["n_peak_seasons"] = 1
    config["len_peak_season"] = _OOS_FULL_YEAR_DUMMY_PEAK_HOURS
    config["operational_hours_per_year"] = _OOS_FULL_YEAR_HOURS
    config["use_scenario_generation"] = false
    config["use_fixed_sample"] = false
    return config
end

function _chronological_oos_config(source_config, operational_hours::Int)
    operational_hours > 0 || throw(ArgumentError("operational_hours must be positive"))
    config = deepcopy(source_config)
    config["number_of_scenarios"] = 1
    config["regular_seasons"] = ["full_year"]
    config["length_of_regular_season"] = operational_hours
    config["n_peak_seasons"] = 0
    config["len_peak_season"] = 0
    config["operational_hours_per_year"] = operational_hours
    config["use_scenario_generation"] = false
    config["use_fixed_sample"] = false
    return config
end

function _chronological_year_indices(
    table::RawScenarioTable,
    sample_year::Int,
    operational_hours::Int;
    require_full_year::Bool,
    source_name::AbstractString,
)
    require_full_year && daysinyear(Date(sample_year, 1, 1)) != 365 && throw(ArgumentError(
        "Full-year OOS requires a non-leap sample year; $sample_year has " *
        "$(daysinyear(Date(sample_year, 1, 1))) days",
    ))

    year_indices = _year_indices(table, sample_year)
    expected_rows = require_full_year ? _OOS_FULL_YEAR_HOURS : operational_hours
    if require_full_year
        length(year_indices) == expected_rows || throw(ArgumentError(
            "$source_name must contain exactly $expected_rows rows for non-leap year " *
            "$sample_year; found $(length(year_indices))",
        ))
    else
        length(year_indices) >= expected_rows || throw(ArgumentError(
            "$source_name needs at least $expected_rows rows for chronological fixture " *
            "$sample_year; found $(length(year_indices))",
        ))
    end

    expected_start = DateTime(sample_year, 1, 1)
    if require_full_year
        # InternalEMPIRE filters by year and slices the resulting dataframe by
        # row position without sorting. Preserve that behavior even when one
        # source (notably hydroror.csv) stores a complete year out of timestamp
        # order. Validate completeness without changing the row order.
        timestamps = Set(table.timestamps[year_indices])
        length(timestamps) == expected_rows || throw(ArgumentError(
            "$source_name contains duplicate timestamps for $sample_year",
        ))
        for offset in 0:(expected_rows - 1)
            expected_start + Hour(offset) in timestamps || throw(ArgumentError(
                "$source_name is missing timestamp $(expected_start + Hour(offset))",
            ))
        end
    else
        sort!(year_indices; by = index -> table.timestamps[index])
        year_indices = year_indices[1:expected_rows]
        for (offset, index) in enumerate(year_indices)
            expected_timestamp = expected_start + Hour(offset - 1)
            table.timestamps[index] == expected_timestamp || throw(ArgumentError(
                "$source_name is not a complete ordered hourly chronology for $sample_year: " *
                "row $offset has $(table.timestamps[index]), expected $expected_timestamp",
            ))
        end
    end
    return year_indices
end

function _raw_selection_metadata(
    path::AbstractString,
    table::RawScenarioTable,
    indices;
    selection_semantics::AbstractString,
)
    timestamps = table.timestamps[indices]
    return Dict{String, Any}(
        "sha256" => _oos_sha256_file(path),
        "selected_rows" => length(indices),
        "first_timestamp" => string(first(timestamps)),
        "last_timestamp" => string(last(timestamps)),
        "timestamps_ordered" => issorted(timestamps),
        "non_hourly_row_steps" => count(!=(Hour(1)), diff(timestamps)),
        "selection_semantics" => String(selection_semantics),
    )
end

function _chronological_raw_sources(
    data_folder::AbstractString,
    config,
    sets,
    sample_year::Int,
    operational_hours::Int;
    require_full_year::Bool,
)
    dateformat = _python_dateformat(get(config, "time_format", "%d/%m/%Y %H:%M"))
    load_path = _required_scenario_csv(data_folder, "electricload.csv")
    hydro_path = _required_scenario_csv(data_folder, "hydroseasonal.csv")
    load_table = _read_raw_scenario_table(load_path, dateformat)
    hydro_table = _read_raw_scenario_table(hydro_path, dateformat)
    generator_sources = _raw_generator_sources(data_folder, dateformat, sets)

    load_indices = _chronological_year_indices(
        load_table,
        sample_year,
        operational_hours;
        require_full_year,
        source_name = "electricload.csv",
    )
    hydro_indices = _chronological_year_indices(
        hydro_table,
        sample_year,
        operational_hours;
        require_full_year,
        source_name = "hydroseasonal.csv",
    )
    generator_indices = Dict{String, Vector{Int}}()
    for (generator, table) in generator_sources
        generator_indices[generator] = _chronological_year_indices(
            table,
            sample_year,
            operational_hours;
            require_full_year,
            source_name = "$generator raw scenario data",
        )
    end

    if !require_full_year
        reference_timestamps = load_table.timestamps[load_indices]
        hydro_table.timestamps[hydro_indices] == reference_timestamps || throw(ArgumentError(
            "hydroseasonal.csv timestamps do not match electricload.csv for $sample_year",
        ))
        for (generator, table) in generator_sources
            table.timestamps[generator_indices[generator]] == reference_timestamps ||
                throw(ArgumentError(
                    "$generator timestamps do not match electricload.csv for $sample_year",
                ))
        end
    end

    raw_file_selections = Dict{String, Any}(
        "electricload.csv" => (table = load_table, indices = load_indices),
        "hydroseasonal.csv" => (table = hydro_table, indices = hydro_indices),
    )
    generator_filenames = Dict(
        "Solar" => "solar.csv",
        "Windonshore" => "windonshore.csv",
        "Windoffshore" => "windoffshore.csv",
        "Windoffshoregrounded" => "windoffshore.csv",
        "Windoffshorefloating" => "windoffshore.csv",
        "Hydrorun-of-the-river" => "hydroror.csv",
    )
    for (generator, table) in generator_sources
        filename = generator_filenames[generator]
        get!(
            raw_file_selections,
            filename,
            (table = table, indices = generator_indices[generator]),
        )
    end
    raw_filenames = (
        "electricload.csv",
        "hydroseasonal.csv",
        "solar.csv",
        "windonshore.csv",
        "windoffshore.csv",
        "hydroror.csv",
    )
    selection_semantics = require_full_year ?
                          "internalempire_filtered_source_row_order" :
                          "timestamp_sorted_fixture"
    raw_metadata = Dict{String, Any}()
    for filename in raw_filenames
        path = joinpath(data_folder, "ScenarioData", filename)
        selection = get(raw_file_selections, filename, nothing)
        raw_metadata[filename] = selection === nothing ? Dict{String, Any}(
            "sha256" => _oos_sha256_file(path),
            "selected_rows" => 0,
            "used_by_model" => false,
        ) : _raw_selection_metadata(
            path,
            selection.table,
            selection.indices;
            selection_semantics,
        )
    end

    return (;
        load_table,
        hydro_table,
        generator_sources,
        load_indices,
        hydro_indices,
        generator_indices,
        raw_file_selections,
        raw_metadata,
    )
end

function _internalempire_raw_chunk(raw, chunk_index::Int)
    chunks = _internalempire_full_year_chunks()
    chunk_index in eachindex(chunks) || throw(ArgumentError(
        "Full-year OOS chunk index must be between 1 and $(length(chunks)); got $chunk_index",
    ))
    chunk = chunks[chunk_index]
    load_indices = raw.load_indices[chunk]
    hydro_indices = raw.hydro_indices[chunk]
    generator_indices = Dict(
        generator => indices[chunk] for (generator, indices) in raw.generator_indices
    )
    raw_file_selections = Dict(
        filename => (table = selection.table, indices = selection.indices[chunk]) for
        (filename, selection) in raw.raw_file_selections
    )
    raw_metadata = Dict{String, Any}()
    for (filename, source) in raw.raw_metadata
        selection = get(raw_file_selections, filename, nothing)
        if selection === nothing
            raw_metadata[filename] = Dict{String, Any}(source)
        else
            timestamps = selection.table.timestamps[selection.indices]
            raw_metadata[filename] = merge(
                Dict{String, Any}(source),
                Dict{String, Any}(
                    "selected_rows" => _OOS_FULL_YEAR_CHUNK_HOURS,
                    "source_year_rows" => _OOS_FULL_YEAR_HOURS,
                    "first_timestamp" => string(first(timestamps)),
                    "last_timestamp" => string(last(timestamps)),
                    "timestamps_ordered" => issorted(timestamps),
                    "non_hourly_row_steps" => count(!=(Hour(1)), diff(timestamps)),
                ),
            )
        end
    end
    return merge(
        raw,
        (; load_indices, hydro_indices, generator_indices, raw_file_selections, raw_metadata),
    )
end

function _write_chronological_scenario_csvs!(
    scenario_dir::AbstractString,
    raw,
    sets,
    strategic_period_count::Int,
    sample_year::Int,
    ;
    season::AbstractString = "full_year",
    sample_hour::Int = 0,
    include_internalempire_dummy_peak::Bool = false,
)
    load_columns = _node_columns(raw.load_table, sets)
    hydro_columns = _node_columns(raw.hydro_table, sets)
    isempty(load_columns) && throw(ArgumentError(
        "electricload.csv has no columns matching the model node set",
    ))
    generator_columns = Dict(
        generator => _generator_columns(table, generator, sets) for
        (generator, table) in raw.generator_sources
    )
    mkpath(scenario_dir)
    _write_csv_table(
        joinpath(scenario_dir, "sloadRaw.csv"),
        ("Node", "Operationalhour", "Scenario", "Period", "ElectricLoadRaw_in_MW"),
    ) do io
        for strategic_index in 1:strategic_period_count
            for (column, node) in load_columns
                source = raw.load_table.values[column]
                for (hour, index) in enumerate(raw.load_indices)
                    _write_csv_row(io, (
                        node,
                        hour,
                        "scenario1",
                        strategic_index,
                        _normalized_scenario_value(source[index]),
                    ))
                end
                include_internalempire_dummy_peak && _write_csv_row(io, (
                    node,
                    _OOS_FULL_YEAR_CHUNK_HOURS + 1,
                    "scenario1",
                    strategic_index,
                    0.0,
                ))
            end
        end
    end
    _write_csv_table(
        joinpath(scenario_dir, "maxRegHydroGenRaw.csv"),
        (
            "Node",
            "Period",
            "Season",
            "Operationalhour",
            "Scenario",
            "HydroGeneratorMaxSeasonalProduction",
        ),
    ) do io
        for strategic_index in 1:strategic_period_count
            for (column, node) in hydro_columns
                source = raw.hydro_table.values[column]
                for (hour, index) in enumerate(raw.hydro_indices)
                    _write_csv_row(io, (
                        node,
                        strategic_index,
                        season,
                        hour,
                        "scenario1",
                        _normalized_scenario_value(source[index]),
                    ))
                end
                include_internalempire_dummy_peak && _write_csv_row(io, (
                    node,
                    strategic_index,
                    "peak1",
                    _OOS_FULL_YEAR_CHUNK_HOURS + 1,
                    "scenario1",
                    1.0,
                ))
            end
        end
    end
    _write_csv_table(
        joinpath(scenario_dir, "genCapAvailStochRaw.csv"),
        (
            "Node",
            "IntermitentGenerators",
            "Operationalhour",
            "Scenario",
            "Period",
            "GeneratorStochasticAvailabilityRaw",
        ),
    ) do io
        for strategic_index in 1:strategic_period_count
            for (generator, table) in raw.generator_sources
                source_indices = raw.generator_indices[generator]
                for (column, node_generators) in generator_columns[generator]
                    source = table.values[column]
                    for (node, node_generator) in node_generators
                        for (hour, index) in enumerate(source_indices)
                            _write_csv_row(io, (
                                node,
                                node_generator,
                                hour,
                                "scenario1",
                                strategic_index,
                                _normalized_scenario_value(source[index]),
                            ))
                        end
                        include_internalempire_dummy_peak && _write_csv_row(io, (
                            node,
                            node_generator,
                            _OOS_FULL_YEAR_CHUNK_HOURS + 1,
                            "scenario1",
                            strategic_index,
                            0.0,
                        ))
                    end
                end
            end
        end
    end
    sampling_rows = [
        (
            Period = strategic_index,
            Scenario = 1,
            Season = String(season),
            Year = sample_year,
            Month = 1,
            Hour = sample_hour,
        ) for strategic_index in 1:strategic_period_count
    ]
    _write_csv_rows(joinpath(scenario_dir, "sampling_key.csv"), sampling_rows)
    return nothing
end

function _chronological_tree_metadata(
    execution_config,
    execution_config_file::AbstractString,
    generation_config_file::AbstractString,
    source_data::AbstractString,
    source_data_sha256::AbstractString,
    tree_dir::AbstractString,
    scenario_dir::AbstractString,
    input_format::Symbol,
    seed::Int,
    sample_year::Int,
    operational_hours::Int,
    evaluation_mode::AbstractString,
    raw_metadata,
    ;
    chunk_index::Union{Nothing, Int} = nothing,
)
    config_values = Dict{String, Any}()
    for key in _OOS_TREE_CONFIG_KEYS
        haskey(execution_config, key) && (config_values[key] = execution_config[key])
    end
    chronology = if chunk_index === nothing
        Dict{String, Any}(
            "formulation" => "single_chronology",
            "operational_hours" => operational_hours,
            "representative_periods" => 1,
            "operational_scenarios" => 1,
            "expected_hour_multiplicity" => 1,
            "dummy_peak" => false,
            "storage_cycle_boundaries_per_strategic_period" => 1,
        )
    else
        chunk = _internalempire_full_year_chunks()[chunk_index]
        Dict{String, Any}(
            "formulation" => "internalempire_24x365",
            "tree_index" => chunk_index,
            "tree_count" => _OOS_FULL_YEAR_TREE_COUNT,
            "source_hour_start" => first(chunk),
            "source_hour_end" => last(chunk),
            "source_hours" => length(chunk),
            "model_operational_hours" =>
                _OOS_FULL_YEAR_CHUNK_HOURS + _OOS_FULL_YEAR_DUMMY_PEAK_HOURS,
            "representative_periods" => 2,
            "operational_scenarios" => 1,
            "winter_hour_multiplicity" =>
                (_OOS_FULL_YEAR_HOURS - _OOS_FULL_YEAR_DUMMY_PEAK_HOURS) /
                _OOS_FULL_YEAR_CHUNK_HOURS,
            "dummy_peak" => true,
            "dummy_peak_hours" => _OOS_FULL_YEAR_DUMMY_PEAK_HOURS,
            "dummy_peak_results_ignored" => true,
            "storage_cycle_boundaries_per_strategic_period" => 2,
        )
    end
    return Dict{String, Any}(
        "schema_version" => 2,
        "generator" => "OpenEMPIRE.prepare_full_year_oos_experiment",
        "evaluation_mode" => String(evaluation_mode),
        "created_at_utc" => string(now(UTC), "Z"),
        "julia_version" => string(VERSION),
        "openempire_version" => string(pkgversion(@__MODULE__)),
        "tree" => basename(tree_dir),
        "tree_dir" => tree_dir,
        "seed" => seed,
        "sample_year" => sample_year,
        "chronology" => chronology,
        "input_format" => string(input_format),
        "source_data_folder" => source_data,
        "source_data_sha256" => source_data_sha256,
        "source_config_file" => execution_config_file,
        "source_config_sha256" => _oos_sha256_file(execution_config_file),
        "generation_source_config_file" => generation_config_file,
        "generation_source_config_sha256" => _oos_sha256_file(generation_config_file),
        "config" => config_values,
        "raw_sources" => raw_metadata,
        "files" => _oos_tree_file_metadata(scenario_dir),
    )
end

function _generate_chronological_oos_tree(
    execution_config,
    execution_config_file::AbstractString,
    generation_config_file::AbstractString,
    source_data::AbstractString,
    source_data_sha256::AbstractString,
    target_tree::AbstractString,
    sets;
    input_format::Symbol,
    seed::Int,
    sample_year::Int,
    operational_hours::Int,
    require_full_year::Bool,
    chunk_index::Union{Nothing, Int} = nothing,
)
    ispath(target_tree) && throw(ArgumentError("OOS tree already exists: $target_tree"))
    horizon = Int(execution_config["forecast_horizon_year"])
    strategic_duration = Int(execution_config["leap_years_investment"])
    strategic_period_count = round(Int, (horizon - 2020) / strategic_duration)
    strategic_period_count > 0 || throw(ArgumentError(
        "Chronological OOS config must contain at least one strategic period",
    ))
    full_raw = _chronological_raw_sources(
        source_data,
        execution_config,
        sets,
        sample_year,
        operational_hours;
        require_full_year,
    )
    raw = chunk_index === nothing ? full_raw : _internalempire_raw_chunk(full_raw, chunk_index)
    evaluation_mode = require_full_year ?
                      _OOS_CHRONOLOGICAL_MODE : _OOS_CHRONOLOGICAL_FIXTURE_MODE

    parent = dirname(target_tree)
    mkpath(parent)
    mktempdir(parent; prefix = ".oos-chronological-") do workspace
        staged_tree = joinpath(workspace, "tree")
        scenario_dir = joinpath(staged_tree, "ScenarioData")
        mkpath(scenario_dir)
        _write_chronological_scenario_csvs!(
            scenario_dir,
            raw,
            sets,
            strategic_period_count,
            sample_year,
            ;
            season = chunk_index === nothing ? "full_year" : "winter",
            sample_hour = chunk_index === nothing ? 0 : first(
                _internalempire_full_year_chunks()[chunk_index],
            ) - 1,
            include_internalempire_dummy_peak = chunk_index !== nothing,
        )
        metadata = _chronological_tree_metadata(
            execution_config,
            execution_config_file,
            generation_config_file,
            source_data,
            source_data_sha256,
            target_tree,
            scenario_dir,
            input_format,
            seed,
            sample_year,
            operational_hours,
            evaluation_mode,
            raw.raw_metadata,
            ;
            chunk_index,
        )
        YAML.write_file(joinpath(staged_tree, "metadata.yaml"), metadata)
        mv(staged_tree, target_tree)
    end
    return target_tree
end

function _validate_chronological_oos_metadata(metadata, context::AbstractString)
    chronology = get(metadata, "chronology", nothing)
    chronology isa AbstractDict || throw(ArgumentError(
        "Chronological OOS tree has no chronology metadata: $context",
    ))
    config = get(metadata, "config", nothing)
    config isa AbstractDict || throw(ArgumentError(
        "Chronological OOS tree has no configuration metadata: $context",
    ))
    formulation = get(chronology, "formulation", "single_chronology")
    expected_config = if formulation == "internalempire_24x365"
        tree_index = get(chronology, "tree_index", nothing)
        tree_index isa Integer && tree_index in 1:_OOS_FULL_YEAR_TREE_COUNT ||
            throw(ArgumentError("Full-year OOS tree has an invalid tree index: $context"))
        chunk = _internalempire_full_year_chunks()[tree_index]
        expected_chronology = Dict{String, Any}(
            "tree_count" => _OOS_FULL_YEAR_TREE_COUNT,
            "source_hour_start" => first(chunk),
            "source_hour_end" => last(chunk),
            "source_hours" => _OOS_FULL_YEAR_CHUNK_HOURS,
            "model_operational_hours" =>
                _OOS_FULL_YEAR_CHUNK_HOURS + _OOS_FULL_YEAR_DUMMY_PEAK_HOURS,
            "representative_periods" => 2,
            "operational_scenarios" => 1,
            "winter_hour_multiplicity" =>
                (_OOS_FULL_YEAR_HOURS - _OOS_FULL_YEAR_DUMMY_PEAK_HOURS) /
                _OOS_FULL_YEAR_CHUNK_HOURS,
            "dummy_peak" => true,
            "dummy_peak_hours" => _OOS_FULL_YEAR_DUMMY_PEAK_HOURS,
            "dummy_peak_results_ignored" => true,
            "storage_cycle_boundaries_per_strategic_period" => 2,
        )
        for (key, expected) in expected_chronology
            get(chronology, key, nothing) == expected || throw(ArgumentError(
                "Full-year OOS tree has invalid chronology setting '$key': " *
                "$(get(chronology, key, nothing)) (expected $expected)",
            ))
        end
        Dict{String, Any}(
            "number_of_scenarios" => 1,
            "regular_seasons" => ["winter"],
            "length_of_regular_season" => _OOS_FULL_YEAR_CHUNK_HOURS,
            "n_peak_seasons" => 1,
            "len_peak_season" => _OOS_FULL_YEAR_DUMMY_PEAK_HOURS,
            "operational_hours_per_year" => _OOS_FULL_YEAR_HOURS,
            "use_scenario_generation" => false,
            "use_fixed_sample" => false,
        )
    elseif formulation == "single_chronology"
        operational_hours = get(chronology, "operational_hours", nothing)
        operational_hours isa Integer && operational_hours > 0 || throw(ArgumentError(
            "Chronological OOS tree has an invalid operational-hour count: $context",
        ))
        get(chronology, "expected_hour_multiplicity", nothing) == 1 ||
            throw(ArgumentError(
                "Chronological OOS tree does not declare unit hour multiplicity: $context",
            ))
        get(chronology, "storage_cycle_boundaries_per_strategic_period", nothing) == 1 ||
            throw(ArgumentError(
                "Chronological OOS tree has an unexpected storage-cycle boundary count: $context",
            ))
        get(chronology, "representative_periods", nothing) == 1 || throw(ArgumentError(
            "Chronological OOS tree must contain exactly one representative period: $context",
        ))
        get(chronology, "operational_scenarios", nothing) == 1 || throw(ArgumentError(
            "Chronological OOS tree must contain exactly one operational scenario: $context",
        ))
        get(chronology, "dummy_peak", nothing) == false || throw(ArgumentError(
            "Chronological OOS tree must not contain a dummy peak: $context",
        ))
        Dict{String, Any}(
            "number_of_scenarios" => 1,
            "regular_seasons" => ["full_year"],
            "length_of_regular_season" => operational_hours,
            "n_peak_seasons" => 0,
            "len_peak_season" => 0,
            "operational_hours_per_year" => operational_hours,
            "use_scenario_generation" => false,
            "use_fixed_sample" => false,
        )
    else
        throw(ArgumentError("Unknown chronological OOS formulation '$formulation': $context"))
    end
    for (key, expected) in expected_config
        get(config, key, nothing) == expected || throw(ArgumentError(
            "Chronological OOS tree has invalid config setting '$key': " *
            "$(get(config, key, nothing)) (expected $expected)",
        ))
    end
    return Int(expected_config["operational_hours_per_year"])
end

function _validate_chronological_oos_tree(
    tree_dir::AbstractString,
    seed::Int,
    sample_year::Int,
    data_sha256::AbstractString,
    config_sha256::AbstractString,
    input_format::Symbol,
    evaluation_mode::AbstractString,
    operational_hours::Int,
    ;
    expected_chunk_index::Union{Nothing, Int} = nothing,
)
    metadata = _validate_oos_experiment_tree(
        tree_dir,
        seed,
        data_sha256,
        config_sha256,
        input_format,
    )
    get(metadata, "evaluation_mode", nothing) == evaluation_mode || throw(ArgumentError(
        "Chronological OOS tree has an unexpected evaluation_mode: $tree_dir",
    ))
    get(metadata, "sample_year", nothing) == sample_year || throw(ArgumentError(
        "Chronological OOS tree has an unexpected sample_year: $tree_dir",
    ))
    validated_hours = _validate_chronological_oos_metadata(metadata, tree_dir)
    validated_hours == operational_hours || throw(ArgumentError(
        "Chronological OOS tree has an unexpected operational-hour count: $tree_dir",
    ))
    if expected_chunk_index !== nothing
        chronology = metadata["chronology"]
        get(chronology, "formulation", nothing) == "internalempire_24x365" ||
            throw(ArgumentError("Full-year OOS tree has an unexpected formulation: $tree_dir"))
        get(chronology, "tree_index", nothing) == expected_chunk_index ||
            throw(ArgumentError(
                "Full-year OOS tree chunk index does not match its experiment position: $tree_dir",
            ))
    end
    return metadata
end

function _write_or_validate_chronological_config(
    config_file::AbstractString,
    config,
)
    if ispath(config_file)
        isfile(config_file) || throw(ArgumentError(
            "Chronological OOS config path exists but is not a file: $config_file",
        ))
        YAML.load_file(config_file) == config || throw(ArgumentError(
            "Existing chronological OOS config does not match the requested experiment: " *
            config_file,
        ))
    else
        _write_oos_experiment_manifest(config_file, config)
    end
    return config_file
end

function _prepare_chronological_oos_experiment(
    config_file::AbstractString,
    data_folder::AbstractString,
    experiment_dir::AbstractString;
    sample_years,
    input_format::Symbol,
    resume::Bool,
    progress,
    operational_hours::Int,
    require_full_year::Bool,
)
    source_data = abspath(normpath(data_folder))
    generation_config_file = abspath(normpath(config_file))
    target_experiment = abspath(normpath(experiment_dir))
    years = Int.(collect(sample_years))
    isempty(years) && throw(ArgumentError("sample_years must not be empty"))
    if require_full_year
        length(years) == 1 || throw(ArgumentError(
            "InternalEMPIRE full-year OOS requires exactly one sample year per experiment",
        ))
    else
        length(unique(years)) == length(years) || throw(ArgumentError(
            "sample_years must not contain duplicates",
        ))
    end
    require_full_year && operational_hours != _OOS_FULL_YEAR_HOURS && throw(ArgumentError(
        "Full-year OOS requires exactly $_OOS_FULL_YEAR_HOURS operational hours",
    ))
    isdir(source_data) || throw(ArgumentError("Dataset folder does not exist: $data_folder"))
    isfile(generation_config_file) || throw(ArgumentError(
        "Config file does not exist: $config_file",
    ))
    _is_same_or_child_path(target_experiment, source_data) && throw(ArgumentError(
        "OOS experiment must be outside the source dataset: $experiment_dir",
    ))

    generation_config = YAML.load_file(generation_config_file)
    execution_config = require_full_year ?
                       _internalempire_full_year_config(generation_config) :
                       _chronological_oos_config(generation_config, operational_hours)
    evaluation_mode = require_full_year ?
                      _OOS_CHRONOLOGICAL_MODE : _OOS_CHRONOLOGICAL_FIXTURE_MODE
    tree_years = require_full_year ? fill(only(years), _OOS_FULL_YEAR_TREE_COUNT) : years
    if ispath(target_experiment)
        isdir(target_experiment) || throw(ArgumentError(
            "OOS experiment path exists but is not a directory: $experiment_dir",
        ))
    else
        mkpath(target_experiment)
    end
    execution_config_file = joinpath(target_experiment, _OOS_FULL_YEAR_CONFIG)
    _write_or_validate_chronological_config(execution_config_file, execution_config)

    source_data_sha256 = _oos_directory_sha256(source_data)
    execution_config_sha256 = _oos_sha256_file(execution_config_file)
    expected_manifest = _new_oos_experiment_manifest(
        execution_config_file,
        execution_config_sha256,
        source_data,
        source_data_sha256,
        target_experiment,
        input_format,
        0,
        length(tree_years),
    )
    expected_manifest["evaluation_mode"] = evaluation_mode
    expected_manifest["sample_years"] = tree_years
    expected_manifest["operational_hours_per_year"] = operational_hours
    expected_manifest["generation_source_config_file"] = generation_config_file
    expected_manifest["generation_source_config_sha256"] =
        _oos_sha256_file(generation_config_file)
    for (tree_index, (tree, year)) in enumerate(zip(expected_manifest["trees"], tree_years))
        tree["sample_year"] = year
        if require_full_year
            chunk = _internalempire_full_year_chunks()[tree_index]
            tree["chunk_index"] = tree_index
            tree["source_hour_start"] = first(chunk)
            tree["source_hour_end"] = last(chunk)
        end
    end
    if require_full_year
        expected_manifest["full_year_formulation"] = "internalempire_24x365"
        expected_manifest["full_year_sample_year"] = only(years)
        expected_manifest["chunk_hours"] = _OOS_FULL_YEAR_CHUNK_HOURS
        expected_manifest["dummy_peak_hours_per_tree"] = _OOS_FULL_YEAR_DUMMY_PEAK_HOURS
    end

    manifest_file = joinpath(target_experiment, _OOS_EXPERIMENT_MANIFEST)
    manifest = if isfile(manifest_file)
        resume || throw(ArgumentError(
            "OOS experiment already exists and resume=false: $experiment_dir",
        ))
        existing = YAML.load_file(manifest_file)
        existing isa AbstractDict || throw(ArgumentError(
            "Existing OOS experiment manifest must be a mapping: $manifest_file",
        ))
        _validate_oos_experiment_spec(existing, expected_manifest)
        manifest_keys = String[
            "evaluation_mode",
            "sample_years",
            "operational_hours_per_year",
            "generation_source_config_file",
            "generation_source_config_sha256",
        ]
        if require_full_year
            append!(manifest_keys, [
                "full_year_formulation",
                "full_year_sample_year",
                "chunk_hours",
                "dummy_peak_hours_per_tree",
            ])
        end
        for key in manifest_keys
            get(existing, key, nothing) == expected_manifest[key] || throw(ArgumentError(
                "Existing chronological OOS experiment has a different $key",
            ))
        end
        expected_manifest["created_at_utc"] = get(
            existing,
            "created_at_utc",
            expected_manifest["created_at_utc"],
        )
        expected_manifest
    elseif length(readdir(target_experiment)) > 1
        throw(ArgumentError(
            "OOS experiment directory exists without experiment.yaml and contains " *
            "unexpected files: $experiment_dir",
        ))
    else
        expected_manifest
    end

    trees = manifest["trees"]
    for (tree_index, (tree, year)) in enumerate(zip(trees, tree_years))
        tree_dir = tree["path"]
        ispath(tree_dir) || continue
        try
            _validate_chronological_oos_tree(
                tree_dir,
                tree["seed"],
                year,
                source_data_sha256,
                execution_config_sha256,
                input_format,
                evaluation_mode,
                operational_hours,
                ;
                expected_chunk_index = require_full_year ? tree_index : nothing,
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
    _report_progress(
        progress,
        "Preparing $(length(tree_years)) chronological OOS tree(s) in $target_experiment",
    )
    sets, _ = read_data(source_data; format = input_format)
    for (tree_index, (tree, year)) in enumerate(zip(trees, tree_years))
        tree["status"] == "complete" && continue
        tree["status"] = "generating"
        tree["error"] = nothing
        _mark_oos_experiment_updated!(manifest, "preparing")
        _write_oos_experiment_manifest(manifest_file, manifest)
        source_description = require_full_year ?
                             "historical year $year, hours $(tree["source_hour_start"]):$(tree["source_hour_end"])" :
                             "historical year $year"
        _report_progress(progress, "Generating $(tree["name"]) from $source_description")
        try
            _generate_chronological_oos_tree(
                execution_config,
                execution_config_file,
                generation_config_file,
                source_data,
                source_data_sha256,
                tree["path"],
                sets;
                input_format,
                seed = tree["seed"],
                sample_year = year,
                operational_hours,
                require_full_year,
                chunk_index = require_full_year ? tree_index : nothing,
            )
            _validate_chronological_oos_tree(
                tree["path"],
                tree["seed"],
                year,
                source_data_sha256,
                execution_config_sha256,
                input_format,
                evaluation_mode,
                operational_hours,
                ;
                expected_chunk_index = require_full_year ? tree_index : nothing,
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

    _mark_oos_experiment_updated!(manifest, "complete")
    _write_oos_experiment_manifest(manifest_file, manifest)
    return target_experiment
end

"""
    prepare_full_year_oos_experiment(
        config_file,
        data_folder,
        experiment_dir;
        sample_years,
        input_format = :auto,
        resume = true,
        progress = nothing,
    )

Prepare InternalEMPIRE-equivalent full-year OOS trees for one non-leap year.

The selected 8,760-hour year is partitioned into 24 consecutive 365-hour trees.
Each tree is an independent solve with one `winter` scenario and one dummy peak
hour. The winter multiplicity is `(8760 - 1) / 365`; dummy-peak results are
excluded from full-year aggregation. The function writes a matching
`full_year_config.yaml` and resumable `experiment.yaml`; it never modifies the
source dataset or starts a solver run.
"""
function prepare_full_year_oos_experiment(
    config_file::AbstractString,
    data_folder::AbstractString,
    experiment_dir::AbstractString;
    sample_years,
    input_format::Symbol = :auto,
    resume::Bool = true,
    progress = nothing,
)
    return _prepare_chronological_oos_experiment(
        config_file,
        data_folder,
        experiment_dir;
        sample_years,
        input_format,
        resume,
        progress,
        operational_hours = _OOS_FULL_YEAR_HOURS,
        require_full_year = true,
    )
end
