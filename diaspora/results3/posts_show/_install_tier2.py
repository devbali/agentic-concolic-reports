#!/usr/bin/env python3
"""Install TIER 2 into coverage_assumptions.py with the gate's verdicts applied.

Rule T3: only PASS ships. Every other verdict — FAIL, ERROR, NOT-COMPARABLE,
NOT-TESTABLE — means the class has no gate evidence, so the class is WITHDRAWN
WHOLE (instances included) and its verdict is written into the file beside it.

usage: _install_tier2.py <probe_results.json>
"""
import json, os, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_tier2_probe_results_shipped.json")
CA = os.path.join(HERE, "coverage_assumptions.py")
PATCH = "/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/tier2_final.py"

results = json.load(open(RES))
# the class string is carried in each declared entry's description
decl = {(d["expr_a"], d["expr_b"]): d["description"].split(": ", 1)[1]
        for d in json.load(open(os.path.join(HERE, "_tier2_declared.json")))}

by_class = {}
for r in results:
    cls = r.get("class") or ""
    if ": " in cls:
        cls = cls.split(": ", 1)[1]
    if not cls:
        cls = decl.get((r.get("expr"), r.get("expr_b")), "")
    by_class[cls] = (r["verdict"], (r.get("detail") or "")[:150])

verdicts = Counter(v for v, _ in by_class.values())
passed = sorted(c for c, (v, _) in by_class.items() if v == "PASS")
withdrawn = sorted((c, v, d) for c, (v, d) in by_class.items() if v != "PASS")

print("=== GATE VERDICTS BY CLASS ===")
for v, n in verdicts.most_common():
    print(f"  {v:<16} {n}")
print(f"\nclasses PASSED (ship)   : {len(passed)}")
print(f"classes WITHDRAWN       : {len(withdrawn)}")
for c, v, d in withdrawn[:20]:
    print(f"   {v:<15} {c[:88]}")
    if d:
        print(f"       {d[:120]}")

# how many PAIRS survive
after = json.load(open(os.path.join(HERE, "_tier2_after_wf.json")))
cls_counts = {" || ".join(k): n for k, n in after["classes"]}
pairs_pass = sum(cls_counts.get(c, 0) for c in passed)
pairs_wd = sum(cls_counts.get(c, 0) for c, _, _ in withdrawn)
print(f"\npairs SHIPPING          : {pairs_pass}")
print(f"pairs withdrawn by gate : {pairs_wd}")

block = open(PATCH).read()
wd_lit = "_TIER2_WITHDRAWN = frozenset({\n" + "".join(
    f"    # {v}: {d}\n    {c!r},\n" for c, v, d in withdrawn) + "})\n"
block = block.replace("# =====================================================================\n_PX_ATTR_SUFFIXES",
                      "# =====================================================================\n"
                      "# Classes the gate did NOT pass, withdrawn WHOLE with their verdicts.\n"
                      + wd_lit + "\n_PX_ATTR_SUFFIXES", 1)

src = open(CA).read()
assert "_tier2_disjoint_reps" not in src, "tier2 already installed"
anchor = "def build(runs=None) -> AssumptionSet:"
assert anchor in src
src = src.replace(anchor, block + "\n\n" + anchor, 1)

wire_anchor = """    for ia in _tier6_len_gates_row_attr(all_exprs):
        aset.add(ia)
"""
assert wire_anchor in src
src = src.replace(wire_anchor, wire_anchor + """
    # TIER 2 runs LAST: it dedupes against every pair the earlier tiers already
    # declared, so it only ever ADDS cross-rep pairs none of them covered.
    _already = {frozenset((_a.expr_a, _a.expr_b)) for _a in aset.assumptions
                if isinstance(_a, IndependenceAssumption)}
    for ia in _tier2_disjoint_reps(all_exprs, _already):
        aset.add(ia)
""", 1)
open(CA, "w").write(src)
print(f"\ninstalled into {CA}")
json.dump({"passed": passed, "withdrawn": [list(x) for x in withdrawn],
           "verdicts": dict(verdicts), "pairs_pass": pairs_pass,
           "pairs_withdrawn": pairs_wd},
          open(os.path.join(HERE, "_tier2_install.json"), "w"), indent=1)
