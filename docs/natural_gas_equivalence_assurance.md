# Natural-gas equivalence assurance

This note records what has and has not been established for the OpenEMPIRE.jl
natural-gas port. The reference inspected was InternalEMPIRE commit
`14675a780129e11d03b9e9f4a03fb2649c715346`; the Julia evidence implementation
was inspected at `cfc5e65fedfb42d925977e2ed2c1d454825a1b86`.

## Assurance statement

The deterministic gas operations are strongly supported as an equivalent port
of the overlapping InternalEMPIRE formulation:

- the gas conversion, import, finite-reserve, storage, directional-pipeline,
  transport-demand, nodal-balance, pipeline-electricity, and terminal-cost
  equations were checked directly against `InternalEMPIRE/empire.py`;
- a controlled Julia/Pyomo solve compares 26 keyed primal and objective metrics
  at machine precision;
- multi-period and weather-by-gas weighting is checked independently with 292
  coefficient and indexing assertions;
- the complete converted seven-period gas dataset constructs, validates, and
  solves to optimality when the unrelated North Sea conflict is disabled;
- all five real gas generator types are tested in the condition actually found
  in the workbook: an efficiency profile exists but an ordinary generator fuel
  price does not.

This is not a claim that the complete Julia and Python programs build byte-for-
byte identical solver matrices. JuMP and Pyomo use different containers and
index layouts. The gas-specific LP rows, bounds, and module-controlled objective
coefficients have, however, also been compared against two instances constructed
by the actual unmodified `InternalEMPIRE/empire.py`. The comparison pins the
reference commit and records the exact workbook and converted-data hashes.

## Direct source mapping

| Behaviour | InternalEMPIRE | OpenEMPIRE.jl | Result |
|---|---|---|---|
| Gas generator classification | `empire.py:335-341` | gas set construction/readers | Same case-insensitive `gas` name rule |
| Gas-to-power conversion, 13.9 MWh/t | `empire.py:2120-2125` | `src/natural_gas.jl:247-256` | Same equation |
| Terminal hourly capacity | `empire.py:2132-2134` | `src/natural_gas.jl:257-270` | Same equation |
| Domestic/PipelineImport cumulative reserve | `empire.py:2136-2141` | `src/natural_gas.jl:171-221` | Same terminal classification, strategic/season weights and `1e-3` row scaling |
| Seasonal storage initial condition and balance | `empire.py:2143-2148` | `src/natural_gas.jl:273-290` | Same 50% reset and unit-efficiency default |
| Seasonal terminal storage level | `empire.py:2150-2157` | `src/natural_gas.jl:291-302` | Same end-of-each-season reset |
| Storage capacity | `empire.py:2160-2162` | `src/natural_gas.jl:303-311` | Same equation and scaling |
| Directional pipeline capacity | `empire.py:2164-2172` | `src/natural_gas.jl:312-320` | Same without out-of-scope H2 repurposing |
| Gas nodal balance | `empire.py:2175-2194` | `src/natural_gas.jl:336-366` | Same overlapping power, storage, transmission, terminal and transport terms |
| Transport demand conversion | `empire.py:2674-2677` | `src/natural_gas.jl:321-335` | Same annual MWh divided by `8760 * 13.9` |
| Sending-node compressor electricity | `empire.py:2006-2007` and non-heat equivalent | `src/natural_gas.jl:153-169` plus electricity balance | Same coupling |
| Terminal import cost | `empire.py:1774-1776` | `src/natural_gas.jl:370-409` | Same price, season, discount and scenario weighting |
| Gas generator fuel treatment | `empire.py:1157-1171` | `src/utils.jl:167-221` | Ordinary fuel omitted; O&M and applicable carbon terms retained |

## Numerical evidence

### Controlled equation-level comparison

The shared two-node fixture compares terminal imports, pipeline flow, storage,
gas for power, transport service/shedding, electricity generation, the total
objective, and gas objective components:

| Metric | Result |
|---|---:|
| Keyed values | 26 |
| Maximum absolute difference | `4.54747350886e-13` |
| Maximum relative difference | `3.5527136788e-16` |
| Overall | PASS |

### Corrected full-dataset smoke solve

The previous one-period objective was invalid because the five gas generator
types fell through to zero marginal cost. Repeating exactly the prior reduced
20-hour temporal scale after the correction gives:

| Metric | Result |
|---|---:|
| Strategic periods | 1 |
| Operational periods | 20 |
| Variables | 42,798 |
| Structural constraints | 53,363 (96,161 including variable-in-set constraints) |
| Solver | HiGHS 1.15.1 |
| Status | OPTIMAL / FEASIBLE_POINT |
| Objective | `9.523177899833549e11` |
| Build / solve | 26.71 s / 0.54 s |

The earlier `9.479417173693846e11` value must not be used as a baseline.

### Seven-period model

With one weather scenario and the same reduced 20-hour temporal scale:

| Metric | North Sea on | North Sea off |
|---|---:|---:|
| Variables | 299,586 | 299,586 |
| Structural constraints | 373,809 | 371,975 |
| Gurobi status | INFEASIBLE | OPTIMAL / FEASIBLE_POINT |
| Objective | unavailable | `4.753786325741043e18` |
| Build / solve | 30.19 s / 0.08 s | 27.93 s / 2.00 s |

Gurobi's IIS for the infeasible North-Sea-enabled model contains North Sea
investment/transmission constraints and bounds at HelgoländerBucht:
`max_inv_tech`, `max_inst_tech`, `wind_farm_transmission_cap`,
`installed_cap_gen`, and `trans_track_cap`. It contains no natural-gas
constraint or variable. The prior HiGHS `OTHER_ERROR` is therefore superseded:
the reduced configuration has an unrelated North Sea conflict, while the
complete seven-period gas model solves when that conflict is disabled.

The very large optimal objective is dominated by electric load shedding in
this deliberately tiny 20-hour representation. It is build/feasibility
evidence, not a calibrated planning result.

## Intentional and pre-existing differences

1. InternalEMPIRE declares and prices transport natural gas only inside its
   Hydrogen block even though its gas balance always references the transport
   variable. Julia makes gas transport independent of Hydrogen. This is an
   intentional correction, not literal replication.
2. Base OpenEMPIRE.jl adds a CCS transport-and-storage term to CCS generator
   marginal cost. InternalEMPIRE's current `prepOperationalCostGen_rule` does
   not. Consequently `GasCCS` and `GasCCSadv` are not whole-model cost-identical
   even though their natural-gas fuel is handled correctly.
3. Duplicate workbook keys are canonicalized explicitly with audited
   last-source-row-wins behaviour before Julia reads them. Pyomo `DataPortal`
   performs the same overwrite silently.
4. Gas-pipeline repurposing, Hydrogen reforming, Industry gas consumption, Heat,
   and CVaR are outside this port.

## Accepted claim and limit

> The deterministic natural-gas subsystem matches InternalEMPIRE's gas
> formulation for its constraints, bounds, and module-controlled costs.
> Whole-model objectives and dispatch can differ because OpenEMPIRE.jl retains
> base OpenEMPIRE electricity, CCS, emission, and seasonal semantics.

The actual-`empire.py` comparison is structural and objective-coefficient
evidence, not a claim that the surrounding electricity models or their optimal
solutions are identical. InternalEMPIRE must run with Hydrogen enabled because
of a reference-side hidden dependency; the comparator permits only its
explicitly documented `ng_forHydrogen` column in gas-balance rows.
