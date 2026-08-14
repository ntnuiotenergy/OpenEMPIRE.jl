function _write_oos_aggregation_fixture(
    root,
    tree,
    seed;
    shed_rows,
    staged_tree = tree,
    manifest_tree = staged_tree,
    full_year_tree_index = nothing,
)
    result_dir = joinpath(root, tree, "run")
    input_dir = joinpath(result_dir, "Input")
    fixed_dir = joinpath(input_dir, "fixed_investments")
    output_dir = joinpath(result_dir, "output")
    mkpath(fixed_dir)
    mkpath(output_dir)

    config = YAML.load_file(joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml"))
    config["forecast_horizon_year"] = 2025
    config["leap_years_investment"] = 5
    if full_year_tree_index === nothing
        config["regular_seasons"] = ["winter", "summer"]
        config["length_of_regular_season"] = 2
        config["n_peak_seasons"] = 1
        config["len_peak_season"] = 1
        config["number_of_scenarios"] = 2
    else
        config["regular_seasons"] = ["winter"]
        config["length_of_regular_season"] = 365
        config["n_peak_seasons"] = 1
        config["len_peak_season"] = 1
        config["number_of_scenarios"] = 1
        config["operational_hours_per_year"] = 8760
    end
    config_file = joinpath(input_dir, "config.yaml")
    metadata_file = joinpath(input_dir, "oos_tree_metadata.yaml")
    YAML.write_file(config_file, config)
    metadata = Dict{String, Any}(
        "tree" => staged_tree,
        "seed" => seed,
        "staged_from_metadata_sha256" => "source-tree-metadata-$seed",
    )
    if full_year_tree_index !== nothing
        chunk = OpenEMPIRE._internalempire_full_year_chunks()[full_year_tree_index]
        metadata["evaluation_mode"] = "chronological_full_year"
        metadata["chronology"] = Dict{String, Any}(
            "formulation" => "internalempire_24x365",
            "tree_index" => full_year_tree_index,
            "source_hour_start" => first(chunk),
            "source_hour_end" => last(chunk),
            "dummy_peak_results_ignored" => true,
        )
    end
    staged_tree == tree || (metadata["staged_from_tree"] = tree)
    YAML.write_file(metadata_file, metadata)

    for aliases in OpenEMPIRE._OOS_FIXED_INVESTMENT_FILENAMES
        filename = first(aliases)
        contents = "$(filename),fixture\n"
        write(joinpath(fixed_dir, filename), contents)
        write(joinpath(output_dir, filename), contents)
    end
    YAML.write_file(joinpath(fixed_dir, "source_config.yaml"), config)
    write(
        joinpath(fixed_dir, "summary.txt"),
        "OpenEMPIRE.jl run summary\noptimize=true\ntermination_status=OPTIMAL\n",
    )
    write(
        joinpath(output_dir, "loadShed.csv"),
        "Node,Period,Scenario,Season,Hour,loadShed\n" * join(shed_rows, "\n") * "\n",
    )

    components = Dict{String, Any}(
        "generator_investment" => 10.0,
        "storage_investment" => 20.0,
        "transmission_investment" => 30.0,
        "generator_operation" => 40.0,
        "load_shedding" => 50.0,
    )
    manifest = Dict{String, Any}(
        "status" => "complete",
        "config_sha256" => OpenEMPIRE._oos_sha256_file(config_file),
        "out_of_sample" => Dict{String, Any}(
            "enabled" => true,
            "scenario_tree" => manifest_tree,
            "scenario_seed" => seed,
            "scenario_checksums_verified" => true,
            "investments_fixed" => true,
            "scenario_metadata" => metadata,
        ),
        "solution" => Dict{String, Any}(
            "is_solved_and_feasible" => true,
            "has_values" => true,
            "termination_status" => "OPTIMAL",
            "objective_value" => 150.0,
            "objective_components" => components,
        ),
    )
    YAML.write_file(joinpath(result_dir, "run_manifest.yaml"), manifest)
    return result_dir
end

function test_oos_physical_time_weights()
    config = Dict{String, Any}(
        "forecast_horizon_year" => 2025,
        "leap_years_investment" => 5,
        "regular_seasons" => ["winter", "summer"],
        "length_of_regular_season" => 2,
        "n_peak_seasons" => 1,
        "len_peak_season" => 1,
        "number_of_scenarios" => 2,
    )
    weights = OpenEMPIRE._oos_time_weights(config)
    regular = weights[(1, 1, "winter", 1)]
    peak = weights[(1, 1, "peak1", 1)]
    @test regular.conditional ≈ (8760 - 1) / (2 * 2)
    @test regular.probability ≈ 0.5
    @test regular.expected ≈ (8760 - 1) / (2 * 2 * 2)
    @test peak.conditional ≈ 1.0
    @test peak.expected ≈ 0.5
    @test sum(weight.expected for weight in values(weights)) ≈ 8760.0
end

function test_oos_chronological_full_year_time_weights()
    config = Dict{String, Any}(
        "forecast_horizon_year" => 2025,
        "leap_years_investment" => 5,
        "regular_seasons" => ["winter"],
        "length_of_regular_season" => 365,
        "n_peak_seasons" => 1,
        "len_peak_season" => 1,
        "number_of_scenarios" => 1,
        "operational_hours_per_year" => 8760,
    )
    weights = OpenEMPIRE._oos_time_weights(config)
    @test length(weights) == 366
    @test weights[(1, 1, "winter", 1)] == (
        conditional = 8759 / 365,
        probability = 1.0,
        expected = 8759 / 365,
    )
    @test weights[(1, 1, "winter", 365)] == (
        conditional = 8759 / 365,
        probability = 1.0,
        expected = 8759 / 365,
    )
    @test weights[(1, 1, "peak1", 1)] == (
        conditional = 1.0,
        probability = 1.0,
        expected = 1.0,
    )
    @test sum(weight.expected for weight in values(weights)) ≈ 8760.0
    @test OpenEMPIRE._internalempire_full_year_hour(1, 1) == 1
    @test OpenEMPIRE._internalempire_full_year_hour(2, 1) == 366
    @test OpenEMPIRE._internalempire_full_year_hour(24, 365) == 8760
    @test_throws ArgumentError OpenEMPIRE._internalempire_full_year_hour(25, 1)
    @test_throws ArgumentError OpenEMPIRE._internalempire_full_year_hour(1, 366)
end

function test_internalempire_full_year_aggregation()
    mktempdir() do root
        shed_rows = ["N1,1,1,winter,$hour,0.0" for hour in 1:365]
        push!(shed_rows, "N1,1,1,peak1,1,999.0")
        result_dirs = [
            _write_oos_aggregation_fixture(
                root,
                "oos_tree$tree_index",
                tree_index;
                shed_rows,
                full_year_tree_index = tree_index,
            ) for tree_index in 1:24
        ]

        first_summary = OpenEMPIRE.summarize_oos_result(first(result_dirs)).summary
        @test first_summary.FullYearFormulation == "internalempire_24x365"
        @test first_summary.FullYearTreeIndex == 1
        @test first_summary.DummyPeakResultsIgnored
        @test first_summary.ExpectedAnnualENSAllPeriods_MWh == 0.0
        @test first_summary.NodeHoursAboveThreshold == 0

        aggregated = OpenEMPIRE.aggregate_oos_results(
            reverse(result_dirs),
            joinpath(root, "aggregated");
            combined_files = ["loadShed.csv"],
        )
        @test [row.FullYearTreeIndex for row in aggregated.summaries] == collect(1:24)
        combined = only(aggregated.combined_files)
        @test combined.rows == 8760
        @test combined.dummy_peak_rows_ignored == 24
        rows = collect(CSV.File(combined.path))
        @test propertynames(first(rows)) == [
            :Tree,
            :Seed,
            :Run,
            :ScenarioTree,
            :HourFullYear,
            :Node,
            :Period,
            :Scenario,
            :Season,
            :Hour,
            :loadShed,
        ]
        @test [Int(row.HourFullYear) for row in rows] == collect(1:8760)
        @test all(String(row.Season) == "winter" for row in rows)
        @test all(String(row.Tree) == String(row.ScenarioTree) for row in rows)
        manifest = YAML.load_file(aggregated.manifest_file)
        @test manifest["full_year_formulation"] == "internalempire_24x365"
        @test manifest["dummy_peak_results_ignored"] == true
        @test only(manifest["combined_files"])["dummy_peak_rows_ignored"] == 24
    end
end

function test_summarize_and_aggregate_oos_results()
    mktempdir() do root
        shed_rows = [
            "N1,1,1,winter,1,1.0",
            "N2,1,1,winter,1,2.0",
            "N1,1,2,peak1,1,4.0",
        ]
        first_run = _write_oos_aggregation_fixture(root, "oos_tree1", 101; shed_rows)
        second_run = _write_oos_aggregation_fixture(
            root,
            "oos_tree2",
            102;
            shed_rows,
            staged_tree = "oos_tree1",
            manifest_tree = "oos_tree1",
        )

        result = OpenEMPIRE.summarize_oos_result(first_run)
        @test result.summary.FixedInvestmentsVerified
        @test result.summary.DiscountedFixedInvestmentCost_EUR ≈ 60.0
        @test result.summary.DiscountedNonInvestmentObjective_EUR ≈ 90.0
        expected_regular = 3.0 * (8760 - 1) / (2 * 2 * 2)
        expected_peak = 4.0 * 0.5
        @test result.summary.ExpectedAnnualENSAllPeriods_MWh ≈ expected_regular + expected_peak
        @test result.summary.NodeHoursAboveThreshold == 3
        @test result.summary.MaxLoadShed_MW ≈ 4.0
        @test result.summary.MaxSeason == "peak1"

        scenario_one = only(filter(
            row -> row.Period == 1 && row.Scenario == 1,
            result.ens_by_period_scenario,
        ))
        @test scenario_one.ConditionalAnnualENS_MWh ≈ 3.0 * (8760 - 1) / (2 * 2)
        @test scenario_one.ExpectedAnnualENSContribution_MWh ≈ expected_regular

        discovered = OpenEMPIRE.discover_oos_result_dirs([root])
        @test discovered == sort([first_run, second_run])
        output_dir = joinpath(root, "aggregated")
        aggregated = OpenEMPIRE.aggregate_oos_results(
            discovered,
            output_dir;
            combined_files = ["loadShed.csv"],
        )
        @test length(aggregated.summaries) == 2
        @test Set(row.Tree for row in aggregated.summaries) ==
              Set(["oos_tree1", "oos_tree2"])
        @test isfile(aggregated.summary_file)
        @test isfile(aggregated.scenario_file)
        @test isfile(aggregated.season_file)
        @test only(aggregated.combined_files).rows == 6
        combined_load_shed = collect(CSV.File(only(aggregated.combined_files).path))
        @test propertynames(first(combined_load_shed)) ==
              [:Tree, :Seed, :Run, :Node, :Period, :Scenario, :Season, :Hour, :loadShed]
        @test Set(row.Tree for row in combined_load_shed) == Set(["oos_tree1", "oos_tree2"])
        aggregation_manifest = YAML.load_file(aggregated.manifest_file)
        @test aggregation_manifest["tree_count"] == 2
        @test aggregation_manifest["ens_discounted"] == false
        @test aggregation_manifest["ens_formula"] ==
              "load_shed_mw * multiple_strat * probability * duration"
        @test only(aggregation_manifest["combined_files"])["rows"] == 6
        @test_throws ArgumentError OpenEMPIRE.aggregate_oos_results(
            discovered,
            output_dir,
        )
    end
end

function test_oos_aggregation_rejects_changed_investments()
    mktempdir() do root
        result_dir = _write_oos_aggregation_fixture(
            root,
            "oos_tree1",
            101;
            shed_rows = ["N1,1,1,winter,1,0.0"],
        )
        write(joinpath(result_dir, "output", "genInvCap.csv"), "changed\n")
        @test_throws ArgumentError OpenEMPIRE.summarize_oos_result(result_dir)
    end
end
