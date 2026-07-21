#!/usr/bin/env julia

using OpenEMPIRE
using YAML

const _OOS_RESUME_OPTIONS = Set([
    "plan",
    "preflight",
    "output",
    "julia-command",
])

function _parse_oos_resume_args(args)
    options = Dict{String, String}(
        "plan" => "",
        "preflight" => "",
        "output" => "",
        "julia-command" => "julia",
    )
    for argument in args
        startswith(argument, "--") && occursin("=", argument) || throw(ArgumentError(
            "Unsupported argument: $argument",
        ))
        key, value = split(argument[3:end], "="; limit = 2)
        key in _OOS_RESUME_OPTIONS || throw(ArgumentError("Unsupported option: --$key"))
        options[key] = value
    end
    for required in ("plan", "preflight")
        isempty(strip(options[required])) && throw(ArgumentError("--$required is required"))
    end
    return options
end

function main(args = ARGS)
    options = _parse_oos_resume_args(args)
    output_file = isempty(strip(options["output"])) ?
                  joinpath(dirname(options["plan"]), "resume.yaml") :
                  options["output"]
    resume_file = OpenEMPIRE.prepare_oos_solstorm_resume(
        options["plan"],
        options["preflight"];
        output_file,
        julia_command = options["julia-command"],
    )
    resume = YAML.load_file(resume_file)

    println("Solstorm OOS resume plan (dry-run only)")
    println("Plan:        $resume_file")
    println("Status:      $(resume["status"])")
    println("Destination: $(resume["remote"]["stage_root"])")
    println("Commands (not executed):")
    for command in resume["commands"]
        println("  $(command["original_command_index"]). $(command["display"])")
    end
    return resume_file
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
