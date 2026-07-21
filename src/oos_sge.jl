const _OOS_SOLSTORM_SGE_HOSTS =
    "compute-4-51|compute-4-52|compute-4-53|compute-4-55|compute-4-56"
const _OOS_SOLSTORM_JULIA_BOOTSTRAP_MARKER = "# OpenEMPIRE Solstorm Julia bootstrap"
const _OOS_SOLSTORM_JULIA_MODULE_FALLBACK =
    "module load Julia/1.9.3 2>/dev/null || " *
    "module load julia/1.9.3 2>/dev/null || " *
    "module load Julia/1.10.0 2>/dev/null || " *
    "module load julia/1.10.0 2>/dev/null || " *
    "module load Julia/1.11.2 2>/dev/null || " *
    "module load julia/1.11.2 2>/dev/null || " *
    "module load Julia 2>/dev/null || " *
    "module load julia 2>/dev/null || true"

function _validate_oos_sge_value(value::AbstractString, name::AbstractString, pattern)
    occursin(pattern, value) || throw(ArgumentError("Unsupported $name value: $value"))
    return value
end

function _oos_solstorm_julia_bootstrap(julia_command::AbstractString)
    executable = _oos_shell_quote(julia_command)
    missing_message = _oos_shell_quote(
        "ERROR: Julia executable not found after Solstorm module fallback: $julia_command",
    )
    return """$_OOS_SOLSTORM_JULIA_BOOTSTRAP_MARKER
if ! command -v $executable >/dev/null 2>&1; then
    type module >/dev/null 2>&1 || source /etc/profile >/dev/null 2>&1 || true
    $_OOS_SOLSTORM_JULIA_MODULE_FALLBACK
fi
export JULIA_PKG_UNPACK_REGISTRY=true
if ! command -v $executable >/dev/null 2>&1; then
    echo $missing_message >&2
    exit 1
fi"""
end

function _oos_sge_script_content(queue, job, plan)
    project_dir = queue["runner"]["project_dir"]
    julia_command = queue["runner"]["julia_command"]
    solver_import = queue["solver"] == "Gurobi" ? "; import Gurobi" : ""
    command = join(
        (_oos_shell_quote(string(argument)) for argument in job["command"]),
        " ",
    )
    return """#!/bin/bash
#\$ -S /bin/bash
#\$ -cwd
#\$ -V
#\$ -N $(plan["job_name"])
#\$ -o $(plan["stdout_template"])
#\$ -e $(plan["stderr_template"])
#\$ -l hostname=\"$(plan["hosts"])\"

set -euo pipefail

cd $(_oos_shell_quote(project_dir))

module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
$(_oos_solstorm_julia_bootstrap(julia_command))

if ! $(_oos_shell_quote(julia_command)) --project=$(_oos_shell_quote(project_dir)) -e 'import OpenEMPIRE; import JuMP; import HiGHS$solver_import' >/dev/null 2>&1; then
    $(_oos_shell_quote(julia_command)) --project=$(_oos_shell_quote(project_dir)) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
fi

$(_oos_shell_quote(julia_command)) --project=$(_oos_shell_quote(project_dir)) -e 'using OpenEMPIRE; _, queue = OpenEMPIRE._load_oos_execution_queue(ARGS[1]); OpenEMPIRE._validate_oos_execution_queue_inputs(queue)' $(_oos_shell_quote(plan["queue_file"]))

echo \"OpenEMPIRE OOS job: $(job["tree"])\"
echo \"SGE job ID: \${JOB_ID:-not-submitted}\"
echo \"Host: \$(hostname)\"
echo \"Start time: \$(date)\"

$command
"""
end

function _write_oos_sge_script(path::AbstractString, content::AbstractString)
    mkpath(dirname(path))
    if ispath(path)
        isfile(path) || throw(ArgumentError("SGE script path is not a file: $path"))
        read(path, String) == content || throw(ArgumentError(
            "SGE script already exists with different content: $path",
        ))
        return path
    end
    mktemp(dirname(path)) do temporary_path, io
        write(io, content)
        close(io)
        chmod(temporary_path, 0o755)
        mv(temporary_path, path)
    end
    return path
end

"""
    prepare_oos_sge_job(
        queue_file;
        job_index = nothing,
        output_dir = joinpath(dirname(queue_file), "sge"),
        job_name_prefix = "empire_oos",
        hosts = _OOS_SOLSTORM_SGE_HOSTS,
    )

Generate an idempotent SGE job script for one pending OOS queue job.

When `job_index` is omitted, the first pending job is selected. The generated
script follows the repository's Solstorm module-loading and high-memory-host
conventions. A `qsub` command is recorded in the queue but never executed.
Returns the scheduler-plan mapping stored on the job.
"""
function prepare_oos_sge_job(
    queue_file::AbstractString;
    job_index = nothing,
    output_dir::AbstractString = joinpath(dirname(queue_file), "sge"),
    job_name_prefix::AbstractString = "empire_oos",
    hosts::AbstractString = _OOS_SOLSTORM_SGE_HOSTS,
)
    target_queue, queue = _load_oos_execution_queue(queue_file)
    _validate_oos_execution_queue_inputs(queue)
    _validate_oos_sge_value(job_name_prefix, "SGE job-name prefix", r"^[A-Za-z0-9_-]+$")
    _validate_oos_sge_value(hosts, "SGE host expression", r"^[A-Za-z0-9_.|*-]+$")

    job = if job_index === nothing
        pending = findfirst(candidate -> candidate["status"] == "pending", queue["jobs"])
        pending === nothing && throw(ArgumentError("OOS execution queue has no pending job"))
        queue["jobs"][pending]
    else
        _oos_execution_job(queue, Int(job_index))
    end
    job["status"] == "pending" || throw(ArgumentError(
        "SGE scripts can only be prepared for pending jobs: $(job["tree"])",
    ))

    target_output = abspath(normpath(output_dir))
    logs_dir = joinpath(target_output, "logs")
    mkpath(logs_dir)
    script_path = joinpath(target_output, "$(job["tree"]).sge.sh")
    job_name = "$(job_name_prefix)_$(job["index"])"
    length(job_name) <= 128 || throw(ArgumentError("SGE job name is too long: $job_name"))
    stdout_template = joinpath(logs_dir, "$(job["tree"])_\$JOB_ID.out")
    stderr_template = joinpath(logs_dir, "$(job["tree"])_\$JOB_ID.err")
    submit_command = String["qsub", script_path]
    plan = Dict{String, Any}(
        "kind" => "sge",
        "cluster" => "Solstorm",
        "status" => "prepared",
        "job_name" => job_name,
        "hosts" => hosts,
        "queue_file" => target_queue,
        "script" => script_path,
        "script_sha256" => nothing,
        "stdout_template" => stdout_template,
        "stderr_template" => stderr_template,
        "submit_command" => submit_command,
        "submit_command_display" => _oos_command_display(
            queue["runner"]["project_dir"],
            submit_command,
        ),
        "raw_state" => nothing,
        "last_updated_at_utc" => string(now(UTC), "Z"),
        "accounting" => nothing,
    )
    content = _oos_sge_script_content(queue, job, plan)
    _write_oos_sge_script(script_path, content)
    plan["script_sha256"] = _oos_sha256_file(script_path)

    existing = get(job, "scheduler", nothing)
    if existing !== nothing
        immutable_keys = (
            "kind",
            "cluster",
            "job_name",
            "hosts",
            "queue_file",
            "script",
            "script_sha256",
            "stdout_template",
            "stderr_template",
            "submit_command",
            "submit_command_display",
        )
        all(get(existing, key, nothing) == plan[key] for key in immutable_keys) || throw(
            ArgumentError("OOS job already has a different scheduler plan: $(job["tree"])")
        )
        return existing
    end
    job["scheduler"] = plan
    _write_oos_execution_queue!(target_queue, queue)
    return plan
end

"""
    parse_oos_sge_qsub_output(output)

Extract a numeric SGE job ID from standard `qsub` output.
"""
function parse_oos_sge_qsub_output(output::AbstractString)
    matched = match(r"Your job(?:-array)?\s+([0-9]+)", output)
    matched === nothing && throw(ArgumentError("Could not parse SGE qsub output"))
    return matched.captures[1]
end

function _oos_sge_queue_status(raw_state::AbstractString)
    occursin('E', raw_state) && return "failed"
    state = lowercase(raw_state)
    (occursin('q', state) || occursin('w', state) || occursin('h', state)) &&
        return "submitted"
    (occursin('r', state) || occursin('t', state) || occursin('s', state)) &&
        return "running"
    occursin('d', state) && return "failed"
    return "unknown"
end

"""
    parse_oos_sge_qstat_output(output, job_id)

Parse one job from tabular `qstat` output. Returns `nothing` when the job is no
longer listed, otherwise a mapping with the raw SGE state and queue status.
"""
function parse_oos_sge_qstat_output(output::AbstractString, job_id::AbstractString)
    for line in eachline(IOBuffer(output))
        columns = split(strip(line))
        length(columns) >= 5 || continue
        columns[1] == job_id || continue
        raw_state = columns[5]
        queue = length(columns) >= 8 ? columns[8] : nothing
        return Dict{String, Any}(
            "job_id" => job_id,
            "raw_state" => raw_state,
            "status" => _oos_sge_queue_status(raw_state),
            "queue" => queue,
        )
    end
    return nothing
end

"""
    parse_oos_sge_qacct_output(output, job_id)

Parse an SGE accounting record. Successful scheduler completion is reported as
`finished`; model acceptance is decided separately from the EMPIRE run manifest.
"""
function parse_oos_sge_qacct_output(output::AbstractString, job_id::AbstractString)
    fields = Dict{String, String}()
    for line in eachline(IOBuffer(output))
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, "====") && continue
        columns = split(stripped; limit = 2)
        length(columns) == 2 || continue
        fields[columns[1]] = strip(columns[2])
    end
    get(fields, "jobnumber", nothing) == job_id || throw(ArgumentError(
        "SGE qacct output does not contain job $job_id",
    ))
    failed = get(fields, "failed", "1")
    exit_status = get(fields, "exit_status", "1")
    status = failed == "0" && exit_status == "0" ? "finished" : "failed"
    return Dict{String, Any}(
        "job_id" => job_id,
        "status" => status,
        "failed" => failed,
        "exit_status" => exit_status,
        "fields" => fields,
    )
end

function _oos_sge_plan(job)
    plan = get(job, "scheduler", nothing)
    plan isa AbstractDict && get(plan, "kind", nothing) == "sge" || throw(ArgumentError(
        "OOS job has no prepared SGE scheduler plan: $(job["tree"])",
    ))
    return plan
end

function record_oos_sge_submission!(
    queue_file::AbstractString,
    job_index::Integer,
    qsub_output::AbstractString,
)
    target_queue, queue = _load_oos_execution_queue(queue_file)
    job = _oos_execution_job(queue, job_index)
    plan = _oos_sge_plan(job)
    job_id = parse_oos_sge_qsub_output(qsub_output)
    stdout_path = replace(plan["stdout_template"], "\$JOB_ID" => job_id)
    stderr_path = replace(plan["stderr_template"], "\$JOB_ID" => job_id)
    plan["status"] = "submitted"
    plan["raw_state"] = "qsub accepted"
    plan["last_updated_at_utc"] = string(now(UTC), "Z")
    _set_oos_execution_job_status!(
        queue,
        job,
        "submitted";
        scheduler_job_id = job_id,
        stdout_path,
        stderr_path,
        source = "sge_qsub",
    )
    _write_oos_execution_queue!(target_queue, queue)
    return job
end

function record_oos_sge_qstat!(
    queue_file::AbstractString,
    job_index::Integer,
    qstat_output::AbstractString,
)
    target_queue, queue = _load_oos_execution_queue(queue_file)
    job = _oos_execution_job(queue, job_index)
    plan = _oos_sge_plan(job)
    job_id = get(job, "scheduler_job_id", nothing)
    job_id isa AbstractString || throw(ArgumentError(
        "OOS job has no recorded SGE job ID: $(job["tree"])",
    ))
    parsed = parse_oos_sge_qstat_output(qstat_output, job_id)
    parsed === nothing && return nothing
    parsed["status"] == "unknown" && throw(ArgumentError(
        "Unsupported SGE qstat state for job $job_id: $(parsed["raw_state"])",
    ))
    error = parsed["status"] == "failed" ?
            "SGE qstat reported state $(parsed["raw_state"])" : nothing
    plan["status"] = parsed["status"]
    plan["raw_state"] = parsed["raw_state"]
    plan["queue"] = parsed["queue"]
    plan["last_updated_at_utc"] = string(now(UTC), "Z")
    _set_oos_execution_job_status!(
        queue,
        job,
        parsed["status"];
        error,
        source = "sge_qstat",
    )
    _write_oos_execution_queue!(target_queue, queue)
    return job
end

function record_oos_sge_qacct!(
    queue_file::AbstractString,
    job_index::Integer,
    qacct_output::AbstractString,
)
    target_queue, queue = _load_oos_execution_queue(queue_file)
    job = _oos_execution_job(queue, job_index)
    plan = _oos_sge_plan(job)
    job_id = get(job, "scheduler_job_id", nothing)
    job_id isa AbstractString || throw(ArgumentError(
        "OOS job has no recorded SGE job ID: $(job["tree"])",
    ))
    parsed = parse_oos_sge_qacct_output(qacct_output, job_id)
    error = parsed["status"] == "failed" ?
            "SGE job failed=$(parsed["failed"]), exit_status=$(parsed["exit_status"])" :
            nothing
    plan["status"] = parsed["status"]
    plan["raw_state"] = "accounting available"
    plan["last_updated_at_utc"] = string(now(UTC), "Z")
    plan["accounting"] = parsed["fields"]
    _set_oos_execution_job_status!(
        queue,
        job,
        parsed["status"];
        error,
        source = "sge_qacct",
    )
    _write_oos_execution_queue!(target_queue, queue)
    return job
end
