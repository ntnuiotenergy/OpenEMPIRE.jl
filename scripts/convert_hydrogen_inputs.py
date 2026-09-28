#!/usr/bin/env python3
"""Convert only the Hydrogen/CO2 inputs required by OpenEMPIRE.jl.

The source workbooks are read-only. Outputs are written beneath an existing CSV
dataset and described by a separate deterministic manifest, so this conversion does
not regenerate or disturb the already reviewed electricity/natural-gas dataset.
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

HYDROGEN_TABLES = {
    "ReformerCapitalCost": [0, 1, 2],
    "ReformerFixedOMCost": [0, 1, 2],
    "ReformerVariableOMCost": [0, 1, 2],
    "ReformerEfficiency": [0, 1, 2],
    "ReformerElectricityUse": [0, 1, 2],
    "ReformerLifetime": [0, 1],
    "ReformerEmissionFactor": [0, 1, 2],
    "ReformerCO2CaptureFactor": [0, 1, 2],
    "ElectrolyzerPlantCapitalCost": [0, 1],
    "ElectrolyzerFixedOMCost": [0, 1],
    "ElectrolyzerLifetime": [0],
    "ElectrolyzerPowerUse": [0, 1],
    "PipelineCapitalCost": [0, 1],
    "PipelineOMCostPerKM": [0, 1],
    "PipelineCompressorPowerUsage": [0],
    "StorageCapitalCost": [0, 1, 2],
    "StorageFixedOMCost": [0, 1, 2],
    "StorageMaxCapacity": [0, 1, 2],
    "StorageLifetime": [0, 1],
    "H2TerminalCapitalCost": [0, 1, 2, 3],
    "H2TerminalFixedOM": [0, 1, 2, 3],
    "H2TerminalLifetime": [0, 1],
    "H2TerminalPrice": [0, 1, 2, 3],
    "H2TerminalCapacity": [0, 1, 2, 3],
}

CO2_TABLES = {
    "StorageSiteCapitalCost": [0, 1],
    "StorageSiteFixedOMCost": [0, 1],
    "StorageMaxCapacity": [0, 1, 2],
    "PipelineCapitalCost": [0],
    "PipelineFixedOM": [0],
    "PipelineLifetime": [0],
    "PipelineElectricityUsage": [0],
    "MaxSequestrationCapacity": [0, 1],
}

SET_SHEETS = (
    "ProductionNodes",
    "ReformerLocations",
    "ReformerPlants",
    "H2Storages",
    "H2Terminals",
    "H2TerminalNodes",
)

RELATION_SET_SHEETS = {"H2TerminalsOfNode": [0, 1]}

SCALARS = (
    ("hydrogen_mwh_per_ton", 33.3, "MWh/tonne", "empire.py hydrogen_MWhPerTon"),
    ("storage_initial_fraction", 0.5, "fraction", "empire.py hydrogenStorageInitOperational"),
    ("storage_compression_mwh_per_ton", 0.333, "MWh/tonne", "empire.py 0.01*33.3"),
    ("pipeline_compressor_static_mwh_per_ton", 1.0, "MWh/tonne", "empire.py hard-coded"),
    ("hydrogen_pipeline_lifetime_years", 40.0, "years", "empire.py Param default"),
    ("pipeline_leakage_fraction_per_km", 0.000005, "fraction/km", "empire.py 0.005e-3"),
    ("reformer_ramp_fraction_per_hour", 0.1, "fraction/hour", "empire.py hard-coded"),
    ("repurpose_cost_factor", 0.25, "fraction", "approved port configuration"),
    ("repurpose_energy_flow_factor", 0.8, "fraction", "approved port configuration"),
    ("terminal_eur_per_kg_to_eur_per_ton", 1000.0, "kg/tonne", "empire.py hard-coded"),
    ("hours_per_year", 8760.0, "hour/year", "empire.py hard-coded"),
)

UNUSED_SOURCE_INPUTS = {
    "Hydrogen.xlsx::ElectrolyzerStackCapitalCost": (
        "InternalEMPIRE reads this table but never uses it in electrolyzer investment "
        "cost; the active formulation uses plant capital cost plus fixed O&M."
    ),
    "Hydrogen.xlsx::H2TerminalMaxBuild": (
        "InternalEMPIRE's parameter and constraints are commented out and the table "
        "is incomplete for every LH2Import terminal-node pair."
    ),
}

# A negative SMR value exists in the reference and is used as a generation credit.
SIGNED_VALUE_TABLES = {"Hydrogen/ReformerElectricityUse.csv"}


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
    relative_paths = [
        str((source / name).relative_to(repo))
        for name in ("Hydrogen.xlsx", "CO2.xlsx", "Transport.xlsx", "Generator.xlsx")
    ]
    changed = subprocess.run(
        ["git", "-C", repo, "diff", "--quiet", "--", *relative_paths]
    ).returncode
    if changed:
        raise RuntimeError(
            "Hydrogen conversion source workbooks are modified; refusing an "
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
            for name in ("Hydrogen.xlsx", "CO2.xlsx", "Transport.xlsx", "Generator.xlsx")
        ],
    }


def prepare_target(target: Path) -> None:
    """Clear only converter-owned module outputs so stale files cannot survive."""
    for folder in (target / "Hydrogen", target / "CO2"):
        if folder.exists():
            shutil.rmtree(folder)
    manifest = target / "hydrogen_conversion_manifest.json"
    if manifest.exists():
        manifest.unlink()


def canonicalize(frame: pd.DataFrame, table: str) -> tuple[pd.DataFrame, list[dict]]:
    if frame.empty:
        raise ValueError(f"{table}: table is empty")
    if frame.shape[1] == 1:
        if len(frame) != 1:
            raise ValueError(f"{table}: scalar table must contain exactly one row")
        return frame, []

    keys = list(frame.columns[:-1])
    value = frame.columns[-1]
    duplicate = frame.duplicated(keys, keep=False)
    audit = []
    for _, group in frame.loc[duplicate].groupby(keys, sort=False, dropna=False):
        selected = group.iloc[-1]
        for index, discarded in group.iloc[:-1].iterrows():
            audit.append(
                {
                    "Table": table,
                    "Key": "|".join(str(selected[column]) for column in keys),
                    "DiscardedSourceRow": int(index) + 2,
                    "DiscardedValue": discarded[value],
                    "SelectedSourceRow": int(group.index[-1]) + 2,
                    "SelectedValue": selected[value],
                    "ValuesDiffer": discarded[value] != selected[value],
                }
            )
    return frame.drop_duplicates(keys, keep="last"), audit


def validate_numeric_table(frame: pd.DataFrame, table: str, periods: int) -> None:
    if frame.isna().any().any():
        raise ValueError(f"{table}: missing value")
    for column in frame.columns:
        if "period" in str(column).lower():
            numeric = pd.to_numeric(frame[column], errors="raise")
            if not ((numeric % 1 == 0) & numeric.between(1, periods)).all():
                raise ValueError(f"{table}: invalid period value")

    value_column = frame.columns[-1]
    numeric = pd.to_numeric(frame[value_column], errors="raise")
    if not all(math.isfinite(float(value)) for value in numeric):
        raise ValueError(f"{table}: non-finite value")
    if table not in SIGNED_VALUE_TABLES and (numeric < 0).any():
        raise ValueError(f"{table}: negative value")


def convert_tables(
    workbook: Path,
    tables: dict[str, list[int]],
    target: Path,
    component: str,
    periods: int,
) -> list[dict]:
    excel = pd.ExcelFile(workbook)
    audit = []
    for sheet, columns in tables.items():
        if sheet not in excel.sheet_names:
            raise ValueError(f"{workbook.name}: missing required sheet {sheet!r}")
        selected, _ = select_table(read_sheet(excel, sheet, skiprows=2), columns, periods)
        frame = finalize(selected)
        table = f"{component}/{sheet}.csv"
        frame, duplicate_rows = canonicalize(frame, table)
        validate_numeric_table(frame, table, periods)
        write_csv(frame, target / component / f"{sheet}.csv")
        audit.extend(duplicate_rows)
    return audit


def convert_sets(workbook: Path, target: Path) -> None:
    excel = pd.ExcelFile(workbook)
    for sheet in SET_SHEETS:
        frame = read_sheet(excel, sheet, skiprows=0)
        columns = [
            column
            for column in frame.columns
            if not str(column).startswith("Unnamed") and not frame[column].isna().all()
        ]
        if len(columns) != 1:
            raise ValueError(f"Hydrogen.xlsx::{sheet}: expected exactly one set column")
        values = finalize(frame[[columns[0]]])
        if values.empty or values.iloc[:, 0].duplicated().any():
            raise ValueError(f"Hydrogen.xlsx::{sheet}: empty or duplicate set values")
        write_csv(values, target / "Hydrogen" / f"{sheet}.csv")

    for sheet, positions in RELATION_SET_SHEETS.items():
        raw = read_sheet(excel, sheet, skiprows=2)
        frame = finalize(raw.iloc[:, positions])
        if frame.empty or frame.duplicated().any():
            raise ValueError(f"Hydrogen.xlsx::{sheet}: empty or duplicate relation")
        write_csv(frame, target / "Hydrogen" / f"{sheet}.csv")


def convert_hydrogen_generators(source: Path, target: Path) -> None:
    generator_rows = pd.read_csv(target / "Sets" / "Generator.csv")
    generator_column = generator_rows.columns[0]
    derived = sorted(
        str(value) for value in generator_rows[generator_column]
        if "hydrogen" in str(value).lower()
    )

    excel = pd.ExcelFile(source / "Hydrogen.xlsx")
    reference = finalize(read_sheet(excel, "Generators", skiprows=0))
    reference_values = sorted(str(value) for value in reference.iloc[:, 0])
    if derived != reference_values:
        raise ValueError(
            "Hydrogen generator CSV derivation disagrees with InternalEMPIRE's "
            f"case-insensitive name rule: derived={derived}, workbook={reference_values}"
        )
    write_csv(
        pd.DataFrame({"HydrogenGenerator": derived}),
        target / "Hydrogen" / "HydrogenGenerators.csv",
    )


def convert_co2_set(source: Path, target: Path) -> None:
    excel = pd.ExcelFile(source / "CO2.xlsx")
    frame = finalize(read_sheet(excel, "CO2SequestrationNodes", skiprows=0))
    if frame.shape[1] != 1 or frame.empty or frame.iloc[:, 0].duplicated().any():
        raise ValueError("CO2.xlsx::CO2SequestrationNodes: invalid set")
    write_csv(frame, target / "CO2" / "CO2SequestrationNodes.csv")


def complete_co2_storage_capacity(target: Path, periods: int) -> list[dict[str, object]]:
    """Materialize Pyomo's zero default for missing sequestration-period keys."""
    nodes_frame = pd.read_csv(target / "CO2" / "CO2SequestrationNodes.csv")
    nodes = [str(value) for value in nodes_frame.iloc[:, 0]]
    path = target / "CO2" / "StorageMaxCapacity.csv"
    frame = pd.read_csv(path)
    present = set(map(tuple, frame.iloc[:, :2].itertuples(index=False, name=None)))
    generated = []
    for node in nodes:
        for period in range(1, periods + 1):
            if (node, period) in present:
                continue
            generated.append(
                {
                    "Node": node,
                    "Period": period,
                    "Storage_max_injection_capacity_(ton/hour)": 0.0,
                    "Reason": "InternalEMPIRE Param default for absent source key",
                }
            )
    values = pd.DataFrame(
        [
            {
                "Node": row["Node"],
                "Period": row["Period"],
                "Storage_max_injection_capacity_(ton/hour)": row[
                    "Storage_max_injection_capacity_(ton/hour)"
                ],
            }
            for row in generated
        ]
    )
    write_csv(pd.concat((frame, values), ignore_index=True), path)
    write_csv(
        pd.DataFrame(generated),
        target / "CO2" / "generated_default_rows.csv",
    )
    return generated


def filter_unused_terminal_rows(target: Path) -> list[dict[str, object]]:
    """Remove terminal parameter rows outside the active terminal-node relation."""
    pairs_frame = pd.read_csv(target / "Hydrogen" / "H2TerminalsOfNode.csv")
    pairs = set(map(tuple, pairs_frame.iloc[:, :2].itertuples(index=False, name=None)))
    excluded = []
    for name in (
        "H2TerminalCapitalCost",
        "H2TerminalFixedOM",
        "H2TerminalPrice",
        "H2TerminalCapacity",
    ):
        path = target / "Hydrogen" / f"{name}.csv"
        frame = pd.read_csv(path)
        active = [tuple(row) in pairs for row in frame.iloc[:, :2].itertuples(index=False, name=None)]
        for index, row in frame.loc[[not value for value in active]].iterrows():
            excluded.append(
                {
                    "Table": name,
                    "SourceRow": int(index) + 2,
                    "Key": "|".join(str(value) for value in row.iloc[:3]),
                    "Reason": "terminal-node pair is absent from H2TerminalsOfNode",
                }
            )
        write_csv(frame.loc[active].reset_index(drop=True), path)
    write_csv(
        pd.DataFrame(excluded, columns=("Table", "SourceRow", "Key", "Reason")),
        target / "Hydrogen" / "excluded_input_rows.csv",
    )
    return excluded


def convert_transport_and_capture(source: Path, target: Path, periods: int) -> list[dict]:
    audit = []
    transport = pd.ExcelFile(source / "Transport.xlsx")
    for sheet in ("ElectricityDemand", "HydrogenDemand"):
        selected, _ = select_table(read_sheet(transport, sheet, skiprows=2), [0, 1, 2], periods)
        frame, rows = canonicalize(finalize(selected), f"Transport/{sheet}.csv")
        validate_numeric_table(frame, f"Transport/{sheet}.csv", periods)
        write_csv(frame, target / "Transport" / f"{sheet}.csv")
        audit.extend(rows)

    generator = pd.ExcelFile(source / "Generator.xlsx")
    selected, _ = select_table(read_sheet(generator, "CO2Captured", skiprows=2), [0, 1], periods)
    frame, rows = canonicalize(finalize(selected), "Generator/genCO2Captured.csv")
    validate_numeric_table(frame, "Generator/genCO2Captured.csv", periods)
    write_csv(frame, target / "Generator" / "genCO2Captured.csv")
    audit.extend(rows)
    return audit


def write_manifest(
    source_provenance: dict[str, object],
    target: Path,
    periods: int,
    duplicate_audit: list[dict],
    excluded_rows: list[dict],
    generated_defaults: list[dict],
) -> None:
    write_csv(
        pd.DataFrame(
            duplicate_audit,
            columns=(
                "Table",
                "Key",
                "DiscardedSourceRow",
                "DiscardedValue",
                "SelectedSourceRow",
                "SelectedValue",
                "ValuesDiffer",
            ),
        ),
        target / "Hydrogen" / "duplicate_input_audit.csv",
    )
    output_files = sorted(
        [*list((target / "Hydrogen").glob("*.csv")), *list((target / "CO2").glob("*.csv"))]
        + [target / "Transport" / "ElectricityDemand.csv"]
        + [target / "Transport" / "HydrogenDemand.csv"]
        + [target / "Generator" / "genCO2Captured.csv"]
    )
    manifest = {
        "schema_version": 1,
        "converter": "scripts/convert_hydrogen_inputs.py",
        "periods": periods,
        "source": source_provenance,
        "signed_source_values": {
            "Hydrogen/ReformerElectricityUse.csv": (
                "SMR contains -0.6666666667 MWh/tonne and InternalEMPIRE uses the "
                "signed coefficient as an electricity-balance credit."
            )
        },
        "excluded_inputs": UNUSED_SOURCE_INPUTS,
        "duplicate_rows_resolved_last_source_row_wins": len(duplicate_audit),
        "unused_parameter_rows_excluded": len(excluded_rows),
        "pyomo_default_rows_materialized": len(generated_defaults),
        "files": [
            {
                "path": str(path.relative_to(target)),
                "bytes": path.stat().st_size,
                "rows": sum(1 for _ in path.open(encoding="utf-8")) - 1,
                "sha256": sha256(path),
            }
            for path in output_files
        ],
    }
    (target / "hydrogen_conversion_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


def file_entry(path: Path, target: Path) -> dict[str, object]:
    return {
        "path": str(path.relative_to(target)),
        "bytes": path.stat().st_size,
        "rows": sum(1 for _ in path.open(encoding="utf-8")) - 1
        if path.suffix == ".csv"
        else None,
        "sha256": sha256(path),
    }


def update_dataset_manifest(target: Path) -> None:
    """Add generated module files to the dataset's strict file inventory."""
    manifest_path = target / "conversion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    managed = sorted(
        [*list((target / "Hydrogen").glob("*.csv")), *list((target / "CO2").glob("*.csv"))]
        + [target / "Transport" / "ElectricityDemand.csv"]
        + [target / "Transport" / "HydrogenDemand.csv"]
        + [target / "Generator" / "genCO2Captured.csv"]
        + [target / "hydrogen_conversion_manifest.json"]
    )
    related_names = {
        "Transport/ElectricityDemand.csv",
        "Transport/HydrogenDemand.csv",
        "Generator/genCO2Captured.csv",
        "hydrogen_conversion_manifest.json",
    }
    retained = [
        entry
        for entry in manifest["files"]
        if not entry["path"].startswith(("Hydrogen/", "CO2/"))
        and entry["path"] not in related_names
    ]
    manifest["files"] = sorted(
        [*retained, *(file_entry(path, target) for path in managed)],
        key=lambda entry: entry["path"],
    )
    manifest["hydrogen_conversion_manifest"] = "hydrogen_conversion_manifest.json"
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
    if not (target / "Sets" / "Generator.csv").is_file():
        raise ValueError(f"target is not an existing OpenEMPIRE CSV dataset: {target}")
    provenance = verify_sources(source)
    prepare_target(target)
    audit = []
    audit.extend(
        convert_tables(
            source / "Hydrogen.xlsx", HYDROGEN_TABLES, target, "Hydrogen", args.periods
        )
    )
    audit.extend(convert_tables(source / "CO2.xlsx", CO2_TABLES, target, "CO2", args.periods))
    convert_sets(source / "Hydrogen.xlsx", target)
    excluded_rows = filter_unused_terminal_rows(target)
    convert_hydrogen_generators(source, target)
    convert_co2_set(source, target)
    generated_defaults = complete_co2_storage_capacity(target, args.periods)
    audit.extend(convert_transport_and_capture(source, target, args.periods))
    write_csv(
        pd.DataFrame(SCALARS, columns=("Parameter", "Value", "Unit", "Source")),
        target / "Hydrogen" / "Constants.csv",
    )
    write_manifest(
        provenance,
        target,
        args.periods,
        audit,
        excluded_rows,
        generated_defaults,
    )
    update_dataset_manifest(target)
    print(
        f"hydrogen conversion: PASS ({len(audit)} duplicate source rows resolved, "
        f"{len(excluded_rows)} unreachable terminal rows excluded; "
        f"{len(generated_defaults)} Pyomo defaults materialized; "
        f"target={target})"
    )


if __name__ == "__main__":
    main()
