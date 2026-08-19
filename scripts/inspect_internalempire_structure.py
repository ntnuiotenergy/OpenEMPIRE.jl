#!/usr/bin/env python3
"""Build an InternalEMPIRE runner and report its Pyomo matrix by component.

The runner is executed normally through model construction, but its solver factory is
replaced with a read-only inspector.  No optimization or result reporting is performed.
"""

from __future__ import annotations

import argparse
import csv
import runpy
import sys
from pathlib import Path

from pyomo.environ import Constraint, Var, value
from pyomo.repn.standard_repn import generate_standard_repn


class _InspectingSolver:
    def __init__(self, parameter_output: Path | None) -> None:
        self.options: dict[str, object] = {}
        self.parameter_output = parameter_output

    def solve(self, instance, **_kwargs):
        if self.parameter_output is not None:
            self._write_objective_parameters(instance)
        variable_total = 0
        for component in instance.component_objects(Var, active=True):
            count = len(component)
            variable_total += count
            print(f"VAR\t{component.name}\t{count}")

        constraint_total = 0
        nonzero_total = 0
        for component in instance.component_objects(Constraint, active=True):
            count = len(component)
            nonzeros = 0
            for constraint in component.values():
                representation = generate_standard_repn(
                    constraint.body, compute_values=False
                )
                nonzeros += len(representation.linear_vars)
            constraint_total += count
            nonzero_total += nonzeros
            print(f"CON\t{component.name}\t{count}\t{nonzeros}")

        print(f"TOTAL\tvariables\t{variable_total}")
        print(f"TOTAL\tconstraints\t{constraint_total}")
        print(f"TOTAL\tnonzeros\t{nonzero_total}")
        raise SystemExit(0)

    def _write_objective_parameters(self, instance) -> None:
        rows: list[tuple[str, str, str, float]] = []
        for generator in instance.Generator:
            for period in instance.Period:
                rows.append(("genMargCost", str(generator), str(period), float(value(instance.genMargCost[generator, period]))))
                rows.append(("genInvCost", str(generator), str(period), float(value(instance.genInvCost[generator, period]))))
        for storage in instance.Storage:
            for period in instance.Period:
                rows.append(("storENInvCost", str(storage), str(period), float(value(instance.storENInvCost[storage, period]))))
                rows.append(("storPWInvCost", str(storage), str(period), float(value(instance.storPWInvCost[storage, period]))))
        for node_from, node_to in instance.BidirectionalArc:
            for period in instance.Period:
                rows.append(("transmissionInvCost", f"{node_from}|{node_to}", str(period), float(value(instance.transmissionInvCost[node_from, node_to, period]))))
        for period in instance.Period:
            rows.append(("discount_multiplier", "", str(period), float(value(instance.discount_multiplier[period]))))
        rows.append(("operationalDiscountrate", "", "", float(value(instance.operationalDiscountrate))))
        for scenario in instance.Scenario:
            rows.append(("sceProbab", str(scenario), "", float(value(instance.sceProbab[scenario]))))
        for gas_scenario in instance.GasScenario:
            rows.append(("GasSceProbab", str(gas_scenario), "", float(value(instance.GasSceProbab[gas_scenario]))))
        for season in instance.Season:
            rows.append(("seasScale", str(season), "", float(value(instance.seasScale[season]))))
        for node, terminal in instance.NaturalGasTerminalsOfNode:
            for period in instance.Period:
                for gas_scenario in instance.GasScenario:
                    rows.append(
                        (
                            "ng_terminalCost",
                            f"{node}|{terminal}|{gas_scenario}",
                            str(period),
                            float(value(instance.ng_terminalCost[node, terminal, period, gas_scenario])),
                        )
                    )
        rows.append(("ng_pipelinePowerDemandPerTon", "", "", float(value(instance.ng_pipelinePowerDemandPerTon))))

        self.parameter_output.parent.mkdir(parents=True, exist_ok=True)
        with self.parameter_output.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("parameter", "key", "period", "value"))
            writer.writerows(rows)
        print(f"PARAMETER_OUTPUT\t{self.parameter_output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runner", type=Path)
    parser.add_argument("--parameter-output", type=Path)
    args = parser.parse_args()

    runner = args.runner.resolve()
    sys.path.insert(0, str(runner.parent))
    import empire

    empire.SolverFactory = lambda *_args, **_kwargs: _InspectingSolver(
        args.parameter_output
    )
    runpy.run_path(str(runner), run_name="__main__")


if __name__ == "__main__":
    main()
