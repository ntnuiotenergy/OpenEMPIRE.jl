#!/usr/bin/env julia

import CSV
using Printf

const DEFAULT_PYTHON_OUTPUT = joinpath(
    "..",
    "OpenEMPIRE-csv",
    "Results",
    "basic_run",
    "dataset_test",
    "Output",
)

const TABLE_SPECS = (
    (
        name = "genInvCap",
        python_file = "genInvCap.tab",
        julia_file = "genInvCap.csv",
        key_cols = (:Node, :Generator, :Period),
        value_col = :genInvCap,
    ),
    (
        name = "genInstalledCap",
        python_file = "genInstalledCap.tab",
        julia_file = "genInstalledCap.csv",
        key_cols = (:Node, :Generator, :Period),
        value_col = :genInstalledCap,
    ),
    (
        name = "transmissionInvCap",
        python_file = "transmisionInvCap.tab",
        julia_file = "transmissionInvCap.csv",
        key_cols = (:FromNode, :ToNode, :Period),
        value_col = :transmissionInvCap,
    ),
    (
        name = "transmissionInstalledCap",
        python_file = "transmissionInstalledCap.tab",
        julia_file = "transmissionInstalledCap.csv",
        key_cols = (:FromNode, :ToNode, :Period),
        value_col = :transmissionInstalledCap,
    ),
    (
        name = "storPWInvCap",
        python_file = "storPWInvCap.tab",
        julia_file = "storPWInvCap.csv",
        key_cols = (:Node, :Storage, :Period),
        value_col = :storPWInvCap,
    ),
    (
        name = "storPWInstalledCap",
        python_file = "storPWInstalledCap.tab",
        julia_file = "storPWInstalledCap.csv",
        key_cols = (:Node, :Storage, :Period),
        value_col = :storPWInstalledCap,
    ),
    (
        name = "storENInvCap",
        python_file = "storENInvCap.tab",
        julia_file = "storENInvCap.csv",
        key_cols = (:Node, :Storage, :Period),
        value_col = :storENInvCap,
    ),
    (
        name = "storENInstalledCap",
        python_file = "storENInstalledCap.tab",
        julia_file = "storENInstalledCap.csv",
        key_cols = (:Node, :Storage, :Period),
        value_col = :storENInstalledCap,
    ),
)

const REPORT_SPECS = (
    (
        name = "results_output_gen",
        python_file = "results_output_gen.csv",
        julia_file = "results_output_gen.csv",
        key_cols = (:Node, :GeneratorType, :Period),
    ),
    (
        name = "results_output_stor",
        python_file = "results_output_stor.csv",
        julia_file = "results_output_stor.csv",
        key_cols = (:Node, :StorageType, :Period),
    ),
    (
        name = "results_output_transmission",
        python_file = "results_output_transmision.csv",
        julia_file = "results_output_transmission.csv",
        key_cols = (:BetweenNode, :AndNode, :Period),
    ),
    (
        name = "results_output_transmission_operational",
        python_file = "results_output_transmision_operational.csv",
        julia_file = "results_output_transmission_operational.csv",
        key_cols = (:FromNode, :ToNode, :Period, :Season, :Scenario, :Hour),
    ),
    (
        name = "results_output_Operational",
        python_file = "results_output_Operational.csv",
        julia_file = "results_output_Operational.csv",
        key_cols = (:Node, :Period, :Scenario, :Season, :Hour),
    ),
    (
        name = "results_output_curtailed_operational",
        python_file = "results_output_curtailed_operational.csv",
        julia_file = "results_output_curtailed_operational.csv",
        key_cols = (:Node, :Period, :Scenario, :Season, :Hour, :RESGeneratorType),
    ),
    (
        name = "results_output_curtailed_prod",
        python_file = "results_output_curtailed_prod.csv",
        julia_file = "results_output_curtailed_prod.csv",
        key_cols = (:Node, :RESGeneratorType, :Period),
    ),
    (
        name = "results_output_EuropeSummary",
        python_file = "results_output_EuropeSummary.csv",
        julia_file = "results_output_EuropeSummary.csv",
        key_cols = (:Period, :Scenario),
    ),
    (
        name = "marginal_costs",
        python_file = "marginal_costs.csv",
        julia_file = "marginal_costs.csv",
        key_cols = (:Generator, :Period),
    ),
    (
        name = "investment_costs",
        python_file = "investment_costs.csv",
        julia_file = "investment_costs.csv",
        key_cols = (:Generator, :Period),
    ),
)

const WIDE_REPORT_SPECS = (
    (
        name = "results_output_EuropePlot",
        python_file = "results_output_EuropePlot.csv",
        julia_file = "results_output_EuropePlot.csv",
    ),
)

const COLUMN_ALIASES = Dict{Symbol, Symbol}(
    :transmisionInvCap => :transmissionInvCap,
    :transmisionInvCap_MW => :transmissionInvCap_MW,
    :transmisionExpectedAnnualVolume_GWh => :transmissionExpectedAnnualVolume_GWh,
    :TransmissionRecieved_MW => :TransmissionReceived_MW,
    :storENInstalledCap_MW => :storENInstalledCap_MWh,
)

function _parse_args(args)
    options = Dict{String, String}(
        "python-output" => DEFAULT_PYTHON_OUTPUT,
        "julia-output" => "",
        "report-dir" => "",
        "atol" => "1e-5",
        "rtol" => "1e-6",
        "objective-atol" => "1e-3",
        "objective-rtol" => "1e-6",
        "allow-objective-mismatch" => "false",
    )

    for arg in args
        if arg in ("-h", "--help")
            options["help"] = "true"
        elseif startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            options[key] = value
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end

    return options
end

function _usage()
    return """
    Usage:
      julia --project=. scripts/compare_python_julia_outputs.jl \\
        --python-output=../OpenEMPIRE-csv/Results/basic_run/dataset_test/Output \\
        --julia-output=results/julia_runs/<timestamp>_test/output

    Optional:
      --report-dir=<path>  Defaults to <julia-output>/comparison
      --atol=1e-5
      --rtol=1e-6
      --objective-atol=1e-3
      --objective-rtol=1e-6
      --allow-objective-mismatch=true  Continue table comparison even if run objectives differ.
    """
end

function _parse_bool(value::AbstractString)
    normalized = lowercase(strip(value))
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported boolean value: $value"))
end

function _latest_julia_output(root::AbstractString = joinpath("results", "julia_runs"))
    isdir(root) || return ""
    candidates = String[]
    for entry in readdir(root; join = true)
        output_dir = joinpath(entry, "output")
        isdir(output_dir) && push!(candidates, output_dir)
    end
    isempty(candidates) && return ""
    sort!(candidates)
    return last(candidates)
end

function _header_map(row)
    mapping = Dict{Symbol, Symbol}()
    for name in propertynames(row)
        mapping[_canonical_col(name)] = name
    end
    return mapping
end

function _canonical_col(name)
    col = Symbol(strip(String(name)))
    return get(COLUMN_ALIASES, col, col)
end

function _value(row, col::Symbol, mapping)
    raw_col = get(mapping, col, Symbol(""))
    raw_col == Symbol("") && throw(KeyError(col))
    return getproperty(row, raw_col)
end

function _row_key(row, key_cols, mapping)
    return Tuple(strip(string(_value(row, col, mapping))) for col in key_cols)
end

function _row_number(index::Integer)
    return index + 1
end

function _read_value_table(path::AbstractString, delim::Char, key_cols, value_col::Symbol)
    table = Dict{Tuple{Vararg{String}}, Float64}()
    duplicates = Tuple{Vararg{String}}[]
    mapping = nothing
    for (index, row) in enumerate(CSV.File(path; delim, stripwhitespace = true))
        mapping === nothing && (mapping = _header_map(row))
        key = _row_key(row, key_cols, mapping)
        value = try
            Float64(_value(row, value_col, mapping))
        catch err
            throw(ArgumentError("Could not parse numeric value in $path row $(_row_number(index)), column $value_col: $err"))
        end
        if haskey(table, key)
            push!(duplicates, key)
        end
        table[key] = value
    end
    return table, duplicates
end

function _parse_float_value(value, path::AbstractString, row_index::Integer, col::Symbol)
    if value === missing
        throw(ArgumentError("Missing numeric value in $path row $(_row_number(row_index)), column $col"))
    end
    parsed = tryparse(Float64, strip(string(value)))
    parsed === nothing &&
        throw(ArgumentError("Could not parse numeric value in $path row $(_row_number(row_index)), column $col: $value"))
    return parsed
end

function _read_report_table(path::AbstractString, key_cols)
    table = Dict{Tuple{Vararg{String}}, Dict{Symbol, Float64}}()
    duplicates = Tuple{Vararg{String}}[]
    value_cols = Symbol[]
    mapping = nothing

    for (index, row) in enumerate(CSV.File(IOBuffer(_first_csv_block(path)); delim = ',', stripwhitespace = true))
        if mapping === nothing
            mapping = _header_map(row)
            key_set = Set(key_cols)
            value_cols = sort!(collect(setdiff(Set(keys(mapping)), key_set)); by = string)
        end

        key = _row_key(row, key_cols, mapping)
        values = Dict{Symbol, Float64}()
        for col in value_cols
            values[col] = _parse_float_value(_value(row, col, mapping), path, index, col)
        end

        if haskey(table, key)
            push!(duplicates, key)
        end
        table[key] = values
    end

    return table, duplicates, value_cols
end

function _first_csv_block(path::AbstractString)
    lines = String[]
    for line in eachline(path)
        stripped = strip(line)
        (isempty(stripped) || stripped == "\"\"") && break
        push!(lines, line)
    end
    return join(lines, '\n')
end

function _split_simple_csv_line(line::AbstractString)
    return [strip(strip(cell), '"') for cell in split(chomp(line), ',')]
end

function _is_block_separator(line::AbstractString)
    stripped = strip(line)
    return isempty(stripped) || stripped == "\"\""
end

function _read_wide_report(path::AbstractString)
    table = Dict{Tuple{Vararg{String}}, Float64}()
    duplicates = Tuple{Vararg{String}}[]
    lines = readlines(path)
    index = 1

    while index <= length(lines)
        while index <= length(lines) && _is_block_separator(lines[index])
            index += 1
        end
        index > length(lines) && break

        block_header = _split_simple_csv_line(lines[index])
        length(block_header) >= 2 ||
            throw(ArgumentError("Malformed wide report block header in $path line $index"))
        metric = string(_canonical_col(Symbol(block_header[2])))
        index += 1
        index <= length(lines) ||
            throw(ArgumentError("Missing column header row after $path block $metric"))

        column_headers = _split_simple_csv_line(lines[index])
        index += 1
        while index <= length(lines) && !_is_block_separator(lines[index])
            row = _split_simple_csv_line(lines[index])
            isempty(row) && (index += 1; continue)
            row_label = first(row)
            last_col = min(length(row), length(column_headers))
            for col_index in 2:last_col
                col_label = column_headers[col_index]
                isempty(col_label) && continue
                key = (metric, row_label, col_label)
                value = _parse_float_value(row[col_index], path, index, Symbol(col_label))
                if haskey(table, key)
                    push!(duplicates, key)
                end
                table[key] = value
            end
            index += 1
        end
    end

    return table, duplicates
end

function _relative_diff(a::Float64, b::Float64)
    scale = max(abs(a), abs(b), eps(Float64))
    return abs(a - b) / scale
end

function _parse_prefixed_value(path::AbstractString, prefix::AbstractString)
    isfile(path) || return ""
    for line in eachline(path)
        startswith(line, prefix) || continue
        return strip(line[(lastindex(prefix) + 1):end])
    end
    return ""
end

function _parse_float_or_nan(value::AbstractString)
    isempty(value) && return NaN
    return try
        parse(Float64, value)
    catch
        NaN
    end
end

function _read_julia_summary(julia_output::AbstractString)
    summary_path = joinpath(dirname(julia_output), "summary.txt")
    return (
        path = summary_path,
        objective = _parse_float_or_nan(_parse_prefixed_value(summary_path, "objective_value=")),
        dataset = _parse_prefixed_value(summary_path, "dataset="),
        config_file = _parse_prefixed_value(summary_path, "config_file="),
        solver = _parse_prefixed_value(summary_path, "solver="),
        seed = _parse_prefixed_value(summary_path, "seed="),
        fixed_sample = _parse_prefixed_value(summary_path, "fixed_sample="),
    )
end

function _read_python_objective(python_output::AbstractString)
    objective_path = joinpath(python_output, "results_objective.csv")
    isfile(objective_path) || return (path = objective_path, objective = NaN)
    first_line = ""
    for line in eachline(objective_path)
        first_line = line
        break
    end
    matched = match(r"Objective function value:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", first_line)
    value = matched === nothing ? NaN : parse(Float64, matched.captures[1])
    return (path = objective_path, objective = value)
end

function _read_python_run_ids(python_output::AbstractString)
    logs_path = joinpath(python_output, "logs.txt")
    isfile(logs_path) || return (path = logs_path, run_ids = String[])
    run_ids = String[]
    for line in eachline(logs_path)
        matched = match(r"\bID:\s*(\S+)", line)
        matched === nothing || push!(run_ids, matched.captures[1])
    end
    return (path = logs_path, run_ids = run_ids)
end

function _provenance(python_output::AbstractString, julia_output::AbstractString, objective_atol::Float64, objective_rtol::Float64)
    python_objective = _read_python_objective(python_output)
    python_logs = _read_python_run_ids(python_output)
    julia_summary = _read_julia_summary(julia_output)

    objective_abs_diff = abs(python_objective.objective - julia_summary.objective)
    objective_rel_diff = _relative_diff(python_objective.objective, julia_summary.objective)
    objective_match = isfinite(python_objective.objective) &&
        isfinite(julia_summary.objective) &&
        isapprox(python_objective.objective, julia_summary.objective; atol = objective_atol, rtol = objective_rtol)

    return (
        python_objective = python_objective.objective,
        julia_objective = julia_summary.objective,
        objective_abs_diff = objective_abs_diff,
        objective_rel_diff = objective_rel_diff,
        objective_match = objective_match,
        objective_atol = objective_atol,
        objective_rtol = objective_rtol,
        python_objective_file = python_objective.path,
        julia_summary_file = julia_summary.path,
        python_logs_file = python_logs.path,
        python_run_ids = join(python_logs.run_ids, ";"),
        latest_python_run_id = isempty(python_logs.run_ids) ? "" : last(python_logs.run_ids),
        julia_run_dir = basename(dirname(julia_output)),
        julia_dataset = julia_summary.dataset,
        julia_config_file = julia_summary.config_file,
        julia_solver = julia_summary.solver,
        julia_seed = julia_summary.seed,
        julia_fixed_sample = julia_summary.fixed_sample,
    )
end

function _key_string(key)
    return join(key, "|")
end

function _compare_table(spec, python_output, julia_output, atol::Float64, rtol::Float64)
    python_path = joinpath(python_output, spec.python_file)
    julia_path = joinpath(julia_output, spec.julia_file)
    isfile(python_path) || throw(ArgumentError("Missing Python output file: $python_path"))
    isfile(julia_path) || throw(ArgumentError("Missing Julia output file: $julia_path"))

    python_rows, python_duplicates = _read_value_table(python_path, '\t', spec.key_cols, spec.value_col)
    julia_rows, julia_duplicates = _read_value_table(julia_path, ',', spec.key_cols, spec.value_col)

    python_keys = Set(keys(python_rows))
    julia_keys = Set(keys(julia_rows))
    missing_in_julia = setdiff(python_keys, julia_keys)
    extra_in_julia = setdiff(julia_keys, python_keys)
    common_keys = intersect(python_keys, julia_keys)

    mismatches = NamedTuple{
        (:table, :key, :column, :python_value, :julia_value, :abs_diff, :rel_diff),
        Tuple{String, String, String, Float64, Float64, Float64, Float64},
    }[]

    max_abs_diff = 0.0
    max_rel_diff = 0.0
    for key in sort!(collect(common_keys); by = _key_string)
        python_value = python_rows[key]
        julia_value = julia_rows[key]
        abs_diff = abs(python_value - julia_value)
        rel_diff = _relative_diff(python_value, julia_value)
        max_abs_diff = max(max_abs_diff, abs_diff)
        max_rel_diff = max(max_rel_diff, rel_diff)
        if !isapprox(python_value, julia_value; atol, rtol)
            push!(mismatches, (
                table = spec.name,
                key = _key_string(key),
                column = string(spec.value_col),
                python_value = python_value,
                julia_value = julia_value,
                abs_diff = abs_diff,
                rel_diff = rel_diff,
            ))
        end
    end

    summary = (
        category = "raw",
        table = spec.name,
        python_file = spec.python_file,
        julia_file = spec.julia_file,
        python_rows = length(python_rows),
        julia_rows = length(julia_rows),
        common_rows = length(common_keys),
        missing_in_julia = length(missing_in_julia),
        extra_in_julia = length(extra_in_julia),
        common_columns = 1,
        missing_columns_in_julia = 0,
        extra_columns_in_julia = 0,
        value_mismatches = length(mismatches),
        python_duplicate_keys = length(python_duplicates),
        julia_duplicate_keys = length(julia_duplicates),
        max_abs_diff = max_abs_diff,
        max_rel_diff = max_rel_diff,
        equal_approx = isempty(missing_in_julia) && isempty(extra_in_julia) &&
            isempty(mismatches) && isempty(python_duplicates) && isempty(julia_duplicates),
    )

    return summary, mismatches
end

function _compare_report(spec, python_output, julia_output, atol::Float64, rtol::Float64)
    python_path = joinpath(python_output, spec.python_file)
    julia_path = joinpath(julia_output, spec.julia_file)
    isfile(python_path) || throw(ArgumentError("Missing Python report file: $python_path"))
    isfile(julia_path) || throw(ArgumentError("Missing Julia report file: $julia_path"))

    python_rows, python_duplicates, python_value_cols = _read_report_table(python_path, spec.key_cols)
    julia_rows, julia_duplicates, julia_value_cols = _read_report_table(julia_path, spec.key_cols)

    python_keys = Set(keys(python_rows))
    julia_keys = Set(keys(julia_rows))
    missing_in_julia = setdiff(python_keys, julia_keys)
    extra_in_julia = setdiff(julia_keys, python_keys)
    common_keys = intersect(python_keys, julia_keys)

    python_cols = Set(python_value_cols)
    julia_cols = Set(julia_value_cols)
    missing_cols = setdiff(python_cols, julia_cols)
    extra_cols = setdiff(julia_cols, python_cols)
    common_cols = sort!(collect(intersect(python_cols, julia_cols)); by = string)

    mismatches = NamedTuple{
        (:table, :key, :column, :python_value, :julia_value, :abs_diff, :rel_diff),
        Tuple{String, String, String, Float64, Float64, Float64, Float64},
    }[]

    max_abs_diff = 0.0
    max_rel_diff = 0.0
    for key in sort!(collect(common_keys); by = _key_string)
        python_values = python_rows[key]
        julia_values = julia_rows[key]
        for col in common_cols
            python_value = python_values[col]
            julia_value = julia_values[col]
            abs_diff = abs(python_value - julia_value)
            rel_diff = _relative_diff(python_value, julia_value)
            max_abs_diff = max(max_abs_diff, abs_diff)
            max_rel_diff = max(max_rel_diff, rel_diff)
            if !isapprox(python_value, julia_value; atol, rtol)
                push!(mismatches, (
                    table = spec.name,
                    key = _key_string(key),
                    column = string(col),
                    python_value = python_value,
                    julia_value = julia_value,
                    abs_diff = abs_diff,
                    rel_diff = rel_diff,
                ))
            end
        end
    end

    summary = (
        category = "report",
        table = spec.name,
        python_file = spec.python_file,
        julia_file = spec.julia_file,
        python_rows = length(python_rows),
        julia_rows = length(julia_rows),
        common_rows = length(common_keys),
        missing_in_julia = length(missing_in_julia),
        extra_in_julia = length(extra_in_julia),
        common_columns = length(common_cols),
        missing_columns_in_julia = length(missing_cols),
        extra_columns_in_julia = length(extra_cols),
        value_mismatches = length(mismatches),
        python_duplicate_keys = length(python_duplicates),
        julia_duplicate_keys = length(julia_duplicates),
        max_abs_diff = max_abs_diff,
        max_rel_diff = max_rel_diff,
        equal_approx = isempty(missing_in_julia) && isempty(extra_in_julia) &&
            isempty(missing_cols) && isempty(extra_cols) &&
            isempty(mismatches) && isempty(python_duplicates) && isempty(julia_duplicates),
    )

    return summary, mismatches
end

function _compare_wide_report(spec, python_output, julia_output, atol::Float64, rtol::Float64)
    python_path = joinpath(python_output, spec.python_file)
    julia_path = joinpath(julia_output, spec.julia_file)
    isfile(python_path) || throw(ArgumentError("Missing Python wide report file: $python_path"))
    isfile(julia_path) || throw(ArgumentError("Missing Julia wide report file: $julia_path"))

    python_rows, python_duplicates = _read_wide_report(python_path)
    julia_rows, julia_duplicates = _read_wide_report(julia_path)

    python_keys = Set(keys(python_rows))
    julia_keys = Set(keys(julia_rows))
    missing_in_julia = setdiff(python_keys, julia_keys)
    extra_in_julia = setdiff(julia_keys, python_keys)
    common_keys = intersect(python_keys, julia_keys)

    mismatches = NamedTuple{
        (:table, :key, :column, :python_value, :julia_value, :abs_diff, :rel_diff),
        Tuple{String, String, String, Float64, Float64, Float64, Float64},
    }[]

    max_abs_diff = 0.0
    max_rel_diff = 0.0
    for key in sort!(collect(common_keys); by = _key_string)
        python_value = python_rows[key]
        julia_value = julia_rows[key]
        abs_diff = abs(python_value - julia_value)
        rel_diff = _relative_diff(python_value, julia_value)
        max_abs_diff = max(max_abs_diff, abs_diff)
        max_rel_diff = max(max_rel_diff, rel_diff)
        if !isapprox(python_value, julia_value; atol, rtol)
            push!(mismatches, (
                table = spec.name,
                key = _key_string(key[1:2]),
                column = key[3],
                python_value = python_value,
                julia_value = julia_value,
                abs_diff = abs_diff,
                rel_diff = rel_diff,
            ))
        end
    end

    summary = (
        category = "wide",
        table = spec.name,
        python_file = spec.python_file,
        julia_file = spec.julia_file,
        python_rows = length(python_rows),
        julia_rows = length(julia_rows),
        common_rows = length(common_keys),
        missing_in_julia = length(missing_in_julia),
        extra_in_julia = length(extra_in_julia),
        common_columns = 1,
        missing_columns_in_julia = 0,
        extra_columns_in_julia = 0,
        value_mismatches = length(mismatches),
        python_duplicate_keys = length(python_duplicates),
        julia_duplicate_keys = length(julia_duplicates),
        max_abs_diff = max_abs_diff,
        max_rel_diff = max_rel_diff,
        equal_approx = isempty(missing_in_julia) && isempty(extra_in_julia) &&
            isempty(mismatches) && isempty(python_duplicates) && isempty(julia_duplicates),
    )

    return summary, mismatches
end

function _write_provenance_section(io, provenance)
    println(io, "Provenance:")
    println(io, "  python_objective=$(provenance.python_objective)")
    println(io, "  julia_objective=$(provenance.julia_objective)")
    println(io, "  objective_abs_diff=$(provenance.objective_abs_diff)")
    println(io, "  objective_rel_diff=$(provenance.objective_rel_diff)")
    println(io, "  objective_match=$(provenance.objective_match)")
    println(io, "  latest_python_run_id=$(provenance.latest_python_run_id)")
    println(io, "  python_run_ids=$(provenance.python_run_ids)")
    println(io, "  julia_run_dir=$(provenance.julia_run_dir)")
    println(io, "  julia_config_file=$(provenance.julia_config_file)")
    return nothing
end

function _write_provenance_failed_report(path, python_output, julia_output, report_dir, provenance)
    open(path, "w") do io
        println(io, "OpenEMPIRE Python/Julia output comparison")
        println(io, "python_output=$python_output")
        println(io, "julia_output=$julia_output")
        println(io, "report_dir=$report_dir")
        println(io)
        _write_provenance_section(io, provenance)
        println(io)
        println(io, "Comparison aborted before table-level checks because Python and Julia objectives do not match.")
        println(io, "This usually means the Python Output directory is stale, mixed, or from a different scenario sample.")
        println(io, "Regenerate/copy a clean Python fixed-sample Output directory, then rerun this script.")
    end
    return path
end

function _write_report_text(path, python_output, julia_output, report_dir, provenance, summaries, python_only, julia_only, atol, rtol)
    open(path, "w") do io
        println(io, "OpenEMPIRE Python/Julia output comparison")
        println(io, "python_output=$python_output")
        println(io, "julia_output=$julia_output")
        println(io, "report_dir=$report_dir")
        println(io, "atol=$atol")
        println(io, "rtol=$rtol")
        println(io)
        _write_provenance_section(io, provenance)
        println(io)
        println(io, "Compared tables and reports:")
        for summary in summaries
            status = summary.equal_approx ? "OK" : "DIFF"
            println(
                io,
                @sprintf(
                    "  %-42s %-6s %s rows(py=%d,jl=%d,common=%d) cols(common=%d,missing=%d,extra=%d) missing=%d extra=%d mismatches=%d max_abs=%.12g max_rel=%.12g",
                    summary.table,
                    summary.category,
                    status,
                    summary.python_rows,
                    summary.julia_rows,
                    summary.common_rows,
                    summary.common_columns,
                    summary.missing_columns_in_julia,
                    summary.extra_columns_in_julia,
                    summary.missing_in_julia,
                    summary.extra_in_julia,
                    summary.value_mismatches,
                    summary.max_abs_diff,
                    summary.max_rel_diff,
                ),
            )
        end
        println(io)
        println(io, "Python-only files:")
        for file in python_only
            println(io, "  $file")
        end
        println(io)
        println(io, "Julia-only files:")
        for file in julia_only
            println(io, "  $file")
        end
    end
    return path
end

function main(args = ARGS)
    options = _parse_args(args)
    if get(options, "help", "false") == "true"
        print(_usage())
        return 0
    end

    python_output = options["python-output"]
    julia_output = isempty(options["julia-output"]) ? _latest_julia_output() : options["julia-output"]
    isempty(julia_output) && throw(ArgumentError("No Julia output directory found. Pass --julia-output=<path>."))
    isdir(python_output) || throw(ArgumentError("Python output directory not found: $python_output"))
    isdir(julia_output) || throw(ArgumentError("Julia output directory not found: $julia_output"))

    atol = parse(Float64, options["atol"])
    rtol = parse(Float64, options["rtol"])
    objective_atol = parse(Float64, options["objective-atol"])
    objective_rtol = parse(Float64, options["objective-rtol"])
    allow_objective_mismatch = _parse_bool(options["allow-objective-mismatch"])

    default_report_dir = joinpath(julia_output, "comparison")
    report_dir = isempty(options["report-dir"]) ? default_report_dir : options["report-dir"]
    mkpath(report_dir)

    provenance = _provenance(python_output, julia_output, objective_atol, objective_rtol)
    provenance_path = joinpath(report_dir, "provenance.csv")
    CSV.write(provenance_path, [provenance])

    if !provenance.objective_match && !allow_objective_mismatch
        report_path = joinpath(report_dir, "report.txt")
        _write_provenance_failed_report(report_path, python_output, julia_output, report_dir, provenance)
        println("Compared Python output: $python_output")
        println("Compared Julia output:  $julia_output")
        println("Report written to:      $report_path")
        println("Provenance written to:  $provenance_path")
        println()
        println("PROVENANCE DIFF: table comparison aborted")
        println("  Python objective: $(provenance.python_objective)")
        println("  Julia objective:  $(provenance.julia_objective)")
        println("  abs diff:         $(provenance.objective_abs_diff)")
        println("  rel diff:         $(provenance.objective_rel_diff)")
        println("  Python run IDs:   $(isempty(provenance.python_run_ids) ? "(none found)" : provenance.python_run_ids)")
        println("  Julia run dir:    $(provenance.julia_run_dir)")
        println()
        println("Rerun with --allow-objective-mismatch=true to force row-level comparison anyway.")
        return 2
    elseif !provenance.objective_match
        @warn "Python and Julia objectives differ; continuing because --allow-objective-mismatch=true." provenance
    end

    summaries = NamedTuple[]
    all_mismatches = NamedTuple[]
    for spec in TABLE_SPECS
        summary, mismatches = _compare_table(spec, python_output, julia_output, atol, rtol)
        push!(summaries, summary)
        append!(all_mismatches, mismatches)
    end
    for spec in REPORT_SPECS
        summary, mismatches = _compare_report(spec, python_output, julia_output, atol, rtol)
        push!(summaries, summary)
        append!(all_mismatches, mismatches)
    end
    for spec in WIDE_REPORT_SPECS
        summary, mismatches = _compare_wide_report(spec, python_output, julia_output, atol, rtol)
        push!(summaries, summary)
        append!(all_mismatches, mismatches)
    end

    compared_python_files = Set(spec.python_file for spec in TABLE_SPECS)
    union!(compared_python_files, (spec.python_file for spec in REPORT_SPECS))
    union!(compared_python_files, (spec.python_file for spec in WIDE_REPORT_SPECS))
    push!(compared_python_files, "results_objective.csv")
    compared_julia_files = Set(spec.julia_file for spec in TABLE_SPECS)
    union!(compared_julia_files, (spec.julia_file for spec in REPORT_SPECS))
    union!(compared_julia_files, (spec.julia_file for spec in WIDE_REPORT_SPECS))
    push!(compared_julia_files, "results_objective.csv")
    if abspath(report_dir) == abspath(default_report_dir)
        push!(compared_julia_files, basename(default_report_dir))
    end
    python_files = Set(readdir(python_output))
    julia_files = Set(readdir(julia_output))
    python_only = sort!(collect(setdiff(python_files, compared_python_files)))
    julia_only = sort!(collect(file for file in setdiff(julia_files, compared_julia_files) if !startswith(file, "comparison")))

    summary_path = joinpath(report_dir, "summary.csv")
    mismatch_path = joinpath(report_dir, "mismatches.csv")
    report_path = joinpath(report_dir, "report.txt")

    CSV.write(summary_path, summaries)
    CSV.write(mismatch_path, all_mismatches)
    _write_report_text(report_path, python_output, julia_output, report_dir, provenance, summaries, python_only, julia_only, atol, rtol)

    println("Compared Python output: $python_output")
    println("Compared Julia output:  $julia_output")
    println("Report written to:      $report_path")
    println("Provenance written to:  $provenance_path")
    println("Objective match:        $(provenance.objective_match)")
    println()
    for summary in summaries
        status = summary.equal_approx ? "OK" : "DIFF"
        println(
            @sprintf(
                "%-42s %-6s %s mismatches=%d missing=%d extra=%d col_missing=%d col_extra=%d max_abs=%.12g",
                summary.table,
                summary.category,
                status,
                summary.value_mismatches,
                summary.missing_in_julia,
                summary.extra_in_julia,
                summary.missing_columns_in_julia,
                summary.extra_columns_in_julia,
                summary.max_abs_diff,
            ),
        )
    end

    return all(summary.equal_approx for summary in summaries) ? 0 : 1
end

exit(main())
