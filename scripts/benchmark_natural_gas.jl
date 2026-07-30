#!/usr/bin/env julia

using BenchmarkTools
using OpenEMPIRE

include(joinpath(@__DIR__, "natural_gas_parity_julia.jl"))

repository_root = normpath(joinpath(@__DIR__, ".."))
dataset = joinpath(repository_root, "data", "full_model_int")
fixture = joinpath(repository_root, "test", "data", "natural_gas_parity")
periods = OpenEMPIRE.create_timestruct(
    3,
    5,
    4,
    168,
    2,
    24,
    9;
    operational_hours_per_year = 8760,
)

println("Natural-gas full-dataset parameter parsing")
@btime OpenEMPIRE._read_natural_gas_params_csv(
    $dataset;
    weather_scenarios = 1,
    gas_scenarios = 1,
) samples = 3 evals = 1 seconds = 30

println("Natural-gas operational-period scenario maps (19,440 periods)")
@btime OpenEMPIRE._natural_gas_period_maps($periods, 3) samples = 5 evals = 1 seconds = 30

config = Dict{String, Any}(
    "natural_gas" => true,
    "number_of_scenarios" => 3,
    "number_of_gas_scenarios" => 3,
)
println("Weather × gas combined-scenario count")
@btime OpenEMPIRE.combined_scenario_count($config)

mktempdir() do output_dir
    output_path = joinpath(output_dir, "julia.csv")
    println("Controlled model construction, HiGHS solve, and result writing")
    @btime solve_julia_parity_fixture(
        $fixture,
        $output_path,
    ) samples = 3 evals = 1 seconds = 30
end
