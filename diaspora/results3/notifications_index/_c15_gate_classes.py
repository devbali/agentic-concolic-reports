#!/usr/bin/env python3
"""C15 — one representative per §16e CONJUNCTION-FORECLOSURE class, as the
assumption gate's `--declared` input.

A class is a foreclosed MEMBER: the same decision removed from the path under
a family of gate conjunctions is one app behaviour, and the gate's derived
test (`_test_conjunction_foreclosure`) costs one JRuby replay per row. The
representative is the NARROWEST prefix of the class — foreclosure under a
prefix implies foreclosure under every extension of it, so the narrowest is
the strongest claim of the family and the one a probe is most likely to
REALISE (a wider conjunction is more literals to seed and more chances of the
realised-value rule firing).

  usage: C15_SUMMARY=<pass json> [C15_CLASSES_OUT=...] python3 _c15_gate_classes.py
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SUM = os.environ.get("C15_SUMMARY", os.path.join(HERE, "_cov_C15_C15R2.json"))
OUT = os.environ.get("C15_CLASSES_OUT", os.path.join(HERE, "_c15_gate_classes.json"))

s = json.load(open(SUM))
rows = [a for a in (s.get("assumptions") or [])
        if a.get("type") == "ConjunctionForeclosureAssumption"]
print(f"{os.path.basename(SUM)}: {len(rows)} ConjunctionForeclosureAssumption row(s); "
      f"engine counts conj={s.get('conjunction_foreclosures')} "
      f"groups={s.get('conjunction_foreclosure_groups')}")

best = {}
seen = {}
for a in rows:
    d = a["expr"]
    seen[d] = seen.get(d, 0) + 1
    cur = best.get(d)
    if cur is None or len(a["gates"]) < len(cur["gates"]):
        best[d] = a
reps = [best[d] for d in sorted(best)]
json.dump(reps, open(OUT, "w"), indent=1)
print(f"classes (distinct foreclosed members): {len(reps)}")
w = {}
for a in reps:
    w[len(a["gates"])] = w.get(len(a["gates"]), 0) + 1
print("representative prefix widths: " + ", ".join(f"{k}:{v}" for k, v in sorted(w.items())))
for a in reps[:10]:
    print(f"   {seen[a['expr']]:4d} prefix(es)  width {len(a['gates'])}  {a['expr'][:90]}")
print(f"wrote {OUT}")
