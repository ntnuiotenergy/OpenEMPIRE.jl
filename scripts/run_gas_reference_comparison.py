#!/usr/bin/env python3
"""Run both deterministic InternalEMPIRE/OpenEMPIRE.jl gas LP comparisons."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
INSTANCES = {
    "2p1w": (2, 1, REPOSITORY / "config" / "gas_reference_comparison.yaml"),
    "3p2w": (3, 2, REPOSITORY / "config" / "gas_reference_comparison_3p2s.yaml"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checked(command, *, cwd=None, env=None) -> str:
    result = subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(map(str, command))}\n"
            f"{result.stdout}"
        )
    return result.stdout


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--internal-repo",
        type=Path,
        default=REPOSITORY.parent / "InternalEMPIRE",
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--julia", default="julia")
    parser.add_argument(
        "--instance",
        choices=tuple(INSTANCES),
        action="append",
        help="instance(s) to run; default is both",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    output_root = args.output_dir.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    selected = args.instance or list(INSTANCES)
    evidence = {
        "claim": (
            "The deterministic natural-gas subsystem matches InternalEMPIRE's gas "
            "formulation for its constraints, bounds, and module-controlled costs. "
            "Whole-model objectives and dispatch can differ because OpenEMPIRE.jl "
            "retains base OpenEMPIRE electricity, CCS, emission, and seasonal semantics."
        ),
        "instances": [],
    }

    for name in selected:
        periods, weather, config = INSTANCES[name]
        instance_dir = output_root / name
        instance_dir.mkdir(parents=True, exist_ok=True)
        reference_log = checked(
            [
                sys.executable,
                HERE / "gas_reference_build.py",
                "--internal-repo",
                args.internal_repo,
                "--work-dir",
                instance_dir,
                "--periods",
                periods,
                "--weather-scenarios",
                weather,
            ],
            cwd=REPOSITORY,
        )
        python_lp = instance_dir / "LP_gasparity.lp"
        julia_lp = instance_dir / "julia.lp"
        julia_env = os.environ.copy()
        julia_env["GASPARITY_CONFIG"] = str(config)
        julia_log = checked(
            [
                args.julia,
                f"--project={REPOSITORY}",
                HERE / "write_gas_reference_lp.jl",
                julia_lp,
            ],
            cwd=REPOSITORY,
            env=julia_env,
        )
        comparison_logs = {}
        for label, command in (
            (
                "matrix",
                [sys.executable, HERE / "compare_gas_matrix.py", python_lp, julia_lp],
            ),
            (
                "objective",
                [
                    sys.executable,
                    HERE / "compare_gas_objective.py",
                    python_lp,
                    julia_lp,
                    "--allow-ccs-difference",
                ],
            ),
            (
                "bounds",
                [sys.executable, HERE / "compare_gas_bounds.py", python_lp, julia_lp],
            ),
        ):
            comparison_logs[label] = checked(command, cwd=REPOSITORY)

        (instance_dir / "reference.log").write_text(reference_log, encoding="utf-8")
        (instance_dir / "julia.log").write_text(julia_log, encoding="utf-8")
        for label, log in comparison_logs.items():
            (instance_dir / f"comparison_{label}.log").write_text(log, encoding="utf-8")
        evidence["instances"].append(
            {
                "name": name,
                "periods": periods,
                "weather_scenarios": weather,
                "gas_scenarios": 1,
                "config": str(config.relative_to(REPOSITORY)),
                "python_lp": {
                    "bytes": python_lp.stat().st_size,
                    "sha256": sha256(python_lp),
                },
                "julia_lp": {
                    "bytes": julia_lp.stat().st_size,
                    "sha256": sha256(julia_lp),
                },
                "comparisons": {label: "PASS" for label in comparison_logs},
            }
        )

    evidence_path = output_root / "gas_reference_evidence.json"
    evidence_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"gas reference comparisons: PASS ({', '.join(selected)})")
    print(f"evidence: {evidence_path}")


if __name__ == "__main__":
    main()
