#!/usr/bin/env python3
"""Compare full InternalEMPIRE and OpenEMPIRE.jl Hydrogen/CO2 results.

Operational dispatch is intentionally outside this comparator: it is not unique
even when investments and the objective agree, and the parity contract explicitly
uses only stable quantities.
"""

from __future__ import annotations

import argparse
import csv
import math
from dataclasses import dataclass
from pathlib import Path
import re
from typing import Iterable


@dataclass(frozen=True)
class CapacitySpec:
    name: str
    internal_file: str
    julia_file: str
    key_columns: tuple[str, ...]
    value_column: str
    undirected_pair: bool = False


@dataclass(frozen=True)
class GurobiAudit:
    raw_rows: int
    raw_columns: int
    raw_nonzeros: int
    presolved_rows: int
    presolved_columns: int
    presolved_nonzeros: int
    barrier_primal: float
    barrier_dual: float
    barrier_primal_residual: float
    barrier_dual_residual: float
    barrier_complementarity: float
    barrier_bracket_rounding: float
    final_primal_infeasibility: float
    final_dual_infeasibility: float
    final_objective: float
    final_objective_rounding: float
    certified_optimal: bool
    crossover_used: bool

    @property
    def barrier_bracket_width(self) -> float:
        # Gurobi prints barrier objectives with nine significant digits. Include
        # the maximum endpoint-rounding uncertainty instead of treating equal
        # displayed endpoints as an artificial zero-width certificate.
        return abs(self.barrier_primal - self.barrier_dual) + self.barrier_bracket_rounding


CAPACITY_SPECS = (
    CapacitySpec(
        "generator_installed",
        "genInstalledCap.tab",
        "genInstalledCap.csv",
        ("Node", "Generator", "Period"),
        "genInstalledCap",
    ),
    CapacitySpec(
        "transmission_installed",
        "transmissionInstalledCap.tab",
        "transmissionInstalledCap.csv",
        ("FromNode", "ToNode", "Period"),
        "transmissionInstalledCap",
        True,
    ),
    CapacitySpec(
        "storage_power_installed",
        "storPWInstalledCap.tab",
        "storPWInstalledCap.csv",
        ("Node", "Storage", "Period"),
        "storPWInstalledCap",
    ),
    CapacitySpec(
        "storage_energy_installed",
        "storENInstalledCap.tab",
        "storENInstalledCap.csv",
        ("Node", "Storage", "Period"),
        "storENInstalledCap",
    ),
    CapacitySpec(
        "offshore_converter_installed",
        "offshoreConvInstalledCap.tab",
        "offshoreConvInstalledCap.csv",
        ("Node", "Period"),
        "offshoreConvInstalledCap",
    ),
    CapacitySpec(
        "electrolyzer_installed",
        "elyzerTotalCap.tab",
        "elyzerTotalCap.csv",
        ("Node", "Period"),
        "elyzerTotalCap",
    ),
    CapacitySpec(
        "reformer_installed",
        "ReformerTotalCap.tab",
        "ReformerTotalCap.csv",
        ("Node", "ReformerPlant", "Period"),
        "ReformerTotalCap",
    ),
    CapacitySpec(
        "hydrogen_pipeline_installed",
        "totalHydrogenPipelineCapacity.tab",
        "totalHydrogenPipelineCapacity.csv",
        ("FromNode", "ToNode", "Period"),
        "totalHydrogenPipelineCapacity",
        True,
    ),
    CapacitySpec(
        "repurposed_gas_pipeline_built",
        "repurposedPipelineBuilt.tab",
        "repurposedPipelineBuilt.csv",
        ("FromNode", "ToNode", "Period"),
        "repurposedPipelineBuilt",
    ),
    CapacitySpec(
        "hydrogen_storage_installed",
        "hydrogenTotalStorage.tab",
        "hydrogenTotalStorage.csv",
        ("Node", "H2Storage", "Period"),
        "hydrogenTotalStorage",
    ),
    CapacitySpec(
        "hydrogen_import_installed",
        "H2ImportTotalCap.tab",
        "H2ImportTotalCap.csv",
        ("Node", "TerminalType", "Period"),
        "H2ImportTotalCap",
    ),
    CapacitySpec(
        "co2_pipeline_installed",
        "totalCO2PipelineCapacity.tab",
        "totalCO2PipelineCapacity.csv",
        ("FromNode", "ToNode", "Period"),
        "totalCO2PipelineCapacity",
        True,
    ),
    CapacitySpec(
        "co2_site_capacity_developed",
        "CO2SiteCapacityDeveloped.tab",
        "CO2SiteCapacityDeveloped.csv",
        ("Node", "Period"),
        "CO2SiteCapacityDeveloped",
    ),
)

OBJECTIVE_COMPONENTS = (
    "generator_investment",
    "storage_investment",
    "transmission_investment",
    "offshore_converter_investment",
    "load_shedding",
    "generator_operation",
    "natural_gas_terminal_import",
    "natural_gas_transport_shedding",
    "hydrogen_investment",
    "hydrogen_terminal_import",
    "hydrogen_reformer_operation",
    "hydrogen_transport_shedding",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--internal-results", required=True, type=Path)
    parser.add_argument(
        "--internal-components",
        required=True,
        type=Path,
        help="objective_components.csv emitted by run_internalempire_hydrogen.py",
    )
    parser.add_argument(
        "--julia-run",
        required=True,
        type=Path,
        help="Julia run directory containing summary.txt and output/",
    )
    parser.add_argument("--objective-ppm", type=float, default=20.0)
    parser.add_argument("--capacity-atol", type=float, default=1e-3)
    parser.add_argument("--capacity-rtol", type=float, default=1e-5)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument(
        "--internal-log",
        required=True,
        type=Path,
        help="InternalEMPIRE Gurobi/stdout log used to enforce certification",
    )
    parser.add_argument(
        "--julia-log",
        required=True,
        type=Path,
        help="OpenEMPIRE.jl Gurobi/stdout log used to enforce certification",
    )
    return parser.parse_args()


def parse_summary(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            key, separator, value = line.strip().partition("=")
            if separator:
                values[key] = value
    return values


_NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
_RAW_MODEL = re.compile(
    r"Optimize a model with (\d+) rows, (\d+) columns and (\d+) nonzeros"
)
_PRESOLVED_MODEL = re.compile(
    r"Presolved:\s*(\d+) rows, (\d+) columns, (\d+) nonzeros"
)
_BARRIER_ROW = re.compile(
    rf"^\s*\d+\s+({_NUMBER})\s+({_NUMBER})\s+({_NUMBER})\s+"
    rf"({_NUMBER})\s+({_NUMBER})\s+\d+s\s*$"
)
_SIMPLEX_ROW = re.compile(
    rf"^\s*\d+\s+({_NUMBER})\s+({_NUMBER})\s+({_NUMBER})\s+\d+s\s*$"
)
_OPTIMAL_OBJECTIVE = re.compile(rf"Optimal objective\s+({_NUMBER})")
_SUBOPTIMAL_OBJECTIVE = re.compile(
    rf"Sub-optimal termination\s+-\s+objective\s+({_NUMBER})"
)


def displayed_quantum(number: str) -> float:
    mantissa, _, exponent = number.lower().partition("e")
    decimals = len(mantissa.partition(".")[2])
    return 10.0 ** (int(exponent or "0") - decimals)


def parse_gurobi_audit(path: Path) -> GurobiAudit:
    raw_dimensions: tuple[int, int, int] | None = None
    presolved_dimensions: tuple[int, int, int] | None = None
    barrier: tuple[float, float, float, float, float] | None = None
    barrier_bracket_rounding: float | None = None
    crossover_infeasibility: tuple[float, float] | None = None
    final_objective: float | None = None
    final_objective_rounding: float | None = None
    in_crossover = False
    solved_after_crossover = False
    barrier_solved = False

    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if match := _RAW_MODEL.search(line):
                raw_dimensions = tuple(map(int, match.groups()))
            if match := _PRESOLVED_MODEL.search(line):
                presolved_dimensions = tuple(map(int, match.groups()))
            if not in_crossover and (match := _BARRIER_ROW.fullmatch(line.rstrip())):
                barrier = tuple(map(float, match.groups()))
                barrier_bracket_rounding = 0.5 * (
                    displayed_quantum(match.group(1))
                    + displayed_quantum(match.group(2))
                )
            if "Crossover log" in line:
                in_crossover = True
            elif in_crossover and (match := _SIMPLEX_ROW.fullmatch(line.rstrip())):
                _, primal_infeasibility, dual_infeasibility = map(float, match.groups())
                crossover_infeasibility = (
                    primal_infeasibility,
                    dual_infeasibility,
                )
            if in_crossover and line.lstrip().startswith("Solved in "):
                solved_after_crossover = True
            if "Barrier solved model" in line:
                barrier_solved = True
            if match := _OPTIMAL_OBJECTIVE.search(line):
                final_objective = float(match.group(1))
                final_objective_rounding = 0.5 * displayed_quantum(match.group(1))
            elif match := _SUBOPTIMAL_OBJECTIVE.search(line):
                # Retain the returned value for diagnostics while leaving the
                # optimality flag false. A failed certificate must produce DIFF,
                # not make the audit parser abort before explaining the failure.
                final_objective = float(match.group(1))
                final_objective_rounding = 0.5 * displayed_quantum(match.group(1))

    missing = [
        name
        for name, value in (
            ("raw dimensions", raw_dimensions),
            ("presolved dimensions", presolved_dimensions),
            ("final barrier row", barrier),
            ("barrier display resolution", barrier_bracket_rounding),
            ("optimal objective", final_objective),
            ("optimal-objective display resolution", final_objective_rounding),
        )
        if value is None
    ]
    if in_crossover and crossover_infeasibility is None:
        missing.append("final crossover infeasibility")
    if missing:
        raise ValueError(f"Cannot parse {', '.join(missing)} from {path}")

    assert raw_dimensions is not None
    assert presolved_dimensions is not None
    assert barrier is not None
    assert barrier_bracket_rounding is not None
    assert final_objective is not None
    assert final_objective_rounding is not None
    final_infeasibility = (
        crossover_infeasibility
        if crossover_infeasibility is not None
        else (barrier[2], barrier[3])
    )
    return GurobiAudit(
        *raw_dimensions,
        *presolved_dimensions,
        *barrier,
        barrier_bracket_rounding,
        *final_infeasibility,
        final_objective,
        final_objective_rounding,
        solved_after_crossover if in_crossover else barrier_solved,
        in_crossover,
    )


def format_gurobi_audit(name: str, audit: GurobiAudit) -> str:
    lower = min(audit.barrier_primal, audit.barrier_dual)
    upper = max(audit.barrier_primal, audit.barrier_dual)
    return (
        f"{name}: certified_optimal={audit.certified_optimal} "
        f"solution={'crossover' if audit.crossover_used else 'barrier'} "
        f"raw={audit.raw_rows}x{audit.raw_columns}({audit.raw_nonzeros}) "
        f"presolved={audit.presolved_rows}x{audit.presolved_columns}"
        f"({audit.presolved_nonzeros}) barrier_bracket=[{lower:.17g},{upper:.17g}] "
        f"conservative_bracket_width={audit.barrier_bracket_width:.17g} "
        f"barrier_primal_residual={audit.barrier_primal_residual:.9g} "
        f"barrier_dual_residual={audit.barrier_dual_residual:.9g} "
        f"barrier_complementarity={audit.barrier_complementarity:.9g} "
        f"final_primal_infeasibility={audit.final_primal_infeasibility:.9g} "
        f"final_dual_infeasibility={audit.final_dual_infeasibility:.9g} "
        f"gurobi_objective={audit.final_objective:.17g} "
        f"gurobi_objective_rounding={audit.final_objective_rounding:.17g}"
    )


def aligned_barrier_interval(audit: GurobiAudit, returned_objective: float) -> tuple[float, float]:
    """Align the presolved barrier interval with the returned original-model primal."""
    dual_offset = audit.barrier_dual - audit.barrier_primal
    return (
        returned_objective + min(0.0, dual_offset),
        returned_objective + max(0.0, dual_offset),
    )


def internal_objective(path: Path) -> float:
    first_line = path.read_text(encoding="utf-8").splitlines()[0]
    match = re.fullmatch(
        r"Objective function value:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)",
        first_line,
    )
    if match is None:
        raise ValueError(f"Cannot parse objective from {path}: {first_line!r}")
    return float(match.group(1))


def sum_last_column(path: Path) -> float:
    total = 0.0
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.reader(handle)
        next(rows)
        for row in rows:
            if row:
                total += float(row[-1])
    return total


def investment_components(root: Path) -> dict[str, float]:
    generation = 0.0
    offshore = 0.0
    section = "generation"
    path = root / "results_objective_components_generation_inv_costs.csv"
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.reader(handle):
            if not row:
                continue
            if row[:3] == ["Node", "Period", "offshoreConversionInvestedCost_Euro"]:
                section = "offshore"
                continue
            if row[0] == "Node":
                continue
            if section == "generation":
                generation += float(row[3])
            else:
                offshore += float(row[2])

    return {
        "generator_investment": generation,
        "storage_investment": sum_last_column(
            root / "results_objective_components_storage_inv_costs.csv"
        ),
        "transmission_investment": sum_last_column(
            root / "results_objective_components_transmission_inv_costs.csv"
        ),
        "offshore_converter_investment": offshore,
    }


def generator_operation_component(path: Path) -> float:
    """Aggregate IE's report, restoring omitted uniform scenario probabilities."""
    total = 0.0
    scenarios: set[str] = set()
    gas_scenarios: set[str] = set()
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        for row in rows:
            if not row.get("OperationalCost_Euro"):
                break
            scenarios.add(row["Scenario"])
            gas_scenarios.add(row["GasScenario"])
            total += float(row["OperationalCost_Euro"])
    if not scenarios or not gas_scenarios:
        raise ValueError(f"No operational-cost rows in {path}")
    return total / (len(scenarios) * len(gas_scenarios))


def period_ordinals(labels: Iterable[str]) -> dict[str, int]:
    unique = sorted(set(labels), key=lambda label: tuple(map(int, re.findall(r"\d+", label))))
    return {label: index + 1 for index, label in enumerate(unique)}


def internal_generator_operation_by_key(path: Path) -> dict[tuple[str, str, int], float]:
    records: list[dict[str, str]] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if not row.get("OperationalCost_Euro"):
                break
            records.append(row)
    period_index = period_ordinals(row["Period"] for row in records)
    scenario_count = len({row["Scenario"] for row in records})
    gas_scenario_count = len({row["GasScenario"] for row in records})
    probability_denominator = scenario_count * gas_scenario_count
    result: dict[tuple[str, str, int], float] = {}
    for row in records:
        key = (row["Node"], row["GeneratorType"], period_index[row["Period"]])
        result[key] = result.get(key, 0.0) + float(row["OperationalCost_Euro"]) / probability_denominator
    return result


def julia_generator_operation_by_key(
    output: Path, discount_rate: float, period_years: int
) -> dict[tuple[str, str, int], float]:
    marginal_cost: dict[tuple[str, int], float] = {}
    with (output / "marginal_costs.csv").open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            marginal_cost[(row["Generator"], int(row["Period"]))] = float(
                row["MarginalCost_EurperMWh"]
            )

    with (output / "results_output_gen.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        records = list(csv.DictReader(handle))
    period_index = period_ordinals(row["Period"] for row in records)
    operational_discount = math.fsum(
        (1 + discount_rate) ** -year for year in range(period_years)
    )
    result: dict[tuple[str, str, int], float] = {}
    for row in records:
        period = period_index[row["Period"]]
        strategic_discount = (1 + discount_rate) ** (-period_years * (period - 1))
        key = (row["Node"], row["GeneratorType"], period)
        result[key] = (
            float(row["genExpectedAnnualProduction_GWh"])
            * 1000
            * marginal_cost[(row["GeneratorType"], period)]
            * operational_discount
            * strategic_discount
        )
    return result


def report_generator_cost_differences(
    internal_root: Path,
    julia_output: Path,
    discount_rate: float,
    period_years: int,
    top: int,
) -> list[str]:
    internal = internal_generator_operation_by_key(
        internal_root / "results_objective_components_operational_costs.csv"
    )
    julia = julia_generator_operation_by_key(
        julia_output, discount_rate, period_years
    )
    keys = set(internal) | set(julia)
    differences = sorted(
        (
            abs(internal.get(key, 0.0) - julia.get(key, 0.0)),
            key,
            internal.get(key, 0.0),
            julia.get(key, 0.0),
        )
        for key in keys
    )
    differences.reverse()
    lines = [
        f"reconstructed_totals: ie={math.fsum(internal.values()):.17g} "
        f"jl={math.fsum(julia.values()):.17g}"
    ]
    for absolute, key, left, right in differences[:top]:
        lines.append(
            f"  {'|'.join(map(str, key))} ie={left:.12g} jl={right:.12g} "
            f"signed_jl_minus_ie={right - left:.12g} abs={absolute:.12g}"
        )
    return lines


def internal_components(path: Path) -> dict[str, float]:
    components: dict[str, float] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            name = row["component"]
            if name in components:
                raise ValueError(f"Duplicate objective component in {path}: {name}")
            components[name] = float(row["value"])
    missing = set(OBJECTIVE_COMPONENTS) - set(components)
    extra = set(components) - set(OBJECTIVE_COMPONENTS)
    if missing or extra:
        raise ValueError(
            f"Unexpected objective components in {path}: "
            f"missing={sorted(missing)}, extra={sorted(extra)}"
        )
    return components


def julia_components(summary: dict[str, str]) -> dict[str, float]:
    prefix = "objective_component_"
    available = {
        key[len(prefix) :]: float(value)
        for key, value in summary.items()
        if key.startswith(prefix)
    }
    missing = set(OBJECTIVE_COMPONENTS) - set(available)
    if missing:
        raise ValueError(f"Julia summary is missing objective components: {sorted(missing)}")
    return {name: available[name] for name in OBJECTIVE_COMPONENTS}


def transmission_report_components(path: Path) -> dict[str, float]:
    columns = {
        "transmission_investment": "TransmissionInvCost",
        "hydrogen_pipeline_investment": "HydrogenPipelineInvCost",
        "repurposed_pipeline_investment": "RepurposedPipeilineInvCost",
        "co2_pipeline_investment": "CO2PipelineInvCost",
    }
    _, totals = sum_columns(path, columns)
    return totals


def hydrogen_investment_report(path: Path) -> dict[str, float]:
    rows: list[dict[str, str]] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"No hydrogen investment rows in {path}")
    final = rows[-1]
    columns = {
        "electrolyzer_investment": "Discounted electrolyzer cost [EUR]",
        "reformer_investment": "Discounted Reformer cost [EUR]",
        "hydrogen_pipeline_investment": "Discounted pipeline cost [EUR]",
        "hydrogen_storage_investment": "Discounted storage cost [EUR]",
        "hydrogen_import_investment": "Discounted H2 import cost [EUR]",
        "reported_hydrogen_investment": "Total discounted cost [EUR]",
    }
    return {name: float(final[column]) for name, column in columns.items()}


def read_capacity_table(
    path: Path,
    delimiter: str,
    key_columns: Iterable[str],
    value_column: str,
    undirected_pair: bool,
) -> dict[tuple[str, ...], float]:
    result: dict[tuple[str, ...], float] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle, delimiter=delimiter):
            key = tuple(row[column].strip() for column in key_columns)
            if undirected_pair:
                key = (*sorted(key[:2]), *key[2:])
            if key in result:
                raise ValueError(f"Duplicate stable key in {path}: {key}")
            result[key] = float(row[value_column])
    return result


def ppm_difference(left: float, right: float) -> float:
    return abs(left - right) / max(abs(left), abs(right), math.ulp(0.0)) * 1e6


def compare_capacities(
    internal_root: Path,
    julia_output: Path,
    atol: float,
    rtol: float,
    top: int,
) -> tuple[bool, list[str]]:
    all_ok = True
    lines: list[str] = []
    for spec in CAPACITY_SPECS:
        internal_path = internal_root / spec.internal_file
        julia_path = julia_output / spec.julia_file
        missing_files = [
            str(path)
            for path in (internal_path, julia_path)
            if not path.is_file()
        ]
        if missing_files:
            all_ok = False
            lines.append(
                f"{spec.name}: MISSING files={','.join(missing_files)}"
            )
            continue
        internal = read_capacity_table(
            internal_path,
            "\t",
            spec.key_columns,
            spec.value_column,
            spec.undirected_pair,
        )
        julia = read_capacity_table(
            julia_path,
            ",",
            spec.key_columns,
            spec.value_column,
            spec.undirected_pair,
        )
        internal_keys = set(internal)
        julia_keys = set(julia)
        missing = internal_keys - julia_keys
        extra = julia_keys - internal_keys
        differences = []
        all_deltas = []
        for key in internal_keys & julia_keys:
            left = internal[key]
            right = julia[key]
            signed = right - left
            absolute = abs(signed)
            tolerance = atol + rtol * max(abs(left), abs(right))
            all_deltas.append((signed, left, right))
            if absolute > tolerance:
                differences.append((absolute, key, left, right))
        differences.sort(reverse=True)
        ok = not missing and not extra and not differences
        all_ok &= ok
        maximum = differences[0][0] if differences else 0.0
        material_strict_mismatches = sum(
            max(abs(left), abs(right)) > 1.0
            and abs(delta) > atol + rtol * max(abs(left), abs(right))
            for delta, left, right in all_deltas
        )
        lines.append(
            f"{spec.name}: {'OK' if ok else 'DIFF'} "
            f"keys(ie={len(internal)},jl={len(julia)},missing={len(missing)},extra={len(extra)}) "
            f"mismatches={len(differences)} max_abs={maximum:.12g}"
        )
        lines.append(
            "  all-key delta diagnostics (do not affect pass/fail): "
            f"signed_sum={math.fsum(delta for delta, _, _ in all_deltas):.12g} "
            f"abs_sum={math.fsum(abs(delta) for delta, _, _ in all_deltas):.12g} "
            f"count_abs_gt_1e-2={sum(abs(delta) > 1e-2 for delta, _, _ in all_deltas)} "
            f"material_strict_mismatches={material_strict_mismatches}"
        )
        for absolute, key, left, right in differences[:top]:
            lines.append(
                f"  {'|'.join(key)} ie={left:.12g} jl={right:.12g} "
                f"abs={absolute:.12g} ppm={ppm_difference(left, right):.6g}"
            )
    return all_ok, lines


def sum_columns(path: Path, columns: dict[str, str]) -> tuple[int, dict[str, float]]:
    totals = {name: 0.0 for name in columns}
    row_count = 0
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            row_count += 1
            for name, column in columns.items():
                totals[name] += float(row[column])
    return row_count, totals


def natural_gas_aggregate_diagnostics(
    internal_root: Path, julia_output: Path
) -> list[str]:
    internal_rows, internal = sum_columns(
        internal_root / "results_natural_gas_balance.csv",
        {
            "for_power": "Natural gas for power and heat [ton]",
            "terminal": "Natural gas produced [ton]",
            "pipeline_in": "Natural gas imported [ton]",
            "pipeline_out": "Natural gas exported [ton]",
            "storage_charge": "Natural gas storage charge [ton]",
            "storage_discharge": "Natural gas storage discharge [ton]",
        },
    )
    julia_rows, julia = sum_columns(
        julia_output / "naturalGasBalance.csv",
        {
            "for_power": "NaturalGasForPower_ton",
            "terminal": "TerminalImport_ton",
            "pipeline_in": "PipelineIn_ton",
            "pipeline_out": "PipelineOut_ton",
            "storage_charge": "StorageCharge_ton",
            "storage_discharge": "StorageDischarge_ton",
            "balance_residual": "BalanceResidual_ton",
        },
    )
    lines = [f"rows: ie={internal_rows} jl={julia_rows}"]
    for name in (
        "for_power",
        "terminal",
        "pipeline_in",
        "pipeline_out",
        "storage_charge",
        "storage_discharge",
    ):
        left = internal[name]
        right = julia[name]
        lines.append(
            f"{name}: ie={left:.17g} jl={right:.17g} "
            f"signed_jl_minus_ie={right - left:.17g} "
            f"ppm={ppm_difference(left, right):.9f}"
        )
    lines.append(f"julia_balance_residual_sum={julia['balance_residual']:.17g}")
    return lines


def main() -> int:
    args = parse_args()
    internal_root = args.internal_results.resolve()
    internal_component_path = args.internal_components.resolve()
    julia_run = args.julia_run.resolve()
    julia_output = julia_run / "output"

    summary = parse_summary(julia_run / "summary.txt")
    internal_total = internal_objective(internal_root / "results_objective.csv")
    julia_total = float(summary["objective_value"])
    objective_ppm = ppm_difference(internal_total, julia_total)

    print("InternalEMPIRE ↔ OpenEMPIRE.jl Hydrogen/CO2 verification")
    print(f"internal_results={internal_root}")
    print(f"internal_components={internal_component_path}")
    print(f"julia_run={julia_run}")
    print(f"internal_objective={internal_total:.17g}")
    print(f"julia_objective={julia_total:.17g}")
    print(f"objective_abs_diff={abs(internal_total - julia_total):.17g}")
    print(f"objective_ppm={objective_ppm:.9f}")
    print(f"julia_termination={summary.get('termination_status', 'missing')}")

    internal_audit = parse_gurobi_audit(args.internal_log)
    julia_audit = parse_gurobi_audit(args.julia_log)
    print("\nGurobi certification, convergence, and structure:")
    print(format_gurobi_audit("InternalEMPIRE", internal_audit))
    print(format_gurobi_audit("OpenEMPIRE.jl", julia_audit))
    logs_ok = internal_audit.certified_optimal and julia_audit.certified_optimal
    for name, audit, returned in (
        ("InternalEMPIRE", internal_audit, internal_total),
        ("OpenEMPIRE.jl", julia_audit, julia_total),
    ):
        aligned_lower, aligned_upper = aligned_barrier_interval(audit, returned)
        returned_matches_gurobi = (
            abs(returned - audit.final_objective) <= audit.final_objective_rounding
        )
        logs_ok = logs_ok and returned_matches_gurobi
        print(
            f"{name} postsolve_alignment: "
            f"returned_minus_displayed_primal={returned - audit.barrier_primal:.17g} "
            f"returned_aligned_interval=[{aligned_lower:.17g},{aligned_upper:.17g}] "
            f"returned_matches_gurobi_objective={returned_matches_gurobi}"
        )
    tighter_bracket = min(
        internal_audit.barrier_bracket_width,
        julia_audit.barrier_bracket_width,
    )
    objective_difference = abs(internal_total - julia_total)
    bracket_ok = objective_difference <= tighter_bracket
    # A completed crossover must end at a feasible basic solution. With
    # Crossover=0, Gurobi's `Barrier solved model` is itself the optimality
    # certificate; retain and report the final barrier residuals without
    # pretending they are simplex infeasibilities or requiring exact zeros.
    for audit in (internal_audit, julia_audit):
        if audit.crossover_used:
            logs_ok = logs_ok and audit.final_primal_infeasibility == 0.0
            logs_ok = logs_ok and audit.final_dual_infeasibility == 0.0
    print(
        f"objective_difference_within_tighter_bracket={bracket_ok} "
        f"difference={objective_difference:.17g} "
        f"tighter_conservative_bracket_width={tighter_bracket:.17g}"
    )

    print("\nObjective components (InternalEMPIRE certificate vs Julia summary.txt):")
    julia_costs = julia_components(summary)
    internal_costs = None
    if internal_component_path.is_file():
        internal_costs = internal_components(internal_component_path)
        component_differences = []
        for name in OBJECTIVE_COMPONENTS:
            left = internal_costs[name]
            right = julia_costs[name]
            component_differences.append(right - left)
            print(
                f"{name}: ie={left:.17g} jl={right:.17g} "
                f"signed_jl_minus_ie={right - left:.17g} "
                f"abs={abs(left - right):.17g} ppm={ppm_difference(left, right):.9f}"
            )
        print(
            f"component_signed_sum={math.fsum(component_differences):.17g} "
            f"objective_signed_difference={julia_total - internal_total:.17g} "
            f"internal_component_sum_error={math.fsum(internal_costs.values()) - internal_total:.17g} "
            f"julia_component_sum_error={math.fsum(julia_costs.values()) - julia_total:.17g}"
        )
        component_sum_tolerance = max(
            1.0, max(abs(internal_total), abs(julia_total)) * 1e-12
        )
        component_sums_ok = (
            abs(math.fsum(internal_costs.values()) - internal_total)
            <= component_sum_tolerance
            and abs(math.fsum(julia_costs.values()) - julia_total)
            <= component_sum_tolerance
        )
    else:
        component_sums_ok = False
        print(f"internal_component_certificate=MISSING path={internal_component_path}")
        for name in OBJECTIVE_COMPONENTS:
            print(f"{name}: ie=MISSING jl={julia_costs[name]:.17g}")

    print("\nInternalEMPIRE cost-report reconciliation:")
    base_reports = investment_components(internal_root)
    base_reports["generator_operation"] = generator_operation_component(
        internal_root / "results_objective_components_operational_costs.csv"
    )
    transmission_reports = transmission_report_components(
        internal_root / "results_transmission_inv_costs.csv"
    )
    hydrogen_reports = hydrogen_investment_report(
        internal_root / "results_hydrogen_costs.csv"
    )
    for name in (
        "generator_investment",
        "storage_investment",
        "transmission_investment",
        "offshore_converter_investment",
        "generator_operation",
    ):
        report_value = base_reports[name]
        if internal_costs is None:
            print(
                f"{name}: certificate=MISSING report={report_value:.17g} "
                f"julia={julia_costs[name]:.17g} "
                f"signed_julia_minus_report={julia_costs[name] - report_value:.17g}"
            )
        else:
            print(
                f"{name}: certificate={internal_costs[name]:.17g} "
                f"report={report_value:.17g} "
                f"signed_report_minus_certificate={report_value - internal_costs[name]:.17g}"
            )
    print(
        "extended_transmission_report: "
        + " ".join(f"{name}={value:.17g}" for name, value in transmission_reports.items())
    )
    print(
        "hydrogen_investment_report: "
        + " ".join(f"{name}={value:.17g}" for name, value in hydrogen_reports.items())
    )
    covered_hydrogen_investment = math.fsum(
        (
            hydrogen_reports["reported_hydrogen_investment"],
            transmission_reports["repurposed_pipeline_investment"],
            transmission_reports["co2_pipeline_investment"],
        )
    )
    if internal_costs is None:
        print(
            "hydrogen_investment_certificate=MISSING "
            f"report_covered_hydrogen_investment={covered_hydrogen_investment:.17g} "
            f"julia_hydrogen_investment={julia_costs['hydrogen_investment']:.17g} "
            f"signed_julia_minus_report_covered="
            f"{julia_costs['hydrogen_investment'] - covered_hydrogen_investment:.17g}"
        )
    else:
        print(
            f"hydrogen_investment_certificate={internal_costs['hydrogen_investment']:.17g} "
            f"report_covered_hydrogen_investment={covered_hydrogen_investment:.17g} "
            f"unreported_co2_storage_investment="
            f"{internal_costs['hydrogen_investment'] - covered_hydrogen_investment:.17g}"
        )

    print("\nInstalled capacities by stable key (operational dispatch excluded):")
    capacities_ok, capacity_lines = compare_capacities(
        internal_root,
        julia_output,
        args.capacity_atol,
        args.capacity_rtol,
        args.top,
    )
    print("\n".join(capacity_lines))

    objective_ok = objective_ppm <= args.objective_ppm
    termination_ok = summary.get("termination_status") == "OPTIMAL"
    all_ok = (
        objective_ok
        and termination_ok
        and logs_ok
        and bracket_ok
        and component_sums_ok
        and capacities_ok
    )
    print(
        "\nresult="
        + ("PASS" if all_ok else "DIFF")
        + f" objective_ok={objective_ok} termination_ok={termination_ok} "
        + f"logs_ok={logs_ok} bracket_ok={bracket_ok} "
        + f"component_sums_ok={component_sums_ok} capacities_ok={capacities_ok}"
    )
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
