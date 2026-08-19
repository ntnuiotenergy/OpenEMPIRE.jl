# Run Pipeline Branch Plan

This plan describes how to implement the run-pipeline improvements while keeping
the work usable during the internship and reviewable later.

The core idea is to keep two kinds of branches:

- clean feature branches for later PR review
- one combined `workbench` branch for actually running experiments now

## Branch Model

Use clean branches for isolated changes:

```text
torgrim/run-pipeline-doc
torgrim/run-manifest
torgrim/scheduler-cleanup
torgrim/stage-run-inputs
torgrim/runner-config-cleanup
torgrim/compare-runner
```

Use one combined branch for practical local/Solstorm work:

```text
torgrim/workbench
```

The clean branches should be reviewable one by one. The `workbench` branch is
allowed to contain several features merged together so experiments can continue
without waiting for PR review.

## Recommended Order

### 1. `torgrim/run-pipeline-doc`

Purpose: capture the design direction without changing behavior.

Expected changes:

- add `docs/run_pipeline_improvements.md`
- add this branch plan if useful

Review focus:

- Does the document match the actual workflow pain points?
- Is the proposed direction understandable to future contributors?
- Does it avoid promising implementation details that are not decided yet?

### 2. `torgrim/run-manifest`

Purpose: write a resolved manifest for every Julia run.

Expected changes:

- add helper functions in `scripts/run_julia_empire.jl`
- write `run_manifest.yaml` or `run_manifest.json` into each result directory
- include:
  - runtime name
  - git branch, commit, and dirty-state flag
  - dataset and staged/current data folder
  - config file path
  - resolved solver settings
  - seed and fixed-sample mode
  - sampling-key checksum when present
  - model dimensions after build
  - objective and termination status after solve
  - start/end timestamps

Suggested implementation shape:

```julia
function _git_info()
    return Dict(
        "commit" => _read_command(`git rev-parse HEAD`),
        "branch" => _read_command(`git rev-parse --abbrev-ref HEAD`),
        "dirty" => !isempty(strip(something(_read_command(`git status --short`), ""))),
    )
end
```

```julia
function _write_run_manifest(path, manifest)
    mkpath(dirname(path))
    YAML.write_file(path, manifest)
    return path
end
```

Review focus:

- Does the manifest contain enough information to reproduce/debug a run?
- Does it avoid changing model behavior?
- Does it handle generate-only and no-optimize runs?
- Does it behave sensibly when git commands fail, e.g. on copied HPC folders?

### 3. `torgrim/scheduler-cleanup`

Purpose: make Solstorm job submission less fragile.

Expected changes:

- update `scripts/run_empire_julia_basic_sge.sh`
- avoid selecting unavailable nodes such as nodes in `au` state
- either:
  - let SGE choose from the allowed high-memory node list, or
  - filter unavailable nodes before hard-pinning a hostname

Possible safer direction:

```bash
qsub \
    -l hostname="compute-4-51|compute-4-52|compute-4-55|compute-4-56" \
    -v JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",... \
    "$0" "$DATASET" "$CONFIG_FILE" "$INPUT_FORMAT"
```

Review focus:

- Does the script still work when run manually on Solstorm?
- Does it avoid selecting unavailable nodes?
- Are env vars still passed through correctly?
- Does the script remain understandable for non-expert users?

### 4. `torgrim/stage-run-inputs`

Purpose: stop Julia runs from mutating source datasets.

Expected changes:

- copy the selected dataset into the result directory before scenario generation
- copy the selected config into the result directory
- run the model using the staged input copy
- keep source folders such as `data/europe_v51` unchanged during runs

Target layout:

```text
results/julia_runs/<timestamp>_<dataset>/
  Input/
    csv/
    config.yaml
  output/
  summary.txt
  run_manifest.yaml
```

Suggested implementation shape:

```julia
function _stage_run_inputs(result_dir, data_folder, config_file)
    input_dir = joinpath(result_dir, "Input")
    staged_data = joinpath(input_dir, "csv")
    staged_config = joinpath(input_dir, "config.yaml")

    mkpath(input_dir)
    cp(data_folder, staged_data)
    cp(config_file, staged_config; force = true)

    return staged_data, staged_config
end
```

Review focus:

- Does scenario generation write only into staged input folders?
- Are archived input artifacts still correct?
- Does fixed-sample mode still find the sampling key?
- Does the run manifest point to the staged inputs and original sources clearly?

### 5. `torgrim/runner-config-cleanup`

Purpose: reduce scattered runner state.

Expected changes:

- introduce a small resolved run-spec object in `scripts/run_julia_empire.jl`
- parse CLI/config/env values once
- pass a resolved run spec into smaller helper functions
- reduce repeated local variables in `main`

Suggested implementation shape:

```julia
Base.@kwdef struct JuliaRunSpec
    dataset::String
    data_folder::String
    config_file::String
    input_format::Symbol
    solver_name::String
    seed::Int
    result_dir::String
    optimize::Bool
    generate_only::Bool
    fixed_sample::String
    optimizer
    optimizer_attributes::Tuple
    perf_enabled::Bool
end
```

Review focus:

- Is behavior unchanged compared with the previous runner?
- Are defaults preserved?
- Is the code easier to read?
- Are errors still clear when config/data paths are missing?

### 6. `torgrim/compare-runner`

Purpose: make Python/Julia comparison runs first-class.

Expected changes:

- add a script or command for launching matched Julia/Python runs
- validate or generate one shared sampling key
- ensure both runtimes use the same:
  - dataset
  - scenario sample
  - config values
  - solver settings
  - perf instrumentation
- record both job IDs and output paths

Possible interface:

```bash
empire-compare \
  --dataset europe_v51 \
  --config config/run_2045_3sce.yaml \
  --runtime julia,python \
  --fixed-sample \
  --seed 1 \
  --target solstorm \
  --perf
```

Review focus:

- Does the command make it hard to accidentally compare mismatched runs?
- Does it record enough metadata for later debugging?
- Does it keep Julia/Python-specific details isolated?
- Does it fail early when sampling keys or configs differ?

## Workbench Workflow

After each clean feature branch is committed, merge it into the workbench branch
for practical use.

Example:

```bash
git switch -c torgrim/run-manifest origin/main
# implement and commit run-manifest

git switch torgrim/workbench
git merge torgrim/run-manifest
```

If `torgrim/workbench` does not exist yet:

```bash
git switch -c torgrim/workbench origin/main
```

If North Sea functionality is needed in the workbench branch:

```bash
git switch torgrim/workbench
git merge torgrim/north-sea
```

The `workbench` branch is not intended to be a clean PR. It is a practical branch
for running experiments while supervisors are unavailable.

## Suggested Near-Term Strategy

Do first:

```text
1. torgrim/run-pipeline-doc
2. torgrim/run-manifest
3. torgrim/scheduler-cleanup
```

These are useful and relatively low risk.

Delay until North Sea and the current branch stack are more settled:

```text
4. torgrim/stage-run-inputs
5. torgrim/runner-config-cleanup
6. torgrim/compare-runner
```

Those touch more of the run/config surface and are more likely to conflict with
North Sea or other active work.

## Claude Review Checklist

When reviewing each implemented branch, check:

- Does the branch implement only the feature named in the branch?
- Are unrelated generated files, result files, logs, or config experiments excluded?
- Does the implementation preserve existing behavior unless the branch explicitly
  changes it?
- Are run artifacts written into result directories rather than source config/data
  folders?
- Are errors understandable to someone who knows basic Git/shell but is not an
  HPC expert?
- Are tests or at least manual verification steps included in the final summary?
- Does the branch remain useful if supervisors later review it as a PR?

## Important Git Hygiene

Before switching branches:

```bash
git status
```

If there are unrelated dirty files, do not accidentally commit them. Either leave
them alone, commit only the intended files, or stash them with a clear name.

Good commits should be small and named after what they do:

```text
Write resolved run manifest
Avoid unavailable Solstorm nodes
Stage Julia run inputs under result directory
```

Avoid combining model changes, scheduler changes, generated data, and docs in one
commit.
