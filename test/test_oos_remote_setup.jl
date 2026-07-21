function test_prepare_oos_solstorm_remote_setup()
    mktempdir() do root
        stage_root = "/cluster/users/intern/oos/stages/test"
        project_dir = joinpath(stage_root, "project")
        account = "intern@solstorm.iot.ntnu.no"
        commands = [
            OpenEMPIRE._oos_staging_command(
                "placeholder",
                "Synthetic command $index",
                ["true"],
            ) for index in 1:15
        ]
        commands[14] = OpenEMPIRE._oos_staging_command(
            "remote_configure",
            "Prepare the one-tree execution queue on the Solstorm filesystem",
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                account,
                "cd $project_dir\njulia --project=. " *
                "$project_dir/scripts/prepare_oos_execution_queue.jl",
            ],
        )
        commands[15] = OpenEMPIRE._oos_staging_command(
            "remote_configure",
            "Prepare the SGE script without submitting it",
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                account,
                "cd $project_dir\njulia --project=. " *
                "$project_dir/scripts/prepare_oos_sge_job.jl",
            ],
        )
        dataset_sha256 = repeat("d", 64)
        staging_file = joinpath(root, "staging.yaml")
        staging = Dict{String, Any}(
            "kind" => "oos_solstorm_staging_plan",
            "source" => Dict("dataset" => Dict("sha256" => dataset_sha256)),
            "remote" => Dict(
                "user" => "intern",
                "host" => "solstorm.iot.ntnu.no",
                "stage_root" => stage_root,
                "project_dir" => project_dir,
            ),
            "commands" => commands,
        )
        OpenEMPIRE._write_oos_experiment_manifest(staging_file, staging)

        upstream = Dict{String, String}()
        for key in (
            "remote_preflight",
            "quarantine_plan",
            "quarantine_execution",
            "quarantine_stdout",
            "quarantine_stderr",
        )
            path = joinpath(root, "$key.evidence")
            write(path, "$key\n")
            upstream[key] = path
        end
        validation_file = joinpath(root, "recovered_validation.yaml")
        validation_source = Dict{String, Any}(
            "staging_plan" => staging_file,
            "staging_plan_sha256" => OpenEMPIRE._oos_sha256_file(staging_file),
            "expected_dataset_sha256" => dataset_sha256,
        )
        for (key, path) in upstream
            validation_source[key] = path
            validation_source[key * "_sha256"] = OpenEMPIRE._oos_sha256_file(path)
        end
        validation = Dict{String, Any}(
            "kind" => "oos_solstorm_recovered_validation_plan",
            "source" => validation_source,
        )
        OpenEMPIRE._write_oos_experiment_manifest(validation_file, validation)

        validation_stdout = joinpath(root, "validation.stdout.log")
        validation_stderr = joinpath(root, "validation.stderr.log")
        write(validation_stdout, "")
        write(validation_stderr, "")
        execution_file = joinpath(root, "validation_execution.yaml")
        execution = Dict{String, Any}(
            "kind" => "oos_solstorm_recovered_validation_execution",
            "plan" => validation_file,
            "plan_sha256" => OpenEMPIRE._oos_sha256_file(validation_file),
            "success" => true,
            "exit_code" => 0,
            "original_command_index" => 13,
            "validations" => [
                "repository_code",
                "dataset",
                "execution_config",
                "generation_config",
                "oos_tree",
                "fixed_investments",
            ],
            "stdout" => validation_stdout,
            "stdout_sha256" => OpenEMPIRE._oos_sha256_file(validation_stdout),
            "stderr" => validation_stderr,
            "stderr_sha256" => OpenEMPIRE._oos_sha256_file(validation_stderr),
            "queue_prepared" => false,
            "sge_script_prepared" => false,
            "qsub_executed" => false,
            "runner_executed" => false,
            "solver_started" => false,
        )
        OpenEMPIRE._write_oos_experiment_manifest(execution_file, execution)

        setup_file = OpenEMPIRE.prepare_oos_solstorm_remote_setup(
            staging_file,
            validation_file,
            execution_file,
        )
        setup = YAML.load_file(setup_file)
        @test setup["kind"] == "oos_solstorm_remote_setup_plan"
        @test setup["status"] == "ready"
        @test setup["dry_run"]
        @test setup["commands_executed"] == 0
        @test setup["requires_explicit_remote_approval"]
        @test setup["source"]["expected_dataset_sha256"] == dataset_sha256
        @test length(setup["source"]["validated_inputs"]) == 6
        @test setup["remote"]["stage_root"] == stage_root
        @test setup["safety"]["starts_at_original_command"] == 14
        @test setup["safety"]["ends_at_original_command"] == 15
        @test setup["safety"]["prepares_execution_queue"]
        @test setup["safety"]["prepares_sge_script"]
        @test !setup["safety"]["submits_scheduler_job"]
        @test !setup["safety"]["starts_runner"]
        @test !setup["safety"]["starts_solver"]
        @test length(setup["commands"]) == 2
        @test [command["original_command_index"] for command in setup["commands"]] ==
              [14, 15]
        @test all(command["argv"][1:4] == ["ssh", "-o", "BatchMode=yes", account]
                  for command in setup["commands"])
        @test all(occursin("OpenEMPIRE Solstorm Julia bootstrap", command["display"])
                  for command in setup["commands"])
        @test all(occursin(
                      "OpenEMPIRE Solstorm project dependency bootstrap",
                      command["display"],
                  ) for command in setup["commands"])
        @test occursin("prepare_oos_execution_queue.jl", setup["commands"][1]["display"])
        @test occursin("prepare_oos_sge_job.jl", setup["commands"][2]["display"])
        @test all(!occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"])
                  for command in setup["commands"])
        @test all(!occursin("run_julia_empire", command["display"])
                  for command in setup["commands"])

        write(validation_stdout, "unexpected\n")
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_remote_setup(
            staging_file,
            validation_file,
            execution_file;
            output_file = joinpath(root, "unsafe_setup.yaml"),
        )
    end
end
