# OOS implementation status and handoff

Last updated: 2026-07-21

This is the living handoff document for out-of-sample (OOS) work in the Julia
version of EMPIRE. Update it whenever OOS behavior, workflow, concrete
experiment state, important risks, or the recommended next task changes.

## Start here in a new agent session

1. Read this file and the OOS section of `README.md`.
2. Work in `OpenEMPIRE.jl-workbench` on
   `torgrim/oos-workbench-continuation` unless the user says otherwise.
3. Run `git status --short` before editing. Preserve the user's uncommitted
   change in `config/launch_profiles/2045_3sce_northsea.yaml`.
4. Do not assume the ignored files under `OutOfSample/` exist on another
   machine. Use the regeneration commands in this document when needed.
5. Do not connect to Solstorm, transfer files, submit SGE jobs, push, or open a
   PR unless the user explicitly approves that next action.
6. End each response with the recommended next prompt or a question answerable
   with `yes`.

Suggested resume prompt:

> Continue the OOS work from `OOS_IMPLEMENTATION_STATUS.md`. Verify the current
> branch, ignored experiment artifacts, and Git status first. Perform only the
> documented next task, preserve unrelated changes, update the handoff file,
> run proportionate tests, and end with the next recommended prompt.

## OOS in plain language

A normal investment run lets EMPIRE choose new generation, storage, and
transmission capacity. OOS evaluation takes those capacity decisions, fixes
them, and tests how the resulting system operates under scenario trees that
were not used to choose the investments.

```text
investment run
    -> extract and validate eight capacity tables
    -> generate unseen scenario trees
    -> run EMPIRE with investments fixed for each tree
    -> validate every run
    -> aggregate cost, reliability, emissions, and other metrics
```

The current code reaches the preparation stage for a real one-tree run. It has
not yet completed a representative OOS solver run, aggregation, or full-year
OOS.

## Branch and provenance

- Working branch: `torgrim/oos-workbench-continuation`
- Base branch: `torgrim/workbench`
- At implementation commit `bc575f5`, the continuation branch was thirteen
  commits ahead of `torgrim/workbench`. Use `git rev-list --left-right --count
  torgrim/workbench...HEAD` for the live count.
- No `rf/...` branch or commit has been merged or cherry-picked.
- The `rf/...` branches and existing PRs remain reference implementations that
  must be reconciled before opening replacement OOS PRs.
- Recent OOS code was manually implemented against the newer workbench runner,
  informed by the PDFs, repository history, and historical `rf/...` design.
- Existing branches have not been rebased, reset, deleted, or rewritten.

Implementation commits, oldest first:

| Commit | Purpose |
|---|---|
| `7d41fb7` | Fixed-investment OOS foundation |
| `f5e428f` | Staged single-tree OOS runner |
| `46a1971` | Non-mutating OOS tree generation |
| `887dd25` | OOS tree provenance in run manifests |
| `8b67ac9` | Resumable experiment preparation |
| `edbe8fe` | Resumable execution queue |
| `d9c3bf7` | Queue state reconciliation |
| `fa2debc` | Solstorm SGE dry-run adapter |
| `5cf05e0` | Dry-run Solstorm staging plan |
| `635bc2f` | Living OOS implementation and session handoff |
| `3897820` | Local archive preflight evidence in the handoff |
| `7eaebf3` | Blocked remote preflight evidence in the handoff |
| `bc575f5` | Shared Solstorm Julia bootstrap and safe resume-plan generator |

## Functional progress

| Plan item | What it means | Status |
|---|---|---|
| 1. Fixed investments | Read and fix generation, transmission, and storage capacities | Implemented and locally tested |
| 2. Scenario generation | Generate trees without mutating the base dataset | Implemented and locally tested |
| 3. Single-tree runner | Stage one tree and one fixed investment set | Implemented and locally tested |
| 4a. Experiment preparation | Reproducible tree list, seeds, metadata, and checksums | Implemented |
| 4b. Execution queue | Persistent one-job-per-tree work queue | Implemented |
| 4c. Reconciliation | Require valid run manifest and acceptance criteria | Implemented |
| 4d. SGE adapter | Render SGE script and parse captured scheduler output | Implemented; no submission performed |
| 4e. Staging planner | Render revision-pinned archive, transfer, verification, queue, and SGE commands | Implemented; commands remain inert |
| 4f. Concrete one-tree plan | Prepare actual `europe_v51` tree, queue, and Solstorm manifest | Prepared locally on 2026-07-21 |
| 4g. Local archive preflight | Create and inspect only the two local archives | Passed on 2026-07-21 |
| 4h. Remote staging preflight | Transfer, verify checksums, and prepare remote queue/SGE script | Transfer/extraction and Julia bootstrap passed; blocked because the fresh remote project dependencies are not instantiated |
| 4i. One-tree solver run | Submit and monitor one SGE job | Not started; requires approval |
| 5. Aggregation | Combine validated results across trees | Not implemented |
| 6. Full-year OOS | Full-year evaluation described in the original plan | Not completed |

## Main code and data flow

### Fixed investments and experiments

- `src/out_of_sample.jl`
  - validates the eight fixed capacity tables;
  - generates OOS trees and metadata;
  - prepares resumable experiments and execution queues;
  - checks input fingerprints;
  - reconciles completed run manifests.
- `scripts/prepare_oos_experiment.jl`
  - CLI for generating scenario-tree experiments.
- `scripts/prepare_oos_execution_queue.jl`
  - CLI for preparing a queue without starting processes.
- `scripts/manage_oos_execution_queue.jl`
  - shows and updates queue state from explicit or captured evidence.

### Runner

- `scripts/run_julia_empire.jl`
  - stages the base dataset, selected scenario tree, config, and fixed capacity
    files into an immutable run directory;
  - rewrites the staged OOS config to `use_fixed_sample: false`;
  - fixes investment variables before solving;
  - records OOS provenance and acceptance evidence in `run_manifest.yaml`.

### Solstorm preparation

- `src/oos_sge.jl` and `scripts/prepare_oos_sge_job.jl`
  - generate an SGE script but never invoke `qsub`;
  - share a Solstorm Julia module fallback with remote staging commands;
  - parse captured `qsub`, `qstat`, and `qacct` output;
  - distinguish scheduler completion (`finished`) from accepted model completion
    (`complete`).
- `src/oos_staging.jl` and `scripts/prepare_oos_solstorm_staging.jl`
  - create an isolated one-tree staging manifest;
  - pin the repository archive to a commit;
  - describe local archive, SSH, SCP, checksum, remote queue, and remote SGE
    preparation commands;
  - never execute those commands;
  - mark a plan blocked when relevant code is uncommitted or the selected
    revision is not `HEAD`.
- `scripts/prepare_oos_solstorm_resume.jl`
  - reads the immutable staging plan and recorded failed preflight;
  - refuses to proceed unless commands 3-12 completed, command 13 alone failed
    before validation, commands 14-15 were untouched, and no solver or `qsub`
    ran;
  - emits only bootstrapped SSH commands 13-15 and never executes them.

## Concrete one-tree experiment prepared on 2026-07-21

These artifacts are ignored by Git and exist only in this workspace.

### Selected source inputs

- Dataset: `data/europe_v51`
- Scenario-generation config: `config/run_2045_3sce.yaml`
- OOS seed: `101`
- Solver planned for execution: `Gurobi`
- Fixed-investment run:
  `/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl/results/julia_runs/20260630_124809_europe_v51`
- Fixed-investment checksum:
  `9321df4c69cf2664ade384e5c2f9d59f7455a527725fcf813dd49a1b25fd9274`
- The selected investment run has all eight required capacity tables. Its
  `summary.txt` reports `termination_status=OPTIMAL`, a 2045 horizon, three
  scenarios, `north_sea: true`, and Gurobi. It predates the current run-manifest
  format, so there is no `run_manifest.yaml` to validate.
- The source experiment config has `north_sea: false`, but `north_sea` does not
  control scenario-tree dimensions. The execution queue uses the investment
  run's `north_sea: true` config. The scenario settings checked by the queue
  match. This difference must still be mentioned when interpreting results.

### Local experiment and queue

- Experiment:
  `OutOfSample/europe_v51/experiment_seed101_1tree`
- Experiment manifest:
  `OutOfSample/europe_v51/experiment_seed101_1tree/experiment.yaml`
- Tree:
  `OutOfSample/europe_v51/experiment_seed101_1tree/oos_tree1`
- Execution queue:
  `OutOfSample/europe_v51/experiment_seed101_1tree/execution.yaml`
- Experiment state: `complete`
- Queue state: `ready`
- Job state: `pending`
- Result root reserved locally:
  `results/julia_oos_runs/experiment_seed101_1tree/oos_tree1`
- No result directory has been created and no model has been built or solved.

### Concrete Solstorm dry-run manifest

- Repository revision:
  `5cf05e0ff211a3f6184f54173bf89f8282449c13`
- Staging manifest:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/staging.yaml`
- Manifest state: `ready`
- Commands recorded: `15`
- Local commands executed: `2` (repository archive and dataset archive)
- Remote commands completed: `10` (commands 3 through 12)
- Remote command 13 attempted and failed before checksum code started.
- Remote commands 14 and 15 were not attempted.
- Remote account: `torgrif@solstorm.iot.ntnu.no`
- Remote staging root:
  `/home/torgrif/OpenEMPIRE.jl/stages/experiment_seed101_1tree_oos_tree1_5cf05e0ff211`
- `config/cluster.json` stores `~/OpenEMPIRE.jl`; existing local launch logs and
  the successful remote stage creation confirm `/home/torgrif/OpenEMPIRE.jl`.
- Local archive preflight report:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/archive_preflight.yaml`
- Repository archive: `83,791,483` bytes, SHA-256
  `a685f778e14ab7a8a58741d94a996130b0f928ec3850c0a81308730f7eb16de2`.
- Dataset archive: `55,403,860` bytes, SHA-256
  `59141c4caec4e2aa5ff57847603d300cd4a5ce0e08f11a85192093b8bcb94def`.
- Extracted repository code fingerprint and dataset content fingerprint both
  match the staging plan.
- All required project, runner, queue, OOS, and SGE source files are present.
- No `.git`, `results`, `OutOfSample`, private `config/cluster.json`, private
  key files, or unsafe dataset paths were found.
- The revision archive already contains the tracked `data/europe_v51`, so the
  separate dataset archive duplicates that dataset during transfer. This is an
  informational transfer-size inefficiency, not a checksum or execution error.
- Remote preflight report:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/remote_preflight.yaml`
- The isolated remote directory was absent before creation.
- Commands 3 through 11 created the stage and transferred the validated
  archives, configs, adjusted metadata, four scenario files, and eight fixed
  capacity tables.
- Remote `sha256sum` exactly matched both local archive hashes.
- Command 12 extracted both archives successfully. GNU tar warned that it
  ignored macOS `LIBARCHIVE.xattr.com.apple.provenance` headers.
- Command 13 first stopped immediately with `bash: julia: command not found`.
  The non-interactive Solstorm login shell required a Julia module.
- After local commit `bc575f5`, the resume-plan hash and source-evidence hashes
  were verified and only command 13 was retried with explicit approval.
- The shared Julia fallback worked on Solstorm. Importing `OpenEMPIRE` then
  failed because `JuMP` was not installed in the fresh staged project. The
  checksum code still did not start; no remote queue or SGE script was prepared.
- No `qsub`, solver, remote deletion, push, or PR action was performed.
- Local recovery implementation commit: `bc575f5`.
- Dry-run recovery plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/resume.yaml`
- Recovery plan used for the second command-13 attempt had exactly original
  commands 13, 14, and 15 and SHA-256:
  `c5afbeb577e95cfc09578e701a0eb063d75f2e259f13df4a39234e496abd6d8b`.
- That plan is now stale by design because `remote_preflight.yaml` was updated
  with the second failure. Its source-evidence hash must not validate again.
- Updated remote-preflight evidence SHA-256:
  `4b5fdc9fae9e41867521741e1359207132cefa4230f60d76ba3d02897304d74f`.
- The recovery plan targets the existing stage pinned to commit `5cf05e0`; it
  does not rebuild it from current `HEAD`, recreate directories, transfer
  files, invoke `qsub`, or start a solver.

Current checkpoint:

```text
local archives       remote transfer       Julia bootstrap       dependencies/checksums       queue/SGE       solve
     PASS          ->      PASS          ->      PASS          ->       BLOCKED             -> NOT RUN     -> NOT RUN
 commands 1-2          commands 3-12       command 13 retry        instantiate then validate     14-15         Plan 4i
```

### Regeneration commands

Run from the repository root. These commands prepare local state only.

```bash
julia --project=. scripts/prepare_oos_experiment.jl europe_v51 \
  --config=config/run_2045_3sce.yaml \
  --format=csv \
  --num-trees=1 \
  --seed-start=101 \
  --output=OutOfSample/europe_v51/experiment_seed101_1tree \
  --resume=true

julia --project=. scripts/prepare_oos_execution_queue.jl europe_v51 \
  --config=/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl/results/julia_runs/20260630_124809_europe_v51/fixed_sample_config.yaml \
  --format=csv \
  --solver=Gurobi \
  --experiment=OutOfSample/europe_v51/experiment_seed101_1tree \
  --fixed-investment-dir=/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl/results/julia_runs/20260630_124809_europe_v51 \
  --results=results/julia_oos_runs/experiment_seed101_1tree \
  --queue-file=OutOfSample/europe_v51/experiment_seed101_1tree/execution.yaml \
  --julia-command=julia \
  --resume=true

julia --project=. scripts/prepare_oos_solstorm_staging.jl \
  --queue=OutOfSample/europe_v51/experiment_seed101_1tree/execution.yaml \
  --remote-user=torgrif \
  --remote-host=solstorm.iot.ntnu.no \
  --remote-root=/home/torgrif/OpenEMPIRE.jl \
  --revision=HEAD

julia --project=. scripts/prepare_oos_solstorm_resume.jl \
  --plan=OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/staging.yaml \
  --preflight=OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/remote_preflight.yaml \
  --output=OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/resume.yaml
```

If code affecting the OOS fingerprint changes, the existing execution queue is
intentionally stale. Prepare a new queue path instead of deleting or
overwriting evidence from an in-progress or completed experiment.

## Verification completed

- Full repository suite after Plan 4e: 587 passed, with one pre-existing broken
  Python scenario-parity check caused by missing Python-side
  `Sets/Generator.csv`.
- Focused committed-revision staging tests: 58 passed.
- Concrete experiment input hashes were validated while creating the queue.
- Concrete staging manifest state is `ready`.
- Archive preflight passed: 311 repository files and 84 dataset files were
  extracted temporarily and checked. Both planned content fingerprints match;
  no required files are missing and no forbidden files were found.
- The staging manifest is an immutable plan and still records what the planner
  itself executed (`0`). `archive_preflight.yaml` is the execution evidence
  showing local commands 1 and 2 completed.
- Remote transfer integrity passed: Solstorm reported the same repository and
  dataset archive SHA-256 values as the local preflight.
- `remote_preflight.yaml` records commands 3 through 12 complete, command 13
  failed before Julia validation started, and commands 14 and 15 not attempted.
- Focused recovery tests passed: 82 staging assertions and 46 SGE assertions.
- The concrete resume CLI completed locally and emitted a three-command,
  approval-gated dry-run plan.
- On the approved retry, only original command 13 ran. The Julia module
  bootstrap passed, then `OpenEMPIRE` import failed on missing `JuMP` before
  content checksums started. Commands 14-15 remained unexecuted.
- Verified repository convention: `Manifest.toml` is ignored and deliberately
  excluded from normal HPC transfers; `scripts/run_empire_julia_basic_sge.sh`
  runs `Pkg.instantiate()` and `Pkg.precompile()` when imports are unavailable.

## Known gaps and risks

1. No representative OOS model has been built or solved with the concrete
   `europe_v51` inputs yet.
2. The fixed investment run comes from the older sibling checkout and lacks the
   current `run_manifest.yaml`. Its summary and eight capacity tables are
   present, but model compatibility has not been proven by a current build.
3. The `rf/...` OOS branches and open PRs have not yet been reconciled against
   this implementation. No historical branch should be discarded without that
   comparison and coordination with its author/reviewer.
4. `src/oos_staging.jl` is now 795 lines and contains safety/evidence logistics
   rather than model mathematics. Review whether to split it before a PR; do
   not mix that refactor into the first representative-run debugging work.
5. Aggregation and full-year OOS remain unimplemented.
6. The current continuation branch is an integration branch, not a proposed
   single employee-review PR. Prefer sequential PRs: runner workflow, core OOS,
   experiment orchestration, then optional Solstorm tooling.
7. The shared Julia fallback is now proven in the Solstorm non-interactive
   shell. Dependency setup has not yet been added to staging command 13.
8. The repository archive includes the tracked `europe_v51` dataset while the
   plan also transfers a separately checksummed dataset archive. This adds
   roughly 55 MB of duplicated compressed transfer data but does not alter the
   remote queue inputs.
9. The staged archive intentionally has no `Manifest.toml`, matching the
   existing HPC deployment convention. Command 13 must therefore perform the
   existing import-check/`Pkg.instantiate()` setup before importing
   `OpenEMPIRE` for content validation. Dependency resolution may take several
   minutes and can require package-network access on Solstorm.
10. A partial but isolated stage exists at the documented remote path. Do not
    overwrite, recreate, or delete it. The previous resume plan is consumed and
    evidence-stale; do not rerun it.

## Next recommended task

Fix the dependency bootstrap locally without reconnecting to Solstorm:

1. Reuse the repository's established import-check, `Pkg.instantiate()`, and
   `Pkg.precompile()` convention before content validation.
2. Apply it consistently to remote validation and generated SGE preparation
   without duplicating shell logic.
3. Add focused tests for a fresh environment and the no-`qsub` safety boundary.
4. Generate a new evidence-bound plan containing only revised command 13.
5. Update this handoff, run local checks, and request separate approval before
   another remote attempt. Do not run commands 14-15 or a solver.
