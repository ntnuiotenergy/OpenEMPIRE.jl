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

### Running one out-of-sample evaluation

The Julia runner can consume one generated OOS tree directly. Structural data is
read from `data/<dataset>`, while stochastic scenario data is read from the
folder passed with `--scenario-data-root`. That folder should contain a
`ScenarioData/` subdirectory.

```bash
julia --project=. scripts/run_julia_empire.jl test \
  --config=config/testrun.yaml \
  --out-of-sample=true \
  --fixed-investment-dir=results/julia_runs/<base_investment_run> \
  --scenario-data-root=OutOfSample/test/oos_tree1
```

When `--scenario-data-root` is provided, the runner writes a generated run config
with `use_scenario_generation: false`, so the model reads the generated OOS
scenario CSVs instead of sampling a new tree. OOS solution tables are written
under:

```text
results/julia_runs/<timestamp>_<dataset>/OutOfSample/oos_tree1/output/
```

### Running multiple out-of-sample evaluations

Use `scripts/run_out_of_sample_trees.jl` to evaluate all generated trees with
the same fixed investments:

```bash
julia --project=. scripts/run_out_of_sample_trees.jl test \
  --config=config/testrun.yaml \
  --trees-root=OutOfSample/test \
  --fixed-investment-dir=results/julia_runs/<base_investment_run> \
  --solver=HiGHS \
  --num-trees=3
```

Trees are discovered as `oos_treeN`, sorted numerically, validated, and run
sequentially in separate Julia processes. This keeps peak memory close to one
model and ensures memory is returned when each process exits. An infeasible
tree is recorded and does not prevent later trees from running.

Results are grouped under one batch directory:

```text
results/julia_oos_runs/<timestamp>_<dataset>/
├── batch_summary.csv
├── batch_summary.txt
├── oos_tree1/
│   ├── output/
│   ├── runner.out
│   ├── runner.err
│   └── summary.txt
└── oos_tree2/
```

`batch_summary.csv` is updated after each tree and records its termination
status, objective when available, timings, result directory, and process error.
Use `--first-tree=N` to select a later starting tree, `--num-trees=all` to run
every available tree, and `--continue-on-error=false` to stop after a process
failure.

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

The script selects one of the high-memory Solstorm nodes, instantiates the
Julia project with `Pkg.instantiate()`, and runs:

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
sh scripts/copy_and_run_julia_on_hpc.sh Solstorm
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
