#!/usr/bin/env python3
"""P30 — one gate-test representative per §16f (C, d) CLASS (copied verbatim
from notifications_index/_c19_gate_classes.py, its model; nothing there was
touched).

The coverage pass emits every applied class in `subconjunction_foreclosure_list`
(capped at the engine's `_CONJ_REPORT_CAP`). The gate's own dedup key is
(type, expr, prefix), so two foreclosures of the same member under different
conditioning sets are two claims — but a probe costs one replay, so this
collapses the list to one representative per DISTINCT (member, C) and, when
`PER_MEMBER=1`, one per member (the narrowest C, which needs the fewest flips).

  usage: [PER_MEMBER=0|1] python3 _c19_gate_classes.py <summary.json> <out.json>
"""
import json, os, sys

SUM = sys.argv[1]
OUT = sys.argv[2]
PER_MEMBER = os.environ.get("PER_MEMBER", "1") == "1"

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
        "gates": cond,
        "conditioning": cond,
        "matching_profiles": it.get("A"),
        "inferred": True,
        "description": (f"Sub-conjunction foreclosure (inferred, §16f, width "
                        f"{len(cond)}): no run matching this conjunction "
                        f"evaluates {it['member']}"),
    })

if PER_MEMBER:
    best = {}
    for c in classes:
        m = c["expr"]
        if m not in best or len(c["gates"]) < len(best[m]["gates"]):
            best[m] = c
    classes = [best[m] for m in sorted(best)]

json.dump(classes, open(OUT, "w"), indent=1)
print(f"{len(rows)} applied rows -> {len(seen)} distinct (C, d) classes -> "
      f"{len(classes)} probe(s) written to {os.path.basename(OUT)}"
      + (" (one per MEMBER, narrowest C)" if PER_MEMBER else ""))
for c in classes:
    print(f"  |C|={len(c['gates'])}  A={c['matching_profiles']}  {c['expr'][:80]}")
print("C19-GATE-CLASSES-DONE")
