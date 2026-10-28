#!/usr/bin/env python3
"""Extract the pairs the GATE refused from the engine section's own output, in
the shape `project_confinement(withdrawn=...)` takes. No hand-editing."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "coverage_summary.json")))
w = S.get("confinement_withdrawn_by_gate") or []
if not w:
    sec = (S.get("completion") or {}).get("assumptions") or {}
    w = sec.get("confinement_withdrawn") or []
pairs = []
for x in w:
    if isinstance(x, (list, tuple)) and len(x) >= 2:
        pairs.append(sorted([str(x[0]), str(x[1])]))
    elif isinstance(x, dict):
        a, b = x.get("expr_a"), x.get("expr_b")
        if a and b:
            pairs.append(sorted([a, b]))
json.dump(pairs, open(os.path.join(HERE, "_withdrawn_pairs.json"), "w"), indent=1)
print(f"gate-withdrawn pairs: {len(pairs)} -> _withdrawn_pairs.json")
