# Run configuration files

Every run is described by a YAML file in this folder. It answers three questions:
**how far ahead and at what resolution**, **which optional modules are on**, and
**how the solver should behave**. The dataset is chosen separately, on the command
line.

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=full_model_int --config=config/run_int_full_gas.yaml --format=csv --solver=Gurobi
```

A key that the code does not read is silently ignored, so a typo behaves exactly
like an omission. If a setting seems to have no effect, check the spelling against
the tables below.

---

## The modules, and how they depend on each other

Three optional modules sit on top of the base electricity model. Each is **off by
default**, and they form a chain rather than a menu:

```
                base electricity model
                          │
                   natural_gas: true
                    │            │
          hydrogen: true    industry: true
```

**Natural gas is the foundation.** Both hydrogen and industry need it, and the
model refuses to build without it:

| you set | you must also set | error if you don't |
| --- | --- | --- |
| `hydrogen: true` | `natural_gas: true` | `hydrogen=true requires natural_gas=true` |
| `industry: true` | `natural_gas: true` | `industry=true requires natural_gas=true` |

**Industry does not require hydrogen.** `natural_gas: true, industry: true,
hydrogen: false` is a valid combination — steel, cement and ammonia consume gas
and electricity directly. In practice industry is usually run with hydrogen on,
because hydrogen-based steel is the interesting case, but nothing forces it.

**Hydrogen and industry are deterministic**, so they require a single gas
scenario:

```yaml
number_of_gas_scenarios: 1     # required when hydrogen or industry is on
```

Anything else raises `Deterministic Hydrogen requires number_of_gas_scenarios=1`
(or the industry equivalent).

**All three modules require the CSV dataset layout.** An `.xlsx` dataset is
rejected with *"The natural-gas, Hydrogen, and Industry modules require the
validated CSV dataset layout"*. Use `--format=csv`.

**One coupling that is easy to miss:** natural-gas *transport* demand is part of
the hydrogen module, not the gas module. With `hydrogen: false` there is no gas
transport demand at all, even when gas is on. This mirrors InternalEMPIRE, where
the transport variables are declared inside its hydrogen block, and was confirmed
as intended.

### Valid combinations

| gas | hydrogen | industry | valid | what you get |
| --- | --- | --- | --- | --- |
| false | false | false | yes | base electricity model |
| true | false | false | yes | gas terminals, pipelines, storage; no transport demand |
| true | true | false | yes | electrolysers, reformers, CO2, transport demand |
| true | false | true | yes | steel/cement/ammonia on gas and electricity |
| true | true | true | yes | the full model |
| false | true | — | **no** | hydrogen requires gas |
| false | — | true | **no** | industry requires gas |

---

## Building a run config

Start from an existing file rather than a blank one — `testrun.yaml` is the
smallest and is commented throughout. The settings below are the ones that
actually change what is solved.

### Horizon and resolution

```yaml
forecast_horizon_year: 2055      # last year modelled
leap_years_investment: 5         # years per investment period
length_of_regular_season: 168    # hours in each representative season
number_of_scenarios: 5           # weather/load scenarios per period
```

Periods run from 2020 in steps of `leap_years_investment`, so 2055 with 5-year
steps is **7 periods**. The dataset must actually contain data for every period
you ask for: `full_model_int` ships 7, so 2055 is its ceiling.

Solve time and memory are driven mainly by

```
number_of_scenarios × length_of_regular_season × number of periods
```

To make a run smaller, cut the horizon or the scenario count first.

Optional, if the defaults do not suit:

```yaml
regular_seasons: ["winter", "spring", "summer", "fall"]
n_peak_seasons: 2
len_peak_season: 24
operational_hours_per_year: 8760   # only for chronological full-year OOS
```

### Economics and the emission constraint

```yaml
discount_rate: 0.05
wacc: 0.05
use_emission_cap: True    # True = CO2 cap from the data; False = CO2 price
```

`use_emission_cap` picks one of two mutually exclusive mechanisms. With `True`
the model reads `CO2cap.csv` and constrains emissions; with `False` it reads
`CO2price.csv` and prices them into the marginal cost. Both files usually exist in
a dataset — the flag decides which one matters.

### Scenario sampling

```yaml
use_scenario_generation: True   # sample scenarios from the raw time series
use_fixed_sample: True          # reuse the dataset's stored sampling_key.csv
time_format: "%d/%m/%Y %H:%M"
```

`use_fixed_sample: True` is what makes two runs comparable: both re-derive the
same weather from the same stored key. Set it to `False` to draw a fresh sample
and write a new key.

Optional selection methods, all off by default:

```yaml
filter_make: False              # cluster the candidate windows, write filter_result.csv
filter_use: False               # sample only from those clusters
n_cluster: 10
copula_clusters_make: False     # cluster on co-movement between variables
copula_clusters_use: False
copulas_to_use: ["electricload"]
```

If more than one is enabled, `use_fixed_sample` wins over `filter_use`, and
`filter_use` wins over `copula_clusters_use`.

### Offshore

```yaml
offshore_transmission_cap: true   # default; caps wind-farm corridors by their own generation
```

The older `north_sea` key is obsolete. It is ignored and warned about rather than
silently accepted, because runs were once submitted with `north_sea: true` against
a build that no longer read it.

### Solver

Passed straight through to Gurobi. Leave a key out to keep the Gurobi default —
an absent key is not the same as setting it to zero.

```yaml
solver_method: 2            # 2 = barrier, best for large LPs
solver_crossover: 0         # 0 = skip crossover
solver_presolve: 1
solver_numericfocus: 1
solver_barhomogeneous: 1
solver_barconvtol: 1.0e-8
solver_feasibilitytol: 1.0e-9
solver_scaleflag:
solver_seed: 2
solver_threads: 16
```

Two settings worth knowing before a large run:

- **`solver_crossover: 0`.** Barrier finds the optimum on its own; leaving
  crossover on can add hours after the answer is already known, and it has proven
  numerically unusable at full scale.
- **`solver_barhomogeneous: 1`.** On the full model this closed the duality gap by
  roughly four orders of magnitude compared with the standard barrier, at about
  2.4× the cost per iteration.

`solver_presolve: 2` is best avoided — it has stalled the barrier on this model.

---

## Worked examples

**Base electricity only, small and fast** — start here:

```yaml
forecast_horizon_year: 2030
number_of_scenarios: 3
length_of_regular_season: 24
discount_rate: 0.05
wacc: 0.05
use_scenario_generation: True
use_fixed_sample: False
use_emission_cap: True
leap_years_investment: 5
time_format: "%d/%m/%Y %H:%M"
```

**Gas at full scale** — add the module and its scenario count:

```yaml
forecast_horizon_year: 2055
number_of_scenarios: 5
length_of_regular_season: 168
natural_gas: True
number_of_gas_scenarios: 1
use_fixed_sample: True
solver_method: 2
solver_crossover: 0
solver_numericfocus: 1
solver_barhomogeneous: 1
```

**Everything on** — note that all three flags appear, and gas must be among them:

```yaml
natural_gas: True
hydrogen: True
industry: True
number_of_gas_scenarios: 1
```

---

## What lives here

| file | what it is for |
| --- | --- |
| `testrun.yaml` | the default; smallest useful run |
| `run_2030_1sce.yaml`, `run_2045_3sce.yaml`, `run_2060*.yaml` | europe_v51 runs at increasing size |
| `run_full_model_int.yaml` | full_model_int, base settings |
| `run_int_2030_*_fast.yaml` | reduced module runs, minutes not hours |
| `run_int_full_gas.yaml`, `run_int_full_hydrogen.yaml`, `run_int_full_industry.yaml` | full-scale module runs |
| `run_int_*_offshore*.yaml` | offshore comparison runs |
| `industry_reference_comparison.yaml` | reduced industry parity fixture |
| `launch_profiles/` | *not* run configs — see below |
| `cluster.sample.json` | template for `cluster.json` (gitignored) |

### Run configs versus launch profiles

These are easy to confuse because both are YAML in this folder:

- **a run config** (`run_*.yaml`) describes **what to solve** — horizon, scenarios,
  modules, solver settings;
- **a launch profile** (`launch_profiles/*.yaml`) describes **how to launch it** on
  the cluster — which dataset, which run config, which seed, which nodes.

A launch profile *points at* a run config. See the main
[README](../README.md#running-on-solstorm).

---

## Keys the Julia version does not read

Configs inherited from the Python version may still contain
`use_temporary_directory`, `temporary_directory`, `print_in_iamc_format`,
`serialize_instance`, `write_in_lp_format`, `compute_operational_duals`,
`moment_matching` and `n_tree_compare`. Nothing reads them here, so setting one
has no effect. They have been removed from the files in this folder; what each did
in the Python version is recorded in [TODO.md](../TODO.md).
