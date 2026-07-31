"""Compare the natural-gas rows of InternalEMPIRE's LP against OpenEMPIRE.jl's.

Both files are written by their own model builder with symbolic labels, so nothing
here compares text: rows and columns are reduced to a shared canonical key and the
numbers are compared.

Index encodings differ completely and are reconciled explicitly:

  Pyomo   naturalGas_flow_balance(Austria_1_1_scenario1_1)
          -> entity "Austria", hour 1, period 1, weather scenario, gas scenario
  JuMP    natural_gas_flow_balance_Austria,sp1_rp1_t1_
          -> entity "Austria", strategic period 1, representative period 1, hour 1

With one regular 24 h season followed by two 24 h peak seasons, Pyomo's flat hour
1..72 maps onto (representative period, hour) as 1-24 -> rp1, 25-48 -> rp2,
49-72 -> rp3, and its Period i maps to sp{i}. Entity names are never split on "_",
because several contain one.
"""
import collections
import json
import re
import sys

REG_HOURS = 24
SEASONS = 3

# canonical family <- (pyomo name, jump name)
FAMILIES = {
    "flow_balance": ("naturalGas_flow_balance", "natural_gas_flow_balance"),
    "storage_balance": ("naturalGas_storage_balance", "natural_gas_storage_balance"),
    "storage_max_capacity": ("naturalGas_storage_maxCapacity", "natural_gas_storage_max_capacity"),
    "storage_cyclic": ("naturalGas_net_zero_seasonal_storage", "natural_gas_storage_cyclic"),
    "terminal_capacity": ("naturalGas_terminal_capacity", "natural_gas_terminal_capacity_limit"),
    "pipeline_capacity": ("naturalGas_pipeline_capacity", "natural_gas_pipeline_capacity_limit"),
    "for_power": ("naturalGas_for_power", "natural_gas_for_power"),
    "transport_demand": ("meet_transport_naturalGas_demand", "meet_transport_natural_gas_demand"),
    "max_reserves": ("naturalGas_max_reserves", "natural_gas_max_reserves"),
}
# Trailing index tokens on the Pyomo side, and their meaning.
PY_TAIL = {
    "flow_balance": ("h", "i", "w", "gp"),
    "storage_balance": ("h", "i", "w", "gp"),
    "storage_max_capacity": ("h", "i", "w", "gp"),
    "storage_cyclic": ("h", "i", "w", "gp"),
    "terminal_capacity": ("h", "i", "w", "gp"),
    "pipeline_capacity": ("h", "i", "w", "gp"),
    "for_power": ("h", "i", "w", "gp"),
    "transport_demand": ("i", "w", "gp", "h"),  # note: hour LAST here
    "max_reserves": ("w", "gp"),
}
COLUMNS = {
    "ng_terminalimport": ("terminal_import", 4),
    "ngterminalimport": ("terminal_import", None),
    "ng_transmission": ("transmission", 4),
    "ngtransmission": ("transmission", None),
    "ng_forpower": ("for_power", 4),
    "ngforpower": ("for_power", None),
    "ng_storageoperational": ("storage_level", 4),
    "ngstorageoperational": ("storage_level", None),
    "ng_chargestorage": ("storage_charge", 4),
    "ngstoragecharge": ("storage_charge", None),
    "ng_dischargestorage": ("storage_discharge", 4),
    "ngstoragedischarge": ("storage_discharge", None),
    "transport_naturalgasdemandmet": ("transport_met", 4),
    "transportnaturalgasdemandmet": ("transport_met", None),
    "transport_naturalgasdemandshed": ("transport_shed", 4),
    "transportnaturalgasdemandshed": ("transport_shed", None),
    "genoperational": ("generation", 4),
    "ng_forhydrogen": ("for_hydrogen", 4),
}
PY_FAMILY = {v[0]: k for k, v in FAMILIES.items()}
JL_FAMILY = {v[1]: k for k, v in FAMILIES.items()}


def canon_entity(name):
    """Strip everything but alphanumerics.

    Pyomo's LP writer escapes characters that are illegal in LP names -- "GreatBrit."
    becomes "_GreatBrit__", "Luxemb." becomes "_Luxemb__" -- while JuMP writes the
    name verbatim. Reducing both to alphanumerics makes the two agree. Gas node,
    terminal and generator names contain no "_", so collapsing separators cannot
    merge two distinct entity tuples here.
    """
    return re.sub(r"[^A-Za-z0-9]", "", name)


def canon_time(sp=None, rp=None, t=None):
    parts = []
    if sp is not None:
        parts.append(f"sp{sp}")
    if rp is not None:
        parts.append(f"rp{rp}")
    if t is not None:
        parts.append(f"t{t}")
    return "_".join(parts)


def hour_to_rp_t(hour):
    hour = int(hour)
    idx = (hour - 1) // REG_HOURS
    if idx >= SEASONS:
        raise ValueError(f"hour {hour} outside {SEASONS} seasons")
    return idx + 1, hour - idx * REG_HOURS


def py_key(tokens, tail_spec, drop_hour=False):
    """Split trailing index tokens off the right; the rest is the entity name."""
    n = len(tail_spec)
    entity = "_".join(tokens[:-n]) if n else "_".join(tokens)
    tail = dict(zip(tail_spec, tokens[-n:])) if n else {}
    sp = tail.get("i")
    if "h" in tail and not drop_hour:
        rp, t = hour_to_rp_t(tail["h"])
    elif "h" in tail:
        rp, _ = hour_to_rp_t(tail["h"])
        t = None
    else:
        rp = t = None
    return canon_entity(entity), canon_time(sp, rp, t)


def jl_split(raw):
    """`("A",_"B"),sp1_rp1_t1` or `A,sp1_rp1_t1` -> (entity, [index parts])."""
    raw = raw.strip().rstrip("_")
    if raw.startswith("("):
        close = raw.index(")")
        entities = re.findall(r'"([^"]*)"', raw[: close + 1])
        rest = raw[close + 1 :].lstrip(",")
        parts = [p for p in rest.split(",") if p]
        return canon_entity("_".join(entities)), parts
    parts = raw.split(",")
    # Trailing parts are index labels (sp.., sp.._rp.._t..); the rest is the entity.
    k = len(parts)
    while k > 1 and re.match(r"^sp\d+(_rp\d+)?(_t\d+)?(_sc\d+)?$", parts[k - 1]):
        k -= 1
    return canon_entity("_".join(parts[:k])), parts[k:]


def jl_time(parts):
    """Reduce JuMP index labels to the canonical sp/rp/t string."""
    sp = rp = t = None
    for p in parts:
        m = re.match(r"^sp(\d+)(?:_rp(\d+))?(?:_t(\d+))?(?:_sc\d+)?$", p)
        if not m:
            continue
        sp = sp or m.group(1)
        rp = rp or m.group(2)
        t = t or m.group(3)
    return sp, rp, t


def parse_python(path, want):
    rows, cur, spec = {}, None, None
    row_re = re.compile(r"^c_[elu]_([A-Za-z_]+)\((.*)\)_?:$")
    term_re = re.compile(r"([+-]?\s*[\d.]+(?:[eE][+-]?\d+)?)?\s*([A-Za-z_][\w()]*)")
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not s:
                continue
            if s.lower() in ("bounds", "end", "binaries", "generals"):
                break
            m = row_re.match(s)
            if m:
                fam = PY_FAMILY.get(m.group(1))
                if fam not in want:
                    cur = None
                    continue
                spec = PY_TAIL[fam]
                entity, time = py_key(m.group(2).split("_"), spec,
                                      drop_hour=(fam == "storage_cyclic"))
                cur = (fam, entity, time)
                rows[cur] = {"terms": {}, "sense": None, "rhs": None}
                continue
            if cur is None:
                continue
            rec = rows[cur]
            sm = re.match(r"^(<=|>=|==|=)\s*(-?[\d.eE+-]+)$", s)
            if sm:
                rec["sense"] = "==" if sm.group(1) in ("=", "==") else sm.group(1)
                rec["rhs"] = float(sm.group(2))
                cur = None
                continue
            for coef, name in term_re.findall(s):
                if "(" not in name:
                    continue
                base, inner = name.split("(", 1)
                info = COLUMNS.get(base.lower())
                if info is None:
                    continue
                cname, ntail = info
                toks = inner.rstrip(")").split("_")
                ent, tm = py_key(toks, ("h", "i", "w", "gp")[:ntail])
                c = (coef or "+1").replace(" ", "")
                if c in ("+", "-"):
                    c += "1"
                lbl = f"{cname}|{ent}|{tm}"
                rec["terms"][lbl] = rec["terms"].get(lbl, 0.0) + float(c)
    return rows


def parse_julia(path, want):
    rows, cur = {}, None
    names = sorted(JL_FAMILY, key=len, reverse=True)
    term_re = re.compile(r"([+-]?\s*[\d.]+(?:[eE][+-]?\d+)?)?\s*([A-Za-z][\w,.()\"]*)")
    with open(path, errors="replace") as fh:
        for line in fh:
            s = line.lstrip()
            if not s.strip():
                continue
            low = s.strip().lower()
            if low in ("bounds", "end", "binaries", "generals"):
                break
            head = None
            if ":" in s:
                cand = s.split(":", 1)[0]
                for n in names:
                    if cand.startswith(n):
                        head = (n, cand[len(n):])
                        break
            if head is not None:
                fam = JL_FAMILY[head[0]]
                if fam not in want:
                    cur = None
                    body = ""
                else:
                    raw = head[1].lstrip("_").rstrip("_")
                    if fam == "max_reserves":
                        # base_name is [node,terminal,weather,gas]; the two trailing
                        # scenario indices are not part of the Pyomo row key.
                        comps = raw.split(",")
                        entity = canon_entity("_".join(comps[:-2]))
                        sp = rp = t = None
                    elif fam == "storage_balance":
                        # Indexed by withprev, so the label holds a (previous, current)
                        # pair such as "(sp1_rp1_t1,_sp1_rp1_t2)". Pyomo keys this row
                        # by the CURRENT hour, so take the last label in the pair.
                        entity = canon_entity(raw.split(",")[0])
                        labels = re.findall(r"sp(\d+)_rp(\d+)_t(\d+)", raw)
                        sp, rp, t = labels[-1]
                    else:
                        entity, parts = jl_split(raw)
                        sp, rp, t = jl_time(parts)
                        if fam == "storage_cyclic":
                            t = None
                    cur = (fam, entity, canon_time(sp, rp, t))
                    rows[cur] = {"terms": {}, "sense": None, "rhs": None}
                body = s.split(":", 1)[1]
            else:
                if cur is None:
                    continue
                body = s
            rec = rows[cur] if cur else None
            if rec is None:
                continue
            sm = re.search(r"(<=|>=|==|=)\s*(-?[\d.eE+-]+)\s*$", body)
            if sm:
                rec["sense"] = "==" if sm.group(1) in ("=", "==") else sm.group(1)
                rec["rhs"] = float(sm.group(2))
                body = body[: sm.start()]
            for coef, name in term_re.findall(body):
                if "_" not in name:
                    continue
                base, rest = name.split("_", 1)
                info = COLUMNS.get(base.lower())
                if info is None:
                    continue
                cname = info[0]
                ent, parts = jl_split(rest)
                sp, rp, t = jl_time(parts)
                c = (coef or "+1").replace(" ", "")
                if c in ("+", "-"):
                    c += "1"
                lbl = f"{cname}|{ent}|{canon_time(sp, rp, t)}"
                rec["terms"][lbl] = rec["terms"].get(lbl, 0.0) + float(c)
            if sm:
                cur = None
    return rows


def close(a, b, rtol=1e-9, atol=1e-9):
    return abs(a - b) <= atol + rtol * max(abs(a), abs(b))


def main():
    py_path, jl_path = sys.argv[1], sys.argv[2]
    want = set(FAMILIES)
    py = parse_python(py_path, want)
    jl = parse_julia(jl_path, want)

    print(f"{'family':22s} {'python':>8s} {'julia':>8s} {'matched':>8s} {'coefs':>11s} {'diffs':>6s} {'max rel':>10s}")
    total_bad = 0
    report = collections.defaultdict(list)
    for fam in sorted(FAMILIES):
        pk = {k: v for k, v in py.items() if k[0] == fam}
        jk = {k: v for k, v in jl.items() if k[0] == fam}
        shared = set(pk) & set(jk)
        maxrel, bad, ncoef = 0.0, 0, 0
        for k in shared:
            p, j = pk[k], jk[k]
            cols = set(p["terms"]) | set(j["terms"])
            for c in cols:
                a, b = p["terms"].get(c, 0.0), j["terms"].get(c, 0.0)
                if c.startswith("for_hydrogen|"):
                    continue  # documented: reforming is outside the port
                ncoef += 1
                if not close(a, b):
                    bad += 1
                    if len(report[fam]) < 4:
                        report[fam].append((k, c, a, b))
                else:
                    d = abs(a - b) / max(abs(a), abs(b), 1e-30)
                    maxrel = max(maxrel, d)
            if p["rhs"] is not None and j["rhs"] is not None and not close(p["rhs"], j["rhs"]):
                bad += 1
                if len(report[fam]) < 4:
                    report[fam].append((k, "RHS", p["rhs"], j["rhs"]))
        total_bad += bad
        only_py, only_jl = len(set(pk) - set(jk)), len(set(jk) - set(pk))
        flag = "" if (not bad and not only_py and not only_jl) else "  <-- CHECK"
        print(f"{fam:22s} {len(pk):8d} {len(jk):8d} {len(shared):8d} {ncoef:11d} {bad:6d} {maxrel:10.2e}{flag}")
        globals()['TOTAL_COEF'] = globals().get('TOTAL_COEF', 0) + ncoef
        if only_py or only_jl:
            print(f"{'':22s} keys only in python: {only_py}, only in julia: {only_jl}")
            for k in list(set(pk) - set(jk))[:3]:
                print(f"{'':24s} py-only {k}")
            for k in list(set(jk) - set(pk))[:3]:
                print(f"{'':24s} jl-only {k}")
        total_bad += only_py + only_jl

    for fam, items in report.items():
        print(f"\nsample differences in {fam}:")
        for k, c, a, b in items:
            print(f"  {k} {c}: python={a!r} julia={b!r}")

    print()
    print(f"coefficients compared: {globals().get('TOTAL_COEF', 0)}")
    print("GAS MATRIX IDENTICAL" if total_bad == 0 else f"DIFFERENCES: {total_bad}")
    return 0 if total_bad == 0 else 1


sys.exit(main())
