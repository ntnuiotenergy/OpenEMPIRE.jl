# Natural Gas Implementation Status

Last updated: 2026-08-02 Europe/Oslo

## Objective

Implement OOS handoff item 3: a gated InternalEMPIRE-compatible natural-gas
module, a self-contained `full_model_int` CSV dataset, stochastic gas-price
scenarios, results, OOS/full-year aggregation, parity evidence, and tests.

This file is a live handoff. Update it after every meaningful implementation or
verification milestone.

## Safety and branch state

- Clean evidence worktree:
  `/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl-natural-gas-workbench`
- Evidence branch: `torgrim/natural-gas-workbench`
- Created from: `torgrim/oos-workbench-continuation` at `a6ec6c8`
- Latest verified remote main: `87def4c` (PR #17)
- PRs #18–#29 remain open/draft and stacked as of 2026-07-30.
- SSH fetch failed because the signing agent was unavailable. HTTPS fetch works.
- No natural-gas PR should be opened from this evidence branch. Transplant
  bounded commits to fresh main-based branches after prerequisites merge.
- Bounded evidence commits created:
  - `c6ac80e` — reproducible full-model CSV dataset, converter, audits, config;
  - `64cbad6` — typed loading, scenario axes, gas equations, and objective;
  - `743957b` — results, OOS/full-year integration, parity, and tests;
  - `79b87c7` — standalone converted-dataset validation;
  - `56103df` — reserve completeness and expanded acceptance coverage.
- Clean main-based dataset worktree:
  `/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE.jl-full-model-int-dataset-pr`
- Dataset branch `torgrim/full-model-int-dataset` has been pushed.
- PR #30 is open, non-draft, mergeable, and clean against `main`:
  <https://github.com/ntnuiotenergy/OpenEMPIRE.jl/pull/30>
- PR #30 contains no natural-gas model, OOS, north-sea, copula, or unrelated
  module implementation.
- Dirty checkouts that must remain untouched:
  - `OpenEMPIRE.jl` (`torgrim/north-sea`)
  - `OpenEMPIRE.jl-workbench` (`torgrim/workbench`)
  - `InternalEMPIRE`

## Completed

### Worktree and dataset

- Created the clean evidence worktree and branch.
- Copied the complete generated `data/full_model_int` core dataset.
- Promoted only implemented gas inputs into the same dataset root:
  - `NaturalGas/`
  - `Sets/NaturalGas*.csv`
  - `Sets/OnshoreNode.csv`
  - `Transport/NaturalGasDemand.csv`
  - `Transport/CurtailCost.csv`
- Copied `config/run_full_model_int.yaml`.
- Copied Claude's converter into
  `scripts/convert_internalempire_xlsx.py`; the dirty source copy was not edited.

### Conversion and duplicate audit

- Changed converter defaults to the current OpenEMPIRE repository and sibling
  InternalEMPIRE source tree.
- Added self-contained natural-gas promotion.
- Added explicit Pyomo-compatible last-row-wins canonicalization for terminal
  costs.
- Generated:
  - 308 unique deterministic terminal-cost rows;
  - 308 unique stochastic terminal-cost rows;
  - `NaturalGas/terminal_cost_duplicate_audit.csv`;
  - `conversion_manifest.json` with hashes and row counts.
- Added `docs/natural_gas_terminal_cost_duplicates.md`.
- The final manifest reports 35 duplicate keys per terminal-cost table
  (70 discarded rows total), eight conflicting deterministic keys, and one
  conflicting reserve key.
- Added `scripts/validate_full_model_int_dataset.py`; it checks hashes, byte and
  row counts, exact gas schemas, foreign keys, periods, uniqueness, finiteness,
  non-negativity, completeness, and audited selected values.

### Typed data foundation

- Added `NaturalGasSets` and nested it in `EmpireSets`.
- Added gas set accessors and core/gas foreign-key validation.
- Added `NaturalGasParams` and nested it in `EmpireParams`.
- Added gas parameter accessors and range/completeness validation.
- Added validated gas-specific CSV cell parsing:
  - numeric strings accepted;
  - missing, nonnumeric, fractional integer, overflowing, non-finite, negative,
    duplicate, or wrong-schema values rejected with file/row/column context.
- Added gated gas set/parameter loading from the self-contained CSV dataset.
- Extended `read_data`/`read_data_csv` with optional gas and scenario-count
  keywords while preserving module-off defaults.
- Added scenario-axis helpers:
  - weather scenario count;
  - gas scenario count;
  - combined count;
  - deterministic combined-to-weather/gas mapping.
- `_prepare_model_inputs` now creates the combined scenario count and requests
  gated gas data.
- Instantiated the ignored local `Manifest.toml`; `using OpenEMPIRE` now
  precompiles and loads successfully.

### Model and results

- Scenario generation now samples each weather scenario once and replicates
  that profile across its gas-price scenarios. Sampling keys remain indexed by
  weather scenario.
- Added gated sparse JuMP variables for terminal imports, pipelines,
  gas-for-power, gas storage, and transport demand/shedding.
- Added gas-for-power conversion, terminal capacity, finite reserves,
  per-season storage reset, pipeline capacity/electricity demand, transport
  demand, and nodal gas balance.
- Gas generators no longer pay the ordinary fuel-price term when the module is
  enabled; variable O&M and carbon costs remain.
- Added terminal-import and transport-shedding objective components.
- Added streamed native and Python-style gas result tables, including both
  weather and gas scenario axes. Gas-price/storage dual output is conditional
  on valid solver duals.
- Added initial manifest gas-input hashes/conversion provenance and OOS
  configuration/aggregation hooks.
- Added fixed-investment OOS structural matching for the `natural_gas` gate.
- Added conditional aggregation of all six native gas output families.
- Added full-year output mapping for 24 independently solved 365-hour chunks;
  gas rows receive `HourFullYear=1:8760` and dummy-peak rows are removed.
- Added 139 deterministic natural-gas tests covering strict loading, scenario
  mapping, weather replication, model equations, results, OOS compatibility,
  full-year gas aggregation, active storage, transport shedding, zero supply,
  infeasibility, emission caps, module-off artifacts, and solved 3×3 scenarios.

## Independent review, 2026-07-30

An independent review of the gas implementation and of PR #30 raised one
critical and one high finding, both since fixed on this branch. The full list
and its disposition:

### Fixed — critical

**Gas generators were priced at zero marginal cost on `full_model_int`.**
`preprocess_operational_cost` skipped any generator without a `genFuelCost`
entry *before* reaching the branch that zeroes gas fuel. Because InternalEMPIRE
prices gas through the gas module, the workbook has no `genFuelCost` row for
`Gasexisting`, `GasOCGT`, `GasCCGT`, `GasCCSadv` or `GasCCS` at all, so all five
were skipped, no `genMargCost` key was written, and `gen_marginal_cost` fell
through to `DEFAULT_GEN_MARGINAL_COST` (zero). The intended
"drop fuel, keep variable O&M and carbon" branch was unreachable for exactly the
generators the module targets, and the merit order among the five gas
technologies collapsed to a tie.

`src/utils.jl` now decides `gas_fuelled` first, skips only on a missing
efficiency profile, and raises a named `ArgumentError` when a generator has an
efficiency but no fuel price and is not gas-fuelled. Verified on the real
dataset with an emission cap: `GasCCGT`/`GasOCGT`/`Gasexisting` reduce exactly to
their variable O&M (2.31 EUR/MWh), matching InternalEMPIRE's
`prepOperationalCostGen_rule`.

The previously reported reduced one-period objective `9.479417173693846e11` was
produced with this defect active and must not be used as a baseline.

### Fixed — high

**PR #30 shipped a dataset that its own branch could not build.** The dataset and
the empty-`StrategicProfile` fix were split across branches, so `create_model`
on `full_model_int` failed with an opaque
`BoundsError: attempt to access 0-element Vector{FixedProfile{Float64}}` from
`validate`. PR #30 now carries the minimal standalone fix (skip on missing
efficiency, explicit error on missing fuel price), a
`test_read_full_model_int_dataset` smoke test, and a config comment stating that
the dataset requires the gas module.

### Fixed — medium and low

- Gas input validation was advisory only, because `create_model` calls
  `validate(...; strict = false)`, which downgrades every issue to one warning.
  Added `validate_natural_gas`, which `create_model` now enforces as fatal
  whenever the module is enabled.
- Reserve and storage rows are now built scaled by `NATURAL_GAS_ROW_SCALE`
  (`1e-3`), matching InternalEMPIRE's explicit `/1e3` conditioning. Reserves
  reach 5.55e8 t against ~7.3e3 coefficients, so the unscaled rows had roughly
  1e5 intra-row spread. The scaled storage-balance dual is corrected back to
  EUR/ton when written.
- Gas result tables were computed twice, once per alias filename, re-walking
  every operational period and re-querying every JuMP value. They are now built
  once and copied.
- Dropped the redundant `duration(operational_period)` factor from the reserve
  sum. It was a no-op only because every operational period has unit duration,
  and it diverged from the `multiple_strat` idiom used by the emission cap.
- Shared `FINITE_RESERVE_TERMINALS` through `is_finite_reserve_terminal` instead
  of repeating the literal in `empire_structs.jl`.
- Cached the operational-period context on the JuMP model, so it is built once
  per model rather than three times.
- Gas generators without a `genEfficiency` profile are now a validation issue
  rather than a bare `KeyError` during constraint building.
- `test/test_solve.jl` copies `data/test_excel` into a temporary directory before
  building. The suite no longer rewrites the tracked sampling key, so it no
  longer has to be restored by hand after every run.

### Known difference, deliberately kept

Base OpenEMPIRE adds a CCS transport-and-storage term to generator marginal cost
(`CCSRemFrac * genCO2TypeFactor * CCSCostTSVariable`); InternalEMPIRE's
`prepOperationalCostGen_rule` has no CCS term at all. `GasCCS` and `GasCCSadv`
therefore sit slightly above their variable O&M in Julia. This is a pre-existing
OpenEMPIRE-versus-InternalEMPIRE difference in the port target, not a gas-module
behaviour, and the dataset test asserts it explicitly.

### Accepted as-is

- `TerminalCost.csv` versus `TerminalCost_stochastic.csv` is selected by gas
  scenario count rather than InternalEMPIRE's `gas_stochasticity_flag`. Harmless
  here because the stochastic sheet's repeated values agree at scenario 1.
- Module-off runs still gain two zero-valued gas columns in the objective
  component tuple and the OOS summary. Additive, but it will change hashes for
  anyone diffing electricity-only OOS summaries against older runs.
- The Pyomo parity model is an independent hand-written restatement, not
  `InternalEMPIRE/empire.py` itself. It establishes equation-level parity, not
  agreement with the reference implementation's own code.

## Current work in progress

The implementation compiles, the complete suite passes, and the review findings
above are resolved. The remaining work is delivery preparation rather than
missing model behaviour.

Next immediate actions:

1. After required runner/OOS/north-sea PRs merge, transplant the deterministic
   gas implementation onto fresh `main`; do not merge this 94-commit evidence
   ancestry. The model core (`natural_gas.jl`, `empire_sets.jl`,
   `empire_structs.jl`, `read_csv.jl`, `model_definition.jl`, `utils.jl`,
   `user_interface.jl`, `results.jl`, `scenario.jl`) has no OOS dependency; only
   `out_of_sample.jl`, `oos_aggregation.jl`, `run_julia_empire.jl` and
   `test_runner_staging.jl` do. That supports three PRs rather than two:
   deterministic gas core, gas OOS/runner integration, then the stochastic axis.
2. Split the gas-price scenario axis into the following fresh stochastic PR.
3. The former seven-period HiGHS `OTHER_ERROR` has been superseded and
   attributed. Both HiGHS and Gurobi identify the North-Sea-enabled reduced
   model as infeasible; Gurobi's IIS contains only North Sea
   investment/transmission constraints and bounds at HelgoländerBucht. With
   North Sea disabled, the complete seven-period gas model solves to optimality.
   See `docs/natural_gas_equivalence_assurance.md`.

### Newly discovered source-data issue

- The strict reader found two `Reserves.csv` rows for Italy:
  `2_181_585_300.486274` and `28_830_371.653353803` tonnes.
- InternalEMPIRE's node-indexed Pyomo parameter silently keeps the later row.
- The converter now applies that same rule explicitly and writes
  `NaturalGas/reserves_duplicate_audit.csv`. The Julia reader continues to
  reject duplicates in an already-converted dataset.

## Decisions locked

- `natural_gas: false` by default.
- `number_of_gas_scenarios: 1` by default.
- Deliver deterministic gas first, then stochastic weather × gas scenarios.
- Gas transport demand is part of `natural_gas` and does not depend on Hydrogen.
- Gas-fired generators keep variable O&M and carbon costs and omit only the
  ordinary fuel price. A dataset that omits a fuel price for a non-gas generator
  is an error, not a silent zero.
- Gas input validation is fatal when the module is enabled, unlike the general
  `strict = false` parameter validation.
- Reserve and storage rows carry InternalEMPIRE's `1e-3` conditioning scale, and
  duals derived from them are rescaled before they are written.
- Duplicate source terminal costs use explicitly audited last-source-row-wins
  semantics, matching Pyomo `DataPortal`.
- Version the runnable approximately 77 MB dataset.
- No Industry, Hydrogen, Heat, pipeline repurposing, or CVaR implementation.
- Gas adds no strategic variables, so the existing eight OOS fixed-investment
  tables remain unchanged.

## Verification log

- Converter ran successfully through `conda run -n empire_env`.
- Final converter regeneration after the README and reserve-audit changes:
  PASS.
- Conversion manifest integrity: PASS for all 85 listed output files; every
  byte count and SHA-256 matched and no output was unlisted.
- Independent regeneration into fresh temporary data/extra roots: byte-for-byte
  PASS (`diff -qr` produced no differences). Both conversion manifests had
  SHA-256 `d8864af820de14aeed7f809180d0548ce4a918f99dc1267b6cad325d9c421179`.
- Generated terminal-cost row counts:
  - `TerminalCost.csv`: 309 lines including header;
  - `TerminalCost_stochastic.csv`: 309 lines including header.
- `julia --project=. -e 'using OpenEMPIRE'`: PASS after `Pkg.instantiate()`.
- First strict full-model gas load: EXPECTED FAIL on the newly discovered
  duplicate Italy reserve. Converter regeneration is required before rerunning.
- Converter regeneration after reserve canonicalization: PASS.
- Strict full-model gas load/validation: PASS with 37 nodes, 94 links,
  44 terminal-node pairs, 5 gas generator types, 308 terminal costs,
  15 reserves, and zero validation issues.
- Scenario mapping checks: PASS for 1×1, 2×2, and 3×3.
- Tiny deterministic HiGHS fixture: OPTIMAL; 20 MWh generation required
  `2.8776978417266186` tonnes, exactly `20 / (0.5 * 13.9)`.
- Tiny stochastic 2×2 HiGHS fixture: OPTIMAL; weather profiles/dispatch were
  identical across gas scenarios and the objective used the correct gas-price
  axis.
- Native/Python-style gas CSV and conditional dual writers: PASS on the solved
  fixture; gas-balance residuals were zero.
- Existing focused TimeStruct/model regression: 20/20 PASS.
- Focused natural-gas suite: 105/105 PASS.
- Dedicated full-year gas aggregation: PASS with 24 × 365 = 8,760 retained
  rows and 24 dummy-peak rows removed.
- Complete Julia suite at the preceding checkpoint: all active testsets passed
  (Excel 66, CSV 63, natural gas 95 at that checkpoint, CSV scenarios 164,
  runner 85, OOS 161, full-year OOS 168, OOS aggregation 55, and all
  Solstorm/validation/time/model-solve tests). One pre-existing optional Python
  comparison was reported as broken/skipped because its temporary raw fixture
  does not contain `Sets/Generator.csv`.
- Historical pre-review full-model evidence: a complete seven-period,
  one-weather-scenario gas build produced 299,586 variables and 371,975
  constraints, but its HiGHS solve returned `OTHER_ERROR`. A reduced
  one-period solve returned objective `9.479417173693846e11`. Both results have
  since been superseded: the former was attributed to an unrelated North Sea
  conflict and the latter used the zero-priced-gas defect. Corrected evidence
  is recorded under "After the 2026-07-30 review fixes" below.
- The full-dataset smoke exposed a pre-existing empty-profile construction for
  generators without fuel/efficiency entries. `preprocess_operational_cost`
  now skips those generators before constructing a `StrategicProfile`.
- Controlled Julia/Pyomo gas-only parity: PASS for 26 keyed metrics. Maximum
  absolute difference `8.881784197e-16`; maximum relative difference
  `1.7763568394e-16`. The comparison covers objective components, terminal
  imports, pipeline flow, storage, gas-for-power, transport demand/shedding,
  and electricity generation. Commands and separate hands-on output tables are
  documented in `docs/natural_gas_parity.md`.
- `@code_warntype`: concrete returns for full gas parameter parsing
  (`NaturalGasParams`), operational-period context
  (`Dict{OperationalPeriod, NamedTuple{...}}`), and YAML-style combined
  scenario counting (`Int64`).
- Representative `BenchmarkTools.@btime` results:
  - full-dataset gas parsing: 1.066 ms, 17,350 allocations, 1.23 MiB;
  - context for 19,440 operational periods: 974.292 μs, 36 allocations,
    8.09 MiB;
  - combined scenario count: 166.227 ns, zero allocations;
  - controlled construct/solve/result write: 3.876 ms, 18,040 allocations,
    4.96 MiB.
- Consolidating three period-index dictionaries into one concrete context map
  reduced that benchmark from 2.342 ms / 20.28 MiB to 974.292 μs / 8.09 MiB.
- Focused natural-gas suite after the context-map optimization: 105/105 PASS.
- Final complete Julia suite after all gas, preprocessing, and allocation
  changes: PASS with process exit code 0. Counts include Excel 66, CSV 63,
  natural gas 105, CSV scenarios 164 pass plus the one pre-existing optional
  Python broken/skip, runner 85, OOS 161, full-year OOS 168, aggregation 55,
  Solstorm SGE 69, staging 108, cleanup 45, remote setup 25, submission 26,
  validation 16, TimeStruct 21, and solve 3.
- The suite rewrote the tracked Excel sampling key as part of scenario
  generation; it was restored exactly to `HEAD`, and there are no unrelated
  tracked test-data changes.
- Expanded focused natural-gas suite: 139/139 PASS. New coverage includes:
  module-off absence of gas variables/files; two-hour active storage with
  seasonal reset; transport conversion and shedding cost; zero terminal and
  pipeline capacity; explicitly infeasible no-shed supply; zero emission cap;
  complete reserve requirements; solved 3×3 weather × gas scenarios; and both
  scenario axes in result files.
- Gas-input manifest/checksum provenance test: 9/9 PASS, including the
  module-off missing-file bypass.
- PR #30 standalone validator after reserve completeness: PASS for all 85
  files, seven periods, 70 audited terminal-cost duplicates, and one audited
  reserve duplicate.
- Final complete Julia suite with 139 gas and 94 runner tests: PASS, exit code
  0. All other counts remain green (Excel 66, CSV 63, scenarios 164 + one
  pre-existing optional broken/skip, OOS 161, full-year 168, aggregation 55,
  SGE 69, staging 108, cleanup 45, remote 25, submission 26, validation 16,
  TimeStruct 21, solve 3).
- The final suite-generated Excel sampling key was again restored byte-for-byte
  to `HEAD`.

### After the 2026-07-30 review fixes

- Focused natural-gas suite: 471/471 PASS, up from 139. New coverage: gas
  marginal cost with no fuel price present (the real `full_model_int`
  condition), the emission-capped variable-O&M-only case, the explicit error
  when the module is off, the untouched non-gas generator, the no-efficiency
  fallback, a dataset-level assertion over all five `full_model_int` gas
  generators, enforced gas validation for missing reserves/terminal
  costs/efficiency, storage-balance duals pinned to the nodal gas price, and a
  2-period x 2-season x 2-weather x 3-gas weighting test.
- The weighting test is the main answer to the review's parity-breadth finding.
  The controlled Pyomo fixture has one strategic period, one representative
  period and one scenario, so it cannot exercise strategic duration, season
  multiplicity, scenario probability, or the gas-price axis. The new test checks
  292 assertions against hand-computed values: one reserve row per weather x gas
  pair, storage resets per representative period per scenario per strategic
  period, each terminal-import objective coefficient equal to
  `objective_weight * terminalCost` at that period's own gas scenario, each
  reserve coefficient equal to
  `NATURAL_GAS_ROW_SCALE * duration_strat * multiple_strat` with exactly one row
  per variable, every reserve row reached, and uniform `1/(W*G)` probabilities.
- Controlled Julia/Pyomo gas-only parity after the row scaling: PASS, still 26
  keyed metrics. Maximum absolute difference `4.54747350886e-13`, maximum
  relative difference `3.5527136788e-16`. The absolute figure moved from
  `8.881784197e-16` because the scaled rows change LP numerics slightly; the
  relative figure remains at machine precision.
- Complete Julia suite: PASS. Excel 66, CSV 63, natural gas 471, CSV scenarios
  164 plus the one pre-existing optional Python broken/skip, runner staging 94,
  OOS 161, full-year OOS 168, aggregation 55, Solstorm SGE 69, staging 108,
  cleanup 45, remote setup 25, submission 26, validation 16, TimeStruct 21,
  solve 3. Total 1,555 passing.
- `git status` is clean after a complete suite run. The tracked Excel sampling
  key is no longer rewritten, so no manual restoration is needed.
- PR #30 suite after its minimal fix: PASS, with CSV rising from 63 to 84
  assertions on the new `full_model_int` dataset test.
- Repeated the corrected one-period `full_model_int` solve at the exact prior
  42,798-variable/20-hour scale: HiGHS OPTIMAL and FEASIBLE_POINT, objective
  `9.523177899833549e11`, build 26.71 s, solve 0.54 s. This replaces the invalid
  zero-priced-gas objective.
- Repeated the seven-period/one-weather/20-hour model with both HiGHS and
  Gurobi. With North Sea enabled both report INFEASIBLE. Gurobi's IIS contains
  `max_inv_tech`, `max_inst_tech`, `wind_farm_transmission_cap`,
  `installed_cap_gen`, `trans_track_cap`, and associated bounds at
  HelgoländerBucht; no natural-gas family appears.
- With North Sea disabled, the seven-period gas model is OPTIMAL and
  FEASIBLE_POINT in Gurobi: 299,586 variables, 371,975 structural constraints,
  objective `4.753786325741043e18`, build 27.93 s, solve 2.00 s. The objective
  is dominated by electric load shedding in the deliberately reduced temporal
  representation and is not a calibrated planning result.
- Added `docs/natural_gas_equivalence_assurance.md`, mapping each overlapping
  gas equation directly to InternalEMPIRE commit
  `14675a780129e11d03b9e9f4a03fb2649c715346`, recording the numerical evidence,
  intentional differences, and the scoped subsystem-equivalence claim.

## Working tree summary

### Gas acceptance gate hardening, 2026-08-02

- Deterministic delivery now rejects `number_of_gas_scenarios > 1`; the existing
  multi-gas implementation remains evidence for a later stochastic PR but is not a
  supported public mode until actual two-price-scenario reference parity exists.
- The real InternalEMPIRE LP builder now accepts explicit repository/work-directory
  arguments, verifies commit `14675a780129e11d03b9e9f4a03fb2649c715346`, checks
  reference Python files are unmodified, generates fresh tabs in an isolated folder,
  records workbook/tab/code/config hashes, and stops after LP export unless `--solve`
  is requested. It does not write to the dirty source checkout or require a solver
  licence for structural comparison.
- The gas-only reference restriction fixes the out-of-scope
  `repurposedPipelineBuilt` variables to zero before LP export and records that fact.
  The comparator then permits only the explicitly counted `ng_forHydrogen` column;
  every other unknown family is fatal.
- Matrix, objective, and bounds comparators now fail on empty parses, unknown
  variables, duplicate canonical keys, absent expected families, or incomplete row
  inventories. Dependency-free negative controls inject coefficient, RHS, row-key,
  unknown-variable, ordinary-gas-objective, and bound errors; all are detected.
- Objective parity now includes ordinary gas-fired `genOperational` coefficients.
  `GasCCS` and `GasCCSadv` differences are reported and require explicit acceptance
  because they contain base OpenEMPIRE.jl's pre-existing CCS transport/storage term.
- The complete reproducible comparison command passed for both 2-period x 1-weather
  and 3-period x 2-weather instances. The first compares 62,446 gas rows, 171,936
  row coefficients, 67,248 bounds, and 32,688 gas-relevant objective coefficients;
  the second compares 187,322 rows, 515,808 row coefficients, 201,744 bounds, and
  98,064 objective coefficients. All module-controlled/ordinary-gas values agree
  exactly; only the documented CCS coefficients differ.
- The optional Python scenario fixture now supplies `Sets/Generator.csv` and runs.
  The complete Julia suite passes 1,566 assertions: Excel 66, CSV 70, natural gas
  461, CSV scenarios 178, runner staging 94, OOS 161, full-year OOS 168,
  aggregation 55, SGE 69, staging 108, cleanup 45, remote setup 25, submission 26,
  validation 16, TimeStruct 21, and solve 3.
- `python3 scripts/test_gas_comparators.py` and
  `python3 scripts/validate_full_model_int_dataset.py data/full_model_int` both pass.
  The dataset validator ignores `.DS_Store` only and still rejects every unlisted
  model input.
- Accepted wording:

  > The deterministic natural-gas subsystem matches InternalEMPIRE's gas formulation
  > for its constraints, bounds, and module-controlled costs. Whole-model objectives
  > and dispatch can differ because OpenEMPIRE.jl retains base OpenEMPIRE electricity,
  > CCS, emission, and seasonal semantics.

The implementation and earlier acceptance changes are committed through `56103df`.
This acceptance-gate checkpoint is ready to commit on the evidence branch. No
generated test artifact or unrelated checkout change is present.
