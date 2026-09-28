#!/usr/bin/env python3
"""Shared, dependency-free streaming algebra fingerprint primitives."""

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


def canonical_component(value: object) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", str(value))


def entity_key(values: Iterable[object]) -> str:
    return "~".join(canonical_component(value) for value in values)


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
    return tuple(
        int.from_bytes(digest[offset : offset + 8], "big")
        for offset in range(0, 32, 8)
    )


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
    """Order-independent SHA-256 multiset summaries with localization buckets."""

    def __init__(self) -> None:
        self.overall: dict[tuple[str, str, int], Accumulator] = {}
        self.buckets: dict[tuple[str, str, int, int], Accumulator] = {}
        self.excluded: dict[tuple[str, str], int] = defaultdict(int)

    def ensure(self, kind: str, group: str) -> None:
        for precision in PRECISIONS:
            self.overall.setdefault((kind, group, precision), Accumulator())

    def add(
        self,
        kind: str,
        group: str,
        key: str,
        records: dict[int, str],
        terms: int = 0,
    ) -> None:
        bucket = hashlib.sha256(key.encode("utf-8")).digest()[0]
        for precision, payload in records.items():
            self.overall.setdefault((kind, group, precision), Accumulator()).add(
                payload, terms
            )
            self.buckets.setdefault(
                (kind, group, precision, bucket), Accumulator()
            ).add(payload, terms)

    def write(self, path: Path, metadata: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as handle:
            for key, value in sorted(metadata.items()):
                handle.write(f"META\t{key}\t{value}\n")
            for (kind, group), count in sorted(self.excluded.items()):
                handle.write(f"EXCLUDED\t{kind}\t{group}\t{count}\n")
            for (kind, group, precision), accumulator in sorted(self.overall.items()):
                handle.write(
                    "\t".join(
                        ("SUMMARY", kind, group, str(precision), *accumulator.fields())
                    )
                    + "\n"
                )
            for (kind, group, precision, bucket), accumulator in sorted(
                self.buckets.items()
            ):
                handle.write(
                    "\t".join(
                        (
                            "BUCKET",
                            kind,
                            group,
                            str(precision),
                            str(bucket),
                            *accumulator.fields(),
                        )
                    )
                    + "\n"
                )


def constraint_terms(constraint: object) -> tuple[list[tuple[object, float]], str, float]:
    """Return linear terms, sense, and RHS with body constants moved to the RHS."""
    from pyomo.environ import value
    from pyomo.repn.standard_repn import generate_standard_repn

    representation = generate_standard_repn(constraint.body, compute_values=True)
    if not representation.is_linear():
        raise ValueError(f"nonlinear row: {constraint.name}")
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
    raise ValueError(f"unsupported ranged row: {constraint.name}")


def normalized_records(
    key: str, sense: str, rhs: float, terms: dict[str, float]
) -> dict[int, str]:
    """Normalize a row for uniform nonzero scaling and sign."""
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
                    f"{name}={float_text(value, precision)}"
                    for name, value in sorted(terms.items())
                ),
            )
        )
        for precision in PRECISIONS
    }


def raw_records(key: str, values: Iterable[float]) -> dict[int, str]:
    values = tuple(values)
    return {
        precision: "\t".join(
            (key, *(float_text(value, precision) for value in values))
        )
        for precision in PRECISIONS
    }
