# OpenEMPIRE.jl

This Julia package provides an open version of the European Model for Power
system Investments with Renewable Energy (EMPIRE), reimplemented in Julia based
on the existing Python version. EMPIRE is a multi-horizon stochastic capacity
expansion model that co-optimizes investments in generation, storage and
transmission across European countries together with the corresponding hourly
operational dispatch under a set of weather and load scenarios.

The Julia version aims to:

- Provide a transparent, modular and easily extensible 
  implementation of EMPIRE.
- Use [JuMP](https://jump.dev/) as the modeling layer so the model can be
  solved with any compatible LP/MIP solver (e.g. HiGHS, Gurobi, Xpress, CPLEX).
- Use [TimeStruct.jl](https://github.com/sintefore/TimeStruct.jl) to make the
  multi-horizon time structure (strategic periods, operational seasons, peak
  hours and stochastic scenarios) explicit and easily configurable.
- Use [SparseVariables.jl](https://github.com/sintefore/SparseVariables.jl) to
  keep the model representation readable and efficient for the sparse index sets
  typical in EMPIRE (e.g. only valid node/technology/period combinations).

## Building and solving a model

The main entry point is `OpenEMPIRE.create_model`, defined in
[src/user_interface.jl](src/user_interface.jl). It takes a YAML configuration
file and a data folder (similar to the Python version), and returns the JuMP model together with the time
structure, sets and parameters:

```julia
using OpenEMPIRE
using HiGHS
using JuMP

data_folder = joinpath(pkgdir(OpenEMPIRE), "data", "test_excel")
config_file = joinpath(data_folder, "testrun.yaml")

emp, periods, sets, params = OpenEMPIRE.create_model(
    config_file, data_folder; optimizer = HiGHS.Optimizer,
)
```
The model can then be optimized using `JuMP` with the associated solver:
```
JuMP.optimize!(emp)
```

No systematic output and post-processing of results are currently available
in the Julia version. 
After solving, results can be extracted directly from the JuMP variables
(`emp[:genOperational]`, `emp[:genInvCap]`, `emp[:storCharge]`,
`emp[:transmissionInvCap]`, `emp[:loadShed]`, ...) using `value` and the
helpers from `JuMP.Containers`, for example:

```julia
genInvCap = Containers.rowtable(
    value, emp[:genInvCap];
    header = [:Node, :Generator, :Period, :Investment],
)
filter!(r -> r.Investment > 0, genInvCap)
```

See [test/test_interface.jl](test/test_interface.jl) for some more 
examples covering investments, dispatch, storage operation, transmission flows
and load shedding.

## Input data

The input is split into a structural part (sets,
technology parameters, topology, cost data) and a stochastic part
(time-dependent scenario data for load and renewable generation).
These input data can be input from the same data used for the Python version.
The repository stores bundled datasets under `data/`. CSV datasets follow the
same component layout as the Python CSV version, for example
`data/test/Sets/Node.csv`, `data/test/Generator/genCapitalCost.csv` and
`data/test/ScenarioData/electricload.csv`. The older Excel-based sample data is
kept under `data/test_excel`.

Structural inputs can be read from CSV or Excel:

```julia
sets, params = OpenEMPIRE.read_data(joinpath(pkgdir(OpenEMPIRE), "data", "test"); format = :csv)
sets_xlsx, params_xlsx = OpenEMPIRE.read_data(joinpath(pkgdir(OpenEMPIRE), "data", "test_excel"); format = :xlsx)
```

Additional source/unit columns extracted from the Excel workbooks are stored
under `data_extra/`, mirroring the dataset names in `data/`.

The Julia version can generate stochastic scenario CSV files directly from raw
`ScenarioData/*.csv` inputs. The generated files are written to the dataset's
`ScenarioData` folder as `sloadRaw.csv`, `maxRegHydroGenRaw.csv`, and
`genCapAvailStochRaw.csv`. If `use_fixed_sample: true`, the sampler uses
`sampling_key.csv`; otherwise it writes a new key alongside the generated
scenario CSVs.

### Generating scenarios without building the model

Scenario generation is independent of model construction. To produce the
scenario CSVs (and a fresh `sampling_key.csv`) for a dataset and then exit before
any JuMP model is built, pass `--generate-only`:

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=test \
  --config=config/testrun.yaml \
  --format=csv \
  --seed=1 \
  --generate-only
```

This runs only build stages 1–6 (config, time structure, dataset, scenario
sampling), writes the four files above into `data/<dataset>/ScenarioData`, and
archives the sampling key plus run metadata under
`results/julia_runs/<timestamp>_<dataset>/Input/`. The same step is available as a
library call, `OpenEMPIRE.generate_scenarios(config_file, data_folder; seed=...)`,
which returns `(periods, sets, params)` without constructing a model.

The output is **not** only `sampling_key.csv`: the key records which weather
`(Year, Hour)` each `(Period, Scenario, Season)` drew, while the three `*Raw.csv`
files are the derived stochastic inputs the model actually consumes. Both the
key and the derived files are written deterministically from `(raw inputs, key)`.

### Generating one out-of-sample scenario tree

Current implementation status, concrete experiment state, and session handoff
instructions are maintained in [`OOS_IMPLEMENTATION_STATUS.md`](OOS_IMPLEMENTATION_STATUS.md).

Generate one self-contained tree without modifying the source dataset:

```bash
julia --project=. scripts/create_out_of_sample_tree.jl test \
  --config=config/testrun.yaml \
  --seed=101 \
  --output=OutOfSample/test/oos_tree1
```

The generator works on a temporary dataset copy and publishes the completed
tree only after all required files have been produced. It refuses to overwrite
an existing tree. `metadata.yaml` records the seed, relevant configuration,
source paths, config checksum, and checksums and sizes for every scenario file.
The corresponding library function is
`OpenEMPIRE.generate_oos_scenario_tree(config_file, data_folder, tree_dir; seed=...)`.

### Preparing a multi-tree out-of-sample experiment

Prepare a deterministic sequence of trees without starting solver jobs:

```bash
julia --project=. scripts/prepare_oos_experiment.jl test \
  --config=config/testrun.yaml \
  --num-trees=3 \
  --seed-start=101 \
  --output=OutOfSample/test/experiment_seed101_3trees
```

This produces `oos_tree1`, `oos_tree2`, and `oos_tree3` with seeds 101–103.
The atomic `experiment.yaml` manifest records the immutable inputs and each
tree's preparation status. Repeating the command resumes the preparation:
valid completed trees are checksum-verified and skipped, while missing trees
are generated. A changed experiment specification or an invalid existing tree
is rejected rather than overwritten. Multi-tree preparation requires
`use_fixed_sample: false`; otherwise different seeds would not produce
independent trees.

This step only prepares inputs. It does not submit EMPIRE runs or aggregate
results. The corresponding library function is
`OpenEMPIRE.prepare_oos_experiment(config_file, data_folder, experiment_dir;
num_trees=..., seed_start=...)`.

### Preparing an out-of-sample execution queue

After the investment run and scenario trees are complete, prepare runner
commands without starting any jobs:

```bash
julia --project=. scripts/prepare_oos_execution_queue.jl test \
  --experiment=OutOfSample/test/experiment_seed101_3trees \
  --fixed-investment-dir=results/julia_runs/<investment-run> \
  --config=config/testrun.yaml \
  --solver=HiGHS
```

The command validates the experiment manifest and every tree checksum, checks
that the dataset and scenario-shaping configuration match, and verifies all
eight fixed-capacity result tables. It then writes `execution.yaml` under the
experiment directory. Each job contains an argument vector and copyable command
for the current `run_julia_empire.jl` interface, together with fields for
scheduler job ID, status, logs, and result location.

No command in the queue is executed. Repeating the preparation command preserves
existing `pending`, `submitted`, `running`, `complete`, or `failed` job state if
the experiment, runner, fixed investments, and commands are unchanged. Changed
inputs are rejected rather than silently replacing an active queue.

Inspect and update the queue without executing its commands:

```bash
# Show all states and the next pending command.
julia --project=. scripts/manage_oos_execution_queue.jl show \
  --queue=OutOfSample/test/experiment_seed101_3trees/execution.yaml

# Record a scheduler submission performed separately.
julia --project=. scripts/manage_oos_execution_queue.jl mark \
  --queue=OutOfSample/test/experiment_seed101_3trees/execution.yaml \
  --job=1 --status=submitted --job-id=<scheduler-job-id>

# Inspect matching run manifests and verify completed results.
julia --project=. scripts/manage_oos_execution_queue.jl reconcile \
  --queue=OutOfSample/test/experiment_seed101_3trees/execution.yaml
```

The controller never submits or starts jobs. It records audited state
transitions and discovers run directories under each job's result root.
Reconciliation checks that a run used the expected dataset, config,
fixed-investment source, tree metadata, and seed. It marks a result `complete`
only when the run manifest, fixed-capacity flag, scenario checksum flag,
termination status, and summary satisfy the queue's acceptance criteria.
Otherwise the job becomes `failed` with the reasons recorded. A failed job can
be returned to `pending` with the `mark` command for a deliberate retry.

### Preparing a Solstorm scheduler job

Solstorm uses Sun Grid Engine (SGE), so OOS jobs use `qsub`, `qstat`, and
`qacct` rather than Slurm commands. Generate an SGE script for the next pending
queue job without submitting it:

```bash
julia --project=. scripts/prepare_oos_sge_job.jl \
  --queue=OutOfSample/test/experiment_seed101_3trees/execution.yaml \
  --h-vmem=320G --h-rt=12:00:00 --mem-free=320G
```

The adapter follows the existing Solstorm high-memory-host and Julia/Gurobi
module conventions. It writes an executable `sge/oos_treeN.sge.sh`, records the
corresponding `qsub` command and log templates in `execution.yaml`, and prints
the command as **not executed**. Repeating it is safe when the generated script
is unchanged; a conflicting existing script is rejected.

The three resource options are optional and map directly to requestable SGE
resources. `h_vmem` bounds per-process virtual memory, `h_rt` bounds elapsed
runtime, and `mem_free` delays dispatch until a matching host reports the
requested free memory. Record evidence for the selected values instead of
copying the example values to a differently sized model.

Prepare the execution queue and SGE script on Solstorm after transferring the
repository, scenario experiment, and fixed-investment outputs. Queue commands
use absolute paths and checksums from the execution host; a queue prepared on a
local workstation is intentionally not portable to a different filesystem.

After a future manual or automated submission, captured scheduler output can be
fed back into the queue without letting the controller execute scheduler
commands:

```bash
julia --project=. scripts/manage_oos_execution_queue.jl sge-submit \
  --queue=<execution.yaml> --job=1 --input=<captured-qsub-output.txt>
julia --project=. scripts/manage_oos_execution_queue.jl sge-qstat \
  --queue=<execution.yaml> --job=1 --input=<captured-qstat-output.txt>
julia --project=. scripts/manage_oos_execution_queue.jl sge-qacct \
  --queue=<execution.yaml> --job=1 --input=<captured-qacct-output.txt>
```

Successful SGE accounting moves a job to `finished`, not `complete`.
`reconcile` must still validate the EMPIRE run manifest and summary. The queue
also fingerprints the Julia source, runner, dataset, config, trees, and fixed
investments, preventing a prepared scheduler job from silently running changed
inputs or code.
The generated SGE script repeats this fingerprint validation on the execution
node immediately before invoking the EMPIRE runner.

### Planning a one-tree Solstorm staging run

Create a locally validated staging plan before transferring an OOS smoke test:

```bash
julia --project=. scripts/prepare_oos_solstorm_staging.jl \
  --queue=OutOfSample/test/experiment_seed101_3trees/execution.yaml \
  --remote-user=<username> \
  --remote-root=/absolute/solstorm/path/openempire-oos \
  --sge-h-vmem=320G --sge-h-rt=12:00:00 --sge-mem-free=320G
```

This is a dry-run operation. It writes `staging.yaml` plus remote-adjusted tree
and experiment metadata, but it does not create archives, connect to Solstorm,
copy files, prepare a remote queue, or submit a scheduler job. The manifest
contains exact commands for those later steps, each marked `executed: false`.

The plan creates a unique workspace under `<remote-root>/stages/`, pins the
repository archive to the current Git commit, transfers the full base dataset,
one selected scenario tree, the execution and generation configurations, and
only the eight fixed-investment tables required by OOS. It records checksums
and includes a remote verification command that must pass before queue and SGE
preparation. The selected source tree is deliberately represented as
`oos_tree1` in a self-contained one-tree experiment.

`--remote-root` must be an absolute Solstorm path; `~` is rejected to prevent
local and remote path expansion from producing different manifests. If Julia
source or the runner differs from the selected Git revision, the plan is
written with `status: blocked`. Unrelated working-tree changes are recorded but
excluded from the revision-pinned repository archive.

### Running one out-of-sample scenario tree

Use the standard Julia runner with a completed investment run and one external
scenario-tree directory:

```bash
julia --project=. scripts/run_julia_empire.jl test \
  --config=config/testrun.yaml \
  --out-of-sample=true \
  --fixed-investment-dir=results/julia_runs/<investment-run> \
  --scenario-data-root=OutOfSample/test/oos_tree1
```

The scenario-tree directory must contain `ScenarioData/sloadRaw.csv`,
`maxRegHydroGenRaw.csv`, and `genCapAvailStochRaw.csv`. The investment directory
may be a run directory or its `Output`/`output` directory. The runner validates
both sources, copies the scenario inputs and eight strategic-capacity tables
under the new run's `Input/` directory, and modifies only the staged config to
read the supplied scenario tree. The shared dataset, original config, scenario
tree, and investment result are not modified. When the tree contains
`metadata.yaml`, the runner verifies its file checksums, stages the metadata,
and records the tree seed, full provenance, and base investment run in
`run_manifest.yaml`.

### Preparing chronological full-year OOS

Prepare one OOS tree for each selected complete non-leap historical year:

```bash
julia --project=. scripts/prepare_full_year_oos_experiment.jl europe_v51 \
  --config=config/run_2045_3sce.yaml \
  --sample-years=2015 \
  --format=csv \
  --output=OutOfSample/europe_v51/full_year_2015
```

The command only prepares inputs; it does not build or solve EMPIRE. It writes
`full_year_config.yaml`, `experiment.yaml`, and one checksummed `oos_treeN` per
sample year. Supply the generated `full_year_config.yaml`—not the original
representative-period config—to `prepare_oos_execution_queue.jl` and the Julia
runner.

Each strategic period receives the same selected historical profile as one
ordered 8760-hour operational scenario. The time structure contains one
regular period, one scenario, no dummy peak, and one storage cycle boundary at
the end of the year. `operational_hours_per_year: 8760` makes every modeled
hour's representative multiplicity exactly one. All required raw files must
contain exactly the same gap-free hourly non-leap year; source rows are sorted
by parsed timestamp before output because some historical files are stored in
a non-chronological row order.

This intentionally differs from InternalEMPIRE's current 24 independent
365-hour runs. In Julia, placing a 365-hour block inside
`RepresentativePeriods(8760, ...)` scales that block to a representative year,
and independent blocks also reset cyclic storage 24 times. Those semantics are
not a continuous chronological full-year evaluation.

Before an OOS queue or run is accepted, the source investment run must also
provide provenance. New Julia run manifests record a normalized investment
context and a checksum over the eight capacity tables. Older runs can be used
only when a preserved config plus `summary.txt` prove `optimize=true` and
`OPTIMAL`; these are explicitly labelled `reconstructed_legacy_run` rather
than being presented as manifest-verified. The runner stages this evidence as
`fixed_investment_provenance.yaml` and `source_config.yaml` beside its private
fixed-capacity inputs.

The following settings must match the investment run: forecast horizon,
investment-period length, North Sea mode, emission-cap mode, discount rate,
WACC, and load-change mode. Scenario generation/fixed-sample flags, scenario
count, representative seasons and peaks, operational period lengths, and time
format may differ intentionally for OOS—including chronological full-year
evaluation. Both the equality rules and the accepted differences are recorded
in the queue and run manifests. An incompatible setting fails before model
construction.

### Aggregating out-of-sample results

Aggregate one or more completed OOS run directories without rebuilding or
solving a model:

```bash
julia --project=. scripts/aggregate_out_of_sample_results.jl \
  results/julia_oos_runs/<experiment> \
  --output=results/julia_oos_aggregations/<experiment>
```

The command discovers OOS `run_manifest.yaml` files beneath the supplied
paths. Every selected run must be complete and feasible, must confirm fixed
investments and scenario checksums, and must have byte-identical staged
configurations and fixed-investment tables. It also verifies that all eight
capacity outputs still match their staged fixed inputs.

The aggregation writes:

```text
oos_tree_summary.csv
oos_ens_by_period_scenario.csv
oos_ens_by_period_scenario_season.csv
aggregation_manifest.yaml
combined/genOperational.csv
combined/transmissionOperational.csv
combined/storCharge.csv
combined/storDischarge.csv
combined/loadShed.csv
```

Combined operational files are streamed rather than loaded into memory and
add `Tree`, `Seed`, and `Run` identifiers. Use `--files=loadShed` to select a
smaller set or `--files=none` to produce only summaries. Existing non-empty
aggregation directories are rejected unless `--overwrite=true` is explicit.

Physical energy not served (ENS) is calculated from each load-shedding row as
`loadShed_MW * multiple_strat * probability * duration`. The scenario table
reports both conditional annual ENS (without scenario probability) and its
probability-weighted contribution. ENS is never discounted. Objective
components remain financial and discounted: fixed generator, storage, and
transmission investment costs are reported separately from the varying
non-investment objective so constant investment offsets do not dominate
cross-tree comparisons. The manifest records source and output checksums,
units, formula, threshold, and tree provenance.

### Comparable multi-seed Julia/Python parity runs

Scenario draws are **not** cross-language reproducible (Julia's RNG differs from
Python's `numpy`), so a shared `sampling_key.csv` is the unit of comparison. To
run both implementations on identical scenarios:

1. Generate a key once with one implementation, e.g. Julia
   `--generate-only --seed=<n>` (or Python `scripts/generate_scenarios.py`).
2. Copy the resulting `sampling_key.csv` into both repos' dataset
   `ScenarioData/` folders (verify with `md5`).
3. Run both with fixed sampling (`use_fixed_sample: true`, Julia
   `--fixed-sample`); each re-derives byte-identical `*Raw.csv` from the shared
   key.

Repeat with different seeds to build confidence that the two implementations stay
equivalent beyond a single sampled tree.

## Running on Solstorm

The repository includes a small Julia runner and a Solstorm SGE wrapper for a
first cluster smoke test.

To test locally without solving:

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=test \
  --config=config/testrun.yaml \
  --format=csv \
  --solver=HiGHS \
  --no-optimize
```

To run directly on Solstorm after copying the repo there:

```bash
sh scripts/run_empire_julia_basic_sge.sh test
```

The script asks SGE to choose an available high-memory Solstorm node,
instantiates the Julia project with `Pkg.instantiate()`, and runs:

```bash
julia --project=. scripts/run_julia_empire.jl --dataset=test
```

Results from the Julia runner are written under `results/julia_runs/`. At the
moment the runner writes a compact `summary.txt`; systematic result export is
still under development.

For one-command local-to-Solstorm deployment, create a cluster config:

```bash
cp config/cluster.sample.json config/cluster.json
```

Edit `config/cluster.json` with your Solstorm username and remote directory,
then run:

```bash
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm \
  --profile config/launch_profiles/2045_3sce_northsea.yaml
```

`config/cluster.json` should describe the cluster connection and scheduler
entrypoint. The launch profile describes the actual model run:

```yaml
dataset: europe_v51
model_config: config/run_2045_3sce.yaml
format: csv
solver: Gurobi
seed: 1
fixed_sample: true
optimize: true
perf: true
perf_interval: 2.0
```

Explicit flags can still override profile values when useful:

```bash
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm \
  --profile config/launch_profiles/2045_3sce_northsea.yaml \
  --dataset europe_v51 \
  --model-config config/run_2045_3sce.yaml \
  --format csv \
  --solver Gurobi \
  --seed 1 \
  --fixed-sample \
  --perf \
  --perf-interval 2.0
```

The default solver for this first Julia smoke test is HiGHS. Gurobi is loaded
by the SGE script when available and can be selected with:

```bash
JULIA_SOLVER=Gurobi sh scripts/run_empire_julia_basic_sge.sh test
```

For one-command deployment, set this in `config/cluster.json`:

```json
"JULIA_SOLVER": "Gurobi"
```

The default SGE host expression is the high-memory node group
`compute-4-51|compute-4-52|compute-4-53|compute-4-55|compute-4-56`. Override it
with `JULIA_SGE_HOSTS` in your environment or `config/cluster.json` if Solstorm
node availability changes.

The Julia project includes `Gurobi.jl`; on Solstorm, the script tries to load
`gurobi/13.0` first and then `gurobi/12.0`. If Gurobi license discovery fails,
check `GRB_LICENSE_FILE` in the job log and verify the Solstorm Gurobi module.

### Time structure

The time structure used by the model is built in `create_model`:

- A configurable number of *strategic periods* derived from
  `forecast_horizon_year` and `leap_years_investment`.
- 4 regular *operational seasons* with `length_of_regular_season` hours each.
- 2 *peak seasons* of 24 hours each, used to capture capacity-relevant
  extreme situations.
- `number_of_scenarios` stochastic *operational scenarios* per strategic
  period.

This structure is materialized as a `TimeStruct` object and used both for
indexing variables and constraints and for the probability and duration
weights in the objective.

## Packages used in the model

### TimeStruct.jl

[TimeStruct.jl](https://github.com/sintefore/TimeStruct.jl) is used to
represent the multi-horizon, two-stage stochastic time structure of EMPIRE in
a uniform way. A single `periods` object encodes:

- *Strategic periods* (`strat_periods(periods)`) over which investment
  decisions are taken.
- *Representative periods* (`repr_periods(periods)`) per strategic period,
  each with an associated weight.
- *Operational scenarios* (`opscenarios(periods)`) per representative period,
  each with an associated probability.
- *Operational time periods* within each scenario (the hours of the regular
  and peak seasons), each with a duration and a season scale factor used to
  expand sampled hours to a full year.

Iterating over `periods`, `repr_periods(periods)`, `strat_periods(periods)`, `opscenarios(periods)`
and the operational time periods within a scenario provides type-stable
indices that are used directly as variable and constraint indices in
[src/model_definition.jl](src/model_definition.jl). This avoids manual
bookkeeping of `(period, season, hour, scenario)` tuples and makes the
mapping between data and model unambiguous.

### SparseVariables.jl

[SparseVariables.jl](https://github.com/sintefore/SparseVariables.jl) extends
JuMP with sparse, dictionary-backed variable containers. EMPIRE has many
naturally sparse index sets. Using sparse variable containers with explicit 
valid index tuples lets the model:

- Allocate only the variables that actually appear in the formulation,
  keeping memory use and model build time low for European-scale instances.
- Iterate efficiently over the existing variables when constructing
  constraints and the objective, without filtering dense `JuMP.Containers`.

## Status and roadmap

Items that are known to be missing or under investigation compared to the
Python reference implementation are tracked in [TODO.md](TODO.md). Notable
open points include the North Sea extensions and the implementation of
emission limits, as well as a documented discrepancy in the annuity / present
value calculation for investment costs.
