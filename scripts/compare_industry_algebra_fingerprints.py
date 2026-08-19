#!/usr/bin/env python3
"""Fail-closed comparison of streaming Industry algebra fingerprints."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path

from industry_algebra_fingerprint import (
    ALL_ROW_FAMILIES,
    OBJECTIVE_GROUPS,
    VARIABLES,
)


def read_fingerprint(path: Path) -> dict[str, object]:
    metadata: dict[str, str] = {}
    excluded: dict[tuple[str, str], int] = {}
    summaries: dict[tuple[str, str, int], tuple[str, ...]] = {}
    buckets: dict[tuple[str, str, int, int], tuple[str, ...]] = {}
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "META" and len(fields) == 3:
                if fields[1] in metadata:
                    raise ValueError(f"duplicate metadata in {path}:{line_number}")
                metadata[fields[1]] = fields[2]
            elif fields[0] == "EXCLUDED" and len(fields) == 4:
                key = (fields[1], fields[2])
                if key in excluded:
                    raise ValueError(f"duplicate exclusion in {path}:{line_number}")
                excluded[key] = int(fields[3])
            elif fields[0] == "SUMMARY" and len(fields) == 14:
                key = (fields[1], fields[2], int(fields[3]))
                if key in summaries:
                    raise ValueError(f"duplicate summary in {path}:{line_number}: {key}")
                summaries[key] = tuple(fields[4:])
            elif fields[0] == "BUCKET" and len(fields) == 15:
                key = (fields[1], fields[2], int(fields[3]), int(fields[4]))
                if key in buckets:
                    raise ValueError(f"duplicate bucket in {path}:{line_number}: {key}")
                buckets[key] = tuple(fields[5:])
            else:
                raise ValueError(
                    f"malformed fingerprint line {path}:{line_number}: {fields[:5]}"
                )
    required_metadata = {"schema", "side", "scope", "precisions", "buckets"}
    missing = required_metadata - metadata.keys()
    if missing:
        raise ValueError(f"missing metadata in {path}: {sorted(missing)}")
    return {
        "metadata": metadata,
        "excluded": excluded,
        "summaries": summaries,
        "buckets": buckets,
    }


def required_groups() -> set[tuple[str, str]]:
    return (
        {("row", family) for family in ALL_ROW_FAMILIES}
        | {("variable", canonical) for canonical, _ in VARIABLES.values()}
        | {("objective", group) for group in OBJECTIVE_GROUPS.values()}
    )


def compare(
    internal_path: Path, julia_path: Path, precision: int
) -> tuple[list[str], dict[tuple[str, str], list[int]], dict[str, object], dict[str, object]]:
    internal = read_fingerprint(internal_path)
    julia = read_fingerprint(julia_path)
    failures: list[str] = []
    if internal["metadata"]["scope"] != "industry" or julia["metadata"]["scope"] != "industry":
        failures.append("both fingerprints must declare scope=industry")
    left = {
        (kind, group): value
        for (kind, group, candidate), value in internal["summaries"].items()
        if candidate == precision
    }
    right = {
        (kind, group): value
        for (kind, group, candidate), value in julia["summaries"].items()
        if candidate == precision
    }
    required = required_groups()
    missing = required - (set(left) & set(right))
    if missing:
        failures.append(f"missing required groups: {sorted(missing)}")
    extra = (set(left) | set(right)) - required
    if extra:
        failures.append(f"unexpected groups: {sorted(extra)}")
    for key in sorted(set(left) | set(right)):
        if left.get(key) != right.get(key):
            failures.append(
                f"{key[0]} {key[1]}: internal={left.get(key)} julia={right.get(key)}"
            )

    bucket_differences: dict[tuple[str, str], list[int]] = defaultdict(list)
    left_buckets = {
        (kind, group, bucket): value
        for (kind, group, candidate, bucket), value in internal["buckets"].items()
        if candidate == precision
    }
    right_buckets = {
        (kind, group, bucket): value
        for (kind, group, candidate, bucket), value in julia["buckets"].items()
        if candidate == precision
    }
    for key in set(left_buckets) | set(right_buckets):
        if left_buckets.get(key) != right_buckets.get(key):
            bucket_differences[key[:2]].append(key[2])
    return failures, bucket_differences, internal, julia


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("internal", type=Path)
    parser.add_argument("julia", type=Path)
    parser.add_argument("--precision", type=int, choices=(9, 12), default=12)
    args = parser.parse_args()
    failures, buckets, internal, julia = compare(
        args.internal, args.julia, args.precision
    )
    left = {
        (kind, group): value
        for (kind, group, precision), value in internal["summaries"].items()
        if precision == args.precision
    }
    right = {
        (kind, group): value
        for (kind, group, precision), value in julia["summaries"].items()
        if precision == args.precision
    }
    print(f"precision={args.precision}")
    print(f"groups_internal={len(left)} groups_julia={len(right)}")
    for key in sorted(set(left) & set(right)):
        status = "MATCH" if left[key] == right[key] else "DIFF"
        count, terms = left[key][:2]
        print(f"{key[0]:9s} {key[1]:30s} {status} records={count} terms={terms}")
        if status == "DIFF":
            localized = sorted(buckets.get(key, ()))
            print(f"  differing_buckets={len(localized)} sample={localized[:20]}")
    print("InternalEMPIRE documented exclusions:")
    for key, count in sorted(internal["excluded"].items()):
        print(f"  {key[0]} {key[1]}={count}")
    if failures:
        print("result=DIFF")
        for failure in failures[:60]:
            print(f"failure={failure}")
        return 1
    print("result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
