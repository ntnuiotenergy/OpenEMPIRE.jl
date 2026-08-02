"""Compare the natural-gas objective coefficients of both LPs.

`compare_gas_matrix.py` compares the constraint block (A, b, sense). It does not
touch the objective vector c, so a module could build identical constraints and still
price gas differently -- and pricing is half of what the gas module does. This closes
that gap.

The coefficients carry the full operational weighting chain: discount rate x seasonal
scale x scenario probability x the terminal price itself. Agreement therefore tests
the weighting logic, not just the price data.

Objective coefficients on gas variables do not depend on the weather draw (they are
built from the discount rate, seasScale, scenario probability and terminal cost), so
this comparison is unaffected by the sampling-key divergence between the two
implementations.
"""
import argparse
import collections
import re
import sys

REG_HOURS = 24

PY_VARS = {
    "ng_terminalImport": ("terminal_import", 4),
    "transport_naturalGasDemandShed": ("transport_shed", 4),
    "transport_naturalGasDemandMet": ("transport_met", 4),
    "ng_chargeStorage": ("storage_charge", 4),
    "ng_dischargeStorage": ("storage_discharge", 4),
    "ng_storageOperational": ("storage_level", 4),
    "ng_transmission": ("transmission", 4),
    "ng_forPower": ("for_power", 4),
    "genOperational": ("generation", 4),
}
JL_VARS = {
    "ngTerminalImport": "terminal_import",
    "transportNaturalGasDemandShed": "transport_shed",
    "transportNaturalGasDemandMet": "transport_met",
    "ngStorageCharge": "storage_charge",
    "ngStorageDischarge": "storage_discharge",
    "ngStorageOperational": "storage_level",
    "ngTransmission": "transmission",
    "ngForPower": "for_power",
    "genOperational": "generation",
}

GAS_GENERATORS = {"Gasexisting", "GasOCGT", "GasCCGT", "GasCCS", "GasCCSadv"}
CCS_GENERATORS = {"GasCCS", "GasCCSadv"}


def canon_entity(name):
    return re.sub(r"[^A-Za-z0-9]", "", name)


def scenario_number(token):
    """`scenario2` -> "2"; a bare number passes through."""
    m = re.match(r"^scenario(\d+)$", str(token))
    return m.group(1) if m else str(token)


def hour_to_rp_t(hour):
    idx = (int(hour) - 1) // REG_HOURS
    return idx + 1, int(hour) - idx * REG_HOURS


def py_objective(path):
    """Coefficients between `min` and the first constraint row."""
    coefs = {}
    term = re.compile(r"([+-]\s*[\d.]+(?:[eE][+-]?\d+)?)\s+([A-Za-z_][\w]*)\((.*?)\)")
    started = False
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not started:
                if s.lower().startswith("min"):
                    started = True
                continue
            if s.startswith("c_") or s.lower() in ("s.t.", "subject to"):
                break
            for coef, base, inner in term.findall(s):
                info = PY_VARS.get(base)
                if info is None:
                    continue
                cname, ntail = info
                toks = inner.split("_")
                if cname == "generation":
                    generator = toks[-ntail - 1]
                    if generator not in GAS_GENERATORS:
                        continue
                    cname = f"generation_{generator}"
                ent = canon_entity("_".join(toks[:-ntail]))
                rp, t = hour_to_rp_t(toks[-4])
                sc = scenario_number(toks[-2])
                key = f"{cname}|{ent}|sp{toks[-3]}_rp{rp}_sc{sc}_t{t}"
                coefs[key] = coefs.get(key, 0.0) + float(coef.replace(" ", ""))
    return coefs


def jl_objective(path):
    coefs = {}
    term = re.compile(r"([+-]?\s*[\d.]+(?:[eE][+-]?\d+)?)\s+([A-Za-z][\w]*)_([^\s+-]*)")
    started = False
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not started:
                if s.lower().startswith("minimize"):
                    started = True
                continue
            if s.lower().startswith("subject to"):
                break
            body = s[4:] if s.lower().startswith("obj:") else s
            for coef, base, rest in term.findall(body):
                cname = JL_VARS.get(base)
                if cname is None:
                    continue
                parts = rest.rstrip("_").split(",")
                m = re.match(r"^sp(\d+)_rp(\d+)(?:_sc(\d+))?_t(\d+)$", parts[-1])
                if not m:
                    continue
                if cname == "generation":
                    generator = parts[-2]
                    if generator not in GAS_GENERATORS:
                        continue
                    cname = f"generation_{generator}"
                ent = canon_entity("_".join(parts[:-1]))
                sc = m.group(3) or "1"
                key = f"{cname}|{ent}|sp{m.group(1)}_rp{m.group(2)}_sc{sc}_t{m.group(4)}"
                coefs[key] = coefs.get(key, 0.0) + float(coef.replace(" ", ""))
    return coefs


def close(a, b, rtol=1e-9, atol=1e-9):
    return abs(a - b) <= atol + rtol * max(abs(a), abs(b))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("python_lp")
    parser.add_argument("julia_lp")
    parser.add_argument(
        "--allow-ccs-difference",
        action="store_true",
        help="report, but do not fail on, the documented base-OpenEMPIRE CCS term",
    )
    args = parser.parse_args(argv)
    py = py_objective(args.python_lp)
    jl = jl_objective(args.julia_lp)
    if not py or not jl:
        raise ValueError(
            f"no gas-relevant objective coefficients parsed: python={len(py)}, julia={len(jl)}"
        )

    groups = collections.defaultdict(lambda: [0, 0, 0, 0.0, []])
    for key in set(py) | set(jl):
        name = key.split("|", 1)[0]
        g = groups[name]
        a, b = py.get(key), jl.get(key)
        if a is None or b is None:
            g[2] += 1
            continue
        g[0] += 1
        if close(a, b):
            g[1] += 1
        else:
            rel = abs(a - b) / max(abs(a), abs(b), 1e-30)
            g[3] = max(g[3], rel)
            if len(g[4]) < 3:
                g[4].append((key, a, b))

    print(f"{'gas variable':20s} {'shared':>8s} {'agree':>8s} {'unmatched':>10s} {'max rel':>10s}")
    ok = True
    for name in sorted(groups):
        shared, agree, unmatched, maxrel, samples = groups[name]
        ccs_group = name in {f"generation_{generator}" for generator in CCS_GENERATORS}
        accepted_difference = ccs_group and args.allow_ccs_difference and unmatched == 0
        group_ok = (shared == agree and unmatched == 0) or accepted_difference
        flag = ""
        if accepted_difference and shared != agree:
            flag = "  <-- DOCUMENTED CCS DIFFERENCE"
        elif not group_ok:
            flag = "  <-- CHECK"
        ok &= group_ok
        print(f"{name:20s} {shared:8d} {agree:8d} {unmatched:10d} {maxrel:10.2e}{flag}")
        for key, a, b in samples:
            print(f"    {key}: python={a!r} julia={b!r}")

    required = {"terminal_import", "transport_shed"} | {
        f"generation_{generator}" for generator in GAS_GENERATORS - CCS_GENERATORS
    }
    absent = required - groups.keys()
    if absent:
        raise ValueError(
            f"expected gas-relevant objective families were not parsed: {sorted(absent)}"
        )

    total = sum(g[0] for g in groups.values())
    print(f"\ncoefficients compared: {total}")
    documented_ccs_difference = any(
        name in {f"generation_{generator}" for generator in CCS_GENERATORS}
        and group[0] != group[1]
        for name, group in groups.items()
    )
    if not ok:
        print("DIFFERENCES FOUND")
    elif documented_ccs_difference:
        print("GAS OBJECTIVE ACCEPTED WITH DOCUMENTED CCS DIFFERENCES")
    else:
        print("GAS OBJECTIVE IDENTICAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
