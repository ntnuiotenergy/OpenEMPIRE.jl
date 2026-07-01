#!/usr/bin/env julia

using Dates
import Gurobi
using HiGHS
using JuMP
using OpenEMPIRE
using Random
using SHA
using TimeStruct
using YAML

function _parse_args(args)
    options = Dict{String, String}(
        "dataset" => "test",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "HiGHS",
        "seed" => "1",
        "results" => joinpath("results", "julia_runs"),
        "optimize" => "true",
        "generate-only" => "false",
        "fixed-sample" => "auto",
        "gurobi-method" => "",
        "gurobi-crossover" => "",
    )

    for arg in args
        if arg == "--no-optimize"
            options["optimize"] = "false"
        elseif arg == "--generate-only"
            options["generate-only"] = "true"
        elseif arg == "--fixed-sample"
            options["fixed-sample"] = "true"
        elseif startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            options[key] = value
        elseif !startswith(arg, "--")
            options["dataset"] = arg
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end

    return options
end

function _input_format(value)
    value == "csv" && return :csv
    value == "xlsx" && return :xlsx
    value == "auto" && return :auto
    throw(ArgumentError("Unsupported input format: $value. Expected csv, xlsx, or auto."))
end

function _optimizer(value)
    value == "HiGHS" && return HiGHS.Optimizer
    value == "Gurobi" && return Gurobi.Optimizer
    value == "none" && return nothing
    throw(ArgumentError(
        "Unsupported solver: $value. This runner currently supports HiGHS, Gurobi, or none.",
    ))
end

function _optional_int(value, key)
    (value === nothing || ismissing(value)) && return nothing
    value isa Integer && return Int(value)
    text = strip(string(value))
    isempty(text) && return nothing
    try
        return parse(Int, text)
    catch err
        throw(ArgumentError("Unsupported integer value for $key: $value"))
    end
end

function _set_optimizer_attribute!(attributes, name, value)
    parsed = _optional_int(value, name)
    parsed === nothing && return attributes
    for index in eachindex(attributes)
        if first(attributes[index]) == name
            attributes[index] = name => parsed
            return attributes
        end
    end
    push!(attributes, name => parsed)
    return attributes
end

function _optimizer_attributes(value, config, options)
    if value == "Gurobi"
        attributes = Pair{String, Int}[]
        config_attribute_names = (
            "solver_method" => "Method",
            "solver_crossover" => "Crossover",
            "solver_presolve" => "Presolve",
            "solver_threads" => "Threads",
            "solver_scaleflag" => "ScaleFlag",
            "solver_numericfocus" => "NumericFocus",
            "solver_barhomogeneous" => "BarHomogeneous",
        )
        for (config_key, gurobi_name) in config_attribute_names
            _set_optimizer_attribute!(attributes, gurobi_name, get(config, config_key, nothing))
        end
        _set_optimizer_attribute!(attributes, "Method", options["gurobi-method"])
        _set_optimizer_attribute!(attributes, "Crossover", options["gurobi-crossover"])
        return Tuple(attributes)
    end
    return ()
end

function _optimizer_attribute_summary(attributes)
    isempty(attributes) && return "(none)"
    return join(("$name=$value" for (name, value) in attributes), ", ")
end

function _boolean_option(value, name)
    normalized = lowercase(value)
    normalized in ("true", "1", "yes") && return true
    normalized in ("false", "0", "no") && return false
    throw(ArgumentError("Unsupported $name value: $value. Expected true or false."))
end

function _config_bool(config, key, default)
    value = get(config, key, default)
    value isa Bool && return value
    return _boolean_option(string(value), key)
end

function _config_with_fixed_sample(config_file, result_dir)
    config = YAML.load_file(config_file)
    config["use_scenario_generation"] = true
    config["use_fixed_sample"] = true

    generated_config = joinpath(result_dir, "fixed_sample_config.yaml")
    YAML.write_file(generated_config, config)
    return generated_config
end

function _read_command(cmd::Cmd)
    try
        return strip(read(cmd, String))
    catch
        return nothing
    end
end

function _git_info()
    status = _read_command(`git status --short`)
    return Dict{String, Any}(
        "branch" => _read_command(`git rev-parse --abbrev-ref HEAD`),
        "commit" => _read_command(`git rev-parse HEAD`),
        "dirty" => status === nothing ? nothing : !isempty(status),
    )
end

function _sha256_file(path::AbstractString)
    isfile(path) || return nothing
    open(path, "r") do io
        return bytes2hex(sha256(io))
    end
end

function _optimizer_attributes_manifest(attributes)
    return Dict{String, Any}(string(name) => value for (name, value) in attributes)
end

function _sampling_key_info(data_folder::AbstractString)
    path = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
    return Dict{String, Any}(
        "path" => path,
        "exists" => isfile(path),
        "sha256" => _sha256_file(path),
    )
end

function _write_run_manifest(path, manifest)
    mkpath(dirname(path))
    YAML.write_file(path, manifest)
    return path
end

function _write_summary(path, lines)
    mkpath(dirname(path))
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return path
end

# Minimal ordered JSON serializer for perf.json (avoids adding a JSON dependency).
# `JObj` preserves key order so the artifact diffs cleanly across runs.
struct JObj
    pairs::Vector{Pair{String, Any}}
end

_json_escape(s) = replace(string(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\t" => "\\t")

function _json(x)
    if x === nothing
        return "null"
    elseif x isa Bool
        return x ? "true" : "false"
    elseif x isa Integer
        return string(x)
    elseif x isa AbstractFloat
        return isfinite(x) ? string(x) : "null"
    elseif x isa Union{AbstractString, Symbol}
        return "\"" * _json_escape(x) * "\""
    elseif x isa JObj
        return "{" * join(("\"" * _json_escape(k) * "\":" * _json(v) for (k, v) in x.pairs), ",") * "}"
    elseif x isa AbstractVector
        return "[" * join((_json(v) for v in x), ",") * "]"
    else
        return "\"" * _json_escape(x) * "\""
    end
end

_write_perf_json(path, obj::JObj) = (mkpath(dirname(path)); write(path, _json(obj) * "\n"); path)

# Opt-in via EMPIRE_PERF (matches the Python side and the SGE wrapper), so default
# runs emit no perf.json. The @timed phase capture itself is always-on and cheap.
_perf_enabled() = lowercase(strip(get(ENV, "EMPIRE_PERF", ""))) in ("1", "true", "yes", "on")

# Record one phase boundary. `wall_seconds`, `alloc_bytes` and `gc_seconds` are
# the per-phase figures from `@timed` (the `@time` machinery): alloc_bytes is the
# *cumulative bytes allocated* in the phase — allocation pressure, not footprint.
# Footprint is `rss_peak_bytes` from Sys.maxrss(), the monotonic peak RSS of the
# whole process (already includes Gurobi, linked in-process); live_bytes is the
# current live heap from gc_live_bytes().
function _perf_phase(name::AbstractString, wall_seconds::Real; alloc_bytes = nothing, gc_seconds = nothing)
    return JObj([
        "name" => name,
        "wall_seconds" => round(Float64(wall_seconds); digits = 3),
        "alloc_bytes" => alloc_bytes === nothing ? nothing : Int(alloc_bytes),
        "gc_seconds" => gc_seconds === nothing ? nothing : round(Float64(gc_seconds); digits = 3),
        "rss_peak_bytes" => Int(Sys.maxrss()),
        "live_bytes" => Int(Base.gc_live_bytes()),
    ])
end

function _pkgversion_str(m::Module)
    try
        v = pkgversion(m)
        return v === nothing ? nothing : string(v)
    catch
        return nothing
    end
end

function _log_line(message)
    println(message)
    flush(stdout)
    return nothing
end

function _progress_logger()
    run_start = time()
    step = Ref(0)
    return function (message)
        step[] += 1
        elapsed = round(time() - run_start; digits = 1)
        _log_line("[progress $(step[]) | +$(elapsed)s | $(now())] $message")
    end
end

# Count how many JuMP.ConstraintRef objects a registered object_dictionary entry holds.
# Variable containers (VariableRef) and other registered objects return 0.
function _family_cref_count(obj)
    obj isa JuMP.ConstraintRef && return 1
    obj isa AbstractArray && return count(v -> v isa JuMP.ConstraintRef, obj)
    return 0
end

# Print the number of constraints in each registered @constraint family, plus a total.
# Used to localize Python/Julia constraint-count parity gaps.
function report_constraint_family_counts(emp::JuMP.Model)
    counts = Tuple{String,Int}[]
    for (name, obj) in JuMP.object_dictionary(emp)
        n = _family_cref_count(obj)
        n > 0 && push!(counts, (string(name), n))
    end
    sort!(counts; by = first)
    println("Constraint family counts:")
    total = 0
    for (name, n) in counts
        total += n
        println("  $(name): $(n)")
    end
    println("  TOTAL (named families): $(total)")
    flush(stdout)
    return counts
end

function main(args = ARGS)
    options = _parse_args(args)
    dataset = options["dataset"]
    data_folder = joinpath("data", dataset)
    config_file = options["config"]
    original_config_file = config_file
    format = _input_format(options["format"])
    solver_name = options["solver"]
    optimizer = _optimizer(solver_name)
    seed = parse(Int, options["seed"])
    optimize_model = lowercase(options["optimize"]) in ("true", "1", "yes")
    generate_only = lowercase(options["generate-only"]) in ("true", "1", "yes")
    fixed_sample_option = lowercase(options["fixed-sample"])

    isdir(data_folder) || throw(ArgumentError("Dataset folder not found: $data_folder"))
    isfile(config_file) || throw(ArgumentError("Config file not found: $config_file"))

    timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    result_dir = joinpath(options["results"], "$(timestamp)_$(dataset)")
    mkpath(result_dir)

    if fixed_sample_option != "auto"
        if _boolean_option(fixed_sample_option, "fixed-sample")
            sampling_key = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
            isfile(sampling_key) ||
                throw(ArgumentError("--fixed-sample requires sampling key: $sampling_key"))
            config_file = _config_with_fixed_sample(config_file, result_dir)
        else
            throw(ArgumentError(
                "--fixed-sample=false is not supported by this runner. Use a config file with use_fixed_sample: False instead.",
            ))
        end
    end
    run_config = YAML.load_file(config_file)
    optimizer_attributes = _optimizer_attributes(solver_name, run_config, options)
    run_started_at = now()
    manifest_path = joinpath(result_dir, "run_manifest.yaml")
    manifest = Dict{String, Any}(
        "runtime" => "julia",
        "status" => "started",
        "start_time" => string(run_started_at),
        "host" => gethostname(),
        "cpu_threads" => Sys.CPU_THREADS,
        "versions" => Dict{String, Any}(
            "julia" => string(VERSION),
            "jump" => _pkgversion_str(JuMP),
            "gurobi_jl" => _pkgversion_str(Gurobi),
        ),
        "git" => _git_info(),
        "dataset" => dataset,
        "data_folder" => data_folder,
        "config_file" => config_file,
        "original_config_file" => original_config_file,
        "config_sha256" => _sha256_file(config_file),
        "original_config_sha256" => _sha256_file(original_config_file),
        "input_format" => string(format),
        "solver" => Dict{String, Any}(
            "name" => solver_name,
            "attributes" => _optimizer_attributes_manifest(optimizer_attributes),
        ),
        "seed" => seed,
        "fixed_sample" => fixed_sample_option,
        "sampling_key" => _sampling_key_info(data_folder),
        "generate_only" => generate_only,
        "optimize" => optimize_model,
        "result_dir" => result_dir,
        "timings" => Dict{String, Any}(),
        "model" => nothing,
        "solution" => nothing,
    )
    _write_run_manifest(manifest_path, manifest)

    println("================================================")
    println("OpenEMPIRE.jl run")
    println("================================================")
    println("Dataset:      $dataset")
    println("Data folder:  $data_folder")
    println("Config file:  $config_file")
    println("Input format: $format")
    println("Solver:       $solver_name")
    println("Solver attrs: $(_optimizer_attribute_summary(optimizer_attributes))")
    println("Seed:         $seed")
    println("Fixed sample: $fixed_sample_option")
    println("Generate only: $generate_only")
    println("Optimize:     $optimize_model")
    println("Result dir:   $result_dir")
    println("Start time:   $(now())")
    println("================================================")
    flush(stdout)

    progress = _progress_logger()
    progress("Runner initialized")

    perf_phases = JObj[]
    run_start = time()

    if generate_only
        progress("Generating scenario data only (no model build)")
        generate_start = time()
        OpenEMPIRE.generate_scenarios(
            config_file,
            data_folder;
            input_format = format,
            scenario_rng = MersenneTwister(seed),
            progress,
        )
        generate_seconds = time() - generate_start
        progress("Scenario generation finished in $(round(generate_seconds; digits = 2)) seconds")
        scenario_artifact = OpenEMPIRE.write_scenario_artifacts(
            result_dir,
            data_folder,
            run_config;
            config_file = config_file,
            dataset = dataset,
            input_format = format,
            seed = seed,
        )
        scenario_artifact !== nothing &&
            println("Scenario sampling key archived to: $scenario_artifact")
        summary_path = _write_summary(
            joinpath(result_dir, "summary.txt"),
            [
                "mode=generate-only",
                "dataset=$dataset",
                "config=$config_file",
                "seed=$seed",
                "fixed_sample=$fixed_sample_option",
                "scenario_data_folder=$(joinpath(data_folder, "ScenarioData"))",
                "generate_seconds=$generate_seconds",
            ],
        )
        println("Summary written to: $summary_path")
        run_ended_at = now()
        manifest["status"] = "complete"
        manifest["end_time"] = string(run_ended_at)
        manifest["timings"]["generate_seconds"] = generate_seconds
        manifest["timings"]["wall_seconds"] = round(time() - run_start; digits = 3)
        manifest["sampling_key"] = _sampling_key_info(data_folder)
        manifest["scenario_artifact"] = scenario_artifact
        _write_run_manifest(manifest_path, manifest)
        println("Run manifest written to: $manifest_path")
        println("End time: $run_ended_at")
        flush(stdout)
        progress("Run complete")
        return result_dir
    end

    build_start = time()
    progress("Starting model build")
    build_stats = @timed OpenEMPIRE.create_model(
        config_file,
        data_folder;
        optimizer,
        optimizer_attributes,
        input_format = format,
        scenario_rng = MersenneTwister(seed),
        progress,
    )
    emp, periods, sets, params = build_stats.value
    build_seconds = time() - build_start
    push!(perf_phases, _perf_phase("build", build_seconds; alloc_bytes = build_stats.bytes, gc_seconds = build_stats.gctime))
    println("Model build seconds: $(round(build_seconds; digits = 2))")
    println("Variables: $(JuMP.num_variables(emp))")
    println("Constraints: $(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))")
    report_constraint_family_counts(emp)
    flush(stdout)
    progress("Model build finished in $(round(build_seconds; digits = 2)) seconds")
    manifest["timings"]["build_seconds"] = build_seconds
    manifest["model"] = Dict{String, Any}(
        "variables" => JuMP.num_variables(emp),
        "constraints" => JuMP.num_constraints(
            emp;
            count_variable_in_set_constraints = false,
        ),
    )
    _write_run_manifest(manifest_path, manifest)
    scenario_artifact = OpenEMPIRE.write_scenario_artifacts(
        result_dir,
        data_folder,
        run_config;
        config_file = config_file,
        dataset = dataset,
        input_format = format,
        seed = seed,
    )
    if scenario_artifact !== nothing
        println("Scenario sampling key archived to: $scenario_artifact")
        flush(stdout)
    end
    manifest["sampling_key"] = _sampling_key_info(data_folder)
    manifest["scenario_artifact"] = scenario_artifact
    _write_run_manifest(manifest_path, manifest)

    termination = nothing
    objective = nothing
    objective_components = nothing
    solve_seconds = 0.0
    if optimize_model
        solve_start = time()
        progress("Starting solver optimization")
        solve_stats = @timed JuMP.optimize!(emp)
        solve_seconds = time() - solve_start
        push!(perf_phases, _perf_phase("solve", solve_seconds; alloc_bytes = solve_stats.bytes, gc_seconds = solve_stats.gctime))
        manifest["timings"]["solve_seconds"] = solve_seconds
        progress("Solver optimization finished in $(round(solve_seconds; digits = 2)) seconds")
        termination = JuMP.termination_status(emp)
        objective = JuMP.objective_value(emp)
        progress("Computing objective component diagnostics")
        objective_components = OpenEMPIRE.objective_component_values(
            emp,
            sets,
            params,
            periods,
            Discounter(OpenEMPIRE.discount_rate(params), 1, periods),
        )
        println("Solve seconds: $(round(solve_seconds; digits = 2))")
        println("Termination status: $termination")
        println("Objective value: $objective")
        println("Objective components:")
        for (name, value) in pairs(objective_components)
            println("  $name: $value")
        end
        flush(stdout)
        if JuMP.is_solved_and_feasible(emp)
            progress("Writing solution CSV tables")
            results_stats = @timed OpenEMPIRE.write_solution_tables(result_dir, emp, sets, params, periods)
            output_dir = results_stats.value
            push!(perf_phases, _perf_phase("results", results_stats.time; alloc_bytes = results_stats.bytes, gc_seconds = results_stats.gctime))
            println("Solution CSVs written to: $output_dir")
            flush(stdout)
            progress("Solution CSV tables written to $output_dir")
        else
            println("Solution CSVs skipped because the solved model is not feasible.")
            flush(stdout)
        end
    end
    manifest["solution"] = Dict{String, Any}(
        "termination_status" => termination === nothing ? "not_optimized" : string(termination),
        "objective_value" => objective === nothing ? "not_optimized" : objective,
        "objective_components" => objective_components === nothing ? nothing :
            Dict{String, Any}(string(name) => value for (name, value) in pairs(objective_components)),
    )

    component_lines = if objective_components === nothing
        ["objective_component_$name=not_optimized" for name in (
            :generator_investment,
            :storage_investment,
            :transmission_investment,
            :load_shedding,
            :generator_operation,
        )]
    else
        ["objective_component_$name=$value" for (name, value) in pairs(objective_components)]
    end
    progress("Writing run summary")
    summary_path = _write_summary(
        joinpath(result_dir, "summary.txt"),
        vcat([
            "OpenEMPIRE.jl run summary",
            "dataset=$dataset",
            "data_folder=$data_folder",
            "config_file=$config_file",
            "input_format=$format",
            "solver=$solver_name",
            "solver_attributes=$(_optimizer_attribute_summary(optimizer_attributes))",
            "seed=$seed",
            "fixed_sample=$fixed_sample_option",
            "optimize=$optimize_model",
            "variables=$(JuMP.num_variables(emp))",
            "constraints=$(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))",
            "build_seconds=$build_seconds",
            "solve_seconds=$solve_seconds",
            "termination_status=$(termination === nothing ? "not_optimized" : string(termination))",
            "objective_value=$(objective === nothing ? "not_optimized" : string(objective))",
            "end_time=$(now())",
        ], component_lines),
    )
    println("Summary written to: $summary_path")
    manifest["status"] = "complete"
    manifest["end_time"] = string(now())
    manifest["timings"]["wall_seconds"] = round(time() - run_start; digits = 3)
    manifest["summary_path"] = summary_path
    manifest["scenario_artifact"] = scenario_artifact
    manifest["perf_enabled"] = _perf_enabled()
    _write_run_manifest(manifest_path, manifest)
    println("Run manifest written to: $manifest_path")

    if _perf_enabled()
        solver_threads = nothing
        for (k, v) in optimizer_attributes
            k == "Threads" && (solver_threads = v)
        end
        perf = JObj([
            "runtime" => "julia",
            "host" => gethostname(),
            "cpu_threads" => Sys.CPU_THREADS,
            "solver_threads" => solver_threads === nothing ? nothing : Int(solver_threads),
            "datetime" => string(now()),
            "dataset" => dataset,
            "config" => config_file,
            "seed" => seed,
            "versions" => JObj([
                "julia" => string(VERSION),
                "jump" => _pkgversion_str(JuMP),
                "gurobi_jl" => _pkgversion_str(Gurobi),
            ]),
            "solver" => solver_name,
            "solver_attributes" => JObj(Pair{String, Any}[string(k) => string(v) for (k, v) in optimizer_attributes]),
            "model" => JObj([
                "variables" => JuMP.num_variables(emp),
                "constraints" => JuMP.num_constraints(emp; count_variable_in_set_constraints = false),
            ]),
            "phases" => perf_phases,
            "totals" => JObj([
                "wall_seconds" => round(time() - run_start; digits = 3),
                "peak_rss_bytes" => Int(Sys.maxrss()),
                "peak_rss_source" => "Sys.maxrss",
            ]),
            "objective_value" => objective,
            "termination_status" => termination === nothing ? nothing : string(termination),
        ])
        perf_path = _write_perf_json(joinpath(result_dir, "perf.json"), perf)
        println("Perf JSON written to: $perf_path")
    end

    println("End time: $(now())")
    flush(stdout)
    progress("Run complete")

    return termination
end

main()
