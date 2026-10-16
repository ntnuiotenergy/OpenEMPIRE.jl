# Deterministic Industry evidence module

## Configuration and scope

Industry is disabled by default:

```yaml
natural_gas: true
hydrogen: true     # optional
industry: true
number_of_gas_scenarios: 1
```

`industry=true` requires natural gas. The deterministic evidence implementation
rejects more than one gas-price scenario. Hydrogen is optional. Without Hydrogen,
the H2/CO2-dependent routes (`H2-DRI`, `H2-Cement`, `H2-Ammonia`, `BF-BOF-CCS`,
`NG-CCS-Cement`) and refineries are omitted; conventional steel, cement, and
ammonia remain active. With Hydrogen, all converted pathways and refinery Hydrogen
demand are active. Refinery heat demand is reported but unconstrained, matching the
intended `HEATMODULE=false` scope.

The module co-optimizes steel, cement, and ammonia capacity and hourly production.
Demand follows InternalEMPIRE with `FLEX_IND=false`: in every operational hour,
production plus shedding equals annual production divided by 8,760. It includes
Scrap/EAF material balance, the 45% Scrap limit, season-reset 10% ramp limits,
lifetime/retirement trajectories, and shedding. Production is coupled to
electricity, natural gas, Hydrogen, biomass, emissions, and captured-CO2 balances.

## Running and outputs

Copy `config/run_full_model_int.yaml`, enable the gates above, then run:

```bash
julia --project=. scripts/run_julia_empire.jl \
  --dataset=full_model_int \
  --config=/path/to/run_full_model_int_industry.yaml
```

Results are written below `<result-dir>/output/`. Native operational files are
`industrySteelOperations.csv`, `industryCementOperations.csv`,
`industryAmmoniaOperations.csv`, and, when active,
`industryRefineryOperations.csv`. Equivalent `results_industry_*.csv` aliases are
provided for hands-on Python comparison. Six strategic capacity files are written
for OOS: built and installed steel, cement, and ammonia capacity. The run manifest
records input hashes, conversion provenance, active/inactive pathways, gates,
scenario dimensions, and objective components.

Fixed-investment OOS validates and fixes all six complete capacity trajectories.
Industry gates and pathway inventories are structural compatibility inputs.
Representative OOS aggregates Industry operational files conditionally. Full-year
OOS streams all 24 independently solved 365-hour chunks to
`HourFullYear=1:8760`, excluding dummy-peak rows and without inventing inter-chunk
state coupling.

## Actual InternalEMPIRE comparison

The actual unmodified `empire.py` builder was compared directly against the
Julia LP export. That comparison requires the private InternalEMPIRE checkout, so
its tooling and evidence live outside this repository.

The two-period/one-weather comparison parses 75,582 dedicated Industry rows and
compares 238,155 dedicated coefficients, 50,400 Industry contributions in shared
electricity/gas/Hydrogen/CO2 balances, and 29,290 Industry-controlled objective
coefficients. All row keys, senses, right-hand sides, matrix coefficients, and
objective coefficients agree at `1e-9` tolerance. Biomass and emissions are
checked directly in Julia and in the solved fixture because their surrounding
base-model rows are not structurally identical between the two implementations.

The independent three-hour Pyomo fixture exercises every Industry route, refinery
Hydrogen, shedding, energy use, biomass, emissions, and CO2 capture in both a
carbon-price and an emission-cap mode:

```bash
PYTHON=/opt/homebrew/Caskroom/miniconda/base/envs/empire_env/bin/python
julia --project=. scripts/industry_parity_julia.jl \
  test/data/industry_parity /tmp/industry-julia.csv
"$PYTHON" scripts/industry_parity_python.py \
  test/data/industry_parity /tmp/industry-python.csv
"$PYTHON" scripts/compare_industry_parity.py \
  /tmp/industry-julia.csv /tmp/industry-python.csv
```

Both modes compare 68 metrics and pass at `1e-7` absolute/relative tolerance.

The measured model growth is linear in active producer/technology/operational-
period tuples; no dense cross-scenario tensor was introduced. Industry adds 920
variables and 1,572 constraints to a warmed one-hour full model. Inference checks
return concrete `IndustryParams`, `IndustrySets`, and `Vector{String}` validator
results. The heterogeneous validation-only diagnostic loops contain an inferred
`Any`, but the reader output and model containers are concrete and this is not a
model-build hot path.
