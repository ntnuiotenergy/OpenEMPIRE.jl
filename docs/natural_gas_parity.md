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
| Maximum absolute difference | `4.54747350886e-13` |
| Maximum relative difference | `3.5527136788e-16` |
| Tolerance | `atol=1e-8`, `rtol=1e-9` |
| Overall | PASS |

Re-measured after reserve and storage rows were scaled by `NATURAL_GAS_ROW_SCALE`
to match InternalEMPIRE's `/1e3` conditioning. The absolute figure moved from
`8.881784197e-16` because the scaled rows change LP numerics slightly; the
relative figure stays at machine precision.

The fixture also confirms the intended compressor recursion: sending natural
gas through the pipeline consumes electricity at the sending node, and the gas
generator producing that electricity consumes a small additional amount of
gas.

This controlled comparison documents equation-level parity. It does not claim
that unrelated InternalEMPIRE modules are active. Natural-gas transport is
deliberately independent of Hydrogen in Julia, and duplicate workbook rows are
explicitly canonicalized before Julia reads them, as documented in
`natural_gas_terminal_cost_duplicates.md`.

## What this fixture cannot show

Two limits are worth stating plainly.

The fixture has one strategic period, one representative period and one
operational scenario, so it cannot exercise strategic duration, season
multiplicity, scenario probability, storage resets across seasons, or the
gas-price axis. Those are covered separately by
`test_natural_gas_multi_period_scenario_weighting`, which builds a
2-period x 2-season x 2-weather x 3-gas model and checks reserve row counts,
reserve coefficients, storage-reset counts, per-period objective coefficients
against the correct gas scenario, and uniform `1/(W*G)` probabilities against
hand-computed values.

`natural_gas_parity_python.py` is an independent hand-written restatement of the
intended equations, not `InternalEMPIRE/empire.py`. It establishes that the Julia
formulation agrees with a second expression of the same equations; it does not
establish agreement with the reference implementation's own code, and a shared
misreading of InternalEMPIRE would pass both.

**That gap has since been closed** by a direct comparison against `empire.py` itself:
all 62,446 natural-gas rows and 171,936 coefficients on a 52-node instance agree
bit-for-bit with the reference's own LP. That comparison requires the private
InternalEMPIRE checkout, so its tooling and evidence live outside this repository.
This fixture remains useful as a fast, hand-inspectable regression check.

The Julia side is not a reimplementation: `natural_gas_parity_julia.jl` calls the
real `create_variables`, `create_constraints`, `create_objective` and
`objective_component_values`. It does, however, inject `genMargCost` directly and
so does not exercise `preprocess_operational_cost`; gas marginal cost is covered
by `test_gas_marginal_cost_without_a_fuel_price` and
`test_full_model_int_gas_generators_are_priced` instead.

