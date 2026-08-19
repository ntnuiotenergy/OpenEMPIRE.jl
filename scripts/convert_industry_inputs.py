#!/usr/bin/env python3
"""Convert the deterministic Industry inputs required by OpenEMPIRE.jl.

The InternalEMPIRE source workbooks are treated as read-only. Outputs extend an
existing full_model_int CSV dataset and are described by a separate deterministic
manifest. Sparse Pyomo default-zero capacity grids are materialized explicitly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
from pathlib import Path

import pandas as pd

from convert_internalempire_xlsx import finalize, read_sheet, select_table, write_csv


HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
WORKSPACE = REPOSITORY.parent
DEFAULT_SOURCE = WORKSPACE / "InternalEMPIRE" / "Data handler" / "full_model_int"

INDUSTRY_TABLES = {
    "ShedCost": [0],
    "Steel_PlantLifetime": [0, 1],
    "Steel_InitialCapacity": [0, 1, 2],
    "Steel_ScaleFactorInitialCap": [0, 1, 2],
    "Steel_InvCost": [0, 1, 2],
    "Steel_FixedOM": [0, 1, 2],
    "Steel_VarOpex": [0, 1, 2],
    "Steel_CoalConsumption": [0, 1, 2],
    "Steel_HydrogenConsumption": [0, 1, 2],
    "Steel_BioConsumption": [0, 1, 2],
    "Steel_OilConsumption": [0, 1, 2],
    "Steel_ElConsumption": [0, 1, 2],
    "Steel_CO2Emissions": [0, 1],
    "Steel_CO2Captured": [0, 1],
    "Steel_YearlyProduction": [0, 1, 2],
    "Cement_PlantLifetime": [0, 1],
    "Cement_InitialCapacity": [0, 1, 2],
    "Cement_ScaleFactorInitialCap": [0, 1, 2],
    "Cement_InvCost": [0, 1, 2],
    "Cement_FixedOM": [0, 1, 2],
    "Cement_FuelConsumption": [0, 1, 2],
    "Cement_CO2CaptureRate": [0, 1],
    "Cement_ElConsumption": [0, 1, 2],
    "Cement_YearlyProduction": [0, 1],
    "Ammonia_PlantLifetime": [0, 1],
    "Ammonia_InitialCapacity": [0, 1, 2],
    "Ammonia_ScaleFactorInitialCap": [0, 1, 2],
    "Ammonia_InvCost": [0, 1, 2],
    "Ammonia_FixedOM": [0, 1, 2],
    "Ammonia_FeedstockConsumption": [0, 1],
    "Ammonia_ElConsumption": [0, 1],
    "Ammonia_YearlyProduction": [0, 1, 2],
    "Refinery_HydrogenConsumption": [0],
    "Refinery_HeatConsumption": [0],
    "Refinery_YearlyProduction": [0, 1, 2],
}

SET_SHEETS = {
    "Steel_Plants": "SteelPlants",
    "Cement_Plants": "CementPlants",
    "Ammonia_Plants": "AmmoniaPlants",
}

PRODUCER_SHEETS = {
    "SteelProducers": "SteelProducers",
    "CementProducers": "CementProducers",
    "AmmoniaProducers": "AmmoniaProducers",
    "OilProducers": "OilProducers",
}

OUTPUT_NAMES = {
    name: name.replace("_", "") for name in INDUSTRY_TABLES
}

CONSTANTS = (
    ("ramp_fraction_per_hour", 0.1, "fraction/hour", "empire.py hard-coded"),
    ("maximum_scrap_share", 0.45, "fraction", "empire.py hard-coded"),
    ("hours_per_year", 8760.0, "hour/year", "empire.py hard-coded"),
    ("oil_shed_cost", 1_000_000.0, "EUR/kbbl", "empire.py hard-coded"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_value(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", repo, *args], text=True).strip()


def verify_sources(source: Path) -> dict[str, object]:
    repo = source.parents[1]
    names = ("Industry.xlsx", "Sets.xlsx", "General.xlsx")
    relative_paths = [str((source / name).relative_to(repo)) for name in names]
    changed = subprocess.run(
        ["git", "-C", repo, "diff", "--quiet", "--", *relative_paths]
    ).returncode
    if changed:
        raise RuntimeError(
            "Industry conversion source workbooks are modified; refusing an "
            "unreproducible conversion"
        )
    return {
        "repository": str(repo.resolve()),
        "commit": git_value(repo, "rev-parse", "HEAD"),
        "workbooks": [
            {
                "path": str((source / name).relative_to(repo)),
                "bytes": (source / name).stat().st_size,
                "sha256": sha256(source / name),
            }
            for name in names
        ],
    }


def prepare_target(target: Path) -> None:
    folder = target / "Industry"
    if folder.exists():
        shutil.rmtree(folder)
    manifest = target / "industry_conversion_manifest.json"
    if manifest.exists():
        manifest.unlink()


def canonicalize(
    frame: pd.DataFrame,
    table: str,
    source_row_offset: int = 4,
) -> tuple[pd.DataFrame, list[dict[str, object]]]:
    if frame.empty:
        raise ValueError(f"{table}: table is empty")
    if frame.shape[1] == 1:
        if len(frame) != 1:
            raise ValueError(f"{table}: scalar table must contain exactly one row")
        return frame, []
    keys = list(frame.columns[:-1])
    value = frame.columns[-1]
    duplicate = frame.duplicated(keys, keep=False)
    audit: list[dict[str, object]] = []
    for _, group in frame.loc[duplicate].groupby(keys, sort=False, dropna=False):
        selected = group.iloc[-1]
        for index, discarded in group.iloc[:-1].iterrows():
            audit.append(
                {
                    "Table": table,
                    "Key": "|".join(str(selected[column]) for column in keys),
                    "DiscardedSourceRow": int(index) + source_row_offset,
                    "DiscardedValue": discarded[value],
                    "SelectedSourceRow": int(group.index[-1]) + source_row_offset,
                    "SelectedValue": selected[value],
                    "ValuesDiffer": discarded[value] != selected[value],
                }
            )
    return frame.drop_duplicates(keys, keep="last"), audit


def validate_numeric(frame: pd.DataFrame, table: str, periods: int) -> None:
    if frame.isna().any().any():
        raise ValueError(f"{table}: missing value")
    for column in frame.columns:
        if "period" in str(column).lower():
            values = pd.to_numeric(frame[column], errors="raise")
            if not ((values % 1 == 0) & values.between(1, periods)).all():
                raise ValueError(f"{table}: invalid period value")
    values = pd.to_numeric(frame.iloc[:, -1], errors="raise")
    if not all(math.isfinite(float(value)) for value in values):
        raise ValueError(f"{table}: non-finite value")
    if (values < 0).any():
        raise ValueError(f"{table}: negative value")


def convert_sets(source: Path, target: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    industry = pd.ExcelFile(source / "Industry.xlsx")
    for sheet, output in SET_SHEETS.items():
        frame = finalize(read_sheet(industry, sheet, skiprows=0))
        if frame.shape[1] != 1 or frame.empty or frame.iloc[:, 0].duplicated().any():
            raise ValueError(f"Industry.xlsx::{sheet}: invalid set")
        frame.columns = [output]
        values = [str(value) for value in frame.iloc[:, 0]]
        result[output] = values
        write_csv(frame, target / "Industry" / f"{output}.csv")

    sets = pd.ExcelFile(source / "Sets.xlsx")
    for sheet, output in PRODUCER_SHEETS.items():
        frame = finalize(read_sheet(sets, sheet, skiprows=0))
        if frame.shape[1] != 1 or frame.empty or frame.iloc[:, 0].duplicated().any():
            raise ValueError(f"Sets.xlsx::{sheet}: invalid set")
        frame.columns = [output]
        values = [str(value) for value in frame.iloc[:, 0]]
        result[output] = values
        write_csv(frame, target / "Sets" / f"{output}.csv")
    return result


def convert_tables(
    source: Path,
    target: Path,
    periods: int,
) -> tuple[dict[str, pd.DataFrame], list[dict[str, object]]]:
    excel = pd.ExcelFile(source / "Industry.xlsx")
    frames: dict[str, pd.DataFrame] = {}
    audit: list[dict[str, object]] = []
    for sheet, columns in INDUSTRY_TABLES.items():
        selected, _ = select_table(read_sheet(excel, sheet, skiprows=2), columns, periods)
        frame = finalize(selected)
        output = OUTPUT_NAMES[sheet]
        table = f"Industry/{output}.csv"
        frame, duplicate_rows = canonicalize(frame, table)
        validate_numeric(frame, table, periods)
        frames[output] = frame.reset_index(drop=True)
        audit.extend(duplicate_rows)
    return frames, audit


def complete_grid(
    frame: pd.DataFrame,
    dimensions: tuple[list[object], ...],
    reason: str,
) -> tuple[pd.DataFrame, list[dict[str, object]]]:
    key_columns = list(frame.columns[:-1])
    value_column = frame.columns[-1]
    present = set(map(tuple, frame[key_columns].itertuples(index=False, name=None)))
    additions: list[dict[str, object]] = []
    generated: list[dict[str, object]] = []

    def visit(prefix: tuple[object, ...], depth: int) -> None:
        if depth == len(dimensions):
            if prefix not in present:
                row = dict(zip(key_columns, prefix))
                row[value_column] = 0.0
                additions.append(row)
                generated.append(
                    {
                        "Table": "",
                        "Key": "|".join(str(value) for value in prefix),
                        "Value": 0.0,
                        "Reason": reason,
                    }
                )
            return
        for value in dimensions[depth]:
            visit((*prefix, value), depth + 1)

    visit((), 0)
    addition_frame = pd.DataFrame(
        additions,
        columns=(*key_columns, value_column),
    )
    complete = pd.concat((frame, addition_frame), ignore_index=True)
    complete = complete.sort_values(key_columns, kind="stable").reset_index(drop=True)
    return complete, generated


def materialize_defaults(
    frames: dict[str, pd.DataFrame],
    sets: dict[str, list[str]],
    periods: int,
) -> list[dict[str, object]]:
    generated: list[dict[str, object]] = []
    specifications = (
        ("SteelInitialCapacity", (sets["SteelProducers"], sets["SteelPlants"])),
        ("CementInitialCapacity", (sets["CementProducers"], sets["CementPlants"])),
        ("AmmoniaInitialCapacity", (sets["AmmoniaProducers"], sets["AmmoniaPlants"])),
        ("SteelScaleFactorInitialCap", (sets["SteelPlants"], list(range(1, periods + 1)))),
        ("CementScaleFactorInitialCap", (sets["CementPlants"], list(range(1, periods + 1)))),
        ("AmmoniaScaleFactorInitialCap", (sets["AmmoniaPlants"], list(range(1, periods + 1)))),
    )
    for name, dimensions in specifications:
        complete, rows = complete_grid(
            frames[name],
            dimensions,
            "InternalEMPIRE Pyomo Param default for absent source key",
        )
        for row in rows:
            row["Table"] = f"Industry/{name}.csv"
        frames[name] = complete
        generated.extend(rows)
    return generated


def convert_biomass(source: Path, target: Path, periods: int) -> list[dict[str, object]]:
    excel = pd.ExcelFile(source / "General.xlsx")
    selected, _ = select_table(
        read_sheet(excel, "AvailableBioEnergy", skiprows=2), [0, 1], periods
    )
    frame, audit = canonicalize(finalize(selected), "General/AvailableBioEnergy.csv")
    validate_numeric(frame, "General/AvailableBioEnergy.csv", periods)
    write_csv(frame, target / "General" / "AvailableBioEnergy.csv")
    return audit


def file_entry(path: Path, target: Path) -> dict[str, object]:
    return {
        "path": str(path.relative_to(target)),
        "bytes": path.stat().st_size,
        "rows": sum(1 for _ in path.open(encoding="utf-8")) - 1
        if path.suffix == ".csv"
        else None,
        "sha256": sha256(path),
    }


def write_outputs(
    target: Path,
    frames: dict[str, pd.DataFrame],
    duplicate_audit: list[dict[str, object]],
    generated: list[dict[str, object]],
) -> None:
    for name, frame in frames.items():
        write_csv(frame, target / "Industry" / f"{name}.csv")
    write_csv(
        pd.DataFrame(CONSTANTS, columns=("Parameter", "Value", "Unit", "Source")),
        target / "Industry" / "Constants.csv",
    )
    write_csv(
        pd.DataFrame(
            duplicate_audit,
            columns=(
                "Table", "Key", "DiscardedSourceRow", "DiscardedValue",
                "SelectedSourceRow", "SelectedValue", "ValuesDiffer",
            ),
        ),
        target / "Industry" / "duplicate_input_audit.csv",
    )
    write_csv(
        pd.DataFrame(generated, columns=("Table", "Key", "Value", "Reason")),
        target / "Industry" / "generated_default_rows.csv",
    )


def write_manifest(
    source: dict[str, object],
    target: Path,
    periods: int,
    duplicate_audit: list[dict[str, object]],
    generated: list[dict[str, object]],
) -> None:
    managed = sorted(
        [*list((target / "Industry").glob("*.csv"))]
        + [
            target / "Sets" / f"{name}.csv" for name in PRODUCER_SHEETS.values()
        ]
        + [target / "General" / "AvailableBioEnergy.csv"]
    )
    manifest = {
        "schema_version": 1,
        "converter": "scripts/convert_industry_inputs.py",
        "periods": periods,
        "source": source,
        "demand_formulation": "fixed hourly demand (FLEX_IND=false; yearly production / 8760)",
        "refinery_heat_semantics": (
            "Refinery heat consumption is recorded but unconstrained while the Heat "
            "module is disabled, matching InternalEMPIRE HEATMODULE=false."
        ),
        "duplicate_rows_resolved_last_source_row_wins": len(duplicate_audit),
        "pyomo_default_rows_materialized": len(generated),
        "files": [file_entry(path, target) for path in managed],
    }
    path = target / "industry_conversion_manifest.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def update_dataset_manifest(target: Path) -> None:
    manifest_path = target / "conversion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    managed = sorted(
        [*list((target / "Industry").glob("*.csv"))]
        + [target / "Sets" / f"{name}.csv" for name in PRODUCER_SHEETS.values()]
        + [target / "General" / "AvailableBioEnergy.csv"]
        + [target / "industry_conversion_manifest.json"]
    )
    related = {
        *(f"Sets/{name}.csv" for name in PRODUCER_SHEETS.values()),
        "General/AvailableBioEnergy.csv",
        "industry_conversion_manifest.json",
    }
    retained = [
        entry for entry in manifest["files"]
        if not entry["path"].startswith("Industry/") and entry["path"] not in related
    ]
    manifest["files"] = sorted(
        [*retained, *(file_entry(path, target) for path in managed)],
        key=lambda entry: entry["path"],
    )
    manifest["industry_conversion_manifest"] = "industry_conversion_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument(
        "--target", type=Path, default=REPOSITORY / "data" / "full_model_int"
    )
    parser.add_argument("--periods", type=int, default=7)
    return parser.parse_args(argv)


def main(argv=None) -> None:
    args = parse_args(argv)
    source = args.source.resolve()
    target = args.target.resolve()
    if not (target / "Sets" / "Node.csv").is_file():
        raise ValueError(f"target is not an existing OpenEMPIRE CSV dataset: {target}")
    provenance = verify_sources(source)
    prepare_target(target)
    sets = convert_sets(source, target)
    frames, audit = convert_tables(source, target, args.periods)
    generated = materialize_defaults(frames, sets, args.periods)
    audit.extend(convert_biomass(source, target, args.periods))
    write_outputs(target, frames, audit, generated)
    write_manifest(provenance, target, args.periods, audit, generated)
    update_dataset_manifest(target)
    print(
        f"industry conversion: PASS ({len(audit)} duplicate source rows resolved, "
        f"{len(generated)} Pyomo defaults materialized; target={target})"
    )


if __name__ == "__main__":
    main()
