# OOS compact handoff

Last verified: 2026-07-28

This is the entry point for new agent sessions. Read this file first, then the
OOS sections of [`README.md`](README.md). Open
[`OOS_IMPLEMENTATION_STATUS.md`](OOS_IMPLEMENTATION_STATUS.md) only when exact
historical commands, job records, hashes, failure investigations, or the full
evidence trail are needed.

## Current state

The electricity-only OOS implementation is complete and validated on
`torgrim/oos-workbench-continuation`.

- A normal investment run chooses generation, storage, and transmission
  capacity. OOS reuses and fixes those strategic decisions, then tests system
  operation on scenario trees not used for the investment decision.
- Representative-period OOS, fixed-investment transfer, provenance checking,
  result validation, experiment queues, and aggregation are implemented.
- Accepted full-year OOS matches checked-in InternalEMPIRE: 24 independently
  solved consecutive 365-hour chunks, not one 8,760-hour optimization.
- Every solve has one scenario, a 365-hour `winter` season, and one dummy peak
  hour. The dummy is excluded from aggregation.
- Winter multiplicity is `(8760 - 1) / 365`, scenario probability is one, and
  the dummy multiplicity is one.
- The 24 chunks cover source rows 1:365, 366:730, ..., 8396:8760 and are
  duplicated across all strategic periods.
- Full-year slicing preserves InternalEMPIRE's filtered source-row order.
  Julia additionally validates complete, unique timestamps and records source
  disorder.
- Julia writes explicit dummy defaults equivalent to InternalEMPIRE's implicit
  Pyomo defaults: zero load, zero stochastic availability, and seasonal-hydro
  raw value one.
- Each chunk is a separate model, so winter and dummy-peak storage boundaries
  are independent for every tree.
- Aggregation removes non-`winter` rows, preserves tree identity, and computes
  `HourFullYear = Hour + (tree_index - 1) * 365`.

The older Julia formulation that solves one 8,760-hour model is superseded.
Keep it only as diagnostic and historical evidence; do not use it as the
accepted full-year method.

## Runtime and verification evidence

- Representative fixed-investment job `6421`: `OPTIMAL`; all eight strategic
  capacity tables were reproduced byte-for-byte.
- Superseded single-8,760-hour job `6424`: `OPTIMAL`, but diagnostic-only.
- Accepted full-year tree 1 job `6426`: `OPTIMAL`.
- Accepted sequential trees 2–24 job `6430`: all 23 remaining trees
  `OPTIMAL`, validated one at a time, fail-closed.
- All 24 results share fixed-investment fingerprint
  `9321df4c69cf2664ade384e5c2f9d59f7455a527725fcf813dd49a1b25fd9274`.
- Aggregated result:
  `results/julia_oos_runs/full_year_2015_internal_24x365_b0bbb80_aggregated/`
  in the `OpenEMPIRE.jl-workbench` checkout.
- The aggregation manifest and all three summary plus five combined-output
  hashes were revalidated on 2026-07-28.
- All 55,056,600 combined rows were streamed again: every file has trees
  1–24, only `winter`, local hours 1:365, full-year hours 1:8760, matching
  `Tree`/`ScenarioTree`, and zero hour-mapping violations.
- Focused current-branch OOS tests: 469/469 passed.
- Complete current-branch suite: 1,075 passed, zero failures/errors. One
  pre-existing external Python scenario fixture remains marked `Broken`
  because it lacks `Sets/Generator.csv`.

`OPTIMAL` means the models solved; it is not a reliability verdict. Material
load shedding is concentrated in a few trees and especially strategic period
4. No reliability acceptance threshold has been selected.

## Main implementation map

- `src/out_of_sample.jl`: fixed-capacity tables, compatibility/provenance,
  scenario generation, experiments, queues, and result reconciliation.
- `src/oos_full_year.jl`: exact InternalEMPIRE 24 × 365 construction and
  metadata.
- `src/oos_aggregation.jl`: accepted-result validation, physical ENS, cost
  separation, dummy removal, and streamed combined outputs.
- `scripts/run_julia_empire.jl`: immutable staging, fixed investments,
  investment-constraint omission, solver safety, manifests, and results.
- `scripts/prepare_full_year_oos_experiment.jl`: prepares the 24 full-year
  trees without solving.
- `scripts/aggregate_out_of_sample_results.jl`: validates and aggregates
  completed trees.
- `test/test_out_of_sample.jl`, `test/test_oos_full_year.jl`,
  `test/test_oos_aggregation.jl`, and `test/test_runner_staging.jl`: primary
  deterministic evidence.

## InternalEMPIRE equivalence boundary

Deterministic tests map and reproduce partitioning, source-row selection,
strategic-period duplication, scenario probability, season scaling,
dummy-peak defaults, storage boundaries, independent jobs, fixed investments,
and concatenation. The checked-in Python generator was also run against the
test fixture; all 24 Julia-generated trees matched its load, hydro, and
availability tables within `1e-12`.

A direct numerical Python-versus-Julia `europe_v51` solve is unavailable
because the current dataset and checked-in InternalEMPIRE input schemas have
diverged. Do not claim numerical full-case Python parity. The verified claim is
source/fixture-level functional equivalence plus controlled Julia runtime and
real aggregation identities.

## Git and PR state

- Evidence/integration branch: `torgrim/oos-workbench-continuation`.
- General-functionality base: `torgrim/workbench`.
- No `rf/*` branch or commit was merged or cherry-picked. Preserve those
  branches and existing PRs as references.
- The implementation was manually integrated on the newer workbench runner,
  informed by InternalEMPIRE and historical OOS work.
- This large branch is not one employee-review PR. Keep it intact as the
  evidence source.
- Infrastructure PRs must merge first. Then create small, non-stacked OOS PRs
  from the newly updated base: core fixed investments; runner/provenance;
  experiments/queue; aggregation; InternalEMPIRE full-year core; optional
  Solstorm tooling.
- Do not push, open PRs, merge, rebase, reset, delete, or rewrite branches
  without explicit user approval.

## Future heat and hydrogen work

Neither module has been implemented in this Julia OOS branch. The detailed
workspace plans are analysis documents written before OOS completion, so their
OOS status sections are historical; use this handoff for current OOS facts.

- [Heat module and earlier OOS review](../oos_review_and_heatmodule_port_plan.md):
  proposed config-and-data-gated heat sets, parameters, thermal flow balance,
  converters, heat storage, results, OOS converter capacity fixing, branch
  slicing, and validation. The reference heat path has unresolved defects and
  missing data sources, so verify author decisions before treating every
  Python behavior as binding.
- [Hydrogen module port plan](../hydrogen_module_port_plan.md): hydrogen does
  not technically depend on heat. The recommended first increment is green
  hydrogen plus imports, pipelines, storage, transport demand, H2-fired
  generation, and the CO2 network. Natural gas, reformers, and pipeline
  repurposing are a separate Phase B required for full-case objective parity.

Both modules touch the electric flow balance; land one before starting the
other. Hydrogen-first is technically defensible because its reference path is
actively exercised, although the original organizational plan listed heat
first. Whichever module lands second needs a combined heat–hydrogen test.

Each module must extend OOS as part of its own reviewable increment:

1. export every new strategic investment and installed-capacity table;
2. validate provenance and compatibility;
3. fix those variables and omit their investment-only constraints in OOS;
4. add deterministic investment-to-OOS round-trip tests;
5. add relevant operational outputs to aggregation without weakening the
   existing 24 × 365 contract.

## What a new agent should do

1. Read this file and the OOS README sections; do not initially load the large
   journal.
2. Run `git status --short --branch` and `git worktree list` before editing.
   Preserve unrelated changes and use a clean worktree when necessary.
3. Do not rerun jobs `6421`, `6424`, `6426`, or `6430`, and do not regenerate
   the accepted aggregation.
4. For OOS history, search the large journal for the exact job, commit, or
   topic instead of reading all of it.
5. The next OOS action is PR coordination. Check which infrastructure PRs have
   merged, then prepare only the first curated OOS scope when authorized.

Suggested resume prompt:

> Read `OOS_HANDOFF.md` and the OOS README sections. Verify branch, worktrees,
> and Git status. Do not rerun completed OOS jobs or aggregation. Use
> `OOS_IMPLEMENTATION_STATUS.md` only for specific historical evidence. Report
> whether the infrastructure prerequisites permit preparing the first compact
> OOS PR; do not push or open a PR without approval.
