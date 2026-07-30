#!/usr/bin/env python3
"""Side-by-side performance/RAM comparison of a Julia and a Python EMPIRE run.

Reads the ``perf.json`` produced in-process by each runtime (and, when present,
the external ``memwatch.py`` sampler's ``mem_summary.json`` / ``mem.csv`` and the
Gurobi model dimensions parsed from a run log) and prints a comparison table.
Optionally overlays the RSS-vs-time traces.

Usage:
    python compare_perf.py --julia <run_dir|perf.json> --python <run_dir|perf.json>
        [--julia-log logs/julia_empire_6253.out] [--python-log logs/empire_6234.out]
        [--out perf/comparison.md] [--plot perf/comparison.png]

A *run_dir* is searched for ``perf.json``, ``mem_summary.json`` and ``mem.csv``.
Pure standard library; matplotlib is only needed for ``--plot``.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

GIB = 1024 ** 3


def _gib(n):
    return None if n is None else round(n / GIB, 3)


def _fmt_gib(n):
    return "-" if n is None else f"{n / GIB:.3f}"


def _fmt(n):
    return "-" if n is None else (f"{n:.1f}" if isinstance(n, float) else str(n))


def _resolve(path, name):
    """Return path if it is a file, else <path>/<name> if that exists, else None."""
    if path is None:
        return None
    if os.path.isfile(path):
        return path
    cand = os.path.join(path, name)
    return cand if os.path.isfile(cand) else None


def _load_json(path):
    if path is None:
        return None
    with open(path) as fh:
        return json.load(fh)


def _parse_gurobi_log(path):
    """Pull model dimensions and barrier stats from a Gurobi run log."""
    if path is None or not os.path.isfile(path):
        return {}
    info = {}
    with open(path, errors="replace") as fh:
        text = fh.read()
    m = re.search(r"Optimize a model with ([\d,]+) rows, ([\d,]+) columns and ([\d,]+) nonzeros", text)
    if m:
        info["rows"], info["cols"], info["nonzeros"] = (int(g.replace(",", "")) for g in m.groups())
    m = re.search(r"Presolved: ([\d,]+) rows, ([\d,]+) columns, ([\d,]+) nonzeros", text)
    if m:
        info["presolved_rows"], info["presolved_cols"], info["presolved_nonzeros"] = (
            int(g.replace(",", "")) for g in m.groups()
        )
    m = re.search(r"Barrier solved model in (\d+) iterations", text)
    if m:
        info["barrier_iters"] = int(m.group(1))
    m = re.search(r"\(([\d.]+) work units\)", text)
    if m:
        info["work_units"] = float(m.group(1))
    return info


def _load_run(arg, log_arg, mem_arg=None):
    """Bundle one run's artifacts into a dict.

    ``mem_arg`` (the sampler's mem_summary.json) overrides auto-discovery — needed
    for the SGE layout where mem.csv/json land in logs/ rather than the run dir.
    The matching time-series CSV is the same stem with a .csv extension.
    """
    perf_path = _resolve(arg, "perf.json")
    run_dir = arg if (arg and os.path.isdir(arg)) else (os.path.dirname(perf_path) if perf_path else None)
    perf = _load_json(perf_path) or {}

    if mem_arg:
        mem_summary_path = mem_arg
        mem_csv = os.path.splitext(mem_arg)[0] + ".csv"
        mem_csv = mem_csv if os.path.isfile(mem_csv) else None
    else:
        mem_summary_path = _resolve(run_dir, "mem_summary.json")
        mem_csv = _resolve(run_dir, "mem.csv")

    return {
        "perf": perf,
        "mem_summary": _load_json(mem_summary_path) or {},
        "mem_csv": mem_csv,
        "log": _parse_gurobi_log(log_arg),
        "label": perf.get("runtime") or os.path.basename(str(arg)),
    }


def _phase_map(perf):
    return {p["name"]: p for p in perf.get("phases", [])}


def _row(metric, jv, pv):
    return f"| {metric} | {jv} | {pv} |"


def build_report(j, p):
    jp, pp = j["perf"], p["perf"]
    jm, pm = j["mem_summary"], p["mem_summary"]
    jl, pl = j["log"], p["log"]
    jph, pph = _phase_map(jp), _phase_map(pp)

    lines = []
    lines.append("# EMPIRE performance comparison — Julia vs Python\n")
    lines.append("| Metric | Julia | Python |")
    lines.append("| --- | --- | --- |")
    lines.append(_row("host", jp.get("host", "-"), pp.get("host", "-")))
    lines.append(_row("dataset", jp.get("dataset", "-"), pp.get("dataset", "-")))
    lines.append(_row("solver threads", jp.get("solver_threads", "-"), pp.get("solver_threads", "-")))
    lines.append(_row("objective", jp.get("objective_value", "-"), pp.get("objective_value", "-")))
    lines.append("")
    lines.append("## Peak RAM (the headline)\n")
    lines.append("| Source | Julia | Python |")
    lines.append("| --- | --- | --- |")
    lines.append(_row(
        "in-process peak RSS (GiB)",
        _fmt_gib(jp.get("totals", {}).get("peak_rss_bytes")),
        _fmt_gib(pp.get("totals", {}).get("peak_rss_bytes")),
    ))
    lines.append(_row(
        "external sampler peak RSS (GiB)",
        _fmt_gib(jm.get("peak_rss_bytes")),
        _fmt_gib(pm.get("peak_rss_bytes")),
    ))
    lines.append("")
    lines.append("## Wall time\n")
    lines.append("| Metric | Julia | Python |")
    lines.append("| --- | --- | --- |")
    lines.append(_row(
        "total wall (s)",
        _fmt(jp.get("totals", {}).get("wall_seconds")),
        _fmt(pp.get("totals", {}).get("wall_seconds")),
    ))
    lines.append("")
    lines.append("## Per-phase (wall s / peak RSS GiB / alloc GiB)\n")
    lines.append("| Phase | Julia wall | Julia RSS | Julia alloc | Python wall | Python RSS | Python alloc |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for name in ("data_read", "build", "create_instance", "solve", "results"):
        jx, px = jph.get(name), pph.get(name)
        if not jx and not px:
            continue
        lines.append(
            f"| {name} "
            f"| {_fmt((jx or {}).get('wall_seconds'))} | {_fmt_gib((jx or {}).get('rss_peak_bytes'))} | {_fmt_gib((jx or {}).get('alloc_bytes'))} "
            f"| {_fmt((px or {}).get('wall_seconds'))} | {_fmt_gib((px or {}).get('rss_peak_bytes'))} | {_fmt_gib((px or {}).get('alloc_bytes'))} |"
        )
    lines.append("")
    lines.append("## Model size (from Gurobi log)\n")
    lines.append("| Metric | Julia | Python |")
    lines.append("| --- | --- | --- |")
    for key in ("rows", "cols", "nonzeros", "presolved_rows", "presolved_cols", "presolved_nonzeros", "barrier_iters", "work_units"):
        lines.append(_row(key, jl.get(key, "-"), pl.get(key, "-")))
    lines.append("")
    return "\n".join(lines)


def _read_mem_csv(path):
    xs, ys = [], []
    with open(path) as fh:
        next(fh, None)
        for line in fh:
            parts = line.strip().split(",")
            if len(parts) >= 2:
                try:
                    xs.append(float(parts[0]))
                    ys.append(int(parts[1]) / GIB)
                except ValueError:
                    continue
    return xs, ys


def make_plot(j, p, out):
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not available; skipping --plot", file=sys.stderr)
        return
    plt.figure(figsize=(9, 5))
    for run, color in ((j, "tab:blue"), (p, "tab:red")):
        if run["mem_csv"]:
            xs, ys = _read_mem_csv(run["mem_csv"])
            if xs:
                plt.plot(xs, ys, label=run["perf"].get("runtime", run["label"]), color=color)
    plt.xlabel("elapsed (s)")
    plt.ylabel("process RSS (GiB)")
    plt.title("EMPIRE memory profile: Julia vs Python")
    plt.legend()
    plt.grid(True, alpha=0.3)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    plt.savefig(out, dpi=120, bbox_inches="tight")
    print(f"Wrote plot {out}", file=sys.stderr)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--julia", required=True, help="Julia run dir or perf.json")
    ap.add_argument("--python", required=True, help="Python run dir or perf.json")
    ap.add_argument("--julia-log", default=None, help="Julia Gurobi log for model dims")
    ap.add_argument("--python-log", default=None, help="Python Gurobi log for model dims")
    ap.add_argument("--julia-mem", default=None, help="Julia sampler mem_summary.json (e.g. logs/perf_mem_<id>.json)")
    ap.add_argument("--python-mem", default=None, help="Python sampler mem_summary.json (e.g. logs/perf_mem_<id>.json)")
    ap.add_argument("--out", default=None, help="Write the markdown report here")
    ap.add_argument("--plot", default=None, help="Write an RSS-vs-time overlay PNG here")
    args = ap.parse_args(argv)

    j = _load_run(args.julia, args.julia_log, args.julia_mem)
    p = _load_run(args.python, args.python_log, args.python_mem)
    report = build_report(j, p)
    print(report)

    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w") as fh:
            fh.write(report + "\n")
        print(f"\nWrote report {args.out}", file=sys.stderr)
    if args.plot:
        make_plot(j, p, args.plot)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
