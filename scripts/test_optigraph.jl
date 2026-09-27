using OpenEMPIRE
using JuMP
using Plasmo
using TimeStruct
using Gurobi
using Random

# ---------------------------------------------------------
# 1. Build original OpenEMPIRE model
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

println("\n=== Solving original model ===")

optimize!(emp)

println("Original termination status: ", termination_status(emp))
println("Original objective value: ", objective_value(emp))


# ---------------------------------------------------------
# 2. Build OptiGraph
# ---------------------------------------------------------

println("\n=== Creating OptiGraph ===")

graph, master, subproblem_nodes =
    OpenEMPIRE.create_benders_graph(
        sets,
        params,
        periods,
        discounter,
    )

set_to_node_objectives(graph)

println("\n=== Graph objective created ===")

graph_obj = objective_function(graph)

println("Graph objective type: ", typeof(graph_obj))

# ---------------------------------------------------------
# 4. Solve full OptiGraph
# ---------------------------------------------------------

println("\n=== Solving full OptiGraph ===")

set_optimizer(graph, Gurobi.Optimizer)

optimize!(graph)

status = termination_status(graph)

println("\nGraph termination status: ", status)

if status != MOI.OPTIMAL
    println("Graph did not solve to OPTIMAL.")
    exit()
end