# Julia Performance and Memory Instrumentation

The Julia runner has opt-in phase timing and memory reporting for comparable
OpenEMPIRE runs. Default runs are unchanged and do not write a performance
artifact.

Enable reporting with:

```sh
EMPIRE_PERF=1 julia --project=. scripts/run_julia_empire.jl \
  --dataset=test \
  --config=config/testrun.yaml \
  --solver=HiGHS
```

The runner writes `perf.json` beside the normal run summary. It records:

- Julia, JuMP, and Gurobi.jl versions;
- solver and solver attributes;
- model variable and constraint counts;
- build, solve, and result-writing wall time;
- Julia allocation traffic and garbage-collection time per phase;
- process peak resident memory from `Sys.maxrss()`;
- current Julia live heap size at each phase boundary;
- objective value and termination status.

`alloc_bytes` is cumulative allocation traffic, not peak memory. Use
`rss_peak_bytes` for the process high-water mark. The latter includes an
in-process solver such as HiGHS or Gurobi.

## Launching matched Julia/Python runs

Use the comparison runner when the goal is a fair same-dataset, same-config,
same-sampling-key Julia/Python launch:

```bash
scripts/run_python_julia_comparison.sh \
    --dataset test \
    --config config/testrun.yaml \
    --generate-key \
    --perf
```

The script validates both repos, installs the same `sampling_key.csv` into the
Julia `data/<dataset>/ScenarioData/` folder and Python
`input_data/<dataset>/ScenarioData/` folder, writes a manifest under
`results/comparison_runs/`, and then calls the existing copy/submit launchers.

The two ports' config files are never byte-identical (different headers, the
Julia `solver_*` block, the `use_fixed_sample` flag), so the runner does **not**
compare checksums. Instead it checks that the **model-relevant keys** agree
(`forecast_horizon_year`, `number_of_scenarios`, `length_of_regular_season`,
`discount_rate`, `wacc`, `use_emission_cap`, `leap_years_investment`,
`north_sea`, `time_format`) and fails on a difference unless
`--allow-config-mismatch`. Solver settings (`solver_method`, `solver_crossover`,
`solver_presolve`, `solver_threads`, `optimization_solver`) are reported as a
**warning**, not a hard failure, because the Python reference may source Gurobi
parameters outside its YAML — verify these match by hand for a fair run.

**`config/cluster.json` is the source of truth for what runs remotely.** The
comparison runner's `--dataset`/`--config` install the sampling key and validate
paths, but the actual dataset, config, and solver on the remote side come from
each repo's `SCHEDULER_SCRIPT`, not from this script. So make each
`SCHEDULER_SCRIPT` pass the intended dataset and config **explicitly** (do not
rely on the SGE script defaults — the runner checks that both appear). The Python
scheduler command must include `USE_FIXED_SAMPLE=true` and must **not** be a
test run (`--test-run`/`TEST_RUN=true`); the runner fails early on either, so it
does not accidentally launch a Python run with regenerated scenarios or a tiny
test instance. The written manifest records both repos' git commit, both
`SCHEDULER_SCRIPT` strings, the config-parity result, and any solver
differences, so a comparison is reproducible after the fact.

## Comparing two runs

The runner also prints counts for every named JuMP constraint family. This
localizes model-size differences without requiring performance reporting to be
enabled.

For fair comparisons, use the same dataset, scenario key, configuration, solver
settings, thread count, and machine. Report model-build and solve behavior
separately because either phase can determine peak memory.
