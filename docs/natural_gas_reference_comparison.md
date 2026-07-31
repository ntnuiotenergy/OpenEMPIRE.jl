# Comparison against InternalEMPIRE's own model builder

`natural_gas_parity.md` documents equation-level agreement between OpenEMPIRE.jl and
an independently hand-written Pyomo restatement of the intended equations. That is
strong evidence about the formulation, but it cannot rule out a shared misreading of
the reference: the same author wrote the Julia model and the Pyomo restatement.

This document covers the stronger comparison — driving `InternalEMPIRE/empire.py`
itself, at commit `14675a7`, and comparing its natural-gas rows against the Julia
model's.

## The reference cannot run without Hydrogen

Before any comparison could be set up, one property of `empire.py` had to be
established, because it determines whether the reference can be run in a
gas-only configuration at all.

It cannot. All six transport-demand variables are declared inside the
`if hydrogen is True:` block:

- `empire.py:1731-1736` — `transport_electricityDemandMet` / `Shed`,
  `transport_hydrogenDemandMet` / `Shed`, `transport_naturalGasDemandMet` / `Shed`.

All three constraints that reference them are declared at function level, with no
hydrogen guard:

- `empire.py:2664-2667` — `meet_transport_elec_demand`
- `empire.py:2669-2672` — `empire.py:meet_transport_hydrogen_demand`
- `empire.py:2674-2677` — `meet_transport_naturalGas_demand`

So `run_empire(..., hydrogen=False)` raises `AttributeError` on the *electricity*
transport constraint, before natural gas is reached. `run_EMPIRE_int.py:55` hardcodes
`hydrogen = True`, which is why this has never surfaced in normal use.

The natural-gas balance has the same shape of coupling on its own:
`empire.py:2191-2192` subtracts `transport_naturalGasDemandMet` under only
`if n in model.OnshoreNode`, while the variable exists only under Hydrogen. The
matching shed cost at `empire.py:1871-1874` is also Hydrogen-gated and enters the
objective at `empire.py:1932` fused with two H2-only cost terms.

This is the "hidden Hydrogen dependency" referred to in
`natural_gas_equivalence_assurance.md`, now pinned to exact lines and found to be
broader than natural gas alone.

## Why the reference is neither patched nor neutralised

Making `hydrogen=False` work would mean hoisting six variable declarations and
splitting the fused objective term at `empire.py:1932`. That is real surgery on the
reference, and every line of it would be something a reviewer has to take on trust —
the patched reference could no longer be described as the reference.

A first attempt instead neutralised the two Hydrogen couplings through the tab data.
That was dropped, for two reasons discovered while trying it:

- Zeroing `Transport_NaturalGasDemand.tab` does **not** remove
  `transport_naturalGasDemandMet` from the gas balance row. Pyomo builds the term at
  `empire.py:2192` whatever the parameter value, so the column is still in the
  matrix with coefficient `-1`. Neutralising the data would have hidden the column
  from a solution comparison while leaving it in the matrix — the worst of both.
- Emptying `Hydrogen_ReformerLocations.tab` is not loadable at all: Pyomo's set
  reader raises `TypeError` on a header-only file (`dataportal/plugins/text.py:57`).

So the reference runs **completely unmodified, with unmodified data**, in its real
`hydrogen=True` configuration. The Hydrogen-side columns that appear in gas rows are
then *enumerated and justified* rather than suppressed:

| Extra column in reference gas rows | Origin | Why Julia has no counterpart |
|---|---|---|
| `ng_forHydrogen[n,p,h,i,w,gp]` | `empire.py:2179-2180` | Hydrogen reforming is outside the port's scope |

That is the *only* expected extra column. `transport_naturalGasDemandMet` is **not**
one: the port implements it as `transportNaturalGasDemandMet` (`natural_gas.jl:121-129`),
so it is compared rather than excused. The comparison asserts `ng_forHydrogen` is the
only unmatched column; any second one is a finding. This is the same discipline the
repository applies elsewhere: document the difference, do not mask it.

`industry=False` and `HEATMODULE=False` are ordinary run flags, not modifications,
and match the port's current scope.

## Instance

The comparison instance is `full_model_int` itself — full 52-node network, real gas
terminals, reserves, pipelines and storage — reduced **only in time**:

| Dimension | Production | Comparison |
|---|---:|---:|
| Strategic periods | 7 | 2 |
| Regular seasons | 4 × 168 h | 1 × 24 h |
| Peak seasons | 2 × 24 h | 1 × 24 h |
| Weather scenarios | 5 | 1 |
| Gas scenarios | 1 | 1 |

Time-only reduction keeps every gas parameter and every set membership exactly as
production uses them, so no tab-file surgery on the network is required and no
inconsistency between subsets can be introduced. Two strategic periods retain
discounting and `LeapYearsInvestment` scaling; one regular plus one peak season
retains `seasScale` heterogeneity, which is the factor most likely to be got wrong.

## What is compared, and what that does and does not cover

The reference is run with `WRITE_LP=True`, which writes an LP with
`symbolic_solver_labels=True` at `empire.py:3058-3064` — full variable and
constraint names. The Julia model writes its own LP. The comparison is then
**matrix-level on the natural-gas rows**: constraint-by-constraint, coefficient by
coefficient, on canonicalised keys, after mapping Pyomo names to JuMP names.

Matrix comparison is the right target for the question "does it build identically",
and it has one important property here: the natural-gas reserve, storage, balance,
terminal-capacity and pipeline rows are **structural**. Their coefficients do not
depend on weather scenario data. So the reduction to one weather scenario, and any
difference in generated scenario tables between the two sides, cannot affect the
gas rows being compared.

That property does *not* extend to solution values. Electricity load enters the
power balance, gas-fired dispatch responds to it, and `ng_forPower` therefore
depends on scenario data. A solution-level comparison would additionally require
feeding byte-identical scenario tables to both sides. Solution comparison is
therefore secondary here, and any claim from it is scoped accordingly.

## Checks

Independent of the coefficient comparison, the run must satisfy:

1. `ReformerLocations` is empty in the built instance.
2. Every `transport_naturalGasDemandMet` value is exactly zero.
3. No `ng_forHydrogen` variable appears in any gas balance row.
4. Gas row and gas variable counts agree between the two models.

Items 1-3 verify the neutralisation actually held. If any fails, the comparison is
void regardless of how well the coefficients match.

## Reference-side result, 2026-07-30

The reference ran end to end on the reduced instance with **no modification to
`empire.py`, `reader.py`, `scenario_random.py` or any tab file**:

| | |
|---|---|
| Reference commit | `14675a7` |
| Tab generation | `reader.generate_tab_files`, `periods=2`, `hydrogen=True`, `industry=False`, `HEATMODULE=False` |
| Scenario generation | `generate_random_scenario`, `fix_sample=False` |
| Termination | optimal |
| Objective | `1.95297314e+12` |
| LP written | `LP_gasparity.lp`, 205 MB, `symbolic_solver_labels=True` |

Its natural-gas row inventory, extracted and counted independently, decomposes
exactly as the sets predict — 37 gas nodes, 44 (node, terminal) pairs, 94 directional
links, 148 (node, gas generator) pairs, 35 onshore nodes, 72 hours, 3 seasons,
2 periods:

| Reference family | Rows | Decomposition |
|---|---:|---|
| `naturalGas_for_power` | 21,312 | 148 × 72 × 2 |
| `naturalGas_for_hydrogen` | 15,120 | out of port scope |
| `naturalGas_pipeline_capacity` | 13,536 | 94 × 72 × 2 |
| `naturalGas_terminal_capacity` | 6,336 | 44 × 72 × 2 |
| `naturalGas_storage_maxCapacity` | 5,328 | 37 × 72 × 2 |
| `naturalGas_storage_balance` | 5,328 | 37 × 72 × 2 |
| `naturalGas_flow_balance` | 5,328 | 37 × 72 × 2 |
| `meet_transport_naturalGas_demand` | 5,040 | 35 × 72 × 2 |
| `naturalGas_net_zero_seasonal_storage` | 222 | 37 × 3 × 2 |
| `naturalGas_max_reserves` | 16 | one row per reserve node, **not** per period |

Two facts worth recording independently of the coefficient comparison:

- The 16 reserve rows confirm the reference accumulates terminal imports across all
  strategic periods into a single row per node. That is what the Julia
  implementation does, and it is the property the `NATURAL_GAS_ROW_SCALE`
  conditioning applies to.
- The reference's own scenario generator hardcodes two peak blocks
  (`scenario_random.py:160-172`), so the reference cannot be run with a single peak
  season at all. Any reduced instance must use `NoOfPeakSeason = 2`.

## Structural comparison, 2026-07-30

The Julia model builds on the matching instance
(`config/gas_reference_comparison.yaml`, `scripts/write_gas_reference_lp.jl`):
295,260 variables, 375,224 constraints, 144 operational periods — the same
72 hours x 2 strategic periods the reference uses.

Gas row counts per family, both sides counted from their own LP:

| Family (Julia name) | Julia | Reference | |
|---|---:|---:|---|
| `natural_gas_flow_balance` | 5,328 | 5,328 | match |
| `natural_gas_storage_balance` | 5,328 | 5,328 | match |
| `natural_gas_storage_max_capacity` | 5,328 | 5,328 | match |
| `natural_gas_storage_cyclic` | 222 | 222 | match |
| `natural_gas_terminal_capacity_limit` | 6,336 | 6,336 | match |
| `natural_gas_pipeline_capacity_limit` | 13,536 | 13,536 | match |
| `natural_gas_for_power` | 21,312 | 21,312 | match |
| `meet_transport_natural_gas_demand` | 5,040 | 5,040 | match |
| `natural_gas_max_reserves` | **0** | **16** | **OPEN FINDING** |

Eight of nine families agree exactly, on a 52-node instance with the real gas
network. That is meaningful structural agreement: the same number of rows over the
same index sets, produced by two independent builders.

### Resolved: the reserve rows were anonymous, not missing

An earlier pass reported no reserve rows in the Julia LP. That was a defect in the
*detection*, not the model. The constraints were built with a bare
`@constraint(emp, total_import <= ...)` and registered only in
`emp[:natural_gas_max_reserves]`, so JuMP wrote them without a name and a name-based
search could not see them. The dataset was fine and `is_finite_reserve_terminal` was
fine.

They now carry an explicit `base_name`, which also makes them identifiable in Gurobi
IIS output. The dataset has exactly 16 (node, finite-terminal) pairs, matching the
reference's 16 rows, and `empire.py:2136-2141` indexes the same way.

## Coefficient comparison, 2026-07-30

Run after the RussianGas terminal-cost repair, so both sides read identical input
(see `natural_gas_terminal_cost_duplicates.md`). The reference solves to
**1.80734672e+12**; before the data repair the same instance gave 1.95297314e+12.

`scripts/compare_gas_matrix.py` reduces both LPs to a shared canonical form and
compares numbers, never text. Three encoding differences are reconciled explicitly:

- **Index encoding.** Pyomo writes `(Austria_1_1_scenario1_1)` - node, hour, period,
  weather scenario, gas scenario. JuMP writes `Austria,sp1_rp1_t1`. With one 24 h
  regular season and two 24 h peak seasons, hours 1-24 map to `rp1`, 25-48 to `rp2`,
  49-72 to `rp3`, and Period `i` to `sp{i}`. Index tuples are split from the right by
  a known token count, never on `_`, because several entity names contain one.
- **Name escaping.** Pyomo escapes characters illegal in LP names, so `GreatBrit.`
  becomes `_GreatBrit__`. Both sides are reduced to alphanumerics.
- **Row keying.** `meet_transport_naturalGas_demand` puts the hour *last* in its index
  tuple, unlike every other family. `storage_balance` is indexed by `withprev` in
  Julia, so its label carries a `(previous, current)` pair, and the current period is
  the one matching Pyomo's hour. `max_reserves` carries trailing scenario indices in
  its `base_name` that are not part of the Pyomo row key.

| Family | Reference rows | Julia rows | Matched | Coefficients | Differences |
|---|---:|---:|---:|---:|---:|
| `flow_balance` | 5,328 | 5,328 | 5,328 | 70,416 | 0 |
| `for_power` | 21,312 | 21,312 | 21,312 | 42,624 | 0 |
| `storage_balance` | 5,328 | 5,328 | 5,328 | 21,090 | 0 |
| `pipeline_capacity` | 13,536 | 13,536 | 13,536 | 13,536 | 0 |
| `transport_demand` | 5,040 | 5,040 | 5,040 | 10,080 | 0 |
| `terminal_capacity` | 6,336 | 6,336 | 6,336 | 6,336 | 0 |
| `storage_max_capacity` | 5,328 | 5,328 | 5,328 | 5,328 | 0 |
| `max_reserves` | 16 | 16 | 16 | 2,304 | 0 |
| `storage_cyclic` | 222 | 222 | 222 | 222 | 0 |
| **Total** | **62,446** | **62,446** | **62,446** | **171,936** | **0** |

Every row key matches on both sides - no row exists in one model and not the other.
All 171,936 coefficients and every right-hand side agree, and the maximum relative
difference is `0.00e+00`: bit-identical, not merely within tolerance.

### Validated against a negative control

A comparator that silently parses nothing also reports "identical". Two known errors
were injected into the Julia LP - one coefficient changed by `1e-5` relative, one RHS
by `1e-6` relative - and both were detected and localised to the exact row and column:

```
storage_max_capacity  Austria sp1_rp1_t1  storage_level: python=0.001 julia=0.00100001
terminal_capacity     NO2DomesticProduction sp1_rp1_t1  RHS: python=3354.888981940906 julia=3354.892337
```

## Status

**Complete for the deterministic natural-gas formulation.** The Julia model's gas
constraint matrix is identical to the one InternalEMPIRE's own builder produces, on a
52-node instance with the real gas network, verified coefficient by coefficient
against `empire.py` at commit `14675a7` running unmodified.

This retires the limitation stated in `natural_gas_parity.md`: the earlier evidence
compared Julia against a hand-written restatement of the equations, which a shared
misreading would have passed. This compares against the reference implementation
itself.

What it does **not** cover, unchanged from `natural_gas_equivalence_assurance.md`:

- One weather scenario and one gas scenario. Coefficients in these families are
  structural and do not depend on scenario draws, but the weather x gas product is
  exercised only by `test_natural_gas_multi_period_scenario_weighting`, not here.
- `ng_forHydrogen` columns in the reference's gas balance are skipped by agreement,
  since hydrogen reforming is outside the port's scope.
- The objective function and the electricity-side model are not compared here, only
  the natural-gas rows. `GasCCS`/`GasCCSadv` marginal costs still differ by base
  OpenEMPIRE.jl's CCS transport-and-storage term.
- Solution values are not compared; that would additionally require identical
  scenario tables on both sides.

### Reproducing

```bash
# reference side (writes LP_gasparity.lp)
conda run -n empire_env python scripts/gas_reference_build.py
# julia side
julia --project=. scripts/write_gas_reference_lp.jl /tmp/julia.lp
# compare
python3 scripts/compare_gas_matrix.py LP_gasparity.lp /tmp/julia.lp
```


## Solution-level comparison: attempted, blocked (2026-07-31)

The matrix comparison above shows the two models *are* the same. The natural follow-up
is to show the numbers coming out of them agree. That is **not** delivered, and the
blocker is worth recording precisely because it is not in the gas module.

### Setup that does work

`scripts/gas_reference_build.py` (env `GASPARITY_NEUTRALISE_H2=1`) makes the two
out-of-scope consumers inert through data, leaving `empire.py` unmodified:

| Lever | Why |
|---|---|
| reformer capital cost -> `1e12` | steam reforming physically consumes gas (`empire.py:2179-2180`); with no capacity built, `hydrogenProducedReformer <= ReformerTotalCap` (`empire.py:2511`) forces the draw to zero |
| transport H2 demand -> 0 | keeps electrolysers idle so the electricity side is comparable |
| transport electricity demand -> 0 | the port has `transportNaturalGasDemandMet` but no electricity counterpart; left active it is extra load pulling extra gas-fired generation |

`scripts/write_gas_reference_lp.jl` takes `GASPARITY_ZERO_CCS=1` to zero
`CCSCostTSVariable`, which the reference declares but leaves commented out
(`empire.py:462`, `empire.py:748`), and `GASPARITY_SAMPLING_KEY` to adopt the
reference's own weather draw.

Both models solve to optimality, and the hydrogen neutralisation verifiably holds:
`ng_forHydrogen` is **0.0 across all 15,120 variables**, asserted in the solved model.

### The blocker: the two sides cannot be made to draw the same weather

`compare_gas_solution.py` refuses to report quantities unless the electricity balance
RHS -- the hourly load, straight from the scenario draw -- matches on both sides.
Feeding Julia the reference's own `sampling_key.csv` does **not** achieve that:

```
sp1 rp1:  1248 keys,   840 mismatched      <- all 35 onshore nodes
sp1 rp2:  1248 keys,   839 mismatched
sp1 rp3:  1248 keys,   840 mismatched
sp2 rp1:  1248 keys,     0 mismatched      <- strategic period 2 is exact
sp2 rp2:  1248 keys,     0 mismatched
sp2 rp3:  1248 keys,     0 mismatched
```

Strategic period 2 reproduces **exactly**; strategic period 1 does not, in every
season. Julia's period-1 load is not a rescaling of Python's period 1 or period 2
either (ratio spread 0.43-1.58), so it is sampling different hours, not applying
different scaling. The key is demonstrably read and validated -- an invalid probe key
raised `Invalid sample window for winter 2011` from `scenario.jl:262` -- so it is not
being ignored.

One earlier run with a different key (period-1 winter `2016/7`) did match on all 7,488
keys. So the divergence is key-dependent, which points at window construction in
`_sample_regular_indices` / `generate_scenario_csv!` rather than at the key being
dropped outright.

### Root cause found and fixed: the season -> month mapping was wrong

`_season_months` in `scenario.jl` did not match `season_month` in
`scenario_random.py:23-31`. Every season was offset by one month:

| Season | Reference | Port (before) |
|---|---|---|
| winter | 1, 2, **12** | 1, 2, **3** |
| spring | **3**, 4, 5 | 4, 5, **6** |
| summer | **6**, 7, 8 | 7, 8, **9** |
| fall | **9**, 10, 11 | 10, 11, **12** |

Both implementations preserve chronological order when filtering, so a winter pool of
(1, 2, 12) and one of (1, 2, 3) are **identical for their first 1,416 rows** -- January
plus February -- and diverge only beyond that. A fixed-sample key with a small sample
hour therefore reproduced the reference exactly, while a large one silently sampled
March where the reference sampled December. That is precisely the observed pattern:
period 2 (hour 127) matched, period 1 (hour 2124) did not.

This affected **all** scenario generation, random as well as fixed-sample, for every
dataset -- not just the gas comparison.

Fixed in `scenario.jl`, with two regression tests in `test_scenario_csv.jl`:
`test_season_months_match_python` pins the mapping against the reference values and
checks every month belongs to exactly one season, and
`test_december_is_sampled_into_winter` exercises `_season_indices` on a December
fixture. The pre-existing `test_python_fixed_sample_scenario_parity` could not catch
this: its fixture only emits months 1, 4, 7 and 10, each of which falls in the same
season under both the correct and the incorrect mapping.

After the fix the electricity load matches **exactly** -- `max abs diff 0.0000e+00`
across all 7,488 shared keys, against 2.98e+04 before.

## Solution comparison: current state

With scenarios matched and hydrogen inert (`ng_forHydrogen` = 0 across all 15,120
variables):

| Quantity | Reference | Julia | Relative |
|---|---:|---:|---:|
| `transport_met` | 2,449,068.5612 | 2,449,068.5612 | **exact** |
| `transport_shed` | 17,252.0382 | 17,252.0382 | **exact** |
| `storage_level` | 5,750,343,200.94 | 5,749,934,669.60 | 0.007% |
| `terminal_import` | 3,652,526.13 | 3,597,749.89 | 1.5% |
| `storage_charge` | 941,130.90 | 921,477.01 | 2.1% |
| `for_power` | 1,203,457.57 | 1,148,681.33 | 4.6% |
| `transmission` | 3,707,812.51 | 3,502,302.96 | 5.5% |

The two quantities determined purely by gas-side data agree to the last digit. The
rest, which are coupled to electricity dispatch and investment, differ by a few
percent.

### Why, and what remains

The models still differ in scope on the *investment* side. InternalEMPIRE has **both**
CCS cost terms commented out -- `CCSCostTSFix` at `empire.py:461` and
`CCSCostTSVariable` at `empire.py:462` -- while OpenEMPIRE.jl applies both: the
variable term at `utils.jl:200-202` and an investment term at `utils.jl:63-64` using
the same hardcoded `1149873.72`. The comparison neutralises only the variable term
(`GASPARITY_ZERO_CCS=1`), so Julia still charges a CCS *investment* cost the reference
does not. That changes CCS capacity, hence dispatch, hence gas draw, and it is the
leading explanation for both the residual few-percent spread and the objective gap
(1.68e12 vs 2.01e12).

`ccs_cost_fix` was therefore made data-driven (clearing the standing
`# TODO: avoid hardcoding of ccs data`), defaulting to the same `1149873.72` so
existing behaviour is unchanged, and `GASPARITY_ZERO_CCS=1` now zeroes **both** terms.

Zeroing both moved the numbers materially -- `for_power` flipped from 4.6% below the
reference to 5.6% above -- but did **not** make them exact:

| Quantity | Reference | Julia | Delta |
|---|---:|---:|---:|
| `transport_met` / `transport_shed` | - | - | **exact** |
| `terminal_import` | 3,268,872.55 | 3,315,122.95 | +1.4% |
| `storage_charge` | 835,894.69 | 859,031.42 | +2.8% |
| `for_power` | 819,803.99 | 866,054.39 | +5.6% |
| `transmission` | 3,416,448.97 | 3,165,643.05 | -7.3% |

So CCS was a real contributor, not the only one. The CO2 cap is identical for both
periods, so that is not it either.

### Why exact solution identity is not the right target

OpenEMPIRE.jl is a port of **OpenEMPIRE-csv** (base EMPIRE), extended with the gas
module taken from InternalEMPIRE. InternalEMPIRE is itself a *fork* of base EMPIRE
carrying its own modifications -- the two commented-out CCS cost terms are a proven
instance, found only because this comparison went looking.

Whole-model identity between OpenEMPIRE.jl and InternalEMPIRE therefore cannot be
reached without first enumerating and matching every way InternalEMPIRE's base
diverges from base EMPIRE. That is a different project, and it is not what this port
set out to do. Gas quantities are endogenous to that surrounding electricity and
investment model, so they inherit its differences no matter how exact the gas module
itself is.

The defensible claim remains the matrix one: the natural-gas constraint matrix is
bit-identical to the one InternalEMPIRE's own builder produces. Alongside it,
`transport_met` and `transport_shed` -- the only gas quantities fixed purely by
gas-side data rather than by dispatch -- agree to the last digit.

If whole-model agreement is wanted later, the productive next step is a systematic
diff of `InternalEMPIRE/empire.py` against `OpenEMPIRE-csv/empire/core/empire.py`.
That is Python against Python, so no port question muddies it, and it would enumerate
the fork's divergences once instead of rediscovering them one at a time through
solution mismatches.

An attempt to validate the season fix end-to-end with a forced key (winter hour 2124,
past the shared prefix) is blocked separately: the reference's `fix_sample=True` path
fails on this reduced time structure with
`KeyError: Index '('Belgium', 'Windoffshore', 1, 'scenario1', 1)' is not valid for
indexed component 'genCapAvailStochRaw'`. The fix is validated at unit level instead.
