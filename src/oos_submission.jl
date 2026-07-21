function _load_oos_remote_setup_inspection(path::AbstractString)
    values = Dict{String, Vector{String}}()
    for (line_number, line) in enumerate(eachline(path))
        fields = split(line, '\t'; keepempty = true)
        length(fields) >= 2 || throw(ArgumentError(
            "Invalid setup-inspection line $line_number: $line",
        ))
        haskey(values, fields[1]) && throw(ArgumentError(
            "Duplicate setup-inspection field: $(fields[1])",
        ))
        values[fields[1]] = fields[2:end]
    end
    required = Set([
        "QUEUE_SHA256",
        "SCRIPT_SHA256",
        "QUEUE_STATUS",
        "JOB",
        "SOLVER",
        "HOSTS",
        "SCHEDULER",
        "INPUTS_VALIDATED",
        "QSUB_EXECUTED",
    ])
    Set(keys(values)) == required || throw(ArgumentError(
        "Setup inspection does not contain the exact required fields",
    ))
    return values
end

function _validate_oos_remote_setup_execution(setup, execution, setup_file)
    abspath(normpath(string(execution["plan"]))) == setup_file || throw(ArgumentError(
        "Remote-setup execution refers to a different plan",
    ))
    _oos_sha256_file(setup_file) == execution["plan_sha256"] || throw(ArgumentError(
        "Remote-setup plan changed after execution",
    ))
    get(execution, "success", false) == true || throw(ArgumentError(
        "Remote-setup execution was not successful",
    ))
    Int.(execution["commands_attempted"]) == [14, 15] || throw(ArgumentError(
        "Remote-setup execution did not run exactly commands 14 and 15",
    ))
    results = execution["commands"]
    length(results) == 2 || throw(ArgumentError("Remote setup needs two command results"))
    all(
        get(result, "success", false) == true &&
        get(result, "exit_code", nothing) == 0 &&
        get(result, "stderr_bytes", nothing) == 0 for result in results
    ) || throw(ArgumentError("One or more remote-setup commands did not pass"))
    for result in results, key in ("stdout", "stderr")
        evidence_file = abspath(normpath(string(result[key])))
        isfile(evidence_file) || throw(ArgumentError(
            "Remote-setup $key evidence is missing: $evidence_file",
        ))
        _oos_sha256_file(evidence_file) == result[key * "_sha256"] || throw(
            ArgumentError("Remote-setup $key evidence changed"),
        )
    end
    for key in ("qsub_executed", "runner_executed", "solver_started")
        get(execution, key, true) == false || throw(ArgumentError(
            "Unsafe remote-setup execution evidence: $key",
        ))
    end
    return nothing
end

function _validate_oos_remote_setup_inspection(inspection, inspection_file)
    get(inspection, "success", false) == true &&
    get(inspection, "exit_code", nothing) == 0 &&
    get(inspection, "read_only", false) == true || throw(ArgumentError(
        "Remote setup artifact inspection did not pass read-only",
    ))
    for key in ("stdout", "stderr")
        evidence_file = abspath(normpath(string(inspection[key])))
        isfile(evidence_file) || throw(ArgumentError(
            "Artifact-inspection $key is missing: $evidence_file",
        ))
        _oos_sha256_file(evidence_file) == inspection[key * "_sha256"] || throw(
            ArgumentError("Artifact-inspection $key changed"),
        )
    end
    isempty(read(inspection["stderr"], String)) || throw(ArgumentError(
        "Successful artifact inspection has non-empty stderr",
    ))
    for key in ("qsub_executed", "runner_executed", "solver_started")
        get(inspection, key, true) == false || throw(ArgumentError(
            "Unsafe artifact-inspection evidence: $key",
        ))
    end
    return _load_oos_remote_setup_inspection(inspection["stdout"])
end

function _oos_submission_preflight_code()
    return raw"""using OpenEMPIRE
queue_file, queue = OpenEMPIRE._load_oos_execution_queue(ARGS[1])
OpenEMPIRE._validate_oos_execution_queue_inputs(queue)
OpenEMPIRE._oos_sha256_file(queue_file) == ARGS[2] || error("remote queue changed")
length(queue["jobs"]) == 1 || error("queue no longer has exactly one job")
job = only(queue["jobs"])
job["index"] == 1 || error("unexpected job index")
job["tree"] == "oos_tree1" || error("unexpected job tree")
job["seed"] == 101 || error("unexpected OOS seed")
job["status"] == "pending" || error("OOS job is no longer pending")
job["scheduler_job_id"] === nothing || error("OOS job already has a scheduler ID")
job["submitted_at_utc"] === nothing || error("OOS job already has a submission time")
plan = job["scheduler"]
plan["kind"] == "sge" || error("job no longer has an SGE plan")
plan["status"] == "prepared" || error("SGE plan is no longer prepared")
plan["script"] == ARGS[3] || error("SGE script path changed")
OpenEMPIRE._oos_sha256_file(ARGS[3]) == ARGS[4] || error("SGE script changed")
plan["script_sha256"] == ARGS[4] || error("recorded SGE script hash changed")
plan["submit_command"] == ["qsub", ARGS[3]] || error("recorded submit command changed")
plan["raw_state"] === nothing || error("scheduler already has a raw state")
plan["accounting"] === nothing || error("scheduler already has accounting")
!ispath(ARGS[5]) || error("qsub stdout reservation already exists")
!ispath(ARGS[6]) || error("qsub stderr reservation already exists")
"""
end

"""
    prepare_oos_solstorm_submission(
        setup_plan_file,
        setup_execution_file,
        artifact_inspection_file;
        output_file = joinpath(dirname(setup_plan_file), "submission.yaml"),
        julia_command = "julia",
    )

Prepare a one-command, duplicate-safe `qsub` plan for the verified single-tree
OOS job. The remote command revalidates the pending queue and SGE script, then
uses noclobber-protected remote stdout/stderr reservations before invoking
exactly one `qsub`. It does not run the model directly or record a fabricated
job ID, and it never executes SSH itself.
"""
function prepare_oos_solstorm_submission(
    setup_plan_file::AbstractString,
    setup_execution_file::AbstractString,
    artifact_inspection_file::AbstractString;
    output_file::AbstractString = joinpath(dirname(setup_plan_file), "submission.yaml"),
    julia_command::AbstractString = "julia",
)
    sources = abspath.(normpath.((
        setup_plan_file,
        setup_execution_file,
        artifact_inspection_file,
    )))
    all(isfile, sources) || throw(ArgumentError(
        "Submission planning requires setup plan, execution, and inspection evidence",
    ))
    target_setup, target_execution, target_inspection = sources
    setup = YAML.load_file(target_setup)
    execution = YAML.load_file(target_execution)
    inspection = YAML.load_file(target_inspection)
    get(setup, "kind", nothing) == "oos_solstorm_remote_setup_plan" || throw(
        ArgumentError("Not an OOS remote-setup plan: $target_setup"),
    )
    get(execution, "kind", nothing) == "oos_solstorm_remote_setup_execution" || throw(
        ArgumentError("Not OOS remote-setup execution evidence"),
    )
    get(inspection, "kind", nothing) ==
    "oos_solstorm_remote_setup_artifact_inspection" || throw(ArgumentError(
        "Not OOS remote artifact-inspection evidence",
    ))
    _validate_oos_remote_setup_execution(setup, execution, target_setup)
    inspected = _validate_oos_remote_setup_inspection(inspection, target_inspection)

    inspected["QUEUE_STATUS"] == ["ready"] || throw(ArgumentError(
        "Inspected remote queue is not ready",
    ))
    inspected["JOB"] == ["1", "oos_tree1", "101", "pending"] || throw(
        ArgumentError("Inspected OOS job is not the expected pending tree"),
    )
    inspected["SOLVER"] == ["Gurobi"] || throw(ArgumentError(
        "Inspected OOS job does not use Gurobi",
    ))
    inspected["SCHEDULER"] == ["prepared", "NO_JOB_ID"] || throw(ArgumentError(
        "Inspected scheduler is not prepared without a job ID",
    ))
    inspected["QSUB_EXECUTED"] == ["false"] || throw(ArgumentError(
        "Inspection indicates qsub already executed",
    ))
    queue_sha256 = only(inspected["QUEUE_SHA256"])
    script_sha256 = only(inspected["SCRIPT_SHA256"])
    occursin(r"^[0-9a-f]{64}$", queue_sha256) || throw(ArgumentError(
        "Invalid inspected queue SHA-256",
    ))
    occursin(r"^[0-9a-f]{64}$", script_sha256) || throw(ArgumentError(
        "Invalid inspected script SHA-256",
    ))

    remote = setup["remote"]
    queue_file = remote["execution_queue"]
    script_file = remote["sge_script"]
    inspection["queue_file"] == queue_file || throw(ArgumentError(
        "Inspection refers to a different queue path",
    ))
    inspection["sge_script"] == script_file || throw(ArgumentError(
        "Inspection refers to a different SGE script path",
    ))
    artifacts = joinpath(remote["stage_root"], "artifacts")
    remote_stdout = joinpath(artifacts, "qsub_oos_tree1_attempt1.stdout")
    remote_stderr = joinpath(artifacts, "qsub_oos_tree1_attempt1.stderr")
    preflight_arguments = [
        julia_command,
        "--startup-file=no",
        "--project=$(remote["project_dir"])",
        "-e",
        strip(_oos_submission_preflight_code()),
        queue_file,
        queue_sha256,
        script_file,
        script_sha256,
        remote_stdout,
        remote_stderr,
    ]
    preflight = _oos_command_display(remote["project_dir"], preflight_arguments)
    submit = join((
        "set -euo pipefail",
        _oos_solstorm_julia_bootstrap(julia_command),
        preflight,
        "set -o noclobber",
        "qsub $(_oos_shell_quote(script_file)) " *
        "> $(_oos_shell_quote(remote_stdout)) " *
        "2> $(_oos_shell_quote(remote_stderr))",
        "cat $(_oos_shell_quote(remote_stdout))",
    ), "\n")
    account = "$(remote["user"])@$(remote["host"])"
    command = _oos_staging_command(
        "remote_submit",
        "Submit the verified one-tree OOS SGE job exactly once",
        ["ssh", "-o", "BatchMode=yes", account, submit],
    )
    length(collect(eachmatch(r"(^|[[:space:]])qsub([[:space:]]|$)", submit))) == 1 ||
        throw(ArgumentError("Submission plan must contain exactly one qsub invocation"))
    for forbidden in ("run_julia_empire", "Gurobi.Optimizer", "scp ", "rsync ")
        !occursin(forbidden, submit) || throw(ArgumentError(
            "Submission command contains forbidden direct action: $forbidden",
        ))
    end

    submission = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_submission_plan",
        "status" => "ready",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "requires_explicit_remote_approval" => true,
        "source" => Dict{String, Any}(
            "setup_plan" => target_setup,
            "setup_plan_sha256" => _oos_sha256_file(target_setup),
            "setup_execution" => target_execution,
            "setup_execution_sha256" => _oos_sha256_file(target_execution),
            "artifact_inspection" => target_inspection,
            "artifact_inspection_sha256" => _oos_sha256_file(target_inspection),
            "queue_sha256" => queue_sha256,
            "sge_script_sha256" => script_sha256,
        ),
        "remote" => Dict{String, Any}(
            "account" => account,
            "stage_root" => remote["stage_root"],
            "project_dir" => remote["project_dir"],
            "queue_file" => queue_file,
            "sge_script" => script_file,
            "qsub_stdout" => remote_stdout,
            "qsub_stderr" => remote_stderr,
        ),
        "safety" => Dict{String, Any}(
            "expected_qsub_invocations" => 1,
            "remote_evidence_noclobber" => true,
            "requires_pending_job_without_id" => true,
            "requires_exact_queue_hash" => true,
            "requires_exact_script_hash" => true,
            "starts_runner_directly" => false,
            "starts_solver_directly" => false,
            "retransfers_files" => false,
        ),
        "commands" => [command],
    )
    target_output = abspath(normpath(output_file))
    target_output in sources && throw(ArgumentError(
        "Submission plan cannot overwrite source evidence",
    ))
    _write_oos_experiment_manifest(target_output, submission)
    return target_output
end
