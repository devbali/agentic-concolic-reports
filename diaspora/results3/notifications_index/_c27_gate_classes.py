#!/usr/bin/env python3
"""C27 — one gate-test representative per §16g (C, d) WELL-FOUNDED DROP class.

The §16g coverage pass emits every applied drop in `wellfounded_drop_list`
(capped at the engine's report cap). Each row is a (conditioning set C,
member d) pair with its A. §16g classes reach the gate as the SAME
`SubconjunctionForeclosureAssumption` the §16f gate test already reads
(DISCIPLINE §16g, "The gate test — the §16f probe, unchanged"), marked
`wellfounded: True` / `section: "16g"` so the report can separate the claims.

One representative per DISTINCT (member, C) — that is the class, and the
gate's own dedup key is (type, expr, prefix), so no collapsing beyond that.

  usage: python3 _c27_gate_classes.py <summary.json> <out.json>
"""
import json, os, sys

SUM, OUT = sys.argv[1], sys.argv[2]
s = json.load(open(SUM))
rows = s.get("wellfounded_drop_list") or []
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
        "gates": cond,
        "conditioning": cond,
        "matching_profiles": it.get("A"),
        "inferred": True,
        "wellfounded": True,
        "section": "16g",
        "description": (f"Well-founded drop (inferred, §16g, |C|="
                        f"{len(cond)}): no run matching this conjunction "
                        f"evaluates {it['member']}"),
    })

json.dump(classes, open(OUT, "w"), indent=1)
print(f"{len(rows)} applied rows -> {len(classes)} distinct (C, d) class(es) "
      f"written to {os.path.basename(OUT)}")
for i, c in enumerate(classes):
    print(f"  [{i:02d}] |C|={len(c['gates'])}  A={c['matching_profiles']}  {c['expr'][:88]}")
print("C27-GATE-CLASSES-DONE")
