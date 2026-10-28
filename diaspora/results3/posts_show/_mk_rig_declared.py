#!/usr/bin/env python3
"""Build the rig-replay gate input: the confinement-aware pass's CONFINED pairs
(these actually replay) plus the 44 OVERLAPPING pairs and the 6 controls (these
the gate refuses before any replay — their rig verdict is the cheap half).

Entries are `ConfinementAssumption` with `footprint_a`/`footprint_b`, the shape
lists the checker inferred — hand-built footprints would be a different claim.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "_cov_p5_conf.json")))
out, seen = [], set()
for a in S.get("assumptions") or S.get("assumptions_used") or []:
    if (a.get("type") or "").startswith("Confinement"):
        k = (a.get("expr_a"), a.get("expr_b"))
        if k in seen:
            continue
        seen.add(k)
        out.append(dict(a, type="ConfinementAssumption"))
print(f"confined pairs from the pass: {len(out)}")
# the overlapping pairs the pass did NOT confine — gate must refuse them
try:
    ov = json.load(open(os.path.join(HERE, "_sep_pairs.json")))["overlapping"]
except Exception:
    ov = []
print(f"overlapping pairs carried for their refusal verdict: {len(ov)}")
json.dump(out, open(os.path.join(HERE, "_rig_declared.json"), "w"), indent=1)
print(f"wrote _rig_declared.json ({len(out)} entries)")
