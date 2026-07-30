# Copula-Cluster Scenario Generation: Behaviour and Results

This documents the Julia copula-cluster SGR port: how it departs from the Python
reference, its full-scale clustering profile on `europe_v51`, and a solved
baseline-versus-copula comparison.

Unlike [FILTER_COMPARISON.md](FILTER_COMPARISON.md), this is **not** a numerical
parity study. Strict Python parity is impossible here by design — two of the
three departures below change which candidates and feature dimensions exist, so
cluster-for-cluster agreement is not a meaningful target. What is verified
instead is internal consistency, reproducibility, and behaviour at full scale.

## Departures from the Python reference

All three are deliberate. The first was confirmed with the project lead; the
second fixes a latent crash; the third keeps the port consistent with Julia's own
sampler.

1. **Sample years.** Candidates use only years shared by every selected copula
   input. Python hard-codes 2015–2019 in `make_mean` regardless of the data
   loaded. The project lead confirmed the hard-coding reflects only what data
   happened to exist across all EMPIRE parameters, and that flexibility here is
   wanted. On `europe_v51` both resolve to 2015–2019, so this changes nothing
   today. The scenario filter makes the same choice.

2. **Feature dimensions.** Dimensions come from each selected variable's own
   columns. Python always uses `solar.csv`'s columns, chosen because solar data
   exists for every country while run-of-river hydro and offshore wind do not.
   That intent does not generalise mechanically: on `europe_v51`,
   `windoffshore.csv` uses offshore zone codes (`MF`, `FF`, `DB`, …) rather than
   country codes, and `hydroror.csv` omits `BA`. Python therefore raises
   `KeyError` for `copulas_to_use: ["windoffshore"]` or `["hydroror"]`; the Julia
   port does not.

3. **Candidate window range.** Offsets run `0:(n_season_hours - regular_hours)`
   inclusive. Python uses `range(n_season_hours - regular_hours - 1)`, excluding
   the final two windows of every year-season. The Julia range is exactly the
   one `_random_regular_sample` draws from, so every clustered candidate is a
   window unstratified sampling could also have selected. This is the one place
   the copula port and the scenario filter differ: the filter replicates
   Python's narrower range to support its candidate-key parity claim, yielding
   40,444 keys where copula clustering yields 40,484 on the same input.

   Python's cutoff makes the last two hours of every season structurally
   unsampleable. For winter 2015 (2,160 hours, 168-hour seasons) its final
   candidate covers hours 1,991–2,158, so hours 2,159 and 2,160 appear in no
   candidate window at all; the inclusive range covers 1–2,160. Across five
   years and four seasons that is 40 hours of input data Python cannot select,
   with no modelling rationale distinguishing them — the narrower bound reads as
   index arithmetic that overshot rather than a deliberate exclusion.

   The counter-argument is cross-feature consistency: a maintainer comparing the
   two clustering paths will find the difference surprising, and it forecloses a
   candidate-key parity study for copula clustering later. That tradeoff was
   accepted because parity is already unattainable here — departure 2 changes the
   feature dimensions, so no cluster-for-cluster comparison against Python is
   possible regardless, and replicating the off-by-one would inherit its cost
   without buying a parity claim. At 0.093 % of season hours the practical effect
   on results is negligible either way; the choice is about not reproducing a
   defect gratuitously, not about materially different outcomes.

### Precedence and RNG

Fixed sampling takes precedence over `filter_use`, which takes precedence over
`copula_clusters_use` — matching Python's `if filter_use: … elif
copula_clusters_use: …`.

Python still advances its cluster counter and consumes `np.random.choice` draws
under `use_fixed_sample: true` before overwriting the result from the sampling
key; Julia skips those branches entirely. Sampled regular seasons agree either
way because the key fully determines them, but the downstream RNG stream — and
therefore peak-season selection — can diverge in that specific combination.

Clustering consumes the scenario RNG, and cluster labels are canonicalised by
sorted centers, so an equal seed reproduces the catalog including its
`ClusterGroup` numbering. `test_copula_clusters_make_writes_csv` asserts this.

## Clustering profile on `europe_v51`

`copulas_to_use: ["electricload"]`, `n_cluster: 10`, 168-hour regular seasons,
seed 1, 49 nodes. Electric load contributes 35 node columns, so k-means runs on
a 35-dimensional rank-transformed feature space, 100 restarts per season.

| Season | Candidates | Non-empty clusters |
|---|---:|---:|
| winter | 9,989 | 10 |
| spring | 10,085 | 10 |
| summer | 10,205 | 10 |
| fall | 10,205 | 10 |
| **total** | **40,484** | — |

Cluster sizes across all seasons ranged from 3,301 to 4,774 (mean 4,048), so no
cluster collapsed or absorbed a disproportionate share. Years resolved to
2015–2019 as expected.

Clustering all four seasons took **≈363 s** on a local Windows workstation, the
dominant cost of an otherwise ~9 s scenario-generation step. This is a one-time
cost per `copula_clusters_make: true` run — negligible beside the multi-hour
solves below — but it is not free, and it scales with `n_cluster`, restart count,
and the node count of every entry in `copulas_to_use`.

## Solved comparison

Two full `run_2060` optimizations on Solstorm, Gurobi, seed 1, identical apart
from the sampling mode. The copula run used a duplicated dataset directory so the
two jobs could not race on shared `ScenarioData` output.

| | Baseline (unstratified) | Copula clusters |
|---|---|---|
| Dataset | `europe_v51` | `europe_v51_copula` |
| Termination | `OPTIMAL` | `LOCALLY_SOLVED` |
| Solve seconds | 21,858 | 22,147 |
| **Objective** | **4.643551e12** | **4.583776e12** (−1.29 %) |

Objective components:

| Component | Baseline | Copula | Change |
|---|---|---|---:|
| generator_investment | 3.339561e12 | 3.313277e12 | −0.79 % |
| storage_investment | 9.052455e10 | 1.067261e11 | +17.90 % |
| transmission_investment | 7.377339e10 | 7.593939e10 | +2.94 % |
| load_shedding | 3.253328e8 | 1.871233e9 | +475.2 % |
| generator_operation | 1.139367e12 | 1.085962e12 | −4.69 % |

The copula run reached a 1.29 % lower total system cost while shifting the
investment mix: less generation capacity, more storage and transmission, and
markedly lower operating cost, but nearly six times more load shedding.

### How much this does and does not show

- **One seed per mode.** This cannot separate a systematic effect from a single
  favourable draw. The motivating question — whether stratification yields
  *more stable* investment decisions — requires several seeds per mode and a
  comparison of spread within each, which has not been run.
- **Differing termination status.** With `solver_crossover: 0`, barrier can
  report `LOCALLY_SOLVED` on converging within tolerance without a certified
  basic solution. The copula solution is therefore slightly less strongly
  certified than the baseline's, which is worth keeping in mind when reading a
  1.29 % gap.
- **Load shedding rose sharply** in relative terms while remaining small in
  absolute terms (≈0.04 % of total cost). Whether that is desirable behaviour or
  a sign that stratification is over-weighting scarce regimes is not settled by
  a single run.

## Reproduce

Build and immediately use a catalog, without building a model:

```yaml
use_scenario_generation: true
use_fixed_sample: false
copula_clusters_make: true
copula_clusters_use: true
copulas_to_use: ["electricload"]
n_cluster: 10
```

```sh
julia --project=. scripts/run_julia_empire.jl \
  --dataset=europe_v51 \
  --config=config/run_2060.yaml \
  --format=csv \
  --solver=none \
  --seed=1 \
  --generate-only
```

The catalog is written to
`data/europe_v51/Copulas/CopulaClusters/copula_clusters.csv`, and a run with
copula clustering enabled archives it under
`results/julia_runs/<run>/Input/ScenarioData/copula_clusters.csv`.

Focused tests:

```sh
julia --project=. -e '
using CSV, HiGHS, OpenEMPIRE, Dates, JuMP, Random, Test, TimeStruct, YAML
include("test/test_csv.jl")
include("test/test_scenario_csv.jl")
@testset "Copula clusters focused" begin
    test_copula_clusters_make_writes_csv()
    test_copula_clusters_use_samples_from_clusters()
    test_copula_clusters_use_without_make_errors()
    test_copula_clusters_invalid_copula_name_errors()
    test_write_scenario_copula_cluster_artifacts()
end
'
```

The complete Julia suite is:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```
