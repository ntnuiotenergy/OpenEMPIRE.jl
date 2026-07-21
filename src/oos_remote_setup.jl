function _validate_oos_recovered_validation_execution(
    validation_plan,
    validation_execution,
    validation_plan_file::AbstractString,
)
    recorded_plan = abspath(normpath(string(validation_execution["plan"])))
    recorded_plan == validation_plan_file || throw(ArgumentError(
        "Validation execution refers to a different validation plan",
    ))
    _oos_sha256_file(validation_plan_file) == validation_execution["plan_sha256"] ||
        throw(ArgumentError("Validation plan changed after execution"))
    get(validation_execution, "success", false) == true || throw(ArgumentError(
        "Recovered validation execution was not successful",
    ))
    get(validation_execution, "exit_code", nothing) == 0 || throw(ArgumentError(
        "Recovered validation execution did not exit successfully",
    ))
    get(validation_execution, "original_command_index", nothing) == 13 || throw(
        ArgumentError("Recovered validation execution was not command 13"),
    )
    expected_validations = [
        "repository_code",
        "dataset",
        "execution_config",
        "generation_config",
        "oos_tree",
        "fixed_investments",
    ]
    get(validation_execution, "validations", nothing) == expected_validations || throw(
        ArgumentError("Recovered validation evidence does not contain all six checks"),
    )
    for key in (
        "queue_prepared",
        "sge_script_prepared",
        "qsub_executed",
        "runner_executed",
        "solver_started",
    )
        get(validation_execution, key, true) == false || throw(ArgumentError(
            "Unsafe recovered validation evidence: $key",
        ))
    end
    for key in ("stdout", "stderr")
        path = abspath(normpath(string(validation_execution[key])))
        isfile(path) || throw(ArgumentError("Validation $key evidence is missing: $path"))
        _oos_sha256_file(path) == validation_execution[key * "_sha256"] || throw(
            ArgumentError("Validation $key evidence changed after execution"),
        )
        isempty(read(path, String)) || throw(ArgumentError(
            "Successful assertion-only validation must have empty $key",
        ))
    end
    return expected_validations
end

function _oos_remote_setup_command(original, index, staging, julia_command)
    command = _oos_resume_command(
        original,
        index,
        staging["remote"]["project_dir"],
        julia_command,
    )
    display = command["display"]
    for forbidden in ("run_julia_empire", "Gurobi.Optimizer", "scp ", "rsync ")
        !occursin(forbidden, display) || throw(ArgumentError(
            "Remote setup command $index contains forbidden action: $forbidden",
        ))
    end
    occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", display) && throw(
        ArgumentError("Remote setup command $index unexpectedly contains qsub"),
    )
    return command
end

"""
    prepare_oos_solstorm_remote_setup(
        staging_plan_file,
        validation_plan_file,
        validation_execution_file;
        output_file = joinpath(dirname(staging_plan_file), "remote_setup.yaml"),
        julia_command = "julia",
    )

Prepare a two-command dry-run plan that reproduces only original Solstorm
staging commands 14 and 15 after successful recovered-input validation. These
commands create or idempotently verify the one-tree execution queue and SGE
script. The plan cannot submit with `qsub`, invoke the model runner, or start a
solver, and it never executes SSH itself.
"""
function prepare_oos_solstorm_remote_setup(
    staging_plan_file::AbstractString,
    validation_plan_file::AbstractString,
    validation_execution_file::AbstractString;
    output_file::AbstractString = joinpath(
        dirname(staging_plan_file),
        "remote_setup.yaml",
    ),
    julia_command::AbstractString = "julia",
)
    source_files = abspath.(normpath.((
        staging_plan_file,
        validation_plan_file,
        validation_execution_file,
    )))
    all(isfile, source_files) || throw(ArgumentError(
        "Remote setup requires all three source-evidence files",
    ))
    target_staging, target_validation, target_execution = source_files
    isempty(strip(julia_command)) && throw(ArgumentError("julia_command cannot be empty"))
    staging = YAML.load_file(target_staging)
    validation = YAML.load_file(target_validation)
    execution = YAML.load_file(target_execution)

    get(staging, "kind", nothing) == "oos_solstorm_staging_plan" || throw(
        ArgumentError("Not an OOS Solstorm staging plan: $target_staging"),
    )
    get(validation, "kind", nothing) ==
    "oos_solstorm_recovered_validation_plan" || throw(ArgumentError(
        "Not an OOS recovered-validation plan: $target_validation",
    ))
    get(execution, "kind", nothing) ==
    "oos_solstorm_recovered_validation_execution" || throw(ArgumentError(
        "Not OOS recovered-validation execution evidence: $target_execution",
    ))
    validation["source"]["staging_plan"] == target_staging || throw(ArgumentError(
        "Recovered-validation plan refers to a different staging plan",
    ))
    _oos_sha256_file(target_staging) == validation["source"]["staging_plan_sha256"] ||
        throw(ArgumentError("Staging plan changed after recovered validation planning"))
    for key in (
        "remote_preflight",
        "quarantine_plan",
        "quarantine_execution",
        "quarantine_stdout",
        "quarantine_stderr",
    )
        path = abspath(normpath(string(validation["source"][key])))
        isfile(path) || throw(ArgumentError("Upstream validation evidence is missing: $key"))
        _oos_sha256_file(path) == validation["source"][key * "_sha256"] || throw(
            ArgumentError("Upstream validation evidence changed: $key"),
        )
    end
    expected_digest = validation["source"]["expected_dataset_sha256"]
    expected_digest == staging["source"]["dataset"]["sha256"] || throw(ArgumentError(
        "Recovered dataset fingerprint differs from the staging plan",
    ))
    validated_inputs = _validate_oos_recovered_validation_execution(
        validation,
        execution,
        target_validation,
    )

    staging_commands = staging["commands"]
    length(staging_commands) >= 15 || throw(ArgumentError(
        "Staging plan does not contain commands 14 and 15",
    ))
    all(staging_commands[index]["phase"] == "remote_configure" for index in 14:15) ||
        throw(ArgumentError("Staging commands 14 and 15 are not remote setup commands"))
    commands = [
        _oos_remote_setup_command(
            staging_commands[index],
            index,
            staging,
            julia_command,
        ) for index in 14:15
    ]
    occursin("prepare_oos_execution_queue.jl", commands[1]["display"]) || throw(
        ArgumentError("Remote setup command 14 does not prepare the execution queue"),
    )
    occursin("prepare_oos_sge_job.jl", commands[2]["display"]) || throw(
        ArgumentError("Remote setup command 15 does not prepare the SGE script"),
    )
    expected_target = "$(staging["remote"]["user"])@$(staging["remote"]["host"])"
    all(command["argv"][4] == expected_target for command in commands) || throw(
        ArgumentError("Remote setup plan contains an unexpected account"),
    )

    setup = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_remote_setup_plan",
        "status" => "ready",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "requires_explicit_remote_approval" => true,
        "source" => Dict{String, Any}(
            "staging_plan" => target_staging,
            "staging_plan_sha256" => _oos_sha256_file(target_staging),
            "validation_plan" => target_validation,
            "validation_plan_sha256" => _oos_sha256_file(target_validation),
            "validation_execution" => target_execution,
            "validation_execution_sha256" => _oos_sha256_file(target_execution),
            "expected_dataset_sha256" => expected_digest,
            "validated_inputs" => validated_inputs,
        ),
        "remote" => deepcopy(staging["remote"]),
        "safety" => Dict{String, Any}(
            "starts_at_original_command" => 14,
            "ends_at_original_command" => 15,
            "prepares_execution_queue" => true,
            "prepares_sge_script" => true,
            "idempotent_repository_operations" => true,
            "recreates_remote_stage" => false,
            "retransfers_files" => false,
            "submits_scheduler_job" => false,
            "starts_runner" => false,
            "starts_solver" => false,
        ),
        "commands" => commands,
    )
    target_output = abspath(normpath(output_file))
    target_output in source_files && throw(ArgumentError(
        "Remote setup plan cannot overwrite source evidence",
    ))
    _write_oos_experiment_manifest(target_output, setup)
    return target_output
end
