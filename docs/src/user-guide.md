# Running the model

## Quick start

From a fresh checkout, instantiate the project and run the bundled test
instance:

```bash
git clone git@github.com:ntnuiotenergy/OpenEMPIRE.jl.git
cd OpenEMPIRE.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. scripts/run_julia_empire.jl --dataset=test --format=csv --solver=HiGHS
```

The run writes results under `results/julia_runs/`. Pass `--project=.` on
every Julia command so that the repository environment is used.

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

```julia
using HiGHS
using JuMP
using OpenEMPIRE

data_folder = joinpath(pkgdir(OpenEMPIRE), "data", "test_excel")
config_file = joinpath(data_folder, "testrun.yaml")

emp, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    optimizer = HiGHS.Optimizer,
)
JuMP.optimize!(emp)
```

`create_model` reads the YAML configuration, constructs the time structure, loads structural and stochastic inputs, creates JuMP variables and constraints, and adds the discounted objective. It returns the JuMP model together with `periods`, `sets`, and `params` for inspection.

To build without attaching an optimizer, omit the `optimizer` keyword. To fix strategic capacities for an out-of-sample operational run, use `include_investment_constraints = false` and supply the fixed capacities through the runner workflow.

