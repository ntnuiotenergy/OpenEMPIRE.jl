function _validate_oos_manifest_relative_path(path::AbstractString)
    isempty(path) && throw(ArgumentError("Manifest path cannot be empty"))
    isabspath(path) && throw(ArgumentError("Manifest path must be relative: $path"))
    normpath(path) == path || throw(ArgumentError("Manifest path is not normalized: $path"))
    path == "." && throw(ArgumentError("Manifest path cannot be ."))
    startswith(path, "../") && throw(ArgumentError("Manifest path escapes its root: $path"))
    return path
end

function _load_oos_file_manifest(path::AbstractString)
    target = abspath(normpath(path))
    isfile(target) || throw(ArgumentError("File manifest does not exist: $target"))
    entries = Dict{String, Tuple{Int, String}}()
    directory_sha256 = nothing
    for (line_number, line) in enumerate(eachline(target))
        isempty(line) && continue
        fields = split(line, '\t'; keepempty = true)
        if fields[1] == "__DIRECTORY_SHA256__"
            length(fields) == 2 || throw(ArgumentError(
                "Invalid directory digest on line $line_number of $target",
            ))
            directory_sha256 === nothing || throw(ArgumentError(
                "Duplicate directory digest in $target",
            ))
            occursin(r"^[0-9a-f]{64}$", fields[2]) || throw(ArgumentError(
                "Invalid directory SHA-256 on line $line_number of $target",
            ))
            directory_sha256 = fields[2]
            continue
        end
        length(fields) == 3 || throw(ArgumentError(
            "Invalid file manifest line $line_number of $target",
        ))
        relative_path = _validate_oos_manifest_relative_path(fields[1])
        haskey(entries, relative_path) && throw(ArgumentError(
            "Duplicate manifest path in $target: $relative_path",
        ))
        bytes = tryparse(Int, fields[2])
        bytes === nothing && throw(ArgumentError(
            "Invalid file size on line $line_number of $target",
        ))
        bytes >= 0 || throw(ArgumentError(
            "Negative file size on line $line_number of $target",
        ))
        occursin(r"^[0-9a-f]{64}$", fields[3]) || throw(ArgumentError(
            "Invalid file SHA-256 on line $line_number of $target",
        ))
        entries[relative_path] = (bytes, fields[3])
    end
    isempty(entries) && throw(ArgumentError("File manifest is empty: $target"))
    return entries, directory_sha256
end

function _oos_manifest_directory_sha256(entries)
    paths = sort!(collect(keys(entries)))
    digest_manifest = join(("$path\t$(entries[path][2])" for path in paths), "\n")
    return bytes2hex(sha256(digest_manifest))
end

function _oos_sidecar_quarantine_code()
    return raw"""using SHA

dataset_root = normpath(abspath(ARGS[1]))
stage_root = normpath(abspath(ARGS[2]))
quarantine_root = normpath(abspath(ARGS[3]))
expected_directory_sha256 = ARGS[4]
intended_count = parse(Int, ARGS[5])
sidecar_count = parse(Int, ARGS[6])
length(ARGS) == 6 + 3 * (intended_count + sidecar_count) || error("invalid cleanup argument count")

startswith(dataset_root, stage_root * "/") || error("dataset is outside the isolated stage")
startswith(quarantine_root, stage_root * "/") || error("quarantine is outside the isolated stage")
startswith(quarantine_root, dataset_root * "/") && error("quarantine cannot be inside the dataset")
ispath(quarantine_root) && error("quarantine path already exists")

function validated_path(root, relative)
    isempty(relative) && error("empty manifest path")
    isabspath(relative) && error("absolute manifest path: $relative")
    normpath(relative) == relative || error("unnormalized manifest path: $relative")
    relative == "." && error("invalid manifest path: $relative")
    startswith(relative, "../") && error("manifest path escapes root: $relative")
    path = normpath(joinpath(root, relative))
    startswith(path, root * "/") || error("manifest path escapes root: $relative")
    return path
end

function parse_entries(arguments, first_index, count)
    entries = Dict{String, Tuple{Int, String}}()
    count == 0 && return entries
    for offset in 0:(count - 1)
        index = first_index + 3 * offset
        relative = arguments[index]
        validated_path(dataset_root, relative)
        haskey(entries, relative) && error("duplicate manifest path: $relative")
        entries[relative] = (parse(Int, arguments[index + 1]), arguments[index + 2])
    end
    return entries
end

function actual_entries(root)
    entries = Dict{String, Tuple{Int, String}}()
    for (directory, _, names) in walkdir(root)
        for name in names
            path = joinpath(directory, name)
            relative = relpath(path, root)
            digest = open(path, "r") do io
                bytes2hex(sha256(io))
            end
            entries[relative] = (filesize(path), digest)
        end
    end
    return entries
end

intended = parse_entries(ARGS, 7, intended_count)
sidecars = parse_entries(ARGS, 7 + 3 * intended_count, sidecar_count)
isempty(intersect(keys(intended), keys(sidecars))) || error("cleanup targets overlap intended files")
all(startswith(basename(path), "._") for path in keys(sidecars)) ||
    error("cleanup target is not an AppleDouble sidecar")

expected_before = merge(copy(intended), sidecars)
actual_entries(dataset_root) == expected_before ||
    error("remote dataset changed after the captured diagnostic; no files moved")

mkpath(quarantine_root)
for relative in sort!(collect(keys(sidecars)))
    source = validated_path(dataset_root, relative)
    destination = validated_path(quarantine_root, relative)
    mkpath(dirname(destination))
    mv(source, destination)
end

after = actual_entries(dataset_root)
after == intended || error("dataset manifest is not clean after quarantine")
paths = sort!(collect(keys(after)))
digest_lines = ["$path\t$(after[path][2])" for path in paths]
actual_directory_sha256 = bytes2hex(sha256(join(digest_lines, "\n")))
actual_directory_sha256 == expected_directory_sha256 ||
    error("dataset fingerprint mismatch after quarantine")

for path in paths
    println(path, "\t", after[path][1], "\t", after[path][2])
end
println("__DIRECTORY_SHA256__", "\t", actual_directory_sha256)
println("__QUARANTINE__", "\t", quarantine_root, "\t", length(sidecars))
"""
end

function _oos_sidecar_quarantine_arguments(
    julia_command::AbstractString,
    dataset_root::AbstractString,
    stage_root::AbstractString,
    quarantine_root::AbstractString,
    expected_directory_sha256::AbstractString,
    intended,
    sidecars,
)
    arguments = String[
        julia_command,
        "--startup-file=no",
        "--history-file=no",
        "--compiled-modules=no",
        "-e",
        strip(_oos_sidecar_quarantine_code()),
        dataset_root,
        stage_root,
        quarantine_root,
        expected_directory_sha256,
        string(length(intended)),
        string(length(sidecars)),
    ]
    for entries in (intended, sidecars)
        for path in sort!(collect(keys(entries)))
            bytes, digest = entries[path]
            append!(arguments, [path, string(bytes), digest])
        end
    end
    return arguments
end

"""
    prepare_oos_solstorm_sidecar_quarantine(
        staging_plan_file,
        remote_preflight_file,
        local_manifest_file,
        remote_manifest_file;
        output_file = joinpath(dirname(staging_plan_file), "sidecar_quarantine.yaml"),
        julia_command = "julia",
    )

Prepare an evidence-bound recovery plan that moves only proven macOS
AppleDouble sidecars out of an isolated Solstorm dataset and into a recoverable
quarantine directory. The generated command first requires the entire remote
file manifest to match captured evidence, then moves the exact sidecar paths,
and finally requires the intended dataset fingerprint. It never executes the
command, transfers files, submits a job, or starts a solver.
"""
function prepare_oos_solstorm_sidecar_quarantine(
    staging_plan_file::AbstractString,
    remote_preflight_file::AbstractString,
    local_manifest_file::AbstractString,
    remote_manifest_file::AbstractString;
    output_file::AbstractString = joinpath(
        dirname(staging_plan_file),
        "sidecar_quarantine.yaml",
    ),
    julia_command::AbstractString = "julia",
)
    target_staging = abspath(normpath(staging_plan_file))
    target_preflight = abspath(normpath(remote_preflight_file))
    target_local_manifest = abspath(normpath(local_manifest_file))
    target_remote_manifest = abspath(normpath(remote_manifest_file))
    staging = YAML.load_file(target_staging)
    preflight = YAML.load_file(target_preflight)
    get(staging, "kind", nothing) == "oos_solstorm_staging_plan" || throw(
        ArgumentError("Not an OOS Solstorm staging plan: $target_staging"),
    )
    get(preflight, "kind", nothing) == "oos_remote_staging_preflight" || throw(
        ArgumentError("Not OOS remote preflight evidence: $target_preflight"),
    )
    get(preflight, "status", nothing) == "blocked" || throw(ArgumentError(
        "Remote preflight must be blocked before preparing sidecar quarantine",
    ))
    abspath(normpath(string(preflight["staging_plan"]))) == target_staging || throw(
        ArgumentError("Remote preflight refers to a different staging plan"),
    )
    preflight["remote"]["stage_root"] == staging["remote"]["stage_root"] || throw(
        ArgumentError("Remote preflight and staging plan use different stage roots"),
    )
    failure = preflight["failure"]
    get(failure, "attempt", nothing) == 3 || throw(ArgumentError(
        "Sidecar quarantine requires the recorded third validation attempt",
    ))
    get(failure, "dataset_checksum_passed", true) == false || throw(ArgumentError(
        "Sidecar quarantine requires a recorded dataset checksum failure",
    ))
    diagnostic = preflight["dataset_diagnostic"]
    get(diagnostic, "status", nothing) == "root_cause_identified" || throw(
        ArgumentError("Dataset diagnostic has not identified the root cause"),
    )
    get(preflight["safety"], "remote_files_deleted", true) == false || throw(
        ArgumentError("Remote files were already deleted after the diagnostic"),
    )
    get(preflight["safety"], "qsub_executed", true) == false || throw(
        ArgumentError("Cannot prepare quarantine after qsub execution"),
    )
    get(preflight["safety"], "solver_started", true) == false || throw(
        ArgumentError("Cannot prepare quarantine after a solver started"),
    )
    _oos_sha256_file(target_local_manifest) == diagnostic["local_manifest_sha256"] ||
        throw(ArgumentError("Local dataset manifest does not match diagnostic evidence"))
    _oos_sha256_file(target_remote_manifest) == diagnostic["remote_manifest_sha256"] ||
        throw(ArgumentError("Remote dataset manifest does not match diagnostic evidence"))

    intended, local_directory_sha256 = _load_oos_file_manifest(target_local_manifest)
    remote, remote_directory_sha256 = _load_oos_file_manifest(target_remote_manifest)
    local_directory_sha256 === nothing || throw(ArgumentError(
        "Local expected manifest must not contain a remote directory digest",
    ))
    expected_directory_sha256 = staging["source"]["dataset"]["sha256"]
    _oos_manifest_directory_sha256(intended) == expected_directory_sha256 || throw(
        ArgumentError("Local manifest does not reproduce the planned dataset fingerprint"),
    )
    remote_directory_sha256 == diagnostic["remote_directory_sha256"] || throw(
        ArgumentError("Remote manifest directory digest differs from diagnostic evidence"),
    )
    missing = setdiff(keys(intended), keys(remote))
    changed = [path for path in intersect(keys(intended), keys(remote)) if
               intended[path] != remote[path]]
    sidecar_paths = setdiff(keys(remote), keys(intended))
    isempty(missing) || throw(ArgumentError("Remote manifest is missing intended files"))
    isempty(changed) || throw(ArgumentError("Remote manifest has changed intended files"))
    length(sidecar_paths) == diagnostic["extra_files"] || throw(ArgumentError(
        "Remote manifest sidecar count differs from diagnostic evidence",
    ))
    all(startswith(basename(path), "._") for path in sidecar_paths) || throw(
        ArgumentError("Remote manifest contains an unexpected non-sidecar file"),
    )
    sidecars = Dict(path => remote[path] for path in sidecar_paths)
    expected_sidecar = (
        Int(diagnostic["extra_file_bytes_each"]),
        string(diagnostic["extra_file_sha256"]),
    )
    all(metadata == expected_sidecar for metadata in values(sidecars)) || throw(
        ArgumentError("One or more remote sidecars differ from diagnostic evidence"),
    )

    stage_root = staging["remote"]["stage_root"]
    dataset_root = staging["remote"]["dataset"]
    quarantine_root = joinpath(
        stage_root,
        "artifacts",
        "appledouble_quarantine_attempt3",
    )
    startswith(dataset_root, "$stage_root/") || throw(ArgumentError(
        "Remote dataset is outside the isolated stage",
    ))
    startswith(quarantine_root, "$stage_root/") || throw(ArgumentError(
        "Quarantine is outside the isolated stage",
    ))
    arguments = _oos_sidecar_quarantine_arguments(
        julia_command,
        dataset_root,
        stage_root,
        quarantine_root,
        expected_directory_sha256,
        intended,
        sidecars,
    )
    remote_shell = _oos_solstorm_julia_bootstrap(julia_command) * "\n" *
                   _oos_command_display(staging["remote"]["project_dir"], arguments)
    remote_target = "$(staging["remote"]["user"])@$(staging["remote"]["host"])"
    command = _oos_staging_command(
        "remote_recover",
        "Quarantine exact AppleDouble sidecars and verify the clean dataset",
        ["ssh", "-o", "BatchMode=yes", remote_target, remote_shell],
    )
    occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", command["display"]) && throw(
        ArgumentError("Sidecar quarantine command unexpectedly contains qsub"),
    )

    targets = [
        Dict{String, Any}(
            "relative_path" => path,
            "remote_path" => joinpath(dataset_root, path),
            "quarantine_path" => joinpath(quarantine_root, path),
            "bytes" => sidecars[path][1],
            "sha256" => sidecars[path][2],
        ) for path in sort!(collect(keys(sidecars)))
    ]
    plan = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_appledouble_quarantine_plan",
        "status" => "ready",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "requires_explicit_remote_approval" => true,
        "source" => Dict{String, Any}(
            "staging_plan" => target_staging,
            "staging_plan_sha256" => _oos_sha256_file(target_staging),
            "remote_preflight" => target_preflight,
            "remote_preflight_sha256" => _oos_sha256_file(target_preflight),
            "local_manifest" => target_local_manifest,
            "local_manifest_sha256" => _oos_sha256_file(target_local_manifest),
            "remote_manifest" => target_remote_manifest,
            "remote_manifest_sha256" => _oos_sha256_file(target_remote_manifest),
            "expected_dataset_sha256" => expected_directory_sha256,
            "captured_remote_dataset_sha256" => remote_directory_sha256,
        ),
        "remote" => Dict{String, Any}(
            "account" => remote_target,
            "stage_root" => stage_root,
            "dataset" => dataset_root,
            "quarantine" => quarantine_root,
        ),
        "safety" => Dict{String, Any}(
            "exact_target_count" => length(targets),
            "uses_wildcards" => false,
            "pre_move_full_manifest_match_required" => true,
            "post_move_expected_manifest_required" => true,
            "post_move_expected_fingerprint_required" => true,
            "files_deleted" => false,
            "recoverable_quarantine" => true,
            "retransfers_files" => false,
            "submits_scheduler_job" => false,
            "starts_solver" => false,
        ),
        "targets" => targets,
        "commands" => [command],
    )
    target_output = abspath(normpath(output_file))
    target_output in (
        target_staging,
        target_preflight,
        target_local_manifest,
        target_remote_manifest,
    ) && throw(ArgumentError("Quarantine plan cannot overwrite source evidence"))
    _write_oos_experiment_manifest(target_output, plan)
    return target_output
end

function _validate_oos_quarantine_execution(
    quarantine_plan,
    quarantine_execution,
    quarantine_plan_file::AbstractString,
)
    recorded_plan = abspath(normpath(string(quarantine_execution["plan"])))
    recorded_plan == quarantine_plan_file || throw(ArgumentError(
        "Quarantine execution refers to a different recovery plan",
    ))
    _oos_sha256_file(quarantine_plan_file) == quarantine_execution["plan_sha256"] ||
        throw(ArgumentError("Quarantine plan changed after execution"))
    get(quarantine_execution, "success", false) == true || throw(ArgumentError(
        "Quarantine execution was not successful",
    ))
    get(quarantine_execution, "exit_code", nothing) == 0 || throw(ArgumentError(
        "Quarantine execution did not exit successfully",
    ))
    get(quarantine_execution, "command_count", nothing) == 1 || throw(ArgumentError(
        "Quarantine execution must contain exactly one command",
    ))
    get(quarantine_execution, "target_count", nothing) ==
    length(quarantine_plan["targets"]) || throw(ArgumentError(
        "Quarantine execution target count differs from its plan",
    ))
    for key in ("qsub_executed", "runner_executed", "solver_started", "files_deleted")
        get(quarantine_execution, key, true) == false || throw(ArgumentError(
            "Unsafe quarantine execution evidence: $key",
        ))
    end

    stdout_file = abspath(normpath(string(quarantine_execution["stdout"])))
    stderr_file = abspath(normpath(string(quarantine_execution["stderr"])))
    for (label, path, digest) in (
        ("stdout", stdout_file, quarantine_execution["stdout_sha256"]),
        ("stderr", stderr_file, quarantine_execution["stderr_sha256"]),
    )
        isfile(path) || throw(ArgumentError("Quarantine $label evidence is missing: $path"))
        _oos_sha256_file(path) == digest || throw(ArgumentError(
            "Quarantine $label evidence has changed",
        ))
    end
    isempty(read(stderr_file, String)) || throw(ArgumentError(
        "Quarantine execution stderr is not empty",
    ))

    local_manifest_file = abspath(normpath(string(
        quarantine_plan["source"]["local_manifest"],
    )))
    _oos_sha256_file(local_manifest_file) ==
    quarantine_plan["source"]["local_manifest_sha256"] || throw(ArgumentError(
        "Expected local manifest changed after quarantine planning",
    ))
    intended, directory_digest = _load_oos_file_manifest(local_manifest_file)
    directory_digest === nothing || throw(ArgumentError(
        "Expected local manifest unexpectedly contains a directory digest",
    ))
    expected_digest = quarantine_plan["source"]["expected_dataset_sha256"]
    _oos_manifest_directory_sha256(intended) == expected_digest || throw(ArgumentError(
        "Expected local manifest does not reproduce the dataset fingerprint",
    ))
    expected_lines = [
        "$path\t$(intended[path][1])\t$(intended[path][2])" for
        path in sort!(collect(keys(intended)))
    ]
    push!(expected_lines, "__DIRECTORY_SHA256__\t$expected_digest")
    quarantine_root = quarantine_plan["remote"]["quarantine"]
    target_count = length(quarantine_plan["targets"])
    push!(expected_lines, "__QUARANTINE__\t$quarantine_root\t$target_count")
    readlines(stdout_file) == expected_lines || throw(ArgumentError(
        "Quarantine stdout does not prove the exact clean dataset manifest",
    ))
    return expected_digest, stdout_file, stderr_file
end

"""
    prepare_oos_solstorm_recovered_validation(
        staging_plan_file,
        remote_preflight_file,
        quarantine_plan_file,
        quarantine_execution_file;
        output_file = joinpath(dirname(staging_plan_file), "recovered_validation.yaml"),
        julia_command = "julia",
    )

Prepare a one-command dry-run plan that retries original staging command 13
after an exact, successful AppleDouble quarantine. The plan requires immutable
staging, failure, quarantine, output, and clean-manifest evidence. It never
executes SSH, prepares the queue or SGE script, submits a job, or starts a
solver.
"""
function prepare_oos_solstorm_recovered_validation(
    staging_plan_file::AbstractString,
    remote_preflight_file::AbstractString,
    quarantine_plan_file::AbstractString,
    quarantine_execution_file::AbstractString;
    output_file::AbstractString = joinpath(
        dirname(staging_plan_file),
        "recovered_validation.yaml",
    ),
    julia_command::AbstractString = "julia",
)
    targets = abspath.(normpath.((
        staging_plan_file,
        remote_preflight_file,
        quarantine_plan_file,
        quarantine_execution_file,
    )))
    all(isfile, targets) || throw(ArgumentError(
        "Recovered validation requires all four source-evidence files",
    ))
    target_staging, target_preflight, target_quarantine, target_execution = targets
    isempty(strip(julia_command)) && throw(ArgumentError("julia_command cannot be empty"))
    staging = YAML.load_file(target_staging)
    preflight = YAML.load_file(target_preflight)
    quarantine = YAML.load_file(target_quarantine)
    execution = YAML.load_file(target_execution)

    get(staging, "kind", nothing) == "oos_solstorm_staging_plan" || throw(
        ArgumentError("Not an OOS Solstorm staging plan: $target_staging"),
    )
    get(preflight, "kind", nothing) == "oos_remote_staging_preflight" || throw(
        ArgumentError("Not OOS remote staging preflight evidence: $target_preflight"),
    )
    get(preflight, "status", nothing) == "blocked" || throw(ArgumentError(
        "Remote preflight must record the blocked dataset-validation state",
    ))
    get(quarantine, "kind", nothing) == "oos_solstorm_appledouble_quarantine_plan" ||
        throw(ArgumentError("Not an OOS AppleDouble quarantine plan"))
    get(execution, "kind", nothing) ==
    "oos_solstorm_appledouble_quarantine_execution" || throw(ArgumentError(
        "Not OOS AppleDouble quarantine execution evidence",
    ))
    abspath(normpath(string(preflight["staging_plan"]))) == target_staging || throw(
        ArgumentError("Remote preflight refers to a different staging plan"),
    )
    quarantine["source"]["staging_plan"] == target_staging || throw(ArgumentError(
        "Quarantine plan refers to a different staging plan",
    ))
    quarantine["source"]["remote_preflight"] == target_preflight || throw(ArgumentError(
        "Quarantine plan refers to different remote preflight evidence",
    ))
    _oos_sha256_file(target_staging) == quarantine["source"]["staging_plan_sha256"] ||
        throw(ArgumentError("Staging plan changed after quarantine planning"))
    _oos_sha256_file(target_preflight) ==
    quarantine["source"]["remote_preflight_sha256"] || throw(ArgumentError(
        "Remote preflight changed after quarantine planning",
    ))
    staging["remote"]["stage_root"] == quarantine["remote"]["stage_root"] || throw(
        ArgumentError("Staging and quarantine plans use different remote stages"),
    )

    evidence_commands = preflight["commands"]
    Set(Int.(evidence_commands["completed"])) == Set(3:12) || throw(ArgumentError(
        "Recovered validation requires staging commands 3 through 12 complete",
    ))
    Int.(evidence_commands["attempted_and_failed"]) == [13] || throw(ArgumentError(
        "Recovered validation requires command 13 as the only failed command",
    ))
    Int.(evidence_commands["not_attempted"]) == [14, 15] || throw(ArgumentError(
        "Recovered validation requires commands 14 and 15 unattempted",
    ))
    get(preflight["transfer"], "archive_hashes_match", false) == true || throw(
        ArgumentError("Remote archive hashes were not verified"),
    )
    get(preflight["transfer"], "archives_extracted", false) == true || throw(
        ArgumentError("Remote archives were not recorded as extracted"),
    )
    failure = preflight["failure"]
    get(failure, "command_index", nothing) == 13 &&
    get(failure, "attempt", nothing) == 3 &&
    get(failure, "dataset_checksum_passed", true) == false || throw(ArgumentError(
        "Recovered validation requires the recorded attempt-3 dataset failure",
    ))
    for key in ("qsub_executed", "solver_started", "remote_files_deleted")
        get(preflight["safety"], key, true) == false || throw(ArgumentError(
            "Unsafe remote preflight evidence: $key",
        ))
    end
    expected_digest, stdout_file, stderr_file = _validate_oos_quarantine_execution(
        quarantine,
        execution,
        target_quarantine,
    )

    commands = staging["commands"]
    length(commands) >= 15 || throw(ArgumentError(
        "Staging plan does not contain commands 13 through 15",
    ))
    commands[13]["phase"] == "remote_validate" || throw(ArgumentError(
        "Staging command 13 is not remote validation",
    ))
    command = _oos_resume_command(
        commands[13],
        13,
        staging["remote"]["project_dir"],
        julia_command,
    )
    expected_target = "$(staging["remote"]["user"])@$(staging["remote"]["host"])"
    command["argv"][4] == expected_target || throw(ArgumentError(
        "Recovered validation targets an unexpected remote account",
    ))
    display = command["display"]
    for forbidden in (
        "prepare_oos_execution_queue.jl",
        "prepare_oos_sge_job.jl",
        "run_julia_empire",
        "Gurobi.Optimizer",
        "scp ",
    )
        !occursin(forbidden, display) || throw(ArgumentError(
            "Recovered validation contains forbidden action: $forbidden",
        ))
    end

    recovered = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_recovered_validation_plan",
        "status" => "ready",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "requires_explicit_remote_approval" => true,
        "source" => Dict{String, Any}(
            "staging_plan" => target_staging,
            "staging_plan_sha256" => _oos_sha256_file(target_staging),
            "remote_preflight" => target_preflight,
            "remote_preflight_sha256" => _oos_sha256_file(target_preflight),
            "quarantine_plan" => target_quarantine,
            "quarantine_plan_sha256" => _oos_sha256_file(target_quarantine),
            "quarantine_execution" => target_execution,
            "quarantine_execution_sha256" => _oos_sha256_file(target_execution),
            "quarantine_stdout" => stdout_file,
            "quarantine_stdout_sha256" => execution["stdout_sha256"],
            "quarantine_stderr" => stderr_file,
            "quarantine_stderr_sha256" => execution["stderr_sha256"],
            "expected_dataset_sha256" => expected_digest,
            "failed_attempt" => 3,
        ),
        "remote" => deepcopy(staging["remote"]),
        "safety" => Dict{String, Any}(
            "original_command_index" => 13,
            "validates_staged_inputs_only" => true,
            "recreates_remote_stage" => false,
            "retransfers_files" => false,
            "prepares_execution_queue" => false,
            "prepares_sge_script" => false,
            "submits_scheduler_job" => false,
            "starts_runner" => false,
            "starts_solver" => false,
        ),
        "commands" => [command],
    )
    target_output = abspath(normpath(output_file))
    target_output in targets && throw(ArgumentError(
        "Recovered validation plan cannot overwrite source evidence",
    ))
    _write_oos_experiment_manifest(target_output, recovered)
    return target_output
end
