# Contributing

## Development setup

Clone the repository and instantiate both the package and test environments:

```powershell
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=test -e 'using Pkg; Pkg.instantiate()'
```

Build the documentation locally after adding Documenter to the documentation environment:

```powershell
julia --project=docs docs/make.jl
```

The generated site is written to `docs/build/`.

## Tests

Run the full suite with:

```powershell
julia --project=test test/runtests.jl
```

The tests cover CSV and Excel readers, scenario generation and parity, model constraints, time structures, runners, out-of-sample preparation, full-year aggregation, and solver behavior. Use the smallest relevant test file while iterating, then run the full suite before submitting a change.

## Documentation and comparisons

Document user-facing commands in `README.md` and this site together when behavior changes. Keep Python/Julia comparison claims reproducible and record the configuration, seed, dataset, and solver. `COPULA_COMPARISON.md` and `FILTER_COMPARISON.md` contain existing comparison methodology.

Please keep pull requests focused, preserve input compatibility where possible, and add a regression test for changed model behavior.
