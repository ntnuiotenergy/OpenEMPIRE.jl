#!/usr/bin/env python3
"""Dependency-free negative controls for Industry algebra fingerprints."""

from __future__ import annotations

import random
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import algebra_fingerprint as core  # noqa: E402
import compare_industry_algebra_fingerprints as compare  # noqa: E402
import industry_algebra_fingerprint as industry  # noqa: E402


def complete_fingerprint() -> core.Fingerprints:
    fingerprint = core.Fingerprints()
    for kind, group in compare.required_groups():
        fingerprint.ensure(kind, group)
    return fingerprint


class IndustryAlgebraFingerprintTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.left = root / "left.fingerprint"
        self.right = root / "right.fingerprint"
        self.metadata = {
            "schema": 1,
            "side": "test",
            "scope": "industry",
            "precisions": "9,12",
            "buckets": 256,
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_pair(
        self, left: core.Fingerprints, right: core.Fingerprints
    ) -> list[str]:
        left.write(self.left, self.metadata)
        right.write(self.right, self.metadata)
        failures, _, _, _ = compare.compare(self.left, self.right, 12)
        return failures

    def test_uniform_row_scale_and_sign_are_ignored(self) -> None:
        first = core.normalized_records("row", "<=", 6.0, {"x": 2.0, "y": -4.0})
        second = core.normalized_records("row", ">=", -18.0, {"x": -6.0, "y": 12.0})
        self.assertEqual(first, second)

    def test_order_is_ignored(self) -> None:
        left = complete_fingerprint()
        right = complete_fingerprint()
        records = ["record-a", "record-b", "record-c"]
        for record in records:
            left.add("row", "steel_capacity", record, {9: record, 12: record}, 2)
        for record in reversed(records):
            right.add("row", "steel_capacity", record, {9: record, 12: record}, 2)
        self.assertEqual(self.write_pair(left, right), [])

    def assert_mutation_rejected(
        self,
        kind: str,
        group: str,
        original: dict[int, str],
        changed: dict[int, str],
    ) -> None:
        left = complete_fingerprint()
        right = complete_fingerprint()
        left.add(kind, group, "key", original, 1)
        right.add(kind, group, "key", changed, 1)
        self.assertTrue(self.write_pair(left, right))

    def test_changed_coefficient_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "row",
            "steel_capacity",
            core.normalized_records("key", "<=", 1.0, {"x": 2.0, "y": 3.0}),
            core.normalized_records("key", "<=", 1.0, {"x": 2.1, "y": 3.0}),
        )

    def test_changed_rhs_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "row",
            "steel_demand",
            core.normalized_records("key", "==", 4.0, {"x": 1.0}),
            core.normalized_records("key", "==", 4.1, {"x": 1.0}),
        )

    def test_changed_bounds_are_rejected(self) -> None:
        self.assert_mutation_rejected(
            "variable",
            "steel_production",
            core.raw_records("key", (0.0, float("inf"))),
            core.raw_records("key", (0.0, 9.0)),
        )

    def test_changed_objective_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "objective",
            "steel_operation",
            core.raw_records("key", (3.0,)),
            core.raw_records("key", (3.01,)),
        )

    def test_missing_required_group_is_rejected(self) -> None:
        fingerprint = complete_fingerprint()
        fingerprint.write(self.left, self.metadata)
        lines = self.left.read_text(encoding="utf-8").splitlines()
        self.right.write_text(
            "\n".join(
                line
                for line in lines
                if not line.startswith("SUMMARY\trow\tsteel_capacity\t")
            )
            + "\n",
            encoding="utf-8",
        )
        failures, _, _, _ = compare.compare(self.left, self.right, 12)
        self.assertTrue(any("missing required groups" in failure for failure in failures))

    def test_malformed_input_is_rejected(self) -> None:
        self.left.write_text("SUMMARY\ttoo\tshort\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            compare.read_fingerprint(self.left)

    def test_file_line_order_is_irrelevant(self) -> None:
        fingerprint = complete_fingerprint()
        fingerprint.add(
            "row",
            "steel_capacity",
            "key",
            core.normalized_records("key", "<=", 1.0, {"x": 1.0}),
            1,
        )
        fingerprint.write(self.left, self.metadata)
        lines = self.left.read_text(encoding="utf-8").splitlines()
        random.Random(7).shuffle(lines)
        self.right.write_text("\n".join(lines) + "\n", encoding="utf-8")
        failures, _, _, _ = compare.compare(self.left, self.right, 12)
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
