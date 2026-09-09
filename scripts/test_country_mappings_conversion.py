"""Converter regression test: country / NUTS2 Excel sheets -> country-level CSVs.

Exercises the localized converter support added for NUTS2 datasets:

  Sets.xlsx!Countries                    -> Sets/Countries.csv
  Sets.xlsx!NodesOfCountry               -> Sets/NodesOfCountry.csv
  Generator.xlsx!MaxBuiltCapacityCountry -> Generator/genMaxBuiltCapCountry.csv
  Generator.xlsx!MinBuiltCapacityCountry -> Generator/genMinBuiltCapCountry.csv
  Generator.xlsx!MaxInstalledCapacityCountry
                                         -> Generator/genMaxInstalledCapCountry.csv

It reproduces the exact converter mechanism (``convert_core_tables`` /
``convert_core_sets`` inner loop: optional-skip check -> ``read_sheet`` ->
``select_table`` -> ``finalize`` -> ``write_csv`` for tables; column split for the
``Countries`` set sheet) against synthetic workbooks in a temp directory, and
also against a real North Sea workbook set when one is available locally.

All five sheets must be optional: a workbook missing any or all of them must
convert without raising and without writing a misleading empty CSV.

Usage:
    python scripts/test_country_mappings_conversion.py
    python scripts/test_country_mappings_conversion.py --source <dir with the xlsx>

Exit code 0 on pass, 1 on failure. Modifies nothing under the repo.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

import pandas as pd

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

import convert_internalempire_xlsx as conv  # noqa: E402

PERIODS = 7

# (workbook, sheet) -> expected relative output path.
TABLE_ENTRIES = {
    ("Sets.xlsx", "NodesOfCountry"): Path("Sets") / "NodesOfCountry.csv",
    ("Generator.xlsx", "MaxBuiltCapacityCountry"): Path("Generator") / "genMaxBuiltCapCountry.csv",
    ("Generator.xlsx", "MinBuiltCapacityCountry"): Path("Generator") / "genMinBuiltCapCountry.csv",
    ("Generator.xlsx", "MaxInstalledCapacityCountry"): Path("Generator") / "genMaxInstalledCapCountry.csv",
}
SET_SHEET = ("Sets.xlsx", "Countries")
SET_OUTPUT = Path("Sets") / "Countries.csv"

ALL_OUTPUTS = [SET_OUTPUT, *TABLE_ENTRIES.values()]


# --------------------------------------------------------------------------------------
# Converter mechanism, reproduced exactly for the country entries only
# --------------------------------------------------------------------------------------

def _table_entry(workbook: str, sheet: str):
    for entry in conv.CORE_TABLES[workbook]:
        if entry[0] == sheet:
            return entry
    raise AssertionError(
        f"{sheet!r} is not registered in CORE_TABLES[{workbook!r}] - converter change missing"
    )


def _convert_country_outputs(source: Path, out: Path) -> list[Path]:
    """Write every available country-level CSV under ``out``; return the written paths.

    Mirrors the optional-skip contract of ``convert_core_tables`` /
    ``convert_core_sets``: a registered-but-absent sheet is logged and skipped,
    never fatal, and no CSV is created for it.
    """
    written: list[Path] = []

    # --- Countries set sheet (convert_core_sets: header=0, per-column split) -----------
    sets_path = source / SET_SHEET[0]
    assert ("Countries" in conv.OPTIONAL_CORE_SET_SHEETS), \
        "'Countries' must be registered in OPTIONAL_CORE_SET_SHEETS"
    if sets_path.exists():
        with pd.ExcelFile(sets_path) as excel:
            if "Countries" not in excel.sheet_names:
                # optional -> skipped, exactly as convert_core_sets does
                pass
            else:
                mapping = conv.CORE_SET_COLUMNS["Countries"]
                raw = conv.read_sheet(excel, "Countries", skiprows=0)
                for column in raw.columns:
                    name = str(column).strip()
                    if name not in mapping:
                        continue
                    filename, header = mapping[name]
                    values = conv.strip_cell_whitespace(raw[[column]].dropna())
                    values.columns = [header]
                    target = out / "Sets" / f"{filename}.csv"
                    conv.write_csv(values, target)
                    written.append(SET_OUTPUT)

    # --- CORE_TABLES country entries (convert_core_tables inner loop) ------------------
    for (workbook, sheet), rel in TABLE_ENTRIES.items():
        assert (workbook, sheet) in conv.OPTIONAL_CORE_SHEETS, \
            f"({workbook!r}, {sheet!r}) must be registered in OPTIONAL_CORE_SHEETS"
        wb_path = source / workbook
        if not wb_path.exists():
            continue
        _sheet, usecols, component, filename = _table_entry(workbook, sheet)
        with pd.ExcelFile(wb_path) as excel:
            if sheet not in excel.sheet_names:
                # optional -> logged + skipped, no CSV written
                continue
            raw = conv.read_sheet(excel, sheet, skiprows=2)
        selected, _dropped = conv.select_table(raw, usecols, PERIODS)
        target = out / component / f"{filename}.csv"
        conv.write_csv(conv.finalize(selected), target)
        written.append(rel)

    return written


# --------------------------------------------------------------------------------------
# Synthetic workbook builders
# --------------------------------------------------------------------------------------

def _write_table_sheet(writer, sheet: str, columns: list[str], rows: list[list]) -> None:
    """A CORE_TABLES sheet: two filler rows, then header, then data (read skiprows=2)."""
    frame = pd.DataFrame(rows, columns=columns)
    frame.to_excel(writer, sheet_name=sheet, index=False, header=True, startrow=2)


def _write_set_sheet(writer, sheet: str, columns: list[str], rows: list[list]) -> None:
    """A CORE_SET_COLUMNS sheet: header on the first row (read skiprows=0)."""
    pd.DataFrame(rows, columns=columns).to_excel(writer, sheet_name=sheet, index=False)


def _build_workbooks(base: Path, *, countries: bool, nodes_of_country: bool,
                     max_built: bool, min_built: bool, max_installed: bool) -> None:
    base.mkdir(parents=True, exist_ok=True)

    with pd.ExcelWriter(base / "Sets.xlsx", engine="openpyxl") as w:
        # A non-country sheet so the workbook is always valid on its own.
        _write_table_sheet(w, "GeneratorsOfNode", ["Node", "Generator"],
                           [["N1", "Gas"], ["N2", "Bio"]])
        if countries:
            _write_set_sheet(w, "Countries", ["Country"],
                             [["Alpha"], ["Great Brit."], ["Beta"]])
        if nodes_of_country:
            _write_table_sheet(w, "NodesOfCountry", ["Country", "Node"],
                               [["Alpha", "N1"], ["Alpha", "N2"], ["Beta", "N3"]])

    with pd.ExcelWriter(base / "Generator.xlsx", engine="openpyxl") as w:
        _write_table_sheet(w, "Lifetime", ["GeneratorTechnology", "generatorLifetime"],
                           [["Gas", 25], ["Bio", 30]])
        if max_built:
            _write_table_sheet(
                w, "MaxBuiltCapacityCountry",
                ["Country", "GeneratorTechnology", "Period", "generatorMaxBuildCapacity in MW"],
                [["Alpha", "Nuclear", 1, 0.0], ["Alpha", "Nuclear", 2, 1500.0],
                 ["Beta", "Bio", 1, 200000.0],
                 ["Alpha", "Nuclear", 9, 999.0]],  # Period > PERIODS -> dropped by filter
            )
        if min_built:
            _write_table_sheet(
                w, "MinBuiltCapacityCountry",
                ["Country", "GeneratorTechnology", "Period", "generatorMinBuildCapacity in MW"],
                [["Great Brit.", "Nuclear", 2, 1630.0], ["Great Brit.", "Nuclear", 5, 9632.0]],
            )
        if max_installed:
            _write_table_sheet(
                w, "MaxInstalledCapacityCountry",
                ["Country", "GeneratorTechnology", "generatorMaxInstallCapacity in MW"],
                [["Alpha", "Bio", 200000.0], ["Beta", "Nuclear", 5000.0]],
            )


# --------------------------------------------------------------------------------------
# Cases
# --------------------------------------------------------------------------------------

def _present_outputs(out: Path) -> set[str]:
    return {p.relative_to(out).as_posix() for p in out.rglob("*.csv")}


def _run_case(name: str, *, flags: dict[str, bool]) -> list[str]:
    errors: list[str] = []
    expected = set()
    if flags["countries"]:
        expected.add(SET_OUTPUT.as_posix())
    if flags["nodes_of_country"]:
        expected.add((Path("Sets") / "NodesOfCountry.csv").as_posix())
    if flags["max_built"]:
        expected.add((Path("Generator") / "genMaxBuiltCapCountry.csv").as_posix())
    if flags["min_built"]:
        expected.add((Path("Generator") / "genMinBuiltCapCountry.csv").as_posix())
    if flags["max_installed"]:
        expected.add((Path("Generator") / "genMaxInstalledCapCountry.csv").as_posix())

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
        src = Path(td) / "src"
        out = Path(td) / "out"
        _build_workbooks(src, **flags)
        try:
            _convert_country_outputs(src, out)
        except Exception as exc:  # noqa: BLE001 - any exception is a failure here
            return [f"[{name}] conversion raised {type(exc).__name__}: {exc}"]

        produced = _present_outputs(out)
        if produced != expected:
            errors.append(
                f"[{name}] produced {sorted(produced)} but expected exactly {sorted(expected)}"
            )

        # Column / value spot checks when the sheets are present.
        if flags["countries"] and (out / SET_OUTPUT).exists():
            df = pd.read_csv(out / SET_OUTPUT)
            if list(df.columns) != ["Country"]:
                errors.append(f"[{name}] Countries.csv columns {df.columns.tolist()} != ['Country']")
            if df["Country"].tolist() != ["Alpha", "GreatBrit.", "Beta"]:
                errors.append(f"[{name}] Countries.csv values {df['Country'].tolist()} unexpected")
        if flags["nodes_of_country"] and (out / "Sets" / "NodesOfCountry.csv").exists():
            df = pd.read_csv(out / "Sets" / "NodesOfCountry.csv")
            if list(df.columns) != ["Country", "Node"]:
                errors.append(f"[{name}] NodesOfCountry.csv columns {df.columns.tolist()}")
            if len(df) != 3:
                errors.append(f"[{name}] NodesOfCountry.csv row count {len(df)} != 3")
        if flags["max_built"] and (out / "Generator" / "genMaxBuiltCapCountry.csv").exists():
            df = pd.read_csv(out / "Generator" / "genMaxBuiltCapCountry.csv")
            if list(df.columns) != ["Country", "GeneratorTechnology", "Period",
                                    "generatorMaxBuildCapacity_in_MW"]:
                errors.append(f"[{name}] genMaxBuiltCapCountry.csv columns {df.columns.tolist()}")
            if 9 in df["Period"].tolist():
                errors.append(f"[{name}] genMaxBuiltCapCountry.csv kept Period 9 (> {PERIODS})")
            if len(df) != 3:
                errors.append(f"[{name}] genMaxBuiltCapCountry.csv row count {len(df)} != 3")
        if flags["min_built"] and (out / "Generator" / "genMinBuiltCapCountry.csv").exists():
            df = pd.read_csv(out / "Generator" / "genMinBuiltCapCountry.csv")
            if list(df.columns) != ["Country", "GeneratorTechnology", "Period",
                                    "generatorMinBuildCapacity_in_MW"]:
                errors.append(f"[{name}] genMinBuiltCapCountry.csv columns {df.columns.tolist()}")
            if df["Country"].tolist() != ["GreatBrit.", "GreatBrit."]:
                errors.append(f"[{name}] genMinBuiltCapCountry.csv country whitespace not stripped")
        if flags["max_installed"] and (out / "Generator" / "genMaxInstalledCapCountry.csv").exists():
            df = pd.read_csv(out / "Generator" / "genMaxInstalledCapCountry.csv")
            if list(df.columns) != ["Country", "GeneratorTechnology",
                                    "generatorMaxInstallCapacity_in_MW"]:
                errors.append(f"[{name}] genMaxInstalledCapCountry.csv columns {df.columns.tolist()}")
            if len(df) != 2:
                errors.append(f"[{name}] genMaxInstalledCapCountry.csv row count {len(df)} != 2")

    return errors


# --------------------------------------------------------------------------------------
# Real workbook check (item 6): no generated file is copied into the repo.
# --------------------------------------------------------------------------------------

def _default_source() -> Path:
    candidates = [
        Path.home() / "OpenEMPIRE" / "NorthSea_NECPEssentials",
        Path.home() / "OpenEMPIRE_Data_Raw" / "NorthSea" / "NorthSea_NECPEssentials",
        _HERE.parents[2] / "OpenEMPIRE" / "NorthSea_NECPEssentials",
    ]
    for c in candidates:
        if (c / "Sets.xlsx").is_file() and (c / "Generator.xlsx").is_file():
            return c
    return candidates[0]


def _run_real(source: Path) -> tuple[str, list[str]]:
    if not ((source / "Sets.xlsx").is_file() and (source / "Generator.xlsx").is_file()):
        return f"SKIP: no Sets.xlsx/Generator.xlsx under {source}", []
    errors: list[str] = []
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
        out = Path(td) / "out"
        try:
            _convert_country_outputs(source, out)
        except Exception as exc:  # noqa: BLE001
            return "real workbook", [f"conversion raised {type(exc).__name__}: {exc}"]
        produced = _present_outputs(out)
        expected = {p.as_posix() for p in ALL_OUTPUTS}
        if produced != expected:
            errors.append(f"produced {sorted(produced)} but expected {sorted(expected)}")
        for rel in ALL_OUTPUTS:
            df = pd.read_csv(out / rel)
            if df.empty:
                errors.append(f"{rel.as_posix()} is empty")
    return f"real workbook ({source})", errors


# --------------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=_default_source())
    args = ap.parse_args()

    all_true = dict(countries=True, nodes_of_country=True, max_built=True,
                    min_built=True, max_installed=True)
    all_false = {k: False for k in all_true}
    some = dict(countries=True, nodes_of_country=False, max_built=True,
               min_built=False, max_installed=True)

    cases = [
        ("1: all optional sheets present", all_true),
        ("2: all optional sheets absent", all_false),
        ("3: some optional sheets present", some),
    ]

    failures: list[str] = []
    for name, flags in cases:
        errs = _run_case(name, flags=flags)
        if errs:
            failures.extend(errs)
        else:
            produced = "none" if not any(flags.values()) else "expected subset only"
            print(f"PASS {name} -> {produced}")

    real_label, real_errs = _run_real(args.source)
    if real_errs:
        failures.extend(f"[{real_label}] {e}" for e in real_errs)
    elif real_label.startswith("SKIP"):
        print(real_label)
    else:
        print(f"PASS {real_label}: all 5 country-level CSVs produced")

    if failures:
        print("\nFAIL: country-level converter mapping regression")
        for f in failures:
            print("  -", f)
        return 1

    print("\nPASS: country-level converter mapping regression (synthetic 3 cases + real workbook)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
