#!/usr/bin/env julia

using OpenEMPIRE

function _parse_oos_aggregation_args(args)
    roots = String[]
    output = ""
    event_threshold_mw = 1e-6
    combined_files = collect(OpenEMPIRE.OOS_DEFAULT_COMBINED_RESULT_FILES)
    overwrite = false
    for argument in args
        if startswith(argument, "--output=")
            output = split(argument, "="; limit = 2)[2]
        elseif startswith(argument, "--event-threshold-mw=")
            event_threshold_mw = parse(Float64, split(argument, "="; limit = 2)[2])
        elseif startswith(argument, "--files=")
            value = strip(split(argument, "="; limit = 2)[2])
            combined_files = if lowercase(value) == "none"
                String[]
            else
                [
                    endswith(strip(name), ".csv") ? strip(name) : "$(strip(name)).csv"
                    for name in split(value, ",") if !isempty(strip(name))
                ]
            end
        elseif startswith(argument, "--overwrite=")
            value = lowercase(strip(split(argument, "="; limit = 2)[2]))
            value in ("true", "false") || throw(ArgumentError(
                "--overwrite must be true or false",
            ))
            overwrite = value == "true"
        elseif startswith(argument, "--")
            throw(ArgumentError("Unsupported option: $argument"))
        else
            push!(roots, argument)
        end
    end
    isempty(roots) && throw(ArgumentError("Provide at least one OOS result directory or root"))
    return (; roots, output, event_threshold_mw, combined_files, overwrite)
end

function main(args = ARGS)
    options = _parse_oos_aggregation_args(args)
    result_dirs = OpenEMPIRE.discover_oos_result_dirs(options.roots)
    output_dir = if isempty(options.output)
        joinpath(abspath(first(options.roots)), "aggregated")
    else
        options.output
    end
    result = OpenEMPIRE.aggregate_oos_results(
        result_dirs,
        output_dir;
        event_threshold_mw = options.event_threshold_mw,
        combined_files = options.combined_files,
        overwrite = options.overwrite,
    )
    println("Validated and aggregated $(length(result.summaries)) OOS tree(s)")
    println("Tree summary: $(result.summary_file)")
    println("ENS by period/scenario: $(result.scenario_file)")
    println("Aggregation manifest: $(result.manifest_file)")
    for combined in result.combined_files
        println("Combined $(combined.name): $(combined.rows) rows")
    end
    return result.output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
