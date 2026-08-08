#!/usr/bin/env python3
"""Solve the controlled natural-gas parity fixture with Pyomo."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import pyomo.environ as pyo


def read_scalars(path: Path) -> dict[str, float]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {
            row["Parameter"]: float(row["Value"])
            for row in csv.DictReader(handle)
        }


def solve_fixture(fixture_dir: Path, output_path: Path) -> None:
    scalar = read_scalars(fixture_dir / "parameters.csv")
    with (fixture_dir / "hours.csv").open(newline="", encoding="utf-8") as handle:
        hourly = list(csv.DictReader(handle))
    hours = [int(row["Hour"]) for row in hourly]
    load_a = {int(row["Hour"]): float(row["LoadA_MW"]) for row in hourly}
    load_b = {int(row["Hour"]): float(row["LoadB_MW"]) for row in hourly}

    model = pyo.ConcreteModel()
    model.H = pyo.Set(initialize=hours, ordered=True)
    model.imported = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.pipeline = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.generation = pyo.Var(("A", "B"), model.H, domain=pyo.NonNegativeReals)
    model.gas_for_power = pyo.Var(("A", "B"), model.H, domain=pyo.NonNegativeReals)
    model.storage = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.charge = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.discharge = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.transport_met = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.transport_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)

    mwh_per_ton = scalar["mwh_per_ton"]
    efficiency = scalar["generator_efficiency"]
    initial_storage = (
        scalar["storage_capacity_b_ton"] * scalar["storage_initial_fraction"]
    )
    transport_demand = scalar["transport_demand_b_ton_per_hour"]

    model.power_conversion = pyo.Constraint(
        ("A", "B"),
        model.H,
        rule=lambda m, node, hour: mwh_per_ton * m.gas_for_power[node, hour]
        == m.generation[node, hour] / efficiency,
    )
    model.electricity_a = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.generation["A", hour]
        == load_a[hour]
        + scalar["pipeline_power_mwh_per_ton"] * m.pipeline[hour],
    )
    model.electricity_b = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.generation["B", hour] == load_b[hour],
    )
    model.gas_a = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.imported[hour]
        == m.pipeline[hour] + m.gas_for_power["A", hour],
    )
    model.gas_b = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.pipeline[hour] + m.discharge[hour]
        == m.gas_for_power["B", hour]
        + m.charge[hour]
        + m.transport_met[hour],
    )
    previous = {hours[0]: None}
    previous.update({hour: hours[index - 1] for index, hour in enumerate(hours) if index})
    model.storage_balance = pyo.Constraint(
        model.H,
        rule=lambda m, hour: (
            initial_storage if previous[hour] is None else m.storage[previous[hour]]
        )
        + m.charge[hour]
        - m.discharge[hour]
        == m.storage[hour],
    )
    model.storage_final = pyo.Constraint(expr=model.storage[hours[-1]] == initial_storage)
    model.storage_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.storage[hour] <= scalar["storage_capacity_b_ton"],
    )
    model.pipeline_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.pipeline[hour]
        <= scalar["pipeline_capacity_ton_per_hour"],
    )
    model.terminal_capacity = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.imported[hour]
        <= scalar["terminal_capacity_ton_per_hour"],
    )
    model.reserve = pyo.Constraint(
        expr=sum(model.imported[hour] for hour in model.H)
        <= scalar["terminal_reserve_ton"]
    )
    model.generator_capacity = pyo.Constraint(
        ("A", "B"),
        model.H,
        rule=lambda m, node, hour: m.generation[node, hour]
        <= scalar["generator_capacity_mw"],
    )
    model.transport = pyo.Constraint(
        model.H,
        rule=lambda m, hour: m.transport_met[hour] + m.transport_shed[hour]
        >= transport_demand,
    )

    terminal_cost = scalar["terminal_cost_eur_per_ton"] * sum(
        model.imported[hour] for hour in model.H
    )
    generator_cost = scalar["generator_marginal_cost_eur_per_mwh"] * sum(
        model.generation[node, hour]
        for node in ("A", "B")
        for hour in model.H
    )
    shedding_cost = scalar["transport_shed_cost_eur_per_ton"] * sum(
        model.transport_shed[hour] for hour in model.H
    )
    model.objective = pyo.Objective(
        expr=terminal_cost + generator_cost + shedding_cost,
        sense=pyo.minimize,
    )

    result = pyo.SolverFactory("appsi_highs").solve(model)
    if result.solver.termination_condition != pyo.TerminationCondition.optimal:
        raise RuntimeError(
            "Python parity fixture did not solve to optimality: "
            f"{result.solver.termination_condition}"
        )

    rows: list[dict[str, object]] = []

    def append(metric: str, hour: int, node: str, value: float) -> None:
        rows.append(
            {
                "Metric": metric,
                "Hour": hour,
                "Node": node,
                "Value": pyo.value(value),
            }
        )

    append("objective_total", 0, "all", model.objective)
    append("objective_terminal_import", 0, "all", terminal_cost)
    append("objective_generator_operation", 0, "all", generator_cost)
    append("objective_transport_shedding", 0, "all", shedding_cost)
    for hour in hours:
        append("terminal_import", hour, "A", model.imported[hour])
        append("pipeline_flow", hour, "A->B", model.pipeline[hour])
        for node in ("A", "B"):
            append(
                "electricity_generation",
                hour,
                node,
                model.generation[node, hour],
            )
            append("gas_for_power", hour, node, model.gas_for_power[node, hour])
        append("storage_level", hour, "B", model.storage[hour])
        append("storage_charge", hour, "B", model.charge[hour])
        append("storage_discharge", hour, "B", model.discharge[hour])
        append("transport_demand_met", hour, "B", model.transport_met[hour])
        append("transport_demand_shed", hour, "B", model.transport_shed[hour])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=("Metric", "Hour", "Node", "Value"))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Python natural-gas parity output: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    solve_fixture(args.fixture_dir, args.output)


if __name__ == "__main__":
    main()
