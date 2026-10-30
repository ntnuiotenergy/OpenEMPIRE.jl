include(joinpath(@__DIR__, "benders_run_metadata.jl"))

using OpenEMPIRE
using JuMP
using Plasmo
using PlasmoBenders
using TimeStruct
using Gurobi
using Random
using Dates

#config_file = "config/testrun.yaml"
#data_folder = "data/test"
#seed = 1

function parse_benders_args(args)
    options = Dict(
        "dataset" => "test",
        "data-folder" => "",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "Gurobi",
        "seed" => "1",
    )

    for arg in args
        startswith(arg, "--") ||
            throw(ArgumentError("Expected --key=value, got: $arg"))
        occursin("=", arg) ||
            throw(ArgumentError("Expected --key=value, got: $arg"))

        key, value = split(arg[3:end], "="; limit = 2)

        haskey(options, key) ||
            throw(ArgumentError("Unsupported argument: --$key"))

        options[key] = value
    end

    data_folder = isempty(options["data-folder"]) ?
        joinpath("data", options["dataset"]) :
        options["data-folder"]

    isdir(data_folder) ||
        throw(ArgumentError("Dataset folder not found: $data_folder"))

    config_file = options["config"]
    isfile(config_file) ||
        throw(ArgumentError("Config file not found: $config_file"))

    input_format = get(
        Dict("csv" => :csv, "xlsx" => :xlsx, "auto" => :auto),
        options["format"],
        nothing,
    )
    input_format === nothing &&
        throw(ArgumentError("Unsupported input format: $(options["format"])"))

    solver_name = options["solver"]
    optimizer = if solver_name == "Gurobi"
        Gurobi.Optimizer
    elseif solver_name == "HiGHS"
        HiGHS.Optimizer
    else
        throw(ArgumentError("Unsupported solver: $solver_name"))
    end

    return (
        dataset = options["dataset"],
        data_folder = data_folder,
        config_file = config_file,
        input_format = input_format,
        solver_name = solver_name,
        optimizer = optimizer,
        seed = parse(Int, options["seed"]),
    )
end

spec = parse_benders_args(ARGS)

dataset = spec.dataset
data_folder = spec.data_folder
config_file = spec.config_file
input_format = spec.input_format
solver_name = spec.solver_name
optimizer = spec.optimizer
seed = spec.seed

println("Dataset:      $dataset")
println("Data folder:  $data_folder")
println("Config file:  $config_file")
println("Input format: $input_format")
println("Solver:       $solver_name")
println("Seed:         $seed")


run_start_time = now()
run_start_clock = time()
model_build_start = time()

emp, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    optimizer = optimizer,
    input_format = input_format,
    scenario_rng = MersenneTwister(seed),
)

# Count scenarios (shared across all strategic-period subproblems)
first_sp = first(strat_periods(periods))
first_rp = first(repr_periods(first_sp))
number_of_scenarios = length(opscenarios(first_rp))

model_build_seconds = time() - model_build_start

discounter = Discounter(
    OpenEMPIRE.discount_rate(params),
    1,
    periods,
)

# ---------------------------------------------------------
# 2. Build Benders OptiGraph
# ---------------------------------------------------------

println("\n=== Creating Benders OptiGraph ===")

decomposition_build_start = time()

graph, master_graph, master, subproblem_graphs, subproblem_nodes =
    OpenEMPIRE.create_benders_graph(
        sets,
        params,
        periods,
        discounter,
    )

decomposition_build_seconds = time() - decomposition_build_start

println("Benders OptiGraph created successfully.")

# ---------------------------------------------------------
# 3. Create Benders algorithm
# ---------------------------------------------------------

println("\n=== Creating Benders algorithm ===")

max_iters = 100000
tolerance = 1e-7
multicut = false
parallelize_benders = false

# Regularization configuration
regularize = false
regularize_param = 0.5
warm_start = false


benders = PlasmoBenders.BendersAlgorithm(
    graph,
    master_graph;
    solver = optimizer,
    multicut = multicut,
    max_iters = max_iters,
    tol = tolerance,
    regularize = regularize,
    regularize_param = regularize_param,
    parallelize_benders = parallelize_benders,
    warm_start = warm_start, #må være false når regularize = true
)

println("Benders algorithm created successfully.")

# ---------------------------------------------------------
# 4. Run Benders
# ---------------------------------------------------------

println("\n=== Running Benders ===")

solve_start_clock = time()
PlasmoBenders.run_algorithm!(benders)
solve_seconds = time() - solve_start_clock

relative_gap = PlasmoBenders.relative_gap(benders)
converged = relative_gap <= tolerance

time_to_optimal_seconds = converged ?
    time() - run_start_clock :
    nothing

println("Benders converged: ", converged)
println("Time to convergence: ", time_to_optimal_seconds, " seconds")

#PlasmoBenders.run_algorithm!(benders)

#Write to CSV
timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")

result_dir = joinpath(
    "results",
    "benders_investment_periods",
    "$(timestamp)_$(dataset)",
)

output_dir = joinpath(result_dir, "output")
mkpath(output_dir)

function write_benders_iteration_times(output_dir, benders)

    filepath = joinpath(output_dir, "benders_iteration_times.csv")

    iteration_times = benders.time_iterations

    isempty(iteration_times) && return

    longest_iteration = maximum(iteration_times)
    average_iteration = sum(iteration_times) / length(iteration_times)

    open(filepath, "w") do file
        println(file, "iteration,duration_seconds")

        # Individual iteration times
        for (i, t) in enumerate(iteration_times)
            println(file, "$i,$t")
        end

        # Summary statistics
        println(file, "")
        println(file, "Summary,duration_seconds")
        println(file, "Longest iteration,$longest_iteration")
        println(file, "Average iteration,$average_iteration")
    end

    println("Iteration timings written to: $filepath")
    println("Longest iteration: $longest_iteration seconds")
    println("Average iteration: $average_iteration seconds")
end

#=OpenEMPIRE.write_investment_csvs(
    output_dir,
    master,
    sets,
    periods,
)

OpenEMPIRE.write_benders_operational_csvs(
    output_dir,
    subproblem_nodes,
    sets,
    params,
    periods,
)=#

costs = OpenEMPIRE.benders_cost_totals(
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    discounter,
)

OpenEMPIRE.write_benders_objective_csv(
    output_dir,
    benders.objective_value,
    PlasmoBenders.relative_gap(benders),
    length(PlasmoBenders.get_lower_bounds(benders));
    investment_costs = costs.investment_costs,
    operational_costs = costs.operational_costs,
)

write_benders_iteration_times(output_dir, benders)

#=OpenEMPIRE.write_cost_diagnostic_csvs(
    output_dir,
    sets,
    params,
    periods,
)

OpenEMPIRE.write_benders_generator_report_csv(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_storage_report_csv(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_transmission_report_csv(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_transmission_operational_report_csv(
    output_dir,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_operational_report_csv(
    output_dir,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_curtailment_report_csvs(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_europe_plot_report_csv(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_europe_summary_report_csv(
    output_dir,
    master,
    subproblem_nodes,
    sets,
    params,
    periods,
    OpenEMPIRE._period_labels(periods),
)=#

run_end_time = now()
wall_seconds = time() - run_start_clock

iterations = length(PlasmoBenders.get_lower_bounds(benders))

write_benders_run_metadata(
    result_dir,
    output_dir;
    decomposition_type = "investment_period",
    subproblem_structure = "one_per_investment_period",
    dataset = dataset,
    input_format = string(input_format),
    original_data_folder = data_folder,
    original_config_file = config_file,
    scenario_seed = seed,
    number_of_subproblems = length(subproblem_nodes),
    number_of_scenarios = number_of_scenarios,
    multicut = multicut,
    parallelize_benders = parallelize_benders,
    max_iters = max_iters,
    regularization = Dict{String, Any}(
        "enabled" => PlasmoBenders.get_regularize(benders),
        "method" => "PlasmoBenders regularization",
        "parameters" => Dict{String, Any}(
            "regularize_param" => PlasmoBenders.get_regularize_param(benders),
            "warm_start" => false,
        ),
    ),
    objective_value = benders.objective_value,
    relative_gap = relative_gap,
    iterations = iterations,
    converged = converged,
    build_seconds = model_build_seconds + decomposition_build_seconds,
    solve_seconds = solve_seconds,
    time_to_optimal_seconds = time_to_optimal_seconds,
    wall_seconds = wall_seconds,
    start_time = run_start_time,
    end_time = run_end_time,
    solver_name = solver_name,
    run_status = "complete",
)

# ---------------------------------------------------------
# 5. Results
# ---------------------------------------------------------

println("\n=== Benders results ===")

println("Termination / objective value: ", benders.objective_value)
println("Relative gap: ", PlasmoBenders.relative_gap(benders))
println("Number of Benders iterations: ", length(PlasmoBenders.get_lower_bounds(benders)))

#=function write_benders_solution_tables(
    result_dir,
    master,
    subproblem_nodes,
    sets,
    par,
    periods,
)
    # Write investment results from master
    # Write operational results from each subproblem
    # Reuse existing CSV-writing helpers where possible
end=#