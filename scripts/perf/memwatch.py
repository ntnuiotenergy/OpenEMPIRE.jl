#!/usr/bin/env python3
"""External, language-agnostic RSS sampler for EMPIRE performance runs.

Wraps an arbitrary command, samples the resident memory of the launched process
*and its descendants* at a fixed interval, and writes a time series CSV plus a
summary JSON. Gurobi links in-process in both runtimes (gurobipy / Gurobi.jl),
so the process-tree RSS captures solver memory too — this is the one peak-RAM
number that is directly comparable between the Julia and Python ports.

Pure standard library (no psutil); primary path reads ``/proc`` on Linux
(Solstorm), with a portable ``ps`` fallback so the tooling can be smoke-tested
on macOS.

Usage:
    python scripts/perf/memwatch.py \
        --interval 0.25 --out run/mem.csv --summary run/mem_summary.json \
        --label julia-2045-3sce -- julia --project=. scripts/run_julia_empire.jl ...

The wrapped command's exit code is propagated.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
import time

_HAVE_PROC = os.path.isdir("/proc")


def _parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    if "--" not in argv:
        sys.exit("memwatch.py: missing '--' separator before the wrapped command")
    split = argv.index("--")
    own, command = argv[:split], argv[split + 1 :]
    if not command:
        sys.exit("memwatch.py: no command given after '--'")

    parser = argparse.ArgumentParser(description="Sample RSS of a wrapped command.")
    parser.add_argument("--interval", type=float, default=0.25, help="Sample interval in seconds (default 0.25).")
    parser.add_argument("--out", default=None, help="Time-series CSV output path.")
    parser.add_argument("--summary", default=None, help="Summary JSON output path.")
    parser.add_argument("--label", default=None, help="Free-text label stored in the summary.")
    return parser.parse_args(own), command


def _descendant_pids(root: int) -> list[int]:
    """Return root plus all transitive children, via a single ``ps`` snapshot."""
    try:
        out = subprocess.run(
            ["ps", "-eo", "pid=,ppid="], capture_output=True, text=True, check=True
        ).stdout
    except (subprocess.SubprocessError, FileNotFoundError):
        return [root]

    children: dict[int, list[int]] = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            pid, ppid = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        children.setdefault(ppid, []).append(pid)

    seen, stack = [], [root]
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.append(pid)
        stack.extend(children.get(pid, []))
    return seen


def _rss_bytes_proc(pid: int) -> int:
    """Instantaneous RSS for one pid from /proc, in bytes (0 if gone)."""
    try:
        with open(f"/proc/{pid}/status", "r") as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1]) * 1024
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        pass
    return 0


def _rss_bytes_ps(pids: list[int]) -> int:
    """Summed RSS for pids via ``ps`` (KB → bytes); portable fallback."""
    if not pids:
        return 0
    try:
        out = subprocess.run(
            ["ps", "-o", "rss=", "-p", ",".join(str(p) for p in pids)],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
    except (subprocess.SubprocessError, FileNotFoundError):
        return 0
    total = 0
    for line in out.split():
        try:
            total += int(line) * 1024
        except ValueError:
            continue
    return total


def _sample_tree(root: int) -> int:
    """Summed RSS (bytes) of the process tree rooted at ``root``."""
    pids = _descendant_pids(root)
    if _HAVE_PROC:
        return sum(_rss_bytes_proc(p) for p in pids)
    return _rss_bytes_ps(pids)


def main(argv: list[str]) -> int:
    args, command = _parse_args(argv)

    for path in (args.out, args.summary):
        if path:
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)

    csv_fh = open(args.out, "w") if args.out else None
    if csv_fh:
        csv_fh.write("elapsed_s,rss_bytes\n")

    start = time.time()
    proc = subprocess.Popen(command)

    peak_rss = 0
    peak_at = 0.0
    n_samples = 0
    try:
        while proc.poll() is None:
            elapsed = time.time() - start
            rss = _sample_tree(proc.pid)
            n_samples += 1
            if rss > peak_rss:
                peak_rss, peak_at = rss, elapsed
            if csv_fh:
                csv_fh.write(f"{elapsed:.3f},{rss}\n")
                csv_fh.flush()
            time.sleep(args.interval)
    except KeyboardInterrupt:
        proc.terminate()
        proc.wait()
    finally:
        if csv_fh:
            csv_fh.close()

    returncode = proc.wait()
    wall = time.time() - start

    summary = {
        "label": args.label,
        "command": command,
        "returncode": returncode,
        "platform": platform.platform(),
        "sampler": "proc" if _HAVE_PROC else "ps",
        "interval_s": args.interval,
        "n_samples": n_samples,
        "wall_seconds": round(wall, 3),
        "peak_rss_bytes": peak_rss,
        "peak_rss_gib": round(peak_rss / 1024**3, 4),
        "peak_at_elapsed_s": round(peak_at, 3),
    }
    if args.summary:
        with open(args.summary, "w") as fh:
            json.dump(summary, fh, indent=2)
            fh.write("\n")

    print(
        f"[memwatch] peak RSS {summary['peak_rss_gib']} GiB at +{summary['peak_at_elapsed_s']}s "
        f"over {wall:.1f}s ({n_samples} samples, {summary['sampler']}); exit {returncode}",
        file=sys.stderr,
    )
    return returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
