#!/usr/bin/env python3
"""Compare controlled Julia/Pyomo Industry solution metrics."""
import argparse
import csv
import math
from pathlib import Path


def read(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    result = {}
    for row in rows:
        key = (row["Metric"], int(row["Hour"]), row["Technology"])
        if key in result:
            raise ValueError(f"{path}: duplicate metric key {key}")
        value = float(row["Value"])
        if not math.isfinite(value):
            raise ValueError(f"{path}: non-finite value for {key}: {value}")
        result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("julia_csv", type=Path)
    parser.add_argument("python_csv", type=Path)
    args = parser.parse_args()
    julia = read(args.julia_csv)
    python = read(args.python_csv)
    if not julia or not python:
        raise ValueError("non-empty parity outputs are required")
    unmatched = set(julia) ^ set(python)
    failures = []
    for key in set(julia) & set(python):
        if not math.isclose(julia[key], python[key], rel_tol=1e-7, abs_tol=1e-7):
            failures.append((key, julia[key], python[key]))
    if unmatched:
        print(f"unmatched metrics: {len(unmatched)}")
    if failures:
        print(f"numeric differences: {len(failures)}")
        for failure in failures[:20]:
            print(" ", failure)
    compared = len(set(julia) & set(python))
    print(f"Industry solution metrics compared: {compared}")
    if unmatched or failures:
        return 1
    print("INDUSTRY SOLUTION PARITY PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
