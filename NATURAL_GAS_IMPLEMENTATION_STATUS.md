# Natural Gas Implementation Status

Last updated: 2026-07-30 11:42 Europe/Oslo

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
  - `79b87c7` — standalone converted-dataset validation.
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

## Current work in progress

The implementation compiles and its focused tests pass. The remaining work is
verification and delivery preparation rather than missing core model behavior.

Next immediate actions:

1. Commit the final acceptance tests and live handoff checkpoint.
2. After required runner/OOS/north-sea PRs merge, transplant the deterministic
   gas implementation onto fresh `main`; do not merge this 94-commit evidence
   ancestry.
3. Split the gas-price scenario axis into the following fresh stochastic PR.

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
- Complete seven-period, one-weather-scenario `full_model_int` gas build:
  299,586 variables and 371,975 constraints; build 26.72 s; approximately
  13.08 GiB cumulative allocations and 2.30 GB maximum RSS. The attempted
  HiGHS solve returned `OTHER_ERROR`, so this is build evidence only.
- Reduced one-period deterministic `full_model_int` gas smoke solve: OPTIMAL
  and FEASIBLE_POINT, objective `9.479417173693846e11`, 42,798 variables,
  53,153 constraints, build 26.53 s, solve 0.394 s, and approximately 1.77 GB
  maximum RSS.
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

## Working tree summary

The evidence branch is committed through `79b87c7`. The only expected
uncommitted checkpoint is the final expanded acceptance coverage:

- `scripts/validate_full_model_int_dataset.py`
- `src/empire_structs.jl`
- `test/test_natural_gas.jl`
- `test/test_runner_staging.jl`
- `test/runtests.jl`
- this status file
