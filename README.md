# OpenEMPIRE.jl

A Julia implementation of **EMPIRE** — the European Model for Power system
Investments with Renewable Energy. EMPIRE is a multi-horizon stochastic capacity
expansion model: it decides how much generation, storage and transmission to
build across European countries, while simultaneously simulating hourly
operation under a set of weather and load scenarios.

This is a reimplementation of the existing Python (Pyomo) version, built on:

- **[JuMP](https://jump.dev/)** as the modelling layer, so the model runs on any
  compatible LP solver (HiGHS, Gurobi, Xpress, CPLEX).
- **[TimeStruct.jl](https://github.com/sintefore/TimeStruct.jl)** to make the
  multi-horizon time structure explicit — strategic periods, operational
  seasons, peak hours and stochastic scenarios.
- **[SparseVariables.jl](https://github.com/sintefore/SparseVariables.jl)** so
  only valid index combinations (node/technology/period) are created.

---

## Quick start

If you already have Julia and just want to see it run:

```bash
git clone git@github.com:ntnuiotenergy/OpenEMPIRE.jl.git
cd OpenEMPIRE.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. scripts/run_julia_empire.jl --dataset=test --format=csv --solver=HiGHS
```

That solves the small bundled test instance in a couple of minutes and writes
results under `results/julia_runs/`.

If any of that is unfamiliar, follow the steps below instead.

---

## Step-by-step setup

### Step 1 — Install Julia

The recommended way is [juliaup](https://github.com/JuliaLang/juliaup), which
manages Julia versions for you.

```bash
# macOS / Linux
curl -fsSL https://install.julialang.org | sh
```

Restart your terminal, then check it worked:

```bash
julia --version
```

You should see something like `julia version 1.10.x`. Any recent 1.x release
works.

> **Note for Solstorm users:** the cluster has its own Julia modules. Use
> Julia **1.9.3** there — see [Running on Solstorm](#running-on-solstorm).

### Step 2 — Get the code

```bash
git clone git@github.com:ntnuiotenergy/OpenEMPIRE.jl.git
cd OpenEMPIRE.jl
```

### Step 3 — Install the dependencies

Julia keeps dependencies per project rather than globally. `--project=.` tells
Julia to use *this* repository's environment, defined by `Project.toml` and
`Manifest.toml`.

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

This downloads and precompiles everything the model needs. It takes a few
minutes the first time and is only needed once (repeat it after pulling changes
that touch `Project.toml`).

**You must pass `--project=.` on every command.** Without it Julia uses your
global environment and will not find `OpenEMPIRE`.

### Step 4 — Check the installation

```bash
julia --project=. test/runtests.jl
```

All test sets should report `Pass` with no failures. This takes a few minutes.

### Step 5 — Run your first model

The runner script is the normal way to run the model:

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=test \
  --config=config/testrun.yaml \
  --format=csv \
  --solver=HiGHS
```

What each part means:

| flag | meaning |
| --- | --- |
| `--dataset=test` | which folder under `data/` to read |
| `--config=config/testrun.yaml` | the run settings (horizon, scenarios, solver options) |
| `--format=csv` | read CSV inputs (`xlsx` also supported) |
| `--solver=HiGHS` | which solver to use |

Useful extra flags:

| flag | meaning |
| --- | --- |
| `--no-optimize` | build the model but don't solve — a fast sanity check |
| `--generate-only` | only generate scenario data, then stop |
| `--seed=1` | seed for random scenario sampling |
| `--fixed-sample` | reuse the dataset's existing `sampling_key.csv` |
| `--results=PATH` | where to write output (default `results/julia_runs`) |

A good first check that everything is wired up, without waiting for a solve:

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=test --format=csv --solver=none --no-optimize
```

### Step 6 — Find your results

Each run creates a timestamped folder:

```text
results/julia_runs/20260814_113000_test/
├── Input/              copy of the config and scenario data actually used
├── output/             result tables (CSV)
├── run_manifest.yaml   machine-readable record of the run
└── summary.txt         objective value, solver status, timings, model size
```

`summary.txt` is the first thing to look at — it records the objective value,
termination status, model size and how long each stage took.

The `Input/` copy matters: it captures exactly which config and sampled scenario
data produced these results, so a run stays reproducible even if you later edit
the config.

---

## Choosing a solver

| solver | licence | when to use |
| --- | --- | --- |
| **HiGHS** | free, bundled | learning, the `test` dataset, small runs |
| **Gurobi** | commercial (free academic licence) | anything realistic |

Full-scale European runs are large — tens of millions of variables — and in
practice need Gurobi. HiGHS is fine for the test dataset and for checking that
the model builds.

NTNU students and staff can get a free academic Gurobi licence. Once installed
and licensed, pass `--solver=Gurobi`.

`Gurobi.jl` is a declared dependency, so `Pkg.instantiate()` installs it whether
or not you have a licence. You only need a licence when you actually solve with
`--solver=Gurobi`; HiGHS runs work without one.

---

## How a run is configured

Three things decide what a run does:

1. **The dataset** (`data/<name>/`) — the physical system: nodes, generators,
   costs, transmission topology, and raw weather/load time series.
2. **The config file** (`config/<name>.yaml`) — the run settings: how far into
   the future, how many scenarios, how long the seasons, which solver options.
3. **Command-line flags** — which dataset and config to combine, plus overrides.

### Bundled datasets

| dataset | what it is |
| --- | --- |
| `test` | small instance, solves in 1–2 minutes — start here |
| `test_excel` | the same idea, in the older Excel format |
| `europe_v51` | full European dataset |
| `europe_v50` | older full dataset |

### The config file

Config files live in `config/`. `config/testrun.yaml` is the default and is
commented throughout. The keys you are most likely to change:

```yaml
forecast_horizon_year: 2030      # last year modelled; periods are 5 years each
number_of_scenarios: 3           # weather/load scenarios per investment period
length_of_regular_season: 24     # hours per representative season
discount_rate: 0.05
wacc: 0.05                       # weighted average cost of capital
use_scenario_generation: True    # sample scenarios from the raw time series
use_fixed_sample: False          # True = reuse the stored sampling_key.csv
use_emission_cap: True           # True = CO2 cap; False = CO2 price
north_sea: False                 # optional offshore transmission cap
```

**Horizon and periods.** The model steps in 5-year investment periods starting
from 2020, so `forecast_horizon_year: 2060` means 8 periods. A dataset must
actually contain data for every period you ask for.

**Run size.** Solve time is driven mainly by
`number_of_scenarios × length_of_regular_season × number of periods`. For a
first full-scale run, reduce the horizon or the scenario count rather than
starting at maximum.

### Solver options

Solver settings also live in the config file and are passed straight through to
Gurobi. Leave a key out to keep the Gurobi default.

```yaml
solver_method: 2             # 2 = barrier, usually best for large LPs
solver_crossover: 0          # 0 = skip crossover (much faster on large runs)
solver_numericfocus: 1       # more careful numerics
# solver_presolve: 2         # aggressive presolve
# solver_threads: 16
```

**On large runs, keep `solver_crossover: 0`.** Barrier finds the optimum on its
own; leaving crossover enabled can add hours of extra work afterwards.

---

## Running on Solstorm

Solstorm is NTNU IØT's compute cluster. Full-scale EMPIRE runs need far more
memory than a laptop (hundreds of GB), so they run there.

### Before you start — the ground rules

- **Always connect through the login server:**
  `<username>@solstorm-login.iot.ntnu.no`, not `solstorm.iot.ntnu.no`.
- **Never run computation on the login or head server.** That includes Julia
  precompilation and data preparation. Submit it as a job, or run it on a
  compute node inside `screen`.
- **Write run outputs to `/storage/users/<username>`, not your home directory.**
  Home is for code and small files. Storage is for working data — and is treated
  as temporary.
- **There are no backups.** Copy anything you want to keep back to your own
  machine.

### One-time setup

**1. Copy the cluster config template:**

```bash
cp config/cluster.sample.json config/cluster.json
```

**2. Edit `config/cluster.json`** with your details:

```json
{
  "Solstorm": {
    "REMOTE_USER": "your_username",
    "REMOTE_SERVER": "solstorm-login.iot.ntnu.no",
    "REMOTE_DIR": "~/OpenEMPIRE.jl",
    "SCHEDULER_SCRIPT": "./scripts/run_empire_julia_basic_sge.sh",
    "JULIA_SOLVER": "Gurobi",
    "JULIA_CMD": "julia",
    "JULIA_SGE_HOSTS": "compute-6-24|compute-6-25|compute-6-26"
  }
}
```

`config/cluster.json` is gitignored — it holds your personal settings and is
never committed.

**3. Make sure SSH works:**

```bash
ssh your_username@solstorm-login.iot.ntnu.no
```

### Launch profiles — describing a run once

A **launch profile** is a small YAML file that records everything about a run,
so you don't retype a dozen flags and so the run is reproducible. They live in
`config/launch_profiles/`:

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
sge_hosts: "compute-6-24|compute-6-25|compute-6-26"
```

| key | meaning |
| --- | --- |
| `dataset` | folder under `data/` |
| `model_config` | which config YAML to use |
| `seed` | scenario sampling seed |
| `fixed_sample` | reuse the stored `sampling_key.csv` instead of drawing new scenarios |
| `optimize` | `false` builds the model without solving |
| `perf` / `perf_interval` | record memory and timing during the run |
| `sge_hosts` | which compute nodes are acceptable |

The distinction is worth remembering:

- `config/cluster.json` = **where and how to connect** (your account, the cluster)
- `config/launch_profiles/*.yaml` = **what to run** (dataset, config, seed)

### Submitting a run

One command copies the repository to Solstorm and submits the job:

```bash
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm \
  --profile config/launch_profiles/2045_3sce_northsea.yaml
```

Check what it would do without actually submitting:

```bash
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm \
  --profile config/launch_profiles/2045_3sce_northsea.yaml \
  --dry-run
```

Any profile value can be overridden on the command line:

```bash
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm \
  --profile config/launch_profiles/2045_3sce_northsea.yaml \
  --seed 3 \
  --no-optimize
```

Run `sh scripts/copy_and_run_julia_on_hpc.sh --help` for the full flag list.

### If you are already on Solstorm

To submit from a checkout that already lives on the cluster:

```bash
sh scripts/run_empire_julia_basic_sge.sh test
```

This asks SGE for a high-memory node, instantiates the Julia project, and runs
the model. The solver can be selected with an environment variable:

```bash
JULIA_SOLVER=Gurobi sh scripts/run_empire_julia_basic_sge.sh test
```

### Monitoring a job

```bash
qstat                      # your jobs: qw = queued, r = running
qhost                      # actual node load — qstat does not show everything
tail -n 200 logs/julia_empire_<JOBID>.out
```

Logs land in `logs/` as `*_<JOBID>.out` and `*_<JOBID>.err`.

**Avoid `tail -f` over a plain SSH connection.** If the connection drops, the
process is orphaned and keeps running on the server. Use a bounded `tail -n`, or
run `tail -f` inside `screen` so you can reattach and kill it.

`screen` basics: `screen` to start, `Ctrl-A` then `D` to detach, `screen -ls` to
list, `screen -rd <id>` to reattach.

### Getting results back

```bash
scp -r your_username@solstorm-login.iot.ntnu.no:/storage/users/your_username/<run> ./
```

Because jobs are submitted through SGE, they keep running after you disconnect —
you do not need `screen` for the run itself, only for interactive work.

---

## Troubleshooting

**`Package OpenEMPIRE not found`**
You forgot `--project=.`. Every command needs it.

**`ERROR: Unsatisfiable requirements` during `Pkg.instantiate()`**
Usually a Julia version mismatch. Check `julia --version`; on Solstorm use 1.9.3.

**Gurobi licence errors**
Check that `GRB_LICENSE_FILE` points at a valid licence. On Solstorm the job
script loads the Gurobi module automatically; the job log shows which one.

**The solve is extremely slow, or memory runs out**
Reduce `number_of_scenarios`, `length_of_regular_season`, or
`forecast_horizon_year`. Full-scale runs need a cluster node, not a laptop.
Confirm `solver_crossover: 0` is set.

**Warnings about "initial capacity exceeds maximum installed capacity"**
Expected on some datasets. The model raises the maximum to the initial value and
continues.

**Gurobi warns about "large rhs" or Markowitz tolerances**
Expected, and not a failure. If results look numerically suspect, try
`solver_numericfocus: 1`.

**A job disappears without output**
Check the `.err` file in `logs/`. Out-of-memory kills are the usual cause; pick a
larger node or reduce the run size.

---

## Using the model from Julia directly

The runner script is the easy path, but the model can also be built directly.
The entry point is `OpenEMPIRE.create_model`, in
[src/user_interface.jl](src/user_interface.jl). It takes a config file and a data
folder and returns the JuMP model along with the time structure, sets and
parameters:

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

Solving is a separate step:

```julia
JuMP.optimize!(emp)
```

Results can be read directly from the JuMP variables (`emp[:genOperational]`,
`emp[:genInvCap]`, `emp[:storCharge]`, `emp[:transmissionInvCap]`,
`emp[:loadShed]`, …) using `value` and the helpers in `JuMP.Containers`:

```julia
genInvCap = Containers.rowtable(
    value, emp[:genInvCap];
    header = [:Node, :Generator, :Period, :Investment],
)
filter!(r -> r.Investment > 0, genInvCap)
```

See [test/test_interface.jl](test/test_interface.jl) for further examples
covering investments, dispatch, storage operation, transmission flows and load
shedding.

---

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

Set `filter_make: true` to cluster the possible regular-season load windows and
write `ScenarioData/filter_result.csv`. Set `filter_use: true` to restrict
sampling to that file, rotating through cluster groups `0:n_cluster-1`; both
flags may be enabled to build and immediately use a new filter. The defaults are
`filter_make: false`, `filter_use: false`, and `n_cluster: 10`. Filter candidates
use only years shared by every sampled raw input, while the Python reference
hard-codes 2015–2019; candidate-key parity therefore applies when those year
sets coincide. Filter creation consumes the scenario RNG, so a fixed seed
reproduces a run in the same mode, but make-and-use and reuse-only runs may
produce different sampling keys. Fixed sampling takes precedence over
`filter_use`. Python parity compares candidate identity and numerical
Wasserstein/mean metrics because K-means labels are arbitrary between
implementations. Enabled filters are archived with their sampling key under
`results/julia_runs/<run>/Input/ScenarioData/`.

See [FILTER_COMPARISON.md](FILTER_COMPARISON.md) for the reproducible
Python–Julia metric comparison and the cluster-count sweep from 1 to 30.

Set `copula_clusters_make: true` to sort the possible regular-season windows into
clusters and write `Copulas/CopulaClusters/copula_clusters.csv`. The clustering
looks at how the variables in `copulas_to_use` move together across nodes, not at
how large their values are. Set `copula_clusters_use: true` to sample from that
file, cycling through cluster groups `0:n_cluster-1`. Turn on both flags to build
a new file and use it in the same run.

The defaults are `copula_clusters_make: false`, `copula_clusters_use: false`,
`copulas_to_use: ["electricload"]`, and `n_cluster: 10`. You can cluster on
`electricload`, `hydroseasonal`, `solar`, `windonshore`, `windoffshore`, or
`hydroror`. Clustering uses the scenario RNG, so the same seed gives the same
file. It runs once per `copula_clusters_make` run, and takes longer when the
chosen variables cover more nodes. If more than one sampling mode is on,
`use_fixed_sample` wins over `filter_use`, and `filter_use` wins over
`copula_clusters_use`. The file is saved with the sampling key under
`results/julia_runs/<run>/Input/ScenarioData/`.

### Generating out-of-sample scenario trees

Use `scripts/create_out_of_sample_tree.jl` to generate one or more scenario trees
without building or solving a model:

```bash
julia --project=. scripts/create_out_of_sample_tree.jl test \
  --config=config/testrun.yaml \
  --num-trees=3 \
  --seed=1
```

This writes generated OOS scenario inputs under:

```text
OutOfSample/<dataset>/oos_tree1/ScenarioData/
OutOfSample/<dataset>/oos_tree2/ScenarioData/
OutOfSample/<dataset>/oos_tree3/ScenarioData/
```

Each tree folder also gets a `metadata.yaml` file with the dataset, seed, config,
and scenario settings used to generate it. Internally, the script reuses
`OpenEMPIRE.generate_scenarios`, so the generated files are first written to
`data/<dataset>/ScenarioData` and then copied into the corresponding
`OutOfSample/<dataset>/oos_treeN/ScenarioData` folder.

### North Sea / offshore transmission cap

The Python reference model has an optional North Sea transmission cap, and the
Julia port implements it. When `north_sea: true` is set in the run config *and*
the dataset provides `Sets/OffshoreNode.csv`, the `wind_farm_transmission_cap`
constraint family is created. It caps each offshore-adjacent transmission
corridor by the installed generation capacity at the offshore endpoint, keeping
the Python implementation's ordered-arc row structure (both directions of a
corridor are emitted, pointing at the same canonical corridor capacity).

When `north_sea: false`, the offshore set may still exist in the data but no cap
constraints are created. This is deliberate: the config flag, not the data
layout, decides whether the optional formulation is active.

**`OffshoreNode` must list only nodes whose generation should limit their
corridors.** The cap's right-hand side is a sum over the offshore endpoint's
generators, so an entry with *no* generators yields an empty sum and the
constraint becomes `transmissionInstalledCap <= 0`, disconnecting that node.
This matches the Python behaviour exactly — Python computes the same empty sum —
but it makes the set's contents load-bearing. `europe_v51` lists exactly the 14
offshore wind farms. Datasets that derive the set as "all nodes minus onshore
nodes" can sweep in energy hubs or platforms that carry no generators; those
belong in a separate formulation (the Python internal model gives energy hubs
their own converter capacity constraints), not in this one. A warning is logged
for any offshore node that ends up with an empty right-hand side.

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

North-sea-on parity at europe_v51 2060/5sce/168h (38,120,648 variables,
54,452,000 constraints, all `OPTIMAL`, `wind_farm_transmission_cap: 1728` in
every Julia build log):

| seed | Julia | Python | relative difference |
| ---- | ----- | ------ | ------------------- |
| 3 | `4.634430286661141e12` | `4.63443031e12` | 5.0e-9 |
| 4 | `4.662211214996041e12` | `4.66221071e12` | 1.1e-7 |
| 5 | `4.724774434584402e12` | `4.72477447e12` | 7.5e-9 |
| 6 | `4.661684419314461e12` | `4.66168444e12` | 4.4e-9 |

Python values are as printed by the solver log. Baseline north-sea-*off* parity
is closed for matched configs at the same scale, and north-sea-on 2045/3sce/168h
agrees to solver tolerance as well.

---

## Time structure

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

Open points and known differences from the Python reference implementation are
tracked in [TODO.md](TODO.md).
