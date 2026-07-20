#!/usr/bin/env julia

using OpenEMPIRE
using YAML

const _OOS_STAGING_OPTIONS = Set([
    "queue",
    "job",
    "output-dir",
    "remote-user",
    "remote-host",
    "remote-root",
    "revision",
])

function _parse_oos_staging_args(args)
    options = Dict{String, String}(
        "queue" => "",
        "job" => "",
        "output-dir" => "",
        "remote-user" => "",
        "remote-host" => OpenEMPIRE._OOS_SOLSTORM_HOST,
        "remote-root" => "",
        "revision" => "HEAD",
    )
    for argument in args
        startswith(argument, "--") && occursin("=", argument) || throw(ArgumentError(
            "Unsupported argument: $argument",
        ))
        key, value = split(argument[3:end], "="; limit = 2)
        key in _OOS_STAGING_OPTIONS || throw(ArgumentError("Unsupported option: --$key"))
        options[key] = value
    end
    for required in ("queue", "remote-user", "remote-root")
        isempty(strip(options[required])) && throw(ArgumentError("--$required is required"))
    end
    return options
end

function main(args = ARGS)
    options = _parse_oos_staging_args(args)
    job_index = isempty(strip(options["job"])) ? nothing : parse(Int, options["job"])
    output_dir = isempty(strip(options["output-dir"])) ? nothing : options["output-dir"]
    plan_file = OpenEMPIRE.prepare_oos_solstorm_staging(
        options["queue"];
        remote_user = options["remote-user"],
        remote_host = options["remote-host"],
        remote_root = options["remote-root"],
        job_index,
        output_dir,
        revision = options["revision"],
    )
    plan = YAML.load_file(plan_file)

    println("Solstorm OOS staging plan (dry-run only)")
    println("Plan:       $plan_file")
    println("Status:     $(plan["status"])")
    println("Source:     $(plan["source"]["selected_job"]["tree"])")
    println("Revision:   $(plan["source"]["repository"]["commit"])")
    println("Destination: $(plan["remote"]["stage_root"])")
    if !isempty(plan["blockers"])
        println("Blockers:")
        for blocker in plan["blockers"]
            println("  - $blocker")
        end
    end
    println("Commands (not executed):")
    for (index, command) in enumerate(plan["commands"])
        println("  $index. [$(command["phase"])] $(command["display"])")
    end
    return plan_file
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
