using JuMP
using OpenEMPIRE
using Test
using TimeStruct

function _write_oos_csv(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
end

function test_fix_investments_from_results()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("A", "B", "HVDC"), ("B", "A", "HVDC")],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))

    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        output_dir = joinpath(result_dir, "Output")

        _write_oos_csv(joinpath(output_dir, "genInvCap.csv"), "Node,Generator,Period,genInvCap\nA,Solar,1,3.5\n")
        _write_oos_csv(joinpath(output_dir, "transmissionInvCap.csv"), "FromNode,ToNode,Period,transmissionInvCap\nA,B,1,4.5\n")
        _write_oos_csv(joinpath(output_dir, "storPWInvCap.csv"), "Node,Storage,Period,storPWInvCap\nA,battery,1,5.5\n")
        _write_oos_csv(joinpath(output_dir, "storENInvCap.csv"), "Node,Storage,Period,storENInvCap\nA,battery,1,6.5\n")
        _write_oos_csv(joinpath(output_dir, "genInstalledCap.csv"), "Node,Generator,Period,genInstalledCap\nA,Solar,1,7.5\n")
        _write_oos_csv(joinpath(output_dir, "transmissionInstalledCap.csv"), "FromNode,ToNode,Period,transmissionInstalledCap\nA,B,1,8.5\n")
        _write_oos_csv(joinpath(output_dir, "storPWInstalledCap.csv"), "Node,Storage,Period,storPWInstalledCap\nA,battery,1,9.5\n")
        _write_oos_csv(joinpath(output_dir, "storENInstalledCap.csv"), "Node,Storage,Period,storENInstalledCap\nA,battery,1,10.5\n")

        OpenEMPIRE.fix_investments_from_results!(model, sets, periods, result_dir)
    end

    @test JuMP.is_fixed(model[:genInvCap]["A", "Solar", sp])
    @test JuMP.fix_value(model[:genInvCap]["A", "Solar", sp]) == 3.5
    @test JuMP.is_fixed(model[:transmissionInvCap]["A", "B", sp])
    @test JuMP.fix_value(model[:transmissionInvCap]["A", "B", sp]) == 4.5
    @test JuMP.is_fixed(model[:storPWInvCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storPWInvCap]["A", "battery", sp]) == 5.5
    @test JuMP.is_fixed(model[:storENInvCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storENInvCap]["A", "battery", sp]) == 6.5

    @test JuMP.is_fixed(model[:genInstalledCap]["A", "Solar", sp])
    @test JuMP.fix_value(model[:genInstalledCap]["A", "Solar", sp]) == 7.5
    @test JuMP.is_fixed(model[:transmissionInstalledCap]["A", "B", sp])
    @test JuMP.fix_value(model[:transmissionInstalledCap]["A", "B", sp]) == 8.5
    @test JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storPWInstalledCap]["A", "battery", sp]) == 9.5
    @test JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storENInstalledCap]["A", "battery", sp]) == 10.5
end

function _oos_test_sets_and_periods()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [
            ("A", "B", "HVDC"),
            ("B", "A", "HVDC"),
        ],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    return sets, periods
end

function _oos_source_snapshot(root)
    snapshot = Dict{String, String}()
    for (directory, _, filenames) in walkdir(root)
        for filename in filenames
            path = joinpath(directory, filename)
            snapshot[relpath(path, root)] = OpenEMPIRE._oos_sha256_file(path)
        end
    end
    return snapshot
end

function test_generate_single_oos_scenario_tree()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        source_before = _oos_source_snapshot(source_data)

        tree_dir = joinpath(root, "trees", "oos_tree1")
        generated_tree = OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            tree_dir;
            input_format = :csv,
            seed = 23,
        )

        @test generated_tree == abspath(tree_dir)
        @test _oos_source_snapshot(source_data) == source_before
        scenario_dir = joinpath(generated_tree, "ScenarioData")
        @test all(
            isfile(joinpath(scenario_dir, filename)) for
            filename in OpenEMPIRE._OOS_TREE_FILENAMES
        )

        metadata = YAML.load_file(joinpath(generated_tree, "metadata.yaml"))
        @test metadata["schema_version"] == 1
        @test metadata["generator"] == "OpenEMPIRE.generate_oos_scenario_tree"
        @test metadata["tree"] == "oos_tree1"
        @test metadata["seed"] == 23
        @test metadata["input_format"] == "csv"
        @test metadata["source_data_folder"] == abspath(source_data)
        @test metadata["source_data_sha256"] == OpenEMPIRE._oos_directory_sha256(source_data)
        @test metadata["source_config_sha256"] == OpenEMPIRE._oos_sha256_file(config_file)
        @test metadata["config"]["number_of_scenarios"] == 3
        for filename in OpenEMPIRE._OOS_TREE_FILENAMES
            file_metadata = metadata["files"][filename]
            generated_file = joinpath(scenario_dir, filename)
            @test file_metadata["bytes"] == filesize(generated_file)
            @test file_metadata["sha256"] == OpenEMPIRE._oos_sha256_file(generated_file)
        end

        second_tree = OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            joinpath(root, "trees", "oos_tree2");
            input_format = :csv,
            seed = 23,
        )
        for filename in OpenEMPIRE._OOS_TREE_FILENAMES
            @test OpenEMPIRE._oos_sha256_file(joinpath(second_tree, "ScenarioData", filename)) ==
                  OpenEMPIRE._oos_sha256_file(joinpath(scenario_dir, filename))
        end
        @test _oos_source_snapshot(source_data) == source_before

        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            tree_dir;
            input_format = :csv,
            seed = 24,
        )
        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            config_file,
            source_data,
            joinpath(source_data, "oos_tree");
            input_format = :csv,
            seed = 24,
        )

        disabled_config = joinpath(root, "disabled.yaml")
        config = YAML.load_file(config_file)
        config["use_scenario_generation"] = false
        YAML.write_file(disabled_config, config)
        disabled_tree = joinpath(root, "trees", "disabled")
        @test_throws ArgumentError OpenEMPIRE.generate_oos_scenario_tree(
            disabled_config,
            source_data,
            disabled_tree;
            input_format = :csv,
            seed = 24,
        )
        @test !ispath(disabled_tree)
    end
end

function _oos_tree_scenario_snapshot(tree_dir)
    scenario_dir = joinpath(tree_dir, "ScenarioData")
    return Dict(
        filename => OpenEMPIRE._oos_sha256_file(joinpath(scenario_dir, filename)) for
        filename in OpenEMPIRE._OOS_TREE_FILENAMES
    )
end

function test_prepare_oos_experiment()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        source_before = _oos_source_snapshot(source_data)
        experiment_dir = joinpath(root, "experiment")

        prepared = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            num_trees = 2,
            seed_start = 40,
            input_format = :csv,
        )

        @test prepared == abspath(experiment_dir)
        @test _oos_source_snapshot(source_data) == source_before
        manifest_file = joinpath(experiment_dir, "experiment.yaml")
        manifest = YAML.load_file(manifest_file)
        @test manifest["schema_version"] == 1
        @test manifest["kind"] == "oos_tree_experiment"
        @test manifest["status"] == "complete"
        @test manifest["seed_start"] == 40
        @test manifest["num_trees"] == 2
        @test [tree["seed"] for tree in manifest["trees"]] == [40, 41]
        @test all(tree["status"] == "complete" for tree in manifest["trees"])

        tree1 = joinpath(experiment_dir, "oos_tree1")
        tree2 = joinpath(experiment_dir, "oos_tree2")
        tree1_metadata_before = OpenEMPIRE._oos_sha256_file(joinpath(tree1, "metadata.yaml"))
        tree1_before = _oos_tree_scenario_snapshot(tree1)
        tree2_before = _oos_tree_scenario_snapshot(tree2)
        @test tree1_before != tree2_before

        saved_tree2 = joinpath(root, "saved_oos_tree2")
        mv(tree2, saved_tree2)
        resumed = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            num_trees = 2,
            seed_start = 40,
            input_format = :csv,
        )
        @test resumed == prepared
        @test _oos_tree_scenario_snapshot(tree1) == tree1_before
        @test OpenEMPIRE._oos_sha256_file(joinpath(tree1, "metadata.yaml")) ==
              tree1_metadata_before
        @test _oos_tree_scenario_snapshot(tree2) == tree2_before
        @test _oos_source_snapshot(source_data) == source_before

        @test_throws ArgumentError OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            num_trees = 3,
            seed_start = 40,
            input_format = :csv,
        )
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            num_trees = 2,
            seed_start = 40,
            input_format = :csv,
            resume = false,
        )

        scenario_file = joinpath(tree2, "ScenarioData", "sloadRaw.csv")
        write(scenario_file, read(scenario_file, String) * "\n")
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            experiment_dir;
            num_trees = 2,
            seed_start = 40,
            input_format = :csv,
        )
        failed_manifest = YAML.load_file(manifest_file)
        @test failed_manifest["status"] == "failed"
        @test failed_manifest["trees"][2]["status"] == "failed"

        fixed_config_file = joinpath(root, "fixed-sample.yaml")
        fixed_config = YAML.load_file(config_file)
        fixed_config["use_fixed_sample"] = true
        YAML.write_file(fixed_config_file, fixed_config)
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_experiment(
            fixed_config_file,
            source_data,
            joinpath(root, "fixed-sample-experiment");
            num_trees = 2,
            seed_start = 40,
            input_format = :csv,
        )
    end
end

function test_prepare_oos_execution_queue()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        experiment_dir = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            joinpath(root, "experiment");
            num_trees = 2,
            seed_start = 90,
            input_format = :csv,
        )
        fixed_investment_dir = joinpath(root, "investment_run")
        _write_investment_csvs(joinpath(fixed_investment_dir, "Output"))
        results_root = joinpath(root, "results")

        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root,
            input_format = :csv,
            solver = "HiGHS",
        )

        @test queue_file == joinpath(experiment_dir, "execution.yaml")
        @test !ispath(results_root)
        queue = YAML.load_file(queue_file)
        @test queue["schema_version"] == 1
        @test queue["kind"] == "oos_execution_queue"
        @test queue["status"] == "ready"
        @test queue["experiment"]["num_trees"] == 2
        @test queue["dataset"]["sha256"] ==
              OpenEMPIRE._oos_directory_sha256(source_data)
        @test queue["fixed_investments"]["output_dir"] ==
              joinpath(fixed_investment_dir, "Output")
        @test length(queue["fixed_investments"]["files"]) == 8
        @test [job["seed"] for job in queue["jobs"]] == [90, 91]
        @test all(job["status"] == "pending" for job in queue["jobs"])

        first_job = queue["jobs"][1]
        @test first_job["scenario_tree"] == joinpath(experiment_dir, "oos_tree1")
        @test "--out-of-sample=true" in first_job["command"]
        @test "--fixed-investment-dir=$fixed_investment_dir" in first_job["command"]
        @test "--scenario-data-root=$(joinpath(experiment_dir, "oos_tree1"))" in
              first_job["command"]
        @test "--results=$(joinpath(results_root, "oos_tree1"))" in first_job["command"]
        @test !occursin("--result-dir=", first_job["command_display"])

        first_job["status"] = "submitted"
        first_job["scheduler_job_id"] = "12345"
        first_job["submitted_at_utc"] = "2026-07-20T12:00:00Z"
        YAML.write_file(queue_file, queue)
        resumed_file = OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root,
            input_format = :csv,
            solver = "HiGHS",
        )
        resumed = YAML.load_file(resumed_file)
        @test resumed["status"] == "submitted"
        @test resumed["jobs"][1]["status"] == "submitted"
        @test resumed["jobs"][1]["scheduler_job_id"] == "12345"
        @test resumed["jobs"][2]["status"] == "pending"

        @test_throws ArgumentError OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root,
            input_format = :csv,
            solver = "Gurobi",
        )
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root,
            input_format = :csv,
            solver = "HiGHS",
            resume = false,
        )

        incompatible_config_file = joinpath(root, "incompatible.yaml")
        incompatible_config = YAML.load_file(config_file)
        incompatible_config["number_of_scenarios"] += 1
        YAML.write_file(incompatible_config_file, incompatible_config)
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file = incompatible_config_file,
            results_root = joinpath(root, "incompatible-results"),
            input_format = :csv,
            solver = "HiGHS",
            queue_file = joinpath(root, "incompatible-execution.yaml"),
        )
    end
end

function _write_investment_csvs(
    output_dir;
    include_installed = true,
    extra_generator = false,
)
    generator_rows = extra_generator ?
                     "A,Solar,1,3.5\nB,Solar,1,1.0\n" :
                     "A,Solar,1,3.5\n"
    _write_oos_csv(
        joinpath(output_dir, "genInvCap.csv"),
        "Node,Generator,Period,genInvCap\n$generator_rows",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmisionInvCap.csv"),
        "FromNode,ToNode,Period,transmisionInvCap\nA,B,1,4.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInvCap.csv"),
        "Node,Storage,Period,storPWInvCap\nA,battery,1,5.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInvCap.csv"),
        "Node,Storage,Period,storENInvCap\nA,battery,1,6.5\n",
    )

    include_installed || return output_dir

    _write_oos_csv(
        joinpath(output_dir, "genInstalledCap.csv"),
        "Node,Generator,Period,genInstalledCap\nA,Solar,1,7.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmissionInstalledCap.csv"),
        "FromNode,ToNode,Period,transmissionInstalledCap\nA,B,1,8.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInstalledCap.csv"),
        "Node,Storage,Period,storPWInstalledCap\nA,battery,1,9.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInstalledCap.csv"),
        "Node,Storage,Period,storENInstalledCap\nA,battery,1,10.5\n",
    )
    return output_dir
end

function _write_test_investment_run_evidence(run_dir, config_file)
    input_dir = joinpath(run_dir, "Input")
    mkpath(input_dir)
    cp(config_file, joinpath(input_dir, "config.yaml"); force = true)
    write(
        joinpath(run_dir, "summary.txt"),
        "OpenEMPIRE.jl run summary\noptimize=true\ntermination_status=OPTIMAL\n",
    )
    return run_dir
end

function test_fixed_investment_provenance_and_compatibility()
    mktempdir() do root
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        config = YAML.load_file(config_file)
        legacy_run = joinpath(root, "legacy")
        _write_investment_csvs(joinpath(legacy_run, "Output"))
        _write_test_investment_run_evidence(legacy_run, config_file)

        legacy = OpenEMPIRE._oos_fixed_investment_metadata(legacy_run)
        @test legacy["provenance"]["kind"] == "reconstructed_legacy_run"
        @test legacy["provenance"]["summary_sha256"] ==
              OpenEMPIRE._oos_sha256_file(joinpath(legacy_run, "summary.txt"))
        @test OpenEMPIRE.validate_oos_fixed_investment_compatibility(
            legacy,
            config,
        )["status"] == "compatible"

        operationally_different = copy(config)
        operationally_different["number_of_scenarios"] += 1
        operationally_different["length_of_regular_season"] = 8760
        @test OpenEMPIRE.validate_oos_fixed_investment_compatibility(
            legacy,
            operationally_different,
        )["status"] == "compatible"

        structurally_different = copy(config)
        structurally_different["north_sea"] =
            !get(structurally_different, "north_sea", false)
        @test_throws ArgumentError OpenEMPIRE.validate_oos_fixed_investment_compatibility(
            legacy,
            structurally_different,
        )

        staged = joinpath(root, "staged")
        mkpath(staged)
        for source in OpenEMPIRE._oos_fixed_investment_source_files(legacy_run)
            cp(source, joinpath(staged, basename(source)))
        end
        staged_metadata = OpenEMPIRE.stage_oos_fixed_investment_provenance(
            legacy_run,
            staged,
        )
        @test staged_metadata["sha256"] == legacy["sha256"]
        @test staged_metadata["provenance"]["kind"] ==
              "reconstructed_legacy_run"
        @test isfile(joinpath(staged, "source_config.yaml"))
        @test isfile(joinpath(staged, "fixed_investment_provenance.yaml"))

        verified_run = joinpath(root, "verified")
        _write_investment_csvs(joinpath(verified_run, "output"))
        verified_input = joinpath(verified_run, "Input")
        mkpath(verified_input)
        cp(config_file, joinpath(verified_input, "config.yaml"))
        capacity = OpenEMPIRE._oos_fixed_capacity_metadata(verified_run)
        YAML.write_file(
            joinpath(verified_run, "run_manifest.yaml"),
            Dict{String, Any}(
                "status" => "complete",
                "config_sha256" => OpenEMPIRE._oos_sha256_file(
                    joinpath(verified_input, "config.yaml"),
                ),
                "out_of_sample" => Dict("enabled" => false),
                "solution" => Dict(
                    "termination_status" => "OPTIMAL",
                    "is_solved_and_feasible" => true,
                ),
                "investment_context" =>
                    OpenEMPIRE._oos_structural_config(config),
                "investment_result" => Dict(
                    "fixed_investments_sha256" => capacity["sha256"],
                ),
            ),
        )
        verified = OpenEMPIRE._oos_fixed_investment_metadata(verified_run)
        @test verified["provenance"]["kind"] == "verified_run_manifest"

        unsupported = joinpath(root, "unsupported")
        _write_investment_csvs(joinpath(unsupported, "output"))
        mkpath(joinpath(unsupported, "Input"))
        cp(config_file, joinpath(unsupported, "Input", "config.yaml"))
        @test_throws ArgumentError OpenEMPIRE._oos_fixed_investment_metadata(
            unsupported,
        )
    end

    return nothing
end

function test_fix_only_investment_capacities()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
        )
        OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    @test JuMP.is_fixed(model[:genInvCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(model[:genInstalledCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(
        model[:transmissionInstalledCap]["A", "B", strategic_period],
    )
    @test !JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", strategic_period])
    @test !JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", strategic_period])
end

function test_fixed_investment_key_validation()
    sets, periods = _oos_test_sets_and_periods()

    mktempdir() do result_dir
        _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
            extra_generator = true,
        )
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    mktempdir() do result_dir
        output_dir = _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
        )
        write(
            joinpath(output_dir, "genInvCap.csv"),
            "Node,Generator,Period,genInvCap\n",
        )
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end
end

function test_oos_omits_investment_only_constraints()
    sets, periods = _oos_test_sets_and_periods()
    params = OpenEMPIRE.EmpireParams(genCapAvailType = Dict("Solar" => 1.0))

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "output"))

        investment_model = JuMP.Model(HiGHS.Optimizer)
        JuMP.set_silent(investment_model)
        OpenEMPIRE.create_variables(investment_model, sets, periods)
        OpenEMPIRE.create_constraints(investment_model, sets, params, periods)
        OpenEMPIRE.fix_investments_from_results!(
            investment_model,
            sets,
            periods,
            result_dir,
        )
        @objective(investment_model, Min, 0)
        optimize!(investment_model)
        @test JuMP.termination_status(investment_model) == JuMP.MOI.INFEASIBLE

        oos_model = JuMP.Model(HiGHS.Optimizer)
        JuMP.set_silent(oos_model)
        OpenEMPIRE.create_variables(oos_model, sets, periods)
        OpenEMPIRE.create_constraints(
            oos_model,
            sets,
            params,
            periods;
            include_investment_constraints = false,
        )
        OpenEMPIRE.fix_investments_from_results!(oos_model, sets, periods, result_dir)
        @objective(oos_model, Min, 0)
        optimize!(oos_model)

        @test JuMP.is_solved_and_feasible(oos_model)
        object_names = JuMP.object_dictionary(oos_model)
        for operational_family in (
            :flow_balance,
            :gen_max_prod,
            :storage_bal,
            :trans_cap,
        )
            @test haskey(object_names, operational_family)
        end
        for investment_family in (
            :installed_cap_gen,
            :max_inv_tech,
            :max_inst_tech,
            :storage_installed_cap_en,
            :storage_installed_cap_pow,
            :storage_max_inv_pow,
            :storage_max_inv_en,
            :storage_max_inst_pow,
            :storage_max_inst_en,
            :storage_couple_pow_en,
            :trans_track_cap,
            :trans_max_capacity,
            :trans_installed_cap,
        )
            @test !haskey(object_names, investment_family)
        end
    end
end
