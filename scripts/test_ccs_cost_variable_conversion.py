"""Converter regression test: Generator.xlsx!CCSCostTSVariable -> Generator/CCSCostTSVariable.csv.

Runs the real converter pipeline (`read_sheet` -> `select_table` -> `finalize`
-> `write_csv`) for the `CCSCostTSVariable` entry in `CORE_TABLES["Generator.xlsx"]`
into a temp directory, then checks that every source (Period -> cost) pair
survives unchanged - i.e. the `--ccs-cost-mode python-nuts` output preserves the
genuine ZEP Excel values.

Also checks that `--ccs-cost-mode internalempire` (the default) still zeroes both
CCS T&S cost CSVs via `mirror_internalempire_ccs_cost_omission`.

Usage:
    python scripts/test_ccs_cost_variable_conversion.py
    python scripts/test_ccs_cost_variable_conversion.py --source <dir with Generator.xlsx>

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

SHEET = "CCSCostTSVariable"
PERIODS = 7


def _default_source() -> Path:
    candidates = [
        Path.home() / "OpenEMPIRE" / "NorthSea_NECPEssentials",
        Path.home() / "OpenEMPIRE_Data_Raw" / "NorthSea" / "NorthSea_NECPEssentials",
        _HERE.parents[2] / "OpenEMPIRE" / "NorthSea_NECPEssentials",
    ]
    for c in candidates:
        if (c / "Generator.xlsx").is_file():
            return c
    return candidates[0]


def _entry():
    for sheet, usecols, component, filename in conv.CORE_TABLES["Generator.xlsx"]:
        if sheet == SHEET:
            return sheet, usecols, component, filename
    raise AssertionError(f"{SHEET!r} not in CORE_TABLES['Generator.xlsx']")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=_default_source())
    args = ap.parse_args()
    source = args.source
    if not (source / "Generator.xlsx").is_file():
        print(f"SKIP: no Generator.xlsx under {source}")
        return 0

    sheet, usecols, component, filename = _entry()
    excel = pd.ExcelFile(source / "Generator.xlsx")

    raw = pd.read_excel(source / "Generator.xlsx", sheet, header=2).iloc[:, usecols].dropna()
    src = {int(r.iloc[0]): float(r.iloc[1]) for _, r in raw.iterrows()}

    with tempfile.TemporaryDirectory() as td:
        conv_raw = conv.read_sheet(excel, sheet, skiprows=2)
        selected, dropped = conv.select_table(conv_raw, usecols, PERIODS)
        assert dropped.empty, f"unexpected Period>{PERIODS} rows: {len(dropped)}"
        out_csv = Path(td) / f"{filename}.csv"
        conv.write_csv(conv.finalize(selected), out_csv)
        df = pd.read_csv(out_csv)
        got = {int(p): float(v) for p, v in zip(df.iloc[:, 0], df.iloc[:, 1])}

    errors: list[str] = []
    if sorted(src) != sorted(got) or sorted(got) != list(range(1, PERIODS + 1)):
        errors.append(f"period keys differ: excel={sorted(src)} csv={sorted(got)}")
    if len(got) != PERIODS:
        errors.append(f"expected {PERIODS} rows, got {len(got)}")
    for p in sorted(set(src) & set(got)):
        if src[p] != got[p]:
            errors.append(f"period {p}: excel={src[p]!r} csv={got[p]!r}")
    if any(v == 0.0 for v in got.values()):
        errors.append("python-nuts conversion must NOT zero CCSCostTSVariable")

    # internalempire mode still zeroes (sanity on the mode switch)
    with tempfile.TemporaryDirectory() as td:
        gen = Path(td) / "Generator"
        gen.mkdir(parents=True)
        pd.DataFrame({"Period": range(1, PERIODS + 1),
                      "CCS_TScost_in_euro_per_tCO2": list(src.values())}).to_csv(
            gen / "CCSCostTSVariable.csv", index=False)
        conv.mirror_internalempire_ccs_cost_omission(Path(td), "internalempire")
        z = pd.read_csv(gen / "CCSCostTSVariable.csv")
        if not (z.iloc[:, -1] == 0.0).all():
            errors.append("internalempire mode did not zero CCSCostTSVariable")
        if not (gen / "CCSCostTSFixed.csv").is_file():
            errors.append("internalempire mode did not write CCSCostTSFixed.csv")
        else:
            f = pd.read_csv(gen / "CCSCostTSFixed.csv")
            if float(f.iloc[0, 0]) != 0.0:
                errors.append("internalempire CCSCostTSFixed.csv is not 0.0")

    # python-nuts mode writes no CCSCostTSFixed.csv and leaves variable untouched
    with tempfile.TemporaryDirectory() as td:
        gen = Path(td) / "Generator"
        gen.mkdir(parents=True)
        pd.DataFrame({"Period": range(1, PERIODS + 1),
                      "CCS_TScost_in_euro_per_tCO2": list(src.values())}).to_csv(
            gen / "CCSCostTSVariable.csv", index=False)
        conv.mirror_internalempire_ccs_cost_omission(Path(td), "python-nuts")
        z = pd.read_csv(gen / "CCSCostTSVariable.csv")
        if not all(z.iloc[:, -1] == list(src.values())):
            errors.append("python-nuts mode altered CCSCostTSVariable values")
        if (gen / "CCSCostTSFixed.csv").is_file():
            errors.append("python-nuts mode must not write CCSCostTSFixed.csv")

    if errors:
        print("FAIL: CCSCostTSVariable conversion / mode regression")
        for e in errors:
            print("  -", e)
        return 1

    print(f"PASS: CCSCostTSVariable conversion + mode regression ({PERIODS} periods, exact values)")
    for p in sorted(src):
        print(f"    period {p} -> {src[p]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
