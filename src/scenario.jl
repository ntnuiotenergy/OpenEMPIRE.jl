
function scenario_id(scenario_name)
    m = match(r"\d+$", scenario_name)
    if m !== nothing
        value = parse(Int, m.match)
        return value
    end
    return nothing
end

const REGULAR_SCENARIO_SEASONS = ("winter", "spring", "summer", "fall")
const SCENARIO_METADATA_COLUMNS = Set(["time", "year", "month", "hour", "dayofweek"])
const COUNTRY_NODE_MAPPING = Dict(
    "AT" => "Austria",
    "BA" => "BosniaH",
    "BE" => "Belgium",
    "BG" => "Bulgaria",
    "CH" => "Switzerland",
    "CZ" => "CzechR",
    "DE" => "Germany",
    "DK" => "Denmark",
    "EE" => "Estonia",
    "ES" => "Spain",
    "FI" => "Finland",
    "FR" => "France",
    "GB" => "GreatBrit.",
    "GR" => "Greece",
    "HR" => "Croatia",
    "HU" => "Hungary",
    "IE" => "Ireland",
    "IT" => "Italy",
    "LT" => "Lithuania",
    "LU" => "Luxemb.",
    "LV" => "Latvia",
    "MK" => "Macedonia",
    "NL" => "Netherlands",
    "NO" => "Norway",
    "PL" => "Poland",
    "PT" => "Portugal",
    "RO" => "Romania",
    "RS" => "Serbia",
    "SE" => "Sweden",
    "SI" => "Slovenia",
    "SK" => "Slovakia",
    "MF" => "MorayFirth",
    "FF" => "FirthofForth",
    "DB" => "DoggerBank",
    "HS" => "Hornsea",
    "OD" => "OuterDowsing",
    "NF" => "Norfolk",
    "EA" => "EastAnglia",
    "BS" => "Borssele",
    "HK" => "HollandseeKust",
    "HB" => "HelgolanderBucht",
    "NS" => "Nordsoen",
    "UN" => "UtsiraNord",
    "SN1" => "SorligeNordsjoI",
    "SN2" => "SorligeNordsjoII",
)

struct RawScenarioTable
    columns::Vector{String}
    timestamps::Vector{DateTime}
    years::Vector{Int}
    months::Vector{Int}
    values::Dict{String, Vector{Float64}}
end

regular_scenario_seasons(config) = Tuple(String.(get(config, "regular_seasons", collect(REGULAR_SCENARIO_SEASONS))))

function _positive_config_int(config, key::AbstractString, default::Int)::Int
    value = get(config, key, default)
    parsed = value isa Integer ? Int(value) : try
        parse(Int, strip(string(value)))
    catch
        throw(ArgumentError("$key must be a positive integer; got $(repr(value))"))
    end
    parsed > 0 || throw(ArgumentError("$key must be a positive integer; got $parsed"))
    return parsed
end

natural_gas_enabled(config)::Bool = _config_bool(config, "natural_gas", false)
weather_scenario_count(config)::Int =
    _positive_config_int(config, "number_of_scenarios", 1)
gas_scenario_count(config)::Int =
    natural_gas_enabled(config) ?
    _positive_config_int(config, "number_of_gas_scenarios", 1) : 1
combined_scenario_count(config)::Int =
    Base.checked_mul(weather_scenario_count(config), gas_scenario_count(config))
weather_scenario_index(combined::Integer, gas_count::Integer) =
    fld(Int(combined) - 1, Int(gas_count)) + 1
gas_scenario_index(combined::Integer, gas_count::Integer) =
    mod(Int(combined) - 1, Int(gas_count)) + 1
scenario_peak_count(config) = Int(get(config, "n_peak_seasons", 2))
scenario_peak_hours(config) = Int(get(config, "len_peak_season", 24))

const LoadScenarioRow = NamedTuple{
    (:Node, :Operationalhour, :Scenario, :Period, :ElectricLoadRaw_in_MW),
    Tuple{String, Int, String, Int, Float64},
}
const HydroScenarioRow = NamedTuple{
    (:Node, :Period, :Season, :Operationalhour, :Scenario, :HydroGeneratorMaxSeasonalProduction),
    Tuple{String, Int, String, Int, String, Float64},
}
const GeneratorScenarioRow = NamedTuple{
    (:Node, :IntermitentGenerators, :Operationalhour, :Scenario, :Period, :GeneratorStochasticAvailabilityRaw),
    Tuple{String, String, Int, String, Int, Float64},
}
const SamplingKeyRow = NamedTuple{
    (:Period, :Scenario, :Season, :Year, :Month, :Hour),
    Tuple{Int, Int, String, Int, Int, Int},
}
const FilterMetricRow = NamedTuple{
    (:Year, :Season, :SampleIndex, :Value, :Value2),
    Tuple{Int, String, Int, Float64, Float64},
}
const FilterResultRow = NamedTuple{
    (:Year, :Season, :SampleIndex, :Value, :Value2, :ClusterGroup),
    Tuple{Int, String, Int, Float64, Float64, Int},
}

function _generated_scenario_csv_files(data_folder::AbstractString)
    return (
        joinpath(data_folder, "ScenarioData", "sloadRaw.csv"),
        joinpath(data_folder, "ScenarioData", "maxRegHydroGenRaw.csv"),
        joinpath(data_folder, "ScenarioData", "genCapAvailStochRaw.csv"),
    )
end

"""
    read_scenario_data!(data_folder, periods, params, sets, config, season_for_hour; rng=Random.default_rng())

Populate stochastic scenario profiles in `params`.

When `use_scenario_generation` is true, raw `ScenarioData/*.csv` files are
sampled and written as generated stochastic CSV files. When it is false,
existing generated stochastic CSV files are loaded.
"""
function read_scenario_data!(
    data_folder,
    periods,
    params::EmpireParams,
    sets,
    config,
    season_for_hour::Dict{Int, Int};
    rng = Random.default_rng(),
)
    use_generation = get(config, "use_scenario_generation", true)
    if use_generation
        return generate_scenario_csv!(data_folder, periods, params, sets, config; rng)
    end

    scenario_files = _generated_scenario_csv_files(data_folder)
    has_csvs = isfile.(scenario_files)
    if all(has_csvs)
        return read_generated_scenario_csv!(data_folder, periods, params, sets, season_for_hour)
    elseif any(has_csvs)
        missing_files = collect(scenario_files)[.!collect(has_csvs)]
        throw(ArgumentError(
            "Generated stochastic scenario CSV files are incomplete. Missing files: " *
            join(missing_files, ", ")
        ))
    end

    throw(ArgumentError(
        "Generated stochastic scenario CSV files are missing. Set use_scenario_generation=true " *
        "or provide sloadRaw.csv, maxRegHydroGenRaw.csv, and genCapAvailStochRaw.csv in " *
        joinpath(data_folder, "ScenarioData")
    ))
end

function _python_dateformat(time_format::AbstractString)
    unsupported = [m.match for m in eachmatch(r"%[A-Za-z]", time_format) if !(m.match in ("%Y", "%m", "%d", "%H", "%M", "%S"))]
    if !isempty(unsupported)
        throw(ArgumentError("Unsupported time_format token(s): $(join(unique(unsupported), ", "))"))
    end
    julia_format = replace(
        time_format,
        "%Y" => "yyyy",
        "%m" => "mm",
        "%d" => "dd",
        "%H" => "HH",
        "%M" => "MM",
        "%S" => "SS",
    )
    return DateFormat(julia_format)
end

"""
Months belonging to each regular season.

These match `season_month` in `OpenEMPIRE-csv/empire/core/scenario_utils.py:21-29`,
which is the implementation this port targets.

InternalEMPIRE used to disagree here -- winter (1, 2, 12), spring (3, 4, 5), summer
(6, 7, 8), fall (9, 10, 11), wrapping winter around the turn of the year -- so the
two could not be driven from a shared sampling key and be expected to draw the same
weather. That divergence was **resolved upstream** in InternalEMPIRE commit
`219034c` ("Update sampling frame to match OpenEMPIRE", 2026-08-03), which adopted
exactly the split below. All three implementations now agree.

The old difference was easy to miss in testing because both implementations preserve
chronological order when filtering, so the two winter pools were identical for their
first 1,416 rows (January plus February) and diverged only beyond that.
"""
function _season_months(season::AbstractString)
    season == "winter" && return (1, 2, 3)
    season == "spring" && return (4, 5, 6)
    season == "summer" && return (7, 8, 9)
    season == "fall" && return (10, 11, 12)
    throw(ArgumentError("$season is not a valid regular season"))
end

function _required_scenario_csv(data_folder::AbstractString, filename::AbstractString)
    path = joinpath(data_folder, "ScenarioData", filename)
    isfile(path) || throw(ArgumentError("Required raw scenario CSV file not found: $path"))
    return path
end

function _float_value(x)
    _is_blank(x) && return 0.0
    return x isa Real ? Float64(x) : parse(Float64, strip(string(x)))
end

function _read_raw_scenario_table(path::AbstractString, dateformat::DateFormat)
    file = CSV.File(path; normalizenames = false)
    names = string.(propertynames(file))
    time_col = findfirst(==("time"), names)
    time_col === nothing && throw(ArgumentError("Raw scenario CSV file must contain a time column: $path"))

    data_cols = [i for (i, name) in enumerate(names) if !(lowercase(name) in SCENARIO_METADATA_COLUMNS)]
    columns = names[data_cols]
    values = Dict(col => Float64[] for col in columns)
    timestamps = DateTime[]
    years = Int[]
    months = Int[]

    for row in file
        timestamp = DateTime(strip(string(row[time_col])), dateformat)
        push!(timestamps, timestamp)
        push!(years, Dates.year(timestamp))
        push!(months, Dates.month(timestamp))
        for (col, idx) in zip(columns, data_cols)
            push!(values[col], _float_value(row[idx]))
        end
    end
    return RawScenarioTable(columns, timestamps, years, months, values)
end

function _node_name(raw::AbstractString, node_set::Set{String})
    raw in node_set && return raw
    mapped = get(COUNTRY_NODE_MAPPING, raw, raw)
    mapped in node_set && return mapped
    return nothing
end

function _node_names_for_generator(raw::AbstractString, generator::AbstractString, node_set::Set{String})
    exact = _node_name(raw, node_set)
    exact !== nothing && return [exact]

    if raw == "NO"
        start_area = generator in ("Windoffshore", "Windoffshoregrounded", "Windoffshorefloating") ? 2 : 1
        return [node for node in ("NO$(i)" for i in start_area:5) if node in node_set]
    end

    return String[]
end

function _season_indices(table::RawScenarioTable, year::Int, season::AbstractString)
    months = Set(_season_months(season))
    return [i for i in eachindex(table.years) if table.years[i] == year && table.months[i] in months]
end

function _year_indices(table::RawScenarioTable, year::Int)
    return [i for i in eachindex(table.years) if table.years[i] == year]
end

function _sample_regular_indices(
    table::RawScenarioTable,
    year::Int,
    season::AbstractString,
    sample_hour::Int,
    hours::Int,
)
    indices = _season_indices(table, year, season)
    if sample_hour < 0 || sample_hour + hours > length(indices)
        throw(ArgumentError(
            "Invalid sample window for $season $year: hour $sample_hour with length $hours " *
            "but only $(length(indices)) rows are available",
        ))
    end
    return indices[(sample_hour + 1):(sample_hour + hours)]
end

function _random_regular_sample(rng, table::RawScenarioTable, year::Int, season::AbstractString, hours::Int)
    indices = _season_indices(table, year, season)
    max_start = length(indices) - hours
    max_start < 0 && throw(ArgumentError(
        "Not enough hours in $season $year. Need $hours but found $(length(indices)).",
    ))
    return max_start == 0 ? 0 : rand(rng, 0:max_start)
end

function _sample_peak_indices(table::RawScenarioTable, year::Int, center_zero_based::Int, hours::Int)
    indices = _year_indices(table, year)
    length(indices) >= hours || throw(ArgumentError(
        "Not enough hours in year $year. Need $hours but found $(length(indices)).",
    ))
    start_index = center_zero_based - div(hours, 2) + 1
    start_index = clamp(start_index, 1, length(indices) - hours + 1)
    return indices[start_index:(start_index + hours - 1)]
end

function _peak_centers(load_table::RawScenarioTable, year::Int)
    indices = _year_indices(load_table, year)
    isempty(indices) && throw(ArgumentError("No electric load data found for year $year"))

    best_system_value = -Inf
    best_system_position = 0
    best_node_value = -Inf
    best_node_position = 0

    for (pos, idx) in enumerate(indices)
        system_value = 0.0
        for col in load_table.columns
            value = load_table.values[col][idx]
            system_value += value
            if value > best_node_value
                best_node_value = value
                best_node_position = pos - 1
            end
        end
        if system_value > best_system_value
            best_system_value = system_value
            best_system_position = pos - 1
        end
    end

    return best_node_position, best_system_position
end

function _sample_years(tables::RawScenarioTable...)
    common_years = Set(tables[1].years)
    for table in tables[2:end]
        intersect!(common_years, Set(table.years))
    end
    isempty(common_years) && throw(ArgumentError("Raw scenario CSV files have no common sample years"))
    return sort!(collect(common_years))
end

function _total_scenario_values(table::RawScenarioTable)
    totals = zeros(Float64, length(table.timestamps))
    for column in table.columns
        values = table.values[column]
        length(values) == length(totals) || throw(DimensionMismatch(
            "Raw scenario column $column has $(length(values)) values; expected $(length(totals))",
        ))
        @inbounds for index in eachindex(totals)
            totals[index] += values[index]
        end
    end
    all(isfinite, totals) || throw(ArgumentError(
        "Electric-load data contains non-finite total values",
    ))
    return totals
end

function _wasserstein_distance_sorted(
    reference::AbstractVector{<:Real},
    sample::AbstractVector{<:Real},
)
    isempty(reference) && throw(ArgumentError("Wasserstein reference must not be empty"))
    isempty(sample) && throw(ArgumentError("Wasserstein sample must not be empty"))

    reference_index = 1
    sample_index = 1
    reference_cdf = 0.0
    sample_cdf = 0.0
    previous = min(Float64(first(reference)), Float64(first(sample)))
    distance = 0.0

    while reference_index <= length(reference) || sample_index <= length(sample)
        reference_value = reference_index <= length(reference) ?
                          Float64(reference[reference_index]) : Inf
        sample_value = sample_index <= length(sample) ?
                       Float64(sample[sample_index]) : Inf
        value = min(reference_value, sample_value)
        distance += abs(reference_cdf - sample_cdf) * (value - previous)

        while reference_index <= length(reference) &&
              Float64(reference[reference_index]) == value
            reference_index += 1
        end
        while sample_index <= length(sample) &&
              Float64(sample[sample_index]) == value
            sample_index += 1
        end

        reference_cdf = (reference_index - 1) / length(reference)
        sample_cdf = (sample_index - 1) / length(sample)
        previous = value
    end

    return distance
end

function _wasserstein_distance_1d(
    reference::AbstractVector{<:Real},
    sample::AbstractVector{<:Real},
)
    all(isfinite, reference) || throw(ArgumentError(
        "Wasserstein reference contains non-finite values",
    ))
    all(isfinite, sample) || throw(ArgumentError(
        "Wasserstein sample contains non-finite values",
    ))
    return _wasserstein_distance_sorted(sort!(Float64.(reference)), sort!(Float64.(sample)))
end

function _filter_metric_rows(
    table::RawScenarioTable,
    seasons,
    regular_hours::Int,
    sample_years::AbstractVector{<:Integer},
)
    regular_hours > 0 || throw(ArgumentError(
        "length_of_regular_season must be positive when making a scenario filter",
    ))

    totals = _total_scenario_values(table)
    years = sort!(unique(Int.(sample_years)))
    isempty(years) && throw(ArgumentError(
        "Scenario filter requires at least one common sample year",
    ))
    rows = FilterMetricRow[]
    sample_values = Vector{Float64}(undef, regular_hours)

    for season in seasons
        months = _season_months(season)
        season_indices = [
            index for index in eachindex(table.months)
            if table.months[index] in months
        ]
        isempty(season_indices) && throw(ArgumentError(
            "No electric-load rows are available for filter season $season",
        ))
        reference = sort!(totals[season_indices])

        season_start = length(rows) + 1
        for year in years
            year_indices = _season_indices(table, year, season)
            candidate_count = length(year_indices) - regular_hours - 1
            candidate_count <= 0 && continue

            for sample_hour in 0:(candidate_count - 1)
                window_sum = 0.0
                @inbounds for offset in 1:regular_hours
                    value = totals[year_indices[sample_hour + offset]]
                    sample_values[offset] = value
                    window_sum += value
                end
                mean_value = window_sum / regular_hours
                sort!(sample_values)
                wasserstein = _wasserstein_distance_sorted(reference, sample_values)
                isfinite(wasserstein) && isfinite(mean_value) || throw(ArgumentError(
                    "Filter metric is non-finite for $season $year at hour $sample_hour",
                ))
                push!(rows, (
                    Year = year,
                    Season = String(season),
                    SampleIndex = sample_hour,
                    Value = wasserstein,
                    Value2 = mean_value,
                ))
            end
        end
        length(rows) >= season_start || throw(ArgumentError(
            "No complete filter windows are available for season $season with " *
            "length_of_regular_season=$regular_hours",
        ))
    end

    return rows
end

function _cluster_filter_rows(
    metrics::Vector{FilterMetricRow},
    seasons,
    n_cluster::Int,
    rng;
    n_init::Int = 100,
)
    n_cluster > 0 || throw(ArgumentError("n_cluster must be positive"))
    n_init > 0 || throw(ArgumentError("K-means initialization count must be positive"))
    rows = FilterResultRow[]

    for season in seasons
        season_metrics = [row for row in metrics if row.Season == season]
        length(season_metrics) >= n_cluster || throw(ArgumentError(
            "n_cluster=$n_cluster exceeds the $(length(season_metrics)) filter candidates " *
            "for season $season",
        ))

        features = Matrix{Float64}(undef, 2, length(season_metrics))
        for (index, row) in enumerate(season_metrics)
            features[1, index] = row.Value
            features[2, index] = row.Value2
        end

        best_result = nothing
        best_cost = Inf
        for _ in 1:n_init
            result = Clustering.kmeans(
                features,
                n_cluster;
                init = :kmpp,
                maxiter = 300,
                rng,
            )
            if isfinite(result.totalcost) && result.totalcost < best_cost
                best_result = result
                best_cost = result.totalcost
            end
        end
        best_result === nothing && throw(ArgumentError(
            "K-means did not produce a finite result for season $season",
        ))
        all(>(0), best_result.counts) || throw(ArgumentError(
            "K-means produced an empty cluster for season $season",
        ))

        center_order = sortperm(
            1:n_cluster;
            by = cluster -> (
                best_result.centers[1, cluster],
                best_result.centers[2, cluster],
                cluster,
            ),
        )
        canonical_group = Vector{Int}(undef, n_cluster)
        for (group, cluster) in enumerate(center_order)
            canonical_group[cluster] = group - 1
        end

        for (index, row) in enumerate(season_metrics)
            push!(rows, (
                Year = row.Year,
                Season = row.Season,
                SampleIndex = row.SampleIndex,
                Value = row.Value,
                Value2 = row.Value2,
                ClusterGroup = canonical_group[best_result.assignments[index]],
            ))
        end
    end

    return rows
end

function _make_filter_result!(
    scenario_dir::AbstractString,
    load_table::RawScenarioTable,
    seasons,
    regular_hours::Int,
    n_cluster::Int,
    sample_years::AbstractVector{<:Integer},
    rng,
)
    metrics = _filter_metric_rows(load_table, seasons, regular_hours, sample_years)
    rows = _cluster_filter_rows(metrics, seasons, n_cluster, rng)
    CSV.write(joinpath(scenario_dir, "filter_result.csv"), rows)
    return rows
end

function _invalid_filter_value(
    path::AbstractString,
    row_number::Int,
    column::AbstractString,
    value,
)
    throw(ArgumentError(
        "Scenario filter $path row $row_number has an invalid $column value: $(repr(value))",
    ))
end

function _parse_filter_integer(
    value,
    path::AbstractString,
    row_number::Int,
    column::AbstractString,
)
    parsed = if value isa Integer && !(value isa Bool)
        try
            Int(value)
        catch
            nothing
        end
    elseif value isa AbstractFloat
        if isfinite(value) && isinteger(value)
            try
                Int(value)
            catch
                nothing
            end
        end
    elseif value isa AbstractString
        tryparse(Int, strip(value))
    end
    parsed === nothing && _invalid_filter_value(path, row_number, column, value)
    return parsed
end

function _parse_filter_float(
    value,
    path::AbstractString,
    row_number::Int,
    column::AbstractString,
)
    parsed = if value isa Real && !(value isa Bool)
        try
            Float64(value)
        catch
            nothing
        end
    elseif value isa AbstractString
        tryparse(Float64, strip(value))
    end
    parsed === nothing && _invalid_filter_value(path, row_number, column, value)
    return parsed
end

function _parse_filter_season(value, path::AbstractString, row_number::Int)
    value isa AbstractString ||
        _invalid_filter_value(path, row_number, "Season", value)
    season = strip(String(value))
    isempty(season) && _invalid_filter_value(path, row_number, "Season", value)
    return season
end

function _filter_candidate_groups(
    scenario_dir::AbstractString,
    seasons,
    n_cluster::Int,
    load_table::RawScenarioTable,
    regular_hours::Int,
    sample_years::AbstractVector{<:Integer},
)
    n_cluster > 0 || throw(ArgumentError("n_cluster must be positive"))
    path = joinpath(scenario_dir, "filter_result.csv")
    isfile(path) || throw(ArgumentError(
        "filter_use is true, but scenario filter not found: $path",
    ))

    file = try
        CSV.File(path; normalizenames = false)
    catch err
        throw(ArgumentError(
            "Could not read scenario filter $path: $(sprint(showerror, err))",
        ))
    end
    required_columns = ["Year", "Season", "SampleIndex", "Value", "Value2", "ClusterGroup"]
    names = string.(propertynames(file))
    missing_columns = setdiff(required_columns, names)
    isempty(missing_columns) || throw(ArgumentError(
        "Scenario filter $path is missing column(s): $(join(missing_columns, ", "))",
    ))

    requested_seasons = Set(String.(seasons))
    allowed_years = sort!(unique(Int.(sample_years)))
    isempty(allowed_years) && throw(ArgumentError(
        "Scenario filter $path cannot be used without a common sample year",
    ))
    allowed_year_set = Set(allowed_years)
    groups = Dict{Tuple{String, Int}, Vector{FilterResultRow}}()
    seen = Set{Tuple{Int, String, Int}}()
    available_hours = Dict(
        (year, String(season)) => length(_season_indices(load_table, year, season))
        for year in allowed_years, season in seasons
    )
    for (data_row, input_row) in enumerate(file)
        row_number = data_row + 1
        row = (
            Year = _parse_filter_integer(input_row.Year, path, row_number, "Year"),
            Season = _parse_filter_season(input_row.Season, path, row_number),
            SampleIndex = _parse_filter_integer(
                input_row.SampleIndex,
                path,
                row_number,
                "SampleIndex",
            ),
            Value = _parse_filter_float(input_row.Value, path, row_number, "Value"),
            Value2 = _parse_filter_float(input_row.Value2, path, row_number, "Value2"),
            ClusterGroup = _parse_filter_integer(
                input_row.ClusterGroup,
                path,
                row_number,
                "ClusterGroup",
            ),
        )
        row.Season in requested_seasons || continue
        row.Year in allowed_year_set || throw(ArgumentError(
            "Scenario filter $path row $row_number references Year=$(row.Year), " *
            "which is not present in every raw scenario input; allowed years: " *
            join(allowed_years, ", "),
        ))
        row.SampleIndex >= 0 || throw(ArgumentError(
            "Scenario filter $path row $row_number contains a negative SampleIndex " *
            "for $(row.Season) $(row.Year)",
        ))
        isfinite(row.Value) && isfinite(row.Value2) || throw(ArgumentError(
            "Scenario filter $path row $row_number contains a non-finite metric " *
            "for $(row.Season) $(row.Year)",
        ))
        0 <= row.ClusterGroup < n_cluster || throw(ArgumentError(
            "Scenario filter $path row $row_number has ClusterGroup " *
            "$(row.ClusterGroup) outside 0:$(n_cluster - 1)",
        ))
        key = (row.Year, row.Season, row.SampleIndex)
        key in seen && throw(ArgumentError(
            "Scenario filter $path row $row_number contains duplicate candidate $key",
        ))
        push!(seen, key)
        hours = get(available_hours, (row.Year, row.Season), 0)
        row.SampleIndex <= hours - regular_hours || throw(ArgumentError(
            "Scenario filter $path row $row_number candidate $(row.Season) " *
            "$(row.Year) hour " *
            "$(row.SampleIndex) exceeds the $hours available rows",
        ))
        push!(get!(groups, (row.Season, row.ClusterGroup), FilterResultRow[]), row)
    end

    for season in seasons, cluster in 0:(n_cluster - 1)
        isempty(get(groups, (String(season), cluster), FilterResultRow[])) &&
            throw(ArgumentError(
                "Scenario filter $path has no candidates for season $season " *
                "and ClusterGroup $cluster",
            ))
    end
    return groups
end

function _sample_filter_candidate(rng, candidates::Vector{FilterResultRow})
    selected_year = rand(rng, candidates).Year
    count_for_year = count(row -> row.Year == selected_year, candidates)
    selected_index = rand(rng, 1:count_for_year)
    seen = 0
    for row in candidates
        row.Year == selected_year || continue
        seen += 1
        seen == selected_index && return row.Year, row.SampleIndex
    end
    error("Unreachable filtered-candidate selection state")
end

function _sampling_key(path::AbstractString)
    key_path = joinpath(path, "ScenarioData", "sampling_key.csv")
    isfile(key_path) || throw(ArgumentError("use_fixed_sample is true, but sampling key not found: $key_path"))

    values = Dict{Tuple{Int, Int, String}, Tuple{Int, Int}}()
    for row in CSV.File(key_path; normalizenames = false)
        values[(Int(row.Period), Int(row.Scenario), String(row.Season))] = (Int(row.Year), Int(row.Hour))
    end
    return values
end

function _sample_month(table::RawScenarioTable, indices)::Int
    isempty(indices) && return 0
    return table.months[first(indices)]
end

function _get_fixed_sample(key, period::Int, scenario::Int, season::AbstractString)
    sample = get(key, (period, scenario, season), nothing)
    sample === nothing && throw(ArgumentError(
        "sampling_key.csv is missing Period=$period, Scenario=$scenario, Season=$season",
    ))
    return sample
end

# ===== Copula-cluster scenario generation reduction (SGR) =====
#
# Stratifies regular-season sampling by clustering candidate (year, hour-window)
# combinations on the empirical copula (rank-transformed, uniform-margin) of one
# or more input variables across all their nodes, via k-means. Sampling then
# round-robins through the clusters instead of sampling purely at random, so
# scenarios are pulled from all regimes (e.g. low-load vs. high-load weeks).

const COPULA_VARIABLE_NAMES = ("electricload", "hydroseasonal", "solar", "windonshore", "windoffshore", "hydroror")

const CopulaClusterRow = NamedTuple{
    (:Season, :Year, :SampleIndex, :ClusterGroup),
    Tuple{String, Int, Int, Int},
}

_copula_cluster_path(data_folder) = joinpath(data_folder, "Copulas", "CopulaClusters", "copula_clusters.csv")

function _copula_source_table(name::AbstractString, load_table::RawScenarioTable, hydro_table::RawScenarioTable, generator_sources)
    name == "electricload" && return load_table
    name == "hydroseasonal" && return hydro_table
    for (gen_name, table) in generator_sources
        name == "solar" && gen_name == "Solar" && return table
        name == "windonshore" && gen_name == "Windonshore" && return table
        name == "hydroror" && gen_name == "Hydrorun-of-the-river" && return table
        name == "windoffshore" && startswith(gen_name, "Windoffshore") && return table
    end
    return nothing
end

function _copula_source_tables(copulas_to_use, load_table::RawScenarioTable, hydro_table::RawScenarioTable, generator_sources)
    isempty(copulas_to_use) && throw(ArgumentError("copulas_to_use must contain at least one variable"))
    tables = Tuple{String, RawScenarioTable}[]
    for name in copulas_to_use
        table = _copula_source_table(String(name), load_table, hydro_table, generator_sources)
        table === nothing && throw(ArgumentError(
            "Unknown copula variable \"$name\" in copulas_to_use. Valid options: " *
            join(COPULA_VARIABLE_NAMES, ", "),
        ))
        push!(tables, (String(name), table))
    end
    return tables
end

# Candidate count per year, matching Python's `make_mean`:
#
#     for j in range(max_sample - regularSeasonHours - 1)
#
# `range` is exclusive, so the last offset Python considers is
# `length(indices) - regular_hours - 2`, two short of the last window that
# actually fits. `_filter_metric_rows` reproduces the same bound for the scenario
# filter via Python's `make_ws`, so both stratification paths agree with the
# reference implementation and with each other.
function _copula_candidate_count(table::RawScenarioTable, year::Int, season::AbstractString, regular_hours::Int)
    indices = _season_indices(table, year, season)
    return length(indices) - regular_hours - 1
end

function _copula_candidate_windows(tables, years, season::AbstractString, regular_hours::Int)
    candidates = Tuple{Int, Int}[]
    for year in years
        candidate_count = minimum(_copula_candidate_count(table, year, season, regular_hours) for table in tables)
        candidate_count <= 0 && continue
        for offset in 0:(candidate_count - 1)
            push!(candidates, (year, offset))
        end
    end
    isempty(candidates) && throw(ArgumentError(
        "No candidate $season windows available for copula clustering in years $years",
    ))
    return candidates
end

function _copula_window_mean(table::RawScenarioTable, col::String, year::Int, season::AbstractString, offset::Int, regular_hours::Int)
    indices = _sample_regular_indices(table, year, season, offset, regular_hours)
    return mean(view(table.values[col], indices))
end

"""
    _copula_window_means(table, col, candidates, season, regular_hours)

Window means for `col` over every `(year, offset)` in `candidates`.

Equivalent to mapping [`_copula_window_mean`] over `candidates`, but
`_season_indices` scans the whole table, so it is resolved once per year instead
of once per candidate window. That lookup otherwise dominates catalog
construction: on `europe_v51` it is ~350k scans per season. Windows are still
averaged with `mean` over the same elements in the same order, so results are
unchanged.
"""
function _copula_window_means(
    table::RawScenarioTable,
    col::String,
    candidates::Vector{Tuple{Int, Int}},
    season::AbstractString,
    regular_hours::Int,
)
    values = table.values[col]
    year_indices = Dict{Int, Vector{Int}}()
    for (year, _) in candidates
        haskey(year_indices, year) && continue
        year_indices[year] = _season_indices(table, year, season)
    end

    means = Vector{Float64}(undef, length(candidates))
    for (i, (year, offset)) in enumerate(candidates)
        indices = year_indices[year]
        if offset < 0 || offset + regular_hours > length(indices)
            throw(ArgumentError(
                "Invalid sample window for $season $year: hour $offset with length " *
                "$regular_hours but only $(length(indices)) rows are available",
            ))
        end
        means[i] = mean(view(values, view(indices, (offset + 1):(offset + regular_hours))))
    end
    return means
end

# Ordinal rank (ties broken by order of appearance, matching pandas' rank(method="first"))
# divided by N, transforming to a uniform-margin empirical copula.
function _rank_transform(values::Vector{Float64})
    n = length(values)
    order = sortperm(values; alg = Base.Sort.MergeSort)
    ranks = Vector{Float64}(undef, n)
    for (rank, idx) in enumerate(order)
        ranks[idx] = rank
    end
    return ranks ./ n
end

# Runs k-means `n_init` times with k-means++ initialization (matching sklearn's
# default) and keeps the lowest-cost run, since Clustering.jl has no built-in
# multi-restart option. Cluster labels are canonicalized by sorting the centers
# so that `ClusterGroup` values are deterministic rather than arbitrary, matching
# `_cluster_filter_rows`. Returns 0-indexed cluster assignments.
function _best_kmeans(X::Matrix{Float64}, k::Int, rng; n_init::Int = 100, season = nothing)
    n_init > 0 || throw(ArgumentError("K-means initialization count must be positive"))
    label = season === nothing ? "copula clustering" : "season $season"

    best = nothing
    best_cost = Inf
    for _ in 1:n_init
        result = Clustering.kmeans(X, k; init = :kmpp, maxiter = 300, rng)
        if isfinite(result.totalcost) && result.totalcost < best_cost
            best = result
            best_cost = result.totalcost
        end
    end
    best === nothing && throw(ArgumentError(
        "K-means did not produce a finite result for $label",
    ))
    all(>(0), best.counts) || throw(ArgumentError(
        "K-means produced an empty cluster for $label",
    ))

    center_order = sortperm(1:k; by = cluster -> (best.centers[:, cluster], cluster))
    canonical_group = Vector{Int}(undef, k)
    for (group, cluster) in enumerate(center_order)
        canonical_group[cluster] = group - 1
    end
    return [canonical_group[assignment] for assignment in Clustering.assignments(best)]
end

# Column layout mirrors Python's `make_copula_filter`, which writes
# `Year,Season,SampleIndex,Value1..ValueN,ClusterGroup`. `ValueI` is the
# rank-transformed window mean of the I-th feature dimension, i.e. the uniform
# margin the clustering actually ran on. Persisting those columns is what makes a
# Julia catalog directly comparable with a Python one: the `ClusterGroup` labels
# cannot be diffed (Python leaves K-means labelling arbitrary, this port
# canonicalises it), so the `Value` columns are the part that can.
#
# Sampling reads only the four index columns, and `_read_copula_clusters` looks up
# fields by name, so the extra columns are inert at read time.
function _copula_cluster_table(rows::Vector{CopulaClusterRow}, value_columns::Vector{Vector{Float64}})
    names = (
        :Year, :Season, :SampleIndex,
        (Symbol("Value", i) for i in eachindex(value_columns))...,
        :ClusterGroup,
    )
    columns = (
        [row.Year for row in rows],
        [row.Season for row in rows],
        [row.SampleIndex for row in rows],
        value_columns...,
        [row.ClusterGroup for row in rows],
    )
    return NamedTuple{names}(columns)
end

"""
    make_copula_clusters(data_folder, regular_seasons, regular_hours, copulas_to_use, n_cluster,
                          load_table, hydro_table, generator_sources, rng; n_init=100)

Cluster candidate regular-season sampling windows by the empirical copula of
`copulas_to_use` across all of their nodes, and write the result to
`Copulas/CopulaClusters/copula_clusters.csv` under `data_folder`.

Clustering consumes `rng`, so a fixed seed reproduces the same cluster catalog.
"""
function make_copula_clusters(
    data_folder,
    regular_seasons,
    regular_hours::Int,
    copulas_to_use,
    n_cluster::Int,
    load_table::RawScenarioTable,
    hydro_table::RawScenarioTable,
    generator_sources,
    rng;
    n_init::Int = 100,
)
    source_tables = _copula_source_tables(copulas_to_use, load_table, hydro_table, generator_sources)
    years = _sample_years((table for (_, table) in source_tables)...)

    rows = CopulaClusterRow[]
    value_columns = Vector{Float64}[]
    for season in regular_seasons
        candidates = _copula_candidate_windows((table for (_, table) in source_tables), years, season, regular_hours)
        n_candidates = length(candidates)
        n_cluster <= n_candidates || throw(ArgumentError(
            "n_cluster=$n_cluster exceeds the number of candidate $season windows " *
            "($n_candidates) available for copula clustering",
        ))

        dims = Vector{Float64}[]
        for (_, table) in source_tables, col in table.columns
            means = _copula_window_means(table, col, candidates, season, regular_hours)
            push!(dims, _rank_transform(means))
        end

        if isempty(value_columns)
            value_columns = [Float64[] for _ in dims]
        end
        length(value_columns) == length(dims) || throw(ArgumentError(
            "Season $season produced $(length(dims)) copula dimensions, but earlier " *
            "seasons produced $(length(value_columns))",
        ))
        for (dimension, ranks) in enumerate(dims)
            append!(value_columns[dimension], ranks)
        end

        X = permutedims(reduce(hcat, dims))
        cluster_of = _best_kmeans(X, n_cluster, rng; n_init, season)

        for (i, (year, offset)) in enumerate(candidates)
            push!(rows, (Season = String(season), Year = year, SampleIndex = offset, ClusterGroup = cluster_of[i]))
        end
    end

    path = _copula_cluster_path(data_folder)
    mkpath(dirname(path))
    CSV.write(path, _copula_cluster_table(rows, value_columns))
    return rows
end

function _read_copula_clusters(data_folder)
    path = _copula_cluster_path(data_folder)
    isfile(path) || throw(ArgumentError(
        "copula_clusters_use is true, but no copula cluster file found at $path. " *
        "Set copula_clusters_make=true first to build it.",
    ))
    rows = CopulaClusterRow[]
    for row in CSV.File(path; normalizenames = false)
        push!(rows, (
            Season = String(row.Season),
            Year = Int(row.Year),
            SampleIndex = Int(row.SampleIndex),
            ClusterGroup = Int(row.ClusterGroup),
        ))
    end
    return rows
end

function _pick_copula_cluster_sample(rng, clusters::Vector{CopulaClusterRow}, season::AbstractString, cluster::Int)
    matches = filter(r -> r.Season == season && r.ClusterGroup == cluster, clusters)
    isempty(matches) && throw(ArgumentError(
        "No candidate windows found for season=$season, cluster=$cluster in copula_clusters.csv",
    ))
    year = rand(rng, unique(r.Year for r in matches))
    year_matches = filter(r -> r.Year == year, matches)
    sample_hour = rand(rng, [r.SampleIndex for r in year_matches])
    return year, sample_hour
end

_scenario_name(scenario_index::Int) = "scenario$scenario_index"
_normalized_scenario_value(value) = value <= 0.001 ? 0.0 : value

function _fill_load_values!(
    profiles::Dict{Tuple{String, Int, Int, Int}, Vector{Float64}},
    rows::Vector{LoadScenarioRow},
    table::RawScenarioTable,
    columns_to_nodes,
    indices,
    strategic_index::Int,
    representative_index::Int,
    scenario_index::Int,
    first_operational_hour::Int,
)
    scenario = _scenario_name(scenario_index)
    for (col, node) in columns_to_nodes
        vals = get!(profiles, (node, strategic_index, representative_index, scenario_index), Float64[])
        source = table.values[col]
        for (offset, idx) in enumerate(indices)
            value = _normalized_scenario_value(source[idx])
            push!(vals, value)
            push!(rows, (
                Node = node,
                Operationalhour = first_operational_hour + offset - 1,
                Scenario = scenario,
                Period = strategic_index,
                ElectricLoadRaw_in_MW = value,
            ))
        end
    end
end

function _fill_hydro_values!(
    profiles::Dict{Tuple{String, Int, Int, Int}, Vector{Float64}},
    rows::Vector{HydroScenarioRow},
    table::RawScenarioTable,
    columns_to_nodes,
    indices,
    strategic_index::Int,
    representative_index::Int,
    scenario_index::Int,
    season::AbstractString,
    first_operational_hour::Int,
)
    scenario = _scenario_name(scenario_index)
    for (col, node) in columns_to_nodes
        vals = get!(profiles, (node, strategic_index, representative_index, scenario_index), Float64[])
        source = table.values[col]
        for (offset, idx) in enumerate(indices)
            value = _normalized_scenario_value(source[idx])
            push!(vals, value)
            push!(rows, (
                Node = node,
                Period = strategic_index,
                Season = String(season),
                Operationalhour = first_operational_hour + offset - 1,
                Scenario = scenario,
                HydroGeneratorMaxSeasonalProduction = value,
            ))
        end
    end
end

function _fill_generator_values!(
    profiles::Dict{Tuple{String, String, Int, Int, Int}, Vector{Float64}},
    rows::Vector{GeneratorScenarioRow},
    table::RawScenarioTable,
    columns_to_node_gens,
    indices,
    strategic_index::Int,
    representative_index::Int,
    scenario_index::Int,
    first_operational_hour::Int,
)
    scenario = _scenario_name(scenario_index)
    for (col, node_gens) in columns_to_node_gens
        source = table.values[col]
        for (node, gen) in node_gens
            vals = get!(profiles, (node, gen, strategic_index, representative_index, scenario_index), Float64[])
            for (offset, idx) in enumerate(indices)
                value = _normalized_scenario_value(source[idx])
                push!(vals, value)
                push!(rows, (
                    Node = node,
                    IntermitentGenerators = gen,
                    Operationalhour = first_operational_hour + offset - 1,
                    Scenario = scenario,
                    Period = strategic_index,
                    GeneratorStochasticAvailabilityRaw = value,
                ))
            end
        end
    end
end

function _build_node_profiles(profiles::Dict{Tuple{String, Int, Int, Int}, Vector{Float64}}, periods)
    nodes = sort!(collect(Set(k[1] for k in keys(profiles))))
    out = Dict{String, TimeProfile}()
    for n in nodes
        repr_profiles = RepresentativeProfile[]
        for (strategic_index, strategic_period) in enumerate(strat_periods(periods))
            scen_profiles = ScenarioProfile[]
            for (representative_index, representative_period) in enumerate(repr_periods(strategic_period))
                op_profiles = OperationalProfile[]
                for (scenario_index, operational_scenario) in enumerate(opscenarios(representative_period))
                    vals = get(profiles, (n, strategic_index, representative_index, scenario_index), Float64[])
                    length(vals) == length(operational_scenario) || throw(ArgumentError(
                        "Scenario profile for node $n, period $strategic_index, " *
                        "representative period $representative_index, scenario $scenario_index " *
                        "has $(length(vals)) values; expected $(length(operational_scenario))",
                    ))
                    push!(op_profiles, OperationalProfile(vals))
                end
                push!(scen_profiles, ScenarioProfile(op_profiles))
            end
            push!(repr_profiles, RepresentativeProfile(scen_profiles))
        end
        out[n] = StrategicProfile(repr_profiles)
    end
    return out
end

function _build_generator_profiles(
    profiles::Dict{Tuple{String, String, Int, Int, Int}, Vector{Float64}},
    periods,
)
    node_gens = sort!(collect(Set((k[1], k[2]) for k in keys(profiles))))
    out = Dict{Tuple{String, String}, TimeProfile}()
    for (n, g) in node_gens
        repr_profiles = RepresentativeProfile[]
        for (strategic_index, strategic_period) in enumerate(strat_periods(periods))
            scen_profiles = ScenarioProfile[]
            for (representative_index, representative_period) in enumerate(repr_periods(strategic_period))
                op_profiles = OperationalProfile[]
                for (scenario_index, operational_scenario) in enumerate(opscenarios(representative_period))
                    vals = get(profiles, (n, g, strategic_index, representative_index, scenario_index), Float64[])
                    length(vals) == length(operational_scenario) || throw(ArgumentError(
                        "Scenario profile for generator $((n, g)), period $strategic_index, " *
                        "representative period $representative_index, scenario $scenario_index " *
                        "has $(length(vals)) values; expected $(length(operational_scenario))",
                    ))
                    push!(op_profiles, OperationalProfile(vals))
                end
                push!(scen_profiles, ScenarioProfile(op_profiles))
            end
            push!(repr_profiles, RepresentativeProfile(scen_profiles))
        end
        out[(n, g)] = StrategicProfile(repr_profiles)
    end
    return out
end

function _generator_columns(table::RawScenarioTable, generator::AbstractString, sets)
    node_set = Set(nodes(sets))
    node_gens = Set(sets.GeneratorsOfNode)
    mapping = Tuple{String, Vector{Tuple{String, String}}}[]
    for col in table.columns
        pairs = Tuple{String, String}[]
        for node in _node_names_for_generator(col, generator, node_set)
            (node, generator) in node_gens && push!(pairs, (node, generator))
        end
        !isempty(pairs) && push!(mapping, (col, pairs))
    end
    return mapping
end

function _node_columns(table::RawScenarioTable, sets)
    node_set = Set(nodes(sets))
    mapping = Tuple{String, String}[]
    for col in table.columns
        node = _node_name(col, node_set)
        node !== nothing && push!(mapping, (col, node))
    end
    return mapping
end

function _offshore_generators(sets)
    gens = String[]
    "Windoffshore" in sets.Generator && push!(gens, "Windoffshore")
    "Windoffshoregrounded" in sets.Generator && push!(gens, "Windoffshoregrounded")
    "Windoffshorefloating" in sets.Generator && push!(gens, "Windoffshorefloating")
    return gens
end

function _raw_generator_sources(data_folder::AbstractString, dateformat::DateFormat, sets)
    sources = Tuple{String, RawScenarioTable}[
        ("Solar", _read_raw_scenario_table(_required_scenario_csv(data_folder, "solar.csv"), dateformat)),
        ("Windonshore", _read_raw_scenario_table(_required_scenario_csv(data_folder, "windonshore.csv"), dateformat)),
    ]
    offshore_table = _read_raw_scenario_table(_required_scenario_csv(data_folder, "windoffshore.csv"), dateformat)
    for generator in _offshore_generators(sets)
        push!(sources, (generator, offshore_table))
    end
    push!(
        sources,
        ("Hydrorun-of-the-river", _read_raw_scenario_table(_required_scenario_csv(data_folder, "hydroror.csv"), dateformat)),
    )
    return sources
end

"""
    generate_scenario_csv!(data_folder, periods, params, sets, config; rng=Random.default_rng())

Sample raw CSV scenario time series, write generated stochastic CSV files, and
fill `sloadRaw`, `maxRegHydroGenRaw`, and `genCapAvail` directly on `params`.
"""
function generate_scenario_csv!(data_folder, periods, params::EmpireParams, sets, config; rng = Random.default_rng())
    scenario_dir = joinpath(data_folder, "ScenarioData")
    @info "Generating stochastic scenario CSV data in $scenario_dir"

    dateformat = _python_dateformat(get(config, "time_format", "%d/%m/%Y %H:%M"))
    regular_seasons = regular_scenario_seasons(config)
    regular_hours = Int(config["length_of_regular_season"])
    peak_count = scenario_peak_count(config)
    peak_hours = scenario_peak_hours(config)
    fixed_sample = get(config, "use_fixed_sample", false)
    sample_key = fixed_sample ? _sampling_key(data_folder) : nothing
    filter_make = get(config, "filter_make", false)
    filter_use = get(config, "filter_use", false)
    n_cluster = Int(get(config, "n_cluster", 10))
    weather_scenarios = weather_scenario_count(config)
    gas_scenarios = gas_scenario_count(config)

    load_table = _read_raw_scenario_table(_required_scenario_csv(data_folder, "electricload.csv"), dateformat)
    hydro_table = _read_raw_scenario_table(_required_scenario_csv(data_folder, "hydroseasonal.csv"), dateformat)
    generator_sources = _raw_generator_sources(data_folder, dateformat, sets)
    sample_years = _sample_years(load_table, hydro_table, (source[2] for source in generator_sources)...)
    if filter_make || (!fixed_sample && filter_use)
        n_cluster > 0 || throw(ArgumentError("n_cluster must be positive"))
    end
    if filter_make
        _make_filter_result!(
            scenario_dir,
            load_table,
            regular_seasons,
            regular_hours,
            n_cluster,
            sample_years,
            rng,
        )
    end
    filter_groups = if !fixed_sample && filter_use
        _filter_candidate_groups(
            scenario_dir,
            regular_seasons,
            n_cluster,
            load_table,
            regular_hours,
            sample_years,
        )
    else
        nothing
    end
    filter_cluster = n_cluster - 1

    copula_clusters_make = get(config, "copula_clusters_make", false)
    copula_clusters_use = get(config, "copula_clusters_use", false)
    copulas_to_use = get(config, "copulas_to_use", ["electricload"])

    if copula_clusters_make
        @info "Making copula clusters..."
        make_copula_clusters(
            data_folder,
            regular_seasons,
            regular_hours,
            copulas_to_use,
            n_cluster,
            load_table,
            hydro_table,
            generator_sources,
            rng,
        )
    end
    # Only load the catalog when copula clustering will actually drive sampling.
    # Fixed sampling and the scenario filter both take precedence, and a stale
    # `copula_clusters_use: true` left in a config must not fail those runs.
    copula_clusters =
        if !fixed_sample && copula_clusters_use && filter_groups === nothing
            _read_copula_clusters(data_folder)
        else
            nothing
        end
    cluster_state = Ref(n_cluster - 1)

    load_columns = _node_columns(load_table, sets)
    hydro_columns = _node_columns(hydro_table, sets)
    generator_columns = Dict(g => _generator_columns(table, g, sets) for (g, table) in generator_sources)

    load_profiles = Dict{Tuple{String, Int, Int, Int}, Vector{Float64}}()
    hydro_profiles = Dict{Tuple{String, Int, Int, Int}, Vector{Float64}}()
    gen_profiles = Dict{Tuple{String, String, Int, Int, Int}, Vector{Float64}}()
    load_rows = LoadScenarioRow[]
    hydro_rows = HydroScenarioRow[]
    generator_rows = GeneratorScenarioRow[]
    sampling_rows = SamplingKeyRow[]

    for (strategic_index, strategic_period) in enumerate(strat_periods(periods))
        representative_periods = collect(repr_periods(strategic_period))
        operational_scenario_count = length(opscenarios(first(representative_periods)))
        operational_scenario_count == Base.checked_mul(weather_scenarios, gas_scenarios) ||
            throw(ArgumentError(
                "Time structure has $operational_scenario_count operational scenarios, " *
                "but configuration requires $weather_scenarios weather × " *
                "$gas_scenarios gas scenarios",
            ))
        for weather_scenario in 1:weather_scenarios
            combined_scenarios =
                ((weather_scenario - 1) * gas_scenarios + 1):(weather_scenario * gas_scenarios)
            for (season_index, season) in enumerate(regular_seasons)
                season_index > length(representative_periods) && break
                if fixed_sample
                    year, sample_hour =
                        _get_fixed_sample(sample_key, strategic_index, weather_scenario, season)
                elseif filter_groups !== nothing
                    filter_cluster = filter_cluster == n_cluster - 1 ? 0 : filter_cluster + 1
                    year, sample_hour = _sample_filter_candidate(
                        rng,
                        filter_groups[(String(season), filter_cluster)],
                    )
                elseif copula_clusters !== nothing
                    cluster_state[] = mod(cluster_state[] + 1, n_cluster)
                    year, sample_hour = _pick_copula_cluster_sample(rng, copula_clusters, season, cluster_state[])
                else
                    year = rand(rng, sample_years)
                    sample_hour = _random_regular_sample(rng, load_table, year, season, regular_hours)
                end
                load_indices = _sample_regular_indices(load_table, year, season, sample_hour, regular_hours)
                hydro_indices = _sample_regular_indices(hydro_table, year, season, sample_hour, regular_hours)
                !fixed_sample && push!(sampling_rows, (
                    Period = strategic_index,
                    Scenario = weather_scenario,
                    Season = String(season),
                    Year = year,
                    Month = _sample_month(load_table, load_indices),
                    Hour = sample_hour,
                ))
                first_operational_hour = (season_index - 1) * regular_hours + 1
                for combined_scenario in combined_scenarios
                    _fill_load_values!(
                        load_profiles,
                        load_rows,
                        load_table,
                        load_columns,
                        load_indices,
                        strategic_index,
                        season_index,
                        combined_scenario,
                        first_operational_hour,
                    )
                    _fill_hydro_values!(
                        hydro_profiles,
                        hydro_rows,
                        hydro_table,
                        hydro_columns,
                        hydro_indices,
                        strategic_index,
                        season_index,
                        combined_scenario,
                        season,
                        first_operational_hour,
                    )
                    for (generator, table) in generator_sources
                        indices = _sample_regular_indices(
                            table,
                            year,
                            season,
                            sample_hour,
                            regular_hours,
                        )
                        _fill_generator_values!(
                            gen_profiles,
                            generator_rows,
                            table,
                            generator_columns[generator],
                            indices,
                            strategic_index,
                            season_index,
                            combined_scenario,
                            first_operational_hour,
                        )
                    end
                end
            end

            peak_start = length(regular_seasons) + 1
            if peak_count > 0 && peak_start <= length(representative_periods)
                if fixed_sample
                    peak_year, _ =
                        _get_fixed_sample(sample_key, strategic_index, weather_scenario, "peak")
                else
                    peak_year = rand(rng, sample_years)
                end
                !fixed_sample && push!(sampling_rows, (
                    Period = strategic_index,
                    Scenario = weather_scenario,
                    Season = "peak",
                    Year = peak_year,
                    Month = 0,
                    Hour = 0,
                ))

                country_peak, overall_peak = _peak_centers(load_table, peak_year)
                peak_centers = (country_peak, overall_peak)
                max_peak_offset = min(peak_count - 1, length(representative_periods) - peak_start, length(peak_centers) - 1)
                for peak_offset in 0:max_peak_offset
                    representative_index = peak_start + peak_offset
                    center = peak_centers[peak_offset + 1]
                    season = "peak$(peak_offset + 1)"
                    first_operational_hour = length(regular_seasons) * regular_hours + peak_offset * peak_hours + 1
                    load_indices = _sample_peak_indices(load_table, peak_year, center, peak_hours)
                    hydro_indices = _sample_peak_indices(hydro_table, peak_year, center, peak_hours)
                    for combined_scenario in combined_scenarios
                        _fill_load_values!(
                            load_profiles,
                            load_rows,
                            load_table,
                            load_columns,
                            load_indices,
                            strategic_index,
                            representative_index,
                            combined_scenario,
                            first_operational_hour,
                        )
                        _fill_hydro_values!(
                            hydro_profiles,
                            hydro_rows,
                            hydro_table,
                            hydro_columns,
                            hydro_indices,
                            strategic_index,
                            representative_index,
                            combined_scenario,
                            season,
                            first_operational_hour,
                        )
                        for (generator, table) in generator_sources
                            indices =
                                _sample_peak_indices(table, peak_year, center, peak_hours)
                            _fill_generator_values!(
                                gen_profiles,
                                generator_rows,
                                table,
                                generator_columns[generator],
                                indices,
                                strategic_index,
                                representative_index,
                                combined_scenario,
                                first_operational_hour,
                            )
                        end
                    end
                end
            end
        end
    end

    _write_generated_scenario_csvs!(
        scenario_dir,
        load_rows,
        hydro_rows,
        generator_rows,
        sampling_rows;
        write_sampling_key = !fixed_sample,
    )

    params.sloadRaw = _build_node_profiles(load_profiles, periods)
    params.maxRegHydroGenRaw = _build_node_profiles(hydro_profiles, periods)
    params.genCapAvail = _build_generator_profiles(gen_profiles, periods)
    _fill_missing_stochastic_availability!(params, sets, periods)
    _validate_stochastic_availability(params, sets)

    return params
end

read_scenario_csv!(data_folder, periods, params::EmpireParams, sets, config; rng = Random.default_rng()) =
    generate_scenario_csv!(data_folder, periods, params, sets, config; rng)

function _write_generated_scenario_csvs!(
    scenario_dir::AbstractString,
    load_rows::Vector{LoadScenarioRow},
    hydro_rows::Vector{HydroScenarioRow},
    generator_rows::Vector{GeneratorScenarioRow},
    sampling_rows::Vector{SamplingKeyRow};
    write_sampling_key::Bool,
)
    mkpath(scenario_dir)
    CSV.write(joinpath(scenario_dir, "sloadRaw.csv"), load_rows)
    CSV.write(joinpath(scenario_dir, "maxRegHydroGenRaw.csv"), hydro_rows)
    CSV.write(joinpath(scenario_dir, "genCapAvailStochRaw.csv"), generator_rows)
    write_sampling_key && CSV.write(joinpath(scenario_dir, "sampling_key.csv"), sampling_rows)
    return nothing
end

function _zero_time_profile(periods)
    repr_profiles = RepresentativeProfile[]
    for strategic_period in strat_periods(periods)
        scen_profiles = ScenarioProfile[]
        for representative_period in repr_periods(strategic_period)
            op_profiles = OperationalProfile[]
            for operational_scenario in opscenarios(representative_period)
                push!(op_profiles, OperationalProfile(zeros(Float64, length(operational_scenario))))
            end
            push!(scen_profiles, ScenarioProfile(op_profiles))
        end
        push!(repr_profiles, RepresentativeProfile(scen_profiles))
    end
    return StrategicProfile(repr_profiles)
end

function _fill_missing_stochastic_availability!(params::EmpireParams, sets, periods)
    zero_profile = nothing
    for (node, generator) in sets.GeneratorsOfNode
        get(params.genCapAvailType, generator, 1.0) == 0.0 || continue
        haskey(params.genCapAvail, (node, generator)) && continue
        zero_profile === nothing && (zero_profile = _zero_time_profile(periods))
        params.genCapAvail[(node, generator)] = zero_profile
    end
end

function _validate_stochastic_availability(params::EmpireParams, sets)
    missing_pairs = Tuple{String, String}[]
    for (node, generator) in sets.GeneratorsOfNode
        get(params.genCapAvailType, generator, 1.0) == 0.0 || continue
        haskey(params.genCapAvail, (node, generator)) && continue
        push!(missing_pairs, (node, generator))
    end
    if !isempty(missing_pairs)
        preview = join(string.(missing_pairs[1:min(end, 20)]), ", ")
        suffix = length(missing_pairs) > 20 ? " ..." : ""
        throw(ArgumentError("Missing stochastic availability for generator-node pair(s): $preview$suffix"))
    end
end

function _read_generated_node_profiles(
    file::AbstractString,
    periods,
    season_for_hour::Dict{Int, Int},
    value_column::Symbol,
)
    @info "Reading generated scenario CSV data from $file"
    profiles = Dict{Tuple{String,Int,Int,Int}, Vector{Float64}}()

    for row in CSV.File(file; normalizenames = false)
        node = String(row.Node)
        strategic_index = Int(row.Period)
        representative_index = season_for_hour[Int(row.Operationalhour)]
        scenario_index = scenario_id(String(row.Scenario))
        scenario_index === nothing && throw(ArgumentError("Invalid scenario name in $file: $(row.Scenario)"))
        vals = get!(profiles, (node, strategic_index, representative_index, scenario_index), Float64[])
        push!(vals, _float_value(getproperty(row, value_column)))
    end

    return _build_node_profiles(profiles, periods)
end

function _read_generated_generator_profiles(
    file::AbstractString,
    periods::TimeStructure,
    season_for_hour::Dict{Int, Int},
)
    @info "Reading generated scenario CSV data from $file"
    profiles = Dict{Tuple{String,String,Int,Int,Int}, Vector{Float64}}()

    for row in CSV.File(file; normalizenames = false)
        node = String(row.Node)
        generator = String(row.IntermitentGenerators)
        strategic_index = Int(row.Period)
        representative_index = season_for_hour[Int(row.Operationalhour)]
        scenario_index = scenario_id(String(row.Scenario))
        scenario_index === nothing && throw(ArgumentError("Invalid scenario name in $file: $(row.Scenario)"))
        vals = get!(profiles, (node, generator, strategic_index, representative_index, scenario_index), Float64[])
        push!(vals, _float_value(row.GeneratorStochasticAvailabilityRaw))
    end

    return _build_generator_profiles(profiles, periods)
end

function read_generated_scenario_csv!(
    data_folder,
    periods,
    params::EmpireParams,
    sets,
    season_for_hour::Dict{Int, Int},
)
    sload_file, hydro_file, availability_file = _generated_scenario_csv_files(data_folder)

    params.sloadRaw = _read_generated_node_profiles(
        sload_file,
        periods,
        season_for_hour,
        :ElectricLoadRaw_in_MW,
    )
    params.maxRegHydroGenRaw = _read_generated_node_profiles(
        hydro_file,
        periods,
        season_for_hour,
        :HydroGeneratorMaxSeasonalProduction,
    )
    params.genCapAvail = _read_generated_generator_profiles(
        availability_file,
        periods,
        season_for_hour,
    )
    _fill_missing_stochastic_availability!(params, sets, periods)
    _validate_stochastic_availability(params, sets)

    return params
end
