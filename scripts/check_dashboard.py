"""Report the numbers that decide whether a dashboard is readable.

Usage:
    python scripts/check_dashboard.py <run>/Plots [<other-run>/Plots]

Pass two directories to compare them, e.g. a dashboard built before a change
against one built after. Written for eyeballs, not CI: it prints counts and says
what each should look like, it does not assert.
"""

import json
import re
import sys
from pathlib import Path


def _parse(path):
    text = path.read_text(encoding="utf-8")
    data = re.search(r"const data = (\[.*?\]);\n", text, re.S)
    layout = re.search(r"const layout = (\{.*?\});\n", text, re.S)
    if not data or not layout:
        return None, None
    return json.loads(data.group(1)), json.loads(layout.group(1))


def _buttons(layout):
    menus = layout.get("updatemenus") or []
    return len(menus[0].get("buttons", [])) if menus else 0


def report(plots: Path):
    print(f"\n=== {plots} ===")
    pages = sorted(plots.glob("*.html"))
    dispatch = [p for p in pages if p.name.startswith("dispatch_")]
    print(f"pages: {len(pages)}  (of which dispatch: {len(dispatch)})")
    total_mb = sum(p.stat().st_size for p in pages) / 1024**2
    print(f"total size: {total_mb:.1f} MB")

    checks = {
        "transmission_installed_capacity_map.html": "result map",
        "input_transmission_map.html": "input map",
    }
    for name, label in checks.items():
        path = plots / name
        if not path.exists():
            print(f"{label:22} MISSING")
            continue
        data, layout = _parse(path)
        visible = [t for t in data if t.get("visible") is not False]
        framed = "lataxis" in layout.get("geo", {})
        print(
            f"{label:22} {len(visible):>4} visible traces (legend rows)"
            f" | framed on nodes: {framed}"
        )
        print(f"{'':22} want a handful, not one per corridor")

    path = plots / "generator_investment_capacity_by_node.html"
    if path.exists():
        data, layout = _parse(path)
        categories = len(data[0]["x"]) if data else 0
        print(
            f"{'investment by node':22} {categories:>4} x-categories"
            f" | period dropdown: {_buttons(layout)}"
        )
        print(f"{'':22} want one per node, not per (period, node)")

    path = plots / "generation_mix.html"
    if path.exists():
        _, layout = _parse(path)
        print(f"{'generation mix':22} y-axis: {layout['yaxis']['title']}")
        print(f"{'':22} want TWh at European scale, GWh on test")

    if dispatch:
        data, layout = _parse(dispatch[0])
        names = {t["name"] for t in data}
        anchors = {a.get("xanchor") for a in layout.get("annotations", [])}
        print(f"{'dispatch sample':22} {dispatch[0].name}")
        print(f"{'':22} series: {len(names)} | season labels anchored: {anchors}")
        print(f"{'':22} want 'center' (labels sit over their span)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for argument in sys.argv[1:]:
        report(Path(argument))
