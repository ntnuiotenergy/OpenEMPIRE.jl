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

function _write_oos_csv(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
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
        @test queue["runner"]["code_sha256"] ==
              OpenEMPIRE._oos_code_sha256(pkgdir(OpenEMPIRE))
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

function _write_test_oos_run_manifest(queue, job; status, termination = nothing)
    result_dir = joinpath(job["result_root"], "20260720_120000_test")
    mkpath(result_dir)
    summary_path = joinpath(result_dir, "summary.txt")
    if status == "complete"
        write(summary_path, "termination_status=$termination\n")
    end
    tree_metadata = YAML.load_file(joinpath(job["scenario_tree"], "metadata.yaml"))
    YAML.write_file(
        joinpath(result_dir, "run_manifest.yaml"),
        Dict{String, Any}(
            "status" => status,
            "start_time" => "2026-07-20T12:00:00",
            "original_data_folder" => queue["dataset"]["folder"],
            "original_config_sha256" => queue["config"]["sha256"],
            "result_dir" => result_dir,
            "summary_path" => status == "complete" ? summary_path : nothing,
            "out_of_sample" => Dict{String, Any}(
                "enabled" => true,
                "scenario_tree" => job["tree"],
                "scenario_seed" => job["seed"],
                "scenario_checksums_verified" => status == "complete",
                "scenario_metadata" => tree_metadata,
                "base_investment_run" => queue["fixed_investments"]["run_dir"],
                "investments_fixed" => status == "complete",
            ),
            "solution" => status == "complete" ?
                          Dict{String, Any}("termination_status" => termination) :
                          nothing,
        ),
    )
    return result_dir
end

function test_manage_oos_execution_queue()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        experiment_dir = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            joinpath(root, "experiment");
            num_trees = 2,
            seed_start = 120,
            input_format = :csv,
        )
        fixed_investment_dir = joinpath(root, "investment_run")
        _write_investment_csvs(joinpath(fixed_investment_dir, "Output"))
        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root = joinpath(root, "results"),
            input_format = :csv,
            solver = "HiGHS",
        )

        @test OpenEMPIRE.next_pending_oos_job(queue_file)["index"] == 1
        submitted = OpenEMPIRE.update_oos_execution_job!(
            queue_file,
            1,
            "submitted";
            scheduler_job_id = "98765",
            stdout_path = joinpath(root, "logs", "tree1.out"),
            stderr_path = joinpath(root, "logs", "tree1.err"),
        )
        @test submitted["status"] == "submitted"
        @test submitted["scheduler_job_id"] == "98765"
        @test submitted["history"][1]["from"] == "pending"
        @test submitted["history"][1]["to"] == "submitted"
        @test YAML.load_file(queue_file)["status"] == "submitted"
        @test_throws ArgumentError OpenEMPIRE.update_oos_execution_job!(
            queue_file,
            2,
            "submitted",
        )
        @test_throws ArgumentError OpenEMPIRE.update_oos_execution_job!(
            queue_file,
            1,
            "complete",
        )

        queue = YAML.load_file(queue_file)
        first_result = _write_test_oos_run_manifest(
            queue,
            queue["jobs"][1];
            status = "started",
        )
        reconciled = OpenEMPIRE.reconcile_oos_execution_queue!(queue_file)
        @test reconciled["jobs"][1]["status"] == "running"
        @test reconciled["jobs"][1]["result_dir"] == first_result
        @test reconciled["jobs"][1]["history"][2]["source"] == "reconcile"

        _write_test_oos_run_manifest(
            reconciled,
            reconciled["jobs"][1];
            status = "complete",
            termination = "OPTIMAL",
        )
        reconciled = OpenEMPIRE.reconcile_oos_execution_queue!(queue_file)
        @test reconciled["jobs"][1]["status"] == "complete"
        @test isnothing(reconciled["jobs"][1]["error"])
        @test OpenEMPIRE.next_pending_oos_job(queue_file)["index"] == 2

        second_result = _write_test_oos_run_manifest(
            reconciled,
            reconciled["jobs"][2];
            status = "complete",
            termination = "INFEASIBLE",
        )
        reconciled = OpenEMPIRE.reconcile_oos_execution_queue!(queue_file)
        @test reconciled["status"] == "attention_required"
        @test reconciled["jobs"][2]["status"] == "failed"
        @test reconciled["jobs"][2]["result_dir"] == second_result
        @test occursin("INFEASIBLE", reconciled["jobs"][2]["error"])

        retried = OpenEMPIRE.update_oos_execution_job!(queue_file, 2, "pending")
        @test retried["status"] == "pending"
        @test isnothing(retried["result_dir"])
        @test isnothing(retried["error"])
        @test length(retried["history"]) == 2
        @test OpenEMPIRE.next_pending_oos_job(queue_file)["index"] == 2
    end
end

function _write_investment_csvs(output_dir; include_installed = true, extra_generator = false)
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

function test_fix_investments_from_results()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "output"))
        @test OpenEMPIRE.fix_investments_from_results!(model, sets, periods, result_dir) === model
    end

    expected = (
        (:genInvCap, ("A", "Solar", strategic_period), 3.5),
        (:transmissionInvCap, ("A", "B", strategic_period), 4.5),
        (:storPWInvCap, ("A", "battery", strategic_period), 5.5),
        (:storENInvCap, ("A", "battery", strategic_period), 6.5),
        (:genInstalledCap, ("A", "Solar", strategic_period), 7.5),
        (:transmissionInstalledCap, ("A", "B", strategic_period), 8.5),
        (:storPWInstalledCap, ("A", "battery", strategic_period), 9.5),
        (:storENInstalledCap, ("A", "battery", strategic_period), 10.5),
    )
    for (name, index, value) in expected
        variable = model[name][index...]
        @test JuMP.is_fixed(variable)
        @test JuMP.fix_value(variable) == value
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
            :wind_farm_transmission_cap,
        )
            @test !haskey(object_names, investment_family)
        end
    end
end

function test_fix_only_investment_capacities()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "Output"); include_installed = false)
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
    @test !JuMP.is_fixed(model[:transmissionInstalledCap]["A", "B", strategic_period])
    @test !JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", strategic_period])
    @test !JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", strategic_period])
end

function test_fixed_investment_key_validation()
    sets, periods = _oos_test_sets_and_periods()

    mktempdir() do result_dir
        output_dir = joinpath(result_dir, "output")
        _write_investment_csvs(output_dir; include_installed = false, extra_generator = true)
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
        output_dir = joinpath(result_dir, "output")
        _write_investment_csvs(output_dir; include_installed = false)
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
