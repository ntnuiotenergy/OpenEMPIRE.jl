#!/usr/bin/env python3
"""Run an InternalEMPIRE Hydrogen/Industry parity case without editing its checkout."""

from __future__ import annotations

import argparse
import csv
import os
import sys
import types
from pathlib import Path


def replace_once(source: str, old: str, new: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"expected one InternalEMPIRE runner token, found {count}: {old!r}")
    return source.replace(old, new, 1)


def replace_one_of(source: str, replacements: tuple[tuple[str, str], ...]) -> str:
    matches = [
        (old, new, source.count(old)) for old, new in replacements if old in source
    ]
    count = sum(match_count for _, _, match_count in matches)
    if count != 1:
        tokens = [old for old, _ in replacements]
        raise RuntimeError(
            f"expected exactly one InternalEMPIRE token across {tokens!r}, found {count}"
        )
    old, new, _ = matches[0]
    return source.replace(old, new, 1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--internal-repo", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--runner",
        default="run_EMPIRE_int_2030_gas_fast.py",
        help="runner path relative to --internal-repo",
    )
    parser.add_argument(
        "--no-raw-solution",
        action="store_true",
        help="skip the potentially multi-gigabyte complete Pyomo variable export",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="write patched runner/reference sources for inspection without executing",
    )
    parser.add_argument(
        "--industry",
        action="store_true",
        help="enable InternalEMPIRE's Industry module in addition to Hydrogen",
    )
    parser.add_argument(
        "--solver-seed",
        type=int,
        help="set Gurobi's deterministic Seed parameter",
    )
    return parser.parse_args()


def write_objective_component_certificate(instance: object, path: Path) -> None:
    """Write the components used by OpenEMPIRE's parity summary."""
    from pyomo.environ import value

    periods = tuple(instance.Period)
    scenarios = tuple(instance.Scenario)
    gas_scenarios = tuple(instance.GasScenario)

    def discounted_scenario_expression(expression: object) -> float:
        return sum(
            value(
                instance.discount_multiplier[period]
                * instance.sceProbab[scenario]
                * instance.GasSceProbab[gas_scenario]
                * expression[period, scenario, gas_scenario]
            )
            for period in periods
            for scenario in scenarios
            for gas_scenario in gas_scenarios
        )

    generator_investment = sum(
        value(
            instance.discount_multiplier[period]
            * instance.genInvCost[generator, period]
            * instance.genInvCap[node, generator, period]
        )
        for node, generator in instance.GeneratorsOfNode
        for period in periods
    )
    storage_investment = sum(
        value(
            instance.discount_multiplier[period]
            * (
                instance.storPWInvCost[storage, period]
                * instance.storPWInvCap[node, storage, period]
                + instance.storENInvCost[storage, period]
                * instance.storENInvCap[node, storage, period]
            )
        )
        for node, storage in instance.StoragesOfNode
        for period in periods
    )
    transmission_investment = sum(
        value(
            instance.discount_multiplier[period]
            * instance.transmissionInvCost[node, neighbor, period]
            * instance.transmissionInvCap[node, neighbor, period]
        )
        for node, neighbor in instance.BidirectionalArc
        for period in periods
    )
    offshore_converter_investment = sum(
        value(
            instance.discount_multiplier[period]
            * instance.offshoreConvInvCost[period]
            * instance.offshoreConvInvCap[node, period]
        )
        for node in instance.OffshoreEnergyHubs
        for period in periods
    )
    load_shedding = discounted_scenario_expression(instance.shedcomponent)
    natural_gas_terminal_import = discounted_scenario_expression(
        instance.ng_import_cost
    )
    hydrogen_terminal_import = discounted_scenario_expression(
        instance.H2TerminalImportCost
    )
    hydrogen_reformer_operation = discounted_scenario_expression(
        instance.reformerOperationalCost
    )
    industry_enabled = hasattr(instance, "steel_opex")
    industry_steel_operation = (
        discounted_scenario_expression(instance.steel_opex)
        if industry_enabled
        else 0.0
    )
    industry_cement_operation = (
        discounted_scenario_expression(instance.cement_opex)
        if industry_enabled
        else 0.0
    )
    industry_ammonia_operation = (
        discounted_scenario_expression(instance.ammonia_opex)
        if industry_enabled
        else 0.0
    )
    industry_oil_operation = (
        discounted_scenario_expression(instance.oil_opex)
        if industry_enabled
        else 0.0
    )
    industry_steel_investment = (
        sum(
            value(
                instance.discount_multiplier[period]
                * instance.steel_plantInvCost[plant, period]
                * instance.steelPlantBuiltCapacity[node, plant, period]
            )
            for node in instance.SteelProducers
            for plant in instance.SteelPlants
            for period in periods
        )
        if industry_enabled
        else 0.0
    )
    industry_cement_investment = (
        sum(
            value(
                instance.discount_multiplier[period]
                * instance.cement_plantInvCost[plant, period]
                * instance.cementPlantBuiltCapacity[node, plant, period]
            )
            for node in instance.CementProducers
            for plant in instance.CementPlants
            for period in periods
        )
        if industry_enabled
        else 0.0
    )
    industry_ammonia_investment = (
        sum(
            value(
                instance.discount_multiplier[period]
                * instance.ammonia_plantInvCost[plant, period]
                * instance.ammoniaPlantBuiltCapacity[node, plant, period]
            )
            for node in instance.AmmoniaProducers
            for plant in instance.AmmoniaPlants
            for period in periods
        )
        if industry_enabled
        else 0.0
    )
    industry_investment = sum(
        (
            industry_steel_investment,
            industry_cement_investment,
            industry_ammonia_investment,
        )
    )

    def transport_shedding(variable_names: tuple[str, ...]) -> float:
        variables = tuple(getattr(instance, name) for name in variable_names)
        return sum(
            value(
                instance.discount_multiplier[period]
                * instance.sceProbab[scenario]
                * instance.GasSceProbab[gas_scenario]
                * instance.operationalDiscountrate
                * instance.seasScale[season]
                * instance.transport_curtail_cost
                * sum(
                    variable[node, hour, period, scenario, gas_scenario]
                    for variable in variables
                )
            )
            for period in periods
            for scenario in scenarios
            for gas_scenario in gas_scenarios
            for node in instance.OnshoreNode
            for season, hour in instance.HoursOfSeason
        )

    natural_gas_transport_shedding = transport_shedding(
        ("transport_naturalGasDemandShed",)
    )
    hydrogen_transport_shedding = transport_shedding(
        ("transport_electricityDemandShed", "transport_hydrogenDemandShed")
    )
    total_operational = sum(
        value(instance.discount_multiplier[period] * instance.operationalcost[period])
        for period in periods
    )
    generator_operation = total_operational - sum(
        (
            load_shedding,
            natural_gas_terminal_import,
            natural_gas_transport_shedding,
            hydrogen_terminal_import,
            hydrogen_reformer_operation,
            hydrogen_transport_shedding,
            industry_steel_operation,
            industry_cement_operation,
            industry_ammonia_operation,
            industry_oil_operation,
        )
    )
    objective = value(instance.Obj)
    hydrogen_investment = objective - total_operational - sum(
        (
            generator_investment,
            storage_investment,
            transmission_investment,
            offshore_converter_investment,
            industry_investment,
        )
    )
    components = (
        ("generator_investment", generator_investment),
        ("storage_investment", storage_investment),
        ("transmission_investment", transmission_investment),
        ("offshore_converter_investment", offshore_converter_investment),
        ("load_shedding", load_shedding),
        ("generator_operation", generator_operation),
        ("natural_gas_terminal_import", natural_gas_terminal_import),
        ("natural_gas_transport_shedding", natural_gas_transport_shedding),
        ("hydrogen_investment", hydrogen_investment),
        ("hydrogen_terminal_import", hydrogen_terminal_import),
        ("hydrogen_reformer_operation", hydrogen_reformer_operation),
        ("hydrogen_transport_shedding", hydrogen_transport_shedding),
        ("industry_investment", industry_investment),
        ("industry_steel_investment", industry_steel_investment),
        ("industry_cement_investment", industry_cement_investment),
        ("industry_ammonia_investment", industry_ammonia_investment),
        ("industry_steel_operation", industry_steel_operation),
        ("industry_cement_operation", industry_cement_operation),
        ("industry_ammonia_operation", industry_ammonia_operation),
        ("industry_oil_operation", industry_oil_operation),
    )
    sector_volumes: list[tuple[str, float]] = []
    if industry_enabled:
        sector_specs = (
            (
                "steel",
                instance.SteelProducers,
                instance.SteelPlants_FinalSteel,
                instance.steelProduced,
                instance.steelLoadShed,
            ),
            (
                "cement",
                instance.CementProducers,
                instance.CementPlants,
                instance.cementProduced,
                instance.cementLoadShed,
            ),
            (
                "ammonia",
                instance.AmmoniaProducers,
                instance.AmmoniaPlants,
                instance.ammoniaProduced,
                instance.ammoniaLoadShed,
            ),
        )
        for sector, nodes, plants, production_variable, shed_variable in sector_specs:
            for period in periods:
                production = sum(
                    value(
                        instance.sceProbab[scenario]
                        * instance.GasSceProbab[gas_scenario]
                        * instance.seasScale[season]
                        * production_variable[
                            node, plant, hour, period, scenario, gas_scenario
                        ]
                    )
                    for scenario in scenarios
                    for gas_scenario in gas_scenarios
                    for node in nodes
                    for plant in plants
                    for season, hour in instance.HoursOfSeason
                )
                shedding = sum(
                    value(
                        instance.sceProbab[scenario]
                        * instance.GasSceProbab[gas_scenario]
                        * instance.seasScale[season]
                        * shed_variable[node, hour, period, scenario, gas_scenario]
                    )
                    for scenario in scenarios
                    for gas_scenario in gas_scenarios
                    for node in nodes
                    for season, hour in instance.HoursOfSeason
                )
                sector_volumes.extend(
                    (
                        (f"industry_{sector}_production_volume_period_{period}", production),
                        (f"industry_{sector}_shed_volume_period_{period}", shedding),
                    )
                )
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("component", "value"))
        writer.writerows(components)
        writer.writerows(sector_volumes)
    print(f"objective_component_certificate={path}")


def main() -> None:
    args = parse_args()
    internal_repo = args.internal_repo.resolve()
    output_dir = args.output_dir.resolve()
    work_dir = output_dir / "work"
    results_root = output_dir / "Results"
    tabs = output_dir / "tabs"
    temp_dir = output_dir / "TempDir"
    for path in (work_dir, results_root, tabs, temp_dir):
        path.mkdir(parents=True, exist_ok=True)

    runner = internal_repo / args.runner
    source = runner.read_text(encoding="utf-8")
    source = replace_one_of(
        source,
        (
            ("using_solstorm = True", "using_solstorm = False"),
            ("using_solstorm = False", "using_solstorm = False"),
        ),
    )
    # Pyomo's shell solver writes a very large intermediate LP. Keep it on the
    # explicitly isolated /storage output tree rather than the compute node's
    # small local disk.
    source = replace_one_of(
        source,
        (
            ("USE_TEMP_DIR = True", "USE_TEMP_DIR = True"),
            ("USE_TEMP_DIR = False", "USE_TEMP_DIR = True"),
        ),
    )
    source = replace_once(source, "hydrogen = False", "hydrogen = True")
    if args.industry:
        source = replace_once(source, "industry = False", "industry = True")
    source = replace_one_of(
        source,
        (
            (
                "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_gas_fast\"",
                "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_hydrogen_fast\"",
            ),
            (
                "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_gas_full\"",
                "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_hydrogen_full\"",
            ),
        ),
    )
    if args.industry:
        source = replace_one_of(
            source,
            (
                ("_hydrogen_fast\"", "_industry_fast\""),
                ("_hydrogen_full\"", "_industry_full\""),
            ),
        )
    source = replace_once(
        source,
        "workbook_path = 'Data handler/' + version",
        f"workbook_path = {str(internal_repo / 'Data handler' / 'full_model_int')!r}",
    )
    source = replace_once(
        source,
        "tab_file_path = 'Data handler/' + version + '/Tab_Files_' + name",
        f"tab_file_path = {str(tabs)!r}",
    )
    source = replace_once(
        source,
        "scenario_data_path = 'Data handler/' + version + '/ScenarioData'",
        f"scenario_data_path = {str(internal_repo / 'Data handler' / 'full_model_int' / 'ScenarioData')!r}",
    )
    source = replace_once(
        source,
        "if HEATMODULE:\n    include_results.append(heat_results)",
        "include_results = [\"results_transmission_inv_costs\", "
        "\"results_hydrogen_costs\"]\n\n"
        "if HEATMODULE:\n    include_results.append(heat_results)",
    )
    source = replace_once(
        source,
        "base_results_path = '../InternalEMPIRE/Results'",
        f"base_results_path = {str(results_root)!r}",
    )
    source = replace_once(
        source,
        "temp_dir = '../InternalEMPIRE/TempDir'",
        f"temp_dir = {str(temp_dir)!r}",
    )

    if args.no_raw_solution:
        os.environ.pop("EMPIRE_EXPORT_RAW_SOLUTION", None)
    else:
        os.environ["EMPIRE_EXPORT_RAW_SOLUTION"] = str(output_dir / "raw_solution.csv")
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(internal_repo))
    os.chdir(work_dir)

    empire_path = internal_repo / "empire.py"
    empire_source = empire_path.read_text(encoding="utf-8")
    empire_source = replace_one_of(
        empire_source,
        (
            (
                '        opt.options["Crossover"] = 1',
                '        opt.options["Crossover"] = 0',
            ),
            (
                '        opt.options["Crossover"] = 0',
                '        opt.options["Crossover"] = 0',
            ),
        ),
    )
    empire_source = replace_one_of(
        empire_source,
        (
            (
                "        # opt.options['NumericFocus']=1",
                "        opt.options['NumericFocus']=1",
            ),
            (
                "        opt.options['NumericFocus']=1",
                "        opt.options['NumericFocus']=1",
            ),
        ),
    )
    if args.solver_seed is not None:
        seed_anchor = "        opt.options['NumericFocus']=1"
        empire_source = replace_once(
            empire_source,
            seed_anchor,
            seed_anchor + f"\n        opt.options['Seed']={args.solver_seed}",
        )
    empire_source = replace_one_of(
        empire_source,
        (
            (
                "        # opt.options['BarHomogeneous']=1",
                "        opt.options['BarHomogeneous']=1",
            ),
            (
                "        opt.options['BarHomogeneous']=1",
                "        opt.options['BarHomogeneous']=1",
            ),
        ),
    )
    empire_source = replace_one_of(
        empire_source,
        (
            ("        # opt.options['Presolve']=2", "        opt.options['Presolve']=1"),
            ("        opt.options['Presolve']=2", "        opt.options['Presolve']=1"),
            ("        opt.options['Presolve']=1", "        opt.options['Presolve']=1"),
        ),
    )
    empire_source = replace_one_of(
        empire_source,
        (
            (
                "        # opt.options['FeasibilityTol']=10**(-9)",
                "        opt.options['FeasibilityTol']=1e-9",
            ),
            (
                "        opt.options['FeasibilityTol']=10**(-9)",
                "        opt.options['FeasibilityTol']=1e-9",
            ),
            (
                "        opt.options['FeasibilityTol']=1e-9",
                "        opt.options['FeasibilityTol']=1e-9",
            ),
        ),
    )
    empire_source = replace_one_of(
        empire_source,
        (
            (
                '        opt.options["BarConvTol"] = 1e-5',
                '        opt.options["BarConvTol"] = 1e-8',
            ),
            (
                '        opt.options["BarConvTol"] = 1e-8',
                '        opt.options["BarConvTol"] = 1e-8',
            ),
        ),
    )
    empire_source = replace_once(
        empire_source,
        "        opt.options['ResultFile'] = f\"{name}.ilp\"",
        "        # ResultFile=.ilp requests an IIS, not an optimal-solution artifact.",
    )
    empire_source = replace_once(
        empire_source,
        "    del results, instance, model",
        "    _openempire_write_objective_component_certificate(\n"
        "        instance, _openempire_objective_component_path\n"
        "    )\n"
        "    del results, instance, model",
    )
    if args.prepare_only:
        prepared_runner = output_dir / "prepared_runner.py"
        prepared_empire = output_dir / "prepared_empire.py"
        prepared_runner.write_text(source, encoding="utf-8")
        prepared_empire.write_text(empire_source, encoding="utf-8")
        print(f"prepared_runner={prepared_runner}")
        print(f"prepared_empire={prepared_empire}")
        return

    empire_module = types.ModuleType("empire")
    empire_module.__file__ = str(empire_path)
    sys.modules["empire"] = empire_module
    exec(compile(empire_source, str(empire_path), "exec"), empire_module.__dict__)
    empire_module._openempire_write_objective_component_certificate = (
        write_objective_component_certificate
    )
    empire_module._openempire_objective_component_path = (
        output_dir / "objective_components.csv"
    )

    namespace = {"__name__": "__main__", "__file__": str(runner)}
    exec(compile(source, str(runner), "exec"), namespace)


if __name__ == "__main__":
    main()
