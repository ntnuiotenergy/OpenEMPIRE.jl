function _test_oos_manifest_entries(root)
    entries = Dict{String, Tuple{Int, String}}()
    for (directory, _, names) in walkdir(root)
        for name in names
            path = joinpath(directory, name)
            entries[relpath(path, root)] = (
                filesize(path),
                OpenEMPIRE._oos_sha256_file(path),
            )
        end
    end
    return entries
end

function _write_test_oos_manifest(path, entries; directory_sha256 = nothing)
    lines = [
        "$relative\t$(entries[relative][1])\t$(entries[relative][2])" for
        relative in sort!(collect(keys(entries)))
    ]
    directory_sha256 === nothing || push!(
        lines,
        "__DIRECTORY_SHA256__\t$directory_sha256",
    )
    write(path, join(lines, "\n") * "\n")
    return path
end

function _write_cleanup_fixture(stage_root)
    dataset = joinpath(stage_root, "inputs", "dataset")
    mkpath(joinpath(dataset, "nested"))
    write(joinpath(dataset, "input.csv"), "value\n1\n")
    write(joinpath(dataset, "nested", "other.csv"), "value\n2\n")
    intended = _test_oos_manifest_entries(dataset)
    write(joinpath(dataset, "._input.csv"), "sidecar-one")
    write(joinpath(dataset, "nested", "._other.csv"), "sidecar-two")
    actual = _test_oos_manifest_entries(dataset)
    sidecars = Dict(path => metadata for (path, metadata) in actual if
                    !haskey(intended, path))
    return dataset, intended, sidecars
end

function test_oos_sidecar_quarantine_command()
    mktempdir() do root
        stage_root = joinpath(root, "stage")
        dataset, intended, sidecars = _write_cleanup_fixture(stage_root)
        quarantine = joinpath(stage_root, "artifacts", "quarantine")
        expected_sha256 = OpenEMPIRE._oos_manifest_directory_sha256(intended)
        julia_command = joinpath(Sys.BINDIR, Base.julia_exename())
        arguments = OpenEMPIRE._oos_sidecar_quarantine_arguments(
            julia_command,
            dataset,
            stage_root,
            quarantine,
            expected_sha256,
            intended,
            sidecars,
        )
        output = read(Cmd(arguments), String)
        @test occursin("__DIRECTORY_SHA256__\t$expected_sha256", output)
        @test occursin("__QUARANTINE__\t$quarantine\t2", output)
        @test _test_oos_manifest_entries(dataset) == intended
        @test all(!isfile(joinpath(dataset, path)) for path in keys(sidecars))
        @test all(isfile(joinpath(quarantine, path)) for path in keys(sidecars))

        drift_stage = joinpath(root, "drift-stage")
        drift_dataset, drift_intended, drift_sidecars =
            _write_cleanup_fixture(drift_stage)
        write(joinpath(drift_dataset, "unexpected.txt"), "drift")
        drift_quarantine = joinpath(drift_stage, "artifacts", "quarantine")
        drift_arguments = OpenEMPIRE._oos_sidecar_quarantine_arguments(
            julia_command,
            drift_dataset,
            drift_stage,
            drift_quarantine,
            OpenEMPIRE._oos_manifest_directory_sha256(drift_intended),
            drift_intended,
            drift_sidecars,
        )
        process = run(pipeline(ignorestatus(Cmd(drift_arguments)); stdout = devnull,
                               stderr = devnull))
        @test !success(process)
        @test !ispath(drift_quarantine)
        @test all(isfile(joinpath(drift_dataset, path)) for path in keys(drift_sidecars))
    end
end

function test_prepare_oos_sidecar_quarantine_plan()
    mktempdir() do root
        intended = Dict(
            "input.csv" => (8, repeat("1", 64)),
            "nested/other.csv" => (8, repeat("2", 64)),
        )
        sidecars = Dict(
            "._input.csv" => (163, repeat("a", 64)),
            "nested/._other.csv" => (163, repeat("a", 64)),
        )
        remote_entries = merge(copy(intended), sidecars)
        expected_sha256 = OpenEMPIRE._oos_manifest_directory_sha256(intended)
        remote_sha256 = OpenEMPIRE._oos_manifest_directory_sha256(remote_entries)
        local_manifest = _write_test_oos_manifest(
            joinpath(root, "local.tsv"),
            intended,
        )
        remote_manifest = _write_test_oos_manifest(
            joinpath(root, "remote.tsv"),
            remote_entries;
            directory_sha256 = remote_sha256,
        )
        stage_root = "/cluster/users/intern/oos/stages/test"
        project_dir = joinpath(stage_root, "project")
        commands = [
            OpenEMPIRE._oos_staging_command(
                "placeholder",
                "Synthetic command $index",
                ["true"],
            ) for index in 1:15
        ]
        commands[13] = OpenEMPIRE._oos_staging_command(
            "remote_validate",
            "Verify all staged checksums before preparing a queue",
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "intern@solstorm.iot.ntnu.no",
                "cd $project_dir\njulia --project=. -e 'using OpenEMPIRE; " *
                "OpenEMPIRE._oos_code_sha256(ARGS[1]); " *
                "OpenEMPIRE._oos_directory_sha256(ARGS[2]); " *
                "OpenEMPIRE._oos_sha256_file(ARGS[3]); " *
                "OpenEMPIRE._oos_fixed_investment_metadata(ARGS[4])'",
            ],
        )
        staging_file = joinpath(root, "staging.yaml")
        staging = Dict{String, Any}(
            "kind" => "oos_solstorm_staging_plan",
            "source" => Dict(
                "dataset" => Dict("sha256" => expected_sha256),
                "repository" => Dict("commit" => repeat("c", 40)),
            ),
            "remote" => Dict(
                "user" => "intern",
                "host" => "solstorm.iot.ntnu.no",
                "stage_root" => stage_root,
                "project_dir" => project_dir,
                "dataset" => joinpath(stage_root, "inputs", "dataset"),
            ),
            "commands" => commands,
        )
        OpenEMPIRE._write_oos_experiment_manifest(staging_file, staging)
        preflight_file = joinpath(root, "remote_preflight.yaml")
        preflight = Dict{String, Any}(
            "kind" => "oos_remote_staging_preflight",
            "status" => "blocked",
            "staging_plan" => staging_file,
            "remote" => Dict("stage_root" => stage_root),
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
                "attempt" => 3,
                "content_checksum_verification_started" => true,
                "dataset_checksum_passed" => false,
            ),
            "dataset_diagnostic" => Dict(
                "status" => "root_cause_identified",
                "local_manifest_sha256" => OpenEMPIRE._oos_sha256_file(local_manifest),
                "remote_manifest_sha256" => OpenEMPIRE._oos_sha256_file(remote_manifest),
                "remote_directory_sha256" => remote_sha256,
                "extra_files" => 2,
                "extra_file_bytes_each" => 163,
                "extra_file_sha256" => repeat("a", 64),
            ),
            "safety" => Dict(
                "remote_files_deleted" => false,
                "qsub_executed" => false,
                "solver_started" => false,
            ),
        )
        OpenEMPIRE._write_oos_experiment_manifest(preflight_file, preflight)
        cleanup_file = OpenEMPIRE.prepare_oos_solstorm_sidecar_quarantine(
            staging_file,
            preflight_file,
            local_manifest,
            remote_manifest,
        )
        cleanup = YAML.load_file(cleanup_file)
        @test cleanup["kind"] == "oos_solstorm_appledouble_quarantine_plan"
        @test cleanup["status"] == "ready"
        @test cleanup["dry_run"]
        @test cleanup["commands_executed"] == 0
        @test cleanup["requires_explicit_remote_approval"]
        @test cleanup["safety"]["exact_target_count"] == 2
        @test !cleanup["safety"]["uses_wildcards"]
        @test cleanup["safety"]["recoverable_quarantine"]
        @test !cleanup["safety"]["files_deleted"]
        @test length(cleanup["targets"]) == 2
        @test Set(target["relative_path"] for target in cleanup["targets"]) ==
              Set(keys(sidecars))
        @test length(cleanup["commands"]) == 1
        command = only(cleanup["commands"])
        @test command["argv"][1:4] == [
            "ssh",
            "-o",
            "BatchMode=yes",
            "intern@solstorm.iot.ntnu.no",
        ]
        @test occursin("mv(source, destination)", command["argv"][5])
        @test !occursin("rm(", command["argv"][5])
        @test !occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"])
        @test all(occursin(path, command["display"]) for path in keys(sidecars))

        stdout_file = joinpath(root, "quarantine.stdout.log")
        stdout_lines = [
            "$path\t$(intended[path][1])\t$(intended[path][2])" for
            path in sort!(collect(keys(intended)))
        ]
        push!(stdout_lines, "__DIRECTORY_SHA256__\t$expected_sha256")
        push!(
            stdout_lines,
            "__QUARANTINE__\t$(cleanup["remote"]["quarantine"])\t2",
        )
        write(stdout_file, join(stdout_lines, "\n") * "\n")
        stderr_file = joinpath(root, "quarantine.stderr.log")
        write(stderr_file, "")
        execution_file = joinpath(root, "quarantine_execution.yaml")
        execution = Dict{String, Any}(
            "kind" => "oos_solstorm_appledouble_quarantine_execution",
            "plan" => cleanup_file,
            "plan_sha256" => OpenEMPIRE._oos_sha256_file(cleanup_file),
            "success" => true,
            "exit_code" => 0,
            "command_count" => 1,
            "target_count" => 2,
            "stdout" => stdout_file,
            "stdout_sha256" => OpenEMPIRE._oos_sha256_file(stdout_file),
            "stderr" => stderr_file,
            "stderr_sha256" => OpenEMPIRE._oos_sha256_file(stderr_file),
            "qsub_executed" => false,
            "runner_executed" => false,
            "solver_started" => false,
            "files_deleted" => false,
        )
        OpenEMPIRE._write_oos_experiment_manifest(execution_file, execution)
        recovered_file = OpenEMPIRE.prepare_oos_solstorm_recovered_validation(
            staging_file,
            preflight_file,
            cleanup_file,
            execution_file,
        )
        recovered = YAML.load_file(recovered_file)
        @test recovered["kind"] == "oos_solstorm_recovered_validation_plan"
        @test recovered["status"] == "ready"
        @test recovered["dry_run"]
        @test recovered["commands_executed"] == 0
        @test recovered["source"]["failed_attempt"] == 3
        @test recovered["source"]["expected_dataset_sha256"] == expected_sha256
        @test recovered["safety"]["validates_staged_inputs_only"]
        @test !recovered["safety"]["prepares_execution_queue"]
        @test !recovered["safety"]["prepares_sge_script"]
        @test !recovered["safety"]["submits_scheduler_job"]
        @test !recovered["safety"]["starts_runner"]
        @test !recovered["safety"]["starts_solver"]
        @test length(recovered["commands"]) == 1
        recovered_command = only(recovered["commands"])
        @test recovered_command["original_command_index"] == 13
        @test occursin(
            "OpenEMPIRE Solstorm project dependency bootstrap",
            recovered_command["display"],
        )
        @test occursin("_oos_directory_sha256", recovered_command["display"])
        @test !occursin("prepare_oos_execution_queue.jl", recovered_command["display"])
        @test !occursin("prepare_oos_sge_job.jl", recovered_command["display"])
        @test !occursin(r"(^|[[:space:]])qsub([[:space:]]|$)",
                        recovered_command["display"])

        write(stdout_file, read(stdout_file, String) * "unexpected\n")
        @test_throws ArgumentError OpenEMPIRE.prepare_oos_solstorm_recovered_validation(
            staging_file,
            preflight_file,
            cleanup_file,
            execution_file;
            output_file = joinpath(root, "unsafe_recovered_validation.yaml"),
        )
    end
end
