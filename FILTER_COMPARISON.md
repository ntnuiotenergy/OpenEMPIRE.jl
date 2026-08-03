# Python–Julia Scenario Filter Comparison

This comparison uses the `europe_v51` electric-load input, 168-hour regular
seasons, and seed 1. The Python and Julia input files were byte-identical.

Both implementations generated the same 40,444 candidate keys
(`Year,Season,SampleIndex`). The largest absolute metric differences were:

- Wasserstein distance (`Value`): `3.49e-10`;
- candidate-window mean load (`Value2`): `6.98e-10`.

These are floating-point rounding differences. Cluster numbers themselves are
not compared because K-means labels have no intrinsic ordering. Adjusted Rand
index (ARI) compares the resulting partitions independently of those labels.
The objective ratio below is Julia's within-cluster sum of squares divided by
Python's; a value of 1 means equal K-means compactness.

| Clusters | Mean ARI | Minimum seasonal ARI | Mean NMI | Julia/Python objective |
|---:|---:|---:|---:|---:|
| 1  | 1.0000 | 1.0000 | 1.0000 | 1.000000 |
| 2  | 0.9996 | 0.9984 | 0.9988 | 1.000000 |
| 3  | 0.9996 | 0.9991 | 0.9989 | 1.000000 |
| 5  | 0.9990 | 0.9975 | 0.9981 | 0.999999 |
| 8  | 0.9933 | 0.9877 | 0.9910 | 0.999967 |
| 10 | 0.9934 | 0.9854 | 0.9917 | 0.999974 |
| 15 | 0.9893 | 0.9837 | 0.9886 | 0.999775 |
| 20 | 0.9519 | 0.9181 | 0.9680 | 0.999816 |
| 25 | 0.8705 | 0.8086 | 0.9337 | 0.999164 |
| 30 | 0.8737 | 0.7947 | 0.9358 | 1.000095 |

All four seasons contained exactly the requested number of non-empty clusters
for every tested value. The lower high-cluster ARI reflects alternative
near-equal K-means optima: even at 25 clusters, the objective difference is
less than 0.1%. The default of 10 clusters has high partition agreement without
the additional ambiguity and runtime of the largest values.

## Reproduce Python output

Run from an `OpenEMPIRE.jl` checkout with the sibling Python repository at
`../OpenEMPIRE-csv`:

```sh
mkdir -p results/filter_comparison/python
env MPLBACKEND=Agg PYTHONPATH='../OpenEMPIRE-csv' \
  ../OpenEMPIRE-csv/.venv/bin/python -c 'from pathlib import Path
import numpy as np
import pandas as pd
from empire.core.scenario_random import make_filter_result
from empire.core.scenario_utils import make_datetime
np.random.seed(1)
source = Path("../OpenEMPIRE-csv/input_data/europe_v51/ScenarioData/electricload.csv")
output = Path("results/filter_comparison/python")
data = make_datetime(pd.read_csv(source), "%d/%m/%Y %H:%M")
make_filter_result(data, data, 168, ["winter", "spring", "summer", "fall"], 10, output)
print(output / "filter_result.csv")'
```

## Reproduce Julia output

```sh
mkdir -p results/filter_comparison/julia
julia --project=. -e 'using CSV, OpenEMPIRE, Random
source = joinpath(pwd(), "data", "europe_v51", "ScenarioData", "electricload.csv")
output = joinpath(pwd(), "results", "filter_comparison", "julia", "filter_result.csv")
table = OpenEMPIRE._read_raw_scenario_table(
    source,
    OpenEMPIRE._python_dateformat("%d/%m/%Y %H:%M"),
)
seasons = ("winter", "spring", "summer", "fall")
sample_years = sort!(unique(table.years))
metrics = OpenEMPIRE._filter_metric_rows(table, seasons, 168, sample_years)
rows = OpenEMPIRE._cluster_filter_rows(metrics, seasons, 10, MersenneTwister(1))
CSV.write(output, rows)
println(output)'
```

The focused filter tests import and call Python's real `make_ws` and
`make_mean` functions when the sibling repository and its dependencies are
available:

```sh
julia --project=. -e '
using CSV, HiGHS, OpenEMPIRE, Dates, JuMP, Random, Test, TimeStruct, YAML
include("test/test_csv.jl")
include("test/test_scenario_csv.jl")
@testset "Scenario filter focused" begin
    test_scenario_filter_metrics_and_clustering()
    test_scenario_filter_make_and_use()
    test_scenario_filter_defaults()
end
'
```

The complete Julia suite is:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Generate and use the filter normally

Set these public configuration keys:

```yaml
use_scenario_generation: true
use_fixed_sample: false
filter_make: true
filter_use: true
n_cluster: 10
```

Then run:

```sh
julia --project=. scripts/run_julia_empire.jl \
  --dataset=europe_v51 \
  --config=config/run_2060.yaml \
  --format=csv \
  --solver=none \
  --seed=1 \
  --generate-only
```

The generated catalog is written to
`data/europe_v51/ScenarioData/filter_result.csv`. A normal model run with
filtering enabled archives the exact catalog under
`results/julia_runs/<run>/Input/ScenarioData/filter_result.csv`.
