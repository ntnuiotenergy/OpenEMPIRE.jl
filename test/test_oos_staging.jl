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
        @test OpenEMPIRE._oos_dataset_archive_arguments(
            "/source",
            "/archive.tar.gz";
            is_apple = true,
        ) == [
            "env",
            "COPYFILE_DISABLE=1",
            "tar",
            "--no-xattrs",
            "--no-mac-metadata",
            "--no-fflags",
            "-czf",
            "/archive.tar.gz",
            "-C",
            "/source",
            ".",
        ]
        @test OpenEMPIRE._oos_dataset_archive_arguments(
            "/source",
            "/archive.tar.gz";
            is_apple = false,
        ) == ["tar", "-czf", "/archive.tar.gz", "-C", "/source", "."]
        dataset_archive_command = commands[2]["argv"]
        if Sys.isapple()
            @test dataset_archive_command[1:6] == [
                "env",
                "COPYFILE_DISABLE=1",
                "tar",
                "--no-xattrs",
                "--no-mac-metadata",
                "--no-fflags",
            ]
        else
            @test dataset_archive_command[1] == "tar"
        end
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
        remote_julia_commands = commands[13:15]
        @test [command["phase"] for command in remote_julia_commands] == [
            "remote_validate",
            "remote_configure",
            "remote_configure",
        ]
        @test all(occursin("OpenEMPIRE Solstorm Julia bootstrap", command["display"])
                  for command in remote_julia_commands)
        @test all(occursin("source /etc/profile", command["display"])
                  for command in remote_julia_commands)
        @test all(occursin("module load Julia/1.9.3", command["display"])
                  for command in remote_julia_commands)
        @test all(occursin("command -v julia", command["display"])
                  for command in remote_julia_commands)
        @test all(occursin(
                      "OpenEMPIRE Solstorm project dependency bootstrap",
                      command["display"],
                  ) for command in remote_julia_commands)
        @test all(occursin("Pkg.instantiate()", command["display"])
                  for command in remote_julia_commands)
        @test all(occursin("Pkg.precompile()", command["display"])
                  for command in remote_julia_commands)
        @test all(!occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"])
                  for command in commands)
        @test !isfile(plan["generated_files"]["repository_archive"]["path"])
        @test !isfile(plan["generated_files"]["dataset_archive"]["path"])
        @test !ispath(results_root)

        legacy_plan = deepcopy(plan)
        for index in 13:15
            remote_shell = legacy_plan["commands"][index]["argv"][5]
            command_start = findfirst("\ncd ", remote_shell)
            @test command_start !== nothing
            legacy_plan["commands"][index]["argv"][5] =
                remote_shell[(first(command_start) + 1):end]
        end
        legacy_plan_file = joinpath(staging_dir, "staging.without-bootstrap.yaml")
        OpenEMPIRE._write_oos_experiment_manifest(legacy_plan_file, legacy_plan)
        preflight = Dict{String, Any}(
            "schema_version" => 1,
            "kind" => "oos_remote_staging_preflight",
            "status" => "blocked",
            "staging_plan" => legacy_plan_file,
            "remote" => Dict(
                "stage_root" => legacy_plan["remote"]["stage_root"],
            ),
            "commands" => Dict(
                "completed" => collect(3:12),
                "attempted_and_failed" => [13],
                "not_attempted" => [14, 15],
            ),
            "transfer" => Dict(
                "archive_hashes_match" => true,
                "archives_extracted" => true,
            ),
            "failure" => Dict(
                "command_index" => 13,
                "content_checksum_verification_started" => false,
            ),
            "safety" => Dict(
                "qsub_executed" => false,
                "solver_started" => false,
            ),
        )
        preflight_file = joinpath(staging_dir, "remote_preflight.yaml")
        OpenEMPIRE._write_oos_experiment_manifest(preflight_file, preflight)
        resume_file = OpenEMPIRE.prepare_oos_solstorm_resume(
            legacy_plan_file,
            preflight_file,
        )
        resume = YAML.load_file(resume_file)
        @test resume["kind"] == "oos_solstorm_resume_plan"
        @test resume["status"] == "ready"
        @test resume["dry_run"]
        @test resume["commands_executed"] == 0
        @test resume["requires_explicit_remote_approval"]
        @test resume["source"]["failed_command_index"] == 13
        @test resume["source"]["failed_attempt"] == 1
        @test resume["remote"]["stage_root"] == plan["remote"]["stage_root"]
        @test resume["safety"] == Dict(
            "starts_at_original_command" => 13,
            "ends_at_original_command" => 13,
            "retries_only_failed_command" => true,
            "recreates_remote_stage" => false,
            "retransfers_files" => false,
            "submits_scheduler_job" => false,
            "starts_solver" => false,
        )
        @test [command["original_command_index"] for command in resume["commands"]] ==
              [13]
        @test all(command["argv"][1:4] == [
                      "ssh",
                      "-o",
                      "BatchMode=yes",
                      "intern.user@solstorm.iot.ntnu.no",
                  ] for command in resume["commands"])
        @test all(occursin("OpenEMPIRE Solstorm Julia bootstrap", command["display"])
                  for command in resume["commands"])
        @test all(occursin("module load Julia/1.9.3", command["display"])
                  for command in resume["commands"])
        @test all(occursin(
                      "OpenEMPIRE Solstorm project dependency bootstrap",
                      command["display"],
                  ) for command in resume["commands"])
        @test all(occursin("Pkg.instantiate()", command["display"])
                  for command in resume["commands"])
        @test all(occursin("Pkg.precompile()", command["display"])
                  for command in resume["commands"])
        @test all(occursin("_oos_code_sha256", command["display"])
                  for command in resume["commands"])
        @test all(!occursin("prepare_oos_execution_queue.jl", command["display"])
                  for command in resume["commands"])
        @test all(!occursin("prepare_oos_sge_job.jl", command["display"])
                  for command in resume["commands"])
        @test all(!occursin("scp ", command["display"]) for command in resume["commands"])
        @test all(!occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"])
                  for command in resume["commands"])
        @test !ispath(results_root)

        mismatched_preflight = deepcopy(preflight)
        mismatched_preflight["remote"]["stage_root"] = "/different/stage"
        mismatched_preflight_file = joinpath(staging_dir, "mismatched_preflight.yaml")
        OpenEMPIRE._write_oos_experiment_manifest(
            mismatched_preflight_file,
            mismatched_preflight,
        )
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_resume(
            legacy_plan_file,
            mismatched_preflight_file;
            output_file = joinpath(staging_dir, "unsafe-resume.yaml"),
        )

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
