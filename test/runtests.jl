
using CSV
using HiGHS
using JuMP
using OpenEMPIRE
using Dates
using Random
using Test
using TimeStruct
using YAML
# using Xpress

include("test_excel.jl")
include("test_csv.jl")
include("test_scenario_csv.jl")
include("test_out_of_sample.jl")
include("test_multiple_oos_trees.jl")
include("test_oos_result_aggregation.jl")
#include("test_interface.jl")
include("test_timestruct.jl")
include("test_solve.jl")

@testset "Excel" begin
    test_read_excel_sets()
    test_read_excel_params()
end

@testset "CSV" begin
    test_read_csv_dataset()
    test_read_bundled_csv_datasets()
    test_native_timestruct_operational_weights()
    test_write_solution_csv_tables()
    test_europe_summary_uses_per_scenario_totals()
end

@testset "CSV scenarios" begin
    test_read_raw_csv_scenarios()
    test_fixed_sample_raw_csv_scenarios()
    test_configurable_regular_scenario_seasons()
    test_python_fixed_sample_scenario_parity()
    test_create_model_with_raw_csv_scenarios()
    test_generate_scenarios_without_model()
    test_create_model_reads_separate_scenario_data_root()
    test_write_scenario_sampling_key_artifacts()
    test_create_model_accepts_optimizer_type()
    test_storage_constraints_match_python_formulation()
    test_create_model_adds_storage_max_constraints()
    test_emission_constraints_match_python_formulation()
    test_native_dual_weight_normalization()
    test_create_model_respects_emission_cap_config()
end

@testset "Out-of-sample" begin
    test_fix_investments_from_results()
    test_discover_and_select_oos_trees()
    test_validate_oos_tree_files()
    test_validate_fixed_investment_files()
    test_write_multiple_oos_summary()
    test_aggregate_oos_result_file()
    test_aggregate_oos_missing_file_modes()
    test_aggregate_oos_status_filter()
end

@testset "Validate" begin
    test_validate_params()
end

# @testset "Interface" begin
#     test_interface()
# end

@testset "TimeStruct" begin
    test_timestruct()
    test_variables()
    test_variable_large()
    test_constraints()
end

@testset "Solve" begin
    test_solve()
end
