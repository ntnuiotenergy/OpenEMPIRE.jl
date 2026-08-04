#!/usr/bin/env python3
"""Solve the controlled three-node Hydrogen/CO2 fixture with Pyomo."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import pyomo.environ as pyo


def read_scalars(path: Path) -> dict[str, float]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["Parameter"]: float(row["Value"]) for row in csv.DictReader(handle)}


def solve_fixture(fixture_dir: Path, output_path: Path) -> None:
    scalar = read_scalars(fixture_dir / "parameters.csv")
    with (fixture_dir / "hours.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    hours = [int(row["Hour"]) for row in rows]
    load = {
        node: {int(row["Hour"]): float(row[f"Load{node}_MW"]) for row in rows}
        for node in ("A", "B", "C")
    }
    model = pyo.ConcreteModel()
    model.H = pyo.Set(initialize=hours, ordered=True)
    model.grid = pyo.Var(("A", "B"), model.H, domain=pyo.NonNegativeReals)
    model.h2_generation = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.load_shed = pyo.Var(("A", "B", "C"), model.H, domain=pyo.NonNegativeReals)
    model.gas_import = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.electrolyzer_power = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.electrolyzer_h2 = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.h2_import = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.reformer_h2_ton = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.reformer_h2_mwh = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.reformer_gas = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.h2_ab = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.h2_bc = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.storage = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.charge = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.discharge = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.transport_met = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.transport_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.h2_for_power = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.co2_bc = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.co2_sequestered = pyo.Var(model.H, domain=pyo.NonNegativeReals)

    h2_mwh = scalar["hydrogen_mwh_per_ton"]
    gas_mwh = scalar["natural_gas_mwh_per_ton"]
    loss = scalar["hydrogen_pipeline_leakage_per_km"] * scalar["hydrogen_pipeline_length_km"]
    compressor = 0.5 * (
        scalar["hydrogen_pipeline_static_power_mwh_per_ton"]
        + scalar["hydrogen_pipeline_distance_power_mwh_per_ton_km"]
        * scalar["hydrogen_pipeline_length_km"]
    )
    co2_compressor = 0.5 * scalar["co2_pipeline_power_mwh_per_ton"]
    initial_storage = (
        scalar["hydrogen_storage_initial_fraction"]
        * scalar["hydrogen_storage_capacity_ton"]
    )

    model.electrolyzer_conversion = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.electrolyzer_h2[h]
        == m.electrolyzer_power[h] / scalar["electrolyzer_power_use_mwh_per_ton"],
    )
    model.reformer_ton_mwh = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.reformer_h2_ton[h] == m.reformer_h2_mwh[h] / h2_mwh,
    )
    model.reformer_gas_conversion = pyo.Constraint(
        model.H,
        rule=lambda m, h: gas_mwh * m.reformer_gas[h]
        == m.reformer_h2_mwh[h] / scalar["reformer_efficiency"],
    )
    model.h2_power_conversion = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_generation[h]
        == scalar["hydrogen_generator_efficiency"] * h2_mwh * m.h2_for_power[h],
    )
    model.gas_balance = pyo.Constraint(
        model.H, rule=lambda m, h: m.gas_import[h] == m.reformer_gas[h]
    )
    model.h2_a = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.electrolyzer_h2[h] + m.h2_import[h] == m.h2_ab[h],
    )
    model.h2_b = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.reformer_h2_ton[h] + (1 - loss) * m.h2_ab[h]
        + m.discharge[h]
        == m.h2_bc[h] + m.charge[h] + m.transport_met[h],
    )
    model.h2_c = pyo.Constraint(
        model.H,
        rule=lambda m, h: (1 - loss) * m.h2_bc[h] == m.h2_for_power[h],
    )
    previous = {hours[0]: None}
    previous.update({hour: hours[index - 1] for index, hour in enumerate(hours) if index})
    model.storage_balance = pyo.Constraint(
        model.H,
        rule=lambda m, h: (initial_storage if previous[h] is None else m.storage[previous[h]])
        + m.charge[h] - m.discharge[h] == m.storage[h],
    )
    model.storage_final = pyo.Constraint(expr=model.storage[hours[-1]] == initial_storage)
    model.transport = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.transport_met[h] + m.transport_shed[h]
        >= scalar["hydrogen_transport_demand_ton_per_hour"],
    )
    model.co2_b = pyo.Constraint(
        model.H,
        rule=lambda m, h: scalar["reformer_co2_capture_ton_per_ton_h2"]
        * m.reformer_h2_ton[h] == m.co2_bc[h],
    )
    model.co2_c = pyo.Constraint(
        model.H, rule=lambda m, h: m.co2_bc[h] == m.co2_sequestered[h]
    )
    model.electricity_a = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.grid["A", h] + m.load_shed["A", h]
        == load["A"][h] + m.electrolyzer_power[h] + compressor * m.h2_ab[h],
    )
    model.electricity_b = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.grid["B", h] + m.load_shed["B", h]
        == load["B"][h]
        + scalar["reformer_electricity_mwh_per_ton"] * m.reformer_h2_ton[h]
        + scalar["hydrogen_storage_compression_mwh_per_ton"] * m.charge[h]
        + compressor * (m.h2_ab[h] + m.h2_bc[h])
        + co2_compressor * m.co2_bc[h],
    )
    model.electricity_c = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_generation[h] + m.load_shed["C", h]
        == load["C"][h] + compressor * m.h2_bc[h]
        + co2_compressor * m.co2_bc[h],
    )

    model.grid_capacity = pyo.Constraint(
        ("A", "B"), model.H,
        rule=lambda m, n, h: m.grid[n, h] <= scalar["grid_capacity_mw"],
    )
    model.h2_generator_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_generation[h] <= scalar["hydrogen_generator_capacity_mw"],
    )
    model.gas_terminal_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.gas_import[h] <= scalar["gas_terminal_capacity_ton_per_hour"],
    )
    model.gas_reserve = pyo.Constraint(
        expr=sum(model.gas_import[h] for h in model.H) <= scalar["gas_terminal_reserve_ton"]
    )
    model.h2_import_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_import[h] <= scalar["hydrogen_terminal_capacity_ton_per_hour"],
    )
    model.electrolyzer_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.electrolyzer_power[h] <= scalar["electrolyzer_capacity_mw"],
    )
    model.reformer_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.reformer_h2_mwh[h] <= scalar["reformer_capacity_mwh_h2_per_hour"],
    )
    model.reformer_ramp = pyo.Constraint(
        [hour for hour in hours if previous[hour] is not None],
        rule=lambda m, h: m.reformer_h2_mwh[h] - m.reformer_h2_mwh[previous[h]]
        <= scalar["reformer_ramp_fraction_per_hour"]
        * scalar["reformer_capacity_mwh_h2_per_hour"],
    )
    model.h2_pipeline_ab_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_ab[h] <= scalar["hydrogen_pipeline_capacity_ton_per_hour"],
    )
    model.h2_pipeline_bc_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.h2_bc[h] <= scalar["hydrogen_pipeline_capacity_ton_per_hour"],
    )
    model.storage_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.storage[h] <= scalar["hydrogen_storage_capacity_ton"],
    )
    model.co2_pipeline_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.co2_bc[h] <= scalar["co2_pipeline_capacity_ton_per_hour"],
    )
    model.co2_site_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.co2_sequestered[h]
        <= scalar["co2_sequestration_capacity_ton_per_hour"],
    )

    grid_cost = scalar["grid_marginal_cost_eur_per_mwh"] * sum(
        model.grid[n, h] for n in ("A", "B") for h in model.H
    )
    h2_generation_cost = scalar["hydrogen_generator_marginal_cost_eur_per_mwh"] * sum(
        model.h2_generation[h] for h in model.H
    )
    gas_cost = scalar["gas_terminal_cost_eur_per_ton"] * sum(
        model.gas_import[h] for h in model.H
    )
    h2_import_cost = scalar["hydrogen_terminal_cost_eur_per_ton"] * sum(
        model.h2_import[h] for h in model.H
    )
    reformer_cost = scalar["reformer_variable_cost_eur_per_ton"] * sum(
        model.reformer_h2_ton[h] for h in model.H
    )
    transport_shed_cost = scalar["transport_shed_cost_eur_per_ton"] * sum(
        model.transport_shed[h] for h in model.H
    )
    load_shed_cost = scalar["lost_load_cost_eur_per_mwh"] * sum(
        model.load_shed[n, h] for n in ("A", "B", "C") for h in model.H
    )
    model.objective = pyo.Objective(
        expr=grid_cost + h2_generation_cost + gas_cost + h2_import_cost
        + reformer_cost + transport_shed_cost + load_shed_cost,
        sense=pyo.minimize,
    )
    result = pyo.SolverFactory("appsi_highs").solve(model)
    if result.solver.termination_condition != pyo.TerminationCondition.optimal:
        raise RuntimeError(f"Python Hydrogen fixture did not solve: {result.solver.termination_condition}")

    output_rows: list[dict[str, object]] = []
    def append(metric: str, hour: int, node: str, value) -> None:
        output_rows.append({"Metric": metric, "Hour": hour, "Node": node, "Value": pyo.value(value)})

    append("objective_total", 0, "all", model.objective)
    append("objective_generator_operation", 0, "all", grid_cost + h2_generation_cost)
    append("objective_gas_import", 0, "all", gas_cost)
    append("objective_hydrogen_import", 0, "all", h2_import_cost)
    append("objective_reformer_operation", 0, "all", reformer_cost)
    append("objective_transport_shedding", 0, "all", transport_shed_cost)
    for hour in hours:
        for node in ("A", "B"):
            append("grid_generation", hour, node, model.grid[node, hour])
        append("hydrogen_generation", hour, "C", model.h2_generation[hour])
        append("gas_import", hour, "B", model.gas_import[hour])
        append("electrolyzer_power", hour, "A", model.electrolyzer_power[hour])
        append("electrolyzer_hydrogen", hour, "A", model.electrolyzer_h2[hour])
        append("hydrogen_import", hour, "A", model.h2_import[hour])
        append("reformer_hydrogen", hour, "B", model.reformer_h2_ton[hour])
        append("reformer_gas", hour, "B", model.reformer_gas[hour])
        append("hydrogen_pipeline", hour, "A->B", model.h2_ab[hour])
        append("hydrogen_pipeline", hour, "B->C", model.h2_bc[hour])
        append("storage_level", hour, "B", model.storage[hour])
        append("storage_charge", hour, "B", model.charge[hour])
        append("storage_discharge", hour, "B", model.discharge[hour])
        append("transport_hydrogen_met", hour, "B", model.transport_met[hour])
        append("transport_hydrogen_shed", hour, "B", model.transport_shed[hour])
        append("hydrogen_for_power", hour, "C", model.h2_for_power[hour])
        append("co2_pipeline", hour, "B->C", model.co2_bc[hour])
        append("co2_sequestered", hour, "C", model.co2_sequestered[hour])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=("Metric", "Hour", "Node", "Value"))
        writer.writeheader()
        writer.writerows(output_rows)
    print(f"Python Hydrogen parity output: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    solve_fixture(args.fixture_dir, args.output)


if __name__ == "__main__":
    main()
