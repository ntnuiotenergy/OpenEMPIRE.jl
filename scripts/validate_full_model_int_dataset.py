#!/usr/bin/env python3
"""Validate the versioned full_model_int CSV dataset and gas-module inputs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Iterable


SCHEMAS = {
    "Sets/NaturalGasNodes.csv": ("NaturalGasNodes",),
    "Sets/NaturalGasDirectionalLines.csv": ("NodeFrom", "NodeTo"),
    "Sets/NaturalGasTerminals.csv": ("NaturalGasTerminals",),
    "Sets/NaturalGasTerminalsOfNode.csv": ("Node", "NG_Terminal_Type"),
    "Sets/OnshoreNode.csv": ("OnshoreNode",),
    "NaturalGas/PipelineCapacity.csv": (
        "FromNode",
        "ToNode",
        "Capacity_(ton/h)",
    ),
    "NaturalGas/PipelineElectricityUse.csv": ("Power_usage_[MWh/ton]",),
    "NaturalGas/Reserves.csv": ("Node", "Reserves_(tons)"),
    "NaturalGas/StorageCapacity.csv": ("Node", "Storage_(ton)"),
    "NaturalGas/TerminalCapacity.csv": (
        "Node",
        "Terminal",
        "Period",
        "Capacity_(ton/hr)",
    ),
    "NaturalGas/TerminalCost.csv": (
        "Node",
        "Terminal",
        "Period",
        "Scenario",
        "Cost_(EUR/ton)",
    ),
    "NaturalGas/TerminalCost_stochastic.csv": (
        "Node",
        "Terminal",
        "Period",
        "GasScenario",
        "Cost_(EUR/ton)",
    ),
    "NaturalGas/reserves_duplicate_audit.csv": (
        "Table",
        "Node",
        "DiscardedSourceRow",
        "DiscardedValue",
        "SelectedSourceRow",
        "SelectedValue",
        "ValuesDiffer",
    ),
    "NaturalGas/terminal_cost_duplicate_audit.csv": (
        "Table",
        "Node",
        "Terminal",
        "Period",
        "GasScenario",
        "DiscardedSourceRow",
        "DiscardedValue",
        "SelectedSourceRow",
        "SelectedValue",
        "ValuesDiffer",
    ),
    "Transport/NaturalGasDemand.csv": (
        "Node",
        "Period",
        "Natural_gas_demand_[MWh/yr]",
    ),
    "Transport/CurtailCost.csv": ("CurtailCost_(€/MWh)",),
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_csv(dataset: Path, relative: str) -> list[dict[str, str]]:
    path = dataset / relative
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        actual = tuple(reader.fieldnames or ())
        expected = SCHEMAS.get(relative)
        if expected is not None and actual != expected:
            fail(f"{path}: expected schema {expected}, got {actual}")
        return list(reader)


def unique_keys(
    dataset: Path,
    relative: str,
    columns: tuple[str, ...],
) -> tuple[list[dict[str, str]], set[tuple[str, ...]]]:
    rows = read_csv(dataset, relative)
    keys: set[tuple[str, ...]] = set()
    for row_number, row in enumerate(rows, start=2):
        key = tuple(row[column] for column in columns)
        if key in keys:
            fail(f"{dataset / relative}: duplicate key at row {row_number}: {key}")
        keys.add(key)
    return rows, keys


def finite_nonnegative(
    dataset: Path,
    relative: str,
    rows: Iterable[dict[str, str]],
    columns: tuple[str, ...],
) -> None:
    for row_number, row in enumerate(rows, start=2):
        for column in columns:
            raw = row[column]
            try:
                value = float(raw)
            except ValueError as error:
                fail(
                    f"{dataset / relative}: row {row_number} column {column} "
                    f"is not numeric: {raw!r}"
                )
                raise AssertionError from error
            if not math.isfinite(value):
                fail(
                    f"{dataset / relative}: row {row_number} column {column} "
                    f"must be finite: {raw!r}"
                )
            if value < 0:
                fail(
                    f"{dataset / relative}: row {row_number} column {column} "
                    f"must be non-negative: {raw!r}"
                )


def integer_column(
    dataset: Path,
    relative: str,
    rows: Iterable[dict[str, str]],
    column: str,
    allowed: set[int],
) -> None:
    for row_number, row in enumerate(rows, start=2):
        raw = row[column]
        try:
            value = int(raw)
        except ValueError as error:
            fail(
                f"{dataset / relative}: row {row_number} column {column} "
                f"must be an integer: {raw!r}"
            )
            raise AssertionError from error
        if value not in allowed:
            fail(
                f"{dataset / relative}: row {row_number} column {column} "
                f"has {value}; allowed values are {sorted(allowed)}"
            )


def single_column_set(dataset: Path, relative: str, column: str) -> set[str]:
    rows = read_csv(dataset, relative)
    values = {row[column] for row in rows}
    if len(values) != len(rows):
        fail(f"{dataset / relative}: duplicate values in {column}")
    return values


def validate_manifest(dataset: Path) -> dict[str, object]:
    manifest_path = dataset / "conversion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entries = manifest["files"]
    listed: set[str] = set()
    for entry in entries:
        relative = entry["path"]
        if relative in listed:
            fail(f"{manifest_path}: duplicate file entry {relative}")
        listed.add(relative)
        path = dataset / relative
        if not path.is_file():
            fail(f"{manifest_path}: missing listed file {relative}")
        payload = path.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if digest != entry["sha256"]:
            fail(
                f"{manifest_path}: SHA-256 mismatch for {relative}; "
                f"expected {entry['sha256']}, got {digest}"
            )
        if len(payload) != entry["bytes"]:
            fail(
                f"{manifest_path}: byte-count mismatch for {relative}; "
                f"expected {entry['bytes']}, got {len(payload)}"
            )
        if path.suffix == ".csv":
            with path.open(newline="", encoding="utf-8") as handle:
                row_count = sum(1 for _ in csv.reader(handle)) - 1
            if row_count != entry["rows"]:
                fail(
                    f"{manifest_path}: row-count mismatch for {relative}; "
                    f"expected {entry['rows']}, got {row_count}"
                )
    actual = {
        path.relative_to(dataset).as_posix()
        for path in dataset.rglob("*")
        if path.is_file() and path.name != manifest_path.name
    }
    if listed != actual:
        fail(
            f"{manifest_path}: file inventory mismatch; "
            f"unlisted={sorted(actual - listed)}, missing={sorted(listed - actual)}"
        )
    return manifest


def validate_gas_tables(dataset: Path, manifest: dict[str, object]) -> None:
    periods = set(range(1, int(manifest["periods"]) + 1))
    core_nodes = single_column_set(dataset, "Sets/Node.csv", "Node")
    gas_nodes = single_column_set(
        dataset,
        "Sets/NaturalGasNodes.csv",
        "NaturalGasNodes",
    )
    onshore_nodes = single_column_set(dataset, "Sets/OnshoreNode.csv", "OnshoreNode")
    terminals = single_column_set(
        dataset,
        "Sets/NaturalGasTerminals.csv",
        "NaturalGasTerminals",
    )
    if not gas_nodes <= core_nodes:
        fail(f"Natural-gas nodes absent from Sets/Node.csv: {sorted(gas_nodes-core_nodes)}")
    if not onshore_nodes <= gas_nodes:
        fail(f"Onshore gas nodes absent from gas-node set: {sorted(onshore_nodes-gas_nodes)}")

    link_rows, links = unique_keys(
        dataset,
        "Sets/NaturalGasDirectionalLines.csv",
        ("NodeFrom", "NodeTo"),
    )
    for row in link_rows:
        if row["NodeFrom"] not in gas_nodes or row["NodeTo"] not in gas_nodes:
            fail(f"Natural-gas link references an unknown node: {row}")

    pair_rows, terminal_pairs = unique_keys(
        dataset,
        "Sets/NaturalGasTerminalsOfNode.csv",
        ("Node", "NG_Terminal_Type"),
    )
    for row in pair_rows:
        if row["Node"] not in gas_nodes:
            fail(f"Terminal pair references an unknown node: {row}")
        if row["NG_Terminal_Type"] not in terminals:
            fail(f"Terminal pair references an unknown terminal: {row}")

    pipeline_rows, pipeline_keys = unique_keys(
        dataset,
        "NaturalGas/PipelineCapacity.csv",
        ("FromNode", "ToNode"),
    )
    finite_nonnegative(
        dataset,
        "NaturalGas/PipelineCapacity.csv",
        pipeline_rows,
        ("Capacity_(ton/h)",),
    )
    if pipeline_keys != links:
        fail(
            "Pipeline-capacity keys are incomplete or unexpected: "
            f"missing={sorted(links-pipeline_keys)}, extra={sorted(pipeline_keys-links)}"
        )

    scalar_tables = (
        ("NaturalGas/PipelineElectricityUse.csv", "Power_usage_[MWh/ton]"),
        ("Transport/CurtailCost.csv", "CurtailCost_(€/MWh)"),
    )
    for relative, column in scalar_tables:
        rows = read_csv(dataset, relative)
        if len(rows) != 1:
            fail(f"{dataset / relative}: expected exactly one data row")
        finite_nonnegative(dataset, relative, rows, (column,))

    reserve_rows, reserve_keys = unique_keys(
        dataset,
        "NaturalGas/Reserves.csv",
        ("Node",),
    )
    finite_nonnegative(
        dataset,
        "NaturalGas/Reserves.csv",
        reserve_rows,
        ("Reserves_(tons)",),
    )
    reserve_nodes = {key[0] for key in reserve_keys}
    if not reserve_nodes <= gas_nodes:
        fail("NaturalGas/Reserves.csv contains an unknown node")
    expected_reserve_nodes = {
        node
        for node, terminal in terminal_pairs
        if terminal.lower() in {"domesticproduction", "pipelineimport"}
    }
    if reserve_nodes != expected_reserve_nodes:
        fail(
            "NaturalGas/Reserves.csv is incomplete or has unexpected nodes: "
            f"missing={sorted(expected_reserve_nodes-reserve_nodes)}, "
            f"extra={sorted(reserve_nodes-expected_reserve_nodes)}"
        )

    storage_rows, storage_keys = unique_keys(
        dataset,
        "NaturalGas/StorageCapacity.csv",
        ("Node",),
    )
    finite_nonnegative(
        dataset,
        "NaturalGas/StorageCapacity.csv",
        storage_rows,
        ("Storage_(ton)",),
    )
    if not {key[0] for key in storage_keys} <= gas_nodes:
        fail("NaturalGas/StorageCapacity.csv contains an unknown node")

    terminal_capacity_rows, terminal_capacity_keys = unique_keys(
        dataset,
        "NaturalGas/TerminalCapacity.csv",
        ("Node", "Terminal", "Period"),
    )
    finite_nonnegative(
        dataset,
        "NaturalGas/TerminalCapacity.csv",
        terminal_capacity_rows,
        ("Capacity_(ton/hr)",),
    )
    integer_column(
        dataset,
        "NaturalGas/TerminalCapacity.csv",
        terminal_capacity_rows,
        "Period",
        periods,
    )
    expected_terminal_periods = {
        (node, terminal, str(period))
        for node, terminal in terminal_pairs
        for period in periods
    }
    if terminal_capacity_keys != expected_terminal_periods:
        fail("NaturalGas/TerminalCapacity.csv is incomplete or has unexpected keys")

    cost_tables = (
        ("NaturalGas/TerminalCost.csv", "Scenario"),
        ("NaturalGas/TerminalCost_stochastic.csv", "GasScenario"),
    )
    cost_rows_by_table: dict[str, dict[tuple[str, str, str, str], float]] = {}
    for relative, scenario_column in cost_tables:
        rows, keys = unique_keys(
            dataset,
            relative,
            ("Node", "Terminal", "Period", scenario_column),
        )
        finite_nonnegative(dataset, relative, rows, ("Cost_(EUR/ton)",))
        integer_column(dataset, relative, rows, "Period", periods)
        integer_column(dataset, relative, rows, scenario_column, {1})
        expected = {
            (node, terminal, str(period), "1")
            for node, terminal in terminal_pairs
            for period in periods
        }
        if keys != expected:
            fail(f"{dataset / relative}: incomplete or unexpected terminal costs")
        cost_rows_by_table[Path(relative).stem] = {
            (row["Node"], row["Terminal"], row["Period"], row[scenario_column]): float(
                row["Cost_(EUR/ton)"]
            )
            for row in rows
        }

    transport_rows, transport_keys = unique_keys(
        dataset,
        "Transport/NaturalGasDemand.csv",
        ("Node", "Period"),
    )
    finite_nonnegative(
        dataset,
        "Transport/NaturalGasDemand.csv",
        transport_rows,
        ("Natural_gas_demand_[MWh/yr]",),
    )
    integer_column(
        dataset,
        "Transport/NaturalGasDemand.csv",
        transport_rows,
        "Period",
        periods,
    )
    expected_transport = {
        (node, str(period)) for node in onshore_nodes for period in periods
    }
    if transport_keys != expected_transport:
        fail("Transport/NaturalGasDemand.csv is incomplete or has unexpected keys")

    terminal_audit = read_csv(
        dataset,
        "NaturalGas/terminal_cost_duplicate_audit.csv",
    )
    if len(terminal_audit) != int(manifest["terminal_cost_duplicate_keys_total"]):
        fail("Terminal-cost duplicate audit count differs from conversion manifest")
    differing = sum(row["ValuesDiffer"] == "True" for row in terminal_audit)
    if differing != int(manifest["terminal_cost_conflicting_keys"]):
        fail("Terminal-cost conflicting-key count differs from conversion manifest")
    corrections = manifest.get("owner_confirmed_corrections", {}).get("rules", [])

    def corrected_value(table, terminal, period):
        """Owner-confirmed value that intentionally overrides the workbook, if any."""
        for rule in corrections:
            if table in rule["tables"] and terminal == rule["terminal"]:
                return rule["values_by_period"].get(str(period))
        return None

    for row in terminal_audit:
        key = (
            row["Node"],
            row["Terminal"],
            row["Period"],
            row["GasScenario"],
        )
        selected = cost_rows_by_table[row["Table"]][key]
        override = corrected_value(row["Table"], row["Terminal"], row["Period"])
        if override is not None:
            # The audit still records what the workbook said; the CSV deliberately
            # carries the corrected value instead. Check that, not last-row-wins.
            if selected != override:
                fail(
                    f"Owner-confirmed correction not applied for {row['Table']} "
                    f"key {key}: expected {override}, found {selected}"
                )
        elif selected != float(row["SelectedValue"]):
            fail(f"Last-source-row-wins mismatch for {row['Table']} key {key}")

    # Every row covered by a correction rule must carry the corrected value, not only
    # the ones that happened to be duplicated in the workbook.
    for rule in corrections:
        for table in rule["tables"]:
            for (node, terminal, period, gas_scenario), value in cost_rows_by_table[
                table
            ].items():
                if terminal != rule["terminal"]:
                    continue
                want = rule["values_by_period"].get(str(period))
                if want is None:
                    fail(f"{table}: {terminal} has unexpected period {period}")
                if value != want:
                    fail(
                        f"{table}: {terminal} at {node} period {period} is {value}, "
                        f"expected the owner-confirmed {want}"
                    )

    reserve_audit = read_csv(dataset, "NaturalGas/reserves_duplicate_audit.csv")
    if len(reserve_audit) != int(manifest["reserve_duplicate_keys"]):
        fail("Reserve duplicate audit count differs from conversion manifest")
    reserve_values = {row["Node"]: float(row["Reserves_(tons)"]) for row in reserve_rows}
    for row in reserve_audit:
        if reserve_values[row["Node"]] != float(row["SelectedValue"]):
            fail(f"Last-source-row-wins reserve mismatch for node {row['Node']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "dataset",
        type=Path,
        nargs="?",
        default=Path("data/full_model_int"),
    )
    args = parser.parse_args()
    dataset = args.dataset.resolve()
    manifest = validate_manifest(dataset)
    validate_gas_tables(dataset, manifest)
    print(
        "full_model_int validation: PASS "
        f"({len(manifest['files'])} files, {manifest['periods']} periods, "
        f"{manifest['terminal_cost_duplicate_keys_total']} audited terminal-cost "
        f"duplicates, {manifest['reserve_duplicate_keys']} audited reserve duplicate)"
    )


if __name__ == "__main__":
    main()
