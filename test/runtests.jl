
using CSV
using HiGHS
using JuMP
using OpenEMPIRE
using Dates
using Logging
using Random
using Test
using TimeStruct
using YAML
# using Xpress

include("test_excel.jl")
include("test_csv.jl")
include("test_scenario_csv.jl")
include("test_natural_gas.jl")
include("test_out_of_sample.jl")
include("test_runner_performance.jl")
include("test_runner_manifest.jl")
include("test_runner_staging.jl")
include("test_runner_spec.jl")
#include("test_interface.jl")
include("test_timestruct.jl")
include("test_solve.jl")

@testset "Excel" begin
    test_read_excel_sets()
    test_read_excel_params()
end

@testset "CSV" begin
    test_read_csv_dataset()
    test_ccs_fixed_cost_is_data_driven()
    test_read_bundled_csv_datasets()
    test_read_full_model_int_dataset()
    test_internalempire_bioenergy_constraints()
    test_internalempire_missing_hydro_default()
    test_native_timestruct_operational_weights()
    test_write_solution_csv_tables()
    test_europe_summary_uses_per_scenario_totals()
end

@testset "CSV scenarios" begin
    test_read_raw_csv_scenarios()
    test_fixed_sample_raw_csv_scenarios()
    test_configurable_regular_scenario_seasons()
    test_season_months_match_python()
    test_december_is_sampled_into_fall()
    test_scenario_filter_metrics_and_clustering()
    test_scenario_filter_make_and_use()
    test_scenario_filter_defaults()
    test_python_fixed_sample_scenario_parity()
    test_create_model_with_raw_csv_scenarios()
    test_generate_scenarios_without_model()
    test_write_scenario_sampling_key_artifacts()
    test_write_scenario_copula_cluster_artifacts()
    test_copula_clusters_make_writes_csv()
    test_copula_clusters_use_samples_from_clusters()
    test_copula_clusters_multiple_variables()
    test_filter_takes_precedence_over_copula_clusters()
    test_copula_clusters_use_without_make_errors()
    test_copula_clusters_invalid_copula_name_errors()
    test_create_model_accepts_optimizer_type()
    test_storage_constraints_match_python_formulation()
    test_create_model_adds_storage_max_constraints()
    test_north_sea_transmission_cap_is_config_gated()
    test_north_sea_cap_pins_generatorless_offshore_node_to_zero()
    test_emission_constraints_match_python_formulation()
    test_objective_matches_component_sum()
    test_native_dual_weight_normalization()
    test_create_model_respects_emission_cap_config()
end

@testset "Natural gas" begin
    test_natural_gas_csv_loading_and_validation()
    test_natural_gas_scenario_mapping_and_costs()
    test_gas_marginal_cost_without_a_fuel_price()
    test_full_model_int_gas_generators_are_priced()
    test_natural_gas_validation_is_enforced()
    test_multiple_gas_scenarios_rejected_until_verified()
    test_natural_gas_multi_period_scenario_weighting()
    test_weather_profiles_replicate_across_gas_scenarios()
    test_natural_gas_model_and_results()
    test_natural_gas_storage_transport_and_supply_edges()
    test_natural_gas_three_by_three_scenarios()
    test_natural_gas_controlled_solution_parity()
end

@testset "Out-of-sample" begin
    test_fix_investments_from_results()
end

@testset "Runner performance" begin
    test_runner_performance_helpers()
end

@testset "Runner manifest" begin
    test_runner_manifest_helpers()
end

@testset "Runner staging" begin
    test_stage_run_inputs_copies_without_mutating_source()
end

@testset "Runner spec" begin
    test_resolve_julia_run_spec()
    test_gurobi_numeric_attribute_parsing()
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
