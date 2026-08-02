#!/usr/bin/env python3
"""Dependency-free negative controls for the natural-gas LP comparators."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent


def python_matrix() -> str:
    rows = [
        ("naturalGas_flow_balance", "A_1_1_scenario1_1", "="),
        ("naturalGas_storage_balance", "A_1_1_scenario1_1", "="),
        ("naturalGas_storage_maxCapacity", "A_1_1_scenario1_1", "<="),
        ("naturalGas_net_zero_seasonal_storage", "A_1_1_scenario1_1", "="),
        ("naturalGas_terminal_capacity", "A_DomesticProduction_1_1_scenario1_1", "<="),
        ("naturalGas_pipeline_capacity", "A_B_1_1_scenario1_1", "<="),
        ("naturalGas_for_power", "A_GasCCGT_1_1_scenario1_1", "="),
        ("meet_transport_naturalGas_demand", "A_1_scenario1_1_1", ">="),
        ("naturalGas_max_reserves", "A_DomesticProduction_scenario1_1", "<="),
    ]
    lines = ["min", " obj: + 1 x", "s.t."]
    for index, (family, key, sense) in enumerate(rows):
        lines.append(f"c_e_{family}({key})_:")
        lines.append("+ 1 ng_terminalImport(A_DomesticProduction_1_1_scenario1_1)")
        if index == 0:
            lines.append("+ 1 ng_forHydrogen(A_SMR_1_1_scenario1_1)")
        lines.append(f"{sense} 1")
    lines.extend(["bounds", "end"])
    return "\n".join(lines) + "\n"


def julia_matrix() -> str:
    rows = [
        ("natural_gas_flow_balance", "A,sp1_rp1_t1", "="),
        ("natural_gas_storage_balance", "A,(sp1_rp1_t1,_sp1_rp1_t1)", "="),
        ("natural_gas_storage_max_capacity", "A,sp1_rp1_t1", "<="),
        ("natural_gas_storage_cyclic", "A,sp1_rp1_t1", "="),
        ("natural_gas_terminal_capacity_limit", "A,DomesticProduction,sp1_rp1_t1", "<="),
        ("natural_gas_pipeline_capacity_limit", '("A",_"B"),sp1_rp1_t1', "<="),
        ("natural_gas_for_power", "A,GasCCGT,sp1_rp1_t1", "="),
        ("meet_transport_natural_gas_demand", "A,sp1_rp1_t1", ">="),
        ("natural_gas_max_reserves", "A,DomesticProduction,1,1", "<="),
    ]
    lines = ["minimize", " obj: + 1 x", "subject to"]
    for family, key, sense in rows:
        lines.append(f"{family}_{key}_: + 1 ngTerminalImport_A,DomesticProduction,sp1_rp1_t1 {sense} 1")
    lines.extend(["bounds", "end"])
    return "\n".join(lines) + "\n"


def objective_pair() -> tuple[str, str]:
    generators = ("Gasexisting", "GasOCGT", "GasCCGT", "GasCCS", "GasCCSadv")
    py_terms = [
        "+ 2 ng_terminalImport(A_DomesticProduction_1_1_scenario1_1)",
        "+ 3 transport_naturalGasDemandShed(A_1_1_scenario1_1)",
    ]
    jl_terms = [
        "+ 2 ngTerminalImport_A,DomesticProduction,sp1_rp1_t1",
        "+ 3 transportNaturalGasDemandShed_A,sp1_rp1_t1",
    ]
    for offset, generator in enumerate(generators, start=4):
        py_terms.append(f"+ {offset} genOperational(A_{generator}_1_1_scenario1_1)")
        jl_terms.append(f"+ {offset} genOperational_A,{generator},sp1_rp1_t1")
    py = "min\n obj: " + "\n ".join(py_terms) + "\ns.t.\n"
    jl = "minimize\n obj: " + "\n ".join(jl_terms) + "\nsubject to\n"
    return py, jl


def bounds_pair() -> tuple[str, str]:
    py_vars = (
        "ng_terminalImport(A_DomesticProduction_1_1_scenario1_1)",
        "ng_transmission(A_B_1_1_scenario1_1)",
        "ng_forPower(A_GasCCGT_1_1_scenario1_1)",
        "ng_storageOperational(A_1_1_scenario1_1)",
        "ng_chargeStorage(A_1_1_scenario1_1)",
        "ng_dischargeStorage(A_1_1_scenario1_1)",
        "transport_naturalGasDemandMet(A_1_1_scenario1_1)",
        "transport_naturalGasDemandShed(A_1_1_scenario1_1)",
    )
    jl_vars = (
        "ngTerminalImport_A,DomesticProduction,sp1_rp1_t1",
        "ngTransmission_A,B,sp1_rp1_t1",
        "ngForPower_A,GasCCGT,sp1_rp1_t1",
        "ngStorageOperational_A,sp1_rp1_t1",
        "ngStorageCharge_A,sp1_rp1_t1",
        "ngStorageDischarge_A,sp1_rp1_t1",
        "transportNaturalGasDemandMet_A,sp1_rp1_t1",
        "transportNaturalGasDemandShed_A,sp1_rp1_t1",
    )
    py = "bounds\n" + "\n".join(f"0 <= {name} <= +inf" for name in py_vars) + "\nend\n"
    jl = "bounds\n" + "\n".join(f"{name} >= 0" for name in jl_vars) + "\nend\n"
    return py, jl


def run(script: str, left: Path, right: Path, *extra: str, success: bool) -> None:
    result = subprocess.run(
        [sys.executable, str(HERE / script), str(left), str(right), *extra],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if (result.returncode == 0) != success:
        raise AssertionError(
            f"{script} expected success={success}, exit={result.returncode}\n{result.stdout}"
        )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="gas-comparator-tests-") as tmp:
        root = Path(tmp)
        py = root / "python.lp"
        jl = root / "julia.lp"

        py.write_text(python_matrix())
        jl.write_text(julia_matrix())
        run("compare_gas_matrix.py", py, jl, success=True)

        original = jl.read_text()
        jl.write_text(original.replace("+ 1 ngTerminalImport", "+ 1.0001 ngTerminalImport", 1))
        run("compare_gas_matrix.py", py, jl, success=False)
        jl.write_text(original.replace("<= 1", "<= 1.001", 1))
        run("compare_gas_matrix.py", py, jl, success=False)
        jl.write_text(original.replace("flow_balance_A", "flow_balance_B", 1))
        run("compare_gas_matrix.py", py, jl, success=False)
        jl.write_text(original.replace("ngTerminalImport", "unexpectedGasVariable", 1))
        run("compare_gas_matrix.py", py, jl, success=False)

        objective_py, objective_jl = objective_pair()
        py.write_text(objective_py)
        jl.write_text(objective_jl)
        run(
            "compare_gas_objective.py",
            py,
            jl,
            "--allow-ccs-difference",
            success=True,
        )
        jl.write_text(objective_jl.replace("+ 6 genOperational", "+ 6.01 genOperational"))
        run(
            "compare_gas_objective.py",
            py,
            jl,
            "--allow-ccs-difference",
            success=False,
        )

        bounds_py, bounds_jl = bounds_pair()
        py.write_text(bounds_py)
        jl.write_text(bounds_jl)
        run("compare_gas_bounds.py", py, jl, success=True)
        jl.write_text(bounds_jl.replace(">= 0", ">= 0.5", 1))
        run("compare_gas_bounds.py", py, jl, success=False)

    print("gas comparator negative controls: PASS")


if __name__ == "__main__":
    main()
