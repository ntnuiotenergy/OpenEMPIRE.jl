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

The runner also prints counts for every named JuMP constraint family. This
localizes model-size differences without requiring performance reporting to be
enabled.

For fair comparisons, use the same dataset, scenario key, configuration, solver
settings, thread count, and machine. Report model-build and solve behavior
separately because either phase can determine peak memory.
