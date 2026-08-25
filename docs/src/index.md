# OpenEMPIRE.jl

OpenEMPIRE.jl is a Julia implementation of EMPIRE, the European Model for Power system Investments with Renewable Energy. It is a multi-horizon stochastic capacity expansion model that co-optimizes generation, storage, transmission, and hourly operation across European nodes.

The Julia implementation uses [JuMP](https://jump.dev/) for optimization, [TimeStruct.jl](https://github.com/sintefore/TimeStruct.jl) for strategic and operational time, and [SparseVariables.jl](https://github.com/sintefore/SparseVariables.jl) for sparse model indices.

!!! note
    This documentation describes the Julia implementation. The [legacy Python/Pyomo documentation](https://openempire.readthedocs.io/en/latest/) remains useful for the shared EMPIRE concepts, but its package API and commands do not apply to Julia.

## Contents

- [Running the model](user-guide.md): installation, solvers, the Julia API, and the command-line runner.
- [Input data](input-data.md): CSV and Excel layouts, configuration, and validation.
- [Scenarios and out-of-sample](scenarios.md): sampling, filters, copulas, scenario trees, and aggregation.
- [Mathematical model](mathematical-model.md): decision variables, constraints, objective, and uncertainty.
- [API reference](api.md): generated documentation for the public data and model functions.
- [Contributing](contributing.md): tests, comparisons, and development workflow.

## Origin and maintainers

EMPIRE originated in research on long-term European power-system planning. The Julia port is maintained by contributors from the Norwegian University of Science and Technology and the wider open-source community.

OpenEMPIRE.jl is free software distributed under the terms of the repository [license](https://github.com/ntnuiotenergy/OpenEMPIRE.jl/blob/main/LICENSE).
