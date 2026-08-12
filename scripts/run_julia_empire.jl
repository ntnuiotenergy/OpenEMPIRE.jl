#!/usr/bin/env julia

using Dates
import Gurobi
using HiGHS
using JuMP
using OpenEMPIRE
using Random
using TimeStruct
using YAML

isdefined(@__MODULE__, :JObj) ||
    include(joinpath(@__DIR__, "runner_performance.jl"))
isdefined(@__MODULE__, :_write_run_manifest) ||
    include(joinpath(@__DIR__, "runner_manifest.jl"))
isdefined(@__MODULE__, :_stage_run_inputs) ||
    include(joinpath(@__DIR__, "runner_staging.jl"))

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

function _optional_float(value, key)
    (value === nothing || ismissing(value)) && return nothing
    value isa Real && return Float64(value)
    text = strip(string(value))
    isempty(text) && return nothing
    try
        return parse(Float64, text)
    catch err
        throw(ArgumentError("Unsupported floating-point value for $key: $value"))
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

function _set_optimizer_float_attribute!(attributes, name, value)
    parsed = _optional_float(value, name)
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
        attributes = Pair{String, Real}[]
        config_attribute_names = (
            "solver_method" => "Method",
            "solver_crossover" => "Crossover",
            "solver_presolve" => "Presolve",
            "solver_threads" => "Threads",
            "solver_scaleflag" => "ScaleFlag",
            "solver_numericfocus" => "NumericFocus",
            "solver_barhomogeneous" => "BarHomogeneous",
            "solver_seed" => "Seed",
        )
        for (config_key, gurobi_name) in config_attribute_names
            _set_optimizer_attribute!(attributes, gurobi_name, get(config, config_key, nothing))
        end
        float_config_attribute_names = (
            "solver_barconvtol" => "BarConvTol",
            "solver_feasibilitytol" => "FeasibilityTol",
        )
        for (config_key, gurobi_name) in float_config_attribute_names
            _set_optimizer_float_attribute!(
                attributes,
                gurobi_name,
                get(config, config_key, nothing),
            )
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

function _write_summary(path, lines)
    mkpath(dirname(path))
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return path
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

function _write_raw_solution(model::JuMP.Model, path::AbstractString)
    JuMP.has_values(model) ||
        throw(ArgumentError("Cannot write a raw solution before the model has values."))
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "variable,value")
        for variable in JuMP.all_variables(model)
            escaped_name = replace(JuMP.name(variable), '"' => "\"\"")
            println(io, '"', escaped_name, "\",", JuMP.value(variable))
        end
    end
    return path
end

function _solver_model_attribute(model::JuMP.Model, name::AbstractString)
    try
        return JuMP.MOI.get(JuMP.backend(model), Gurobi.ModelAttribute(String(name)))
    catch
        return nothing
    end
end

"""
    JuliaRunSpec

Fully resolved description of one runner invocation: CLI/config/env values are
folded into this once by [`_resolve_run_spec`](@ref) and the rest of the runner
only reads spec fields. `data_folder`/`config_file` point at the staged copies
under `result_dir/Input`; the `original_*` fields keep the source paths.
"""
Base.@kwdef struct JuliaRunSpec{O, A <: Tuple, C}
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
    fixed_investment_dir::String
    result_dir::String
    manifest_path::String
    perf_enabled::Bool
end

"""
    _resolve_run_spec(options) -> JuliaRunSpec

Resolve parsed CLI options into a `JuliaRunSpec`. This validates the source
dataset/config, creates the timestamped result directory, stages the inputs
under `Input/`, applies the fixed-sample config rewrite to the staged config,
and loads the resolved run config.
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
    out_of_sample = _boolean_option(options["out-of-sample"], "out-of-sample")
    fixed_investment_dir = options["fixed-investment-dir"]

    isdir(original_data_folder) || throw(ArgumentError("Dataset folder not found: $original_data_folder"))
    isfile(original_config_file) || throw(ArgumentError("Config file not found: $original_config_file"))
    if out_of_sample && !generate_only && isempty(fixed_investment_dir)
        throw(ArgumentError("--out-of-sample=true requires --fixed-investment-dir=..."))
    end

    timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    result_dir = joinpath(options["results"], "$(timestamp)_$(_run_label(dataset))")
    mkpath(result_dir)
    data_folder, config_file = _stage_run_inputs(result_dir, original_data_folder, original_config_file)

    if fixed_sample != "auto"
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
        out_of_sample,
        fixed_investment_dir,
        result_dir,
        manifest_path = joinpath(result_dir, "run_manifest.yaml"),
        perf_enabled = _perf_enabled(),
    )
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
        "generate_only" => spec.generate_only,
        "optimize" => spec.optimize,
        "out_of_sample" => spec.out_of_sample,
        "fixed_investment_dir" => spec.fixed_investment_dir,
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
    println("Generate only: $(spec.generate_only)")
    println("Optimize:     $(spec.optimize)")
    println("Out of sample: $(spec.out_of_sample)")
    println("Fixed investments: $(spec.fixed_investment_dir)")
    println("Result dir:   $(spec.result_dir)")
    println("Start time:   $(now())")
    println("================================================")
    flush(stdout)
    return nothing
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
    push!(
        perf_phases,
        _perf_phase(
            "solve",
            solve_seconds;
            alloc_bytes = solve_stats.bytes,
            gc_seconds = solve_stats.gctime,
        ),
    )
    manifest["timings"]["solve_seconds"] = solve_seconds
    progress("Solver optimization finished in $(round(solve_seconds; digits = 2)) seconds")
    termination = JuMP.termination_status(emp)
    primal_status = JuMP.primal_status(emp)
    dual_status = JuMP.dual_status(emp)
    has_values = JuMP.has_values(emp)
    objective = has_values ? JuMP.objective_value(emp) : nothing
    objective_bound = try
        JuMP.objective_bound(emp)
    catch
        nothing
    end
    relative_gap = try
        JuMP.relative_gap(emp)
    catch
        nothing
    end
    objective_components = if has_values
        progress("Computing objective component diagnostics")
        OpenEMPIRE.objective_component_values(
            emp,
            sets,
            params,
            periods,
            Discounter(OpenEMPIRE.discount_rate(params), 1, periods),
        )
    else
        nothing
    end
    solver_diagnostics = Dict{String, Any}()
    if spec.solver_name == "Gurobi"
        for attribute in ("BarIterCount", "ConstrVio", "DualVio", "ComplVio")
            attribute_value = _solver_model_attribute(emp, attribute)
            attribute_value === nothing ||
                (solver_diagnostics[attribute] = attribute_value)
        end
    end
    println("Solve seconds: $(round(solve_seconds; digits = 2))")
    println("Termination status: $termination")
    println("Primal status: $primal_status")
    println("Dual status: $dual_status")
    println("Objective value: $objective")
    println("Objective bound: $objective_bound")
    println("Relative gap: $relative_gap")
    for (name, value) in sort!(collect(solver_diagnostics); by = first)
        println("Gurobi $name: $value")
    end
    if objective_components !== nothing
        println("Objective components:")
        for (name, value) in pairs(objective_components)
            println("  $name: $value")
        end
    end
    flush(stdout)
    if JuMP.is_solved_and_feasible(emp)
        progress("Writing solution CSV tables")
        results_stats =
            @timed OpenEMPIRE.write_solution_tables(
                spec.result_dir,
                emp,
                sets,
                params,
                periods,
            )
        output_dir = results_stats.value
        push!(
            perf_phases,
            _perf_phase(
                "results",
                results_stats.time;
                alloc_bytes = results_stats.bytes,
                gc_seconds = results_stats.gctime,
            ),
        )
        println("Solution CSVs written to: $output_dir")
        flush(stdout)
        progress("Solution CSV tables written to $output_dir")
        if _config_bool(spec.run_config, "write_raw_solution", false)
            raw_solution_path = joinpath(spec.result_dir, "raw_solution.csv")
            progress("Writing complete raw variable solution")
            _write_raw_solution(emp, raw_solution_path)
            println("Raw variable solution written to: $raw_solution_path")
            flush(stdout)
        end
    else
        println("Solution CSVs skipped because the solved model is not feasible.")
        flush(stdout)
    end
    return (;
        termination,
        primal_status,
        dual_status,
        objective,
        objective_bound,
        relative_gap,
        objective_components,
        solver_diagnostics,
        solve_seconds,
    )
end

function _write_perf_report(
    spec::JuliaRunSpec,
    emp,
    perf_phases,
    run_start,
    objective,
    termination,
)
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
        "versions" => JObj([
            "julia" => string(VERSION),
            "jump" => _pkgversion_str(JuMP),
            "gurobi_jl" => _pkgversion_str(Gurobi),
        ]),
        "solver" => spec.solver_name,
        "solver_attributes" => JObj(
            Pair{String, Any}[
                string(name) => string(value) for
                (name, value) in spec.optimizer_attributes
            ],
        ),
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

    progress("Starting model build")
    build_stats = @timed OpenEMPIRE.create_model(
        spec.config_file,
        spec.data_folder;
        optimizer = spec.optimizer,
        optimizer_attributes = spec.optimizer_attributes,
        input_format = spec.input_format,
        scenario_rng = MersenneTwister(spec.seed),
        progress,
    )
    emp, periods, sets, params = build_stats.value
    build_seconds = build_stats.time
    push!(
        perf_phases,
        _perf_phase(
            "build",
            build_seconds;
            alloc_bytes = build_stats.bytes,
            gc_seconds = build_stats.gctime,
        ),
    )
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
    _write_run_manifest(spec.manifest_path, manifest)
    scenario_artifact = _archive_scenario_artifacts(spec)
    manifest["sampling_key"] = _sampling_key_info(spec.data_folder)
    manifest["scenario_artifact"] = scenario_artifact
    _write_run_manifest(spec.manifest_path, manifest)

    if spec.out_of_sample
        progress("Fixing investments from previous result directory")
        OpenEMPIRE.fix_investments_from_results!(
            emp,
            sets,
            periods,
            spec.fixed_investment_dir;
            fix_installed_capacities = true,
        )
    end

    solution = if spec.optimize
        _solve_model!(spec, manifest, perf_phases, emp, sets, params, periods, progress)
    else
        (
            termination = nothing,
            primal_status = nothing,
            dual_status = nothing,
            objective = nothing,
            objective_bound = nothing,
            relative_gap = nothing,
            objective_components = nothing,
            solver_diagnostics = Dict{String, Any}(),
            solve_seconds = 0.0,
        )
    end
    termination = solution.termination
    objective = solution.objective
    objective_components = solution.objective_components
    manifest["solution"] = Dict{String, Any}(
        "termination_status" => termination === nothing ? "not_optimized" : string(termination),
        "primal_status" => solution.primal_status === nothing ? "not_optimized" : string(solution.primal_status),
        "dual_status" => solution.dual_status === nothing ? "not_optimized" : string(solution.dual_status),
        "objective_value" => objective === nothing ? "not_optimized" : objective,
        "objective_bound" => solution.objective_bound === nothing ? "unavailable" : solution.objective_bound,
        "relative_gap" => solution.relative_gap === nothing ? "unavailable" : solution.relative_gap,
        "solver_diagnostics" => solution.solver_diagnostics,
        "objective_components" => objective_components === nothing ? nothing :
            Dict{String, Any}(string(name) => value for (name, value) in pairs(objective_components)),
    )

    component_lines = if objective_components === nothing
        ["objective_component_$name=not_optimized" for name in (
            :generator_investment,
            :storage_investment,
            :transmission_investment,
            :offshore_converter_investment,
            :load_shedding,
            :generator_operation,
            :natural_gas_terminal_import,
            :natural_gas_transport_shedding,
        )]
    else
        ["objective_component_$name=$value" for (name, value) in pairs(objective_components)]
    end
    solver_diagnostic_lines = [
        "solver_diagnostic_$name=$value" for
        (name, value) in sort!(collect(solution.solver_diagnostics); by = first)
    ]
    progress("Writing run summary")
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
            "fixed_investment_dir=$(spec.fixed_investment_dir)",
            "optimize=$(spec.optimize)",
            "variables=$(JuMP.num_variables(emp))",
            "constraints=$(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))",
            "build_seconds=$build_seconds",
            "solve_seconds=$(solution.solve_seconds)",
            "termination_status=$(termination === nothing ? "not_optimized" : string(termination))",
            "primal_status=$(solution.primal_status === nothing ? "not_optimized" : string(solution.primal_status))",
            "dual_status=$(solution.dual_status === nothing ? "not_optimized" : string(solution.dual_status))",
            "objective_value=$(objective === nothing ? "not_optimized" : string(objective))",
            "objective_bound=$(solution.objective_bound === nothing ? "unavailable" : string(solution.objective_bound))",
            "relative_gap=$(solution.relative_gap === nothing ? "unavailable" : string(solution.relative_gap))",
            "end_time=$(now())",
        ], solver_diagnostic_lines, component_lines),
    )
    println("Summary written to: $summary_path")
    manifest["status"] = "complete"
    manifest["end_time"] = string(now())
    manifest["timings"]["wall_seconds"] = round(time() - run_start; digits = 3)
    manifest["summary_path"] = summary_path
    manifest["scenario_artifact"] = scenario_artifact
    manifest["perf_enabled"] = spec.perf_enabled
    _write_run_manifest(spec.manifest_path, manifest)
    println("Run manifest written to: $(spec.manifest_path)")

    spec.perf_enabled &&
        _write_perf_report(spec, emp, perf_phases, run_start, objective, termination)

    println("End time: $(now())")
    flush(stdout)
    progress("Run complete")

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
