"""Compare variable bounds on the natural-gas variables.

The constraint and objective comparisons cover A, b, sense and c. Bounds are the last
piece of the LP that the gas module controls: a variable free where it should be
non-negative, or capped where it should be unbounded, changes the feasible region
without touching a single constraint row.

Pyomo writes `0 <= name <= +inf`; JuMP writes `name >= 0`. Both are normalised to a
(lower, upper) pair before comparison.
"""
import collections
import math
import re
import sys

REG_HOURS = 24

PY_VARS = {
    "ng_terminalImport": ("terminal_import", 4),
    "ng_transmission": ("transmission", 4),
    "ng_forPower": ("for_power", 4),
    "ng_storageOperational": ("storage_level", 4),
    "ng_chargeStorage": ("storage_charge", 4),
    "ng_dischargeStorage": ("storage_discharge", 4),
    "transport_naturalGasDemandMet": ("transport_met", 4),
    "transport_naturalGasDemandShed": ("transport_shed", 4),
}
JL_VARS = {
    "ngTerminalImport": "terminal_import",
    "ngTransmission": "transmission",
    "ngForPower": "for_power",
    "ngStorageOperational": "storage_level",
    "ngStorageCharge": "storage_charge",
    "ngStorageDischarge": "storage_discharge",
    "transportNaturalGasDemandMet": "transport_met",
    "transportNaturalGasDemandShed": "transport_shed",
}


def canon_entity(name):
    return re.sub(r"[^A-Za-z0-9]", "", name)


def scenario_number(token):
    """`scenario2` -> "2"; a bare number passes through."""
    m = re.match(r"^scenario(\d+)$", str(token))
    return m.group(1) if m else str(token)


def hour_to_rp_t(hour):
    idx = (int(hour) - 1) // REG_HOURS
    return idx + 1, int(hour) - idx * REG_HOURS


def num(tok):
    tok = tok.strip()
    if tok in ("+inf", "inf", "1e+30"):
        return math.inf
    if tok in ("-inf", "-1e+30"):
        return -math.inf
    return float(tok)


def py_bounds(path):
    out = {}
    pat = re.compile(r"^\s*(\S+)\s*<=\s*([A-Za-z_]\w*)\((.*?)\)\s*<=\s*(\S+)\s*$")
    started = False
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.rstrip()
            if not started:
                if s.strip().lower() == "bounds":
                    started = True
                continue
            if s.strip().lower() in ("end", "binaries", "generals"):
                break
            m = pat.match(s)
            if not m:
                continue
            info = PY_VARS.get(m.group(2))
            if info is None:
                continue
            cname, ntail = info
            toks = m.group(3).split("_")
            ent = canon_entity("_".join(toks[:-ntail]))
            rp, t = hour_to_rp_t(toks[-4])
            sc = scenario_number(toks[-2])
            out[f"{cname}|{ent}|sp{toks[-3]}_rp{rp}_sc{sc}_t{t}"] = (num(m.group(1)), num(m.group(4)))
    return out


def jl_bounds(path):
    out = {}
    started = False
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not started:
                if s.lower() == "bounds":
                    started = True
                continue
            if s.lower() in ("end", "binaries", "generals", "general"):
                break
            m = re.match(r"^([A-Za-z]\w*)_(\S+?)\s*(>=|<=|==)\s*(\S+)$", s)
            two = re.match(r"^(\S+)\s*<=\s*([A-Za-z]\w*)_(\S+?)\s*<=\s*(\S+)$", s)
            if two:
                base, rest, lo, hi = two.group(2), two.group(3), num(two.group(1)), num(two.group(4))
            elif m:
                base, rest = m.group(1), m.group(2)
                if m.group(3) == ">=":
                    lo, hi = num(m.group(4)), math.inf
                elif m.group(3) == "<=":
                    lo, hi = -math.inf, num(m.group(4))
                else:
                    lo = hi = num(m.group(4))
            else:
                continue
            cname = JL_VARS.get(base)
            if cname is None:
                continue
            parts = rest.rstrip("_").split(",")
            mm = re.match(r"^sp(\d+)_rp(\d+)(?:_sc(\d+))?_t(\d+)$", parts[-1])
            if not mm:
                continue
            ent = canon_entity("_".join(parts[:-1]))
            sc = mm.group(3) or "1"
            out[f"{cname}|{ent}|sp{mm.group(1)}_rp{mm.group(2)}_sc{sc}_t{mm.group(4)}"] = (lo, hi)
    return out


def main():
    py, jl = py_bounds(sys.argv[1]), jl_bounds(sys.argv[2])
    groups = collections.defaultdict(lambda: [0, 0, 0, []])
    for key in set(py) | set(jl):
        name = key.split("|", 1)[0]
        g = groups[name]
        a, b = py.get(key), jl.get(key)
        if a is None or b is None:
            g[2] += 1
            if len(g[3]) < 2:
                g[3].append((key, a, b))
            continue
        g[0] += 1
        if a == b:
            g[1] += 1
        elif len(g[3]) < 2:
            g[3].append((key, a, b))

    print(f"{'gas variable':20s} {'shared':>8s} {'identical':>10s} {'unmatched':>10s}")
    ok = True
    for name in sorted(groups):
        shared, same, unmatched, samples = groups[name]
        flag = "" if shared == same and unmatched == 0 else "  <-- CHECK"
        ok &= shared == same and unmatched == 0
        print(f"{name:20s} {shared:8d} {same:10d} {unmatched:10d}{flag}")
        for key, a, b in samples:
            print(f"    {key}: python={a} julia={b}")

    total = sum(g[0] for g in groups.values())
    print(f"\nbounds compared: {total}")
    print("GAS BOUNDS IDENTICAL" if ok else "DIFFERENCES FOUND")
    return 0 if ok else 1


sys.exit(main())
