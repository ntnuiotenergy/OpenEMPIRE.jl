#!/usr/bin/env python3
"""Focused tests for mandatory full Industry reconciliation gates."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from compare_internalempire_industry_results import reconciled


def main() -> None:
    assert reconciled(1.0e9, 1.0e9 + 10_000.0, atol=10.0, ppm=20.0)
    assert not reconciled(1.0e9, 1.0e9 + 30_000.0, atol=10.0, ppm=20.0)
    assert reconciled(1.0, 9.0, atol=10.0, ppm=20.0)
    assert not reconciled(0.0, 11.0, atol=10.0, ppm=20.0)
    assert reconciled(0.0, 0.0, atol=0.001, ppm=20.0)
    assert reconciled(1.0e8, 1.0e8 + 0.001, atol=0.001, ppm=20.0)
    assert not reconciled(1.0e8, 1.0e8 + 3_000.0, atol=0.001, ppm=20.0)
    print("Industry verifier reconciliation gates: PASS")


if __name__ == "__main__":
    main()
