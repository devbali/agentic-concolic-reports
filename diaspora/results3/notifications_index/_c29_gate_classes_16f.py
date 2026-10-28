#!/usr/bin/env python3
"""C29 — one gate-test representative per §16f (C, d) SUB-CONJUNCTION class,
the §16f twin of `_c27_gate_classes.py`.  usage: <summary.json> <out.json>"""
import json, os, sys
SUM, OUT = sys.argv[1], sys.argv[2]
s = json.load(open(SUM))
rows = s.get("subconjunction_foreclosure_list") or []
seen, classes = set(), []
for it in rows:
    cond = [[g, o] for g, o in it["conditioning"]]
    key = (it["member"], tuple(map(tuple, cond)))
    if key in seen:
        continue
    seen.add(key)
    classes.append({
        "type": "SubconjunctionForeclosureAssumption",
        "expr": it["member"],
        "prefix": " AND ".join(f"{g} :: {o}" for g, o in cond),
        "gates": cond, "conditioning": cond,
        "matching_profiles": it.get("A"), "inferred": True, "section": "16f",
        "description": (f"Sub-conjunction foreclosure (inferred, §16f, |C|="
                        f"{len(cond)}): no run matching this conjunction "
                        f"evaluates {it['member']}"),
    })
json.dump(classes, open(OUT, "w"), indent=1)
print(f"{len(rows)} applied rows -> {len(classes)} distinct (C, d) class(es) -> {os.path.basename(OUT)}")
for i, c in enumerate(classes):
    print(f"  [{i:02d}] |C|={len(c['gates'])}  A={c['matching_profiles']}  {c['expr'][:88]}")
print("C29-GATE-CLASSES-16F-DONE")
