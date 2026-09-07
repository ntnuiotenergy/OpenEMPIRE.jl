
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
include("test_empire_sets.jl")
include("test_country_constraints.jl")
include("test_ccs_captured_co2.jl")
include("test_ccs_cost_mode.jl")
include("test_biomass_fallback.jl")
include("test_generation_growth.jl")
include("test_bioccs_headroom.jl")
include("test_country_smoke.jl")
include("test_scenario_csv.jl")
include("test_annuity.jl")
include("test_out_of_sample.jl")
include("test_oos_full_year.jl")
include("test_oos_aggregation.jl")
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

@testset "EmpireSets" begin
    test_empire_sets_countries_default_empty()
    test_empire_sets_explicit_empty_country_mapping()
    test_empire_sets_countries_positional_constructor_unchanged()
    test_empire_sets_nodes_of_country_accessors()
    test_empire_sets_country_validation()
end

@testset "NUTS2 country constraints" begin
    test_country_generator_capacity_constraints()
    test_country_generator_constraints_are_data_driven()
end

@testset "CCS captured-CO2 and cost accounting" begin
    test_ccs_explicit_captured_co2_takes_precedence()
    test_ccs_counterpart_gross_minus_net()
    test_ccs_capture_rate_fallback_only_as_last_resort()
    test_ccs_gasccs_counterpart_resolution()
    test_ccs_ligniteccs_counterpart_resolution()
    test_ccs_negative_emission_and_bioccs()
    test_ccs_invalid_values_rejected()
    test_ccs_explicit_captured_co2_loaded_and_used()
    test_ccs_non_ccs_costs_unchanged()
    test_ccs_fixed_cost_matches_python()
    test_ccs_marginal_cost_matches_python()
    test_ccs_residual_co2_price_matches_python()
end

@testset "CCS T&S cost provenance / mode" begin
    test_ccs_fixed_cost_provenance_and_modes()
    test_ccs_variable_cost_seven_periods_excel_to_param()
    test_ccs_realized_coefficients_match_python_in_python_nuts_mode()
    test_ccs_cost_mode_leaves_non_ccs_unchanged()
    test_ccs_fixed_cost_explicit_user_value_not_overwritten()
end

@testset "Biomass country/both per-node fallback" begin
    test_biomass_fallback_country_scope_covers_unmapped_nodes()
    test_biomass_fallback_no_duplicate_rows_for_mapped_nodes()
    test_biomass_fallback_zero_availability_node_is_constrained_and_warns()
    test_biomass_fallback_system_scope_unchanged()
    test_biomass_fallback_both_scope_builds_all_three_row_families()
    test_biomass_fallback_absent_when_no_unmapped_nodal_data()
end

@testset "Biomass limit flag gate" begin
    test_biomass_limit_flag_true_builds_annual_constraints()
    test_biomass_limit_flag_false_suppresses_annual_constraints()
    test_biomass_limit_flag_ignored_when_no_annual_data()
end

@testset "Node generation-growth limit" begin
    test_generation_growth_loader_maps_periods()
    test_generation_growth_loader_absent_is_nothing()
    test_generation_growth_loader_reads_northsea_csv()
    test_generation_growth_flag_false_creates_nothing()
    test_generation_growth_flag_true_creates_constraints()
    test_generation_growth_first_period_skipped()
    test_generation_growth_count_and_indices_match_python()
    test_generation_growth_uses_period_specific_data_rate()
    test_generation_growth_uses_config_fallback_when_absent()
    test_generation_growth_multiplier_scales_with_leap_years()
    test_generation_growth_exact_coefficients_small_fixture()
    test_generation_growth_rejects_negative_config_rate()
    test_generation_growth_partial_profile_per_period_fallback()
    test_generation_growth_supplied_zero_is_not_fallback()
    test_generation_growth_trailing_gap_uses_fallback()
end

@testset "BioCCS capacity headroom" begin
    test_bioccs_factor_one_is_identity()
    test_bioccs_factor_gt_one_changes_only_bioccs()
    test_bioccs_non_bioccs_generators_unchanged()
    test_bioccs_affects_only_python_equivalent_constraints()
    test_bioccs_nodal_minimum_matches_python_plain_sum()
    test_bioccs_invalid_factor_rejected()
end

@testset "NUTS2 country smoke test" begin
    test_country_smoke_baseline_solve()
    test_country_smoke_minbuild_forces_investment()
    test_country_smoke_maxbuild_limits_investment()
    test_country_smoke_maxinstalled_limits_capacity()
    test_country_smoke_non_nuts2_regression()
end

@testset "CSV" begin
    test_read_csv_dataset()
    test_read_bundled_csv_datasets()
    test_read_full_model_int_dataset()
    test_internalempire_bioenergy_constraints()
    test_internalempire_missing_hydro_default()
    test_ccs_fixed_cost_is_data_driven()
    test_native_timestruct_operational_weights()
    test_write_solution_csv_tables()
    test_europe_summary_uses_per_scenario_totals()
end

@testset "CSV scenarios" begin
    test_read_raw_csv_scenarios()
    test_fixed_sample_raw_csv_scenarios()
    test_configurable_regular_scenario_seasons()
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
    test_offshore_transmission_cap_is_on_by_default()
    test_offshore_energy_hub_converter()
    test_offshore_wind_farm_without_generators_is_rejected()
    test_emission_constraints_match_python_formulation()
    test_objective_matches_component_sum()
    test_native_dual_weight_normalization()
    test_create_model_respects_emission_cap_config()
    test_norwegian_elspot_columns_map_to_their_nodes()
    test_norwegian_availability_is_populated()
end

@testset "Out-of-sample" begin
    test_generate_single_oos_scenario_tree()
    test_prepare_oos_experiment()
    test_prepare_oos_execution_queue()
    test_manage_oos_execution_queue()
    test_fixed_investment_provenance_and_compatibility()
    test_fix_investments_from_results()
    test_fix_only_investment_capacities()
    test_fixed_investment_key_validation()
    test_oos_omits_investment_only_constraints()
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
    test_gurobi_numeric_attribute_parsing()
    test_resolve_julia_run_spec()
    test_resolve_single_tree_oos_run_spec()
    test_reject_incomplete_oos_runner_options()
    test_reject_mismatched_oos_tree_config()
    test_runner_solver_result_extraction()
end

@testset "Annuity" begin
    test_annuity_factor()
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
