#!/usr/bin/env python3
"""Convert InternalEMPIRE strategic-capacity tabs to Julia result CSVs.

This is a diagnostic bridge for cross-fixing an InternalEMPIRE investment plan in
OpenEMPIRE.jl. It does not compare or alter operational dispatch.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


FILES = (
    "genInvCap",
    "genInstalledCap",
    "transmissionInvCap",
    "transmissionInstalledCap",
    "storPWInvCap",
    "storPWInstalledCap",
    "storENInvCap",
    "storENInstalledCap",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("internal_results", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    for stem in FILES:
        source = args.internal_results / f"{stem}.tab"
        target = args.output / f"{stem}.csv"
        with source.open(newline="") as source_stream, target.open(
            "w", newline=""
        ) as target_stream:
            rows = csv.reader(source_stream, delimiter="\t")
            writer = csv.writer(target_stream)
            header = next(rows)
            writer.writerow(header)
            for row in rows:
                if stem.startswith("transmission") and row[1] < row[0]:
                    row[0], row[1] = row[1], row[0]
                writer.writerow(row)
        print(f"{source} -> {target}")


if __name__ == "__main__":
    main()
