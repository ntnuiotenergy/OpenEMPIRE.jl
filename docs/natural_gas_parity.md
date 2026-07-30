# Natural-gas Julia/Pyomo parity

The controlled fixture in `test/data/natural_gas_parity/` is intentionally
small enough to inspect by hand. It has two gas nodes, one directional
pipeline, one domestic terminal, one gas generator at each node, two hours,
gas storage at the receiving node, pipeline electricity consumption, and
natural-gas transport demand.

Both implementations read the same `parameters.csv` and `hours.csv`:

- `scripts/natural_gas_parity_julia.jl` builds and solves the actual
  OpenEMPIRE.jl natural-gas model;
- `scripts/natural_gas_parity_python.py` independently expresses the same
  equations in Pyomo;
- `scripts/compare_natural_gas_parity.py` compares keyed outputs.

Run the comparison from the repository root:

```bash
output_dir="$(mktemp -d /tmp/openempire-gas-parity.XXXXXX)"

julia --project=. scripts/natural_gas_parity_julia.jl \
  test/data/natural_gas_parity \
  "$output_dir/julia.csv"

conda run -n empire_env python scripts/natural_gas_parity_python.py \
  test/data/natural_gas_parity \
  "$output_dir/python.csv"

python3 scripts/compare_natural_gas_parity.py \
  "$output_dir/julia.csv" \
  "$output_dir/python.csv"
```

The output directory contains the separate Julia and Python tables so values
can also be compared manually. The comparator checks terminal imports,
pipeline flow, storage level/charge/discharge, gas-for-power, transport demand
and shedding, electricity generation, the total objective, and each gas-related
objective component.

## Recorded result

The 2026-07-30 comparison used HiGHS in Julia and Pyomo's `appsi_highs`
interface:

| Check | Result |
|---|---:|
| Keyed metrics compared | 26 |
| Maximum absolute difference | `8.881784197e-16` |
| Maximum relative difference | `1.7763568394e-16` |
| Tolerance | `atol=1e-8`, `rtol=1e-9` |
| Overall | PASS |

The fixture also confirms the intended compressor recursion: sending natural
gas through the pipeline consumes electricity at the sending node, and the gas
generator producing that electricity consumes a small additional amount of
gas.

This controlled comparison documents equation-level parity. It does not claim
that unrelated InternalEMPIRE modules are active. Natural-gas transport is
deliberately independent of Hydrogen in Julia, and duplicate workbook rows are
explicitly canonicalized before Julia reads them, as documented in
`natural_gas_terminal_cost_duplicates.md`.

## Performance diagnostics

`BenchmarkTools` is kept out of the runtime dependency set. Run the
representative benchmarks in a temporary Julia environment:

```bash
julia --project=. -e '
    using Pkg
    Pkg.activate(; temp=true)
    Pkg.develop(path=pwd())
    Pkg.add(["BenchmarkTools", "CSV", "HiGHS", "JuMP", "TimeStruct"])
    include("scripts/benchmark_natural_gas.jl")
'
```

The script measures full-dataset gas parsing, weather × gas period mapping, the
scalar combined-scenario helper, and a controlled construction/solve/result
writing cycle. It uses `BenchmarkTools.@btime`, excludes first-run compilation,
and reports allocations.

Recorded on 2026-07-30:

| Operation | Minimum time | Allocations |
|---|---:|---:|
| Full-dataset gas parameter parsing | `1.066 ms` | 17,350 / 1.23 MiB |
| Period context for 19,440 operational periods | `974.292 μs` | 36 / 8.09 MiB |
| Weather × gas combined-scenario count | `166.227 ns` | 0 / 0 bytes |
| Controlled construct + solve + result write | `3.876 ms` | 18,040 / 4.96 MiB |

An initial implementation built three separate dictionaries for strategic,
weather, and gas indices. Consolidating them into one concrete named-tuple
dictionary reduced the representative period-map measurement from `2.342 ms`
and 20.28 MiB to `974.292 μs` and 8.09 MiB. `@code_warntype` infers concrete
return types for this map, the complete gas parameter reader, and combined
scenario counting.
