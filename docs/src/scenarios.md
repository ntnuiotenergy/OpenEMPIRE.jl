# Scenarios and out-of-sample

## Generate scenarios without building a model

Scenario generation follows the same preparation path as `create_model` but stops before JuMP model construction:

```julia
periods, sets, params = OpenEMPIRE.generate_scenarios(
    "config/testrun.yaml",
    "data/test";
    scenario_rng = MersenneTwister(1),
)
```

From the command line:

```powershell
julia --project=. scripts/run_julia_empire.jl `
  --dataset=test `
  --config=config/testrun.yaml `
  --format=csv `
  --seed=1 `
  --generate-only
```

Julia and Python use different random-number generators. Cross-language comparisons should therefore share a `sampling_key.csv`, then set `use_fixed_sample: true` in both implementations.

## Filters and copula clusters

Set `filter_make: true` to cluster possible regular-season load windows and write `ScenarioData/filter_result.csv`. Set `filter_use: true` to sample from that file. The `n_cluster` configuration controls the number of groups.

Set `copula_clusters_make: true` to create `Copulas/CopulaClusters/copula_clusters.csv`, and `copula_clusters_use: true` to sample from it. The supported copula variables include `electricload`, `hydroseasonal`, `solar`, `windonshore`, `windoffshore`, and `hydroror`.

When multiple sampling modes are enabled, fixed sampling takes precedence over filters, and filters take precedence over copula clusters. See [FILTER_COMPARISON.md](https://github.com/ntnuiotenergy/OpenEMPIRE.jl/blob/main/FILTER_COMPARISON.md) for parity details.

## One out-of-sample tree

```powershell
julia --project=. scripts/create_out_of_sample_tree.jl test `
  --config=config/testrun.yaml `
  --seed=101 `
  --output=OutOfSample/test/oos_tree1
```

The tree is prepared from a temporary dataset copy and is published only when all required scenario files are complete. Its `metadata.yaml` records configuration, seed, source paths, and file checksums.

## Multiple trees and execution queues

Prepare several deterministic trees:

```powershell
julia --project=. scripts/prepare_oos_experiment.jl test `
  --config=config/testrun.yaml `
  --num-trees=3 `
  --seed-start=101 `
  --output=OutOfSample/test/experiment_seed101_3trees
```

Then prepare and manage an execution queue using `prepare_oos_execution_queue.jl` and `manage_oos_execution_queue.jl`. Queue preparation validates tree checksums, fixed-investment provenance, and configuration compatibility without submitting jobs.

Run a tree with fixed investments using `run_julia_empire.jl --out-of-sample=true`, `--fixed-investment-dir`, and `--scenario-data-root`. Completed runs can be aggregated with:

```powershell
julia --project=. scripts/aggregate_out_of_sample_results.jl `
  results/julia_oos_runs/<experiment> `
  --output=results/julia_oos_aggregations/<experiment>
```

The aggregator checks manifests, feasibility, fixed capacities, staged configurations, and scenario checksums before writing summaries and combined operational CSV files.

## Full-year evaluation

`prepare_full_year_oos_experiment.jl` creates 24 chronological trees for a complete non-leap year. It validates that the source has exactly 8,760 ordered, gap-free rows and writes a full-year experiment manifest. Full-year OOS is an evaluation workflow; it does not rebuild the investment decision.
