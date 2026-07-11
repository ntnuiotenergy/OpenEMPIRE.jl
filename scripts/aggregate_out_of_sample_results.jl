#!/usr/bin/env julia

using CSV
using Dates

const DEFAULT_AGGREGATION_FILES = (
    "genOperational.csv",
    "transmissionOperational.csv",
    "storCharge.csv",
    "storDischarge.csv",
    "loadShed.csv",
)

function _parse_aggregation_args(args)
    options = Dict{String, String}(
        "batch-dir" => "",
        "output-dir" => "",
        "files" => join(DEFAULT_AGGREGATION_FILES, ","),
        "status" => "OPTIMAL",
        "skip-missing" => "true",
        "run" => "",
    )

    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            haskey(options, key) || throw(ArgumentError("Unsupported option: --$key"))
            options[key] = value
        elseif !startswith(arg, "--")
            isempty(options["batch-dir"]) || throw(ArgumentError("Batch directory provided more than once"))
            options["batch-dir"] = arg
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end

    isempty(options["batch-dir"]) && throw(ArgumentError("Batch directory is required"))
    return options
end

function _parse_bool(value, name)
    normalized = lowercase(strip(value))
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported $name value: $value. Expected true or false."))
end

function _csv_field(value)
    text = string(value)
    if occursin(',', text) || occursin('"', text) || occursin('\n', text) || occursin('\r', text)
        return "\"$(replace(text, "\"" => "\"\""))\""
    end
    return text
end

function _read_csv_header(path)
    open(path, "r") do io
        eof(io) && throw(ArgumentError("CSV file is empty: $path"))
        return split(chomp(readline(io)), ",")
    end
end

function _tree_index(tree_name)
    matched = match(r"^oos_tree(\d+)$", tree_name)
    matched === nothing && return ""
    return matched.captures[1]
end

function _batch_run_name(batch_dir)
    return basename(normpath(batch_dir))
end

function _split_csv_list(value)
    files = String[]
    for item in split(value, ",")
        stripped = strip(item)
        isempty(stripped) || push!(files, endswith(stripped, ".csv") ? stripped : "$stripped.csv")
    end
    isempty(files) && throw(ArgumentError("--files must contain at least one CSV file name"))
    return files
end

_string_cell(value) = ismissing(value) ? "" : string(value)

function read_batch_rows(batch_dir)
    summary_path = joinpath(batch_dir, "batch_summary.csv")
    isfile(summary_path) || throw(ArgumentError("Batch summary not found: $summary_path"))

    rows = NamedTuple[]
    for row in CSV.File(summary_path)
        push!(rows, (
            tree = _string_cell(row.tree),
            seed = _string_cell(row.seed),
            status = _string_cell(row.status),
            objective = _string_cell(row.objective),
            build_seconds = _string_cell(row.build_seconds),
            solve_seconds = _string_cell(row.solve_seconds),
            result_directory = _string_cell(row.result_directory),
            error = _string_cell(row.error),
        ))
    end
    isempty(rows) && throw(ArgumentError("Batch summary has no tree rows: $summary_path"))
    return rows
end

function selected_batch_rows(rows, status_filter)
    allowed = Set(strip.(split(status_filter, ",")))
    return [row for row in rows if strip(row.status) in allowed]
end

function _output_dir_for_row(row)
    output_dir = joinpath(row.result_directory, "output")
    isdir(output_dir) && return output_dir
    alt_output_dir = joinpath(row.result_directory, "Output")
    isdir(alt_output_dir) && return alt_output_dir
    return output_dir
end

function aggregate_result_file(batch_rows, filename, output_dir; run_name, skip_missing = true)
    output_path = joinpath(output_dir, filename)
    mkpath(dirname(output_path))

    header_written = false
    expected_header = String[]
    rows_written = 0

    open(output_path, "w") do io
        for row in batch_rows
            input_path = joinpath(_output_dir_for_row(row), filename)
            if !isfile(input_path)
                skip_missing && continue
                throw(ArgumentError("Missing OOS result file for $(row.tree): $input_path"))
            end

            header = _read_csv_header(input_path)
            if !header_written
                expected_header = header
                println(io, join(vcat(["Tree", "TreeIndex", "Run"], header), ","))
                header_written = true
            elseif header != expected_header
                throw(ArgumentError(
                    "Header mismatch for $input_path. Expected $(join(expected_header, ", ")); got $(join(header, ", ")).",
                ))
            end

            symbols = Symbol.(header)
            for csv_row in CSV.File(input_path)
                values = Any[row.tree, _tree_index(row.tree), run_name]
                append!(values, (getproperty(csv_row, column) for column in symbols))
                println(io, join(_csv_field.(values), ","))
                rows_written += 1
            end
        end
    end

    if !header_written
        rm(output_path; force = true)
        skip_missing && return (file = filename, path = "", rows = 0, skipped = true)
        throw(ArgumentError("No input rows found for $filename"))
    end

    return (file = filename, path = output_path, rows = rows_written, skipped = false)
end

function write_oos_summary(batch_rows, output_dir; run_name)
    output_path = joinpath(output_dir, "oos_summary.csv")
    mkpath(dirname(output_path))
    columns = (
        "Tree",
        "TreeIndex",
        "Run",
        "Seed",
        "Status",
        "Objective",
        "BuildSeconds",
        "SolveSeconds",
        "ResultDirectory",
        "Error",
    )
    open(output_path, "w") do io
        println(io, join(columns, ","))
        for row in batch_rows
            values = (
                row.tree,
                _tree_index(row.tree),
                run_name,
                row.seed,
                row.status,
                row.objective,
                row.build_seconds,
                row.solve_seconds,
                row.result_directory,
                row.error,
            )
            println(io, join(_csv_field.(values), ","))
        end
    end
    return output_path
end

function write_aggregation_report(path, result_rows; selected_rows, total_rows)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "OpenEMPIRE.jl OOS result aggregation")
        println(io, "total_trees=$(length(total_rows))")
        println(io, "selected_trees=$(length(selected_rows))")
        for result in result_rows
            println(io, "$(replace(result.file, ".csv" => ""))_rows=$(result.rows)")
            result.skipped && println(io, "$(replace(result.file, ".csv" => ""))_skipped=true")
        end
        println(io, "updated_at=$(now())")
    end
    return path
end

function aggregate_oos_results(batch_dir; output_dir = joinpath(batch_dir, "aggregated"), files = collect(DEFAULT_AGGREGATION_FILES), status_filter = "OPTIMAL", skip_missing = true, run_name = _batch_run_name(batch_dir))
    rows = read_batch_rows(batch_dir)
    selected_rows = selected_batch_rows(rows, status_filter)
    isempty(selected_rows) && throw(ArgumentError(
        "No OOS trees match --status=$status_filter in $(joinpath(batch_dir, "batch_summary.csv"))",
    ))

    mkpath(output_dir)
    summary_path = write_oos_summary(rows, output_dir; run_name)
    result_rows = NamedTuple[]
    for file in files
        push!(result_rows, aggregate_result_file(
            selected_rows,
            file,
            output_dir;
            run_name,
            skip_missing,
        ))
    end
    report_path = write_aggregation_report(
        joinpath(output_dir, "aggregation_summary.txt"),
        result_rows;
        selected_rows,
        total_rows = rows,
    )

    return (
        output_dir = output_dir,
        summary_path = summary_path,
        report_path = report_path,
        results = result_rows,
    )
end

function main(args = ARGS)
    options = _parse_aggregation_args(args)
    batch_dir = options["batch-dir"]
    isdir(batch_dir) || throw(ArgumentError("Batch directory not found: $batch_dir"))

    output_dir = isempty(options["output-dir"]) ?
                 joinpath(batch_dir, "aggregated") :
                 options["output-dir"]
    run_name = isempty(options["run"]) ? _batch_run_name(batch_dir) : options["run"]
    files = _split_csv_list(options["files"])
    skip_missing = _parse_bool(options["skip-missing"], "skip-missing")

    result = aggregate_oos_results(
        batch_dir;
        output_dir,
        files,
        status_filter = options["status"],
        skip_missing,
        run_name,
    )

    println("Aggregated OOS results written to: $(result.output_dir)")
    println("Summary written to: $(result.summary_path)")
    println("Report written to: $(result.report_path)")
    for row in result.results
        row.skipped && continue
        println("$(row.file): $(row.rows) rows")
    end
    return result.output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
