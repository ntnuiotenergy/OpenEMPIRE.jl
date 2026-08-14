#!/usr/bin/env python3
"""Evaluate a complete OpenEMPIRE.jl solution in InternalEMPIRE's Pyomo model.

The InternalEMPIRE checkout is read-only: its runner and ``empire.py`` are
patched only in memory, and the solver call is replaced by this diagnostic.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import sys
import types
from collections import defaultdict
from pathlib import Path

from pyomo.environ import Constraint, Objective, Var, value

from run_internalempire_hydrogen import replace_once


STRATEGIC_COMPONENTS = {
    "genInvCap": "genInvCap",
    "genInstalledCap": "genInstalledCap",
    "transmissionInvCap": "transmissionInvCap",
    "transmissionInstalledCap": "transmissionInstalledCap",
    "storPWInvCap": "storPWInvCap",
    "storPWInstalledCap": "storPWInstalledCap",
    "storENInvCap": "storENInvCap",
    "storENInstalledCap": "storENInstalledCap",
    "offshoreConvInvCap": "offshoreConvInvCap",
    "offshoreConvInstalledCap": "offshoreConvInstalledCap",
    "hydrogenImportCapBuilt": "H2ImportCapBuilt",
    "hydrogenImportCapInstalled": "H2ImportTotalCap",
    "electrolyzerCapBuilt": "elyzerCapBuilt",
    "electrolyzerCapInstalled": "elyzerTotalCap",
    "reformerCapBuilt": "ReformerCapBuilt",
    "reformerCapInstalled": "ReformerTotalCap",
    "hydrogenPipelineCapBuilt": "hydrogenPipelineBuilt",
    "hydrogenRepurposedGasPipelineCapBuilt": "repurposedPipelineBuilt",
    "hydrogenPipelineCapInstalled": "totalHydrogenPipelineCapacity",
    "hydrogenStorageCapBuilt": "hydrogenStorageBuilt",
    "hydrogenStorageCapInstalled": "hydrogenTotalStorage",
    "co2PipelineCapBuilt": "CO2PipelineBuilt",
    "co2PipelineCapInstalled": "totalCO2PipelineCapacity",
    "co2SequestrationCapBuilt": "CO2SiteCapacityDeveloped",
}

OPERATIONAL_COMPONENTS = {
    "genOperational": ("genOperational", False),
    "transmissionOperational": ("transmissionOperational", False),
    "storCharge": ("storCharge", False),
    "storDischarge": ("storDischarge", False),
    "storOperational": ("storOperational", False),
    "loadShed": ("loadShed", False),
    "ngTerminalImport": ("ng_terminalImport", False),
    "ngTransmission": ("ng_transmission", False),
    "ngForPower": ("ng_forPower", False),
    "ngStorageOperational": ("ng_storageOperational", False),
    "ngStorageCharge": ("ng_chargeStorage", False),
    "ngStorageDischarge": ("ng_dischargeStorage", False),
    "transportNaturalGasDemandMet": ("transport_naturalGasDemandMet", False),
    "transportNaturalGasDemandShed": ("transport_naturalGasDemandShed", False),
    "electrolyzerHydrogen": ("hydrogenProducedElectro_ton", False),
    "electrolyzerElectricity": ("powerForHydrogen", False),
    "reformerHydrogenTon": ("hydrogenProducedReformer_ton", False),
    "reformerHydrogenMWh": ("hydrogenProducedReformer_MWh", False),
    "reformerNaturalGas": ("ng_forHydrogen", False),
    "hydrogenImportTon": ("H2Imported_ton", False),
    "hydrogenImportMWh": ("H2Imported_MWh", False),
    "hydrogenPipelineFlow": ("hydrogenSentPipeline", False),
    "hydrogenStorageLevel": ("hydrogenStorageOperational", False),
    "hydrogenStorageCharge": ("hydrogenChargeStorage", False),
    "hydrogenStorageDischarge": ("hydrogenDischargeStorage", False),
    "hydrogenStorageCompressionPower": ("hydrogen_storage_compression_power", False),
    "hydrogenForPower": ("hydrogenForPower", True),
    "transportElectricityDemandMet": ("transport_electricityDemandMet", False),
    "transportElectricityDemandShed": ("transport_electricityDemandShed", False),
    "transportHydrogenDemandMet": ("transport_hydrogenDemandMet", False),
    "transportHydrogenDemandShed": ("transport_hydrogenDemandShed", False),
    "co2PipelineFlow": ("CO2sentPipeline", False),
    "co2Sequestered": ("CO2sequestered", False),
}

JULIA_ONLY_COMPONENTS = {
    "co2SequestrationCapInstalled",
    "hydrogenRepurposedGasPipelineCapInstalled",
    "nodeEmission",
}

UNDIRECTED_STRATEGIC_COMPONENTS = {
    "transmissionInvCap",
    "transmissionInstalledCap",
    "hydrogenPipelineCapBuilt",
    "hydrogenPipelineCapInstalled",
    "co2PipelineCapBuilt",
    "co2PipelineCapInstalled",
}

TIME_PATTERN = re.compile(r"^sp(\d+)-rp(\d+)-sc(\d+)-t(\d+)$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--internal-repo", type=Path, required=True)
    parser.add_argument("--julia-solution", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--runner", default="run_EMPIRE_int_2030_gas_fast.py")
    return parser.parse_args()


def parse_julia_name(name: str) -> tuple[str, list[str]]:
    if "[" not in name or not name.endswith("]"):
        return name, []
    component, raw_indices = name[:-1].split("[", 1)
    return component, [index.strip(" '\"") for index in raw_indices.split(",")]


def pyomo_variable(instance, component: str, indices: list[str]):
    target = STRATEGIC_COMPONENTS.get(component)
    if target is not None:
        parsed = list(indices[:-1]) + [int(indices[-1].removeprefix("sp"))]
        variables = getattr(instance, target)
        try:
            return variables[tuple(parsed)]
        except KeyError:
            if component not in UNDIRECTED_STRATEGIC_COMPONENTS:
                raise
            parsed[0], parsed[1] = parsed[1], parsed[0]
            return variables[tuple(parsed)]

    operational = OPERATIONAL_COMPONENTS.get(component)
    if operational is None:
        return None
    target, reverse_first_pair = operational
    match = TIME_PATTERN.match(indices[-1])
    if match is None:
        raise ValueError(f"unsupported Julia operational time: {indices[-1]}")
    period, representative, scenario, hour = map(int, match.groups())
    global_hour = (representative - 1) * int(value(instance.lengthRegSeason)) + hour
    prefix = list(indices[:-1])
    if reverse_first_pair:
        prefix[0], prefix[1] = prefix[1], prefix[0]
    return getattr(instance, target)[
        tuple(prefix + [global_hour, period, f"scenario{scenario}", 1])
    ]


def constraint_violation(constraint) -> float:
    body = float(value(constraint.body))
    violation = 0.0
    if constraint.has_lb():
        violation = max(violation, float(value(constraint.lower)) - body)
    if constraint.has_ub():
        violation = max(violation, body - float(value(constraint.upper)))
    return max(0.0, violation)


def check_solution(instance, solution_path: Path) -> None:
    pyomo_variables = {}
    for component in instance.component_objects(Var, active=True):
        for variable in component.values():
            variable.set_value(0.0, skip_validation=True)
            pyomo_variables[variable.name] = variable

    mapped = 0
    mapped_by_component = defaultdict(int)
    unmapped_by_component = defaultdict(int)
    missing_indices = []
    with solution_path.open(newline="", encoding="utf-8") as solution_file:
        for row in csv.DictReader(solution_file):
            component, indices = parse_julia_name(row["variable"])
            if component in JULIA_ONLY_COMPONENTS:
                unmapped_by_component[component] += 1
                continue
            try:
                variable = pyomo_variable(instance, component, indices)
            except KeyError:
                if len(missing_indices) < 20:
                    missing_indices.append(row["variable"])
                unmapped_by_component[component] += 1
                continue
            if variable is None:
                unmapped_by_component[component] += 1
                continue
            variable.set_value(float(row["value"]), skip_validation=True)
            mapped += 1
            mapped_by_component[component] += 1

    print(
        f"mapped_julia_variables={mapped} pyomo_variables={len(pyomo_variables)} "
        f"unmapped_julia_variables={sum(unmapped_by_component.values())}"
    )
    print(f"mapped_components={dict(sorted(mapped_by_component.items()))}")
    print(f"unmapped_components={dict(sorted(unmapped_by_component.items()))}")
    if missing_indices:
        print(f"first_missing_indices={missing_indices}")

    bound_count = 0
    max_bound_violation = 0.0
    max_bound_name = None
    for variable in pyomo_variables.values():
        variable_value = float(value(variable))
        violation = 0.0
        if variable.has_lb():
            violation = max(violation, float(value(variable.lb)) - variable_value)
        if variable.has_ub():
            violation = max(violation, variable_value - float(value(variable.ub)))
        violation = max(0.0, violation)
        bound_count += violation > 1e-6
        if violation > max_bound_violation:
            max_bound_violation = violation
            max_bound_name = variable.name
    print(
        f"variable_bounds count_gt_1e-6={bound_count} max={max_bound_violation:.12g} "
        f"at={max_bound_name}"
    )

    objective_components = list(instance.component_data_objects(Objective, active=True))
    for objective in objective_components:
        print(f"objective {objective.name}={float(value(objective.expr)):.16g}")

    top_violations = []
    total_rows = 0
    for component in instance.component_objects(Constraint, active=True):
        count_gt_1e6 = 0
        count_gt_1e3 = 0
        max_violation = 0.0
        max_name = None
        for constraint in component.values():
            violation = constraint_violation(constraint)
            if not math.isfinite(violation):
                raise RuntimeError(f"non-finite violation at {constraint.name}: {violation}")
            total_rows += 1
            count_gt_1e6 += violation > 1e-6
            count_gt_1e3 += violation > 1e-3
            if violation > max_violation:
                max_violation = violation
                max_name = constraint.name
            if violation > 1e-6:
                top_violations.append((violation, constraint.name))
        print(
            f"constraint_family {component.name}: rows={len(component)} "
            f"count_gt_1e-6={count_gt_1e6} count_gt_1e-3={count_gt_1e3} "
            f"max={max_violation:.12g} at={max_name}"
        )

    top_violations.sort(reverse=True)
    print(f"constraint_rows={total_rows}")
    for violation, name in top_violations[:30]:
        print(f"top_violation={violation:.12g} constraint={name}")


def patched_runner_source(internal_repo: Path, runner: Path, output_dir: Path) -> str:
    source = runner.read_text(encoding="utf-8")
    source = replace_once(source, "USE_TEMP_DIR = True", "USE_TEMP_DIR = False")
    source = replace_once(source, "hydrogen = False", "hydrogen = True")
    source = replace_once(
        source,
        "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_gas_fast\"",
        "name += f\"_{2020 + NoOfPeriods * LeapYearsInvestment}_{NoOfScenarios}sce_hydrogen_check\"",
    )
    source = replace_once(
        source,
        "workbook_path = 'Data handler/' + version",
        f"workbook_path = {str(internal_repo / 'Data handler' / 'full_model_int')!r}",
    )
    source = replace_once(
        source,
        "tab_file_path = 'Data handler/' + version + '/Tab_Files_' + name",
        f"tab_file_path = {str(output_dir / 'tabs')!r}",
    )
    source = replace_once(
        source,
        "scenario_data_path = 'Data handler/' + version + '/ScenarioData'",
        f"scenario_data_path = {str(internal_repo / 'Data handler' / 'full_model_int' / 'ScenarioData')!r}",
    )
    source = replace_once(
        source,
        "if HEATMODULE:\n    include_results.append(heat_results)",
        "include_results = []\n\nif HEATMODULE:\n    include_results.append(heat_results)",
    )
    source = replace_once(
        source,
        "base_results_path = '../InternalEMPIRE/Results'",
        f"base_results_path = {str(output_dir / 'Results')!r}",
    )
    source = replace_once(
        source,
        "temp_dir = '../InternalEMPIRE/TempDir'",
        f"temp_dir = {str(output_dir / 'TempDir')!r}",
    )
    return source


def main() -> None:
    args = parse_args()
    internal_repo = args.internal_repo.resolve()
    solution_path = args.julia_solution.resolve()
    output_dir = args.output_dir.resolve()
    work_dir = output_dir / "work"
    for path in (work_dir, output_dir / "tabs", output_dir / "Results", output_dir / "TempDir"):
        path.mkdir(parents=True, exist_ok=True)

    runner = internal_repo / args.runner
    runner_source = patched_runner_source(internal_repo, runner, output_dir)
    empire_path = internal_repo / "empire.py"
    empire_source = empire_path.read_text(encoding="utf-8")
    solver_call = (
        "    results = opt.solve(instance, tee=True,\n"
        "                        logfile=result_file_path + '/logfile_' + name + '.log')  # symbolic_solver_labels=True)"
    )
    empire_source = replace_once(
        empire_source,
        solver_call,
        "    _check_julia_solution(instance)\n    return",
    )

    sys.dont_write_bytecode = True
    sys.path.insert(0, str(internal_repo))
    os.chdir(work_dir)
    empire_module = types.ModuleType("empire")
    empire_module.__file__ = str(empire_path)
    empire_module._check_julia_solution = lambda instance: check_solution(instance, solution_path)
    sys.modules["empire"] = empire_module
    exec(compile(empire_source, str(empire_path), "exec"), empire_module.__dict__)

    namespace = {"__name__": "__main__", "__file__": str(runner)}
    exec(compile(runner_source, str(runner), "exec"), namespace)


if __name__ == "__main__":
    main()
