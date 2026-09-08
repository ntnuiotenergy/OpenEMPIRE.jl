# NUTS2 power workflow

This document describes the NUTS2 power extension implemented on the
`feature/nuts2-power` branch: what it adds to the base OpenEMPIRE.jl power
model, how to convert an InternalEMPIRE Excel dataset into the CSV layout the
model reads, how to run it, and which tests cover it.

## Purpose and scope

The base model groups generation, storage and transmission by *node*. Several
capacity policies in the Python NUTS reference are expressed at *country*
level, over a country's constituent NUTS2 nodes, and a few input conventions
(sparse per-period profiles, biomass limits, generation-growth limits, an
Excel-driven offshore split) differ from the InternalEMPIRE datasets the Julia
port was originally wired for.

The extension adds, as **opt-in** features that leave the default model
unchanged when their inputs or flags are absent:

- country-to-node mapping and country-level generation-capacity constraints;
- generator nodal minimum-build capacity and per-period yearly availability;
- annual biomass usage limits at node, country and system level;
- node-level generation-growth limits;
- a BioCCS capacity-headroom factor on the upper capacity limits;
- explicit CCS captured-CO2 factors and matching cost accounting;
- a transmission fixed O&M cost correction;
- optional input-based season scaling;
- an Excel-driven offshore-node classification mode in the converter.

Each item below names the run-config key or input file that enables it and
states the behaviour when it is left at its default.

## Data is not stored in this branch

This Git branch contains **code and documentation only**. It does not ship the
NUTS2 datasets.

- Supply the required input workbooks or CSV datasets yourself, outside the
  repository, and point the converter and runner at them.
- Do not commit generated CSV datasets, `data_extra/` output, solver results,
  logs, `.lp` files, ZIP archives, `Manifest.toml`, or machine-specific run
  files. The repository `.gitignore` already excludes the common cases
  (`results/`, `logs/`, `Manifest.toml`, generated `ScenarioData/*Raw.csv`,
  `config/cluster.json`, `OutOfSample/`, …); keep new machine-specific paths
  and run artefacts out of commits as well.
- With every new option disabled (no country sets, no optional CSVs, flags at
  their defaults) the model builds exactly the same constraints as before this
  branch.

## Country-to-node mapping and country-level generation-capacity constraints

Two optional set files describe the mapping:

- `Sets/Countries.csv` — the list of countries.
- `Sets/NodesOfCountry.csv` — `(country, node)` rows.

Both are keyword-only in `EmpireSets` and default to empty. When present they
populate `countries(sets)`, `nodes_of_country(sets, c)` and
`country_of_node(sets, n)`.

Three country-level generation-capacity constraints are built when the
corresponding optional `Generator/*.csv` inputs are supplied, each summing the
relevant capacity variable over `nodes_of_country(sets, c)`:

| Constraint | Input file | Direction |
| --- | --- | --- |
| `max_inv_tech_country` | `Generator/genMaxBuiltCapCountry.csv` | built capacity per period ≤ limit |
| `min_inv_tech_country` | `Generator/genMinBuiltCapCountry.csv` | built capacity per period ≥ limit |
| `max_inst_tech_country` | `Generator/genMaxInstalledCapCountry.csv` | installed capacity ≤ limit |

Each row is guarded by `haskey(...)` on its parameter dict, so a country or
technology without a limit produces no row. With no country sets and no
`*Country.csv` inputs, none of these constraints exist.

## Generator minimum-build capacity and yearly availability

- **Nodal minimum build** — `Generator/genMinBuiltCap.csv`. Adds
  `min_inv_tech[n, tc, sp]` requiring the built capacity of technology `tc` at
  node `n` in strategic period `sp` to be at least the supplied limit. It is a
  plain sum of `genInvCap`, matching Python's `investment_gen_min_rule`; the
  BioCCS headroom factor (below) does **not** apply here.
- **Yearly availability** — `Generator/genYearlyAvailability.csv`, a sparse
  per-period profile. Applied as `gen_yearly_avail(par, n, g, sp)` inside the
  `gen_max_prod` capacity constraint, alongside the existing operational
  availability. Periods not listed in the file default to an availability of
  `1.0`, so a partial profile only reduces availability where it is stated.

## Annual biomass constraints

Enabled by `biomass_limit_flag` (default `true`) **and** the presence of
annual biomass data:

- `Node/maxBiomassNode.csv` — per-node annual availability.
- `Node/maxBiomassCountry.csv` — per-country annual availability.

Run-config keys: `biomass_limit_factor` (default `1.2`),
`biomass_system_limit_factor` (default `1.04`), `biomass_limit_scope`
(`"country"`, `"system"` or `"both"`, default `"country"`).

Depending on scope the builder emits `biomass_country_usage_limit` (per
country over `NodesOfCountry`), `biomass_node_usage_limit` (per node for nodes
that carry `maxBiomassNode` data but are not mapped in `NodesOfCountry`), and
`biomass_system_usage_limit` (one system-wide row). Each limits
probability-weighted annual generation from `Bio`-prefixed generators to
`factor ×` the referenced availability.

When annual biomass data is present it **replaces** the legacy
InternalEMPIRE fuel-based `availableBioEnergy` limit; that legacy limit is
built only when no annual data is supplied. This matches the Python reference,
which has no fuel-based bioenergy constraint. See the open follow-up in
[TODO.md](../TODO.md) regarding unmapped nodes that carry no nodal biomass
data.

With `biomass_limit_flag: false`, or with neither biomass CSV present, no
annual biomass rows are built.

## Node-level generation-growth constraints

Enabled by `generation_growth_limit_flag` (default `false`). Optional input
`General/GenerationGrowthRate.csv` supplies a per-period growth rate; missing
or non-finite entries, a trailing gap, or an absent file fall back to
`generation_growth_limit_rate` (default `0.04`).

For every node and every strategic period after the first,
`node_generation_growth` caps that period's generation at
`(1 + duration_strat(sp) × rate) ×` the probability-weighted average
generation of the previous strategic period, mirroring Python's
`node_generation_growth_rule`. Fewer than two strategic periods, or the flag
left `false`, produces no rows.

## BioCCS capacity headroom

Run-config key `bioccs_capacity_limit_factor` (default `1.0`, must be
`> 0`). The helper `_capacity_limit_contribution(capacity, g, factor)` returns
`capacity / factor` for a generator named exactly `BioCCS`
(case-insensitive, whitespace-stripped) and `capacity` unchanged otherwise, so
an all-BioCCS build may reach `factor ×` the stated limit.

The helper is applied to the upper/country capacity-limit expressions only:
`max_inv_tech`, `max_inst_tech`, `max_inv_tech_country`,
`min_inv_tech_country`, `max_inst_tech_country`. The nodal `min_inv_tech`
constraint stays a plain unscaled sum. At the default `factor = 1.0`,
`capacity / 1.0` is exact in `Float64`, so every coefficient is identical to
the pre-branch model.

## CCS captured-CO2 and cost-accounting compatibility

Optional input `Generator/CapturedCO2Content.csv` provides an explicit
captured-CO2 factor per CCS generator; negative values are rejected. When it
is absent the factor is resolved by fallback (gross-minus-net of a matching
counterpart generator, then a capture-rate default). CCS fixed investment cost
and operating cost are computed from the resolved captured factor to match the
Python implementation.

The converter's `--ccs-cost-mode` selects the transport-and-storage cost
provenance: `python-nuts` keeps the Excel `CCSCostTSVariable` values and
writes no `CCSCostTSFixed.csv`; `internalempire` (default) zeroes both. Non-CCS
generator costs are unchanged in either mode.

## Transmission fixed O&M correction

Corridor length multiplies the annualized transmission **capital** cost only.
Transmission fixed O&M is specified per MW-year and is added independently of
corridor length, consistent with the Python formulation. (Previously the Julia
cost multiplied the sum of annualized capex and fixed O&M by corridor length.)

## Optional input season scaling

Run-config flag `use_input_season_scale` (default `false`).

`create_timestruct` accepts optional `regular_season_scale` and
`peak_season_scale` keyword arguments. They must be supplied **together** or
not at all (an `ArgumentError` is raised otherwise). When supplied, each
regular-season operational hour is given a multiplicity of exactly
`regular_season_scale` and each peak hour exactly `peak_season_scale`, instead
of the shares derived from `operational_hours_per_year`.

When `use_input_season_scale: true`, `_prepare_model_inputs` reads the
dataset's `General/seasScale.csv`, requires one shared regular-season weight
and one shared peak weight, and passes them to `create_timestruct`. This
reproduces the Python validation setup, which reads `General.xlsx!seasonScale`
verbatim. When the flag is absent or `false`, both keyword arguments stay
`nothing` and the derived-share time structure is used unchanged.

## Offshore-node classification modes

The converter option `--offshore-node-mode {internalempire, excel}` (default
`internalempire`) selects how offshore nodes are split:

- `internalempire` — split "Node minus OnshoreNode" into wind farms and energy
  hubs using the hardcoded `WIND_FARM_NODES` / `ENERGY_HUB_NODES` lists, as
  `run_EMPIRE_int.py` does. This is the unchanged default.
- `excel` — when `Sets.xlsx` has an `OffshoreNodes` sheet, take every listed
  offshore node verbatim as an `OffshoreWindFarmNode` and write an empty
  `OffshoreEnergyHub` set. No hardcoded list is consulted.

To support workbooks whose `Sets.xlsx!Nodes` sheet has no `OnshoreNode`
column, `convert_core_sets` derives the onshore set as **all `Node` entries
minus the explicit `OffshoreNodes` sheet**. Workbooks that do carry an
`OnshoreNode` column are unaffected. The selected mode is recorded in
`conversion_manifest.json` as `offshore_node_mode`.

The model side of offshore handling (the wind-farm transmission cap, the
disjoint-set and generator checks in `validate!`, and the
`offshore_transmission_cap` run-config key) is unchanged; see the "Offshore
nodes" section of the main [README](../README.md).

## Excel-to-CSV conversion workflow

`scripts/convert_internalempire_xlsx.py` converts an InternalEMPIRE
"Data handler" Excel dataset into the CSV dataset layout the Julia model reads
(`data/<dataset>/…`), with non-core columns written under
`data_extra/<dataset>/…`. The NUTS2 inputs above are read from optional sheets
(`MinBuiltCapacity`, `YearlyAvailability`, `CapturedCO2Content`,
`BiomassMaxAnnualActivity`, `BiomassMaxAnnualActivityCountry`,
`GenerationGrowthRate`); a workbook that omits an optional sheet is converted
without it.

```bash
python scripts/convert_internalempire_xlsx.py \
  --dataset NESP_NECPEssentials \
  --source-root "C:/path/to/InternalEMPIRE/Data handler" \
  --data-root data \
  --extra-root data_extra \
  --periods 7 \
  --ccs-cost-mode python-nuts \
  --offshore-node-mode excel
```

Run `python scripts/convert_internalempire_xlsx.py --help` for the full option
list. The generated dataset directories are inputs to a run and should not be
committed.

## Running the model

Use the standard Julia runner with the converted dataset and a run-config YAML
that sets the NUTS2 flags you want:

```bash
julia --project=. scripts/run_julia_empire.jl NorthSea_NECPEssentials --config=config/<your-config>.yaml
```

The first positional argument is the dataset folder under `data/`. Add
`--format=csv`, `--solver=Gurobi`, `--no-optimize`, `--seed=<n>` as needed
(see `README.md` and the runner source for the complete flag set). The
model can also be built from a library call,
`OpenEMPIRE.create_model(config_file, data_folder; optimizer = …)`.

## Tests

| Test file | Covers |
| --- | --- |
| `test/test_country_constraints.jl` | country-to-node accessors and the three country capacity constraints, data-driven |
| `test/test_country_smoke.jl` | end-to-end solves for country min/max build and installed limits, plus a non-NUTS2 regression |
| `test/test_biomass_fallback.jl` | biomass country/both per-node fallback, system scope, and the `biomass_limit_flag` gate |
| `test/test_generation_growth.jl` | growth-rate loader, flag gate, first-period skip, coefficient values, per-period and trailing-gap fallback |
| `test/test_bioccs_headroom.jl` | identity at `factor = 1.0`, non-unit headroom, exactly the five affected constraints, nodal minimum staying a plain sum, rejection of `factor ≤ 0` |
| `test/test_ccs_captured_co2.jl` | explicit vs fallback captured-CO2 resolution, fixed and marginal cost matching Python, non-CCS costs unchanged |
| `test/test_ccs_cost_mode.jl` | `--ccs-cost-mode` provenance and realized coefficients |
| `test/test_stage1_parity.jl` | scaled season multiplier, unchanged default time structure, both-or-neither rejection, and dataset-gated North Sea `seasScale`/offshore checks that self-skip when the dataset is absent |
| `scripts/test_generation_growth_conversion.py` | `GenerationGrowthRate` sheet → CSV round-trip |
| `scripts/test_ccs_cost_variable_conversion.py` | CCS variable-cost conversion and mode regression |

The Julia test files are included from `test/runtests.jl`. The dataset-gated
checks in `test/test_stage1_parity.jl` return early when the referenced dataset
is not present locally.

## Validation status

The North Sea `NorthSea_NECPEssentials` NUTS2 setup was compared against the
Python NUTS reference with generation, storage and transmission capacity caps
removed ("cap-off"). Both models terminated optimally.

| | Objective (EUR) |
| --- | --- |
| Python | `5.272037176166460e12` |
| Julia | `5.272037147040988e12` |
| Absolute difference | 29,125,472 |
| Relative difference | ≈ 0.000552% |

This indicates close numerical parity for the validated setup. It is not a
claim of equivalence for other datasets, other configurations, or the cap-on
model.

## Known limitations

Open items are tracked in [TODO.md](../TODO.md). In particular, the annual
biomass handling for nodes that are unmapped in `NodesOfCountry` and carry no
nodal biomass data differs between the two implementations; this is recorded
as a follow-up to review before any model change.
