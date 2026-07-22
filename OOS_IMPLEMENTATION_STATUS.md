# OOS implementation status and handoff

Last updated: 2026-07-22

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

The current code has completed one representative one-tree OOS run successfully
and now validates and aggregates completed OOS results locally. Job 6421 reached
`OPTIMAL`, reproduced all eight fixed-capacity tables, and has been converted
from raw load-shedding MW into correctly weighted physical ENS. Deterministic
two-tree fixtures validate the cross-tree path. Multiple real trees have not
yet been run, and chronological full-year OOS is still pending.

## Branch and provenance

- Working branch: `torgrim/oos-workbench-continuation`
- Base branch: `torgrim/workbench`
- At handoff commit `8a3dc07`, the continuation branch was 35 commits
  ahead of `torgrim/workbench` and zero behind. Use `git rev-list --left-right
  --count torgrim/workbench...HEAD` for the live count.
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
| `4e4776b` | Second command-13 failure and dependency blocker evidence |
| `1c08af2` | Shared dependency bootstrap and command-13-only retry planning |
| `93127d1` | Metadata-safe dataset archives and evidence-bound sidecar quarantine planning |
| `7ef34e3` | Recovered-dataset validation bound to exact quarantine evidence |
| `2ab5871` | Remote queue/SGE setup gated on successful input validation |
| `8cfcd24` | Duplicate-safe, evidence-bound single-job submission planning |
| `095a84c` | Prepared concrete remote queue and SGE job evidence |
| `075281b` | Recorded the single submitted Solstorm job 6420 |
| `451faee` | Recorded and separated model infeasibility from the runner crash |
| `d1936ac` | Safe no-solution reporting and deterministic runner tests |
| `9c54646` | Omit investment-only constraints during fixed-capacity OOS evaluation |
| `4b007ad` | Record the infeasibility diagnosis and rerun plan |
| `8a3dc07` | Correct the handoff test totals and constraint terminology |
| `c0b0916` | Record the fresh rerun preflight checkpoint |
| `e0d736c` | Record the validated fresh Solstorm stage |
| `ab38075` | Record successful representative OOS job 6421 |

## Functional progress

| Plan item | What it means | Status |
|---|---|---|
| 1. Fixed investments | Read, provenance-check, compatibility-check, and fix generation, transmission, and storage capacities | Implemented and locally tested; legacy job 6421 base provenance reconstructed explicitly |
| 2. Scenario generation | Generate trees without mutating the base dataset | Implemented and locally tested |
| 3. Single-tree runner | Stage one tree and one fixed investment set | Implemented and locally tested |
| 4a. Experiment preparation | Reproducible tree list, seeds, metadata, and checksums | Implemented |
| 4b. Execution queue | Persistent one-job-per-tree work queue | Implemented |
| 4c. Reconciliation | Require valid run manifest and acceptance criteria | Implemented |
| 4d. SGE adapter | Render SGE script and parse captured scheduler output | Implemented; no submission performed |
| 4e. Staging planner | Render revision-pinned archive, transfer, verification, queue, and SGE commands | Implemented; commands remain inert |
| 4f. Concrete one-tree plan | Prepare actual `europe_v51` tree, queue, and Solstorm manifest | Prepared locally on 2026-07-21 |
| 4g. Local archive preflight | Create and inspect only the two local archives | Passed on 2026-07-21 |
| 4h. Remote staging preflight | Transfer, dependencies, recovery, all input validations, queue, and SGE preparation | Passed; one pending job and prepared script verified remotely |
| 4i. One-tree solver run | Submit and monitor one SGE job | Job 6420 finished with process exit 1: model infeasible, followed by an objective-value reporting exception |
| 4j. No-solution reporting | Preserve solver status and terminal manifest evidence without reading a missing objective | Implemented and tested; the corrected runner was included in successful job 6421 |
| 4k. Infeasibility fix | Match InternalEMPIRE by omitting investment-only constraints after capacities are fixed | Root cause demonstrated, locally regression-tested, and verified by job 6421 |
| 4l. Fresh representative rerun | Create, stage, submit, and verify a new immutable run without touching job 6420 | Job 6421 completed `OPTIMAL`; all acceptance evidence passed |
| 5. Aggregation | Validate, summarize, and combine results across trees | Implemented; deterministic two-tree tests and job 6421 local validation passed |
| 6. Full-year OOS | Full-year evaluation described in the original plan | Not completed |

## Main code and data flow

### Fixed investments and experiments

- `src/out_of_sample.jl`
  - validates the eight fixed capacity tables;
  - fingerprints the eight tables and records whether source provenance comes
    from a current run manifest or was reconstructed from a legacy summary;
  - normalizes strategic/policy configuration and rejects incompatible OOS
    execution settings before model construction;
  - permits documented operational differences needed for new scenario trees
    and chronological full-year evaluation;
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
  - records OOS provenance and acceptance evidence in `run_manifest.yaml`;
  - checks termination, primal/dual status, result count, and value availability
    before reading objectives or writing solution tables;
  - records a terminal `failed` manifest and a clear error for infeasible or
    otherwise no-solution runs, then exits nonzero;
  - omits investment lifetime/bound/coupling constraints in OOS after loading
    fixed capacities, while ordinary investment runs retain them by default;
  - records whether investment constraints were included in the manifest and
    summary.
  - stages `fixed_investment_provenance.yaml` and `source_config.yaml` with the
    fixed tables, and records the table fingerprint, provenance class, and
    compatibility report in the run manifest;
  - records `investment_context` and the emitted eight-table fingerprint in new
    successful investment run manifests.

### Result validation and aggregation

- `src/oos_aggregation.jl`
  - accepts only complete, feasible OOS manifests with verified scenario inputs
    and fixed investments;
  - checks the staged config and scenario metadata against the run manifest;
  - verifies that all eight emitted capacity tables are byte-identical to the
    staged fixed-investment inputs;
  - calculates conditional physical ENS with
    `loadShed * multiple_strat * duration` and expected ENS contributions with
    `loadShed * multiple_strat * probability * duration`, without discounting;
  - keeps discounted fixed-investment cost separate from the non-investment
    objective used for cross-tree comparison;
  - streams the five operational result files named in Plan step 5 into combined
    CSVs with `Tree`, `Seed`, and `Run` identifiers;
  - rejects mixed configs, mixed fixed investments, duplicate tree names, and
    non-empty output directories unless overwrite is explicit.
- `scripts/aggregate_out_of_sample_results.jl`
  - discovers one or more result manifests and writes tree, scenario, and
    scenario-season summaries plus a checksummed aggregation manifest;
  - supports `--files=<list>` for selected combined outputs and `--files=none`
    for summary-only analysis.
- Provenance: the default file list and `Tree`/`Run` identifier convention were
  manually ported from `origin/pr/14` (`8d3af69`). Its old batch-summary reader
  was not used because the workbench runner now has stronger manifests. The
  `origin/rf/result_aggregates` helper was inspected but not ported: its load
  shedding calculation does not explicitly apply the required duration.

### Solstorm preparation

- `src/oos_sge.jl` and `scripts/prepare_oos_sge_job.jl`
  - generate an SGE script but never invoke `qsub`;
  - share a Solstorm Julia module fallback with remote staging commands;
  - share an import-check and conditional `Pkg.instantiate()`/`Pkg.precompile()`
    dependency bootstrap with remote staging commands;
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
- `src/oos_cleanup.jl`
  - compares captured local and remote per-file manifests;
  - prepares one approval-gated command that moves only the exact proven
    AppleDouble sidecars into a recoverable quarantine directory;
  - refuses to move anything if the complete remote manifest has drifted;
  - verifies the clean dataset manifest and expected fingerprint after moving;
  - prepares a command-13-only retry only when the immutable quarantine plan,
    execution evidence, stdout/stderr hashes, and exact clean manifest agree;
  - never executes SSH, deletes files, submits a job, or starts a solver.
- `src/oos_remote_setup.jl`
  - accepts only successful command-13 execution evidence with all six checks;
  - reproduces only original commands 14-15 with the proven bootstrap;
  - prepares the one-tree queue and SGE script idempotently;
  - rejects transfer, `qsub`, runner, and solver actions and never executes SSH.
- `src/oos_submission.jl`
  - requires successful setup execution and read-only artifact inspection;
  - atomically rechecks exact queue/script hashes and pending/no-ID state;
  - reserves remote qsub evidence with shell noclobber before one submission;
  - prevents automatic resubmission when any state or evidence path exists.
- `scripts/prepare_oos_solstorm_resume.jl`
  - reads the immutable staging plan and recorded failed preflight;
  - refuses to proceed unless commands 3-12 completed, command 13 alone failed
    before validation, commands 14-15 were untouched, and no solver or `qsub`
    ran;
  - emits only the failed validation command 13, with Julia and dependency
    bootstraps, and never executes it.

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
- Dependency-bootstrap implementation commit: `1c08af2`.
- Third-attempt validation-only plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/validation_retry_attempt3.yaml`
- Third-attempt plan SHA-256:
  `e9a7a81edcdd1cd4f8c60b8ae101cddf74f7556d13f8fbf47456b6ed3fdfe3af`.
- The new plan is bound to the updated remote-preflight hash, records failed
  attempt 2, and contains exactly original command 13. It conditionally runs
  `Pkg.instantiate()` and `Pkg.precompile()` before checksum validation. It
  excludes commands 14-15, queue/SGE preparation, `qsub`, and the model runner.
- With explicit approval, the third-attempt plan hash and source-evidence hash
  were reverified and its only command was executed.
- Solstorm updated the Julia registry, instantiated the project, created its
  remote `Manifest.toml`, and precompiled 80 dependencies; six were already
  precompiled. Three FilePathsBase extension warning groups were reported, but
  the final import check passed.
- The repository-code checksum passed. The next check failed with `dataset
  checksum mismatch`, so execution-config, generation-config, OOS-tree, and
  fixed-investment checks did not start.
- Commands 14-15, queue/SGE preparation, `qsub`, and the solver remained
  unexecuted.
- The attempt-3 plan is now evidence-stale and must not be rerun. Updated
  remote-preflight evidence SHA-256:
  `b161cad58a32b3915eb78a18656add1de9140b2c73d3674e25d81f578cae0a08`.
- Local re-extraction of the exact transferred dataset archive reproduced the
  expected fingerprint `1e015ec90929a41d1a543760a54f5298250718f09f34c21fdf9b7eadc58ac5d0`.
  The source and extraction each contain 84 files, with no missing, extra, or
  changed path/size/file-SHA entries. `.DS_Store` is present and identical in
  both; the archive contains no AppleDouble `._*` file entries.
- The local system has bsdtar 3.5.3/libarchive 3.7.4, not GNU tar, so the
  Solstorm extraction behavior cannot be reproduced exactly without remote
  inspection.
- Local expected per-file manifest:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/dataset_manifest.local.tsv`
  with SHA-256
  `0ee1e37c71f5f48626c67f315860f1d7258e79ff46f575e2eb73e5960b011a63`.
- Approval-gated read-only diagnostic plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/dataset_manifest_diagnostic_attempt3.yaml`
  with SHA-256
  `1ffdc69e03fb19afe4d25ecb7339341a778acbaae57a2bd8d69d525c24293553`.
- The diagnostic contains one SSH command that prints remote relative paths,
  sizes, file SHA-256 values, and the resulting directory fingerprint to local
  stdout. It uses only Julia's SHA standard library with compiled modules
  disabled. It performs no dependency setup, remote write, transfer, queue/SGE
  preparation, `qsub`, or solver action.
- The first read-only diagnostic reached Julia but failed because SSH quoting
  stripped Julia character literals (`UndefVarError: t`). It made no remote
  changes. A corrected, separately verified plan replaced those literals with
  strings and then completed with exit code 0 and empty stderr.
- Corrected diagnostic plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/dataset_manifest_diagnostic_retry.yaml`
  with SHA-256
  `53413d193a5dd0f6955d1a08e448235fb790101fe1fa4e5eb47f5657d60d011e`.
- Captured remote manifest:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/dataset_manifest.remote.retry.tsv`
  with SHA-256
  `49f55855d72e4f9a3180ac79fea6318d7cccf624a816217470d4ed55ccf361e7`.
- Exact manifest comparison found all 84 intended files present and
  byte-identical, with zero missing or changed inputs. The remote extraction
  also contains 93 extra 163-byte `._*` AppleDouble sidecars, all with SHA-256
  `5d7add0d3fe38a560e64f0d4db40f41d255e4b7540a8edac921fae0af566bb30`.
- Those sidecars alone change the expected directory fingerprint from
  `1e015ec90929a41d1a543760a54f5298250718f09f34c21fdf9b7eadc58ac5d0`
  to the remote value
  `842cccf0b3d95ab6560b9c4e551eb850aefa03f10b5e16e852854edd11e48857`.
- Updated remote-preflight evidence SHA-256:
  `74b6b34a15bc78f0f67012afc32b24bbea469da6084c0e8cb1735cc9d5634982`.
- Commit `93127d1` now prevents future macOS-created dataset archives from
  carrying extended attributes by using `COPYFILE_DISABLE=1` and bsdtar's
  `--no-xattrs`, `--no-mac-metadata`, and `--no-fflags` options. Non-macOS
  staging retains the ordinary portable `tar` command.
- Exact recoverable quarantine plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/appledouble_quarantine_plan.yaml`
- Quarantine-plan SHA-256:
  `aec3d9e977b27402403ae1f9771e09e121f1f7423d404f151301cda1291d9a75`.
- The immutable plan records one SSH command and 93 exact relative paths.
  Every target is a captured 163-byte `._*` file with SHA-256
  `5d7add0d3fe38a560e64f0d4db40f41d255e4b7540a8edac921fae0af566bb30`.
- The command first requires the complete remote dataset to equal the captured
  84 intended files plus those 93 sidecars. It then moves the sidecars to
  `artifacts/appledouble_quarantine_attempt3`, preserving relative paths, and
  requires the intended 84-file manifest and expected dataset fingerprint.
  It contains no wildcard, `rm`, transfer, `qsub`, runner, or solver action.
- With explicit approval, the plan and its four source-evidence hashes were
  reverified and its one SSH command was executed on Solstorm. It exited 0
  with empty stderr.
- Quarantine execution evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/appledouble_quarantine_execution.yaml`
  with SHA-256
  `5434b43d7fefdbb97ded07cf0a2fe0afaf82c3b323cf7f5ff11f942a39b66558`.
- Captured stdout SHA-256:
  `6e2f219e24028636817efc8a96ea832d1e5960371c93dac00f4c0009b9460750`.
  It contains exactly the 84 intended manifest entries, the expected dataset
  fingerprint `1e015ec90929a41d1a543760a54f5298250718f09f34c21fdf9b7eadc58ac5d0`,
  and a quarantine marker for 93 files. Captured stderr is empty.
- The 93 sidecars now reside at the recoverable remote path
  `artifacts/appledouble_quarantine_attempt3`. No files were deleted. Command
  13, commands 14-15, `qsub`, the runner, and the solver were not executed.
- Recovered-validation implementation commit: `7ef34e3`.
- Evidence-bound validation plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/recovered_validation_attempt4.yaml`
  with SHA-256
  `d8262fc53ec348edb82295e1f7affe388c1c333558b2b81dda33c0774cf7cf9f`.
- The plan is bound to the staging plan, remote-preflight evidence, quarantine
  plan, quarantine execution, and both captured quarantine logs. It contains
  only original command 13 and the repository, dataset, execution-config,
  generation-config, OOS-tree, and fixed-investment validations.
- With explicit approval, command 13 ran once and exited 0. Both stdout and
  stderr are empty, as expected from the silent assertion-based validator.
  Therefore all six staged-input validations passed.
- Validation execution evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/recovered_validation_attempt4_execution.yaml`
  with SHA-256
  `542b2c08b2d4d8079d70c7eb1ffa4a5fe2b4a6297b6be5846a6ae6db1ef460d3`.
- The sandboxed launcher returned before its asynchronously completed evidence
  became visible. A proposed retry was stopped locally by the no-overwrite
  guard before SSH, confirming there was only one evidenced command-13 run.
- Remote-setup implementation commit: `2ab5871`.
- Evidence-bound commands-14-and-15 plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/remote_setup_commands14_15.yaml`
  with SHA-256
  `d84f468519b991b79f02eceeb09fe903f6576f390de1fa9e8f7e1d8b3d8d9170`.
- Both approved commands exited 0 with empty stderr. Command 14 prepared the
  remote one-tree execution queue. Command 15 prepared the SGE plan and script
  and printed the recorded future `qsub` command with the explicit label
  `not executed`.
- Setup execution evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/remote_setup_commands14_15_execution.yaml`
  with SHA-256
  `95e28d7b6e83c3b71892190bc950524f82916f9d76637fe28b281f1487190521`.
- The first read-only artifact inspection failed before reading either artifact
  because its Julia source incorrectly escaped a literal SGE `$` directive.
  It performed no remote write, submission, runner, or solver action.
- The corrected read-only inspection exited 0 with empty stderr and is recorded
  in `remote_setup_artifact_inspection_retry.yaml`, SHA-256
  `b8c3a5000da080f2c77d224b37801c8d0590885dc3e552c0fd4e764126527536`.
- Verified remote queue SHA-256:
  `a18abaf4a911458fc4283347bf1997048bfb0c990a6054b71ad7aad298e57b95`.
  It is `ready` with exactly one `pending` job: index 1, `oos_tree1`, seed 101,
  solver Gurobi. Dataset, execution config, scenario tree, fixed investments,
  and runner-code inputs all validate. Job history and scheduler job ID are
  empty.
- Verified SGE script SHA-256:
  `a284d53d8ca3de73af52bd992213cf0fe1cfbea25a379a9f9feb1c1741888f14`.
  It targets `compute-4-51|compute-4-52|compute-4-53|compute-4-55|compute-4-56`,
  loads the Gurobi module, revalidates the queue before running, and contains
  the expected OOS runner command. The script itself does not invoke `qsub`.
- Submission-planner implementation commit: `8cfcd24`.
- Duplicate-safe submission plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree/solstorm_staging/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/submission_attempt1.yaml`
  with SHA-256
  `367a39f6b27b672e00384c6268bcbb478c1f085da6cb94abe63be0794a7d980d`.
- The plan rechecked the exact prepared queue and SGE script hashes, required a
  pending job without an ID, reserved attempt-1 stdout/stderr under the remote
  stage with noclobber, and contained exactly one `qsub` invocation.
- With explicit approval, Solstorm accepted exactly one submission:
  `Your job 6420 ("empire_oos_1") has been submitted`. Local stderr and the
  remotely preserved qsub stderr are empty.
- Submission execution evidence:
  `submission_attempt1_execution.yaml`, SHA-256
  `a225d233e62efb9bf1aace725848d05def034ed41ee4196b72ca7f3c5966156b`.
- Job ID `6420` was parsed with the repository SGE adapter and persisted into
  the remote queue. Submission-record evidence: `submission_record.yaml`,
  SHA-256
  `7a0748086b70be02393e03a17c0d5b6c3b52af0e3388cf3fab399b4ee8f4bca9`.
- Initial read-only `qstat` found raw state `r` (`running`) on
  `all.q@compute-4-56.local`. Observation evidence: `qstat_6420_initial.yaml`,
  SHA-256
  `289f9a4d9f31e89d20fb50e371136ef1555e18799496fa9eaa525a07b3a28752`.
- That state was persisted through the existing SGE queue adapter. Record
  evidence: `qstat_6420_record.yaml`, SHA-256
  `85736920165e481192d9f349917d289996b8498323c6f69f0eae336a281c6156`.
- Initial running-state remote queue SHA-256:
  `978dd3b28ab4ad6809170ff62a81435167ab6f6417511c47acf3d7507bd9a357`.
  At that observation, queue/job status was `running`; scheduler ID was `6420`.
- Scheduler logs are expected at
  `/home/torgrif/OpenEMPIRE.jl/stages/experiment_seed101_1tree_oos_tree1_5cf05e0ff211/inputs/experiment/sge/logs/oos_tree1_6420.out`
  and the corresponding `.err` path.
- No second `qsub` was executed. The model was not started directly by the
  agent; the submitted SGE script now controls job startup and solving.
- The next monitoring observation found job `6420` absent from `qstat`.
  `qacct` reports scheduler `failed=0`, process `exit_status=1`, wall time 738s,
  and maximum virtual memory 46.234GB on `compute-4-56.local`.
- Parsed accounting evidence: `qacct_6420_monitor1_parsed.yaml`, SHA-256
  `cf05d580af8de3526c718da369eb710c472190d872ad32d58cb19eadfe2e593f`.
- Accounting was persisted through the SGE adapter. The remote queue is now
  `attention_required`, job `6420` is `failed`, and its SHA-256 is
  `7709b0f0376e5c33cff7ff8de8827ef48816f3bc81e1b844d6a3e18053d87b93`.
- The `.out` log is 8,476 bytes and the `.err` log is 45,632 bytes. Read-only
  tail evidence is `logs_6420_monitor1.yaml`, SHA-256
  `b79117484d85ffe4ef6e9d04ff2e94a519ac266dfa75b7ebb4bc82903ccd9720`.
- Verified run behavior:
  - Gurobi 13.0.2 loaded successfully;
  - OOS scenario checks passed and all investments were fixed;
  - the model built in 619.77s with 20,427,120 named constraints and
    14,299,315 variables;
  - Gurobi presolve completed and reported `Model is infeasible`;
  - optimization returned after 13.87s;
  - the runner then called `JuMP.objective_value(emp)` despite zero solutions,
    raising `MathOptInterface.ObjectiveValue(1) out of bounds` at
    `scripts/run_julia_empire.jl:753`.
- The underlying model infeasibility and the runner's secondary result-handling
  exception are separate problems. The logs do not yet identify which
  constraint combination causes infeasibility.
- Result inventory contains only the staged config, OOS metadata, and
  `run_manifest.yaml`; there are no solution CSV tables. Inventory evidence:
  `results_6420_inventory.yaml`, SHA-256
  `0cbd4b5850fe94270bda4f7b7fe7c22aa41bc1e2cf03757fc803bbc1f43ff955`.
- The run manifest SHA-256 is
  `8104c02d3ded9721a70598257e730190845860804e7fd1c21dc86b170ff653a9`.
  It remains `status: started` with no end time or solution block because the
  exception escaped. It nevertheless records OOS enabled, seed 101, scenario
  checks verified, and investments fixed. Inspection evidence:
  `run_manifest_6420_inspection.yaml`, SHA-256
  `c0c78115a160031fe764c197a2a6823079d282b2f58ead456a7bad5a4f964ff1`.

Current checkpoint:

```text
HISTORICAL: stage 5cf05e0... -> qsub 6420 -> INFEASIBLE
                                         |
                              root cause identified
                              + runner reporting fixed
                              + investment rows omitted
                                         |
FRESH:      tree/queue -> plan -> local archives -> remote stage -> qsub -> result
               PASS       PASS       PASS             PASS        6421     OPTIMAL
               \________________ pinned to 8a3dc07 _______________/
```

### Fresh immutable rerun prepared on 2026-07-21

This package is separate from the historical job-6420 stage and does not
overwrite any earlier evidence.

- Revision: `8a3dc07c315a3da174449c9710831d864c2273d4`
- Experiment and local queue:
  `OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07`
- Local staging plan:
  `OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/solstorm_staging/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/staging.yaml`
  (SHA-256
  `20755188e9f45194ae887ecb9aa0544c4ada8f51537f6545ec7d862374d6cd2f`)
- Remote stage (created and validated 2026-07-21):
  `/home/torgrif/OpenEMPIRE.jl/stages/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a`
- Remote results (currently empty):
  `/home/torgrif/OpenEMPIRE.jl/stages/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/results`
- Local preflight evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/solstorm_staging/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/archive_preflight.yaml`
  (SHA-256
  `1383af27a0d12cc4466efd49a53aa9b01b8ea4ae1b192a385747bf94d6849ca6`)
- The experiment is `complete`; the queue is `ready` with one pending seed-101
  job; the dry-run staging plan is `ready` with no blockers.
- The four scenario files are byte-for-byte identical to the historical
  seed-101 tree. The dataset fingerprint is the validated 84-file fingerprint
  `1e015ec90929a41d1a543760a54f5298250718f09f34c21fdf9b7eadc58ac5d0`.
- All entries in the immutable staging plan are now complete: entries 1-2
  created local archives and entries 3-13 created and validated the isolated
  remote stage. Earlier notes called the remote entries "commands 3-15" by
  counting grouped file transfers separately; the generated YAML contains 13
  command entries in total.
- Remote preflight evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/solstorm_staging/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/remote_preflight.yaml`
  (SHA-256
  `5d060ec0bd8cdcba231161207ddb69b17346c6e337fb865fdf46e7470bc49d62`).
- The remote queue contains exactly one pending seed-101 job. Its scheduler
  state is `prepared`; `scheduler_job_id` and `submitted_at_utc` are null.
  `qstat -u torgrif` was empty, the result directory was empty, and no `qsub`,
  runner, or solver command was executed.
- After submission, scheduler stdout will be written to
  `.../inputs/experiment/sge/logs/oos_tree1_$JOB_ID.out` under this fresh stage
  (and stderr to the corresponding `.err` file).
- Before regenerating, three ignored scenario outputs left by a local static
  audit (`genCapAvailStochRaw.csv`, `maxRegHydroGenRaw.csv`, and `sloadRaw.csv`)
  were removed from the base dataset. All 84 tracked source files were
  unchanged. The superseded draft package was preserved at
  `/private/tmp/experiment_seed101_1tree_oosfix_8a3dc07_draft` for this local
  session.

### Fresh representative OOS run completed on 2026-07-21

- Solstorm job `6421` ran on `compute-4-51.local` and completed with scheduler
  `failed=0`, `exit_status=0`, and 2,857 seconds wall time. Maximum recorded
  memory was 59.651 GB.
- Gurobi returned `OPTIMAL`; primal and dual status are both `FEASIBLE_POINT`.
  The run manifest is `complete`, records fixed investments and verified
  scenario checksums, and confirms `investment_constraints_included: false`.
- Objective value: `2.9758344543298506e12`. Build time was 718.00 seconds and
  solve time was 564.33 seconds; remaining wall time was primarily CSV output.
- All eight emitted investment/capacity CSV files are byte-identical to the
  corresponding fixed-investment inputs. This verifies that the OOS solve did
  not choose new investments.
- Complete remote result:
  `/home/torgrif/OpenEMPIRE.jl/stages/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/results/oos_tree1/20260721_150642_dataset`
- Complete local copy:
  `results/julia_oos_runs/experiment_seed101_1tree_oosfix_8a3dc07/oos_tree1/20260721_150642_dataset`
  (119 files, about 1.4 GB). A checksum-mode rsync dry run reported no remote
  versus local differences.
- Completion evidence:
  `OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/solstorm_staging/experiment_seed101_1tree_oosfix_8a3dc07_oos_tree1_8a3dc07c315a/completion_record.yaml`.
  Its SHA-256 is
  `5f931cfc50fc47828d7b1f75ad36c2300df82257865579379f509a4b1e6e13d2`.
  The reconciled remote queue and job status are both `complete`.
- Load shedding is not zero. Of 529,200 output rows, 142 exceed `1e-6`; the
  maximum is 21,635.71 MW at Germany, strategic period 3, scenario 2, `peak1`
  hour 11. The raw unweighted sum is 213,652.65 MW and must not be interpreted
  as annual energy without the representative-period weights. The load-shedding
  objective component is `2.3471494868033577e10`.
- This is a successful one-tree representative-period OOS solve. It does not
  yet establish acceptable reliability across multiple trees or implement a
  chronological full-year OOS evaluation.

### Job 6421 aggregation completed locally on 2026-07-22

- Aggregation output:
  `results/julia_oos_aggregations/job6421_seed101`.
- The validator reproduced the fixed-investment fingerprint
  `9321df4c69cf2664ade384e5c2f9d59f7455a527725fcf813dd49a1b25fd9274`
  and verified all eight fixed-capacity outputs byte-for-byte.
- Discounted fixed-investment cost is `2.1165135004239844e12` EUR; discounted
  non-investment objective is `8.593209539058662e11` EUR. These are now separate
  comparison columns rather than one dominated objective value.
- Probability-weighted physical annual ENS summed across the five strategic
  periods is `462020.62800057005` MWh. This aggregate is not a discounted
  financial quantity; period/scenario values are retained separately in
  `oos_ens_by_period_scenario.csv`.
- The material-event count is 142 node-hour rows above `1e-6` MW. The maximum
  remains `21635.71246762143` MW at Germany, period 3, scenario 2, `peak1`, hour
  11. This independently reproduces the earlier raw-event audit.
- A combined `loadShed.csv` with 529,200 rows was written by the streaming path.
  The other Plan-step-5 operational files are covered by the same generic path
  and deterministic tests but were not duplicated locally for this one-tree
  validation because their source files are already preserved in the 1.4 GB
  result.

### Regeneration commands

Run from the repository root at revision `8a3dc07` to reproduce the fresh
checkpoint. These commands prepare local state only.

```bash
julia --project=. scripts/prepare_oos_experiment.jl europe_v51 \
  --config=config/run_2045_3sce.yaml \
  --format=csv \
  --num-trees=1 \
  --seed-start=101 \
  --output=OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07 \
  --resume=true

julia --project=. scripts/prepare_oos_execution_queue.jl europe_v51 \
  --config=/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl/results/julia_runs/20260630_124809_europe_v51/fixed_sample_config.yaml \
  --format=csv \
  --solver=Gurobi \
  --experiment=OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07 \
  --fixed-investment-dir=/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl/results/julia_runs/20260630_124809_europe_v51 \
  --results=results/julia_oos_runs/experiment_seed101_1tree_oosfix_8a3dc07 \
  --queue-file=OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/execution.yaml \
  --julia-command=julia \
  --resume=true

julia --project=. scripts/prepare_oos_solstorm_staging.jl \
  --queue=OutOfSample/europe_v51/experiment_seed101_1tree_oosfix_8a3dc07/execution.yaml \
  --remote-user=torgrif \
  --remote-host=solstorm.iot.ntnu.no \
  --remote-root=/home/torgrif/OpenEMPIRE.jl \
  --revision=8a3dc07c315a3da174449c9710831d864c2273d4
```

If code affecting the OOS fingerprint changes, the existing execution queue is
intentionally stale. Prepare a new queue path instead of deleting or
overwriting evidence from an in-progress or completed experiment.

## Verification completed

- OOS aggregation focused tests pass 29/29. They cover exact time weights,
  conditional versus expected ENS, fixed/non-investment cost separation,
  two-tree discovery and aggregation, streaming combined CSV identifiers,
  output overwrite protection, and changed-capacity rejection.
- The full repository suite passed after the provenance/compatibility increment:
  Excel 66, CSV 63, CSV scenarios 164 with one known broken Python fixture
  check, runner 80, core OOS 157, aggregation 29, all Solstorm workflow suites,
  validation 16, TimeStruct 17, and solve 3.
- Focused provenance tests verify legacy-summary reconstruction, current-manifest
  verification, sidecar staging, missing-evidence rejection, allowed operational
  differences, structural mismatch rejection, and unchanged Solstorm command
  safety. The real legacy investment run passes with the fingerprints recorded
  above; `config/run_2045_3sce.yaml` is correctly rejected because its
  `north_sea: false` differs from the base run's `north_sea: true`.
- The job 6421 aggregation completed in about nine seconds when validating ENS
  and streaming all 529,200 load-shedding rows.

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
- Dependency-bootstrap tests passed: 13 assertions covering a fresh project,
  an already-ready project, and a failed instantiation. Updated focused suites
  passed with 92 staging and 49 SGE assertions.
- The third-attempt plan passed local evidence-hash, command-order, command
  count, target-account, and no-submit/no-solver assertions.
- On the approved attempt-3 run, dependency setup and the repository-code
  checksum passed. Dataset content validation failed before the remaining four
  content checks. No queue, scheduler, or solver action occurred.
- Exact local archive re-extraction and per-file comparison passed for all 84
  files. A one-command read-only remote manifest identified 93 AppleDouble
  sidecars and confirmed that no intended file is missing or changed.
- Metadata-safe archive and quarantine tests passed: 95 OOS staging assertions
  and 25 OOS cleanup assertions. The installed macOS bsdtar 3.5.3 also
  successfully created and listed a small archive using all four safeguards.
- The concrete quarantine plan was validated locally: 93 exact sidecar
  targets, one SSH command, recoverable moves, zero executed commands, and no
  `rm`, wildcard, `qsub`, runner, or solver action.
- The approved quarantine command exited 0 with empty stderr. Its output
  exactly matches the expected 84-file local manifest and dataset fingerprint,
  and reports all 93 sidecars in the recoverable quarantine directory.
- Recovered-validation tests passed together with the existing focused suites:
  95 staging assertions and 45 cleanup/recovery assertions.
- The concrete command-13 plan passed six source-hash, command-index,
  target-account, six-validation, and no-queue/no-SGE/no-submit/no-run checks.
  Its one approved remote command exited 0 with empty stdout and stderr, which
  proves every assertion in all six staged-input validations passed.
- Remote-setup focused tests passed with the existing suites: 95 staging, 45
  cleanup/recovery, and 25 setup assertions (165 total).
- Commands 14 and 15 each exited 0 with empty stderr. The corrected read-only
  inspection reran the repository's queue-input validator and verified one
  pending job, the expected hashes, SGE resources and script content, and the
  absence of submission/job-ID state.
- Submission-focused tests passed with the existing suites: 95 staging, 45
  cleanup/recovery, 25 setup, and 26 submission assertions (191 total).
- The concrete submission plan passed source-hash, exact queue/script,
  pending/no-ID, one-qsub, noclobber, and no-direct-runner/solver checks.
  Scheduler output produced job ID `6420`; the submission and initial running
  state were recorded without any additional qsub invocation.
- Completion monitoring captured `qacct`, both scheduler log tails, the result
  inventory, and the run manifest read-only. Scheduler infrastructure passed,
  while the process exited 1 after Gurobi proved the model infeasible and the
  runner attempted to read a nonexistent objective value.
- No-solution handling tests passed with a tiny infeasible HiGHS model and an
  optimal control case. They verify that objectives/components are not read
  without values and that terminal failure evidence is YAML-serializable.
- After the reporting fix, the full repository suite exited 0: Excel 66, CSV
  63, CSV scenarios 157 with one known broken Python parity check, runner 76,
  OOS 122, all Solstorm workflow suites, validation 16, TimeStruct 17, and
  Solve 3. The Python helper still warns because its temporary fixture lacks
  `Sets/Generator.csv`; that check was already marked broken and skipped.
- The source investment run summary is `OPTIMAL` and reports the same
  14,299,315 variables and 20,427,120 constraints as failed job 6420. Its core
  model files match source commit `3901f61`; no intervening core-model diff was
  found before the OOS-specific change.
- A static audit evaluated all 18,875 investment-only rows using job 6420's
  exact eight fixed-capacity tables and the current `europe_v51` parameters.
  It found 155 equality residuals above `1e-6`: 120 generator tracking rows
  (maximum `1.1236142108828062e-4`), 8 storage-energy rows, 5 storage-power
  rows, and 22 transmission tracking rows. No maximum build/installed-capacity,
  storage-ratio, or North Sea inequality exceeded `1e-6`.
- InternalEMPIRE and OpenEMPIRE-csv both represent OOS capacities as parameters
  and omit all investment-only constraints. Julia previously fixed those
  capacities as variables but retained the redundant equalities, converting
  acceptable barrier/no-crossover solution residuals into contradictory fixed
  rows. Commit `9c54646` now matches the reference behavior while retaining all
  operational constraints.
- A tiny deterministic HiGHS reproduction is infeasible with inconsistent
  capacities fixed under investment constraints and feasible when the OOS
  constraint mode is used. Focused regression tests passed 73/73.
- After the infeasibility fix, the full repository suite exited 0: CSV
  scenarios 164 with one known broken parity check, runner 76, OOS 142, and all
  remaining suites passed.
- The fresh seed-101 experiment regenerated successfully and reproduced all
  four historical scenario-file SHA-256 values. Its queue records the expected
  fixed-investment fingerprint, current runner fingerprint, and one pending
  job.
- Fresh local archive preflight passed: the revision-pinned repository archive
  contains 319 files and matches code fingerprint
  `5d1058cf4c5640d97ea39fb7927fbde5d82e59eb5f75e79a8ef2947c0b87cecf`;
  the dataset archive contains 84 files and matches the validated content
  fingerprint. No forbidden or unsafe paths were found. All 13 plan entries
  retain `executed: false` because `staging.yaml` is the immutable dry-run plan;
  actual execution is recorded separately in the preflight evidence files.
- The fresh isolated Solstorm stage passed archive-transfer verification and
  all six content fingerprints: repository code, dataset, execution config,
  generation config, OOS tree, and fixed investments. Julia 1.9.3 instantiated
  and precompiled the clean archived project successfully.
- The generated remote queue passed a separate machine-readable audit: one job,
  seed 101, `pending`, scheduler `prepared`, no job ID or submission timestamp,
  and an SGE script whose SHA-256 matches the queue record. Queue SHA-256 is
  `df66c7d0917c1be4671f5d342322cabb8b18d0d482571d94fde4929285b978e3`;
  SGE script SHA-256 is
  `429663d569b5dd748c37a3eba9486b93c84e164aa7f56bba025a24ce445ad909`.

## Known gaps and risks

1. The historical representative OOS model was infeasible because redundant
   fixed-capacity investment equalities were retained. Commit `9c54646` removes
   that constraint class in OOS, and fresh job 6421 is the representative
   verification: it completed `OPTIMAL` with those constraints omitted.
2. The fixed investment run comes from the older sibling checkout and lacks the
   current `run_manifest.yaml`. The new provenance validator reconstructs its
   evidence from the preserved staged config and summary, verifies
   `optimize=true`, `OPTIMAL`, config SHA-256
   `1ef31a0529a0335cbedc109e4c0418710aecd8bb902b786b4ca834b5e1ba73d0`,
   and fixed-table SHA-256
   `9321df4c69cf2664ade384e5c2f9d59f7455a527725fcf813dd49a1b25fd9274`.
   It is deliberately labelled `reconstructed_legacy_run`, not
   manifest-verified. The job 6421 execution config passes the seven-field
   compatibility check.
3. The `rf/...` OOS branches and open PRs have not yet been reconciled against
   this implementation. No historical branch should be discarded without that
   comparison and coordination with its author/reviewer.
4. `src/oos_staging.jl` is now 837 lines and contains safety/evidence logistics
   rather than model mathematics. Review whether to split it before a PR; do
   not mix that refactor into the first representative-run debugging work.
5. Representative-period aggregation is implemented and validated locally.
   Chronological full-year OOS remains unimplemented.
6. The current continuation branch is an integration branch, not a proposed
   single employee-review PR. Prefer sequential PRs: runner workflow, core OOS,
   experiment orchestration, then optional Solstorm tooling.
7. The shared Julia fallback and dependency setup are now proven again in the
   fresh Solstorm stage with Julia 1.9.3. Dependency resolution took about six
   minutes, mostly waiting on the shared network filesystem, but completed.
8. The repository archive includes the tracked `europe_v51` dataset while the
   plan also transfers a separately checksummed dataset archive. This adds
   roughly 55 MB of duplicated compressed transfer data but does not alter the
   remote queue inputs.
9. The staged archive intentionally has no `Manifest.toml`, matching the
   existing HPC deployment convention. The revised command 13 now performs the
   established import-check/`Pkg.instantiate()` setup. Dependency resolution
   may take several minutes and can require package-network access on Solstorm.
10. A failed isolated stage and scheduler record exist at the documented remote
    path. Preserve them as debugging evidence; do not overwrite, recreate,
    delete, or resubmit them. All earlier plans are consumed/evidenced.
11. GNU tar materialized macOS extended-attribute metadata as 93 `._*`
    AppleDouble sidecars in the already-transferred stage. Future OOS archives
    now use the repository's macOS-safe convention. The existing stage has
    been recovered without deletion and its intended dataset fingerprint is
    verified. Directory validation remains strict.
12. Job 6420's historical manifest remains `started` because it ran the old
    pinned runner. Commit `d1936ac` fixes this behavior for future runs, but the
    preserved remote evidence must not be edited to simulate a rerun.
13. Job 6421 contains material load shedding despite being optimal. The new
    aggregation reports weighted ENS by period/scenario and season, but a
    reliability acceptance threshold has not been chosen. Do not treat solver
    feasibility alone as reliability acceptance.
14. The OOS objective still correctly contains fixed generator, storage, and
    transmission investment costs, matching InternalEMPIRE. Aggregation now
    reports that constant offset separately from the non-investment objective.

## Next recommended task

Implement Plan step 6 with a deterministic chronological fixture before any
full Solstorm run:

1. Reconcile the full-year design in `Feedback.pdf`, InternalEMPIRE's
   `create_scenario_tree_full_year.py`, and any available historical PR ref.
2. Represent one 8760-hour chronological operational period without applying a
   representative-season multiplier, while retaining the dummy peak structure
   only if the existing model indexing requires it.
3. Generate a tiny chronological fixture first (for example 24 or 48 hours)
   with known load, availability, and hydro rows and prove ordering, weights,
   cyclic storage behavior, and scenario dimensions locally.
4. Add full-year tree metadata that distinguishes chronological from
   representative trees and make queue/runner validation reject accidental
   cross-mode assumptions.
5. Run the tiny fixed-investment OOS model locally. Only after that passes,
   prepare a revision-pinned full-year Solstorm experiment; do not submit it
   automatically after an ambiguous failure.
