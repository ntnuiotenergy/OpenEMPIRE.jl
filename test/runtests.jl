
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
include("test_natural_gas.jl")
include("test_runner_staging.jl")
include("test_out_of_sample.jl")
include("test_oos_full_year.jl")
include("test_oos_aggregation.jl")
include("test_oos_sge.jl")
include("test_oos_staging.jl")
include("test_oos_cleanup.jl")
include("test_oos_remote_setup.jl")
include("test_oos_submission.jl")
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
    test_native_timestruct_operational_weights()
    test_write_solution_csv_tables()
    test_europe_summary_uses_per_scenario_totals()
end

@testset "Natural gas" begin
    test_natural_gas_csv_loading_and_validation()
    test_natural_gas_scenario_mapping_and_costs()
    test_gas_marginal_cost_without_a_fuel_price()
    test_full_model_int_gas_generators_are_priced()
    test_natural_gas_validation_is_enforced()
    test_natural_gas_multi_period_scenario_weighting()
    test_weather_profiles_replicate_across_gas_scenarios()
    test_natural_gas_model_and_results()
    test_natural_gas_storage_transport_and_supply_edges()
    test_natural_gas_three_by_three_scenarios()
    test_natural_gas_oos_compatibility_and_full_year_streaming()
end

@testset "CSV scenarios" begin
    test_read_raw_csv_scenarios()
    test_fixed_sample_raw_csv_scenarios()
    test_configurable_regular_scenario_seasons()
    test_season_months_match_python()
    test_december_is_sampled_into_winter()
    test_python_fixed_sample_scenario_parity()
    test_create_model_with_raw_csv_scenarios()
    test_generate_scenarios_without_model()
    test_write_scenario_sampling_key_artifacts()
    test_create_model_accepts_optimizer_type()
    test_storage_constraints_match_python_formulation()
    test_create_model_adds_storage_max_constraints()
    test_north_sea_transmission_cap_is_config_gated()
    test_emission_constraints_match_python_formulation()
    test_native_dual_weight_normalization()
    test_create_model_respects_emission_cap_config()
end

@testset "Runner staging" begin
    test_natural_gas_manifest_input_provenance()
    test_stage_run_inputs_copies_without_mutating_source()
    test_resolve_single_tree_oos_run_spec()
    test_reject_incomplete_oos_runner_options()
    test_reject_mismatched_oos_tree_config()
    test_runner_solver_result_extraction()
end

@testset "Out-of-sample" begin
    test_generate_single_oos_scenario_tree()
    test_prepare_oos_experiment()
    test_prepare_oos_execution_queue()
    test_manage_oos_execution_queue()
    test_fixed_investment_provenance_and_compatibility()
    test_fix_investments_from_results()
    test_oos_omits_investment_only_constraints()
    test_fix_only_investment_capacities()
    test_fixed_investment_key_validation()
end

@testset "OOS full-year" begin
    test_internalempire_full_year_foundation()
    test_full_year_oos_generation()
    test_chronological_oos_fixture_semantics()
    test_chronological_source_validation()
end

@testset "OOS aggregation" begin
    test_oos_physical_time_weights()
    test_oos_chronological_full_year_time_weights()
    test_internalempire_full_year_aggregation()
    test_summarize_and_aggregate_oos_results()
    test_oos_aggregation_rejects_changed_investments()
end

@testset "OOS Solstorm SGE" begin
    test_parse_oos_sge_output()
    test_oos_solstorm_project_bootstrap()
    test_prepare_and_record_oos_sge_job()
end

@testset "OOS Solstorm staging" begin
    test_prepare_oos_solstorm_staging()
end

@testset "OOS Solstorm cleanup" begin
    test_oos_sidecar_quarantine_command()
    test_prepare_oos_sidecar_quarantine_plan()
end

@testset "OOS Solstorm remote setup" begin
    test_prepare_oos_solstorm_remote_setup()
end

@testset "OOS Solstorm submission" begin
    test_prepare_oos_solstorm_submission()
end

@testset "Validate" begin
    test_validate_params()
end

# @testset "Interface" begin
#     test_interface()
# end

@testset "TimeStruct" begin
    test_timestruct()
    test_chronological_timestruct()
    test_variables()
    test_variable_large()
    test_constraints()
end

@testset "Solve" begin
    test_solve()
end
