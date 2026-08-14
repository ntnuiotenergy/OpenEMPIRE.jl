#!/usr/bin/env python3
"""Compare InternalEMPIRE and OpenEMPIRE.jl Industry result certificates."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from compare_internalempire_hydrogen_results import (
    aligned_barrier_interval,
    compare_capacities,
    internal_objective,
    parse_gurobi_audit,
    parse_summary,
    ppm_difference,
    read_capacity_table,
)


BASE_COMPONENTS = (
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
INDUSTRY_COMPONENTS = (
    "industry_investment",
    "industry_steel_operation",
    "industry_cement_operation",
    "industry_ammonia_operation",
    "industry_oil_operation",
)
JULIA_COMPONENT_NAMES = {
    "industry_oil_operation": "industry_refinery_shedding",
}
INDUSTRY_CAPACITIES = (
    ("steel", "steelPlantInstalledCapacity.tab", "industrySteelCapacity.csv", "SteelPlant"),
    ("cement", "cementPlantInstalledCapacity.tab", "industryCementCapacity.csv", "CementPlant"),
    ("ammonia", "ammoniaPlantInstalledCapacity.tab", "industryAmmoniaCapacity.csv", "AmmoniaPlant"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--internal-results", required=True, type=Path)
    parser.add_argument("--internal-components", required=True, type=Path)
    parser.add_argument("--julia-run", required=True, type=Path)
    parser.add_argument("--internal-log", required=True, type=Path)
    parser.add_argument(
        "--julia-log",
        type=Path,
        help="Optional Julia Gurobi log; summary objective bound is used if omitted",
    )
    parser.add_argument("--objective-ppm", type=float, default=20.0)
    parser.add_argument("--sector-ppm", type=float, default=20.0)
    parser.add_argument("--sector-atol", type=float, default=10.0)
    parser.add_argument("--volume-ppm", type=float, default=20.0)
    parser.add_argument("--volume-atol", type=float, default=1.0e-3)
    parser.add_argument("--capacity-atol", type=float, default=1e-3)
    parser.add_argument("--capacity-rtol", type=float, default=1e-5)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--wacc", type=float, default=0.05)
    parser.add_argument("--discount-rate", type=float, default=0.05)
    parser.add_argument("--period-years", type=int, default=5)
    parser.add_argument(
        "--require-sector-volumes",
        action="store_true",
        help="fail unless the InternalEMPIRE certificate contains per-period sector volumes",
    )
    parser.add_argument(
        "--require-tighter-bracket",
        action="store_true",
        help="fail unless the objective difference is within the tighter solver bracket",
    )
    return parser.parse_args()


def reconciled(
    left: float,
    right: float,
    *,
    atol: float,
    ppm: float,
) -> bool:
    """Return whether two values meet an absolute-or-relative parity tolerance."""
    return abs(left - right) <= atol or ppm_difference(left, right) <= ppm


def read_components(path: Path) -> dict[str, float]:
    components: dict[str, float] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            name = row["component"]
            if name in components:
                raise ValueError(f"duplicate component in {path}: {name}")
            components[name] = float(row["value"])
    return components


def compare_industry_capacities(
    internal_root: Path,
    julia_output: Path,
    atol: float,
    rtol: float,
) -> tuple[bool, list[str]]:
    all_ok = True
    lines: list[str] = []
    for sector, internal_file, julia_file, plant_column in INDUSTRY_CAPACITIES:
        internal = read_capacity_table(
            internal_root / internal_file,
            "\t",
            ("Node", plant_column, "Period"),
            f"{sector}PlantInstalledCapacity",
            False,
        )
        julia = read_capacity_table(
            julia_output / julia_file,
            ",",
            ("Node", "Technology", "Period"),
            "Installed_ton_per_h",
            False,
        )
        missing = set(internal) - set(julia)
        extra = set(julia) - set(internal)
        differences: list[tuple[float, tuple[str, ...], float, float]] = []
        for key in set(internal) & set(julia):
            left = internal[key]
            right = julia[key]
            absolute = abs(left - right)
            if absolute > atol + rtol * max(abs(left), abs(right)):
                differences.append((absolute, key, left, right))
        differences.sort(reverse=True)
        ok = not missing and not extra and not differences
        all_ok &= ok
        lines.append(
            f"{sector}_installed: {'OK' if ok else 'DIFF'} "
            f"keys(ie={len(internal)},jl={len(julia)},missing={len(missing)},extra={len(extra)}) "
            f"mismatches={len(differences)} "
            f"sum_ie={math.fsum(internal.values()):.17g} "
            f"sum_jl={math.fsum(julia.values()):.17g}"
        )
        if differences:
            technologies = sorted({key[1] for _, key, _, _ in differences})
            lines.append(f"  mismatch_technologies={','.join(technologies)}")
        for absolute, key, left, right in differences[:10]:
            lines.append(
                f"  {'|'.join(key)} ie={left:.12g} jl={right:.12g} "
                f"abs={absolute:.12g} ppm={ppm_difference(left, right):.6g}"
            )
    return all_ok, lines


def read_last_value_table(
    path: Path, key_columns: tuple[str, ...]
) -> dict[tuple[str, ...], float]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        assert rows.fieldnames is not None
        value_column = rows.fieldnames[-1]
        return {
            tuple(row[column] for column in key_columns): float(row[value_column])
            for row in rows
        }


def julia_industry_investments(
    run_root: Path,
    wacc: float,
    discount_rate: float,
    period_years: int,
) -> dict[str, float]:
    data = run_root / "Input" / "csv" / "Industry"
    output = run_root / "output"
    totals: dict[str, float] = {}
    for title in ("Steel", "Cement", "Ammonia"):
        capital = read_last_value_table(
            data / f"{title}InvCost.csv", ("PlantType", "Period")
        )
        fixed = read_last_value_table(
            data / f"{title}FixedOM.csv", ("PlantType", "Period")
        )
        lifetime = read_last_value_table(
            data / f"{title}PlantLifetime.csv", ("PlantType",)
        )
        with (output / f"{title.lower()}PlantBuiltCapacity.csv").open(
            newline="", encoding="utf-8-sig"
        ) as handle:
            built = list(csv.DictReader(handle))
        period_count = max(int(row["Period"]) for row in built)
        total = 0.0
        for row in built:
            plant = row[f"{title}Plant"]
            period = int(row["Period"])
            life = lifetime[(plant,)]
            # Exponent is -life, matching InternalEMPIRE b3186227 ("Fix WACC
            # calculation to recover the capital cost over lifetime"), which corrected
            # the steel, cement and ammonia plant annualizations this audit reproduces.
            annualized = (
                wacc / (1 - (1 + wacc) ** (-life))
                * capital[(plant, str(period))]
                + fixed[(plant, str(period))]
            )
            remaining_years = (period_count - period + 1) * period_years
            active_years = min(remaining_years, life)
            present_value = annualized * (
                1 - (1 + discount_rate) ** (-active_years)
            ) / (1 - 1 / (1 + discount_rate))
            strategic_discount = (1 + discount_rate) ** (
                -period_years * (period - 1)
            )
            total += (
                strategic_discount
                * present_value
                * float(row[f"{title.lower()}PlantBuiltCapacity"])
            )
        totals[title.lower()] = total
    return totals


def julia_industry_volumes(
    run_root: Path,
) -> dict[tuple[str, str], tuple[float, float, float]]:
    data = run_root / "Input" / "csv" / "Industry"
    output = run_root / "output"
    with (output / "industrySteelCapacity.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        modeled_periods = sorted(
            {row["Period"] for row in csv.DictReader(handle)}, key=int
        )
    specifications = (
        ("steel", "SteelYearlyProduction.csv", "Production_(ton/yr)"),
        ("cement", "CementYearlyProduction.csv", "Production"),
        ("ammonia", "AmmoniaYearlyProduction.csv", "Yearly_production_(tons/yr)"),
    )
    volumes: dict[tuple[str, str], tuple[float, float, float]] = {}
    for sector, demand_file, demand_column in specifications:
        expected_by_period: dict[str, float] = {}
        with (data / demand_file).open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                if "Period" in row:
                    periods = (
                        [row["Period"]]
                        if row["Period"] in modeled_periods
                        else []
                    )
                else:
                    periods = modeled_periods
                for period in periods:
                    expected_by_period[period] = expected_by_period.get(period, 0.0) + float(
                        row[demand_column]
                    )
        production_by_period: dict[str, float] = {}
        shed_by_period: dict[str, float] = {}
        scenarios_by_period: dict[str, set[tuple[str, str]]] = {}
        seen_shed: set[tuple[str, ...]] = set()
        with (output / f"industry{sector.title()}Operations.csv").open(
            newline="", encoding="utf-8-sig"
        ) as handle:
            for row in csv.DictReader(handle):
                period = row["Period"]
                scenario = (row["WeatherScenario"], row["GasScenario"])
                scenarios_by_period.setdefault(period, set()).add(scenario)
                production_by_period[period] = production_by_period.get(period, 0.0) + float(
                    row["SeasonScaledProduction_ton"]
                )
                shed_key = (
                    row["Node"], period, *scenario, row["Season"], row["Hour"]
                )
                if shed_key not in seen_shed:
                    seen_shed.add(shed_key)
                    shed_by_period[period] = shed_by_period.get(period, 0.0) + float(
                        row["SeasonScaledDemandShed_ton"]
                    )
        for period in sorted(expected_by_period, key=int):
            scenario_count = len(scenarios_by_period[period])
            production = production_by_period[period] / scenario_count
            shed = shed_by_period.get(period, 0.0) / scenario_count
            expected = expected_by_period[period]
            volumes[(sector, period)] = (production, shed, expected)
    return volumes


def main() -> int:
    args = parse_args()
    internal_total = internal_objective(
        args.internal_results.resolve() / "results_objective.csv"
    )
    summary = parse_summary(args.julia_run.resolve() / "summary.txt")
    julia_total = float(summary["objective_value"])
    internal = read_components(args.internal_components.resolve())
    internal_audit = parse_gurobi_audit(args.internal_log.resolve())
    julia_audit = (
        parse_gurobi_audit(args.julia_log.resolve()) if args.julia_log else None
    )
    component_names = BASE_COMPONENTS + INDUSTRY_COMPONENTS
    missing_internal = set(component_names) - set(internal)
    if missing_internal:
        raise ValueError(
            f"InternalEMPIRE certificate is missing components: {sorted(missing_internal)}"
        )

    julia = {
        name: float(
            summary[
                "objective_component_" + JULIA_COMPONENT_NAMES.get(name, name)
            ]
        )
        for name in component_names
    }
    ppm = ppm_difference(internal_total, julia_total)
    sum_tolerance = max(abs(internal_total), abs(julia_total)) * 5.0e-12
    internal_sum_error = math.fsum(internal[name] for name in component_names) - internal_total
    julia_sum_error = math.fsum(julia.values()) - julia_total

    print("InternalEMPIRE ↔ OpenEMPIRE.jl Industry verification")
    print(f"internal_objective={internal_total:.17g}")
    print(f"julia_objective={julia_total:.17g}")
    print(f"objective_abs_diff={abs(internal_total - julia_total):.17g}")
    print(f"objective_ppm={ppm:.9f}")
    print(f"julia_termination={summary.get('termination_status', 'missing')}")
    print(f"julia_primal_status={summary.get('primal_status', 'missing')}")
    print(f"julia_dual_status={summary.get('dual_status', 'missing')}")
    audits = [("internal", internal_audit)]
    if julia_audit is not None:
        audits.append(("julia", julia_audit))
    for name, audit in audits:
        print(
            f"{name}_certified_optimal={audit.certified_optimal} "
            f"raw={audit.raw_rows}x{audit.raw_columns}({audit.raw_nonzeros}) "
            f"presolved={audit.presolved_rows}x{audit.presolved_columns}"
            f"({audit.presolved_nonzeros}) "
            f"barrier_primal={audit.barrier_primal:.17g} "
            f"barrier_dual={audit.barrier_dual:.17g} "
            f"barrier_primal_residual={audit.barrier_primal_residual:.9g} "
            f"barrier_dual_residual={audit.barrier_dual_residual:.9g}"
        )
    objective_bound = float(summary["objective_bound"])
    if math.isfinite(objective_bound) and abs(objective_bound) < 1.0e90:
        print(
            "julia_summary_bracket="
            f"[{min(objective_bound, julia_total):.17g},"
            f"{max(objective_bound, julia_total):.17g}] "
            f"relative_gap={summary['relative_gap']}"
        )
    else:
        print(
            "julia_summary_bracket=unavailable "
            f"objective_bound={objective_bound:.17g} "
            f"relative_gap={summary['relative_gap']}"
        )
    print(f"internal_component_sum_error={internal_sum_error:.17g}")
    print(f"julia_component_sum_error={julia_sum_error:.17g}")
    print("\nObjective components:")
    for name in component_names:
        left = internal[name]
        right = julia[name]
        print(
            f"{name}: ie={left:.17g} jl={right:.17g} "
            f"signed_jl_minus_ie={right - left:.17g} "
            f"ppm={ppm_difference(left, right):.9f}"
        )

    base_capacities_ok, base_capacity_lines = compare_capacities(
        args.internal_results.resolve(),
        args.julia_run.resolve() / "output",
        args.capacity_atol,
        args.capacity_rtol,
        args.top,
    )
    industry_capacities_ok, capacity_lines = compare_industry_capacities(
        args.internal_results.resolve(),
        args.julia_run.resolve() / "output",
        args.capacity_atol,
        args.capacity_rtol,
    )
    capacities_ok = base_capacities_ok and industry_capacities_ok
    print("\nBase/Hydrogen installed capacities:")
    print("\n".join(base_capacity_lines))
    print("\nIndustry installed capacities:")
    print("\n".join(capacity_lines))

    julia_investments = julia_industry_investments(
        args.julia_run.resolve(), args.wacc, args.discount_rate, args.period_years
    )
    print("\nIndustry sector costs:")
    sector_costs_ok = True
    for sector in ("steel", "cement", "ammonia"):
        investment_name = f"industry_{sector}_investment"
        if investment_name not in internal:
            raise ValueError(
                f"InternalEMPIRE certificate is missing component: {investment_name}"
            )
        left = internal[investment_name]
        right = julia_investments[sector]
        investment_ok = reconciled(
            left,
            right,
            atol=args.sector_atol,
            ppm=args.sector_ppm,
        )
        sector_costs_ok &= investment_ok
        print(
            f"{sector}_investment: ie={left:.17g} jl={right:.17g} "
            f"signed_jl_minus_ie={right - left:.17g} "
            f"ppm={ppm_difference(left, right):.9f} ok={investment_ok}"
        )
        operation_name = f"industry_{sector}_operation"
        left = internal[operation_name]
        right = julia[operation_name]
        operation_ok = reconciled(
            left,
            right,
            atol=args.sector_atol,
            ppm=args.sector_ppm,
        )
        sector_costs_ok &= operation_ok
        print(
            f"{sector}_operation: ie={left:.17g} jl={right:.17g} "
            f"signed_jl_minus_ie={right - left:.17g} "
            f"ppm={ppm_difference(left, right):.9f} ok={operation_ok}"
        )
    print("\nIndustry annualized volumes (Julia result versus fixed demand RHS):")
    julia_volumes = julia_industry_volumes(args.julia_run.resolve())
    volumes_ok = True
    for (sector, period), (production, shed, expected) in sorted(
        julia_volumes.items(), key=lambda item: (item[0][0], int(item[0][1]))
    ):
        internal_production_name = (
            f"industry_{sector}_production_volume_period_{period}"
        )
        internal_shed_name = f"industry_{sector}_shed_volume_period_{period}"
        internal_available = (
            internal_production_name in internal and internal_shed_name in internal
        )
        if args.require_sector_volumes and not internal_available:
            volumes_ok = False
        internal_text = "unavailable"
        julia_volume_total = production + shed
        julia_balance_ok = reconciled(
            expected,
            julia_volume_total,
            atol=args.volume_atol,
            ppm=args.volume_ppm,
        )
        volumes_ok &= julia_balance_ok
        if internal_available:
            internal_production = internal[internal_production_name]
            internal_shed = internal[internal_shed_name]
            internal_volume_total = internal_production + internal_shed
            internal_balance_ok = reconciled(
                expected,
                internal_volume_total,
                atol=args.volume_atol,
                ppm=args.volume_ppm,
            )
            cross_ok = reconciled(
                internal_volume_total,
                julia_volume_total,
                atol=args.volume_atol,
                ppm=args.volume_ppm,
            )
            volumes_ok &= internal_balance_ok and cross_ok
            internal_text = (
                f"ie_production={internal_production:.17g} "
                f"ie_shed={internal_shed:.17g} "
                f"ie_balance_ppm={ppm_difference(expected, internal_volume_total):.9f} "
                f"ie_balance_ok={internal_balance_ok} "
                f"cross_ppm={ppm_difference(internal_volume_total, julia_volume_total):.9f} "
                f"cross_ok={cross_ok}"
            )
        print(
            f"{sector}_volume_period_{period}: expected={expected:.17g} "
            f"jl_production={production:.17g} jl_shed={shed:.17g} "
            f"balance_ppm={ppm_difference(expected, julia_volume_total):.9f} "
            f"jl_balance_ok={julia_balance_ok} "
            f"{internal_text}"
        )

    objective_ok = ppm <= args.objective_ppm
    julia_ok = (
        summary.get("termination_status") == "OPTIMAL"
        and summary.get("primal_status") == "FEASIBLE_POINT"
        and summary.get("dual_status") == "FEASIBLE_POINT"
    )
    julia_certificate_ok = (
        julia_audit.certified_optimal if julia_audit is not None else julia_ok
    )
    logs_ok = internal_audit.certified_optimal and julia_certificate_ok
    bracket_ok = not args.require_tighter_bracket
    if julia_audit is not None:
        for name, audit, returned in (
            ("InternalEMPIRE", internal_audit, internal_total),
            ("OpenEMPIRE.jl", julia_audit, julia_total),
        ):
            aligned_lower, aligned_upper = aligned_barrier_interval(audit, returned)
            returned_matches_gurobi = (
                abs(returned - audit.final_objective)
                <= audit.final_objective_rounding
            )
            logs_ok &= returned_matches_gurobi
            print(
                f"{name}_aligned_bracket=[{aligned_lower:.17g},{aligned_upper:.17g}] "
                f"returned_matches_gurobi_objective={returned_matches_gurobi}"
            )
        tighter_bracket = min(
            internal_audit.barrier_bracket_width,
            julia_audit.barrier_bracket_width,
        )
        bracket_ok = abs(internal_total - julia_total) <= tighter_bracket
        print(
            f"objective_difference_within_tighter_bracket={bracket_ok} "
            f"difference={abs(internal_total - julia_total):.17g} "
            f"tighter_conservative_bracket_width={tighter_bracket:.17g}"
        )
    component_sums_ok = (
        abs(internal_sum_error) <= sum_tolerance
        and abs(julia_sum_error) <= sum_tolerance
    )
    passed = (
        objective_ok
        and julia_ok
        and logs_ok
        and component_sums_ok
        and sector_costs_ok
        and capacities_ok
        and volumes_ok
        and bracket_ok
    )
    print(
        "\nobjective_result="
        + ("PASS" if objective_ok and julia_ok and logs_ok and component_sums_ok else "DIFF")
    )
    print(
        "\nresult="
        + ("PASS" if passed else "DIFF")
        + f" objective_ok={objective_ok} julia_ok={julia_ok} logs_ok={logs_ok} "
        + f"component_sums_ok={component_sums_ok} capacities_ok={capacities_ok} "
        + f"sector_costs_ok={sector_costs_ok} volumes_ok={volumes_ok}"
        + f" bracket_ok={bracket_ok}"
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
