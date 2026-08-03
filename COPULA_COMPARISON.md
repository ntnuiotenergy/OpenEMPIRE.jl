# Python–Julia Copula-Cluster Comparison

This documents how the Julia copula-cluster SGR port compares with the Python
reference in `OpenEMPIRE/empire/core/scenario_random.py`: which artifacts can be
compared directly, where the two still differ, and what has been measured on
`europe_v51`.

It is the copula counterpart to [FILTER_COMPARISON.md](FILTER_COMPARISON.md).

## Catalog format

Both implementations write `Copulas/CopulaClusters/copula_clusters.csv` with the
same schema:

```
Year, Season, SampleIndex, Value1, ..., ValueN, ClusterGroup
```

`ValueI` is the rank-transformed window mean of the I-th feature dimension — the
uniform margin the clustering ran on. `N` is the number of dimensions, one per
(variable, node) pair: `copulas_to_use: ["electricload"]` on `europe_v51` gives
35 node columns and therefore `Value1`…`Value35`, for 39 columns in total.

Persisting the `Value` columns is what makes the two catalogs comparable. The
`ClusterGroup` column is **not** directly diffable: Python takes
`KMeans.predict` output as-is, so its labels have no intrinsic ordering, while
this port canonicalises them by sorting cluster centers. Comparing partitions
therefore needs a label-invariant measure such as the adjusted Rand index (ARI),
exactly as in the filter comparison. The `Value` columns are the part that
supports a direct numerical diff.

Cost note: on `europe_v51` the catalog is ~27 MB with the `Value` columns, up
from ~730 KB without them, and a run using copula clustering archives a copy
under `results/julia_runs/<run>/Input/ScenarioData/`. That is the price of
matching Python's format.

## Candidate windows

Both enumerate the same candidate keys. Per year and season the offsets run

```
0 .. (season_hours - regular_hours - 2)
```

which reproduces Python's `for j in range(max_sample - regularSeasonHours - 1)`
in `make_mean`, whose exclusive upper bound stops two short of the last window
that actually fits.

This is inherited rather than chosen: `_filter_metric_rows` already reproduces
the same bound for the scenario filter via Python's `make_ws`, and
FILTER_COMPARISON.md records the filter producing 40,444 candidate keys on this
input. Copula clustering now produces the same 40,444, so the two stratification
paths agree with each other and with the reference.

Note that Julia's *unstratified* sampler, `_random_regular_sample`, still draws
from `0:(season_hours - regular_hours)` inclusive — two wider than Python's
`np.random.randint(0, window)`. That predates the copula work and affects every
non-stratified run, so it is untouched here, but it does mean the stratified and
random paths in this repo cover slightly different candidate sets.

## Remaining departures from Python

Two, both deliberate.

1. **Sample years.** Candidates use only the years shared by every selected
   copula input. Python hard-codes 2015–2019 in `make_mean` regardless of what
   data is loaded. The project lead confirmed the hard-coding reflects only what
   data happened to exist across all EMPIRE parameters, and that flexibility is
   wanted. On `europe_v51` both resolve to 2015–2019, so nothing changes today.
   The scenario filter makes the same choice.

2. **Feature dimensions.** Dimensions come from each selected variable's own
   columns. Python always uses `solar.csv`'s columns, chosen because solar data
   exists for every country while run-of-river hydro and offshore wind do not.
   That intent does not generalise mechanically: on `europe_v51`,
   `windoffshore.csv` uses offshore zone codes (`MF`, `FF`, `DB`, …) rather than
   country codes, and `hydroror.csv` omits `BA`. Python therefore raises
   `KeyError` for `copulas_to_use: ["windoffshore"]` or `["hydroror"]`; this port
   does not.

Departure 2 means a cluster-for-cluster comparison is only meaningful when the
selected variable's columns coincide with `solar.csv`'s — which for
`["electricload"]` on `europe_v51` they do.

### Precedence and RNG

Fixed sampling takes precedence over `filter_use`, which takes precedence over
`copula_clusters_use`, matching Python's `if filter_use: … elif
copula_clusters_use: …`.

Python still advances its cluster counter and consumes `np.random.choice` draws
under `use_fixed_sample: true` before overwriting the result from the sampling
key; Julia skips those branches entirely. Sampled regular seasons agree either
way because the key fully determines them, but the downstream RNG stream — and
therefore peak-season selection — can diverge in that specific combination.

Clustering consumes the scenario RNG, and cluster labels are canonicalised by
sorted centers, so an equal seed reproduces the catalog byte-for-byte including
its `ClusterGroup` numbering. `test_copula_clusters_make_writes_csv` asserts
this.

## Numerical comparison

Python's real `make_copula_filter` against the Julia path on the same input: all
35 `electricload` nodes, 2015, 168-hour seasons, `n_cluster: 10`.

Raw window means agree to **1.27e-15** relative across all nodes. 26 of the 35
rank-value columns are bit-identical; the rest differ at the 5e-4 level, one rank
position out of roughly 2,000.

One column is an outlier with a definite cause. `Value35` is BA (Bosnia), whose
load series is quantised to only 2,002 distinct values across 8,760 hours,
leaving **83 %** of its window means as exact ties. Inside a tie group the
ordering is decided entirely by tie-breaking, and although both sides break ties
by order of appearance, the means sit a few ULP apart from summation order, so
comparisons flip. Neither ordering is more correct. DE has 0 % tied means; NO1
has 0.1–0.3 %.

BA accounts for the entire partition disagreement:

| | ARI winter | spring | summer | fall |
|---|---|---|---|---|
| all 35 dimensions | 0.8936 | 0.9989 | 0.9910 | 0.9946 |
| BA excluded | **1.0000** | **1.0000** | **1.0000** | **1.0000** |

Sweeping `n_cluster` and re-clustering both sides' features at matched settings:

| k | mean ARI, all 35 | mean ARI, BA excluded |
|---:|---|---|
| 1 | 1.0000 | 1.0000 |
| 2 | 0.9985 | 1.0000 |
| 5 | 0.9890 | 1.0000 |
| 10 | 0.9520 | 1.0000 |
| 20 | 0.9799 | 1.0000 |
| 30 | 0.8535 | 1.0000 |

Excluding BA the two implementations agree exactly at every k from 1 to 30.

This check uses one year rather than five because Python's `make_mean` grows its
result with `pd.concat` inside a triple-nested loop, making it quadratic in
candidates, and copula clustering calls it once per node. One year over 35 nodes
takes 286 s; five years would be roughly 35x that. Full dimensionality is
covered; candidate count is not.

## Clustering profile on `europe_v51`

`copulas_to_use: ["electricload"]`, `n_cluster: 10`, 168-hour regular seasons,
seed 1, 49 nodes, 35 electric-load node columns, 100 k-means restarts per season.

| Season | Candidates | Non-empty clusters |
|---|---:|---:|
| winter | 9,979 | 10 |
| spring | 10,075 | 10 |
| summer | 10,195 | 10 |
| fall | 10,195 | 10 |
| **total** | **40,444** | — |

Pooled cluster sizes range 3,073–5,214, so no cluster collapsed or absorbed a
disproportionate share. Years resolve to 2015–2019 as expected.

`maxiter = 300` is not load-bearing: k-means converges in 12–63 iterations,
20/20 restarts converge, and costs are identical at 100 and 300. It is kept only
to match `_cluster_filter_rows`.

## Solved comparison and seed variability

Two full `run_2060` Gurobi solves on Solstorm, seed 1, identical apart from
sampling mode:

| | Baseline | Copula |
|---|---|---|
| Termination | `OPTIMAL` | `LOCALLY_SOLVED` |
| Objective | 4.643551e12 | 4.583776e12 (−1.29 %) |

Four further baseline solves at seeds 1–4, identical apart from the scenario RNG
seed, all `OPTIMAL`:

| Seed | Objective | vs mean |
|---|---|---|
| 4 | 4.625761e12 | −0.57 % |
| 3 | 4.630269e12 | −0.47 % |
| 1 | 4.643551e12 | −0.18 % |
| 2 | 4.708658e12 | +1.22 % |

Mean 4.652059e12, spread **1.78 %**. All four built an identical model —
38,120,648 variables and 54,450,272 constraints — so the seed changes only which
weeks are sampled, not the problem structure.

Per-component spread over those four seeds, against the differences reported for
copula at seed 1:

| Component | Baseline spread, seeds 1–4 | Copula effect at seed 1 |
|---|---|---|
| Generator investment | 1.6 % | — |
| Generator operation | 4.0 % | −4.7 % |
| Transmission investment | 12.0 % | +2.9 % |
| Storage investment | 16.1 % | +17.9 % |
| Load shedding | 35x | ~5.8x |

**Every difference attributed to copula sampling at seed 1 is smaller than, or
comparable to, what the baseline does on its own between seeds.** A single-seed
comparison cannot establish an effect in either direction.

Two observations point the other way. The copula objective falls below all four
baseline objectives, 0.90 % under the lowest, where noise alone would put it
inside the range about as often as outside. And the cluster round-robin gives
each cluster an equal share of draws regardless of how often that regime occurs
historically, so a copula tree represents rare weeks more heavily than a
proportional random draw — a mechanism that would produce a systematic rather
than random shift. Cluster sizes here are fairly balanced, so the distortion is
modest, but it is directional.

Neither is evidence from a single copula run. The open question is the copula
arm's own seed spread, which has not been measured.

Note that with `solver_crossover: 0`, barrier can report `LOCALLY_SOLVED` on
converging within tolerance without a certified basic solution, so the copula
solution is slightly less strongly certified than the baseline's.

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

To compare against Python, run its `make_copula_filter` on the same input and
diff the `Value` columns keyed on `(Year, Season, SampleIndex)`. Compare
`ClusterGroup` with ARI rather than equality, for the labelling reason above.

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

The complete suite is:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```
