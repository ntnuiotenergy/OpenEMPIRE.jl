function test_prepare_oos_solstorm_staging()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        experiment_dir = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            joinpath(root, "experiment");
            num_trees = 2,
            seed_start = 210,
            input_format = :csv,
        )
        execution_config = joinpath(root, "execution_config.yaml")
        write(execution_config, read(config_file, String) * "\n# execution-only copy\n")
        fixed_investment_dir = joinpath(root, "investment_run")
        _write_investment_csvs(joinpath(fixed_investment_dir, "Output"))
        results_root = joinpath(root, "results")
        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file = execution_config,
            results_root,
            input_format = :csv,
            solver = "HiGHS",
        )

        staging_dir = joinpath(root, "staging")
        plan_file = OpenEMPIRE.prepare_oos_solstorm_staging(
            queue_file;
            remote_user = "intern.user",
            remote_host = "solstorm.iot.ntnu.no",
            remote_root = "/cluster/users/intern/oos",
            job_index = 2,
            output_dir = staging_dir,
        )
        @test plan_file == joinpath(staging_dir, "staging.yaml")
        @test isfile(plan_file)

        plan = YAML.load_file(plan_file)
        @test plan["schema_version"] == 1
        @test plan["kind"] == "oos_solstorm_staging_plan"
        @test plan["dry_run"]
        @test plan["commands_executed"] == 0
        expected_status = isempty(plan["source"]["repository"]["dirty_code_entries"]) ?
                          "ready" : "blocked"
        @test plan["status"] == expected_status
        @test plan["source"]["selected_job"]["index"] == 2
        @test plan["source"]["selected_job"]["tree"] == "oos_tree2"
        @test plan["source"]["selected_job"]["seed"] == 211
        @test length(plan["source"]["fixed_investments"]["files"]) == 8
        @test length(plan["source"]["repository"]["commit"]) == 40
        @test plan["source"]["repository"]["commit"] ==
              plan["source"]["repository"]["head_commit"]
        @test length(plan["source"]["repository"]["git_tree"]) == 40
        @test plan["remote"]["tree"] == joinpath(
            plan["remote"]["experiment"],
            "oos_tree1",
        )
        @test startswith(
            plan["remote"]["stage_root"],
            "/cluster/users/intern/oos/stages/",
        )
        @test plan["acceptance_criteria"]["one_tree_only"]
        @test !plan["acceptance_criteria"]["scheduler_submission_allowed"]

        remote_experiment_file =
            plan["generated_files"]["remote_experiment_manifest"]["path"]
        remote_experiment = YAML.load_file(remote_experiment_file)
        @test remote_experiment["status"] == "complete"
        @test remote_experiment["num_trees"] == 1
        @test remote_experiment["seed_start"] == 211
        @test remote_experiment["trees"][1]["index"] == 1
        @test remote_experiment["trees"][1]["name"] == "oos_tree1"

        remote_metadata_file = plan["generated_files"]["remote_tree_metadata"]["path"]
        remote_metadata = YAML.load_file(remote_metadata_file)
        @test remote_metadata["tree"] == "oos_tree1"
        @test remote_metadata["staged_from_tree"] == "oos_tree2"
        @test remote_metadata["tree_dir"] == plan["remote"]["tree"]
        @test remote_metadata["source_data_sha256"] ==
              plan["source"]["dataset"]["sha256"]
        @test plan["source"]["generation_config"]["sha256"] !=
              plan["source"]["config"]["sha256"]
        @test plan["remote"]["generation_config"] != plan["remote"]["config"]
        @test remote_metadata["source_config_file"] ==
              plan["remote"]["generation_config"]

        mock_remote_tree = joinpath(root, "mock_remote_tree")
        mkpath(mock_remote_tree)
        cp(
            joinpath(experiment_dir, "oos_tree2", "ScenarioData"),
            joinpath(mock_remote_tree, "ScenarioData"),
        )
        cp(remote_metadata_file, joinpath(mock_remote_tree, "metadata.yaml"))
        @test OpenEMPIRE._oos_directory_sha256(mock_remote_tree) ==
              plan["remote"]["tree_sha256"]

        commands = plan["commands"]
        command_text = join((command["display"] for command in commands), "\n")
        @test all(!command["executed"] for command in commands)
        @test any(occursin("git", command["display"]) &&
                  occursin("archive", command["display"]) for command in commands)
        @test any(occursin("scp", command["display"]) for command in commands)
        @test any(occursin(plan["remote"]["generation_config"], command["display"])
                  for command in commands)
        for entry in plan["source"]["fixed_investments"]["files"]
            @test occursin(entry["path"], command_text)
        end
        for filename in OpenEMPIRE._OOS_TREE_FILENAMES
            @test occursin(filename, command_text)
        end
        @test any(occursin("_oos_code_sha256", command["display"]) for command in commands)
        @test any(occursin("prepare_oos_execution_queue.jl", command["display"]) for
                  command in commands)
        @test any(occursin("prepare_oos_sge_job.jl", command["display"]) for
                  command in commands)
        @test all(!occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"])
                  for command in commands)
        @test !isfile(plan["generated_files"]["repository_archive"]["path"])
        @test !isfile(plan["generated_files"]["dataset_archive"]["path"])
        @test !ispath(results_root)

        old_revision_plan_file = OpenEMPIRE.prepare_oos_solstorm_staging(
            queue_file;
            remote_user = "intern",
            remote_root = "/cluster/users/intern/oos",
            output_dir = joinpath(root, "old-revision"),
            revision = "HEAD~1",
        )
        old_revision_plan = YAML.load_file(old_revision_plan_file)
        @test old_revision_plan["status"] == "blocked"
        @test any(occursin("differs from HEAD", blocker) for
                  blocker in old_revision_plan["blockers"])

        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_staging(
            queue_file;
            remote_user = "invalid user",
            remote_root = "/cluster/users/intern/oos",
            output_dir = joinpath(root, "invalid-user"),
        )
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_staging(
            queue_file;
            remote_user = "intern",
            remote_root = "relative/path",
            output_dir = joinpath(root, "invalid-root"),
        )
    end
end
