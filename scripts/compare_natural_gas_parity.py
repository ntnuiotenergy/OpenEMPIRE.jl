#!/usr/bin/env python3
"""Compare the controlled Julia and Pyomo natural-gas result tables."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


Key = tuple[str, int, str]


def read_results(path: Path) -> dict[Key, float]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    result: dict[Key, float] = {}
    for row in rows:
        key = (row["Metric"], int(row["Hour"]), row["Node"])
        if key in result:
            raise ValueError(f"{path}: duplicate result key {key}")
        result[key] = float(row["Value"])
    return result


def compare(
    julia_path: Path,
    python_path: Path,
    *,
    absolute_tolerance: float,
    relative_tolerance: float,
) -> None:
    julia = read_results(julia_path)
    python = read_results(python_path)
    if julia.keys() != python.keys():
        missing_julia = sorted(python.keys() - julia.keys())
        missing_python = sorted(julia.keys() - python.keys())
        raise AssertionError(
            f"Result-key mismatch; missing Julia={missing_julia}, "
            f"missing Python={missing_python}"
        )

    failures = []
    maximum_absolute = 0.0
    maximum_relative = 0.0
    for key in sorted(julia):
        julia_value = julia[key]
        python_value = python[key]
        absolute = abs(julia_value - python_value)
        scale = max(abs(julia_value), abs(python_value), absolute_tolerance)
        relative = absolute / scale
        maximum_absolute = max(maximum_absolute, absolute)
        maximum_relative = max(maximum_relative, relative)
        if not math.isclose(
            julia_value,
            python_value,
            abs_tol=absolute_tolerance,
            rel_tol=relative_tolerance,
        ):
            failures.append((key, julia_value, python_value, absolute, relative))

    print(f"Compared {len(julia)} natural-gas metrics")
    print(f"Maximum absolute difference: {maximum_absolute:.12g}")
    print(f"Maximum relative difference: {maximum_relative:.12g}")
    if failures:
        for failure in failures:
            print(
                "Mismatch "
                f"{failure[0]} Julia={failure[1]:.12g} "
                f"Python={failure[2]:.12g} "
                f"absolute={failure[3]:.12g} relative={failure[4]:.12g}"
            )
        raise AssertionError(f"{len(failures)} parity metrics exceeded tolerance")
    print("Natural-gas Julia/Pyomo parity: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("julia_output", type=Path)
    parser.add_argument("python_output", type=Path)
    parser.add_argument("--absolute-tolerance", type=float, default=1.0e-8)
    parser.add_argument("--relative-tolerance", type=float, default=1.0e-9)
    args = parser.parse_args()
    compare(
        args.julia_output,
        args.python_output,
        absolute_tolerance=args.absolute_tolerance,
        relative_tolerance=args.relative_tolerance,
    )


if __name__ == "__main__":
    main()
