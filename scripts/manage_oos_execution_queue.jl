#!/usr/bin/env julia

using OpenEMPIRE
using YAML

const _OOS_QUEUE_CONTROL_OPTIONS = Set([
    "queue",
    "job",
    "status",
    "job-id",
    "result-dir",
    "stdout",
    "stderr",
    "error",
])

function _parse_oos_queue_control_args(args)
    options = Dict{String, String}(key => "" for key in _OOS_QUEUE_CONTROL_OPTIONS)
    action = "show"
    action_seen = false
    for arg in args
        if startswith(arg, "--") && occursin("=", arg)
            key, value = split(arg[3:end], "="; limit = 2)
            key in _OOS_QUEUE_CONTROL_OPTIONS || throw(ArgumentError(
                "Unsupported option: --$key",
            ))
            options[key] = value
        elseif !startswith(arg, "--")
            action_seen && throw(ArgumentError("Only one action may be specified"))
            action = lowercase(arg)
            action_seen = true
        else
            throw(ArgumentError("Unsupported argument: $arg"))
        end
    end
    action in ("show", "next", "mark", "reconcile") || throw(ArgumentError(
        "Unsupported action: $action. Expected show, next, mark, or reconcile.",
    ))
    isempty(strip(options["queue"])) && throw(ArgumentError("--queue is required"))
    return action, options
end

function _optional_oos_queue_value(value)
    text = strip(value)
    return isempty(text) ? nothing : text
end

function _print_oos_queue_summary(queue_file)
    queue = YAML.load_file(queue_file)
    println("Queue:  $queue_file")
    println("Status: $(queue["status"])")
    println("Jobs:")
    for job in queue["jobs"]
        scheduler_id = something(get(job, "scheduler_job_id", nothing), "-")
        result_dir = something(get(job, "result_dir", nothing), "-")
        println(
            "  $(job["index"]). $(job["tree"]): $(job["status"]) " *
            "[scheduler=$scheduler_id, result=$result_dir]",
        )
    end
    next_job = OpenEMPIRE.next_pending_oos_job(queue_file)
    if next_job === nothing
        println("Next pending job: none")
    else
        println("Next pending job: $(next_job["index"]) ($(next_job["tree"]))")
        println("Command (not executed):")
        println(next_job["command_display"])
    end
    return queue
end

function main(args = ARGS)
    action, options = _parse_oos_queue_control_args(args)
    queue_file = abspath(normpath(options["queue"]))

    if action == "show"
        return _print_oos_queue_summary(queue_file)
    elseif action == "next"
        job = OpenEMPIRE.next_pending_oos_job(queue_file)
        if job === nothing
            println("No pending OOS job")
        else
            println(job["command_display"])
        end
        return job
    elseif action == "mark"
        isempty(strip(options["job"])) && throw(ArgumentError(
            "mark requires --job=<index>",
        ))
        isempty(strip(options["status"])) && throw(ArgumentError(
            "mark requires --status=<status>",
        ))
        OpenEMPIRE.update_oos_execution_job!(
            queue_file,
            parse(Int, options["job"]),
            options["status"];
            scheduler_job_id = _optional_oos_queue_value(options["job-id"]),
            result_dir = _optional_oos_queue_value(options["result-dir"]),
            stdout_path = _optional_oos_queue_value(options["stdout"]),
            stderr_path = _optional_oos_queue_value(options["stderr"]),
            error = _optional_oos_queue_value(options["error"]),
        )
        return _print_oos_queue_summary(queue_file)
    end

    OpenEMPIRE.reconcile_oos_execution_queue!(queue_file)
    return _print_oos_queue_summary(queue_file)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
