const _OOS_SOLSTORM_HOST = "solstorm.iot.ntnu.no"

function _oos_git_read(project_dir::AbstractString, arguments)
    command = Cmd(vcat(["git", "-C", project_dir], String.(arguments)))
    try
        return strip(read(pipeline(command; stderr = devnull), String))
    catch error
        throw(ArgumentError(
            "Git inspection failed for $(join(command.exec, " ")): $(sprint(showerror, error))",
        ))
    end
end

function _oos_git_lines(project_dir::AbstractString, arguments)
    output = _oos_git_read(project_dir, arguments)
    return isempty(output) ? String[] : split(output, '\n')
end

function _validate_oos_remote_component(
    value::AbstractString,
    name::AbstractString,
    pattern,
)
    isempty(strip(value)) && throw(ArgumentError("$name cannot be empty"))
    occursin(pattern, value) || throw(ArgumentError("Unsupported $name: $value"))
    return value
end

function _validate_oos_remote_root(path::AbstractString)
    isabspath(path) || throw(ArgumentError(
        "Solstorm remote root must be an absolute path: $path",
    ))
    normalized = normpath(path)
    normalized != "/" || throw(ArgumentError("Solstorm remote root cannot be /"))
    occursin(r"^/[A-Za-z0-9._/-]+$", normalized) || throw(ArgumentError(
        "Solstorm remote root contains unsupported characters: $path",
    ))
    return normalized
end

function _oos_staging_component(value::AbstractString)
    component = replace(value, r"[^A-Za-z0-9_-]+" => "_")
    component = strip(component, '_')
    return isempty(component) ? "oos" : component
end

function _oos_staging_command(
    phase::AbstractString,
    purpose::AbstractString,
    arguments;
    working_directory = nothing,
)
    argv = String.(arguments)
    display = working_directory === nothing ?
              join((_oos_shell_quote(argument) for argument in argv), " ") :
              _oos_command_display(string(working_directory), argv)
    return Dict{String, Any}(
        "phase" => phase,
        "purpose" => purpose,
        "working_directory" => working_directory,
        "argv" => argv,
        "display" => display,
        "executed" => false,
    )
end

function _oos_remote_shell_command(
    working_directory::AbstractString,
    arguments,
    julia_command::AbstractString,
)
    command = _oos_command_display(working_directory, String.(arguments))
    return join((
        _oos_solstorm_julia_bootstrap(julia_command),
        _oos_solstorm_project_bootstrap(working_directory, julia_command),
        command,
    ), "\n")
end

function _oos_dataset_archive_arguments(
    source_dir::AbstractString,
    archive_file::AbstractString;
    is_apple::Bool = Sys.isapple(),
)
    arguments = String[]
    if is_apple
        append!(arguments, [
            "env",
            "COPYFILE_DISABLE=1",
            "tar",
            "--no-xattrs",
            "--no-mac-metadata",
            "--no-fflags",
        ])
    else
        push!(arguments, "tar")
    end
    append!(arguments, ["-czf", archive_file, "-C", source_dir, "."])
    return arguments
end

function _oos_staging_file_metadata(path::AbstractString; relative_to = dirname(path))
    return Dict{String, Any}(
        "name" => basename(path),
        "path" => abspath(normpath(path)),
        "relative_path" => relpath(path, relative_to),
        "bytes" => filesize(path),
        "sha256" => _oos_sha256_file(path),
    )
end

function _oos_staging_tree_files(tree_dir::AbstractString)
    paths = String[joinpath(tree_dir, "metadata.yaml")]
    append!(
        paths,
        joinpath(tree_dir, "ScenarioData", filename) for filename in _OOS_TREE_FILENAMES
    )
    return [_oos_staging_file_metadata(path; relative_to = tree_dir) for path in paths]
end

function _oos_digest_from_file_metadata(files)
    ordered = sort(collect(files); by = entry -> entry["relative_path"])
    input = join(
        ("$(entry["relative_path"])\t$(entry["sha256"])" for entry in ordered),
        "\n",
    )
    return bytes2hex(sha256(input))
end

function _oos_remote_tree_metadata(
    source_metadata,
    source_metadata_sha256::AbstractString,
    source_tree::AbstractString,
    remote_tree::AbstractString,
    remote_dataset::AbstractString,
    remote_config::AbstractString,
)
    metadata = deepcopy(source_metadata)
    metadata["tree"] = "oos_tree1"
    metadata["tree_dir"] = remote_tree
    metadata["source_data_folder"] = remote_dataset
    metadata["source_config_file"] = remote_config
    metadata["staged_from_tree"] = source_tree
    metadata["staged_from_metadata_sha256"] = source_metadata_sha256
    return metadata
end

function _oos_remote_experiment_manifest(
    source_experiment,
    seed::Integer,
    remote_dataset::AbstractString,
    remote_config::AbstractString,
    remote_experiment::AbstractString,
)
    created_at = get(source_experiment, "created_at_utc", string(now(UTC), "Z"))
    remote_tree = joinpath(remote_experiment, "oos_tree1")
    return Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_tree_experiment",
        "status" => "complete",
        "created_at_utc" => created_at,
        "updated_at_utc" => created_at,
        "source_data_folder" => remote_dataset,
        "source_data_sha256" => source_experiment["source_data_sha256"],
        "source_config_file" => remote_config,
        "source_config_sha256" => source_experiment["source_config_sha256"],
        "input_format" => source_experiment["input_format"],
        "seed_start" => Int(seed),
        "num_trees" => 1,
        "trees" => Any[Dict{String, Any}(
            "index" => 1,
            "name" => "oos_tree1",
            "seed" => Int(seed),
            "path" => remote_tree,
            "status" => "complete",
            "metadata_file" => joinpath(remote_tree, "metadata.yaml"),
            "error" => nothing,
        )],
    )
end

function _write_oos_staging_yaml(path::AbstractString, value)
    _write_oos_experiment_manifest(path, value)
    return _oos_staging_file_metadata(path; relative_to = dirname(path))
end

"""
    prepare_oos_solstorm_staging(
        queue_file;
        remote_user,
        remote_root,
        remote_host = _OOS_SOLSTORM_HOST,
        job_index = nothing,
        output_dir = nothing,
        revision = "HEAD",
    )

Create a locally validated, one-tree Solstorm staging plan without executing
any command. The plan records source and remote paths, checksums, the resolved
Git revision, and exact archive/SSH/SCP/queue/SGE commands. It also creates
remote-path-adjusted tree and experiment metadata files for later transfer.

The repository archive is pinned to a committed Git revision. Code-related
working-tree changes therefore block execution of the plan until committed,
while unrelated changes are recorded but excluded from the archive. Returns
the absolute path to `staging.yaml`.
"""
function prepare_oos_solstorm_staging(
    queue_file::AbstractString;
    remote_user::AbstractString,
    remote_root::AbstractString,
    remote_host::AbstractString = _OOS_SOLSTORM_HOST,
    job_index = nothing,
    output_dir = nothing,
    revision::AbstractString = "HEAD",
)
    target_queue, queue = _load_oos_execution_queue(queue_file)
    _validate_oos_execution_queue_inputs(queue)
    user = _validate_oos_remote_component(
        remote_user,
        "Solstorm remote user",
        r"^[A-Za-z0-9._-]+$",
    )
    host = _validate_oos_remote_component(
        remote_host,
        "Solstorm remote host",
        r"^[A-Za-z0-9.-]+$",
    )
    root = _validate_oos_remote_root(remote_root)

    job = if job_index === nothing
        pending = findfirst(candidate -> candidate["status"] == "pending", queue["jobs"])
        pending === nothing && throw(ArgumentError("OOS execution queue has no pending job"))
        queue["jobs"][pending]
    else
        _oos_execution_job(queue, Int(job_index))
    end
    job["status"] == "pending" || throw(ArgumentError(
        "Only a pending OOS job can be staged: $(job["tree"])",
    ))

    project_dir = queue["runner"]["project_dir"]
    commit = _oos_git_read(project_dir, ["rev-parse", "--verify", "$(revision)^{commit}"])
    head_commit = _oos_git_read(project_dir, ["rev-parse", "--verify", "HEAD^{commit}"])
    git_tree = _oos_git_read(project_dir, ["rev-parse", "$(commit)^{tree}"])
    branch = _oos_git_read(project_dir, ["rev-parse", "--abbrev-ref", "HEAD"])
    dirty_entries = _oos_git_lines(
        project_dir,
        ["status", "--porcelain=v1", "--untracked-files=all"],
    )
    dirty_code_entries = _oos_git_lines(
        project_dir,
        [
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--",
            "Project.toml",
            "src",
            "scripts",
        ],
    )

    experiment_manifest = YAML.load_file(queue["experiment"]["manifest_file"])
    source_tree = job["scenario_tree"]
    source_tree_metadata_file = joinpath(source_tree, "metadata.yaml")
    source_tree_metadata = YAML.load_file(source_tree_metadata_file)
    source_tree_metadata_sha256 = _oos_sha256_file(source_tree_metadata_file)
    source_tree_files = _oos_staging_tree_files(source_tree)
    generation_config = abspath(normpath(experiment_manifest["source_config_file"]))
    isfile(generation_config) || throw(ArgumentError(
        "OOS generation config does not exist: $generation_config",
    ))
    generation_config_sha256 = _oos_sha256_file(generation_config)
    generation_config_sha256 == experiment_manifest["source_config_sha256"] || throw(
        ArgumentError("OOS generation config checksum has changed: $generation_config"),
    )

    plan_component = _oos_staging_component(
        "$(basename(dirname(target_queue)))_$(job["tree"])_$(commit[1:12])",
    )
    target_output = output_dir === nothing ?
                    joinpath(dirname(target_queue), "solstorm_staging", plan_component) :
                    abspath(normpath(string(output_dir)))
    mkpath(target_output)

    stage_root = joinpath(root, "stages", plan_component)
    remote_project = joinpath(stage_root, "project")
    remote_artifacts = joinpath(stage_root, "artifacts")
    remote_inputs = joinpath(stage_root, "inputs")
    remote_dataset = joinpath(remote_inputs, "dataset")
    remote_config_dir = joinpath(remote_inputs, "config")
    remote_config = joinpath(remote_config_dir, basename(queue["config"]["file"]))
    remote_generation_config = generation_config_sha256 == queue["config"]["sha256"] ?
                               remote_config :
                               joinpath(
        remote_config_dir,
        "generation_$(basename(generation_config))",
    )
    remote_experiment = joinpath(remote_inputs, "experiment")
    remote_tree = joinpath(remote_experiment, "oos_tree1")
    remote_scenario_dir = joinpath(remote_tree, "ScenarioData")
    remote_fixed = joinpath(remote_inputs, "fixed_investments")
    remote_fixed_output = joinpath(remote_fixed, "Output")
    remote_results = joinpath(stage_root, "results")
    remote_queue = joinpath(remote_experiment, _OOS_EXECUTION_MANIFEST)

    adjusted_tree_metadata = _oos_remote_tree_metadata(
        source_tree_metadata,
        source_tree_metadata_sha256,
        job["tree"],
        remote_tree,
        remote_dataset,
        remote_generation_config,
    )
    adjusted_tree_metadata_file = joinpath(target_output, "tree_metadata.remote.yaml")
    adjusted_tree_file =
        _write_oos_staging_yaml(adjusted_tree_metadata_file, adjusted_tree_metadata)

    adjusted_experiment = _oos_remote_experiment_manifest(
        experiment_manifest,
        job["seed"],
        remote_dataset,
        remote_generation_config,
        remote_experiment,
    )
    adjusted_experiment_file = joinpath(target_output, "experiment.remote.yaml")
    adjusted_experiment_metadata =
        _write_oos_staging_yaml(adjusted_experiment_file, adjusted_experiment)

    remote_tree_files = [
        merge(copy(entry), Dict("relative_path" => entry["relative_path"])) for
        entry in source_tree_files if entry["relative_path"] != "metadata.yaml"
    ]
    push!(remote_tree_files, merge(
        copy(adjusted_tree_file),
        Dict("relative_path" => "metadata.yaml"),
    ))
    remote_tree_sha256 = _oos_digest_from_file_metadata(remote_tree_files)

    local_repository_archive = joinpath(target_output, "repository_$(commit[1:12]).tar.gz")
    local_dataset_archive = joinpath(target_output, "dataset.tar.gz")
    remote_repository_archive = joinpath(remote_artifacts, basename(local_repository_archive))
    remote_dataset_archive = joinpath(remote_artifacts, basename(local_dataset_archive))
    remote_target = "$user@$host"

    commands = Dict{String, Any}[]
    push!(commands, _oos_staging_command(
        "local_prepare",
        "Create a clean repository archive pinned to the recorded revision",
        [
            "git",
            "-C",
            project_dir,
            "archive",
            "--format=tar.gz",
            "--output=$local_repository_archive",
            commit,
        ],
    ))
    push!(commands, _oos_staging_command(
        "local_prepare",
        "Create the dataset archive",
        _oos_dataset_archive_arguments(
            queue["dataset"]["folder"],
            local_dataset_archive,
        ),
    ))

    remote_directories = [
        remote_project,
        remote_artifacts,
        remote_dataset,
        remote_config_dir,
        remote_experiment,
        remote_scenario_dir,
        remote_fixed_output,
        remote_results,
    ]
    push!(commands, _oos_staging_command(
        "remote_prepare",
        "Create an isolated Solstorm staging workspace",
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            remote_target,
            join(["mkdir", "-p", (_oos_shell_quote(path) for path in remote_directories)...], " "),
        ],
    ))

    transfer_specs = [
        (local_repository_archive, remote_repository_archive, "Transfer repository archive"),
        (local_dataset_archive, remote_dataset_archive, "Transfer dataset archive"),
        (queue["config"]["file"], remote_config, "Transfer execution configuration"),
        (
            adjusted_experiment_file,
            joinpath(remote_experiment, "experiment.yaml"),
            "Transfer one-tree experiment manifest",
        ),
        (
            adjusted_tree_metadata_file,
            joinpath(remote_tree, "metadata.yaml"),
            "Transfer adjusted tree metadata",
        ),
    ]
    if generation_config_sha256 != queue["config"]["sha256"]
        push!(transfer_specs, (
            generation_config,
            remote_generation_config,
            "Transfer scenario-generation configuration",
        ))
    end
    for (source, destination, purpose) in transfer_specs
        push!(commands, _oos_staging_command(
            "transfer",
            purpose,
            ["scp", "-o", "BatchMode=yes", source, "$remote_target:$destination"],
        ))
    end
    scenario_files = [
        entry["path"] for entry in source_tree_files if
        startswith(entry["relative_path"], "ScenarioData/")
    ]
    push!(commands, _oos_staging_command(
        "transfer",
        "Transfer selected OOS scenario files",
        [
            "scp",
            "-o",
            "BatchMode=yes",
            scenario_files...,
            "$remote_target:$remote_scenario_dir/",
        ],
    ))
    fixed_files = queue["fixed_investments"]["files"]
    push!(commands, _oos_staging_command(
        "transfer",
        "Transfer the required fixed-investment tables",
        [
            "scp",
            "-o",
            "BatchMode=yes",
            (entry["path"] for entry in fixed_files)...,
            "$remote_target:$remote_fixed_output/",
        ],
    ))

    extract_command = join(
        [
            "tar -xzf $(_oos_shell_quote(remote_repository_archive)) -C $(_oos_shell_quote(remote_project))",
            "tar -xzf $(_oos_shell_quote(remote_dataset_archive)) -C $(_oos_shell_quote(remote_dataset))",
        ],
        " && ",
    )
    push!(commands, _oos_staging_command(
        "remote_unpack",
        "Extract repository and dataset archives",
        ["ssh", "-o", "BatchMode=yes", remote_target, extract_command],
    ))

    verification_code = """
using OpenEMPIRE
OpenEMPIRE._oos_code_sha256(ARGS[1]) == ARGS[2] || error("repository code checksum mismatch")
OpenEMPIRE._oos_directory_sha256(ARGS[3]) == ARGS[4] || error("dataset checksum mismatch")
OpenEMPIRE._oos_sha256_file(ARGS[5]) == ARGS[6] || error("execution config checksum mismatch")
OpenEMPIRE._oos_sha256_file(ARGS[7]) == ARGS[8] || error("generation config checksum mismatch")
OpenEMPIRE._oos_directory_sha256(ARGS[9]) == ARGS[10] || error("OOS tree checksum mismatch")
OpenEMPIRE._oos_fixed_investment_metadata(ARGS[11])["sha256"] == ARGS[12] ||
    error("fixed-investment checksum mismatch")
"""
    verification_arguments = [
        queue["runner"]["julia_command"],
        "--project=$remote_project",
        "-e",
        strip(verification_code),
        remote_project,
        queue["runner"]["code_sha256"],
        remote_dataset,
        queue["dataset"]["sha256"],
        remote_config,
        queue["config"]["sha256"],
        remote_generation_config,
        generation_config_sha256,
        remote_tree,
        remote_tree_sha256,
        remote_fixed,
        queue["fixed_investments"]["sha256"],
    ]
    push!(commands, _oos_staging_command(
        "remote_validate",
        "Verify all staged checksums before preparing a queue",
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            remote_target,
            _oos_remote_shell_command(
                remote_project,
                verification_arguments,
                queue["runner"]["julia_command"],
            ),
        ],
    ))

    queue_arguments = [
        queue["runner"]["julia_command"],
        "--project=$remote_project",
        joinpath(remote_project, "scripts", "prepare_oos_execution_queue.jl"),
        remote_dataset,
        "--config=$remote_config",
        "--format=$(queue["input_format"])",
        "--solver=$(queue["solver"])",
        "--experiment=$remote_experiment",
        "--fixed-investment-dir=$remote_fixed",
        "--results=$remote_results",
        "--queue-file=$remote_queue",
        "--julia-command=$(queue["runner"]["julia_command"])",
        "--resume=true",
    ]
    push!(commands, _oos_staging_command(
        "remote_configure",
        "Prepare the one-tree execution queue on the Solstorm filesystem",
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            remote_target,
            _oos_remote_shell_command(
                remote_project,
                queue_arguments,
                queue["runner"]["julia_command"],
            ),
        ],
    ))
    sge_arguments = [
        queue["runner"]["julia_command"],
        "--project=$remote_project",
        joinpath(remote_project, "scripts", "prepare_oos_sge_job.jl"),
        "--queue=$remote_queue",
    ]
    push!(commands, _oos_staging_command(
        "remote_configure",
        "Prepare the SGE script without submitting it",
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            remote_target,
            _oos_remote_shell_command(
                remote_project,
                sge_arguments,
                queue["runner"]["julia_command"],
            ),
        ],
    ))

    blockers = String[]
    commit != head_commit && push!(
        blockers,
        "Selected revision differs from HEAD used to prepare the local execution queue",
    )
    !isempty(dirty_code_entries) && push!(
        blockers,
        "Code-related working-tree changes are excluded from the revision-pinned archive",
    )
    plan = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_staging_plan",
        "status" => isempty(blockers) ? "ready" : "blocked",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "blockers" => blockers,
        "source" => Dict{String, Any}(
            "queue_file" => target_queue,
            "queue_sha256" => _oos_sha256_file(target_queue),
            "repository" => Dict{String, Any}(
                "project_dir" => project_dir,
                "branch" => branch,
                "revision_requested" => revision,
                "commit" => commit,
                "head_commit" => head_commit,
                "git_tree" => git_tree,
                "code_sha256" => queue["runner"]["code_sha256"],
                "dirty" => !isempty(dirty_entries),
                "dirty_entries" => dirty_entries,
                "dirty_code_entries" => dirty_code_entries,
                "archive_mode" => "git_archive_committed_revision",
            ),
            "dataset" => Dict{String, Any}(
                "path" => queue["dataset"]["folder"],
                "sha256" => queue["dataset"]["sha256"],
            ),
            "config" => Dict{String, Any}(
                "path" => queue["config"]["file"],
                "sha256" => queue["config"]["sha256"],
            ),
            "generation_config" => Dict{String, Any}(
                "path" => generation_config,
                "sha256" => generation_config_sha256,
            ),
            "selected_job" => Dict{String, Any}(
                "index" => job["index"],
                "tree" => job["tree"],
                "seed" => job["seed"],
                "status" => job["status"],
                "scenario_tree" => source_tree,
                "scenario_tree_sha256" => _oos_directory_sha256(source_tree),
                "metadata_sha256" => source_tree_metadata_sha256,
                "files" => source_tree_files,
            ),
            "fixed_investments" => queue["fixed_investments"],
        ),
        "generated_files" => Dict{String, Any}(
            "remote_tree_metadata" => adjusted_tree_file,
            "remote_experiment_manifest" => adjusted_experiment_metadata,
            "repository_archive" => Dict{String, Any}(
                "path" => local_repository_archive,
                "exists" => isfile(local_repository_archive),
                "content_identity" => git_tree,
            ),
            "dataset_archive" => Dict{String, Any}(
                "path" => local_dataset_archive,
                "exists" => isfile(local_dataset_archive),
                "content_sha256" => queue["dataset"]["sha256"],
            ),
        ),
        "remote" => Dict{String, Any}(
            "user" => user,
            "host" => host,
            "root" => root,
            "stage_root" => stage_root,
            "project_dir" => remote_project,
            "dataset" => remote_dataset,
            "config" => remote_config,
            "generation_config" => remote_generation_config,
            "experiment" => remote_experiment,
            "tree" => remote_tree,
            "tree_sha256" => remote_tree_sha256,
            "fixed_investments" => remote_fixed,
            "results" => remote_results,
            "execution_queue" => remote_queue,
            "sge_script" => joinpath(remote_experiment, "sge", "oos_tree1.sge.sh"),
        ),
        "acceptance_criteria" => Dict{String, Any}(
            "isolated_remote_workspace" => true,
            "one_tree_only" => true,
            "fixed_investment_file_count" => length(fixed_files),
            "checksums_verified_before_queue_preparation" => true,
            "scheduler_submission_allowed" => false,
        ),
        "commands" => commands,
    )
    plan_file = joinpath(target_output, "staging.yaml")
    _write_oos_experiment_manifest(plan_file, plan)
    return plan_file
end

function _oos_resume_command(
    original,
    command_index::Integer,
    project_dir::AbstractString,
    julia_command::AbstractString,
)
    get(original, "executed", false) && throw(ArgumentError(
        "Cannot resume a staging command recorded as executed: $command_index",
    ))
    argv = String.(original["argv"])
    length(argv) == 5 && argv[1:3] == ["ssh", "-o", "BatchMode=yes"] || throw(
        ArgumentError(
            "Resume command $command_index is not a supported non-interactive SSH command",
        ),
    )
    has_julia_bootstrap = occursin(_OOS_SOLSTORM_JULIA_BOOTSTRAP_MARKER, argv[5])
    has_project_bootstrap = occursin(_OOS_SOLSTORM_PROJECT_BOOTSTRAP_MARKER, argv[5])
    has_julia_bootstrap == has_project_bootstrap || throw(ArgumentError(
        "Resume command $command_index has an incomplete Solstorm bootstrap",
    ))
    if !has_julia_bootstrap
        argv[5] = join((
            _oos_solstorm_julia_bootstrap(julia_command),
            _oos_solstorm_project_bootstrap(project_dir, julia_command),
            argv[5],
        ), "\n")
    end
    occursin(r"(^|[[:space:]])qsub([[:space:]]|$)", argv[5]) && throw(ArgumentError(
        "Resume command $command_index unexpectedly contains qsub",
    ))
    resumed = _oos_staging_command(
        "remote_resume",
        original["purpose"],
        argv,
    )
    resumed["original_command_index"] = Int(command_index)
    return resumed
end

"""
    prepare_oos_solstorm_resume(
        staging_plan_file,
        remote_preflight_file;
        output_file = joinpath(dirname(staging_plan_file), "resume.yaml"),
        julia_command = "julia",
    )

Create a dry-run plan that retries only failed Solstorm staging command 13.
The evidence must show commands 3 through 12 complete, command 13 failed before
checksum validation, and commands 14 and 15 were not attempted. The generated
command adds the shared Julia and project-dependency bootstraps and cannot
transfer files, recreate the stage, submit with `qsub`, or start a solver. No
remote command is executed.
"""
function prepare_oos_solstorm_resume(
    staging_plan_file::AbstractString,
    remote_preflight_file::AbstractString;
    output_file::AbstractString = joinpath(dirname(staging_plan_file), "resume.yaml"),
    julia_command::AbstractString = "julia",
)
    target_plan = abspath(normpath(staging_plan_file))
    target_preflight = abspath(normpath(remote_preflight_file))
    isfile(target_plan) || throw(ArgumentError("Staging plan does not exist: $target_plan"))
    isfile(target_preflight) || throw(ArgumentError(
        "Remote preflight evidence does not exist: $target_preflight",
    ))
    isempty(strip(julia_command)) && throw(ArgumentError("julia_command cannot be empty"))

    plan = YAML.load_file(target_plan)
    preflight = YAML.load_file(target_preflight)
    get(plan, "kind", nothing) == "oos_solstorm_staging_plan" || throw(ArgumentError(
        "Not an OOS Solstorm staging plan: $target_plan",
    ))
    get(preflight, "kind", nothing) == "oos_remote_staging_preflight" || throw(
        ArgumentError("Not OOS remote staging preflight evidence: $target_preflight"),
    )
    get(preflight, "status", nothing) == "blocked" || throw(ArgumentError(
        "Remote preflight must be blocked before preparing this resume plan",
    ))

    recorded_plan = abspath(normpath(string(preflight["staging_plan"])))
    recorded_plan == target_plan || throw(ArgumentError(
        "Remote preflight refers to a different staging plan: $recorded_plan",
    ))
    get(preflight["remote"], "stage_root", nothing) ==
    get(plan["remote"], "stage_root", nothing) || throw(ArgumentError(
        "Remote preflight and staging plan use different stage roots",
    ))

    evidence_commands = preflight["commands"]
    Set(Int.(evidence_commands["completed"])) == Set(3:12) || throw(ArgumentError(
        "Resume requires evidence that staging commands 3 through 12 completed",
    ))
    Int.(evidence_commands["attempted_and_failed"]) == [13] || throw(ArgumentError(
        "Resume requires command 13 as the only attempted and failed command",
    ))
    Int.(evidence_commands["not_attempted"]) == [14, 15] || throw(ArgumentError(
        "Resume requires commands 14 and 15 to be unattempted",
    ))
    failure = preflight["failure"]
    get(failure, "command_index", nothing) == 13 || throw(ArgumentError(
        "Remote preflight failure is not command 13",
    ))
    get(failure, "content_checksum_verification_started", true) == false || throw(
        ArgumentError("Checksum validation already started; automatic resume is unsafe"),
    )
    get(preflight["transfer"], "archive_hashes_match", false) == true || throw(
        ArgumentError("Remote archive hashes were not verified before the failure"),
    )
    get(preflight["transfer"], "archives_extracted", false) == true || throw(
        ArgumentError("Remote archives were not recorded as extracted"),
    )
    get(preflight["safety"], "qsub_executed", true) == false || throw(ArgumentError(
        "Cannot prepare a no-submit resume after qsub execution",
    ))
    get(preflight["safety"], "solver_started", true) == false || throw(ArgumentError(
        "Cannot prepare this resume after a solver started",
    ))

    commands = plan["commands"]
    length(commands) >= 15 || throw(ArgumentError(
        "Staging plan does not contain commands 13 through 15",
    ))
    commands[13]["phase"] == "remote_validate" || throw(ArgumentError(
        "Staging command 13 is not remote validation",
    ))
    resume_commands = [
        _oos_resume_command(
            commands[13],
            13,
            plan["remote"]["project_dir"],
            julia_command,
        ),
    ]
    all(command["argv"][1] == "ssh" for command in resume_commands) || throw(
        ArgumentError("Resume plan contains a non-SSH command"),
    )
    expected_target = "$(plan["remote"]["user"])@$(plan["remote"]["host"])"
    all(command["argv"][4] == expected_target for command in resume_commands) || throw(
        ArgumentError("Resume plan contains an unexpected remote account"),
    )

    resume = Dict{String, Any}(
        "schema_version" => 1,
        "kind" => "oos_solstorm_resume_plan",
        "status" => "ready",
        "created_at_utc" => string(now(UTC), "Z"),
        "dry_run" => true,
        "commands_executed" => 0,
        "requires_explicit_remote_approval" => true,
        "source" => Dict{String, Any}(
            "staging_plan" => target_plan,
            "staging_plan_sha256" => _oos_sha256_file(target_plan),
            "remote_preflight" => target_preflight,
            "remote_preflight_sha256" => _oos_sha256_file(target_preflight),
            "pinned_repository_commit" => plan["source"]["repository"]["commit"],
            "failed_command_index" => 13,
            "failed_attempt" => get(failure, "attempt", 1),
        ),
        "remote" => deepcopy(plan["remote"]),
        "safety" => Dict{String, Any}(
            "starts_at_original_command" => 13,
            "ends_at_original_command" => 13,
            "retries_only_failed_command" => true,
            "recreates_remote_stage" => false,
            "retransfers_files" => false,
            "submits_scheduler_job" => false,
            "starts_solver" => false,
        ),
        "commands" => resume_commands,
    )
    target_output = abspath(normpath(output_file))
    target_output in (target_plan, target_preflight) && throw(ArgumentError(
        "Resume output cannot overwrite its source evidence: $target_output",
    ))
    _write_oos_experiment_manifest(target_output, resume)
    return target_output
end
