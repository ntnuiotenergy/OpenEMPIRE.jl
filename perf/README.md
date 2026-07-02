# EMPIRE performance & RAM analysis

Tooling to compare the **peak memory** and runtime of the Julia (JuMP) port
against the Python (Pyomo) reference. Peak RAM is the headline metric: the large
`europe_v51` instances are memory-bound (~140 GB+), so memory decides which
problems can run at all and on which node.

Everything here is **opt-in** (`EMPIRE_PERF=1`) and additive — with the flag
unset, runs behave exactly as before and write no perf artifacts.

## Three layers of measurement

1. **External RSS sampler** — `scripts/perf/memwatch.py`. Wraps the run and polls
   the process-tree resident memory (`/proc` on Linux, `ps` fallback) at a fixed
   interval. Gurobi links in-process in *both* runtimes (gurobipy / Gurobi.jl),
   so the process-tree RSS captures solver memory too. This is the one peak-RAM
   number that is directly comparable across languages. Emits `mem.csv` (time
   series) and `mem_summary.json` (peak).

2. **In-process phase checkpoints** — written to `perf.json` next to each run's
   outputs, with the *same schema* on both sides:
   - Julia (`scripts/run_julia_empire.jl`): `@timed` around build/solve/results
     gives per-phase `alloc_bytes` (cumulative bytes allocated — *allocation
     pressure*, not footprint) and `gc_seconds`; `Sys.maxrss()` gives the peak
     RSS footprint; `gc_live_bytes()` the live heap.
   - Python (`empire/core/perf.py`): `resource.getrusage(...).ru_maxrss` gives the
     peak RSS at each phase (`data_read` → `create_instance` → `solve` →
     `results`). `tracemalloc` allocation accounting is opt-in via
     `EMPIRE_PERF_TRACEMALLOC=1` (it ~doubles allocator overhead — leave off for
     the large runs).

   > Why not just Julia `@time`? It reports *bytes allocated*, which for a build
   > that allocates and frees transient garbage is far larger than the resident
   > footprint. It measures allocation pressure, not peak RAM. We record both:
   > `@timed` for allocation/GC, `Sys.maxrss()` for the footprint that must fit
   > in node memory.

3. **Scheduler accounting** — `scripts/perf/collect_qacct.sh <JOB_ID>` captures
   SGE `qacct` (`maxvmem`, `ru_maxrss`, `cpu`, `wallclock`) into
   `logs/perf_<JOB_ID>.txt` as an independent cross-check of the sampler.

## Running on Solstorm (SGE)

Enable via env (local override) or `config/cluster.json` key `EMPIRE_PERF`:

```bash
# Julia
cd OpenEMPIRE.jl-testing
EMPIRE_PERF=1 ./scripts/copy_and_run_julia_on_hpc.sh Solstorm
# Python CSV
cd OpenEMPIRE-csv
EMPIRE_PERF=1 ./scripts/copy_and_run_empire_on_hpc.sh Solstorm
```

On the node this wraps the run in `memwatch.py` (→ `logs/perf_mem_<JOB_ID>.csv`
+ `.json`) and gates the in-process `perf.json`. After the job finishes:

```bash
sh scripts/perf/collect_qacct.sh <JOB_ID>     # → logs/perf_<JOB_ID>.txt
```

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

```bash
python OpenEMPIRE.jl-testing/scripts/perf/compare_perf.py \
    --julia  <julia_run_dir>   --python <python_output_dir> \
    --julia-log logs/julia_empire_<id>.out \
    --python-log logs/empire_<id>.out \
    --out perf/comparison_<id>.md  --plot perf/comparison_<id>.png
```

`--julia`/`--python` accept a run directory (auto-finds `perf.json`,
`mem_summary.json`, `mem.csv`) or a direct `perf.json`. The logs feed the
model-dimension parser (rows/cols/nonzeros, barrier iterations, work units). The
report covers peak RAM (in-process **and** sampler), wall time, a per-phase
breakdown, and model size; `--plot` overlays the RSS-vs-time traces (showing the
Pyomo `create_instance` spike vs the JuMP build, and the Gurobi barrier plateau).

## Fair-comparison methodology

- **Same** dataset / config / seed, and the **same Gurobi parameters** —
  `Method=2`, `Crossover=0`, `Presolve`, and a **pinned `solver_threads`**
  (thread count drives barrier memory; leave it equal on both sides).
- Same high-memory node class (`compute-4-5x`); same physical host where possible.
- Deterministic operational tie-break **off** for perf runs.
- Repeat N≈3 and report the median + spread.
- Report the **build-phase peak** (Pyomo `create_instance` / JuMP construction)
  separately from the **solve-phase peak** (Gurobi barrier factorisation) — that
  split is the headline insight: model construction is often the memory peak, not
  the solve.
- Note: Julia RSS is a high-water mark the GC may not return to the OS — report
  both `Sys.maxrss` (peak) and `gc_live_bytes` (live).
