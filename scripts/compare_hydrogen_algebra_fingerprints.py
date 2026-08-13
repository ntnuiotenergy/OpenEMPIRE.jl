#!/usr/bin/env python3
"""Compare canonical streaming Hydrogen/CO2 algebra fingerprints fail-closed."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path

from hydrogen_algebra_fingerprint import FAMILIES, HYDROGEN_GENERATORS, OBJECTIVE_GROUPS


def read_fingerprint(path: Path) -> dict[str, object]:
    metadata: dict[str, str] = {}
    excluded: dict[tuple[str, str], int] = {}
    summaries: dict[tuple[str, str, int], tuple[str, ...]] = {}
    buckets: dict[tuple[str, str, int, int], tuple[str, ...]] = {}
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "META" and len(fields) == 3:
                metadata[fields[1]] = fields[2]
            elif fields[0] == "EXCLUDED" and len(fields) == 4:
                excluded[(fields[1], fields[2])] = int(fields[3])
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
                raise ValueError(f"malformed fingerprint line {path}:{line_number}: {fields[:5]}")
    return {
        "metadata": metadata,
        "excluded": excluded,
        "summaries": summaries,
        "buckets": buckets,
    }


def required_groups() -> set[tuple[str, str]]:
    objectives = set(OBJECTIVE_GROUPS.values()) | {
        f"generation_{generator}" for generator in HYDROGEN_GENERATORS
    }
    return (
        {("row", family) for family in FAMILIES}
        | {("objective", group) for group in objectives}
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("internal", type=Path)
    parser.add_argument("julia", type=Path)
    parser.add_argument("--precision", type=int, choices=(9, 12), default=12)
    args = parser.parse_args()

    internal = read_fingerprint(args.internal)
    julia = read_fingerprint(args.julia)
    precision = args.precision
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
    missing_required = required_groups() - (set(left) & set(right))
    failures: list[str] = []
    if missing_required:
        failures.append(f"missing required groups: {sorted(missing_required)}")

    differing_groups = []
    for key in sorted(set(left) | set(right)):
        if left.get(key) != right.get(key):
            differing_groups.append(key)
            failures.append(
                f"{key[0]} {key[1]}: internal={left.get(key)} julia={right.get(key)}"
            )

    bucket_differences: dict[tuple[str, str], list[int]] = defaultdict(list)
    internal_buckets = {
        (kind, group, bucket): value
        for (kind, group, candidate, bucket), value in internal["buckets"].items()
        if candidate == precision
    }
    julia_buckets = {
        (kind, group, bucket): value
        for (kind, group, candidate, bucket), value in julia["buckets"].items()
        if candidate == precision
    }
    for key in set(internal_buckets) | set(julia_buckets):
        if internal_buckets.get(key) != julia_buckets.get(key):
            bucket_differences[key[:2]].append(key[2])

    print(f"precision={precision}")
    print(f"internal_side={internal['metadata'].get('side')}")
    print(f"julia_side={julia['metadata'].get('side')}")
    print(f"groups_internal={len(left)} groups_julia={len(right)}")
    for key in sorted(set(left) & set(right)):
        status = "MATCH" if left[key] == right[key] else "DIFF"
        count, terms = left[key][:2]
        print(f"{key[0]:9s} {key[1]:34s} {status} records={count} terms={terms}")
        if status == "DIFF":
            buckets = sorted(bucket_differences.get(key, ()))
            print(f"  differing_buckets={len(buckets)} sample={buckets[:20]}")

    print("InternalEMPIRE documented exclusions:")
    for key, count in sorted(internal["excluded"].items()):
        print(f"  {key[0]} {key[1]}={count}")

    if failures:
        print("result=DIFF")
        for failure in failures[:40]:
            print(f"failure={failure}")
        return 1
    print("result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
