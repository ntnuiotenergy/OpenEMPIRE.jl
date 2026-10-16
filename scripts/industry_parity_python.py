#!/usr/bin/env python3
"""Solve the controlled Industry fixture with an independent Pyomo model."""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

import pyomo.environ as pyo


def read_scalars(path: Path) -> dict[str, float]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["Parameter"]: float(row["Value"]) for row in csv.DictReader(handle)}


def solve_fixture(fixture_dir: Path, output_path: Path, emission_cap: bool = False) -> None:
    scalar = read_scalars(fixture_dir / "parameters.csv")
    with (fixture_dir / "technologies.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    values = {
        row["Technology"]: {
            key: (value if key in ("Sector", "Technology") else float(value))
            for key, value in row.items()
        }
        for row in rows
    }
    by_sector = {
        sector: [row["Technology"] for row in rows if row["Sector"] == sector]
        for sector in ("Steel", "Cement", "Ammonia")
    }
    hours = list(range(1, int(scalar["hours"]) + 1))
    model = pyo.ConcreteModel()
    model.H = pyo.Set(initialize=hours, ordered=True)
    model.STEEL = pyo.Set(initialize=by_sector["Steel"])
    model.CEMENT = pyo.Set(initialize=by_sector["Cement"])
    model.AMMONIA = pyo.Set(initialize=by_sector["Ammonia"])
    model.steel = pyo.Var(model.STEEL, model.H, domain=pyo.NonNegativeReals)
    model.cement = pyo.Var(model.CEMENT, model.H, domain=pyo.NonNegativeReals)
    model.ammonia = pyo.Var(model.AMMONIA, model.H, domain=pyo.NonNegativeReals)
    model.steel_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.cement_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.ammonia_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.oil = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.oil_shed = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.grid = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.gas = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.hydrogen = pyo.Var(model.H, domain=pyo.NonNegativeReals)
    model.captured_co2 = pyo.Var(model.H, domain=pyo.NonNegativeReals)

    model.steel_capacity = pyo.Constraint(
        model.STEEL, model.H,
        rule=lambda m, plant, hour: m.steel[plant, hour]
        <= values[plant]["Capacity_ton_per_h"],
    )
    model.cement_capacity = pyo.Constraint(
        model.CEMENT, model.H,
        rule=lambda m, plant, hour: m.cement[plant, hour]
        <= values[plant]["Capacity_ton_per_h"],
    )
    model.ammonia_capacity = pyo.Constraint(
        model.AMMONIA, model.H,
        rule=lambda m, plant, hour: m.ammonia[plant, hour]
        <= values[plant]["Capacity_ton_per_h"],
    )
    final_steel = [plant for plant in model.STEEL if "EAF" in plant or "BOF" in plant]
    model.steel_demand = pyo.Constraint(
        model.H,
        rule=lambda m, h: sum(m.steel[p, h] for p in final_steel)
        + m.steel_shed[h]
        == scalar["steel_demand_ton"] / scalar["hours_per_year"],
    )
    model.cement_demand = pyo.Constraint(
        model.H,
        rule=lambda m, h: sum(m.cement[p, h] for p in m.CEMENT)
        + m.cement_shed[h]
        == scalar["cement_demand_ton"] / scalar["hours_per_year"],
    )
    model.ammonia_demand = pyo.Constraint(
        model.H,
        rule=lambda m, h: sum(m.ammonia[p, h] for p in m.AMMONIA)
        + m.ammonia_shed[h]
        == scalar["ammonia_demand_ton"] / scalar["hours_per_year"],
    )
    model.oil_demand = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.oil[h] + m.oil_shed[h]
        == scalar["oil_demand_ton"] / scalar["hours_per_year"],
    )
    model.raw_material = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.steel["Scrap", h] + m.steel["H2-DRI", h]
        == m.steel["EAF", h],
    )
    model.scrap_limit = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.steel["Scrap", h]
        <= scalar["maximum_scrap_share"] * scalar["steel_demand_ton"]
        / scalar["hours_per_year"],
    )
    previous = {hour: hours[index - 1] for index, hour in enumerate(hours) if index}
    model.steel_ramp = pyo.Constraint(
        [(plant, hour) for plant in model.STEEL if plant != "Scrap" for hour in previous],
        rule=lambda m, plant, hour: m.steel[plant, hour]
        - m.steel[plant, previous[hour]]
        <= scalar["ramp_fraction_per_hour"] * values[plant]["Capacity_ton_per_h"],
    )
    model.cement_ramp = pyo.Constraint(
        [(plant, hour) for plant in model.CEMENT for hour in previous],
        rule=lambda m, plant, hour: m.cement[plant, hour]
        - m.cement[plant, previous[hour]]
        <= scalar["ramp_fraction_per_hour"] * values[plant]["Capacity_ton_per_h"],
    )
    model.ammonia_ramp = pyo.Constraint(
        [(plant, hour) for plant in model.AMMONIA for hour in previous],
        rule=lambda m, plant, hour: m.ammonia[plant, hour]
        - m.ammonia[plant, previous[hour]]
        <= scalar["ramp_fraction_per_hour"] * values[plant]["Capacity_ton_per_h"],
    )
    model.biomass = pyo.Constraint(
        expr=sum(
            values[p]["Biomass_MWh_per_ton"] * model.steel[p, h]
            for p in model.STEEL for h in model.H
        ) <= scalar["available_biomass_mwh"]
    )

    gas_co2 = scalar["gas_co2_content_ton_per_gj"]
    gas_mwh = scalar["natural_gas_mwh_per_ton"]
    def cement_emission(plant: str, captured: bool) -> float:
        if "NG" not in plant:
            return 0.0
        share = values[plant]["CaptureFraction"] if captured else 1 - values[plant]["CaptureFraction"]
        return gas_co2 * 3.6 * gas_mwh * 1e-3 * values[plant]["HydrogenOrFuel_kg_per_ton"] * 2.5 * share

    def ammonia_emission(plant: str) -> float:
        if "NG" not in plant:
            return 0.0
        return gas_co2 * 3.6 * gas_mwh * 1e-3 * values[plant]["HydrogenOrFuel_kg_per_ton"]

    model.electricity_balance = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.grid[h] ==
        sum(values[p]["Electricity_MWh_per_ton"] * m.steel[p, h] for p in m.STEEL)
        + sum(values[p]["Electricity_MWh_per_ton"] * m.cement[p, h] for p in m.CEMENT)
        + sum(values[p]["Electricity_MWh_per_ton"] * m.ammonia[p, h] for p in m.AMMONIA),
    )
    model.gas_balance = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.gas[h] == 1e-3 * (
            sum(values[p]["HydrogenOrFuel_kg_per_ton"] * m.cement[p, h]
                for p in m.CEMENT if "NG" in p)
            + sum(values[p]["HydrogenOrFuel_kg_per_ton"] * m.ammonia[p, h]
                  for p in m.AMMONIA if "NG" in p)
        ),
    )
    model.hydrogen_balance = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.hydrogen[h] ==
        1e-3 * sum(values[p]["HydrogenOrFuel_kg_per_ton"] * m.steel[p, h] for p in m.STEEL)
        + 1e-3 * sum(values[p]["HydrogenOrFuel_kg_per_ton"] * m.cement[p, h]
                     for p in m.CEMENT if "H2" in p)
        + 1e-3 * sum(values[p]["HydrogenOrFuel_kg_per_ton"] * m.ammonia[p, h]
                     for p in m.AMMONIA if "H2" in p)
        + scalar["refinery_hydrogen_ton_per_ton"] * m.oil[h],
    )
    model.co2_balance = pyo.Constraint(
        model.H,
        rule=lambda m, h: m.captured_co2[h] ==
        sum(values[p]["CO2Captured_ton_per_ton"] * m.steel[p, h] for p in m.STEEL)
        + sum(cement_emission(p, True) * m.cement[p, h] for p in m.CEMENT),
    )
    total_emissions = sum(
        values[p]["CO2Emitted_ton_per_ton"] * model.steel[p, h]
        for p in model.STEEL for h in model.H
    ) + sum(
        cement_emission(p, False) * model.cement[p, h]
        for p in model.CEMENT for h in model.H
    ) + sum(
        ammonia_emission(p) * model.ammonia[p, h]
        for p in model.AMMONIA for h in model.H
    )
    if emission_cap:
        model.emission_cap = pyo.Constraint(
            expr=total_emissions <= scalar["emission_cap_ton"]
        )

    steel_operation = sum(
        (
            values[p]["VariableOM_EUR_per_ton"]
            + scalar["coal_cost_eur_per_mwh"] * values[p]["Coal_MWh_per_ton"]
            + scalar["oil_cost_eur_per_mwh"] * values[p]["Oil_MWh_per_ton"]
            + scalar["biomass_cost_eur_per_mwh"] * values[p]["Biomass_MWh_per_ton"]
            + (0.0 if emission_cap else scalar["carbon_price_eur_per_ton"])
            * values[p]["CO2Emitted_ton_per_ton"]
        ) * model.steel[p, h]
        for p in model.STEEL for h in model.H
    ) + scalar["industry_shed_cost_eur_per_ton"] * sum(model.steel_shed[h] for h in model.H)
    cement_operation = sum(
        (0.0 if emission_cap else scalar["carbon_price_eur_per_ton"])
        * gas_co2 * 3.6 * gas_mwh * 1e-3
        * values[p]["HydrogenOrFuel_kg_per_ton"] * model.cement[p, h]
        for p in model.CEMENT if "NG" in p for h in model.H
    ) + scalar["industry_shed_cost_eur_per_ton"] * sum(model.cement_shed[h] for h in model.H)
    ammonia_operation = sum(
        (0.0 if emission_cap else scalar["carbon_price_eur_per_ton"])
        * ammonia_emission(p) * model.ammonia[p, h]
        for p in model.AMMONIA for h in model.H
    ) + scalar["industry_shed_cost_eur_per_ton"] * sum(model.ammonia_shed[h] for h in model.H)
    refinery_shedding = scalar["oil_shed_cost_eur_per_ton"] * sum(model.oil_shed[h] for h in model.H)
    energy = sum(
        scalar["electricity_cost_eur_per_mwh"] * model.grid[h]
        + scalar["gas_cost_eur_per_ton"] * model.gas[h]
        + scalar["hydrogen_cost_eur_per_ton"] * model.hydrogen[h]
        for h in model.H
    )
    model.objective = pyo.Objective(
        expr=steel_operation + cement_operation + ammonia_operation
        + refinery_shedding + energy,
    )
    result = pyo.SolverFactory("appsi_highs").solve(model)
    if result.solver.termination_condition != pyo.TerminationCondition.optimal:
        raise RuntimeError(f"Python Industry fixture did not solve: {result.solver.termination_condition}")

    output = []
    def append(metric: str, hour: int, technology: str, value) -> None:
        output.append({
            "Metric": metric, "Hour": hour, "Technology": technology,
            "Value": pyo.value(value),
        })
    append("objective_total", 0, "all", model.objective)
    append("objective_investment", 0, "all", 0.0)
    append("objective_steel_operation", 0, "all", steel_operation)
    append("objective_cement_operation", 0, "all", cement_operation)
    append("objective_ammonia_operation", 0, "all", ammonia_operation)
    append("objective_refinery_shedding", 0, "all", refinery_shedding)
    append("objective_energy", 0, "all", energy)
    append("total_emissions", 0, "all", total_emissions)
    for hour in model.H:
        for plant in model.STEEL:
            append("production", hour, plant, model.steel[plant, hour])
        for plant in model.CEMENT:
            append("production", hour, plant, model.cement[plant, hour])
        for plant in model.AMMONIA:
            append("production", hour, plant, model.ammonia[plant, hour])
        for metric, variable in (
            ("steel_shed", model.steel_shed[hour]),
            ("cement_shed", model.cement_shed[hour]),
            ("ammonia_shed", model.ammonia_shed[hour]),
            ("oil_refined", model.oil[hour]),
            ("oil_shed", model.oil_shed[hour]),
            ("electricity", model.grid[hour]),
            ("natural_gas", model.gas[hour]),
            ("hydrogen", model.hydrogen[hour]),
            ("captured_co2", model.captured_co2[hour]),
        ):
            append(metric, hour, "A", variable)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=("Metric", "Hour", "Technology", "Value"))
        writer.writeheader()
        writer.writerows(output)
    print(f"Python Industry parity output: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--emission-cap", action="store_true")
    args = parser.parse_args()
    solve_fixture(args.fixture_dir, args.output, args.emission_cap)


if __name__ == "__main__":
    main()
