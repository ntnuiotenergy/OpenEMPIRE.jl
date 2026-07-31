"""Structured diff of InternalEMPIRE/empire.py against base OpenEMPIRE-csv.

A raw textual diff is useless here: InternalEMPIRE is 5,791 lines against the base's
1,574, and most of that is whole modules the base does not have (hydrogen, industry,
heat, transport, CVaR, natural gas). Those additions are expected and uninteresting.

What matters is where the two disagree about the *shared* model -- a parameter the
base declares that the fork disabled, a rule whose body was edited, a coefficient
changed. Those are the divergences that make whole-model results differ, and they are
invisible in a line diff.

So this matches constructs by name:
  * `model.<name> = Param/Var/Set/Constraint/Expression/Objective(...)` declarations
  * `def <name>(...)` rule bodies, including nested ones inside run_empire

and reports, for names present in both, whether the source differs. It also scans for
declarations that are live in the base but commented out in the fork, which is how the
two CCS cost terms were disabled and is easy to miss.
"""
import ast
import difflib
import re
import sys

BASE = "/Users/torgrim/Documents/NTNU/iot/empire/OpenEMPIRE-csv/empire/core/empire.py"
FORK = "/Users/torgrim/Documents/NTNU/iot/empire/InternalEMPIRE/empire.py"

DECL_RE = re.compile(r"^\s*model\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\w+)\s*\(")
COMMENTED_DECL_RE = re.compile(r"^\s*#\s*model\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\w+)\s*\(")


def norm(text):
    """Whitespace- and comment-insensitive normalisation."""
    out = []
    for line in text.splitlines():
        line = re.sub(r"#.*$", "", line).strip()
        if line:
            out.append(re.sub(r"\s+", " ", line))
    return "\n".join(out)


def functions(path):
    """Every function def in the file, by name, including nested ones."""
    src = open(path).read()
    tree = ast.parse(src)
    lines = src.splitlines(keepends=True)
    found = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            seg = "".join(lines[node.lineno - 1 : node.end_lineno])
            # A name can appear more than once (e.g. redefined under a flag); keep the
            # longest body so the comparison is against the substantive definition.
            if node.name not in found or len(seg) > len(found[node.name][1]):
                found[node.name] = (node.lineno, seg)
    return found


def declarations(path):
    decls, commented = {}, {}
    for i, line in enumerate(open(path), 1):
        m = DECL_RE.match(line)
        if m:
            decls.setdefault(m.group(1), (i, m.group(2), line.strip()))
        m = COMMENTED_DECL_RE.match(line)
        if m:
            commented.setdefault(m.group(1), (i, m.group(2), line.strip()))
    return decls, commented


def main():
    bf, ff = functions(BASE), functions(FORK)
    bd, bc = declarations(BASE)
    fd, fc = declarations(FORK)

    print("=" * 78)
    print("1. LIVE IN BASE, COMMENTED OUT IN INTERNALEMPIRE")
    print("   (the CCS pattern: the fork disabled something the base charges)")
    print("=" * 78)
    hits = sorted(set(bd) & set(fc) - set(fd))
    for name in hits:
        print(f"  {name}")
        print(f"      base   {BASE.split('/')[-1]}:{bd[name][0]}  {bd[name][2][:90]}")
        print(f"      fork   empire.py:{fc[name][0]}  {fc[name][2][:90]}")
    print(f"  -> {len(hits)} found")

    print()
    print("=" * 78)
    print("2. DECLARED IN BASE, ABSENT FROM INTERNALEMPIRE ENTIRELY")
    print("=" * 78)
    missing = sorted(set(bd) - set(fd) - set(fc))
    for name in missing:
        print(f"  {name:42s} base:{bd[name][0]} ({bd[name][1]})")
    print(f"  -> {len(missing)} found")

    print()
    print("=" * 78)
    print("3. SHARED RULES WHOSE BODY DIFFERS")
    print("   (same name in both, different maths -- the ones that change results)")
    print("=" * 78)
    shared = sorted(set(bf) & set(ff))
    differing = []
    for name in shared:
        a, b = norm(bf[name][1]), norm(ff[name][1])
        if a != b:
            ratio = difflib.SequenceMatcher(None, a, b).ratio()
            differing.append((ratio, name))
    differing.sort()
    for ratio, name in differing:
        print(f"  {name:46s} similarity {ratio:5.1%}   base:{bf[name][0]} fork:{ff[name][0]}")
    print(f"  -> {len(differing)} of {len(shared)} shared functions differ")

    print()
    print("=" * 78)
    print("4. DETAIL: the most-changed shared rules")
    print("=" * 78)
    for ratio, name in differing[: int(sys.argv[1]) if len(sys.argv) > 1 else 6]:
        print(f"\n--- {name} (similarity {ratio:.1%}) ---")
        diff = difflib.unified_diff(
            norm(bf[name][1]).splitlines(),
            norm(ff[name][1]).splitlines(),
            fromfile="base", tofile="internal", lineterm="", n=1,
        )
        for line in list(diff)[:40]:
            print("   " + line)


main()
