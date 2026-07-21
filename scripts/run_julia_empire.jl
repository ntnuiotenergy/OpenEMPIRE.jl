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
        "out-of-sample" => "false",
        "fixed-investment-dir" => "",
        "scenario-data-root" => "",
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

function _config_with_fixed_sample(config_file)
    config = YAML.load_file(config_file)
    config["use_scenario_generation"] = true
    config["use_fixed_sample"] = true

    YAML.write_file(config_file, config)
    return config_file
end

function _config_for_out_of_sample(config_file)
    config = YAML.load_file(config_file)
    config["use_scenario_generation"] = false
    config["use_fixed_sample"] = false

    YAML.write_file(config_file, config)
    return config_file
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

const _OOS_SCENARIO_FILENAMES = OpenEMPIRE._OOS_SCENARIO_FILENAMES

function _scenario_data_dir(root::AbstractString)
    scenario_dir = joinpath(root, "ScenarioData")
    isdir(scenario_dir) || throw(ArgumentError(
        "--scenario-data-root must contain a ScenarioData directory: $root",
    ))

    missing = filter(_OOS_SCENARIO_FILENAMES) do filename
        !isfile(joinpath(scenario_dir, filename))
    end
    isempty(missing) || throw(ArgumentError(
        "ScenarioData is missing required OOS files: $(join(missing, ", "))",
    ))
    return scenario_dir
end

function _verify_scenario_tree_checksums(root::AbstractString, metadata)
    files = get(metadata, "files", nothing)
    files isa AbstractDict || return false

    scenario_dir = _scenario_data_dir(root)
    for filename in OpenEMPIRE._OOS_TREE_FILENAMES
        file_metadata = get(files, filename, nothing)
        file_metadata isa AbstractDict || return false
        expected = get(file_metadata, "sha256", nothing)
        expected === nothing && return false
        actual = _sha256_file(joinpath(scenario_dir, filename))
        lowercase(string(expected)) == actual || throw(ArgumentError(
            "OOS scenario checksum mismatch for $filename in $root",
        ))
    end
    return true
end

function _load_scenario_tree_metadata(metadata_path::AbstractString, scenario_root::AbstractString)
    isempty(metadata_path) && return (
        path = "",
        data = Dict{String, Any}(),
        checksums_verified = false,
    )

    metadata = YAML.load_file(metadata_path)
    metadata isa AbstractDict || throw(ArgumentError(
        "OOS scenario metadata must be a mapping: $metadata_path",
    ))
    return (
        path = metadata_path,
        data = metadata,
        checksums_verified = _verify_scenario_tree_checksums(scenario_root, metadata),
    )
end

function _scenario_tree_metadata(root::AbstractString)
    metadata_path = joinpath(root, "metadata.yaml")
    return _load_scenario_tree_metadata(
        isfile(metadata_path) ? metadata_path : "",
        root,
    )
end

function _fixed_investment_source_files(path::AbstractString)
    return OpenEMPIRE._oos_fixed_investment_source_files(path)
end

function _validate_out_of_sample_options(options, generate_only::Bool, fixed_sample::String)
    is_out_of_sample = _boolean_option(options["out-of-sample"], "out-of-sample")
    fixed_investment_dir = String(strip(options["fixed-investment-dir"]))
    scenario_data_root = String(strip(options["scenario-data-root"]))

    if !is_out_of_sample
        isempty(fixed_investment_dir) || throw(ArgumentError(
            "--fixed-investment-dir requires --out-of-sample=true",
        ))
        isempty(scenario_data_root) || throw(ArgumentError(
            "--scenario-data-root requires --out-of-sample=true",
        ))
        return (; is_out_of_sample, fixed_investment_dir, scenario_data_root)
    end

    generate_only && throw(ArgumentError("Out-of-sample evaluation cannot use --generate-only"))
    fixed_sample == "auto" || throw(ArgumentError(
        "Out-of-sample evaluation cannot be combined with --fixed-sample",
    ))
    isempty(fixed_investment_dir) && throw(ArgumentError(
        "--out-of-sample=true requires --fixed-investment-dir=...",
    ))
    isempty(scenario_data_root) && throw(ArgumentError(
        "--out-of-sample=true requires --scenario-data-root=...",
    ))

    _scenario_data_dir(scenario_data_root)
    _scenario_tree_metadata(scenario_data_root)
    _fixed_investment_source_files(fixed_investment_dir)
    return (; is_out_of_sample, fixed_investment_dir, scenario_data_root)
end

function _write_run_manifest(path, manifest)
    mkpath(dirname(path))
    YAML.write_file(path, manifest)
    return path
end

function _dataset_folder(dataset::AbstractString)
    return isabspath(dataset) ? dataset : joinpath("data", dataset)
end

function _run_label(dataset::AbstractString)
    label = basename(normpath(dataset))
    return isempty(label) ? "dataset" : label
end

function _stage_run_inputs(
    result_dir::AbstractString,
    data_folder::AbstractString,
    config_file::AbstractString;
    scenario_data_root::AbstractString = "",
    fixed_investment_dir::AbstractString = "",
)
    input_dir = joinpath(result_dir, "Input")
    staged_data = joinpath(input_dir, "csv")
    staged_config = joinpath(input_dir, "config.yaml")
    staged_scenario_metadata_file = ""

    mkpath(input_dir)
    cp(data_folder, staged_data)
    cp(config_file, staged_config; force = true)

    if !isempty(scenario_data_root)
        source_scenario_dir = _scenario_data_dir(scenario_data_root)
        staged_scenario_dir = joinpath(staged_data, "ScenarioData")
        cp(source_scenario_dir, staged_scenario_dir; force = true)
        source_metadata_file = joinpath(scenario_data_root, "metadata.yaml")
        if isfile(source_metadata_file)
            staged_scenario_metadata_file = joinpath(input_dir, "oos_tree_metadata.yaml")
            cp(source_metadata_file, staged_scenario_metadata_file)
        end
    end

    staged_fixed_investment_dir = ""
    if !isempty(fixed_investment_dir)
        staged_fixed_investment_dir = joinpath(input_dir, "fixed_investments")
        mkpath(staged_fixed_investment_dir)
        for source in _fixed_investment_source_files(fixed_investment_dir)
            cp(source, joinpath(staged_fixed_investment_dir, basename(source)); force = true)
        end
    end

    return (
        staged_data,
        staged_config,
        staged_fixed_investment_dir,
        staged_scenario_metadata_file,
    )
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

"""
    JuliaRunSpec

Fully resolved description of one runner invocation: CLI/config/env values are
folded into this once by [`_resolve_run_spec`](@ref) and the rest of the runner
only reads spec fields. `data_folder`/`config_file` point at the staged copies
under `result_dir/Input`; the `original_*` fields keep the source paths.
"""
Base.@kwdef struct JuliaRunSpec{O, A <: Tuple, C, M}
    dataset::String
    original_data_folder::String
    data_folder::String
    original_config_file::String
    config_file::String
    input_format::Symbol
    solver_name::String
    optimizer::O
    optimizer_attributes::A
    run_config::C
    seed::Int
    fixed_sample::String
    generate_only::Bool
    optimize::Bool
    out_of_sample::Bool
    scenario_tree::String
    scenario_tree_metadata::M
    scenario_tree_metadata_file::String
    scenario_tree_checksums_verified::Bool
    original_scenario_data_root::String
    original_fixed_investment_dir::String
    fixed_investment_dir::String
    result_dir::String
    manifest_path::String
    perf_enabled::Bool
end

"""
    _resolve_run_spec(options) -> JuliaRunSpec

Resolve parsed CLI options into a `JuliaRunSpec`. This validates the source
dataset/config, creates the timestamped result directory, stages the inputs
under `Input/`, applies any fixed-sample or OOS config rewrite to the staged
config, and loads the resolved run config. OOS scenario data and fixed-capacity
tables are also copied under `Input/` so the run has no mutable external inputs.
"""
function _resolve_run_spec(options)
    dataset = options["dataset"]
    original_data_folder = _dataset_folder(dataset)
    original_config_file = options["config"]
    input_format = _input_format(options["format"])
    solver_name = options["solver"]
    seed = parse(Int, options["seed"])
    optimize = lowercase(options["optimize"]) in ("true", "1", "yes")
    generate_only = lowercase(options["generate-only"]) in ("true", "1", "yes")
    fixed_sample = lowercase(options["fixed-sample"])
    oos = _validate_out_of_sample_options(options, generate_only, fixed_sample)

    isdir(original_data_folder) || throw(ArgumentError("Dataset folder not found: $original_data_folder"))
    isfile(original_config_file) || throw(ArgumentError("Config file not found: $original_config_file"))

    timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    result_dir = joinpath(options["results"], "$(timestamp)_$(_run_label(dataset))")
    mkpath(result_dir)
    data_folder, config_file, fixed_investment_dir, scenario_tree_metadata_file =
        _stage_run_inputs(
            result_dir,
            original_data_folder,
            original_config_file;
            scenario_data_root = oos.scenario_data_root,
            fixed_investment_dir = oos.fixed_investment_dir,
        )
    scenario_metadata = if isempty(oos.scenario_data_root)
        (data = Dict{String, Any}(), checksums_verified = false)
    else
        _load_scenario_tree_metadata(scenario_tree_metadata_file, data_folder)
    end

    if oos.is_out_of_sample
        config_file = _config_for_out_of_sample(config_file)
    elseif fixed_sample != "auto"
        if _boolean_option(fixed_sample, "fixed-sample")
            sampling_key = joinpath(data_folder, "ScenarioData", "sampling_key.csv")
            isfile(sampling_key) ||
                throw(ArgumentError("--fixed-sample requires sampling key: $sampling_key"))
            config_file = _config_with_fixed_sample(config_file)
        else
            throw(ArgumentError(
                "--fixed-sample=false is not supported by this runner. Use a config file with use_fixed_sample: False instead.",
            ))
        end
    end
    run_config = YAML.load_file(config_file)

    return JuliaRunSpec(;
        dataset,
        original_data_folder,
        data_folder,
        original_config_file,
        config_file,
        input_format,
        solver_name,
        optimizer = _optimizer(solver_name),
        optimizer_attributes = _optimizer_attributes(solver_name, run_config, options),
        run_config,
        seed,
        fixed_sample,
        generate_only,
        optimize,
        out_of_sample = oos.is_out_of_sample,
        scenario_tree = isempty(oos.scenario_data_root) ? "" : basename(normpath(oos.scenario_data_root)),
        scenario_tree_metadata = scenario_metadata.data,
        scenario_tree_metadata_file,
        scenario_tree_checksums_verified = scenario_metadata.checksums_verified,
        original_scenario_data_root = oos.scenario_data_root,
        original_fixed_investment_dir = oos.fixed_investment_dir,
        fixed_investment_dir,
        result_dir,
        manifest_path = joinpath(result_dir, "run_manifest.yaml"),
        perf_enabled = _perf_enabled(),
    )
end

function _oos_scenario_seed(spec::JuliaRunSpec)
    return get(spec.scenario_tree_metadata, "seed", nothing)
end

function _initial_manifest(spec::JuliaRunSpec)
    return Dict{String, Any}(
        "runtime" => "julia",
        "status" => "started",
        "start_time" => string(now()),
        "host" => gethostname(),
        "cpu_threads" => Sys.CPU_THREADS,
        "versions" => Dict{String, Any}(
            "julia" => string(VERSION),
            "jump" => _pkgversion_str(JuMP),
            "gurobi_jl" => _pkgversion_str(Gurobi),
        ),
        "git" => _git_info(),
        "dataset" => spec.dataset,
        "data_folder" => spec.data_folder,
        "original_data_folder" => spec.original_data_folder,
        "input_staging" => Dict{String, Any}(
            "mode" => "full_copy",
            "staged_data_folder" => spec.data_folder,
            "staged_config_file" => spec.config_file,
            "scenario_data_source" => isempty(spec.original_scenario_data_root) ? nothing :
                spec.original_scenario_data_root,
            "staged_scenario_metadata_file" => isempty(spec.scenario_tree_metadata_file) ? nothing :
                spec.scenario_tree_metadata_file,
            "fixed_investment_source" => isempty(spec.original_fixed_investment_dir) ? nothing :
                spec.original_fixed_investment_dir,
            "staged_fixed_investment_dir" => isempty(spec.fixed_investment_dir) ? nothing :
                spec.fixed_investment_dir,
        ),
        "config_file" => spec.config_file,
        "original_config_file" => spec.original_config_file,
        "config_sha256" => _sha256_file(spec.config_file),
        "original_config_sha256" => _sha256_file(spec.original_config_file),
        "input_format" => string(spec.input_format),
        "solver" => Dict{String, Any}(
            "name" => spec.solver_name,
            "attributes" => _optimizer_attributes_manifest(spec.optimizer_attributes),
        ),
        "seed" => spec.seed,
        "fixed_sample" => spec.fixed_sample,
        "sampling_key" => _sampling_key_info(spec.data_folder),
        "out_of_sample" => Dict{String, Any}(
            "enabled" => spec.out_of_sample,
            "scenario_tree" => isempty(spec.scenario_tree) ? nothing : spec.scenario_tree,
            "scenario_seed" => _oos_scenario_seed(spec),
            "scenario_checksums_verified" => spec.scenario_tree_checksums_verified,
            "scenario_metadata" => isempty(spec.scenario_tree_metadata) ? nothing :
                spec.scenario_tree_metadata,
            "base_investment_run" => isempty(spec.original_fixed_investment_dir) ? nothing :
                spec.original_fixed_investment_dir,
            "investments_fixed" => false,
        ),
        "generate_only" => spec.generate_only,
        "optimize" => spec.optimize,
        "result_dir" => spec.result_dir,
        "timings" => Dict{String, Any}(),
        "model" => nothing,
        "solution" => nothing,
    )
end

function _print_run_header(spec::JuliaRunSpec)
    println("================================================")
    println("OpenEMPIRE.jl run")
    println("================================================")
    println("Dataset:      $(spec.dataset)")
    println("Data folder:  $(spec.data_folder)")
    println("Config file:  $(spec.config_file)")
    println("Input format: $(spec.input_format)")
    println("Solver:       $(spec.solver_name)")
    println("Solver attrs: $(_optimizer_attribute_summary(spec.optimizer_attributes))")
    println("Seed:         $(spec.seed)")
    println("Fixed sample: $(spec.fixed_sample)")
    println("OOS:          $(spec.out_of_sample)")
    if spec.out_of_sample
        println("OOS tree:     $(spec.scenario_tree)")
        println("OOS seed:     $(_oos_scenario_seed(spec))")
        println("Investments:  $(spec.fixed_investment_dir)")
    end
    println("Generate only: $(spec.generate_only)")
    println("Optimize:     $(spec.optimize)")
    println("Result dir:   $(spec.result_dir)")
    println("Start time:   $(now())")
    println("================================================")
    flush(stdout)
    return nothing
end

function _apply_out_of_sample!(spec::JuliaRunSpec, emp, sets, periods, progress)
    spec.out_of_sample || return false

    progress("Fixing strategic capacities from staged investment results")
    OpenEMPIRE.fix_investments_from_results!(
        emp,
        sets,
        periods,
        spec.fixed_investment_dir;
        fix_installed_capacities = true,
    )
    progress("Strategic capacities fixed for out-of-sample evaluation")
    return true
end

function _archive_scenario_artifacts(spec::JuliaRunSpec)
    scenario_artifact = OpenEMPIRE.write_scenario_artifacts(
        spec.result_dir,
        spec.data_folder,
        spec.run_config;
        config_file = spec.config_file,
        dataset = spec.dataset,
        input_format = spec.input_format,
        seed = spec.seed,
    )
    if scenario_artifact !== nothing
        println("Scenario sampling key archived to: $scenario_artifact")
        flush(stdout)
    end
    return scenario_artifact
end

function _run_generate_only(spec::JuliaRunSpec, manifest, run_start, progress)
    progress("Generating scenario data only (no model build)")
    generate_start = time()
    OpenEMPIRE.generate_scenarios(
        spec.config_file,
        spec.data_folder;
        input_format = spec.input_format,
        scenario_rng = MersenneTwister(spec.seed),
        progress,
    )
    generate_seconds = time() - generate_start
    progress("Scenario generation finished in $(round(generate_seconds; digits = 2)) seconds")
    scenario_artifact = _archive_scenario_artifacts(spec)
    summary_path = _write_summary(
        joinpath(spec.result_dir, "summary.txt"),
        [
            "mode=generate-only",
            "dataset=$(spec.dataset)",
            "config=$(spec.config_file)",
            "seed=$(spec.seed)",
            "fixed_sample=$(spec.fixed_sample)",
            "scenario_data_folder=$(joinpath(spec.data_folder, "ScenarioData"))",
            "generate_seconds=$generate_seconds",
        ],
    )
    println("Summary written to: $summary_path")
    run_ended_at = now()
    manifest["status"] = "complete"
    manifest["end_time"] = string(run_ended_at)
    manifest["timings"]["generate_seconds"] = generate_seconds
    manifest["timings"]["wall_seconds"] = round(time() - run_start; digits = 3)
    manifest["sampling_key"] = _sampling_key_info(spec.data_folder)
    manifest["scenario_artifact"] = scenario_artifact
    _write_run_manifest(spec.manifest_path, manifest)
    println("Run manifest written to: $(spec.manifest_path)")
    println("End time: $run_ended_at")
    flush(stdout)
    progress("Run complete")
    return spec.result_dir
end

function _extract_solver_result(objective_components::F, emp) where {F}
    termination = JuMP.termination_status(emp)
    primal_status = JuMP.primal_status(emp)
    dual_status = JuMP.dual_status(emp)
    result_count = JuMP.result_count(emp)
    has_values = JuMP.has_values(emp)
    solved_and_feasible = JuMP.is_solved_and_feasible(emp)
    objective = nothing
    components = nothing
    if solved_and_feasible && has_values
        objective = JuMP.objective_value(emp)
        components = objective_components()
    end
    return (;
        termination,
        primal_status,
        dual_status,
        result_count,
        has_values,
        solved_and_feasible,
        objective,
        objective_components = components,
    )
end

function _solver_result_manifest(solution, optimized::Bool)
    return Dict{String, Any}(
        "termination_status" => optimized ? string(solution.termination) : "not_optimized",
        "primal_status" => optimized ? string(solution.primal_status) : "not_optimized",
        "dual_status" => optimized ? string(solution.dual_status) : "not_optimized",
        "result_count" => optimized ? solution.result_count : 0,
        "has_values" => optimized ? solution.has_values : false,
        "is_solved_and_feasible" => optimized ? solution.solved_and_feasible : false,
        "objective_value" => optimized ? solution.objective : "not_optimized",
        "objective_components" => solution.objective_components === nothing ? nothing :
            Dict{String, Any}(
                string(name) => value for
                (name, value) in pairs(solution.objective_components)
            ),
    )
end

function _solver_failure_message(solution)
    return "Model optimization did not produce a feasible solution: " *
           "termination=$(solution.termination), " *
           "primal_status=$(solution.primal_status), " *
           "dual_status=$(solution.dual_status), " *
           "result_count=$(solution.result_count)"
end

function _solver_run_state(solution, optimized::Bool)
    succeeded = !optimized || solution.solved_and_feasible
    return succeeded, succeeded ? nothing : _solver_failure_message(solution)
end

function _finalize_run_manifest!(
    manifest,
    solution,
    optimized::Bool;
    summary_path,
    scenario_artifact,
    perf_enabled::Bool,
    wall_seconds::Real,
    end_time = now(),
)
    succeeded, run_error = _solver_run_state(solution, optimized)
    manifest["solution"] = _solver_result_manifest(solution, optimized)
    manifest["status"] = succeeded ? "complete" : "failed"
    manifest["error"] = run_error
    manifest["end_time"] = string(end_time)
    manifest["timings"]["wall_seconds"] = round(wall_seconds; digits = 3)
    manifest["summary_path"] = summary_path
    manifest["scenario_artifact"] = scenario_artifact
    manifest["perf_enabled"] = perf_enabled
    return succeeded, run_error
end

function _solve_model!(
    spec::JuliaRunSpec,
    manifest,
    perf_phases,
    emp,
    sets,
    params,
    periods,
    progress,
)
    solve_start = time()
    progress("Starting solver optimization")
    solve_stats = @timed JuMP.optimize!(emp)
    solve_seconds = time() - solve_start
    push!(perf_phases, _perf_phase("solve", solve_seconds; alloc_bytes = solve_stats.bytes, gc_seconds = solve_stats.gctime))
    manifest["timings"]["solve_seconds"] = solve_seconds
    progress("Solver optimization finished in $(round(solve_seconds; digits = 2)) seconds")
    solution = _extract_solver_result(emp) do
        progress("Computing objective component diagnostics")
        OpenEMPIRE.objective_component_values(
            emp,
            sets,
            params,
            periods,
            Discounter(OpenEMPIRE.discount_rate(params), 1, periods),
        )
    end
    println("Solve seconds: $(round(solve_seconds; digits = 2))")
    println("Termination status: $(solution.termination)")
    println("Primal status: $(solution.primal_status)")
    println("Dual status: $(solution.dual_status)")
    println("Result count: $(solution.result_count)")
    if solution.objective === nothing
        println("Objective value: unavailable (no feasible solution)")
    else
        println("Objective value: $(solution.objective)")
        println("Objective components:")
        for (name, value) in pairs(solution.objective_components)
            println("  $name: $value")
        end
    end
    flush(stdout)
    if solution.solved_and_feasible
        progress("Writing solution CSV tables")
        results_stats = @timed OpenEMPIRE.write_solution_tables(spec.result_dir, emp, sets, params, periods)
        output_dir = results_stats.value
        push!(perf_phases, _perf_phase("results", results_stats.time; alloc_bytes = results_stats.bytes, gc_seconds = results_stats.gctime))
        println("Solution CSVs written to: $output_dir")
        flush(stdout)
        progress("Solution CSV tables written to $output_dir")
    else
        println("Solution CSVs skipped because the solved model is not feasible.")
        flush(stdout)
    end
    return merge(solution, (; solve_seconds))
end

function _write_perf_report(spec::JuliaRunSpec, emp, perf_phases, run_start, objective, termination)
    solver_threads = nothing
    for (k, v) in spec.optimizer_attributes
        k == "Threads" && (solver_threads = v)
    end
    perf = JObj([
        "runtime" => "julia",
        "host" => gethostname(),
        "cpu_threads" => Sys.CPU_THREADS,
        "solver_threads" => solver_threads === nothing ? nothing : Int(solver_threads),
        "datetime" => string(now()),
        "dataset" => spec.dataset,
        "config" => spec.config_file,
        "seed" => spec.seed,
        "out_of_sample" => spec.out_of_sample,
        "scenario_tree" => isempty(spec.scenario_tree) ? nothing : spec.scenario_tree,
        "versions" => JObj([
            "julia" => string(VERSION),
            "jump" => _pkgversion_str(JuMP),
            "gurobi_jl" => _pkgversion_str(Gurobi),
        ]),
        "solver" => spec.solver_name,
        "solver_attributes" => JObj(Pair{String, Any}[string(k) => string(v) for (k, v) in spec.optimizer_attributes]),
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
    perf_path = _write_perf_json(joinpath(spec.result_dir, "perf.json"), perf)
    println("Perf JSON written to: $perf_path")
    return perf_path
end

function _run_model(spec::JuliaRunSpec, manifest, run_start, progress)
    perf_phases = JObj[]
    include_investment_constraints = !spec.out_of_sample

    build_start = time()
    progress("Starting model build")
    build_stats = @timed OpenEMPIRE.create_model(
        spec.config_file,
        spec.data_folder;
        optimizer = spec.optimizer,
        optimizer_attributes = spec.optimizer_attributes,
        include_investment_constraints,
        input_format = spec.input_format,
        scenario_rng = MersenneTwister(spec.seed),
        progress,
    )
    emp, periods, sets, params = build_stats.value
    build_seconds = time() - build_start
    investments_fixed = _apply_out_of_sample!(spec, emp, sets, periods, progress)
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
        "investment_constraints_included" => include_investment_constraints,
    )
    manifest["out_of_sample"]["investments_fixed"] = investments_fixed
    _write_run_manifest(spec.manifest_path, manifest)
    scenario_artifact = _archive_scenario_artifacts(spec)
    manifest["sampling_key"] = _sampling_key_info(spec.data_folder)
    manifest["scenario_artifact"] = scenario_artifact
    _write_run_manifest(spec.manifest_path, manifest)

    solution = if spec.optimize
        _solve_model!(spec, manifest, perf_phases, emp, sets, params, periods, progress)
    else
        (
            termination = nothing,
            primal_status = nothing,
            dual_status = nothing,
            result_count = 0,
            has_values = false,
            solved_and_feasible = false,
            objective = nothing,
            objective_components = nothing,
            solve_seconds = 0.0,
        )
    end
    termination = solution.termination
    objective = solution.objective
    objective_components = solution.objective_components
    run_succeeded, run_error = _solver_run_state(solution, spec.optimize)

    component_lines = if objective_components === nothing
        component_value = spec.optimize ? "unavailable" : "not_optimized"
        ["objective_component_$name=$component_value" for name in (
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
    run_ended_at = now()
    summary_path = _write_summary(
        joinpath(spec.result_dir, "summary.txt"),
        vcat([
            "OpenEMPIRE.jl run summary",
            "dataset=$(spec.dataset)",
            "data_folder=$(spec.data_folder)",
            "config_file=$(spec.config_file)",
            "input_format=$(spec.input_format)",
            "solver=$(spec.solver_name)",
            "solver_attributes=$(_optimizer_attribute_summary(spec.optimizer_attributes))",
            "seed=$(spec.seed)",
            "fixed_sample=$(spec.fixed_sample)",
            "out_of_sample=$(spec.out_of_sample)",
            "scenario_tree=$(spec.scenario_tree)",
            "scenario_seed=$(_oos_scenario_seed(spec))",
            "scenario_checksums_verified=$(spec.scenario_tree_checksums_verified)",
            "base_investment_run=$(spec.original_fixed_investment_dir)",
            "fixed_investment_dir=$(spec.fixed_investment_dir)",
            "optimize=$(spec.optimize)",
            "variables=$(JuMP.num_variables(emp))",
            "constraints=$(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))",
            "investment_constraints_included=$include_investment_constraints",
            "build_seconds=$build_seconds",
            "solve_seconds=$(solution.solve_seconds)",
            "termination_status=$(termination === nothing ? "not_optimized" : string(termination))",
            "primal_status=$(spec.optimize ? string(solution.primal_status) : "not_optimized")",
            "dual_status=$(spec.optimize ? string(solution.dual_status) : "not_optimized")",
            "result_count=$(solution.result_count)",
            "objective_value=$(objective === nothing ? (spec.optimize ? "unavailable" : "not_optimized") : string(objective))",
            "run_status=$(run_succeeded ? "complete" : "failed")",
            "error=$(something(run_error, "none"))",
            "end_time=$run_ended_at",
        ], component_lines),
    )
    println("Summary written to: $summary_path")
    _finalize_run_manifest!(
        manifest,
        solution,
        spec.optimize;
        summary_path,
        scenario_artifact,
        perf_enabled = spec.perf_enabled,
        wall_seconds = time() - run_start,
        end_time = run_ended_at,
    )
    _write_run_manifest(spec.manifest_path, manifest)
    println("Run manifest written to: $(spec.manifest_path)")

    spec.perf_enabled &&
        _write_perf_report(spec, emp, perf_phases, run_start, objective, termination)

    println("End time: $(now())")
    flush(stdout)
    progress(run_succeeded ? "Run complete" : "Run failed")

    run_succeeded || error(run_error)

    return termination
end

function main(args = ARGS)
    options = _parse_args(args)
    spec = _resolve_run_spec(options)
    manifest = _initial_manifest(spec)
    _write_run_manifest(spec.manifest_path, manifest)

    _print_run_header(spec)

    progress = _progress_logger()
    progress("Runner initialized")
    run_start = time()

    spec.generate_only && return _run_generate_only(spec, manifest, run_start, progress)
    return _run_model(spec, manifest, run_start, progress)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
