#!/usr/bin/env julia

using Dates
using YAML

const REQUIRED_SCENARIO_FILES = (
    "sloadRaw.csv",
    "maxRegHydroGenRaw.csv",
    "genCapAvailStochRaw.csv",
)

const REQUIRED_FIXED_INVESTMENT_FILES = (
    ("genInvCap.csv",),
    ("transmissionInvCap.csv", "transmisionInvCap.csv"),
    ("storPWInvCap.csv",),
    ("storENInvCap.csv",),
    ("genInstalledCap.csv",),
    ("transmissionInstalledCap.csv",),
    ("storPWInstalledCap.csv",),
    ("storENInstalledCap.csv",),
)

function _parse_multi_tree_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "HiGHS",
        "trees-root" => "",
        "fixed-investment-dir" => "",
        "results" => joinpath("results", "julia_oos_runs"),
        "batch-dir" => "",
        "first-tree" => "1",
        "num-trees" => "all",
        "continue-on-error" => "true",
        "gurobi-method" => "",
        "gurobi-crossover" => "",
    )

    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            haskey(options, key) || throw(ArgumentError("Unsupported option: --$key"))
            options[key] = value
        elseif !startswith(arg, "--")
            options["dataset"] = arg
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end

    return options
end

function _parse_bool(value, name)
    normalized = lowercase(strip(value))
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported $name value: $value. Expected true or false."))
end

function discover_oos_trees(trees_root)
    isdir(trees_root) || throw(ArgumentError("OOS trees root not found: $trees_root"))

    trees = NamedTuple{(:index, :name, :path), Tuple{Int, String, String}}[]
    for name in readdir(trees_root)
        path = joinpath(trees_root, name)
        isdir(path) || continue
        matched = match(r"^oos_tree(\d+)$", name)
        matched === nothing && continue
        push!(trees, (index = parse(Int, matched.captures[1]), name = name, path = path))
    end
    sort!(trees; by = tree -> tree.index)
    isempty(trees) && throw(ArgumentError("No oos_treeN directories found under: $trees_root"))
    return trees
end

function select_oos_trees(trees, first_tree::Int, num_trees)
    first_tree >= 1 || throw(ArgumentError("--first-tree must be at least 1"))
    selected = filter(tree -> tree.index >= first_tree, trees)
    if num_trees !== nothing
        num_trees >= 1 || throw(ArgumentError("--num-trees must be at least 1 or 'all'"))
        selected = selected[1:min(num_trees, length(selected))]
    end
    isempty(selected) && throw(ArgumentError("No OOS trees selected from tree $first_tree"))

    expected = collect(first_tree:(first_tree + length(selected) - 1))
    actual = [tree.index for tree in selected]
    actual == expected || throw(ArgumentError(
        "OOS tree sequence is incomplete. Expected $(join(expected, ", ")); found $(join(actual, ", ")).",
    ))
    if num_trees !== nothing && length(selected) != num_trees
        throw(ArgumentError(
            "Requested $num_trees trees starting at $first_tree, but found only $(length(selected)).",
        ))
    end
    return selected
end

function validate_oos_tree(tree)
    scenario_dir = joinpath(tree.path, "ScenarioData")
    isdir(scenario_dir) || throw(ArgumentError(
        "$(tree.name) does not contain a ScenarioData directory: $(tree.path)",
    ))
    missing = filter(
        filename -> !isfile(joinpath(scenario_dir, filename)),
        REQUIRED_SCENARIO_FILES,
    )
    isempty(missing) || throw(ArgumentError(
        "$(tree.name) is missing scenario files: $(join(missing, ", "))",
    ))
    return tree
end

function validate_fixed_investment_dir(path)
    isdir(path) || throw(ArgumentError("Fixed-investment result directory not found: $path"))
    output_dir = path
    for output_name in ("Output", "output")
        candidate = joinpath(path, output_name)
        if isdir(candidate)
            output_dir = candidate
            break
        end
    end

    missing = String[]
    for alternatives in REQUIRED_FIXED_INVESTMENT_FILES
        any(filename -> isfile(joinpath(output_dir, filename)), alternatives) ||
            push!(missing, join(alternatives, " or "))
    end
    isempty(missing) || throw(ArgumentError(
        "Fixed-investment directory is missing result files in $output_dir: $(join(missing, ", "))",
    ))
    return output_dir
end

function _tree_seed(tree)
    metadata_path = joinpath(tree.path, "metadata.yaml")
    isfile(metadata_path) || return ""
    metadata = YAML.load_file(metadata_path)
    return string(get(metadata, "seed", ""))
end

function _read_run_summary(path)
    values = Dict{String, String}()
    isfile(path) || return values
    for line in eachline(path)
        occursin("=", line) || continue
        key, value = split(line, "="; limit = 2)
        values[strip(key)] = strip(value)
    end
    return values
end

function _csv_field(value)
    text = string(value)
    if occursin(',', text) || occursin('"', text) || occursin('\n', text)
        return "\"$(replace(text, "\"" => "\"\""))\""
    end
    return text
end

function write_batch_summary(path, rows)
    columns = (
        :tree,
        :seed,
        :status,
        :objective,
        :build_seconds,
        :solve_seconds,
        :result_directory,
        :error,
    )
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, join(string.(columns), ","))
        for row in rows
            println(io, join((_csv_field(getproperty(row, column)) for column in columns), ","))
        end
    end
    return path
end

function write_batch_report(path, rows)
    counts = Dict{String, Int}()
    for row in rows
        counts[row.status] = get(counts, row.status, 0) + 1
    end
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "OpenEMPIRE.jl multiple OOS tree run")
        println(io, "trees_completed=$(length(rows))")
        for status in sort!(collect(keys(counts)))
            println(io, "status_$status=$(counts[status])")
        end
        println(io, "updated_at=$(now())")
    end
    return path
end

function _runner_command(options, tree, tree_result_dir)
    project_dir = dirname(Base.active_project())
    runner_script = joinpath(@__DIR__, "run_julia_empire.jl")
    runner_args = String[
        options["dataset"],
        "--config=$(options["config"])",
        "--format=$(options["format"])",
        "--solver=$(options["solver"])",
        "--out-of-sample=true",
        "--fixed-investment-dir=$(options["fixed-investment-dir"])",
        "--scenario-data-root=$(tree.path)",
        "--result-dir=$tree_result_dir",
    ]
    for option in ("gurobi-method", "gurobi-crossover")
        isempty(options[option]) || push!(runner_args, "--$option=$(options[option])")
    end
    julia = Base.julia_cmd()
    return `$julia --project=$project_dir $runner_script $runner_args`
end

function _run_tree(options, tree, batch_dir)
    tree_result_dir = joinpath(batch_dir, tree.name)
    mkpath(tree_result_dir)
    stdout_path = joinpath(tree_result_dir, "runner.out")
    stderr_path = joinpath(tree_result_dir, "runner.err")
    command = _runner_command(options, tree, tree_result_dir)

    process_ok = false
    error_message = ""
    try
        open(stdout_path, "w") do stdout_io
            open(stderr_path, "w") do stderr_io
                process = run(pipeline(command; stdout = stdout_io, stderr = stderr_io); wait = false)
                wait(process)
                process_ok = success(process)
                process_ok || (error_message = "Runner exited with code $(process.exitcode)")
            end
        end
    catch err
        error_message = sprint(showerror, err)
    end

    summary = _read_run_summary(joinpath(tree_result_dir, "summary.txt"))
    status = get(summary, "termination_status", process_ok ? "UNKNOWN" : "PROCESS_ERROR")
    if !process_ok && status == "UNKNOWN"
        status = "PROCESS_ERROR"
    end
    return (
        tree = tree.name,
        seed = _tree_seed(tree),
        status,
        objective = get(summary, "objective_value", ""),
        build_seconds = get(summary, "build_seconds", ""),
        solve_seconds = get(summary, "solve_seconds", ""),
        result_directory = tree_result_dir,
        error = error_message,
    )
end

function main(args = ARGS)
    options = _parse_multi_tree_args(args)
    isempty(options["trees-root"]) &&
        (options["trees-root"] = joinpath("OutOfSample", options["dataset"]))
    isempty(options["fixed-investment-dir"]) && throw(ArgumentError(
        "--fixed-investment-dir is required",
    ))
    isfile(options["config"]) || throw(ArgumentError("Config file not found: $(options["config"])"))
    validate_fixed_investment_dir(options["fixed-investment-dir"])

    first_tree = parse(Int, options["first-tree"])
    num_trees = lowercase(options["num-trees"]) == "all" ?
                nothing :
                parse(Int, options["num-trees"])
    continue_on_error = _parse_bool(options["continue-on-error"], "continue-on-error")
    trees = select_oos_trees(discover_oos_trees(options["trees-root"]), first_tree, num_trees)
    foreach(validate_oos_tree, trees)

    timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    batch_dir = isempty(options["batch-dir"]) ?
                joinpath(options["results"], "$(timestamp)_$(options["dataset"])") :
                options["batch-dir"]
    mkpath(batch_dir)
    summary_path = joinpath(batch_dir, "batch_summary.csv")
    report_path = joinpath(batch_dir, "batch_summary.txt")
    rows = NamedTuple[]

    println("Running $(length(trees)) OOS trees sequentially")
    println("Batch directory: $batch_dir")
    println("Fixed investments: $(options["fixed-investment-dir"])")
    flush(stdout)

    for (position, tree) in enumerate(trees)
        println("[$position/$(length(trees))] Starting $(tree.name)")
        flush(stdout)
        row = _run_tree(options, tree, batch_dir)
        push!(rows, row)
        write_batch_summary(summary_path, rows)
        write_batch_report(report_path, rows)
        println("[$position/$(length(trees))] $(tree.name): $(row.status)")
        flush(stdout)

        failed = !isempty(row.error) || row.status in ("PROCESS_ERROR", "UNKNOWN")
        failed && !continue_on_error && error(
            "$(tree.name) failed. See $(joinpath(row.result_directory, "runner.err"))",
        )
    end

    println("Batch summary written to: $summary_path")
    return batch_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
