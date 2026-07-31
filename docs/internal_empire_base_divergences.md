# How InternalEMPIRE diverges from base EMPIRE

## Why this exists

OpenEMPIRE.jl is a port of **base EMPIRE** (`OpenEMPIRE-csv`), extended with the
natural-gas module taken from **InternalEMPIRE**. The gas module itself is verified
identical: its constraint matrix is bit-for-bit the same as the one InternalEMPIRE's
own builder produces (`natural_gas_reference_comparison.md`).

Solution values nevertheless differ by a few percent, and chasing that one symptom at
a time was unproductive — each fix revealed another cause. The reason is structural:
InternalEMPIRE is a *fork* of base EMPIRE carrying its own modifications to the shared
electricity model. Gas quantities are endogenous to that model, so they inherit every
one of its differences no matter how exact the gas module is.

This document enumerates those divergences once, comparing Python against Python so
no port question muddies the picture.

Compared: `OpenEMPIRE-csv/empire/core/empire.py` at `fdc3897` (1,574 lines) against
`InternalEMPIRE/empire.py` at `14675a7` (5,791 lines).

A raw line diff is useless at that size ratio — most of the growth is whole modules
the base lacks (hydrogen, industry, heat, transport, CVaR, natural gas), which are
expected. The comparison instead matches constructs by name and reports only where the
two disagree about something they *share*.

## 1. Parameters the base charges that InternalEMPIRE disabled

All three CCS parameters are live in the base and commented out in the fork:

| Parameter | Base | InternalEMPIRE |
|---|---|---|
| `CCSCostTSFix` | `empire.py:242`, `Param(initialize=1149873.72)` | `empire.py:461`, commented out |
| `CCSCostTSVariable` | `empire.py:243`, `Param(model.Period, default=0.0)` | `empire.py:462`, commented out |
| `CCSRemFrac` | `empire.py:244`, `Param(initialize=0.9)` | `empire.py:463`, commented out |

This is the whole CCS cost block, not just the two terms found earlier. Under an
emission cap, InternalEMPIRE's `prepOperationalCostGen_rule` therefore reduces a CCS
generator's marginal cost to variable O&M alone, and `prepInvCost_rule` adds no CCS
transport-and-storage cost to its investment.

OpenEMPIRE.jl inherits the base behaviour and charges both. That is a deliberate,
documented difference — and arguably the fork is the one with a defect, since the
parameters are still declared and their data still generated (`reader.py:82` writes
`Generator_CCSCostTSVariable.tab`, which nothing reads). **Whether these costs should
apply is a modelling decision for the dataset owner, not a parity question.**

The Julia side can now be aligned either way: `ccs_cost_fixed` reads an optional
`Generator/CCSCostTSFixed.csv` and `CCSCostTSVariable.csv` is already data-driven, so
both can be zeroed per dataset without a code change.

## 2. Base constructs absent from InternalEMPIRE

Nine declarations exist in the base with no counterpart under the same name in the
fork. Some are genuine removals, some may be renames — each needs checking before
being treated as a behavioural difference:

| Name | Kind | Base line |
|---|---|---|
| `nodeEmission` | Var | 767 |
| `node_emission` | Constraint | 772 |
| `transmisionOperational` | Var | 606 |
| `transmisionInvCap` | Param | 571 |
| `sloadMod` | Param | 298 |
| `LeapYearsInvestment` | Param | 214 |
| `OffshoreNode` | Set | 153 |
| `PeriodActive` | Set | 146 |
| `ThermalGenerators` | Set | 164 |

`nodeEmission` / `node_emission` matter most. That pair is the base's ton-scale
emission-cap formulation, which `CLAUDE.md` already flags as intentional and as the
source of Gurobi's "large rhs" warning. InternalEMPIRE does not have it, and its
`emission_cap_rule` is correspondingly only 29.6% similar to the base's — so **the two
implementations impose the emission cap differently**. With `use_emission_cap: True`
that alone can move dispatch, independently of anything gas-related.

`OffshoreNode` and `ThermalGenerators` are supplied to InternalEMPIRE from
`run_EMPIRE_int.py` instead of being declared in the model, so those are plumbing
rather than behaviour.

## 3. Shared rules whose maths differs

**36 of 45 shared functions differ.** Ranked by how much (lower similarity = more
changed):

| Rule | Similarity | Base | Fork |
|---|---:|---:|---:|
| `FlowBalance_rule` | 25.6% | 647 | 2055 |
| `Obj_rule` | 27.7% | 634 | 1947 |
| `emission_cap_rule` | 29.6% | 774 | 2396 |
| `prepSload_rule` | 47.1% | 529 | 1292 |
| `shed_component_rule` | 51.1% | 622 | 1765 |
| `prepOperationalCostGen_rule` | 53.3% | 428 | 1157 |
| `prepInvCost_rule` | 54.8% | 394 | 1080 |
| `operational_cost_rule` | 56.3% | 626 | 1938 |
| `prepGenMaxInstalledCap_rule` | 75.3% | 473 | 1227 |
| `prepGenCapAvail_rule` | 78.3% | 515 | 1275 |

The remaining ~26 sit at 89-99% similarity. Those are dominated by one mechanical
change: InternalEMPIRE threads an extra `gp` (GasScenario) index through every
operational variable, so nearly every rule signature and every variable reference
gains an argument. Pervasive, but not a behavioural difference.

The four at the top are, and they are the ones that make solution-level agreement
unreachable:

- **`FlowBalance_rule`** — the electricity balance itself. The fork adds hydrogen
  production, industry, and transport electricity terms to the nodal balance.
- **`Obj_rule`** and **`operational_cost_rule`** — different cost composition.
- **`emission_cap_rule`** — a different cap formulation, per section 2.
- **`prepSload_rule`** — load preparation subtracts heat and industry electricity
  shares that the base does not model.

## 4. What this means for the port

Whole-model agreement between OpenEMPIRE.jl and InternalEMPIRE is **not attainable**
without first porting InternalEMPIRE's base divergences as well — a different and much
larger task than porting the gas module, and one nobody has asked for. Several of the
divergences are InternalEMPIRE-specific modelling choices that base EMPIRE deliberately
does not make.

So the parity claims should be scoped accordingly:

| Claim | Status |
|---|---|
| Gas constraint matrix identical to InternalEMPIRE's | **verified**, bit-for-bit, 62,446 rows / 171,936 coefficients |
| Gas quantities fixed purely by gas-side data | **verified** exact (`transport_met`, `transport_shed`) |
| Base electricity model matches base EMPIRE | covered separately by `compare_python_julia_outputs.jl` against `OpenEMPIRE-csv` |
| Whole model matches InternalEMPIRE | **not attainable**, and not a goal |

## 5. Reproducing

```bash
python3 scripts/diff_empire_implementations.py       # summary
python3 scripts/diff_empire_implementations.py 6     # plus unified diffs of the top 6
```

The script matches `model.<name> = Param/Var/Set/Constraint/...` declarations and
function bodies by name, normalises away whitespace and comments, and separately scans
for declarations that are live in the base but commented out in the fork — the pattern
that hid the CCS terms.
