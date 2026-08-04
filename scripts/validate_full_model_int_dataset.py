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
    "Hydrogen/Constants.csv": ("Parameter", "Value", "Unit", "Source"),
    "Hydrogen/HydrogenGenerators.csv": ("HydrogenGenerator",),
    "Hydrogen/ProductionNodes.csv": ("ProductionNodes",),
    "Hydrogen/ReformerLocations.csv": ("ReformerLocations",),
    "Hydrogen/ReformerPlants.csv": ("ReformerPlants",),
    "Hydrogen/H2Storages.csv": ("H2Storages",),
    "Hydrogen/H2Terminals.csv": ("H2Terminals",),
    "Hydrogen/H2TerminalNodes.csv": ("H2TerminalNodes",),
    "Hydrogen/H2TerminalsOfNode.csv": ("H2TerminalNodes", "H2Terminals"),
    "Hydrogen/duplicate_input_audit.csv": (
        "Table", "Key", "DiscardedSourceRow", "DiscardedValue",
        "SelectedSourceRow", "SelectedValue", "ValuesDiffer",
    ),
    "Hydrogen/excluded_input_rows.csv": ("Table", "SourceRow", "Key", "Reason"),
    "Transport/ElectricityDemand.csv": (
        "Node", "Period", "Electricity_demand_[MWh/yr]",
    ),
    "Transport/HydrogenDemand.csv": (
        "Node", "Period", "Hydrogen_demand_[MWh/yr]",
    ),
    "Generator/genCO2Captured.csv": (
        "GeneratorTechnology", "CO2Capctured_in_tCO2/GJ",
    ),
    "CO2/CO2SequestrationNodes.csv": ("CO2SequestrationNodes",),
    "CO2/generated_default_rows.csv": (
        "Node", "Period", "Storage_max_injection_capacity_(ton/hour)", "Reason",
    ),
}

SCHEMAS.update({
    "Hydrogen/ElectrolyzerFixedOMCost.csv": ("Period", "eLyzerOMCost"),
    "Hydrogen/ElectrolyzerLifetime.csv": ("elyzerLifetime",),
    "Hydrogen/ElectrolyzerPlantCapitalCost.csv": ("Period", "elyzerCapCost_(€/MWe)"),
    "Hydrogen/ElectrolyzerPowerUse.csv": ("Period", "El_consumption_(MWh/ton)"),
    "Hydrogen/PipelineCapitalCost.csv": ("Period", "Capital_cost"),
    "Hydrogen/PipelineOMCostPerKM.csv": ("Period", "O&M_Cost"),
    "Hydrogen/PipelineCompressorPowerUsage.csv": ("Electricity_usage",),
    "Hydrogen/ReformerCapitalCost.csv": ("Plant_type", "Period", "Capital_cost_[EUR/MW_H2]"),
    "Hydrogen/ReformerFixedOMCost.csv": ("Plant_type", "Period", "Fixed_O&M_cost_[EUR/MW_H2]"),
    "Hydrogen/ReformerVariableOMCost.csv": ("Plant_type", "Period", "Variable_O&M_cost_[EUR/ton_H2]"),
    "Hydrogen/ReformerEfficiency.csv": ("Plant_type", "Period", "LHV_Efficiency"),
    "Hydrogen/ReformerElectricityUse.csv": ("Plant_type", "Period", "Electricity_demand_[MWh_/_ton]"),
    "Hydrogen/ReformerEmissionFactor.csv": ("Plant_type", "Period", "Ton_CO2_emissions_per_ton_H2"),
    "Hydrogen/ReformerCO2CaptureFactor.csv": ("Plant_type", "Period", "Ton_CO2_emissions_captured_per_ton_H2"),
    "Hydrogen/ReformerLifetime.csv": ("elyzerLifetime", "SMRLifetime"),
    "Hydrogen/StorageCapitalCost.csv": ("H2Storage", "Period", "Capital_cost_(EUR/ton)"),
    "Hydrogen/StorageFixedOMCost.csv": ("H2Storage", "Period", "O&M_cost_per_kg_H2"),
    "Hydrogen/StorageMaxCapacity.csv": ("Node", "H2Storage", "Max_capacity_[ton]"),
    "Hydrogen/StorageLifetime.csv": ("H2Storage", "Lifetime"),
    "Hydrogen/H2TerminalCapitalCost.csv": ("H2TerminalNodes", "H2Terminals", "Period", "CapitalCost_(EUR/ton/h)"),
    "Hydrogen/H2TerminalFixedOM.csv": ("H2TerminalNodes", "H2Terminals", "Period", "FixedOM_(EUR/ton/h)"),
    "Hydrogen/H2TerminalLifetime.csv": ("H2Terminals", "importLifetime"),
    "Hydrogen/H2TerminalPrice.csv": ("H2TerminalNodes", "H2Terminals", "Period", "Cost_(EUR/kg)"),
    "Hydrogen/H2TerminalCapacity.csv": ("H2TerminalNodes", "H2Terminals", "Period", "Capacity_(ton/hr)"),
    "CO2/StorageSiteCapitalCost.csv": ("Node", "Site_Development_Cost_euro/(t/hr)"),
    "CO2/StorageSiteFixedOMCost.csv": ("Node", "Field_Fixed_OM_Cost_euro/(t/hr)"),
    "CO2/StorageMaxCapacity.csv": ("Node", "Period", "Storage_max_injection_capacity_(ton/hour)"),
    "CO2/PipelineCapitalCost.csv": ("Capital_cost_(euro/(km_*_tons/hr)",),
    "CO2/PipelineFixedOM.csv": ("O&M_Cost_(euro/km)",),
    "CO2/PipelineLifetime.csv": ("Lifetime_(years)",),
    "CO2/PipelineElectricityUsage.csv": ("Power_usage_[MWh/ton]",),
    "CO2/MaxSequestrationCapacity.csv": ("Node", "Max_sequestration_capacity_[tons]"),
})

SCHEMAS.update({
    "Sets/SteelProducers.csv": ("SteelProducers",),
    "Sets/CementProducers.csv": ("CementProducers",),
    "Sets/AmmoniaProducers.csv": ("AmmoniaProducers",),
    "Sets/OilProducers.csv": ("OilProducers",),
    "General/availableBioEnergy.csv": ("Period", "Available_bioenergy_(GJ)"),
    "Industry/SteelPlants.csv": ("SteelPlants",),
    "Industry/CementPlants.csv": ("CementPlants",),
    "Industry/AmmoniaPlants.csv": ("AmmoniaPlants",),
    "Industry/Constants.csv": ("Parameter", "Value", "Unit", "Source"),
    "Industry/ShedCost.csv": ("ShedCost_(€/ton)",),
    "Industry/SteelPlantLifetime.csv": ("PlantType", "Lifetime"),
    "Industry/SteelInitialCapacity.csv": ("Node", "PlantType", "Initial_capacity_(ton/hr)"),
    "Industry/SteelScaleFactorInitialCap.csv": ("PlantType", "Period", "RetirementFactor"),
    "Industry/SteelInvCost.csv": ("PlantType", "Period", "InvCost_(eur/(t/h)_crude_steel)"),
    "Industry/SteelFixedOM.csv": ("PlantType", "Period", "InvCost_(eur/(t/h)_crude_steel)"),
    "Industry/SteelVarOpex.csv": ("PlantType", "Period", "VarOpex_(eur/(t/h)_crude_steel)"),
    "Industry/SteelCoalConsumption.csv": ("SteelPlant", "Period", "Coal_Consumption"),
    "Industry/SteelHydrogenConsumption.csv": ("SteelPlant", "Period", "Hydrogen_Consumption"),
    "Industry/SteelBioConsumption.csv": ("SteelPlant", "Period", "FuelConsumption"),
    "Industry/SteelOilConsumption.csv": ("SteelPlant", "Period", "FuelConsumption"),
    "Industry/SteelElConsumption.csv": ("SteelPlant", "Period", "ElectricityConsumption"),
    "Industry/SteelCO2Emissions.csv": ("SteelPlant", "CO2_emissions_(ton_CO2/ton_crude_steel)"),
    "Industry/SteelCO2Captured.csv": ("SteelPlant", "CO2_captured_(ton_CO2/ton_crude_steel)"),
    "Industry/SteelYearlyProduction.csv": ("Node", "Period", "Production_(ton/yr)"),
    "Industry/CementPlantLifetime.csv": ("PlantType", "Lifetime"),
    "Industry/CementInitialCapacity.csv": ("Node", "CementPlant", "Capacity_(ton/hr)"),
    "Industry/CementScaleFactorInitialCap.csv": ("PlantType", "Period", "RetirementFactor"),
    "Industry/CementInvCost.csv": ("PlantType", "Period", "InvCost_(EUR/(ton/hr))"),
    "Industry/CementFixedOM.csv": ("PlantType", "Period", "Fixed_O&M_(EUR/(ton/hr))"),
    "Industry/CementFuelConsumption.csv": ("CementPlant", "Period", "FuelConsumption"),
    "Industry/CementCO2CaptureRate.csv": ("CementPlant", "CaptureRate"),
    "Industry/CementElConsumption.csv": ("CementPlant", "Period", "ElectricityConsumption"),
    "Industry/CementYearlyProduction.csv": ("Node", "Production"),
    "Industry/AmmoniaPlantLifetime.csv": ("PlantType", "Lifetime"),
    "Industry/AmmoniaInitialCapacity.csv": ("Node", "AmmoniaPlant", "Capacity_(ton/hr)"),
    "Industry/AmmoniaScaleFactorInitialCap.csv": ("PlantType", "Period", "RetirementFactor"),
    "Industry/AmmoniaInvCost.csv": ("PlantType", "Period", "InvCost_(EUR/(ton/hr))"),
    "Industry/AmmoniaFixedOM.csv": ("PlantType", "Period", "Fixed_O&M_(EUR/(ton/hr))"),
    "Industry/AmmoniaFeedstockConsumption.csv": ("Ammonia_Plant", "Feedstock_Consumption_(kg_feedstock_/_t_ammonia)"),
    "Industry/AmmoniaElConsumption.csv": ("Ammonia_plant", "Electricity_consumption_(MWh_/_t_ammonia)"),
    "Industry/AmmoniaYearlyProduction.csv": ("Node", "Period", "Yearly_production_(tons/yr)"),
    "Industry/RefineryHydrogenConsumption.csv": ("Hydrogen_consumption_(ton/k_bbl)",),
    "Industry/RefineryHeatConsumption.csv": ("Heat_Consumption_(MWh/k_bbl)",),
    "Industry/RefineryYearlyProduction.csv": ("Node", "Period", "Yearly_production_of_oil_(k_bbl/yr)"),
    "Industry/duplicate_input_audit.csv": (
        "Table", "Key", "DiscardedSourceRow", "DiscardedValue",
        "SelectedSourceRow", "SelectedValue", "ValuesDiffer",
    ),
    "Industry/generated_default_rows.csv": ("Table", "Key", "Value", "Reason"),
})


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
        if path.is_file()
        and path.name != manifest_path.name
        # Finder metadata is not a model input and commonly appears in otherwise
        # clean macOS checkouts. Keep the inventory strict for every other file.
        and path.name != ".DS_Store"
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


def validate_hydrogen_manifest(dataset: Path) -> dict[str, object]:
    path = dataset / "hydrogen_conversion_manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    listed = set()
    for entry in manifest["files"]:
        relative = entry["path"]
        if relative in listed:
            fail(f"{path}: duplicate file entry {relative}")
        listed.add(relative)
        output = dataset / relative
        if not output.is_file():
            fail(f"{path}: missing listed file {relative}")
        if hashlib.sha256(output.read_bytes()).hexdigest() != entry["sha256"]:
            fail(f"{path}: SHA-256 mismatch for {relative}")
    expected = {
        file.relative_to(dataset).as_posix()
        for folder in (dataset / "Hydrogen", dataset / "CO2")
        for file in folder.glob("*.csv")
    } | {
        "Transport/ElectricityDemand.csv",
        "Transport/HydrogenDemand.csv",
        "Generator/genCO2Captured.csv",
    }
    if listed != expected:
        fail(
            f"{path}: Hydrogen file inventory mismatch; "
            f"unlisted={sorted(expected-listed)}, missing={sorted(listed-expected)}"
        )
    return manifest


def _validate_complete_numeric_table(
    dataset: Path,
    relative: str,
    key_columns: tuple[str, ...],
    value_column: str,
    expected: set[tuple[str, ...]],
    periods: set[int],
) -> list[dict[str, str]]:
    rows, keys = unique_keys(dataset, relative, key_columns)
    finite_nonnegative(dataset, relative, rows, (value_column,))
    if "Period" in key_columns:
        integer_column(dataset, relative, rows, "Period", periods)
    if keys != expected:
        fail(
            f"{dataset / relative}: incomplete or unexpected keys; "
            f"missing={sorted(expected-keys)[:10]}, extra={sorted(keys-expected)[:10]}"
        )
    return rows


def validate_hydrogen_tables(dataset: Path, base_manifest: dict[str, object]) -> None:
    manifest = validate_hydrogen_manifest(dataset)
    periods = set(range(1, int(base_manifest["periods"]) + 1))
    period_keys = {(str(period),) for period in periods}
    nodes = single_column_set(dataset, "Sets/Node.csv", "Node")
    onshore = single_column_set(dataset, "Sets/OnshoreNode.csv", "OnshoreNode")
    generators = single_column_set(dataset, "Sets/Generator.csv", "Generator")
    hydrogen_generators = single_column_set(
        dataset, "Hydrogen/HydrogenGenerators.csv", "HydrogenGenerator"
    )
    expected_generators = {
        generator for generator in generators if "hydrogen" in generator.lower()
    }
    if hydrogen_generators != expected_generators:
        fail("Hydrogen generator set does not match the case-insensitive name rule")

    production_nodes = single_column_set(
        dataset, "Hydrogen/ProductionNodes.csv", "ProductionNodes"
    )
    reformer_locations = single_column_set(
        dataset, "Hydrogen/ReformerLocations.csv", "ReformerLocations"
    )
    reformers = single_column_set(
        dataset, "Hydrogen/ReformerPlants.csv", "ReformerPlants"
    )
    storages = single_column_set(dataset, "Hydrogen/H2Storages.csv", "H2Storages")
    terminal_nodes = single_column_set(
        dataset, "Hydrogen/H2TerminalNodes.csv", "H2TerminalNodes"
    )
    terminals = single_column_set(dataset, "Hydrogen/H2Terminals.csv", "H2Terminals")
    sequestration_nodes = single_column_set(
        dataset, "CO2/CO2SequestrationNodes.csv", "CO2SequestrationNodes"
    )
    for name, values, allowed in (
        ("production", production_nodes, nodes),
        ("reformer", reformer_locations, production_nodes),
        ("terminal", terminal_nodes, production_nodes),
        ("CO2 sequestration", sequestration_nodes, onshore),
    ):
        if not values <= allowed:
            fail(f"Unknown {name} nodes: {sorted(values-allowed)}")

    pair_rows, terminal_pairs = unique_keys(
        dataset,
        "Hydrogen/H2TerminalsOfNode.csv",
        ("H2TerminalNodes", "H2Terminals"),
    )
    for row in pair_rows:
        if row["H2TerminalNodes"] not in terminal_nodes:
            fail(f"Unknown Hydrogen terminal node: {row}")
        if row["H2Terminals"] not in terminals:
            fail(f"Unknown Hydrogen terminal: {row}")

    scalar_rows = read_csv(dataset, "Hydrogen/Constants.csv")
    scalar_values = {row["Parameter"]: float(row["Value"]) for row in scalar_rows}
    expected_scalars = {
        "hydrogen_mwh_per_ton": 33.3,
        "storage_initial_fraction": 0.5,
        "storage_compression_mwh_per_ton": 0.333,
        "pipeline_compressor_static_mwh_per_ton": 1.0,
        "hydrogen_pipeline_lifetime_years": 40.0,
        "pipeline_leakage_fraction_per_km": 0.000005,
        "reformer_ramp_fraction_per_hour": 0.1,
        "repurpose_cost_factor": 0.25,
        "repurpose_energy_flow_factor": 0.8,
        "terminal_eur_per_kg_to_eur_per_ton": 1000.0,
        "hours_per_year": 8760.0,
    }
    if scalar_values != expected_scalars:
        fail("Hydrogen/Constants.csv differs from the audited formulation constants")

    for relative, value_column in (
        ("Hydrogen/ElectrolyzerFixedOMCost.csv", "eLyzerOMCost"),
        ("Hydrogen/ElectrolyzerPlantCapitalCost.csv", "elyzerCapCost_(€/MWe)"),
        ("Hydrogen/ElectrolyzerPowerUse.csv", "El_consumption_(MWh/ton)"),
        ("Hydrogen/PipelineCapitalCost.csv", "Capital_cost"),
        ("Hydrogen/PipelineOMCostPerKM.csv", "O&M_Cost"),
    ):
        _validate_complete_numeric_table(
            dataset, relative, ("Period",), value_column, period_keys, periods
        )

    for relative, value_column in (
        ("Hydrogen/ReformerCapitalCost.csv", "Capital_cost_[EUR/MW_H2]"),
        ("Hydrogen/ReformerFixedOMCost.csv", "Fixed_O&M_cost_[EUR/MW_H2]"),
        ("Hydrogen/ReformerVariableOMCost.csv", "Variable_O&M_cost_[EUR/ton_H2]"),
        ("Hydrogen/ReformerEfficiency.csv", "LHV_Efficiency"),
        ("Hydrogen/ReformerEmissionFactor.csv", "Ton_CO2_emissions_per_ton_H2"),
        ("Hydrogen/ReformerCO2CaptureFactor.csv", "Ton_CO2_emissions_captured_per_ton_H2"),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("Plant_type", "Period"),
            value_column,
            {(plant, str(period)) for plant in reformers for period in periods},
            periods,
        )

    electricity_rows, electricity_keys = unique_keys(
        dataset,
        "Hydrogen/ReformerElectricityUse.csv",
        ("Plant_type", "Period"),
    )
    expected_reformer_periods = {
        (plant, str(period)) for plant in reformers for period in periods
    }
    if electricity_keys != expected_reformer_periods:
        fail("Hydrogen/ReformerElectricityUse.csv is incomplete")
    for row_number, row in enumerate(electricity_rows, start=2):
        value = float(row["Electricity_demand_[MWh_/_ton]"])
        if not math.isfinite(value):
            fail(f"ReformerElectricityUse.csv row {row_number}: non-finite value")
        if value < 0 and not (row["Plant_type"] == "SMR" and math.isclose(value, -2 / 3)):
            fail(f"ReformerElectricityUse.csv row {row_number}: unexpected negative value")

    efficiency_rows = read_csv(dataset, "Hydrogen/ReformerEfficiency.csv")
    for row in efficiency_rows:
        efficiency = float(row["LHV_Efficiency"])
        if not 0 < efficiency <= 1:
            fail(f"Invalid reformer efficiency: {row}")

    for relative, key_column, value_column, expected_values in (
        ("Hydrogen/ReformerLifetime.csv", "elyzerLifetime", "SMRLifetime", reformers),
        ("Hydrogen/StorageLifetime.csv", "H2Storage", "Lifetime", storages),
        ("Hydrogen/H2TerminalLifetime.csv", "H2Terminals", "importLifetime", terminals),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            (key_column,),
            value_column,
            {(value,) for value in expected_values},
            periods,
        )

    for relative, value_column in (
        ("Hydrogen/StorageCapitalCost.csv", "Capital_cost_(EUR/ton)"),
        ("Hydrogen/StorageFixedOMCost.csv", "O&M_cost_per_kg_H2"),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("H2Storage", "Period"),
            value_column,
            {(storage, str(period)) for storage in storages for period in periods},
            periods,
        )

    storage_rows, _ = unique_keys(
        dataset, "Hydrogen/StorageMaxCapacity.csv", ("Node", "H2Storage")
    )
    finite_nonnegative(
        dataset, "Hydrogen/StorageMaxCapacity.csv", storage_rows, ("Max_capacity_[ton]",)
    )
    for row in storage_rows:
        if row["Node"] not in production_nodes or row["H2Storage"] not in storages:
            fail(f"Hydrogen storage capacity references an unknown key: {row}")

    expected_terminal_periods = {
        (node, terminal, str(period))
        for node, terminal in terminal_pairs
        for period in periods
    }
    for relative, value_column in (
        ("Hydrogen/H2TerminalCapitalCost.csv", "CapitalCost_(EUR/ton/h)"),
        ("Hydrogen/H2TerminalFixedOM.csv", "FixedOM_(EUR/ton/h)"),
        ("Hydrogen/H2TerminalPrice.csv", "Cost_(EUR/kg)"),
        ("Hydrogen/H2TerminalCapacity.csv", "Capacity_(ton/hr)"),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("H2TerminalNodes", "H2Terminals", "Period"),
            value_column,
            expected_terminal_periods,
            periods,
        )

    for relative, column in (
        ("Hydrogen/ElectrolyzerLifetime.csv", "elyzerLifetime"),
        ("Hydrogen/PipelineCompressorPowerUsage.csv", "Electricity_usage"),
        ("CO2/PipelineCapitalCost.csv", "Capital_cost_(euro/(km_*_tons/hr)"),
        ("CO2/PipelineFixedOM.csv", "O&M_Cost_(euro/km)"),
        ("CO2/PipelineLifetime.csv", "Lifetime_(years)"),
        ("CO2/PipelineElectricityUsage.csv", "Power_usage_[MWh/ton]"),
    ):
        rows = read_csv(dataset, relative)
        if len(rows) != 1:
            fail(f"{dataset / relative}: expected one scalar row")
        finite_nonnegative(dataset, relative, rows, (column,))

    for relative, value_column in (
        ("CO2/StorageSiteCapitalCost.csv", "Site_Development_Cost_euro/(t/hr)"),
        ("CO2/StorageSiteFixedOMCost.csv", "Field_Fixed_OM_Cost_euro/(t/hr)"),
        ("CO2/MaxSequestrationCapacity.csv", "Max_sequestration_capacity_[tons]"),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("Node",),
            value_column,
            {(node,) for node in sequestration_nodes},
            periods,
        )
    _validate_complete_numeric_table(
        dataset,
        "CO2/StorageMaxCapacity.csv",
        ("Node", "Period"),
        "Storage_max_injection_capacity_(ton/hour)",
        {(node, str(period)) for node in sequestration_nodes for period in periods},
        periods,
    )
    default_rows = read_csv(dataset, "CO2/generated_default_rows.csv")
    if len(default_rows) != manifest["pyomo_default_rows_materialized"]:
        fail("CO2 default-row audit count differs from its conversion manifest")
    for row in default_rows:
        if (
            float(row["Storage_max_injection_capacity_(ton/hour)"]) != 0.0
            or row["Reason"] != "InternalEMPIRE Param default for absent source key"
        ):
            fail(f"CO2 generated-default audit contains an invalid row: {row}")

    for relative, value_column in (
        ("Transport/ElectricityDemand.csv", "Electricity_demand_[MWh/yr]"),
        ("Transport/HydrogenDemand.csv", "Hydrogen_demand_[MWh/yr]"),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("Node", "Period"),
            value_column,
            {(node, str(period)) for node in onshore for period in periods},
            periods,
        )

    capture_rows, _ = unique_keys(
        dataset, "Generator/genCO2Captured.csv", ("GeneratorTechnology",)
    )
    finite_nonnegative(
        dataset,
        "Generator/genCO2Captured.csv",
        capture_rows,
        ("CO2Capctured_in_tCO2/GJ",),
    )
    if not {row["GeneratorTechnology"] for row in capture_rows} <= generators:
        fail("Generator/genCO2Captured.csv references an unknown generator")

    audit_rows = read_csv(dataset, "Hydrogen/duplicate_input_audit.csv")
    if len(audit_rows) != manifest["duplicate_rows_resolved_last_source_row_wins"]:
        fail("Hydrogen duplicate audit count differs from its conversion manifest")
    excluded_rows = read_csv(dataset, "Hydrogen/excluded_input_rows.csv")
    if len(excluded_rows) != manifest["unused_parameter_rows_excluded"]:
        fail("Hydrogen exclusion audit count differs from its conversion manifest")
    if any(
        row["Reason"] != "terminal-node pair is absent from H2TerminalsOfNode"
        for row in excluded_rows
    ):
        fail("Hydrogen exclusion audit contains an unknown exclusion reason")


def validate_industry_manifest(dataset: Path) -> dict[str, object]:
    path = dataset / "industry_conversion_manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    listed: set[str] = set()
    for entry in manifest["files"]:
        relative = entry["path"]
        if relative in listed:
            fail(f"{path}: duplicate file entry {relative}")
        listed.add(relative)
        output = dataset / relative
        if not output.is_file():
            fail(f"{path}: missing listed file {relative}")
        payload = output.read_bytes()
        if hashlib.sha256(payload).hexdigest() != entry["sha256"]:
            fail(f"{path}: SHA-256 mismatch for {relative}")
        if len(payload) != entry["bytes"]:
            fail(f"{path}: byte-count mismatch for {relative}")
        with output.open(newline="", encoding="utf-8") as handle:
            rows = sum(1 for _ in csv.reader(handle)) - 1
        if rows != entry["rows"]:
            fail(f"{path}: row-count mismatch for {relative}")
    expected = {
        file.relative_to(dataset).as_posix()
        for file in (dataset / "Industry").glob("*.csv")
    } | {
        "Sets/SteelProducers.csv",
        "Sets/CementProducers.csv",
        "Sets/AmmoniaProducers.csv",
        "Sets/OilProducers.csv",
        "General/availableBioEnergy.csv",
    }
    if listed != expected:
        fail(
            f"{path}: Industry file inventory mismatch; "
            f"unlisted={sorted(expected-listed)}, missing={sorted(listed-expected)}"
        )
    return manifest


def _validate_fraction_table(
    dataset: Path,
    relative: str,
    rows: Iterable[dict[str, str]],
    column: str,
) -> None:
    for row_number, row in enumerate(rows, start=2):
        value = float(row[column])
        if value > 1:
            fail(
                f"{dataset / relative}: row {row_number} column {column} "
                f"must be no larger than one: {row[column]!r}"
            )


def validate_industry_tables(dataset: Path, base_manifest: dict[str, object]) -> None:
    manifest = validate_industry_manifest(dataset)
    periods = set(range(1, int(base_manifest["periods"]) + 1))
    period_keys = {str(period) for period in periods}
    nodes = single_column_set(dataset, "Sets/Node.csv", "Node")
    steel_producers = single_column_set(
        dataset, "Sets/SteelProducers.csv", "SteelProducers"
    )
    cement_producers = single_column_set(
        dataset, "Sets/CementProducers.csv", "CementProducers"
    )
    ammonia_producers = single_column_set(
        dataset, "Sets/AmmoniaProducers.csv", "AmmoniaProducers"
    )
    oil_producers = single_column_set(dataset, "Sets/OilProducers.csv", "OilProducers")
    for name, producers in (
        ("steel", steel_producers),
        ("cement", cement_producers),
        ("ammonia", ammonia_producers),
        ("oil", oil_producers),
    ):
        if not producers <= nodes:
            fail(f"Unknown {name} producer nodes: {sorted(producers-nodes)}")

    steel = single_column_set(dataset, "Industry/SteelPlants.csv", "SteelPlants")
    cement = single_column_set(dataset, "Industry/CementPlants.csv", "CementPlants")
    ammonia = single_column_set(dataset, "Industry/AmmoniaPlants.csv", "AmmoniaPlants")
    expected_steel = {
        "BF-BOF", "BF-BOF-BioCarbon", "H2-DRI", "EAF", "Scrap", "BF-BOF-CCS",
    }
    expected_cement = {"NG-Cement", "H2-Cement", "NG-CCS-Cement"}
    expected_ammonia = {"NG-Ammonia", "H2-Ammonia"}
    if steel != expected_steel or cement != expected_cement or ammonia != expected_ammonia:
        fail("Industry plant sets differ from the audited InternalEMPIRE inventory")

    scalar_rows = read_csv(dataset, "Industry/Constants.csv")
    finite_nonnegative(dataset, "Industry/Constants.csv", scalar_rows, ("Value",))
    scalar_values = {row["Parameter"]: float(row["Value"]) for row in scalar_rows}
    if scalar_values != {
        "ramp_fraction_per_hour": 0.1,
        "maximum_scrap_share": 0.45,
        "hours_per_year": 8760.0,
        "oil_shed_cost": 1_000_000.0,
    }:
        fail("Industry/Constants.csv differs from the audited formulation constants")

    for relative, column in (
        ("Industry/ShedCost.csv", "ShedCost_(€/ton)"),
        ("Industry/RefineryHydrogenConsumption.csv", "Hydrogen_consumption_(ton/k_bbl)"),
        ("Industry/RefineryHeatConsumption.csv", "Heat_Consumption_(MWh/k_bbl)"),
    ):
        rows = read_csv(dataset, relative)
        if len(rows) != 1:
            fail(f"{dataset / relative}: expected exactly one data row")
        finite_nonnegative(dataset, relative, rows, (column,))

    plant_period_tables = (
        ("Industry/SteelInvCost.csv", "PlantType", "InvCost_(eur/(t/h)_crude_steel)", steel),
        ("Industry/SteelFixedOM.csv", "PlantType", "InvCost_(eur/(t/h)_crude_steel)", steel),
        ("Industry/SteelVarOpex.csv", "PlantType", "VarOpex_(eur/(t/h)_crude_steel)", steel),
        ("Industry/SteelCoalConsumption.csv", "SteelPlant", "Coal_Consumption", steel),
        ("Industry/SteelHydrogenConsumption.csv", "SteelPlant", "Hydrogen_Consumption", steel),
        ("Industry/SteelBioConsumption.csv", "SteelPlant", "FuelConsumption", steel),
        ("Industry/SteelOilConsumption.csv", "SteelPlant", "FuelConsumption", steel),
        ("Industry/SteelElConsumption.csv", "SteelPlant", "ElectricityConsumption", steel),
        ("Industry/CementInvCost.csv", "PlantType", "InvCost_(EUR/(ton/hr))", cement),
        ("Industry/CementFixedOM.csv", "PlantType", "Fixed_O&M_(EUR/(ton/hr))", cement),
        ("Industry/CementFuelConsumption.csv", "CementPlant", "FuelConsumption", cement),
        ("Industry/CementElConsumption.csv", "CementPlant", "ElectricityConsumption", cement),
        ("Industry/AmmoniaInvCost.csv", "PlantType", "InvCost_(EUR/(ton/hr))", ammonia),
        ("Industry/AmmoniaFixedOM.csv", "PlantType", "Fixed_O&M_(EUR/(ton/hr))", ammonia),
    )
    for relative, plant_column, value_column, plants in plant_period_tables:
        _validate_complete_numeric_table(
            dataset,
            relative,
            (plant_column, "Period"),
            value_column,
            {(plant, period) for plant in plants for period in period_keys},
            periods,
        )

    for relative, plant_column, value_column, plants in (
        ("Industry/SteelPlantLifetime.csv", "PlantType", "Lifetime", steel),
        ("Industry/SteelCO2Emissions.csv", "SteelPlant", "CO2_emissions_(ton_CO2/ton_crude_steel)", steel),
        ("Industry/SteelCO2Captured.csv", "SteelPlant", "CO2_captured_(ton_CO2/ton_crude_steel)", steel),
        ("Industry/CementPlantLifetime.csv", "PlantType", "Lifetime", cement),
        ("Industry/CementCO2CaptureRate.csv", "CementPlant", "CaptureRate", cement),
        ("Industry/AmmoniaPlantLifetime.csv", "PlantType", "Lifetime", ammonia),
        ("Industry/AmmoniaFeedstockConsumption.csv", "Ammonia_Plant", "Feedstock_Consumption_(kg_feedstock_/_t_ammonia)", ammonia),
        ("Industry/AmmoniaElConsumption.csv", "Ammonia_plant", "Electricity_consumption_(MWh_/_t_ammonia)", ammonia),
    ):
        rows = _validate_complete_numeric_table(
            dataset,
            relative,
            (plant_column,),
            value_column,
            {(plant,) for plant in plants},
            periods,
        )
        if "Lifetime" in value_column and any(float(row[value_column]) <= 0 for row in rows):
            fail(f"{dataset / relative}: plant lifetimes must be positive")
        if value_column == "CaptureRate":
            _validate_fraction_table(dataset, relative, rows, value_column)

    initial_specs = (
        ("Industry/SteelInitialCapacity.csv", "PlantType", "Initial_capacity_(ton/hr)", steel_producers, steel),
        ("Industry/CementInitialCapacity.csv", "CementPlant", "Capacity_(ton/hr)", cement_producers, cement),
        ("Industry/AmmoniaInitialCapacity.csv", "AmmoniaPlant", "Capacity_(ton/hr)", ammonia_producers, ammonia),
    )
    for relative, plant_column, value_column, producers, plants in initial_specs:
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("Node", plant_column),
            value_column,
            {(node, plant) for node in producers for plant in plants},
            periods,
        )

    for relative, plants in (
        ("Industry/SteelScaleFactorInitialCap.csv", steel),
        ("Industry/CementScaleFactorInitialCap.csv", cement),
        ("Industry/AmmoniaScaleFactorInitialCap.csv", ammonia),
    ):
        rows = _validate_complete_numeric_table(
            dataset,
            relative,
            ("PlantType", "Period"),
            "RetirementFactor",
            {(plant, period) for plant in plants for period in period_keys},
            periods,
        )
        _validate_fraction_table(dataset, relative, rows, "RetirementFactor")

    for relative, value_column, producers in (
        ("Industry/SteelYearlyProduction.csv", "Production_(ton/yr)", steel_producers),
        ("Industry/AmmoniaYearlyProduction.csv", "Yearly_production_(tons/yr)", ammonia_producers),
        ("Industry/RefineryYearlyProduction.csv", "Yearly_production_of_oil_(k_bbl/yr)", oil_producers),
    ):
        _validate_complete_numeric_table(
            dataset,
            relative,
            ("Node", "Period"),
            value_column,
            {(node, period) for node in producers for period in period_keys},
            periods,
        )
    _validate_complete_numeric_table(
        dataset,
        "Industry/CementYearlyProduction.csv",
        ("Node",),
        "Production",
        {(node,) for node in cement_producers},
        periods,
    )
    _validate_complete_numeric_table(
        dataset,
        "General/availableBioEnergy.csv",
        ("Period",),
        "Available_bioenergy_(GJ)",
        {(period,) for period in period_keys},
        periods,
    )

    duplicate_rows = read_csv(dataset, "Industry/duplicate_input_audit.csv")
    if len(duplicate_rows) != manifest["duplicate_rows_resolved_last_source_row_wins"]:
        fail("Industry duplicate audit count differs from its conversion manifest")
    generated_rows, generated_keys = unique_keys(
        dataset, "Industry/generated_default_rows.csv", ("Table", "Key")
    )
    if len(generated_rows) != manifest["pyomo_default_rows_materialized"]:
        fail("Industry generated-default audit count differs from its conversion manifest")
    for row in generated_rows:
        if float(row["Value"]) != 0 or row["Reason"] != (
            "InternalEMPIRE Pyomo Param default for absent source key"
        ):
            fail(f"Industry generated-default audit contains an invalid row: {row}")


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
    hydrogen_enabled = (dataset / "hydrogen_conversion_manifest.json").is_file()
    if hydrogen_enabled:
        validate_hydrogen_tables(dataset, manifest)
    industry_enabled = (dataset / "industry_conversion_manifest.json").is_file()
    if industry_enabled:
        validate_industry_tables(dataset, manifest)
    print(
        "full_model_int validation: PASS "
        f"({len(manifest['files'])} files, {manifest['periods']} periods, "
        f"{manifest['terminal_cost_duplicate_keys_total']} audited terminal-cost "
        f"duplicates, {manifest['reserve_duplicate_keys']} audited reserve duplicate, "
        f"hydrogen={'yes' if hydrogen_enabled else 'no'}, "
        f"industry={'yes' if industry_enabled else 'no'})"
    )


if __name__ == "__main__":
    main()
