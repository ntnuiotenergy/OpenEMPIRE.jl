# Input data

## Dataset layout

The model accepts the CSV layout used by the Python version and the older Excel layout.

A CSV dataset contains component directories such as:

```text
<dataset>/
  General/
  Generator/
  Node/
  ScenarioData/
  Sets/
  Storage/
  Transmission/
```

The repository includes `data/test`, `data/europe_v50`, `data/europe_v51`, and `data/full_model_int`. Excel sample data is kept under `data/test_excel`.

## Reading data

```julia
using OpenEMPIRE

sets, params = OpenEMPIRE.read_data("data/test"; format = :csv)
sets_xlsx, params_xlsx = OpenEMPIRE.read_data(
    "data/test_excel";
    format = :xlsx,
)
```

With `format = :auto`, the reader detects a CSV dataset from its component directories or an Excel dataset from `Sets.xlsx`. The returned `sets` and `params` objects are used by `create_model` and can also be inspected independently.

## Configuration

A run configuration is a YAML file. Important fields include:

```yaml
forecast_horizon_year: 2030
number_of_scenarios: 3
length_of_regular_season: 24
discount_rate: 0.05
wacc: 0.05
use_scenario_generation: true
use_fixed_sample: false
use_emission_cap: true
offshore_transmission_cap: true
```

The model uses five-year investment periods by default, starting in 2020.
Scenario controls include `use_scenario_generation`, `use_fixed_sample`,
`filter_make`, `filter_use`, `copula_clusters_make`, and
`copula_clusters_use`. When several sampling modes are enabled, fixed sampling
takes precedence over filters, and filters take precedence over copula
clusters.

The optional modules are switched on with `natural_gas`, `hydrogen` and
`industry`, all `false` by default. Hydrogen and industry both require natural
gas and a single gas scenario (`number_of_gas_scenarios: 1`).

The obsolete `north_sea` setting is ignored with a warning. Use
`offshore_transmission_cap` to control the offshore wind-farm transmission
constraint.

Every configuration in `config/` lists every option, in the same order and
sections. Options a run does not need are written at their default. The
exceptions are the Gurobi `solver_*` keys, where an empty value keeps the Gurobi
default, and the opt-in `internalempire_*` compatibility keys, which are
commented out unless a parity run needs them. Make a new configuration by
copying the closest file and changing values. The full key reference, with
defaults, is in
[config/README.md](https://github.com/ntnuiotenergy/OpenEMPIRE.jl/blob/main/config/README.md).
Keep the dataset path and configuration consistent when comparing runs.

## Scenario input files

Raw time-dependent inputs live under `ScenarioData/`. Scenario generation derives the files consumed by the model:

- `sloadRaw.csv`
- `maxRegHydroGenRaw.csv`
- `genCapAvailStochRaw.csv`

A fixed run also uses `sampling_key.csv`. Additional generated filter and copula-cluster files are documented in [Scenarios and out-of-sample](scenarios.md).

## Validation

The model validates set relationships and parameter data before creating
constraints. `Sets/OffshoreWindFarmNode.csv` and
`Sets/OffshoreEnergyHub.csv` are disjoint. Every offshore wind farm must have
at least one generator. Older datasets may provide `Sets/OffshoreNode.csv`,
which is accepted as the wind-farm set with a deprecation warning.

The offshore transmission cap is enabled by default and can be disabled with
`offshore_transmission_cap: false`. It limits transmission adjacent to a wind
farm by the installed generation at that endpoint. Energy hubs are read and
validated, but their converter-capacity formulation is not implemented yet.
