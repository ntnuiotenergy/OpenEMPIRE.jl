using OpenEMPIRE
using JuMP
using Plasmo
using PlasmoBenders
using TimeStruct
using Gurobi
using Random

# ---------------------------------------------------------
# 1. Build OpenEMPIRE model/data
# ---------------------------------------------------------

config_file = "config/testrun.yaml"
data_folder = "data/test"
seed = 1

emp, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    optimizer = Gurobi.Optimizer,
    input_format = :csv,
    scenario_rng = MersenneTwister(seed),
)

discounter = Discounter(
    OpenEMPIRE.discount_rate(params),
    1,
    periods,
)

# ---------------------------------------------------------
# 2. Build Benders OptiGraph
# ---------------------------------------------------------

println("\n=== Creating Benders OptiGraph ===")

graph, master_graph, master, subproblem_graphs, subproblem_nodes =
    OpenEMPIRE.create_benders_graph(
        sets,
        params,
        periods,
        discounter,
    )

println("Benders OptiGraph created successfully.")

# ---------------------------------------------------------
# 3. Create Benders algorithm
# ---------------------------------------------------------

println("\n=== Creating Benders algorithm ===")

benders = PlasmoBenders.BendersAlgorithm(
    graph,
    master_graph;
    solver = Gurobi.Optimizer,
    multicut = true,
    max_iters = 500,
)

println("Benders algorithm created successfully.")

# ---------------------------------------------------------
# 4. Run Benders
# ---------------------------------------------------------

println("\n=== Running Benders ===")

PlasmoBenders.run_algorithm!(benders)

# ---------------------------------------------------------
# 5. Results
# ---------------------------------------------------------

println("\n=== Benders results ===")

println("Termination / objective value: ", benders.objective_value)
println("Relative gap: ", PlasmoBenders.relative_gap(benders))
println("Number of Benders iterations: ", length(PlasmoBenders.get_lower_bounds(benders)))