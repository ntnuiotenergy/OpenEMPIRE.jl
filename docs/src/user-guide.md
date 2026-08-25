# Running the model

## Requirements

Install Julia 1.10 or newer, clone the repository, and instantiate the project:

```powershell
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

A linear optimization solver is also required. The bundled examples use [HiGHS](https://highs.dev/), which is included in the project. Gurobi is available when its Julia package and license are configured. JuMP also supports other compatible solvers when using the library interface.

Run the test suite with:

```powershell
julia --project=test test/runtests.jl
```

## Build and solve from Julia

```julia
using HiGHS
using JuMP
using OpenEMPIRE

data_folder = joinpath(pkgdir(OpenEMPIRE), "data", "test")
config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")

emp, periods, sets, params = OpenEMPIRE.create_model(
    config_file,
    data_folder;
    optimizer = HiGHS.Optimizer,
)
JuMP.optimize!(emp)
```

`create_model` reads the YAML configuration, constructs the time structure, loads structural and stochastic inputs, creates JuMP variables and constraints, and adds the discounted objective. It returns the JuMP model together with `periods`, `sets`, and `params` for inspection.

To build without attaching an optimizer, omit the `optimizer` keyword. To fix strategic capacities for an out-of-sample operational run, use `include_investment_constraints = false` and supply the fixed capacities through the runner workflow.

## Inspect results

There is not yet a complete Julia equivalent of the Python output package. After optimization, inspect JuMP containers directly:

```julia
using JuMP

gen_investment = Containers.rowtable(
    value,
    emp[:genInvCap];
    header = [:Node, :Generator, :Period, :Investment],
)
filter!(row -> row.Investment > 0, gen_investment)
```

Common containers include `genOperational`, `genInvCap`, `storCharge`, `storDischarge`, `storENInvCap`, `storPWInvCap`, `transmissionOperational`, `transmissionInvCap`, and `loadShed`. The functions `write_solution_tables`, `sol_invest_cost`, and `sol_operational_cost` are available for targeted result work.

## Command-line runner

For a repository checkout, the standard runner is:

```powershell
julia --project=. scripts/run_julia_empire.jl `
  --dataset=test `
  --config=config/testrun.yaml `
  --format=csv `
  --solver=HiGHS
```

Useful options include:

- `--no-optimize` builds and stages a model without solving it.
- `--generate-only` prepares stochastic inputs and exits before model construction.
- `--fixed-sample` reuses `ScenarioData/sampling_key.csv`.
- `--solver=Gurobi` selects Gurobi when it is configured.
- `--results=<directory>` changes the run output root.

The runner stores run inputs and a compact summary under `results/julia_runs/`. It does not currently provide the full Python output and charting workflow.

## HPC execution

The repository includes SGE support for Solstorm:

```powershell
sh scripts/run_empire_julia_basic_sge.sh test
```

For a configured remote deployment, copy `config/cluster.sample.json` to `config/cluster.json`, edit the connection details, and use a launch profile with `scripts/copy_and_run_julia_on_hpc.sh`.
