# OpenEMPIRE Run Pipeline Improvements

This note captures suggested improvements to the way OpenEMPIRE runs are configured,
submitted, reproduced, and compared across Julia and Python.

## Current Pain Points

Run intent is currently split across several mechanisms:

- model config YAML files, such as `config/run_2045_3sce.yaml`
- local cluster config JSON, such as `config/cluster.json`
- shell environment variables, such as `JULIA_SOLVER`, `JULIA_FIXED_SAMPLE`, and `EMPIRE_PERF`
- CLI flags in `scripts/run_julia_empire.jl` and `scripts/run.py`
- SGE wrapper behavior in `scripts/run_empire_julia_basic_sge.sh` and `scripts/run_empire_basic_sge.sh`

This is flexible, but it makes it too easy to run almost the same experiment twice
without realizing that one detail differs.

## Recommended Direction

### 1. Use One Run Spec

Create a single run specification file that fully describes the run:

```yaml
run:
  name: 2045_3sce_northsea_compare
  runtime: julia
  dataset: europe_v51
  config: config/run_2045_3sce.yaml
  input_format: csv
  seed: 1

scenario:
  mode: fixed_sample
  sampling_key: data/europe_v51/ScenarioData/sampling_key.csv

solver:
  name: Gurobi
  method: 2
  crossover: 0
  presolve: 2
  threads: null

features:
  north_sea: true
  emission_cap: false

execution:
  target: solstorm
  queue: all.q
  memory_class: high
  perf: true
  perf_interval: 2.0

outputs:
  root: results/julia_runs
  write_solution_csvs: true
  include_string_names: false
```

Then the run command becomes explicit:

```bash
empire-run --spec runs/2045_3sce_northsea_julia.yaml
```

### 2. Stage Inputs Per Run

Treat source datasets as immutable. A run should copy or stage its input data into
the run directory before scenario generation or model construction.

Recommended layout:

```text
data/europe_v51/                  # source dataset, not mutated by runs
results/julia_runs/<run>/Input/    # staged input used by this run
results/julia_runs/<run>/Output/   # model outputs
results/julia_runs/<run>/run.yaml  # resolved run configuration
```

This avoids dirtying reusable input folders and makes each run self-contained.

### 3. Write a Resolved Run Manifest

Every run should emit a complete `run_manifest.yaml` or `run_manifest.json` with:

- runtime and code version
- git commit and dirty-state flag
- dataset and config paths
- resolved model configuration
- solver settings
- scenario mode and sampling-key checksum
- host, job id, and scheduler metadata
- package/runtime versions
- output paths

This removes guesswork after long HPC runs.

### 4. Keep Generated Configs Out of `config/`

Generated fixed-sample configs should live under the run directory, not under the
repository's source `config/` directory.

Prefer:

```text
results/<runtime>_runs/<run>/Input/resolved_config.yaml
```

over:

```text
config/<dataset>_fixed_sample.generated.yaml
```

### 5. Let the Scheduler Schedule

The Solstorm wrappers currently select a high-memory node by counting jobs. This
can pick unavailable nodes. Prefer scheduler resource requests, or at least filter
out unavailable node states before hard-pinning a hostname.

Conceptually:

```bash
qsub -l h_vmem=120G -pe smp 16
```

or, if host pinning is required, query real queue/node state before choosing.

### 6. Separate Environment Setup From Runs

Jobs should fail fast if dependencies are missing. They should not install or
mutate dependencies during the run.

Prefer explicit setup/check commands:

```bash
empire-env install
empire-env check
empire-run --spec runs/my_run.yaml
```

For Julia, preserve `Manifest.toml` for reproducible project instantiation unless
there is a deliberate reason not to.

### 7. Add a First-Class Comparison Runner

Python/Julia parity runs should be launched by one command that guarantees the same
dataset, scenario sample, solver settings, and perf instrumentation:

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

The command should:

1. generate or validate one shared sampling key
2. stage equivalent inputs for both runtimes
3. submit both jobs
4. record job ids
5. collect logs, perf artifacts, and scheduler accounting
6. produce the comparison report

## Practical Priority

1. Emit a resolved run manifest for every run.
2. Stage Julia inputs into each run directory, matching Python's safer pattern.
3. Move generated configs into run directories.
4. Replace scattered environment-variable driven run state with a run spec.
5. Improve Solstorm node selection or let SGE choose.
6. Preserve `Manifest.toml` for Julia HPC runs.
7. Add a first-class Python/Julia comparison command.
