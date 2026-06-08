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

data_folder = joinpath(pkgdir(OpenEMPIRE), "data")
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
Currently, only Excel support is implemented.  

The generation of scenario data is not available yet in the Julia version
and needs to be generated in Python and read in as `.tab` files.

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

