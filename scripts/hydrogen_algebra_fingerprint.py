#!/usr/bin/env python3
"""Canonical streaming fingerprints for the InternalEMPIRE Hydrogen/CO2 algebra.

The implementation deliberately mirrors the documented real-LP comparison in
``compare_hydrogen_matrix.py`` without materializing an LP or retaining millions of
rows.  Records are normalized for uniform row scaling/sign and folded into SHA-256
multiset accumulators.  Per-bucket accumulators make a mismatch localizable without
weakening the fail-closed whole-family digest.
"""

from __future__ import annotations

import hashlib
import math
import re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


PRECISIONS = (9, 12)
BUCKETS = 256
MASK64 = (1 << 64) - 1

FAMILIES = {
    "flow_balance": "hydrogen_flow_balance",
    "pipeline_capacity": "pipeline_cap",
    "electrolyzer_conversion": "hydrogen_production",
    "electrolyzer_capacity": "hydrogen_production_electrolyzer_capacity",
    "reformer_capacity": "hydrogen_production_reformer_capacity",
    "reformer_conversion": "hydrogen_link_reformer_ton_MWh",
    "reformer_natural_gas": "naturalGas_for_hydrogen",
    "reformer_ramp": "hydrogen_reformer_ramp",
    "storage_compression": "hydrogen_storage_compression_power_constraint",
    "storage_balance": "hydrogen_storage_balance",
    "storage_cyclic": "hydrogen_balance_storage",
    "storage_capacity": "hydrogen_storage_operational_capacity",
    "import_capacity": "H2import_capacity",
    "import_conversion": "H2import_link_ton_MWh",
    "co2_pipeline_capacity": "co2_pipeline_cap",
    "co2_flow_balance": "co2_flow_balance",
    "co2_hourly": "co2_sequestering_max_capacity",
    "co2_total": "co2_max_total_sequestration_capacity",
    "transport_electricity": "meet_transport_elec_demand",
    "transport_hydrogen": "meet_transport_hydrogen_demand",
    "repurpose_capacity": "repurpose_cap",
    "pipeline_installed": "installedCapDefinitionPipe",
    "electrolyzer_installed": "installedCapDefinitionElyzer",
    "reformer_installed": "installedCapDefinitionReformer",
    "storage_max": "hydrogen_storage_max_capacity",
    "storage_installed": "hydrogen_storage_lifetime",
    "import_installed": "installedCapDefinitionH2Import",
    "co2_pipeline_installed": "co2_pipeline_lifetime",
    "co2_site_max": "co2_sequestering_max_installed_capacity",
}

OP = ("h", "i", "w", "gp")
PY_TAIL = {name: OP for name in FAMILIES}
PY_TAIL.update(
    {
        "co2_total": ("w", "gp"),
        "transport_electricity": ("i", "w", "gp", "h"),
        "transport_hydrogen": ("i", "w", "gp", "h"),
    }
)
for _name in (
    "repurpose_capacity",
    "pipeline_installed",
    "electrolyzer_installed",
    "reformer_installed",
    "storage_max",
    "storage_installed",
    "import_installed",
    "co2_pipeline_installed",
    "co2_site_max",
):
    PY_TAIL[_name] = ("i",)

VARIABLES: dict[str, tuple[str, bool]] = {}
for _python_name, _canonical, _operational in (
    ("H2Imported_ton", "import_ton", True),
    ("H2Imported_MWh", "import_mwh", True),
    ("hydrogenProducedElectro_ton", "electrolyzer_h2", True),
    ("powerForHydrogen", "electrolyzer_power", True),
    ("hydrogenProducedReformer_ton", "reformer_ton", True),
    ("hydrogenProducedReformer_MWh", "reformer_mwh", True),
    ("ng_forHydrogen", "reformer_gas", True),
    ("hydrogenSentPipeline", "pipeline_flow", True),
    ("hydrogenStorageOperational", "storage_level", True),
    ("hydrogenChargeStorage", "storage_charge", True),
    ("hydrogenDischargeStorage", "storage_discharge", True),
    ("hydrogen_storage_compression_power", "storage_power", True),
    ("transport_electricityDemandMet", "transport_electricity_met", True),
    ("transport_electricityDemandShed", "transport_electricity_shed", True),
    ("transport_hydrogenDemandMet", "transport_hydrogen_met", True),
    ("transport_hydrogenDemandShed", "transport_hydrogen_shed", True),
    ("CO2sentPipeline", "co2_flow", True),
    ("CO2sequestered", "co2_sequestered", True),
    ("genOperational", "generation", True),
    ("hydrogenForPower", "hydrogen_for_power", True),
    ("H2ImportCapBuilt", "import_built", False),
    ("H2ImportTotalCap", "import_total", False),
    ("elyzerCapBuilt", "electrolyzer_built", False),
    ("elyzerTotalCap", "electrolyzer_total", False),
    ("ReformerCapBuilt", "reformer_built", False),
    ("ReformerTotalCap", "reformer_total", False),
    ("hydrogenPipelineBuilt", "pipeline_built", False),
    ("repurposedPipelineBuilt", "repurposed_built", False),
    ("totalHydrogenPipelineCapacity", "pipeline_total", False),
    ("hydrogenStorageBuilt", "storage_built", False),
    ("hydrogenTotalStorage", "storage_total", False),
    ("CO2PipelineBuilt", "co2_pipeline_built", False),
    ("totalCO2PipelineCapacity", "co2_pipeline_total", False),
    ("CO2SiteCapacityDeveloped", "co2_site_built", False),
):
    VARIABLES[_python_name] = (_canonical, _operational)

STORAGE_VARIABLES = {
    "storage_level",
    "storage_charge",
    "storage_discharge",
    "storage_power",
    "storage_built",
    "storage_total",
}
UNDIRECTED_VARIABLES = {
    "pipeline_built",
    "pipeline_total",
    "co2_pipeline_built",
    "co2_pipeline_total",
}
STORAGE_FAMILIES = {
    "storage_compression",
    "storage_balance",
    "storage_cyclic",
    "storage_capacity",
    "storage_installed",
    "storage_max",
}

OBJECTIVE_GROUPS = {
    "H2Imported_ton": "terminal_import",
    "hydrogenProducedReformer_ton": "reformer_operation",
    "transport_electricityDemandShed": "transport_electricity_shed",
    "transport_hydrogenDemandShed": "transport_hydrogen_shed",
    "elyzerCapBuilt": "electrolyzer_investment",
    "ReformerCapBuilt": "reformer_investment",
    "hydrogenPipelineBuilt": "hydrogen_pipeline_investment",
    "repurposedPipelineBuilt": "repurposed_pipeline_investment",
    "hydrogenStorageBuilt": "storage_investment",
    "H2ImportCapBuilt": "terminal_investment",
    "CO2PipelineBuilt": "co2_pipeline_investment",
    "CO2SiteCapacityDeveloped": "co2_site_investment",
}
HYDROGEN_GENERATORS = {"HydrogenCCGT", "HydrogenOCGT", "Hydrogenfuelcell"}


def canonical_component(value: object) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", str(value))


def entity_key(values: Iterable[object], *, undirected: bool = False) -> str:
    parts = [canonical_component(value) for value in values]
    if undirected and len(parts) >= 2:
        parts[:2] = sorted(parts[:2])
    return "~".join(parts)


def scenario_number(value: object) -> int:
    match = re.fullmatch(r"scenario(\d+)", str(value))
    return int(match.group(1)) if match else int(value)


def float_text(value: float, precision: int) -> str:
    if value == 0.0:
        value = 0.0
    if math.isinf(value):
        return "+inf" if value > 0 else "-inf"
    return f"{value:.{precision}e}"


def _sha_limbs(payload: str) -> tuple[int, int, int, int]:
    digest = hashlib.sha256(payload.encode("utf-8")).digest()
    return tuple(int.from_bytes(digest[offset : offset + 8], "big") for offset in range(0, 32, 8))


@dataclass
class Accumulator:
    count: int = 0
    terms: int = 0
    xor: list[int] = field(default_factory=lambda: [0, 0, 0, 0])
    total: list[int] = field(default_factory=lambda: [0, 0, 0, 0])

    def add(self, payload: str, terms: int = 0) -> None:
        self.count += 1
        self.terms += terms
        for index, limb in enumerate(_sha_limbs(payload)):
            self.xor[index] ^= limb
            self.total[index] = (self.total[index] + limb) & MASK64

    def fields(self) -> list[str]:
        return [
            str(self.count),
            str(self.terms),
            *(f"{value:016x}" for value in self.xor),
            *(f"{value:016x}" for value in self.total),
        ]


class Fingerprints:
    def __init__(self) -> None:
        self.overall: dict[tuple[str, str, int], Accumulator] = defaultdict(Accumulator)
        self.buckets: dict[tuple[str, str, int, int], Accumulator] = defaultdict(Accumulator)
        self.excluded: dict[tuple[str, str], int] = defaultdict(int)

    def add(self, kind: str, group: str, key: str, records: dict[int, str], terms: int = 0) -> None:
        bucket = hashlib.sha256(key.encode("utf-8")).digest()[0]
        for precision, payload in records.items():
            self.overall[(kind, group, precision)].add(payload, terms)
            self.buckets[(kind, group, precision, bucket)].add(payload, terms)

    def write(self, path: Path, metadata: dict[str, object]) -> None:
        with path.open("w", encoding="utf-8") as handle:
            for key, value in sorted(metadata.items()):
                handle.write(f"META\t{key}\t{value}\n")
            for (kind, group), count in sorted(self.excluded.items()):
                handle.write(f"EXCLUDED\t{kind}\t{group}\t{count}\n")
            for (kind, group, precision), accumulator in sorted(self.overall.items()):
                handle.write(
                    "\t".join(("SUMMARY", kind, group, str(precision), *accumulator.fields()))
                    + "\n"
                )
            for (kind, group, precision, bucket), accumulator in sorted(self.buckets.items()):
                handle.write(
                    "\t".join(
                        ("BUCKET", kind, group, str(precision), str(bucket), *accumulator.fields())
                    )
                    + "\n"
                )


class InternalCanonicalizer:
    def __init__(self, instance: object, valid_storage_pairs: set[tuple[str, str]]) -> None:
        self.instance = instance
        self.valid_storage_pairs = valid_storage_pairs
        self.valid_power_pairs = {
            (str(node), str(generator))
            for node, generator in instance.GeneratorsOfNode
            if generator in instance.HydrogenGenerators
        }
        self.valid_terminal_pairs = {
            (str(node), str(terminal)) for node, terminal in instance.H2TerminalsOfNode
        }
        self.hour_context: dict[int, tuple[int, int]] = {}
        seasons = list(instance.Season)
        for representative, season in enumerate(seasons, 1):
            hours = [int(hour) for candidate, hour in instance.HoursOfSeason if candidate == season]
            for local_hour, hour in enumerate(hours, 1):
                self.hour_context[hour] = (representative, local_hour)

    @staticmethod
    def _tuple(index: object) -> tuple[object, ...]:
        return index if isinstance(index, tuple) else (index,)

    def time_key(self, tail: dict[str, object], *, drop_hour: bool = False) -> str:
        parts: list[str] = []
        if "i" in tail:
            parts.append(f"sp{int(tail['i'])}")
        hour_context = None
        if "h" in tail:
            hour_context = self.hour_context[int(tail["h"])]
            representative, _ = hour_context
            parts.append(f"rp{representative}")
        if "w" in tail:
            parts.append(f"sc{scenario_number(tail['w'])}")
        if hour_context is not None and not drop_hour:
            _, hour = hour_context
            parts.append(f"t{hour}")
        return "_".join(parts)

    def row_key(self, family: str, index: object) -> tuple[str, tuple[object, ...]]:
        values = self._tuple(index)
        spec = PY_TAIL[family]
        entity = values[: len(values) - len(spec)] if spec else values
        tail = dict(zip(spec, values[len(values) - len(spec) :])) if spec else {}
        undirected = family in {"pipeline_installed", "co2_pipeline_installed"}
        return (
            f"{family}|{entity_key(entity, undirected=undirected)}|"
            f"{self.time_key(tail, drop_hour=family == 'storage_cyclic')}",
            entity,
        )

    def variable(self, variable: object) -> tuple[str, str, bool]:
        component = variable.parent_component().local_name
        info = VARIABLES.get(component)
        if info is None:
            raise KeyError(component)
        canonical, operational = info
        values = list(self._tuple(variable.index()))
        if operational:
            entity = values[:-4]
            tail = dict(zip(OP, values[-4:]))
            if canonical == "hydrogen_for_power":
                entity = [entity[1], entity[0]]
        else:
            entity = values[:-1]
            tail = {"i": values[-1]}
        valid = True
        if canonical in STORAGE_VARIABLES:
            valid = (str(entity[0]), str(entity[1])) in self.valid_storage_pairs
        elif canonical in {"import_ton", "import_mwh"}:
            valid = (str(entity[0]), str(entity[1])) in self.valid_terminal_pairs
        elif canonical == "hydrogen_for_power":
            valid = (str(entity[0]), str(entity[1])) in self.valid_power_pairs
        undirected = canonical in UNDIRECTED_VARIABLES
        key = f"{canonical}|{entity_key(entity, undirected=undirected)}|{self.time_key(tail)}"
        return canonical, key, valid


def _constraint_terms(constraint: object) -> tuple[list[tuple[object, float]], str, float]:
    from pyomo.environ import value
    from pyomo.repn.standard_repn import generate_standard_repn

    representation = generate_standard_repn(constraint.body, compute_values=True)
    if not representation.is_linear():
        raise ValueError(f"nonlinear Hydrogen row: {constraint.name}")
    terms = [
        (variable, float(value(coefficient)))
        for variable, coefficient in zip(
            representation.linear_vars, representation.linear_coefs
        )
    ]
    constant = float(value(representation.constant or 0.0))
    lower = None if constraint.lower is None else float(value(constraint.lower)) - constant
    upper = None if constraint.upper is None else float(value(constraint.upper)) - constant
    if lower is not None and upper is not None and lower == upper:
        return terms, "==", lower
    if upper is not None and lower is None:
        return terms, "<=", upper
    if lower is not None and upper is None:
        return terms, ">=", lower
    raise ValueError(f"unsupported ranged Hydrogen row: {constraint.name}")


def _normalized_records(key: str, sense: str, rhs: float, terms: dict[str, float]) -> dict[int, str]:
    terms = {name: value for name, value in terms.items() if value != 0.0}
    scale = max((abs(value) for value in (*terms.values(), rhs)), default=0.0)
    if scale:
        terms = {name: value / scale for name, value in terms.items()}
        rhs /= scale
    first = next((terms[name] for name in sorted(terms) if terms[name] != 0.0), rhs)
    if first < 0.0:
        terms = {name: -value for name, value in terms.items()}
        rhs = -rhs
        sense = {"<=": ">=", ">=": "<=", "==": "=="}[sense]
    return {
        precision: "\t".join(
            (
                key,
                sense,
                float_text(rhs, precision),
                ";".join(
                    f"{name}={float_text(value, precision)}" for name, value in sorted(terms.items())
                ),
            )
        )
        for precision in PRECISIONS
    }


def _raw_records(key: str, values: Iterable[float]) -> dict[int, str]:
    values = tuple(values)
    return {
        precision: "\t".join((key, *(float_text(value, precision) for value in values)))
        for precision in PRECISIONS
    }


def _valid_storage_pairs(path: Path) -> set[tuple[str, str]]:
    pairs: set[tuple[str, str]] = set()
    with path.open(encoding="utf-8-sig") as handle:
        next(handle)
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 2:
                pairs.add((fields[0], fields[1]))
    return pairs


def export_internal_fingerprints(instance: object, output: Path, tabs: Path) -> Path:
    """Export normalized InternalEMPIRE fingerprints from an already-built instance."""
    from pyomo.environ import value
    from pyomo.repn.standard_repn import generate_standard_repn

    valid_storage_pairs = _valid_storage_pairs(tabs / "Hydrogen_StorageMaxCapacity.tab")
    canonicalizer = InternalCanonicalizer(instance, valid_storage_pairs)
    result = Fingerprints()

    for family, component_name in FAMILIES.items():
        component = getattr(instance, component_name)
        for constraint in component.values():
            key, entity = canonicalizer.row_key(family, constraint.index())
            if family in STORAGE_FAMILIES and (str(entity[0]), str(entity[1])) not in valid_storage_pairs:
                result.excluded[("row", family)] += 1
                continue
            raw_terms, sense, rhs = _constraint_terms(constraint)
            terms: dict[str, float] = defaultdict(float)
            co2_site_coefficients: list[float] = []
            for variable, coefficient in raw_terms:
                canonical, column, valid = canonicalizer.variable(variable)
                if family == "flow_balance" and not valid and (
                    canonical in STORAGE_VARIABLES or canonical == "hydrogen_for_power"
                ):
                    result.excluded[("term", f"{family}:{canonical}")] += 1
                    continue
                if family in {"pipeline_capacity", "co2_pipeline_capacity"} and canonical in {
                    "pipeline_total",
                    "co2_pipeline_total",
                }:
                    _, row_entity, _ = key.split("|", 2)
                    canonical_entity = entity_key(row_entity.split("~"), undirected=True)
                    column = f"{canonical}|{canonical_entity}|{column.rsplit('|', 1)[1]}"
                if family in {"co2_hourly", "co2_site_max"} and canonical == "co2_site_built":
                    co2_site_coefficients.append(coefficient)
                    continue
                terms[column] += coefficient
            if co2_site_coefficients:
                if max(co2_site_coefficients) - min(co2_site_coefficients) > 1e-12:
                    raise ValueError(f"inconsistent cumulative CO2 coefficients in {constraint.name}")
                _, row_entity, row_time = key.split("|", 2)
                period = row_time.split("_", 1)[0]
                terms[f"co2_site_installed|{row_entity}|{period}"] += co2_site_coefficients[0]
            result.add("row", family, key, _normalized_records(key, sense, rhs, terms), len(terms))

    for component_name, (canonical, _) in VARIABLES.items():
        component = getattr(instance, component_name)
        for variable in component.values():
            _, key, valid = canonicalizer.variable(variable)
            if canonical == "generation":
                index = canonicalizer._tuple(variable.index())
                if str(index[1]) not in HYDROGEN_GENERATORS:
                    continue
            if not valid:
                result.excluded[("variable", canonical)] += 1
                continue
            lower = -math.inf if variable.lb is None else float(value(variable.lb))
            upper = math.inf if variable.ub is None else float(value(variable.ub))
            result.add("variable", canonical, key, _raw_records(key, (lower, upper)))

    objective = generate_standard_repn(instance.Obj.expr, compute_values=True)
    for variable, coefficient_raw in zip(objective.linear_vars, objective.linear_coefs):
        component = variable.parent_component().local_name
        group = OBJECTIVE_GROUPS.get(component)
        if component == "genOperational":
            index = canonicalizer._tuple(variable.index())
            generator = str(index[1])
            if generator in HYDROGEN_GENERATORS:
                group = f"generation_{generator}"
        if group is None:
            continue
        _, key, valid = canonicalizer.variable(variable)
        if not valid:
            result.excluded[("objective", group)] += 1
            continue
        coefficient = float(value(coefficient_raw))
        result.add("objective", group, key, _raw_records(key, (coefficient,)))

    result.write(
        output,
        {
            "schema": 1,
            "side": "InternalEMPIRE",
            "periods": len(instance.Period),
            "weather_scenarios": len(instance.Scenario),
            "gas_scenarios": len(instance.GasScenario),
            "operational_hours": len(instance.Operationalhour),
            "precisions": ",".join(map(str, PRECISIONS)),
            "buckets": BUCKETS,
        },
    )
    print(f"hydrogen_algebra_fingerprint={output}")
    return output
