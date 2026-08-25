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

A run configuration is a YAML file. Important fields include the forecast horizon, investment-period length, regular-season and peak-hour lengths, number of scenarios, WACC, discount rate, and solver settings. Scenario controls include `use_scenario_generation`, `use_fixed_sample`, `filter_make`, `filter_use`, `copula_clusters_make`, and `copula_clusters_use`.

The example configurations in `config/` are the best reference for complete files. Keep the dataset path and configuration consistent when comparing runs.

## Scenario input files

Raw time-dependent inputs live under `ScenarioData/`. Scenario generation derives the files consumed by the model:

- `sloadRaw.csv`
- `maxRegHydroGenRaw.csv`
- `genCapAvailStochRaw.csv`

A fixed run also uses `sampling_key.csv`. Additional generated filter and copula-cluster files are documented in [Scenarios and out-of-sample](scenarios.md).

## Validation

The model validates set relationships and parameter data before creating constraints. In particular, offshore wind-farm nodes and offshore energy hubs are distinct sets, and each offshore wind farm must have at least one generator. The offshore transmission cap is enabled by default and can be disabled with `offshore_transmission_cap: false`.
