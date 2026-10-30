
using Dates
using YAML

function _benders_metadata_git_info()
    read_git(command) = try
        strip(read(command, String))
    catch
        nothing
    end

    status = read_git(`git status --short`)

    return Dict{String, Any}(
        "branch" => read_git(`git rev-parse --abbrev-ref HEAD`),
        "commit" => read_git(`git rev-parse HEAD`),
        "dirty" => status === nothing ? nothing : !isempty(status),
    )
end

function write_benders_run_metadata(
    result_dir::AbstractString,
    output_dir::AbstractString;
    decomposition_type,
    subproblem_structure,
    dataset = "test",
    input_format = "csv",
    original_data_folder = nothing,
    original_config_file = nothing,
    scenario_seed = nothing,
    number_of_scenarios = nothing,
    strategic_periods = nothing,
    number_of_subproblems = nothing,
    multicut = false,
    parallelize_benders = false,
    max_iters = nothing,
    regularization = Dict{String, Any}("enabled" => false),
    objective_value = nothing,
    relative_gap = nothing,
    iterations = nothing,
    termination_status = nothing,
    converged = nothing,
    build_seconds = nothing,
    solve_seconds = nothing,
    time_to_optimal_seconds = nothing,
    wall_seconds = nothing,
    start_time = nothing,
    end_time = now(),
    solver_name = "Gurobi",
    solver_attributes = Dict{String, Any}(),
    run_status = "complete",
    error = nothing,
)
    mkpath(result_dir)

    output_files = if isdir(output_dir)
        sort(filter(
            name -> isfile(joinpath(output_dir, name)),
            readdir(output_dir),
        ))
    else
        String[]
    end

    manifest = Dict{String, Any}(
        "run_type" => "benders",
        "dataset" => dataset,
        "status" => run_status,
        "start_time" => start_time === nothing ? nothing : string(start_time),
        "end_time" => string(end_time),
        "problem" => Dict{String, Any}(
            "input_format" => input_format,
            "original_data_folder" => original_data_folder,
            "original_config_file" => original_config_file,
            "scenario_seed" => scenario_seed,
            "number_of_scenarios" => number_of_scenarios,
            "strategic_periods" => strategic_periods,
        ),
        "decomposition" => Dict{String, Any}(
            "type" => decomposition_type,
            "subproblem_structure" => subproblem_structure,
            "number_of_subproblems" => number_of_subproblems,
        ),
        "algorithm" => Dict{String, Any}(
            "name" => "Benders",
            "multicut" => multicut,
            "parallelization_enabled" => parallelize_benders,
            "max_iterations" => max_iters,
            "regularization" => regularization,
        ),
        "convergence" => Dict{String, Any}(
            "objective_value" => objective_value,
            "relative_gap" => relative_gap,
            "iterations" => iterations,
            "termination_status" => termination_status,
            "converged" => converged,
        ),
        "timings" => Dict{String, Any}(
            "build_seconds" => build_seconds,
            "solve_seconds" => solve_seconds,
            "time_to_optimal_seconds" => time_to_optimal_seconds,
            "wall_seconds" => wall_seconds,
        ),
        "solver" => Dict{String, Any}(
            "name" => solver_name,
            "attributes" => solver_attributes,
        ),
        "output" => Dict{String, Any}(
            "output_dir" => output_dir,
            "files" => output_files,
        ),
        "git" => _benders_metadata_git_info(),
        "error" => error,
    )

    manifest_path = joinpath(result_dir, "run_manifest.yaml")
    YAML.write_file(manifest_path, manifest)

    summary_lines = [
        "OpenEMPIRE.jl Benders run summary",
        "run_type=benders",
        "dataset=$dataset",
        "decomposition_type=$decomposition_type",
        "subproblem_structure=$subproblem_structure",
        "number_of_subproblems=$number_of_subproblems",
        "input_format=$input_format",
        "scenario_seed=$scenario_seed",
        "multicut=$multicut",
        "parallelization_enabled=$parallelize_benders",
        "max_iterations=$max_iters",
        "regularization=$regularization",
        "objective_value=$objective_value",
        "relative_gap=$relative_gap",
        "iterations=$iterations",
        "termination_status=$termination_status",
        "converged=$converged",
        "build_seconds=$build_seconds",
        "solve_seconds=$solve_seconds",
        "time_to_optimal_seconds=$time_to_optimal_seconds",
        "wall_seconds=$wall_seconds",
        "solver=$solver_name",
        "run_status=$run_status",
        "error=$(error === nothing ? "none" : error)",
    ]

    summary_path = joinpath(result_dir, "summary.txt")
    open(summary_path, "w") do io
        println(io, join(summary_lines, "\n"))
    end

    println("Run manifest written to: $manifest_path")
    println("Summary written to: $summary_path")

    return (manifest_path = manifest_path, summary_path = summary_path)
end
