#!/usr/bin/env python3
"""Dependency-free semantic negative controls for the Industry dataset validator."""
from __future__ import annotations

import csv
import os
import shutil
import tempfile
from pathlib import Path

import validate_full_model_int_dataset as validator


def mutate_csv(path: Path, mutator) -> None:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
        fields = list(rows[0])
    mutator(fields, rows)
    path.unlink()
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def expect_failure(dataset: Path, base_manifest, needle: str) -> None:
    try:
        validator.validate_industry_tables(dataset, base_manifest)
    except (ValueError, SystemExit) as error:
        if needle.lower() not in str(error).lower():
            raise AssertionError(f"expected {needle!r}, got {error!r}") from error
    else:
        raise AssertionError(f"Industry validator accepted case requiring {needle!r}")


def case(source: Path, base_manifest, relative: str, mutator, needle: str) -> None:
    with tempfile.TemporaryDirectory(prefix="industry-validator-") as tmp:
        target = Path(tmp) / "full_model_int"
        shutil.copytree(source, target, copy_function=os.link)
        mutate_csv(target / relative, mutator)
        expect_failure(target, base_manifest, needle)


def main() -> None:
    source = Path(__file__).resolve().parents[1] / "data" / "full_model_int"
    base_manifest = validator.validate_manifest(source)
    validator.validate_industry_tables(source, base_manifest)
    industry_manifest = validator.validate_industry_manifest(source)
    # These controls target table semantics after provenance/hash validation.
    validator.validate_industry_manifest = lambda _dataset: industry_manifest
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: rows.append(dict(rows[0])), "duplicate key",
    )
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: rows.pop(), "incomplete or unexpected keys",
    )
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: rows[0].update({"Period": "1.5"}), "must be an integer",
    )
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: rows[0].update({"InvCost_(eur/(t/h)_crude_steel)": "NaN"}),
        "must be finite",
    )
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: rows[0].update({"InvCost_(eur/(t/h)_crude_steel)": "-1"}),
        "non-negative",
    )
    case(
        source, base_manifest, "Industry/SteelInvCost.csv",
        lambda fields, rows: (
            fields.remove("Period"),
            [row.pop("Period") for row in rows],
        ),
        "expected schema",
    )
    case(
        source, base_manifest, "Sets/SteelProducers.csv",
        lambda fields, rows: rows[0].update({"SteelProducers": "UnknownNode"}),
        "unknown steel producer",
    )
    print("industry dataset validator negative controls: PASS")


if __name__ == "__main__":
    main()
