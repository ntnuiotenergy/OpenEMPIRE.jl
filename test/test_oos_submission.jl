function test_prepare_oos_solstorm_submission()
    mktempdir() do root
        stage_root = "/cluster/users/intern/oos/stages/test"
        project_dir = joinpath(stage_root, "project")
        queue_file = joinpath(stage_root, "inputs", "experiment", "execution.yaml")
        script_file = joinpath(stage_root, "inputs", "experiment", "sge", "tree.sge.sh")
        setup_file = joinpath(root, "setup.yaml")
        setup = Dict{String, Any}(
            "kind" => "oos_solstorm_remote_setup_plan",
            "remote" => Dict(
                "user" => "intern",
                "host" => "solstorm.iot.ntnu.no",
                "stage_root" => stage_root,
                "project_dir" => project_dir,
                "execution_queue" => queue_file,
                "sge_script" => script_file,
            ),
        )
        OpenEMPIRE._write_oos_experiment_manifest(setup_file, setup)

        command_results = Dict{String, Any}[]
        for index in 14:15
            stdout_file = joinpath(root, "command$index.stdout")
            stderr_file = joinpath(root, "command$index.stderr")
            write(stdout_file, "command $index passed\n")
            write(stderr_file, "")
            push!(command_results, Dict{String, Any}(
                "original_command_index" => index,
                "success" => true,
                "exit_code" => 0,
                "stdout" => stdout_file,
                "stdout_sha256" => OpenEMPIRE._oos_sha256_file(stdout_file),
                "stderr" => stderr_file,
                "stderr_sha256" => OpenEMPIRE._oos_sha256_file(stderr_file),
                "stderr_bytes" => 0,
            ))
        end
        execution_file = joinpath(root, "setup_execution.yaml")
        setup_execution = Dict{String, Any}(
            "kind" => "oos_solstorm_remote_setup_execution",
            "plan" => setup_file,
            "plan_sha256" => OpenEMPIRE._oos_sha256_file(setup_file),
            "success" => true,
            "commands_attempted" => [14, 15],
            "commands" => command_results,
            "qsub_executed" => false,
            "runner_executed" => false,
            "solver_started" => false,
        )
        OpenEMPIRE._write_oos_experiment_manifest(execution_file, setup_execution)

        queue_sha256 = repeat("a", 64)
        script_sha256 = repeat("b", 64)
        inspection_stdout = joinpath(root, "inspection.stdout")
        inspection_lines = [
            "QUEUE_SHA256\t$queue_sha256",
            "SCRIPT_SHA256\t$script_sha256",
            "QUEUE_STATUS\tready",
            "JOB\t1\toos_tree1\t101\tpending",
            "SOLVER\tGurobi",
            "HOSTS\tcompute-4-51|compute-4-52",
            "SCHEDULER\tprepared\tNO_JOB_ID",
            "INPUTS_VALIDATED\tdataset,config,tree,fixed_investments,runner_code",
            "QSUB_EXECUTED\tfalse",
        ]
        write(inspection_stdout, join(inspection_lines, "\n") * "\n")
        inspection_stderr = joinpath(root, "inspection.stderr")
        write(inspection_stderr, "")
        inspection_file = joinpath(root, "inspection.yaml")
        inspection = Dict{String, Any}(
            "kind" => "oos_solstorm_remote_setup_artifact_inspection",
            "success" => true,
            "exit_code" => 0,
            "read_only" => true,
            "queue_file" => queue_file,
            "sge_script" => script_file,
            "stdout" => inspection_stdout,
            "stdout_sha256" => OpenEMPIRE._oos_sha256_file(inspection_stdout),
            "stderr" => inspection_stderr,
            "stderr_sha256" => OpenEMPIRE._oos_sha256_file(inspection_stderr),
            "qsub_executed" => false,
            "runner_executed" => false,
            "solver_started" => false,
        )
        OpenEMPIRE._write_oos_experiment_manifest(inspection_file, inspection)

        submission_file = OpenEMPIRE.prepare_oos_solstorm_submission(
            setup_file,
            execution_file,
            inspection_file,
        )
        submission = YAML.load_file(submission_file)
        @test submission["kind"] == "oos_solstorm_submission_plan"
        @test submission["status"] == "ready"
        @test submission["dry_run"]
        @test submission["commands_executed"] == 0
        @test submission["requires_explicit_remote_approval"]
        @test submission["source"]["queue_sha256"] == queue_sha256
        @test submission["source"]["sge_script_sha256"] == script_sha256
        @test submission["remote"]["queue_file"] == queue_file
        @test submission["remote"]["sge_script"] == script_file
        @test endswith(submission["remote"]["qsub_stdout"], "attempt1.stdout")
        @test endswith(submission["remote"]["qsub_stderr"], "attempt1.stderr")
        @test submission["safety"]["expected_qsub_invocations"] == 1
        @test submission["safety"]["remote_evidence_noclobber"]
        @test submission["safety"]["requires_pending_job_without_id"]
        @test !submission["safety"]["starts_runner_directly"]
        @test !submission["safety"]["starts_solver_directly"]
        @test length(submission["commands"]) == 1
        command = only(submission["commands"])
        @test command["argv"][1:4] == [
            "ssh",
            "-o",
            "BatchMode=yes",
            "intern@solstorm.iot.ntnu.no",
        ]
        remote_shell = command["argv"][5]
        @test length(collect(eachmatch(
            r"(^|[[:space:]])qsub([[:space:]]|$)",
            remote_shell,
        ))) == 1
        @test occursin("set -o noclobber", remote_shell)
        @test occursin(queue_sha256, remote_shell)
        @test occursin(script_sha256, remote_shell)
        @test occursin("OOS job is no longer pending", remote_shell)
        @test !occursin("run_julia_empire", remote_shell)
        @test !occursin("Gurobi.Optimizer", remote_shell)

        write(inspection_stdout, read(inspection_stdout, String) * "EXTRA\tunsafe\n")
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_submission(
            setup_file,
            execution_file,
            inspection_file;
            output_file = joinpath(root, "unsafe_submission.yaml"),
        )
    end
end
