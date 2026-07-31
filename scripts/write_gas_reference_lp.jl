# Build the Julia natural-gas model on the time-reduced full_model_int instance and
# write its LP, for comparison against InternalEMPIRE's own LP.
# See docs/natural_gas_reference_comparison.md.
#
# Usage:
#   julia --project=. scripts/write_gas_reference_lp.jl <output.lp>

using OpenEMPIRE
using JuMP

const CONFIG = get(
    ENV,
    "GASPARITY_CONFIG",
    joinpath(@__DIR__, "..", "config", "gas_reference_comparison.yaml"),
)
const DATA = joinpath(@__DIR__, "..", "data", "full_model_int")

function main(output)
    # Scenario generation writes sampling_key.csv back into the dataset folder, and
    # this reduced time structure produces a key for 1 scenario / 3 seasons that
    # would overwrite the tracked production key. Build from a throwaway copy.
    mktempdir() do root
        data = joinpath(root, "full_model_int")
        cp(DATA, data)
        if get(ENV, "GASPARITY_ZERO_CCS", "") == "1"
            zero_ccs_cost!(data)
        end
        key = get(ENV, "GASPARITY_SAMPLING_KEY", "")
        if !isempty(key)
            # Solution comparison only. Both sides must draw the SAME weather hours:
            # gas-fired generation follows electricity dispatch, so independent draws
            # make every gas quantity differ for reasons unrelated to the port.
            cp(key, joinpath(data, "ScenarioData", "sampling_key.csv"); force = true)
            @info "using external sampling key" key
        end
        build(data, output)
    end
    return nothing
end

"""
Zero the CCS transport-and-storage cost for a solution comparison run.

InternalEMPIRE declares `CCSCostTSVariable` but leaves both the parameter and its
data load commented out (`empire.py:462` and `empire.py:748`), so under an emission
cap a CCS generator's marginal cost there is variable O&M alone. OpenEMPIRE.jl does
charge it (`utils.jl:200-202`), which makes GasCCS and GasCCSadv more expensive than
in the reference and would show up as a dispatch difference unrelated to the gas
module. Zeroing it on a throwaway copy isolates that, and only affects those two
generators.
"""
function zero_ccs_cost!(data_folder)
    # Operational term (utils.jl marginal cost).
    path = joinpath(data_folder, "Generator", "CCSCostTSVariable.csv")
    lines = readlines(path)
    open(path, "w") do io
        println(io, lines[1])
        for line in lines[2:end]
            isempty(strip(line)) && continue
            println(io, first(split(line, ',')), ",0.0")
        end
    end

    # Investment term. The reference disables this one too (`empire.py:461`), so it
    # must be zeroed as well or Julia builds different CCS capacity, which changes
    # dispatch and therefore every gas quantity.
    open(joinpath(data_folder, "Generator", "CCSCostTSFixed.csv"), "w") do io
        println(io, "CCS_TSfixed_cost_in_euro_per_tCO2")
        println(io, "0.0")
    end

    @info "CCS transport-and-storage cost zeroed for comparison (variable + investment)"
    return nothing
end

function build(data_folder, output)
    emp, periods, sets, params = OpenEMPIRE.create_model(CONFIG, data_folder)

    n_gas_nodes = length(OpenEMPIRE.natural_gas_nodes(sets))
    n_periods = length(collect(periods))
    println("gas_nodes = ", n_gas_nodes)
    println("operational_periods = ", n_periods)
    println("variables = ", JuMP.num_variables(emp))
    println("constraints = ", sum(values(JuMP.num_constraints(emp; count_variable_in_set_constraints = false))))

    JuMP.write_to_file(emp, output)
    println("wrote ", output)
    return nothing
end

main(length(ARGS) >= 1 ? ARGS[1] : error("give an output .lp path"))
