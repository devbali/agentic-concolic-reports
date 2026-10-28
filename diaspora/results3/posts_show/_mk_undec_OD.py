#!/usr/bin/env python3
"""Write the CURRENT undecidable-decision list (OD0911 census) in the shape
_oneflip_seeds.py reads, so class (b) is tested on tonight's 21, not on the
79 of the pre-gate-aware census."""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
# The census on the CURRENT snapshot is the preferred source; when it has not
# been able to run (the 2026-09-11 memory constraint) fall back to the
# OR0911-snapshot reconciliation, which measured the same quantity one snapshot
# earlier — 23 there, 21 on OD0911 — and SAY which one this is.
_pp = os.path.join(HERE, "_parts_OD0911.json")
if os.path.exists(_pp):
    und = json.load(open(_pp))["undecidable_decisions"]
    print("SOURCE: _parts_OD0911.json (the census on the CURRENT snapshot)")
else:
    und = json.load(open(os.path.join(HERE, "_and_reconcile.json")))["undecidable_decisions"]
    print("SOURCE: _and_reconcile.json (the OR0911 snapshot — 23 undecidable "
          "there, 21 on OD0911; the census on the current snapshot could not "
          "be run under the 4G cage)")
def is_gate(e):
    return (e.startswith("(len(") or e.startswith("(Length(")
            or "_not_found" in e or "_public" in e
            or re.match(r'^\(([A-Za-z_][A-Za-z0-9_]*) != \1\)$', e.strip()))
gates = [e for e in und if is_gate(e)]
addr = [e for e in und if not is_gate(e)]
print(f"UNDECIDABLE now: {len(und)}   gate-like/unsat (no matched context can exist): {len(gates)}"
      f"   ADDRESSABLE by a one-flip seed: {len(addr)}")
for e in und:
    print(f"   {'GATE ' if e in gates else 'ADDR '} {e[:110]}")
json.dump({"undecidable": und, "gates": gates, "addressable": addr},
          open(os.path.join(HERE, "_undecidable_kinds_OD.json"), "w"), indent=1)
print("wrote _undecidable_kinds_OD.json")
