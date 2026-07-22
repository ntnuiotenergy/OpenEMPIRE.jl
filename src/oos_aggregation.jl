const _OOS_AGGREGATION_SCHEMA_VERSION = 1
const OOS_DEFAULT_COMBINED_RESULT_FILES = (
    "genOperational.csv",
    "transmissionOperational.csv",
    "storCharge.csv",
    "storDischarge.csv",
    "loadShed.csv",
)

mutable struct _OOSEnsAccumulator
    conditional_mwh::Float64
    expected_mwh::Float64
    node_hours_above_threshold::Int
    max_mw::Float64
    max_node::String
    max_period::Int
    max_scenario::Int
    max_season::String
    max_hour::Int
end

_OOSEnsAccumulator() = _OOSEnsAccumulator(0.0, 0.0, 0, 0.0, "", 0, 0, "", 0)

function _oos_required_mapping(mapping, key::AbstractString, context::AbstractString)
    mapping isa AbstractDict || throw(ArgumentError("$context must be a mapping"))
    value = get(mapping, key, nothing)
    value isa AbstractDict || throw(ArgumentError("$context is missing mapping '$key'"))
    return value
end

function _oos_required_string(mapping, key::AbstractString, context::AbstractString)
    value = get(mapping, key, nothing)
    value isa AbstractString && !isempty(strip(value)) || throw(ArgumentError(
        "$context is missing non-empty string '$key'",
    ))
    return String(value)
end

function _oos_required_real(mapping, key::AbstractString, context::AbstractString)
    value = get(mapping, key, nothing)
    value isa Real || throw(ArgumentError("$context is missing numeric '$key'"))
    result = Float64(value)
    isfinite(result) || throw(ArgumentError("$context '$key' must be finite"))
    return result
end

function _oos_result_output_dir(result_dir::AbstractString)
    for name in ("output", "Output")
        output_dir = joinpath(result_dir, name)
        isdir(output_dir) && return output_dir
    end
    throw(ArgumentError("OOS result has no output directory: $result_dir"))
end

function _stream_combined_oos_csv(summaries, filename::AbstractString, output_dir::AbstractString)
    output_file = joinpath(output_dir, filename)
    mkpath(dirname(output_file))
    expected_header = nothing
    rows_written = 0
    open(output_file, "w") do io
        for summary in summaries
            input_file = joinpath(_oos_result_output_dir(summary.RunDirectory), filename)
            isfile(input_file) || throw(ArgumentError(
                "OOS result $(summary.Tree) is missing $filename: $input_file",
            ))
            open(input_file, "r") do input
                eof(input) && throw(ArgumentError("OOS result CSV is empty: $input_file"))
                header = chomp(readline(input))
                if expected_header === nothing
                    expected_header = header
                    println(io, "Tree,Seed,Run,", header)
                elseif header != expected_header
                    throw(ArgumentError(
                        "OOS result CSV header mismatch for $input_file",
                    ))
                end
                prefix = join(
                    _csv_field.((summary.Tree, summary.Seed, basename(summary.RunDirectory))),
                    ",",
                )
                for line in eachline(input)
                    isempty(line) && continue
                    println(io, prefix, ",", line)
                    rows_written += 1
                end
            end
        end
    end
    return (
        name = filename,
        path = output_file,
        rows = rows_written,
        sha256 = _oos_sha256_file(output_file),
        bytes = filesize(output_file),
    )
end


function _oos_time_weights(config)
    horizon = Int(config["forecast_horizon_year"])
    strategic_duration = Int(config["leap_years_investment"])
    strategic_periods = round(Int, (horizon - 2020) / strategic_duration)
    strategic_periods > 0 || throw(ArgumentError(
        "OOS configuration must contain at least one strategic period",
    ))

    regular_seasons = collect(regular_scenario_seasons(config))
    regular_hours = Int(config["length_of_regular_season"])
    peak_count = scenario_peak_count(config)
    peak_hours = scenario_peak_hours(config)
    scenario_count = Int(config["number_of_scenarios"])
    season_names = vcat(regular_seasons, ["peak$i" for i in 1:peak_count])

    periods = create_timestruct(
        strategic_periods,
        strategic_duration,
        length(regular_seasons),
        regular_hours,
        peak_count,
        peak_hours,
        scenario_count,
    )
    weights = Dict{Tuple{Int, Int, String, Int}, NamedTuple{
        (:conditional, :probability, :expected),
        Tuple{Float64, Float64, Float64},
    }}()
    for (period_index, strategic_period) in enumerate(strat_periods(periods))
        for (representative_index, representative_period) in
            enumerate(repr_periods(strategic_period))
            season = season_names[representative_index]
            for (scenario_index, scenario) in enumerate(opscenarios(representative_period))
                for (hour, operational_period) in enumerate(scenario)
                    conditional = Float64(
                        multiple_strat(strategic_period, operational_period) *
                        duration(operational_period),
                    )
                    scenario_probability = Float64(probability(operational_period))
                    weights[(period_index, scenario_index, season, hour)] = (
                        conditional = conditional,
                        probability = scenario_probability,
                        expected = conditional * scenario_probability,
                    )
                end
            end
        end
    end
    return weights
end

function _update_oos_ens!(
    accumulator::_OOSEnsAccumulator,
    shed_mw::Float64,
    time_weight;
    node::AbstractString,
    period::Int,
    scenario::Int,
    season::AbstractString,
    hour::Int,
    event_threshold_mw::Float64,
)
    accumulator.conditional_mwh += shed_mw * time_weight.conditional
    accumulator.expected_mwh += shed_mw * time_weight.expected
    if shed_mw > event_threshold_mw
        accumulator.node_hours_above_threshold += 1
    end
    if shed_mw > accumulator.max_mw
        accumulator.max_mw = shed_mw
        accumulator.max_node = String(node)
        accumulator.max_period = period
        accumulator.max_scenario = scenario
        accumulator.max_season = String(season)
        accumulator.max_hour = hour
    end
    return accumulator
end

function _oos_fixed_investments_verified(result_dir::AbstractString, output_dir::AbstractString)
    input_dir = joinpath(result_dir, "Input", "fixed_investments")
    input_metadata = _oos_fixed_capacity_metadata(input_dir)
    for aliases in _OOS_FIXED_INVESTMENT_FILENAMES
        input_name = findfirst(name -> isfile(joinpath(input_dir, name)), aliases)
        output_name = findfirst(name -> isfile(joinpath(output_dir, name)), aliases)
        input_name === nothing && throw(ArgumentError(
            "Staged OOS investments are missing one of: $(join(aliases, ", "))",
        ))
        output_name === nothing && throw(ArgumentError(
            "OOS result investments are missing one of: $(join(aliases, ", "))",
        ))
        input_hash = _oos_sha256_file(joinpath(input_dir, aliases[input_name]))
        output_hash = _oos_sha256_file(joinpath(output_dir, aliases[output_name]))
        input_hash == output_hash || throw(ArgumentError(
            "OOS result changed fixed investment table $(aliases[input_name])",
        ))
    end
    return String(input_metadata["sha256"])
end

function _oos_objective_summary(solution)
    objective = _oos_required_real(solution, "objective_value", "OOS solution")
    components = _oos_required_mapping(solution, "objective_components", "OOS solution")
    component_values = Dict{String, Float64}()
    for (name, value) in components
        value isa Real || throw(ArgumentError("OOS objective component '$name' is not numeric"))
        component_values[String(name)] = Float64(value)
    end
    component_total = sum(values(component_values); init = 0.0)
    isapprox(component_total, objective; rtol = 1e-8, atol = 1e-3) || throw(ArgumentError(
        "OOS objective components sum to $component_total, not objective value $objective",
    ))
    fixed_cost = sum(
        value for (name, value) in component_values if endswith(name, "_investment");
        init = 0.0,
    )
    return (
        objective = objective,
        fixed_investment = fixed_cost,
        generator_operation = get(component_values, "generator_operation", 0.0),
        load_shedding = get(component_values, "load_shedding", 0.0),
        non_investment = objective - fixed_cost,
    )
end

function _oos_ens_rows(
    load_shed_file::AbstractString,
    config,
    tree::AbstractString,
    seed::Int;
    event_threshold_mw::Float64,
)
    weights = _oos_time_weights(config)
    scenario_accumulators = Dict{Tuple{Int, Int}, _OOSEnsAccumulator}()
    season_accumulators = Dict{Tuple{Int, Int, String}, _OOSEnsAccumulator}()
    total = _OOSEnsAccumulator()

    types = Dict(
        :Node => String,
        :Period => Int,
        :Scenario => Int,
        :Season => String,
        :Hour => Int,
        :loadShed => Float64,
    )
    for row in CSV.Rows(load_shed_file; types = types, strict = true, reusebuffer = true)
        raw_shed = Float64(row.loadShed)
        isfinite(raw_shed) || throw(ArgumentError("Non-finite load shedding in $load_shed_file"))
        raw_shed >= -event_threshold_mw || throw(ArgumentError(
            "Negative load shedding $raw_shed MW exceeds tolerance in $load_shed_file",
        ))
        shed_mw = max(raw_shed, 0.0)
        period = Int(row.Period)
        scenario = Int(row.Scenario)
        season = String(row.Season)
        hour = Int(row.Hour)
        node = String(row.Node)
        key = (period, scenario, season, hour)
        haskey(weights, key) || throw(ArgumentError(
            "loadShed.csv contains operational index not present in its staged configuration: $key",
        ))
        time_weight = weights[key]
        scenario_accumulator = get!(_OOSEnsAccumulator, scenario_accumulators, (period, scenario))
        season_accumulator = get!(_OOSEnsAccumulator, season_accumulators, (period, scenario, season))
        for accumulator in (scenario_accumulator, season_accumulator, total)
            _update_oos_ens!(
                accumulator,
                shed_mw,
                time_weight;
                node,
                period,
                scenario,
                season,
                hour,
                event_threshold_mw,
            )
        end
    end

    scenario_rows = [
        begin
            probability_value = first(
                weight.probability for ((p, s, _, _), weight) in weights
                if p == period && s == scenario
            )
            (
                Tree = String(tree),
                Seed = seed,
                Period = period,
                Scenario = scenario,
                ScenarioProbability = probability_value,
                ConditionalAnnualENS_MWh = accumulator.conditional_mwh,
                ExpectedAnnualENSContribution_MWh = accumulator.expected_mwh,
                NodeHoursAboveThreshold = accumulator.node_hours_above_threshold,
                MaxLoadShed_MW = accumulator.max_mw,
                MaxNode = accumulator.max_node,
                MaxSeason = accumulator.max_season,
                MaxHour = accumulator.max_hour,
            )
        end for ((period, scenario), accumulator) in sort!(collect(scenario_accumulators); by = first)
    ]
    season_rows = [
        (
            Tree = String(tree),
            Seed = seed,
            Period = period,
            Scenario = scenario,
            Season = season,
            ConditionalAnnualENS_MWh = accumulator.conditional_mwh,
            ExpectedAnnualENSContribution_MWh = accumulator.expected_mwh,
            NodeHoursAboveThreshold = accumulator.node_hours_above_threshold,
            MaxLoadShed_MW = accumulator.max_mw,
            MaxNode = accumulator.max_node,
            MaxHour = accumulator.max_hour,
        ) for ((period, scenario, season), accumulator) in
            sort!(collect(season_accumulators); by = first)
    ]
    return scenario_rows, season_rows, total
end

"""
    summarize_oos_result(result_dir; event_threshold_mw=1e-6)

Validate one completed OOS result and calculate physical energy not served
(ENS) from `loadShed.csv`. Conditional ENS excludes scenario probability;
expected ENS includes `multiple_strat * probability * duration`. Neither metric
is financially discounted.
"""
function summarize_oos_result(
    result_dir::AbstractString;
    event_threshold_mw::Real = 1e-6,
)
    threshold = Float64(event_threshold_mw)
    threshold >= 0 || throw(ArgumentError("event_threshold_mw must be non-negative"))
    normalized_result_dir = abspath(normpath(result_dir))
    manifest_file = joinpath(normalized_result_dir, "run_manifest.yaml")
    isfile(manifest_file) || throw(ArgumentError("OOS run manifest not found: $manifest_file"))
    manifest = YAML.load_file(manifest_file)
    get(manifest, "status", nothing) == "complete" || throw(ArgumentError(
        "OOS run manifest is not complete: $manifest_file",
    ))
    oos = _oos_required_mapping(manifest, "out_of_sample", "run manifest")
    get(oos, "enabled", false) == true || throw(ArgumentError("Run is not marked out-of-sample"))
    get(oos, "investments_fixed", false) == true || throw(ArgumentError(
        "OOS run does not confirm fixed investments",
    ))
    get(oos, "scenario_checksums_verified", false) == true || throw(ArgumentError(
        "OOS run does not confirm scenario checksums",
    ))
    solution = _oos_required_mapping(manifest, "solution", "run manifest")
    get(solution, "is_solved_and_feasible", false) == true || throw(ArgumentError(
        "OOS run is not solved and feasible",
    ))
    get(solution, "has_values", false) == true || throw(ArgumentError("OOS run has no values"))

    input_dir = joinpath(normalized_result_dir, "Input")
    config_file = joinpath(input_dir, "config.yaml")
    metadata_file = joinpath(input_dir, "oos_tree_metadata.yaml")
    isfile(config_file) || throw(ArgumentError("Staged OOS config not found: $config_file"))
    isfile(metadata_file) || throw(ArgumentError("Staged OOS metadata not found: $metadata_file"))
    config_sha256 = _oos_sha256_file(config_file)
    config_sha256 == get(manifest, "config_sha256", nothing) || throw(ArgumentError(
        "Staged OOS config checksum does not match run manifest",
    ))
    metadata_sha256 = _oos_sha256_file(metadata_file)
    scenario_metadata = _oos_required_mapping(oos, "scenario_metadata", "OOS manifest")
    staged_metadata = YAML.load_file(metadata_file)
    scenario_metadata == staged_metadata || throw(ArgumentError(
        "Staged OOS scenario metadata does not match the run manifest",
    ))

    output_dir = _oos_result_output_dir(normalized_result_dir)
    fixed_investments_sha256 = _oos_fixed_investments_verified(normalized_result_dir, output_dir)
    tree = _oos_required_string(oos, "scenario_tree", "OOS manifest")
    seed_value = get(oos, "scenario_seed", nothing)
    seed_value isa Integer || throw(ArgumentError("OOS manifest has no integer scenario seed"))
    seed = Int(seed_value)
    objective = _oos_objective_summary(solution)
    config = YAML.load_file(config_file)
    scenario_rows, season_rows, total = _oos_ens_rows(
        joinpath(output_dir, "loadShed.csv"),
        config,
        tree,
        seed;
        event_threshold_mw = threshold,
    )

    summary = (
        Tree = tree,
        Seed = seed,
        RunDirectory = normalized_result_dir,
        RunManifestSHA256 = _oos_sha256_file(manifest_file),
        ConfigSHA256 = config_sha256,
        ScenarioMetadataSHA256 = metadata_sha256,
        FixedInvestmentsSHA256 = fixed_investments_sha256,
        FixedInvestmentsVerified = true,
        TerminationStatus = _oos_required_string(solution, "termination_status", "OOS solution"),
        Objective_EUR = objective.objective,
        DiscountedFixedInvestmentCost_EUR = objective.fixed_investment,
        DiscountedGeneratorOperationCost_EUR = objective.generator_operation,
        DiscountedLoadSheddingCost_EUR = objective.load_shedding,
        DiscountedNonInvestmentObjective_EUR = objective.non_investment,
        ExpectedAnnualENSAllPeriods_MWh = total.expected_mwh,
        NodeHoursAboveThreshold = total.node_hours_above_threshold,
        MaxLoadShed_MW = total.max_mw,
        MaxNode = total.max_node,
        MaxPeriod = total.max_period,
        MaxScenario = total.max_scenario,
        MaxSeason = total.max_season,
        MaxHour = total.max_hour,
    )
    return (
        summary = summary,
        ens_by_period_scenario = scenario_rows,
        ens_by_period_scenario_season = season_rows,
    )
end

"""
    discover_oos_result_dirs(paths)

Find directories containing OOS `run_manifest.yaml` files beneath one or more
result roots. Returned paths are absolute, unique, and sorted.
"""
function discover_oos_result_dirs(paths)
    discovered = Set{String}()
    for path in paths
        normalized = abspath(normpath(path))
        isdir(normalized) || throw(ArgumentError("OOS result path does not exist: $path"))
        if isfile(joinpath(normalized, "run_manifest.yaml"))
            push!(discovered, normalized)
            continue
        end
        for (directory, _, files) in walkdir(normalized)
            "run_manifest.yaml" in files && push!(discovered, directory)
        end
    end
    isempty(discovered) && throw(ArgumentError("No OOS run manifests found"))
    return sort!(collect(discovered))
end

"""
    aggregate_oos_results(result_dirs, output_dir; event_threshold_mw=1e-6,
                          combined_files=OOS_DEFAULT_COMBINED_RESULT_FILES,
                          overwrite=false)

Validate and aggregate completed OOS runs. All runs must use byte-identical
staged configurations and fixed investment tables. The comparison CSV keeps
discounted fixed investment cost separate from the non-investment objective
and reports physical ENS without discounting.
"""
function aggregate_oos_results(
    result_dirs,
    output_dir::AbstractString;
    event_threshold_mw::Real = 1e-6,
    combined_files = OOS_DEFAULT_COMBINED_RESULT_FILES,
    overwrite::Bool = false,
)
    isempty(result_dirs) && throw(ArgumentError("At least one OOS result directory is required"))
    normalized_output = abspath(normpath(output_dir))
    if isdir(normalized_output) && !isempty(readdir(normalized_output)) && !overwrite
        throw(ArgumentError("OOS aggregation output is not empty: $normalized_output"))
    end

    results = [
        summarize_oos_result(result_dir; event_threshold_mw) for result_dir in result_dirs
    ]
    summaries = [result.summary for result in results]
    trees = [row.Tree for row in summaries]
    allunique(trees) || throw(ArgumentError("OOS aggregation contains duplicate tree names"))
    length(unique(row.ConfigSHA256 for row in summaries)) == 1 || throw(ArgumentError(
        "OOS aggregation requires identical staged configurations",
    ))
    length(unique(row.FixedInvestmentsSHA256 for row in summaries)) == 1 ||
        throw(ArgumentError("OOS aggregation requires identical fixed investments"))

    mkpath(normalized_output)
    summary_file = joinpath(normalized_output, "oos_tree_summary.csv")
    scenario_file = joinpath(normalized_output, "oos_ens_by_period_scenario.csv")
    season_file = joinpath(normalized_output, "oos_ens_by_period_scenario_season.csv")
    CSV.write(summary_file, summaries)
    CSV.write(
        scenario_file,
        reduce(vcat, (result.ens_by_period_scenario for result in results); init = NamedTuple[]),
    )
    CSV.write(
        season_file,
        reduce(
            vcat,
            (result.ens_by_period_scenario_season for result in results);
            init = NamedTuple[],
        ),
    )
    combined_dir = joinpath(normalized_output, "combined")
    combined_results = [
        _stream_combined_oos_csv(summaries, String(filename), combined_dir) for
        filename in combined_files
    ]
    output_files = [summary_file, scenario_file, season_file]
    aggregation_manifest = Dict{String, Any}(
        "kind" => "oos_result_aggregation",
        "schema_version" => _OOS_AGGREGATION_SCHEMA_VERSION,
        "created_at_utc" => string(now(UTC), "Z"),
        "event_threshold_mw" => Float64(event_threshold_mw),
        "ens_formula" => "load_shed_mw * multiple_strat * probability * duration",
        "ens_discounted" => false,
        "tree_count" => length(results),
        "trees" => [
            Dict{String, Any}(
                "tree" => row.Tree,
                "seed" => row.Seed,
                "run_directory" => row.RunDirectory,
                "run_manifest_sha256" => row.RunManifestSHA256,
                "scenario_metadata_sha256" => row.ScenarioMetadataSHA256,
            ) for row in summaries
        ],
        "config_sha256" => only(unique(row.ConfigSHA256 for row in summaries)),
        "fixed_investments_sha256" => only(
            unique(row.FixedInvestmentsSHA256 for row in summaries),
        ),
        "combined_files" => [
            Dict{String, Any}(
                "name" => result.name,
                "path" => relpath(result.path, normalized_output),
                "rows" => result.rows,
                "sha256" => result.sha256,
                "bytes" => result.bytes,
            ) for result in combined_results
        ],
        "files" => [
            Dict{String, Any}(
                "name" => basename(path),
                "sha256" => _oos_sha256_file(path),
                "bytes" => filesize(path),
            ) for path in output_files
        ],
    )
    manifest_file = joinpath(normalized_output, "aggregation_manifest.yaml")
    YAML.write_file(manifest_file, aggregation_manifest)
    return (
        output_dir = normalized_output,
        summary_file = summary_file,
        scenario_file = scenario_file,
        season_file = season_file,
        combined_files = combined_results,
        manifest_file = manifest_file,
        summaries = summaries,
    )
end
