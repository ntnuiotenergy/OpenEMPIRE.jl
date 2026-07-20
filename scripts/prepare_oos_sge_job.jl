#!/usr/bin/env julia

using OpenEMPIRE

const _OOS_SGE_OPTIONS = Set([
    "queue",
    "job",
    "output-dir",
    "job-name-prefix",
    "hosts",
])

function _parse_oos_sge_args(args)
    options = Dict{String, String}(
        "queue" => "",
        "job" => "",
        "output-dir" => "",
        "job-name-prefix" => "empire_oos",
        "hosts" => OpenEMPIRE._OOS_SOLSTORM_SGE_HOSTS,
    )
    for arg in args
        startswith(arg, "--") && occursin("=", arg) || throw(ArgumentError(
            "Unsupported argument: $arg",
        ))
        key, value = split(arg[3:end], "="; limit = 2)
        key in _OOS_SGE_OPTIONS || throw(ArgumentError("Unsupported option: --$key"))
        options[key] = value
    end
    isempty(strip(options["queue"])) && throw(ArgumentError("--queue is required"))
    return options
end

function main(args = ARGS)
    options = _parse_oos_sge_args(args)
    queue_file = abspath(normpath(options["queue"]))
    job_index = isempty(strip(options["job"])) ? nothing : parse(Int, options["job"])
    output_dir = isempty(strip(options["output-dir"])) ?
                 joinpath(dirname(queue_file), "sge") :
                 options["output-dir"]

    println("Preparing Solstorm SGE job script (dry-run only)")
    println("Queue:      $queue_file")
    println("Job:        $(job_index === nothing ? "next pending" : job_index)")
    println("Output:     $output_dir")
    println("SGE hosts:  $(options["hosts"])")

    plan = OpenEMPIRE.prepare_oos_sge_job(
        queue_file;
        job_index,
        output_dir,
        job_name_prefix = options["job-name-prefix"],
        hosts = options["hosts"],
    )
    println("SGE script: $(plan["script"])")
    println("Submission command (not executed):")
    println(plan["submit_command_display"])
    return plan
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
