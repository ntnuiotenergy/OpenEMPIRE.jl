"""Converter regression test: General.xlsx!GenerationGrowthRate -> General/GenerationGrowthRate.csv.

Runs the real converter pipeline (`read_sheet` -> `select_table` -> `finalize`
-> `write_csv`) for the `GenerationGrowthRate` entry now registered in
`CORE_TABLES["General.xlsx"]`, into a temp directory, then checks that every
source (Period -> rate) pair survives the conversion unchanged.

Usage:
    python scripts/test_generation_growth_conversion.py
    python scripts/test_generation_growth_conversion.py --source <dir with General.xlsx>

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

SHEET = "GenerationGrowthRate"
TARGET_REL = Path("General") / "GenerationGrowthRate.csv"
PERIODS = 7

# Default source: the InternalEMPIRE NorthSea dataset the shipped CSV was built from
# (see data/NorthSea_NECPEssentials/conversion_manifest.json). Fall back through a few
# known locations so the test is runnable without arguments in this workspace.
def _default_source() -> Path:
    candidates = [
        Path.home() / "OpenEMPIRE" / "NorthSea_NECPEssentials",
        Path.home() / "OpenEMPIRE_Data_Raw" / "NorthSea" / "NorthSea_NECPEssentials",
        _HERE.parents[2] / "OpenEMPIRE" / "NorthSea_NECPEssentials",
    ]
    for c in candidates:
        if (c / "General.xlsx").is_file():
            return c
    return candidates[0]


DEFAULT_SOURCE = _default_source()


def _entry():
    for sheet, usecols, component, filename in conv.CORE_TABLES["General.xlsx"]:
        if sheet == SHEET:
            return sheet, usecols, component, filename
    raise AssertionError(
        f"{SHEET!r} is not registered in CORE_TABLES['General.xlsx'] - converter change missing"
    )


def _source_pairs(source: Path) -> dict[int, float]:
    raw = pd.read_excel(source / "General.xlsx", SHEET, header=2)
    out: dict[int, float] = {}
    for _, row in raw.iloc[:, [0, 1]].dropna().iterrows():
        out[int(row.iloc[0])] = float(row.iloc[1])
    return out


def _converted_pairs(source: Path, tmp: Path) -> dict[int, float]:
    sheet, usecols, _component, filename = _entry()
    excel = pd.ExcelFile(source / "General.xlsx")
    raw = conv.read_sheet(excel, sheet, skiprows=2)
    selected, dropped = conv.select_table(raw, usecols, PERIODS)
    assert dropped.empty, f"unexpected rows dropped by the Period<= {PERIODS} filter: {len(dropped)}"
    out_csv = tmp / _component_dir(filename)
    conv.write_csv(conv.finalize(selected), out_csv)
    df = pd.read_csv(out_csv)
    assert list(df.columns) == ["Period", "generationGrowthRate"], df.columns.tolist()
    return {int(p): float(v) for p, v in zip(df["Period"], df["generationGrowthRate"])}


def _component_dir(filename: str) -> Path:
    return Path("General") / f"{filename}.csv"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    args = ap.parse_args()

    source = args.source
    if not (source / "General.xlsx").is_file():
        print(f"SKIP: no General.xlsx under {source}")
        return 0

    src = _source_pairs(source)
    with tempfile.TemporaryDirectory() as td:
        got = _converted_pairs(source, Path(td))

    errors: list[str] = []
    if sorted(src) != sorted(got):
        errors.append(f"period key sets differ: source={sorted(src)} converted={sorted(got)}")
    if len(src) != PERIODS:
        errors.append(f"expected {PERIODS} source periods, found {len(src)}: {sorted(src)}")
    for p in sorted(set(src) & set(got)):
        if abs(src[p] - got[p]) > 0:
            errors.append(f"period {p}: source={src[p]!r} converted={got[p]!r}")

    if errors:
        print("FAIL: GenerationGrowthRate conversion regression")
        for e in errors:
            print("  -", e)
        return 1

    print(f"PASS: GenerationGrowthRate conversion regression ({len(src)} periods, exact values)")
    for p in sorted(src):
        print(f"    period {p} -> {src[p]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
