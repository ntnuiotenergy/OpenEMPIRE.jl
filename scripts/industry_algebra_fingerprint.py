#!/usr/bin/env python3
"""Canonical streaming fingerprints for InternalEMPIRE's Industry algebra."""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

from algebra_fingerprint import (
    BUCKETS,
    PRECISIONS,
    Fingerprints,
    constraint_terms,
    entity_key,
    normalized_records,
    raw_records,
    scenario_number,
)


DEDICATED_FAMILIES = {
    "steel_capacity": "steelMaxProduction",
    "steel_material": "link_eaf_with_raw_materials",
    "cement_capacity": "cementMaxProduction",
    "ammonia_capacity": "ammoniaMaxProduction",
    "steel_demand": "meet_steel_demand",
    "cement_demand": "meet_cement_demand",
    "ammonia_demand": "meet_ammonia_demand",
    "refinery_demand": "meet_oil_demand",
    "steel_ramp": "steel_ramping",
    "cement_ramp": "cement_ramping",
    "ammonia_ramp": "ammonia_ramping",
    "steel_installed": "steel_plant_lifetime",
    "cement_installed": "cement_plant_lifetime",
    "ammonia_installed": "ammonia_plant_lifetime",
    "scrap_limit": "max_scrap_capacity",
}

SHARED_FAMILIES = {
    "electricity_balance": "FlowBalance",
    "natural_gas_balance": "naturalGas_flow_balance",
    "hydrogen_balance": "hydrogen_flow_balance",
    "captured_co2_balance": "co2_flow_balance",
    "emissions": "emission_cap",
    "biomass_availability": "max_bio_availability",
}

ALL_ROW_FAMILIES = tuple((*DEDICATED_FAMILIES, *SHARED_FAMILIES))
OP = ("h", "i", "w", "gp")
PY_TAIL = {name: OP for name in DEDICATED_FAMILIES}
for name in ("steel_installed", "cement_installed", "ammonia_installed", "scrap_limit"):
    PY_TAIL[name] = ("i",)
PY_TAIL.update(
    {
        "electricity_balance": OP,
        "natural_gas_balance": OP,
        "hydrogen_balance": OP,
        "captured_co2_balance": OP,
        "emissions": ("i", "w", "gp"),
        "biomass_availability": ("i", "w", "gp"),
    }
)

VARIABLES: dict[str, tuple[str, bool]] = {
    "steelProduced": ("steel_production", True),
    "steelLoadShed": ("steel_shed", True),
    "steelPlantBuiltCapacity": ("steel_built", False),
    "steelPlantInstalledCapacity": ("steel_installed", False),
    "cementProduced": ("cement_production", True),
    "cementLoadShed": ("cement_shed", True),
    "cementPlantBuiltCapacity": ("cement_built", False),
    "cementPlantInstalledCapacity": ("cement_installed", False),
    "ammoniaProduced": ("ammonia_production", True),
    "ammoniaLoadShed": ("ammonia_shed", True),
    "ammoniaPlantBuiltCapacity": ("ammonia_built", False),
    "ammoniaPlantInstalledCapacity": ("ammonia_installed", False),
    "oilRefined": ("refinery_output", True),
    "oilLoadShed": ("refinery_shed", True),
}

OBJECTIVE_GROUPS = {
    "steelProduced": "steel_operation",
    "cementProduced": "cement_operation",
    "ammoniaProduced": "ammonia_operation",
    "steelLoadShed": "steel_shedding",
    "cementLoadShed": "cement_shedding",
    "ammoniaLoadShed": "ammonia_shedding",
    "oilLoadShed": "refinery_shedding",
    "steelPlantBuiltCapacity": "steel_investment",
    "cementPlantBuiltCapacity": "cement_investment",
    "ammoniaPlantBuiltCapacity": "ammonia_investment",
}


class InternalCanonicalizer:
    def __init__(self, instance: object) -> None:
        self.hour_context: dict[int, tuple[int, int]] = {}
        for representative, season in enumerate(instance.Season, 1):
            hours = [
                int(hour)
                for candidate, hour in instance.HoursOfSeason
                if candidate == season
            ]
            for local_hour, hour in enumerate(hours, 1):
                self.hour_context[hour] = (representative, local_hour)

    @staticmethod
    def as_tuple(index: object) -> tuple[object, ...]:
        return index if isinstance(index, tuple) else (index,)

    def time_key(self, tail: dict[str, object]) -> str:
        parts: list[str] = []
        if "i" in tail:
            parts.append(f"sp{int(tail['i'])}")
        if "h" in tail:
            representative, local_hour = self.hour_context[int(tail["h"])]
            parts.append(f"rp{representative}")
        if "w" in tail:
            parts.append(f"sc{scenario_number(tail['w'])}")
        if "h" in tail:
            parts.append(f"t{local_hour}")
        return "_".join(parts)

    def row_key(self, family: str, index: object) -> str:
        values = self.as_tuple(index)
        tail_names = PY_TAIL[family]
        split = len(values) - len(tail_names)
        entity = values[:split]
        tail = dict(zip(tail_names, values[split:]))
        return f"{family}|{entity_key(entity)}|{self.time_key(tail)}"

    def variable(self, variable: object) -> tuple[str, str]:
        component = variable.parent_component().local_name
        canonical, operational = VARIABLES[component]
        values = self.as_tuple(variable.index())
        if operational:
            entity = values[:-4]
            tail = dict(zip(OP, values[-4:]))
        else:
            entity = values[:-1]
            tail = {"i": values[-1]}
        return canonical, f"{canonical}|{entity_key(entity)}|{self.time_key(tail)}"


def _industry_terms(
    raw_terms: list[tuple[object, float]], canonicalizer: InternalCanonicalizer
) -> dict[str, float]:
    terms: dict[str, float] = defaultdict(float)
    for variable, coefficient in raw_terms:
        if variable.parent_component().local_name not in VARIABLES:
            continue
        _, column = canonicalizer.variable(variable)
        terms[column] += coefficient
    return dict(terms)


def export_internal_fingerprints(instance: object, output: Path, _tabs: Path) -> Path:
    """Export all Industry-controlled algebra from an already-built Pyomo instance."""
    from pyomo.environ import value
    from pyomo.repn.standard_repn import generate_standard_repn

    canonicalizer = InternalCanonicalizer(instance)
    result = Fingerprints()
    for family in ALL_ROW_FAMILIES:
        result.ensure("row", family)
    for canonical, _ in VARIABLES.values():
        result.ensure("variable", canonical)
    for group in OBJECTIVE_GROUPS.values():
        result.ensure("objective", group)

    for family, component_name in DEDICATED_FAMILIES.items():
        component = getattr(instance, component_name)
        for constraint in component.values():
            key = canonicalizer.row_key(family, constraint.index())
            raw_terms, sense, rhs = constraint_terms(constraint)
            terms = _industry_terms(raw_terms, canonicalizer)
            if not terms:
                raise ValueError(f"empty dedicated Industry row: {constraint.name}")
            result.add(
                "row",
                family,
                key,
                normalized_records(key, sense, rhs, terms),
                len(terms),
            )

    # Shared rows are represented by their keyed Industry contribution only. Base-model
    # terms and RHS values are intentionally excluded from the sector audit.
    for family, component_name in SHARED_FAMILIES.items():
        component = getattr(instance, component_name)
        for constraint in component.values():
            key = canonicalizer.row_key(family, constraint.index())
            raw_terms, _, _ = constraint_terms(constraint)
            terms = _industry_terms(raw_terms, canonicalizer)
            if not terms:
                if family == "biomass_availability":
                    result.add(
                        "row",
                        family,
                        key,
                        normalized_records(key, "==", 0.0, {}),
                        0,
                    )
                    continue
                result.excluded[("row", f"{family}:no_industry_terms")] += 1
                continue
            result.add(
                "row",
                family,
                key,
                normalized_records(key, "==", 0.0, terms),
                len(terms),
            )

    for component_name, (canonical, _) in VARIABLES.items():
        for variable in getattr(instance, component_name).values():
            _, key = canonicalizer.variable(variable)
            lower = -math.inf if variable.lb is None else float(value(variable.lb))
            upper = math.inf if variable.ub is None else float(value(variable.ub))
            result.add("variable", canonical, key, raw_records(key, (lower, upper)))

    objective = generate_standard_repn(instance.Obj.expr, compute_values=True)
    if not objective.is_linear():
        raise ValueError("nonlinear objective")
    for variable, coefficient_raw in zip(objective.linear_vars, objective.linear_coefs):
        component = variable.parent_component().local_name
        group = OBJECTIVE_GROUPS.get(component)
        if group is None:
            continue
        _, key = canonicalizer.variable(variable)
        result.add(
            "objective",
            group,
            key,
            raw_records(key, (float(value(coefficient_raw)),)),
        )

    result.write(
        output,
        {
            "schema": 1,
            "side": "InternalEMPIRE",
            "scope": "industry",
            "periods": len(instance.Period),
            "weather_scenarios": len(instance.Scenario),
            "gas_scenarios": len(instance.GasScenario),
            "operational_hours": len(instance.Operationalhour),
            "precisions": ",".join(map(str, PRECISIONS)),
            "buckets": BUCKETS,
        },
    )
    print(f"industry_algebra_fingerprint={output}")
    return output
