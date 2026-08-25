# API reference

The generated API reference covers the package functions used to load data, construct models, generate scenarios, and prepare out-of-sample experiments.

## Model and data

```@docs
OpenEMPIRE.read_data
OpenEMPIRE.create_timestruct
OpenEMPIRE.generate_scenarios
OpenEMPIRE.create_model
```

## Out-of-sample workflows

```@docs
OpenEMPIRE.generate_oos_scenario_tree
OpenEMPIRE.prepare_oos_experiment
OpenEMPIRE.prepare_oos_execution_queue
```

## Results and utilities

```@docs
OpenEMPIRE.available_datasets
```

The result helpers `write_solution_tables`, `sol_invest_cost`, and
`sol_operational_cost` are available for direct JuMP result work. They are
currently documented in the source and in the [running guide](user-guide.md).

For the complete internal module surface, browse the source under `src/` or use Julia's `names(OpenEMPIRE; all = true)` during development.
