#!/usr/bin/env python3
"""Focused tests for the full Hydrogen/CO2 result verifier."""

from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
VERIFIER_PATH = ROOT / "scripts" / "compare_internalempire_hydrogen_results.py"
SPEC = importlib.util.spec_from_file_location("hydrogen_verifier", VERIFIER_PATH)
assert SPEC is not None and SPEC.loader is not None
VERIFIER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VERIFIER
SPEC.loader.exec_module(VERIFIER)
RUNNER_PATH = ROOT / "scripts" / "run_internalempire_hydrogen.py"
RUNNER_SPEC = importlib.util.spec_from_file_location("hydrogen_internal_runner", RUNNER_PATH)
assert RUNNER_SPEC is not None and RUNNER_SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
sys.modules[RUNNER_SPEC.name] = RUNNER
RUNNER_SPEC.loader.exec_module(RUNNER)


def write_table(path: Path, delimiter: str, header: tuple[str, ...], row: tuple[object, ...]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, delimiter=delimiter)
        writer.writerow(header)
        writer.writerow(row)


class HydrogenResultVerifierTests(unittest.TestCase):
    def test_reference_wrapper_retains_solved_instance_for_certificate(self) -> None:
        source = "def run_empire():\n    del results, instance, model\n"
        patched = RUNNER.retain_instance_for_certificate(source)
        self.assertIn("    return instance\n", patched)
        self.assertNotIn("del results, instance, model", patched)

    def test_capacity_comparison_aggregates_corridors_and_ignores_sparse_zeros(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            internal = root / "internal"
            julia = root / "julia"
            internal.mkdir()
            julia.mkdir()
            write_table(
                internal / "capacity.tab",
                "\t",
                ("FromNode", "ToNode", "Period", "capacity"),
                ("A", "B", 1, 2),
            )
            with (internal / "capacity.tab").open("a", encoding="utf-8") as handle:
                handle.write("B\tA\t1\t3\n")
                handle.write("A\tC\t1\t0\n")
            write_table(
                julia / "capacity.csv",
                ",",
                ("FromNode", "ToNode", "Period", "capacity"),
                ("A", "B", 1, 5),
            )
            spec = VERIFIER.CapacitySpec(
                "capacity",
                "capacity.tab",
                "capacity.csv",
                ("FromNode", "ToNode", "Period"),
                "capacity",
                True,
            )
            with mock.patch.object(VERIFIER, "CAPACITY_SPECS", (spec,)):
                ok, lines = VERIFIER.compare_capacities(
                    internal, julia, atol=1e-3, rtol=1e-6, top=10
                )
            self.assertTrue(ok)
            self.assertIn("keys(ie=2,jl=1,missing=0,extra=0)", lines[0])
            self.assertIn("ie_only=1", lines[1])

    def test_gurobi_certification_and_suboptimal_failure_are_parsed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            common = (
                "Optimize a model with 100 rows, 200 columns and 300 nonzeros\n"
                "Presolved: 10 rows, 20 columns, 30 nonzeros\n"
                "   5   1.00000000e+03  9.99990000e+02  1.00e-04  2.00e-04  3.00e-05  12s\n"
            )
            optimal = root / "optimal.log"
            optimal.write_text(
                common
                + "Barrier solved model in 5 iterations and 12.00 seconds\n"
                + "Optimal objective 1.000000000e+03\n",
                encoding="utf-8",
            )
            audit = VERIFIER.parse_gurobi_audit(optimal)
            self.assertTrue(audit.certified_optimal)
            self.assertEqual((audit.raw_rows, audit.raw_columns, audit.raw_nonzeros), (100, 200, 300))
            self.assertEqual(
                (audit.presolved_rows, audit.presolved_columns, audit.presolved_nonzeros),
                (10, 20, 30),
            )
            self.assertEqual(audit.barrier_primal_residual, 1e-4)
            self.assertEqual(audit.final_objective, 1000.0)

            suboptimal = root / "suboptimal.log"
            suboptimal.write_text(
                common + "Sub-optimal termination - objective 1.000000000e+03\n",
                encoding="utf-8",
            )
            failed_audit = VERIFIER.parse_gurobi_audit(suboptimal)
            self.assertFalse(failed_audit.certified_optimal)
            self.assertEqual(failed_audit.final_objective, 1000.0)

    def test_all_stable_capacity_families_compare_by_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            internal = root / "internal"
            julia = root / "julia"
            internal.mkdir()
            julia.mkdir()
            for spec in VERIFIER.CAPACITY_SPECS:
                keys = tuple(f"key{index}" for index in range(len(spec.key_columns)))
                internal_keys = keys
                julia_keys = keys
                if spec.undirected_pair:
                    julia_keys = (keys[1], keys[0], *keys[2:])
                write_table(
                    internal / spec.internal_file,
                    "\t",
                    (*spec.key_columns, spec.value_column),
                    (*internal_keys, 123.5),
                )
                write_table(
                    julia / spec.julia_file,
                    ",",
                    (*spec.key_columns, spec.value_column),
                    (*julia_keys, 123.5),
                )

            ok, lines = VERIFIER.compare_capacities(internal, julia, 1e-3, 1e-5, 3)
            self.assertTrue(ok)
            self.assertEqual(len([line for line in lines if line.endswith("max_abs=0")]), len(VERIFIER.CAPACITY_SPECS))

            first = VERIFIER.CAPACITY_SPECS[0]
            keys = tuple(f"key{index}" for index in range(len(first.key_columns)))
            write_table(
                julia / first.julia_file,
                ",",
                (*first.key_columns, first.value_column),
                (*keys, 125.5),
            )
            ok, _ = VERIFIER.compare_capacities(internal, julia, 1e-3, 1e-5, 3)
            self.assertFalse(ok)

            (julia / first.julia_file).unlink()
            ok, lines = VERIFIER.compare_capacities(internal, julia, 1e-3, 1e-5, 3)
            self.assertFalse(ok)
            self.assertTrue(any("MISSING" in line for line in lines))

    def test_objective_certificates_and_cost_reports(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            certificate = root / "objective_components.csv"
            with certificate.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow(("component", "value"))
                for index, name in enumerate(VERIFIER.OBJECTIVE_COMPONENTS, start=1):
                    writer.writerow((name, index))
            components = VERIFIER.internal_components(certificate)
            self.assertEqual(tuple(components), VERIFIER.OBJECTIVE_COMPONENTS)
            self.assertEqual(sum(components.values()), 78.0)

            hydrogen_report = root / "results_hydrogen_costs.csv"
            header = (
                "Period",
                "Discounted electrolyzer cost [EUR]",
                "Discounted Reformer cost [EUR]",
                "Discounted pipeline cost [EUR]",
                "Discounted storage cost [EUR]",
                "Discounted H2 import cost [EUR]",
                "Total discounted cost [EUR]",
            )
            write_table(hydrogen_report, ",", header, ("2050-2055", 1, 2, 3, 4, 5, 15))
            report = VERIFIER.hydrogen_investment_report(hydrogen_report)
            self.assertEqual(report["reported_hydrogen_investment"], 15.0)

            transmission_report = root / "results_transmission_inv_costs.csv"
            write_table(
                transmission_report,
                ",",
                (
                    "FromNode",
                    "ToNode",
                    "Period",
                    "TransmissionInvCost",
                    "HydrogenPipelineInvCost",
                    "RepurposedPipeilineInvCost",
                    "CO2PipelineInvCost",
                ),
                ("A", "B", "2050-2055", 10, 20, 30, 40),
            )
            transmission = VERIFIER.transmission_report_components(transmission_report)
            self.assertEqual(transmission["transmission_investment"], 10.0)
            self.assertEqual(transmission["co2_pipeline_investment"], 40.0)

    def test_missing_component_certificate_remains_a_failure_without_stopping_audit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            internal = root / "internal"
            julia_run = root / "julia"
            output = julia_run / "output"
            internal.mkdir()
            output.mkdir(parents=True)

            (internal / "results_objective.csv").write_text(
                "Objective function value:1000\n", encoding="utf-8"
            )
            summary_lines = [
                "objective_value=1000",
                "termination_status=OPTIMAL",
                *(f"objective_component_{name}=1" for name in VERIFIER.OBJECTIVE_COMPONENTS),
            ]
            (julia_run / "summary.txt").write_text(
                "\n".join(summary_lines) + "\n", encoding="utf-8"
            )
            log = root / "solver.log"
            log.write_text(
                "Optimize a model with 100 rows, 200 columns and 300 nonzeros\n"
                "Presolved: 10 rows, 20 columns, 30 nonzeros\n"
                "   5   1.00000000e+03  9.99990000e+02  1.00e-04  2.00e-04  3.00e-05  12s\n"
                "Barrier solved model in 5 iterations and 12.00 seconds\n"
                "Optimal objective 1.000000000e+03\n",
                encoding="utf-8",
            )
            args = [
                "verify",
                "--internal-results", str(internal),
                "--internal-components", str(root / "missing.csv"),
                "--julia-run", str(julia_run),
                "--internal-log", str(log),
                "--julia-log", str(log),
            ]
            reports = {
                "generator_investment": 1.0,
                "storage_investment": 1.0,
                "transmission_investment": 1.0,
                "offshore_converter_investment": 1.0,
                "generator_operation": 1.0,
            }
            transmission = {
                "transmission_investment": 1.0,
                "hydrogen_pipeline_investment": 1.0,
                "repurposed_pipeline_investment": 1.0,
                "co2_pipeline_investment": 1.0,
            }
            hydrogen = {
                "electrolyzer_investment": 1.0,
                "reformer_investment": 1.0,
                "hydrogen_pipeline_investment": 1.0,
                "hydrogen_storage_investment": 1.0,
                "hydrogen_import_investment": 1.0,
                "reported_hydrogen_investment": 5.0,
            }
            with (
                mock.patch.object(sys, "argv", args),
                mock.patch.object(VERIFIER, "investment_components", return_value=reports),
                mock.patch.object(VERIFIER, "generator_operation_component", return_value=1.0),
                mock.patch.object(VERIFIER, "transmission_report_components", return_value=transmission),
                mock.patch.object(VERIFIER, "hydrogen_investment_report", return_value=hydrogen),
                mock.patch.object(VERIFIER, "compare_capacities", return_value=(True, ["capacities: OK"])),
            ):
                self.assertEqual(VERIFIER.main(), 1)


if __name__ == "__main__":
    unittest.main()
