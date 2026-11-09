using Distributed

include(joinpath(@__DIR__, "benders_run_metadata.jl"))

using JuMP, Plasmo, PlasmoBenders, TimeStruct, Gurobi, Random, Dates, Sockets
using OpenEMPIRE

# ---------------------------------------------------------
# Start workers according to the SGE allocation
# ---------------------------------------------------------

hostfile = get(ENV, "SGE_PE_HOSTFILE", "")

isempty(hostfile) &&
    error("SGE_PE_HOSTFILE is not set. Start Julia using run_distributed.sh.")

isfile(hostfile) ||
    error("SGE hostfile does not exist: $hostfile")

project_dir = dirname(Base.active_project())
exeflags = "--project=$project_dir"

local_host = split(gethostname(), ".")[1]

#=for line in eachline(hostfile)
    fields = split(line)

    host = fields[1]
    slots = parse(Int, fields[2])

    short_host = split(host, ".")[1]

    if short_host == local_host
        println("Starting $slots local workers on $host")
        addprocs(slots; exeflags=exeflags)
    else
        println("Starting $slots remote workers on $host")
        addprocs(fill(host, slots); exeflags=exeflags)
    end
end=#

for line in eachline(hostfile)
    fields = split(line)

    host = fields[1]
    slots = parse(Int, fields[2])

    short_host = split(host, ".")[1]

    if short_host == local_host
        println("Starting $slots local workers on $host")
        addprocs(
            slots;
            exeflags=exeflags
        )
    else
        println("Starting $slots remote workers on $host")
        addprocs(
            fill(host, slots);
            exename=joinpath(dirname(@__DIR__), "scripts", "julia_worker.sh"),
            exeflags=exeflags
        )
    end
end

@everywhere using JuMP, Plasmo, PlasmoBenders, Gurobi, OpenEMPIRE, Sockets

worker_ids = workers()
main_worker = myid()

println("Main process: ", main_worker, " on ", gethostname())

for w in worker_ids
    println("Worker ", w, " on ", remotecall_fetch(gethostname, w))
end

println("Main process: ", main_worker, " on ", gethostname())

for w in worker_ids
    println("Worker ", w, " on ", remotecall_fetch(gethostname, w))
end

# ---------------------------------------------------------
# 1. Build OpenEMPIRE model/data
# ---------------------------------------------------------

#config_file = "config/testrun.yaml"
#data_folder = "data/test"
#seed = 1

# ---------------------------------------------------------
# 1. Resolve run configuration from command-line arguments
# ---------------------------------------------------------

function parse_benders_args(args)
    options = Dict(
        "dataset" => "test",
        "data-folder" => "",
        "config" => joinpath("config", "testrun.yaml"),
        "format" => "csv",
        "solver" => "Gurobi",
        "seed" => "1",
        "results" => "results"
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

    isempty(options["dataset"]) &&
        throw(ArgumentError("Dataset name cannot be empty."))

    data_folder = isempty(options["data-folder"]) ?
        joinpath("data", options["dataset"]) :
        options["data-folder"]

    isdir(data_folder) ||
        throw(ArgumentError("Dataset folder not found: $data_folder"))

    isfile(options["config"]) ||
        throw(ArgumentError("Config file not found: $(options["config"])"))

    input_format = get(
        Dict("csv" => :csv, "xlsx" => :xlsx, "auto" => :auto),
        options["format"],
        nothing,
    )

    input_format === nothing &&
        throw(ArgumentError("Unsupported input format: $(options["format"])"))

    solver_name = options["solver"]

    solver_name == "Gurobi" ||
        throw(ArgumentError("Only Gurobi is supported: $solver_name"))

    return (
        dataset = options["dataset"],
        data_folder = data_folder,
        config_file = options["config"],
        input_format = input_format,
        solver_name = solver_name,
        seed = parse(Int, options["seed"]),
        results_dir = options["results"],
    )
end

spec = parse_benders_args(ARGS)

dataset = spec.dataset
data_folder = spec.data_folder
config_file = spec.config_file
input_format = spec.input_format
solver_name = spec.solver_name
seed = spec.seed
results_base_dir = spec.results_dir

println("Dataset:      $dataset")
println("Data folder:  $data_folder")
println("Config file:  $config_file")
println("Input format: $input_format")
println("Solver:       $solver_name")
println("Seed:         $seed")

run_start_time = now()
run_start_clock = time()
model_build_start = time()

periods, sets, params = OpenEMPIRE.prepare_model_inputs(
    config_file,
    data_folder;
    input_format = input_format,
    scenario_rng = MersenneTwister(seed),
)

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

# Build the decomposition graph
decomposition_build_start = time()

graph, master_graph, master, scenario_graphs, scenario_nodes =
    OpenEMPIRE.create_distributed_benders_graph_scenario(
        sets,
        params,
        periods,
        discounter,
        worker_ids,
        main_worker,
    )

decomposition_build_seconds = time() - decomposition_build_start
build_seconds = model_build_seconds + decomposition_build_seconds

println("Benders OptiGraph created successfully.")

# ---------------------------------------------------------
# 3. Create Benders algorithm
# ---------------------------------------------------------


println("\n=== Creating Benders algorithm ===")

max_iters = 100000
tolerance = 1e-7
multicut = parse(Bool, get(ENV, "BENDERS_MULTICUT", "false"))
parallelize_benders = false

# Regularization configuration
regularize = parse(Bool, get(ENV, "BENDERS_REGULARIZE", "false"))
regularize_param = 0.5
warm_start = false

# Gurobi configuartion
benders_solver = optimizer_with_attributes(
    Gurobi.Optimizer,
    "Method" => 1,       # Dual simplex
    "Presolve" => 2,    # Automatic presolve 
    "Threads" => 1,      # Single-threaded
    "Seed" => 0          # Fixed default seed
)



benders = PlasmoBenders.BendersAlgorithm(
    graph,
    master_graph;
    solver = benders_solver,
    multicut = multicut,
    max_iters = max_iters,
    parallelize_benders = parallelize_benders,
    tol = tolerance,
    regularize = regularize,
    regularize_param = regularize_param,
    warm_start = warm_start,
)

println("Benders algorithm created successfully.")

# ---------------------------------------------------------
# 4. Run Benders
# ---------------------------------------------------------

println("\n=== Running Benders ===")

solve_start_clock = time()

PlasmoBenders.run_algorithm!(benders)

solve_seconds = time() - solve_start_clock

println("\n=== Benders timing summary ===")

println(
    "Total iteration time: ",
    sum(PlasmoBenders.get_time_iterations(benders)),
    " seconds"
)

println(
    "Root problem solve time: ",
    PlasmoBenders.get_time_root_problem_solve(benders),
    " seconds"
)

println(
    "Subproblem solve time: ",
    PlasmoBenders.get_time_subproblem_solves(benders),
    " seconds"
)

relative_gap = PlasmoBenders.relative_gap(benders)
converged = relative_gap <= tolerance

time_to_optimal_seconds = converged ?
    time() - run_start_clock :
    nothing

println("Benders converged: ", converged)
println("Time to convergence: ", time_to_optimal_seconds, " seconds")


#Write results to CSV

timestamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")

result_dir = joinpath(
    results_base_dir,
    "benders_scenario_separation",
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

# Investment results
#=OpenEMPIRE.write_investment_csvs(
    output_dir, master, sets, periods,
)=#

# Objective value, relative gap, and number of iterations
#=costs = OpenEMPIRE.benders_cost_totals(
    master,
    scenario_nodes,
    sets,
    params,
    periods,
    discounter,
)=#

OpenEMPIRE.write_benders_objective_csv(
    output_dir,
    benders.objective_value,
    PlasmoBenders.relative_gap(benders),
    length(PlasmoBenders.get_lower_bounds(benders));
    #investment_costs = costs.investment_costs,
    #operational_costs = costs.operational_costs,
)

write_benders_iteration_times(output_dir, benders)

# Cost diagnostics
#=OpenEMPIRE.write_cost_diagnostic_csvs(
    output_dir, sets, params, periods,
)

# Operational results
OpenEMPIRE.write_benders_operational_csvs(
    output_dir, scenario_nodes, sets, params, periods,
)

OpenEMPIRE.write_benders_transmission_operational_report_csv(
    output_dir, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

OpenEMPIRE.write_benders_operational_report_csv(
    output_dir, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Generator report
OpenEMPIRE.write_benders_generator_report_csv(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Storage report
OpenEMPIRE.write_benders_storage_report_csv(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Transmission report
OpenEMPIRE.write_benders_transmission_report_csv(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Curtailment reports
OpenEMPIRE.write_benders_curtailment_report_csvs(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Europe plot report
OpenEMPIRE.write_benders_europe_plot_report_csv(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)

# Europe summary report
OpenEMPIRE.write_benders_europe_summary_report_csv(
    output_dir, master, scenario_nodes, sets, params, periods,
    OpenEMPIRE._period_labels(periods),
)=#

run_end_time = now()
wall_seconds = time() - run_start_clock

write_benders_run_metadata(
    result_dir,
    output_dir;
    decomposition_type = "scenario",
    subproblem_structure = "one_per_strat_period_scenario_combo",
    dataset = dataset,
    input_format = string(input_format),
    original_data_folder = data_folder,
    original_config_file = config_file,
    scenario_seed = seed,
    number_of_subproblems = length(scenario_nodes),
    number_of_scenarios = number_of_scenarios,
    multicut = multicut,
    parallelize_benders = parallelize_benders,
    max_iters = max_iters,
    regularization = Dict{String, Any}(
        "enabled" => regularize,
        "method" => regularize ? "PlasmoBenders regularization" : nothing,
        "parameters" => regularize ?
            Dict{String, Any}(
                "regularize_param" => regularize_param,
                "warm_start" => warm_start,
            ) :
            Dict{String, Any}(),
    ),
    objective_value = benders.objective_value,
    relative_gap = PlasmoBenders.relative_gap(benders),
    iterations = length(PlasmoBenders.get_lower_bounds(benders)),
    converged = PlasmoBenders.relative_gap(benders) <= tolerance,
    build_seconds = build_seconds,
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
println(
    "Relative gap: ",
    PlasmoBenders.relative_gap(benders)
)
println(
    "Number of Benders iterations: ",
    length(PlasmoBenders.get_lower_bounds(benders))
)