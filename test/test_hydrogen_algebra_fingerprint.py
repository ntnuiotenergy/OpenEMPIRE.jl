#!/usr/bin/env python3
"""Dependency-free regression tests for Hydrogen algebra fingerprints."""

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import compare_hydrogen_algebra_fingerprints as compare  # noqa: E402
import hydrogen_algebra_fingerprint as fingerprint  # noqa: E402


class HydrogenAlgebraFingerprintTests(unittest.TestCase):
    def test_normalized_rows_ignore_uniform_scale_and_sign(self) -> None:
        first = fingerprint._normalized_records(
            "flow_balance|A|sp1_rp1_sc1_t1", "<=", 6.0, {"x": 2.0, "y": -4.0}
        )
        second = fingerprint._normalized_records(
            "flow_balance|A|sp1_rp1_sc1_t1", ">=", -18.0, {"x": -6.0, "y": 12.0}
        )
        self.assertEqual(first, second)

    def test_multiset_digest_is_order_independent_and_mutation_sensitive(self) -> None:
        records = ("row-a", "row-b", "row-c")
        forward = fingerprint.Accumulator()
        reverse = fingerprint.Accumulator()
        changed = fingerprint.Accumulator()
        for record in records:
            forward.add(record, 2)
        for record in reversed(records):
            reverse.add(record, 2)
        for record in (*records[:-1], "row-C"):
            changed.add(record, 2)
        self.assertEqual(forward.fields(), reverse.fields())
        self.assertNotEqual(forward.fields(), changed.fields())

    def test_internal_hour_key_matches_julia_component_order(self) -> None:
        canonicalizer = object.__new__(fingerprint.InternalCanonicalizer)
        canonicalizer.hour_context = {25: (2, 1)}
        self.assertEqual(
            canonicalizer.time_key({"h": 25, "i": 3, "w": "scenario4", "gp": 1}),
            "sp3_rp2_sc4_t1",
        )
        self.assertEqual(
            canonicalizer.time_key(
                {"h": 25, "i": 3, "w": "scenario4", "gp": 1}, drop_hour=True
            ),
            "sp3_rp2_sc4",
        )

    def test_written_format_round_trips_and_malformed_input_fails(self) -> None:
        fingerprints = fingerprint.Fingerprints()
        key = "flow_balance|A|sp1_rp1_sc1_t1"
        fingerprints.add("row", "flow_balance", key, {9: key, 12: key}, 3)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fingerprint.tsv"
            fingerprints.write(path, {"schema": 1, "side": "test"})
            parsed = compare.read_fingerprint(path)
            self.assertEqual(parsed["metadata"]["side"], "test")
            self.assertEqual(parsed["summaries"][("row", "flow_balance", 12)][0], "1")
            path.write_text("SUMMARY\ttoo\tshort\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                compare.read_fingerprint(path)


if __name__ == "__main__":
    unittest.main()
