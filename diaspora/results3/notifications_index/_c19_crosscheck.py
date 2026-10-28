#!/usr/bin/env python3
"""C19 — cross-check the engine's §16f inferences against the C18 measurement.

`_c18_minimal_cond.json` was computed OUTSIDE the engine (`_c18_minimal_cond.py`,
campaign §31.5): for every OPEN leaf and its never-evaluated member, the minimal
subset of the LEAF'S OWN literals under which the member is foreclosed
(A > 0, B = 0), searched to width 3 over per-DUMP bitsets.

The engine's §16f search is the same predicate with two deliberate differences,
both stated in DISCIPLINE §16f:

  * it draws C from the literals fixed EARLIER IN THE WALK, not from the whole
    cube — that is what makes the leaf a function of its prefix;
  * it counts A over PROFILES, not dumps, so the A numbers differ by the
    profile collapse while the A > 0 / B = 0 partition is identical.

So the agreement to check is on the (member, C) CLASSES, and any C the
artefact found that the engine did not must be explainable by the walk-order
restriction. This prints both directions.

  usage: python3 _c19_crosscheck.py <coverage summary json>
"""
import json, os, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SUM = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cov_C19_C19R1.json")

s = json.load(open(SUM))
art = json.load(open(os.path.join(HERE, "_c18_minimal_cond.json")))

eng = set()
eng_a = {}
for it in s.get("subconjunction_foreclosure_list") or ():
    key = (it["member"], tuple((g, o == "taken") for g, o in it["conditioning"]))
    eng.add(key)
    eng_a[key] = it["A"]

ref = set()
ref_a = {}
ref_rows = 0
for r in art:
    if not r.get("minimal_conditioning"):
        continue
    ref_rows += 1
    key = (r["member"], tuple((e, bool(o)) for e, o in r["minimal_conditioning"]))
    ref.add(key)
    ref_a[key] = r["A"]

print(f"engine  §16f (C, d) classes            : {len(eng)}")
print(f"        over conditioning sets         : "
      f"{s.get('subconjunction_foreclosure_conditions')}  "
      f"(applied {s.get('subconjunction_foreclosures')}, "
      f"W={s.get('subconjunction_foreclosure_width')})")
print(f"artefact _c18_minimal_cond.json rows   : {ref_rows} "
      f"({len(ref)} distinct (C, d) classes, over "
      f"{len({r['set'] for r in art if r.get('minimal_conditioning')})} sets)")
print()
both = eng & ref
print(f"AGREE   (same member, same minimal C)  : {len(both)} / {len(ref)} "
      f"of the artefact's classes")
for k in sorted(both):
    print(f"    A engine(profiles)={eng_a[k]:>7}  artefact(dumps)={ref_a[k]:>7}  "
          f"|C|={len(k[1])}  {k[0][:70]}")
print()
only_ref = ref - eng
print(f"ARTEFACT ONLY                          : {len(only_ref)}")
by_member = Counter(m for m, _c in only_ref)
for m, n in by_member.most_common():
    print(f"    x{n}  {m[:90]}")
    for _m, c in sorted(x for x in only_ref if x[0] == m)[:1]:
        for e, o in c:
            print(f"          cond {o}  {e[:95]}")
print()
only_eng = eng - ref
print(f"ENGINE ONLY (new, outside the open set): {len(only_eng)}")
for m, n in Counter(m for m, _c in only_eng).most_common(12):
    print(f"    x{n}  {m[:90]}")
print()
# same member, DIFFERENT minimal C — the walk-order restriction's signature
mref = {m for m, _c in ref}
meng = {m for m, _c in eng}
print(f"members reached by BOTH                : {len(mref & meng)} / {len(mref)}")
print(f"members the artefact found and the engine did NOT reach at all: "
      f"{len(mref - meng)}")
for m in sorted(mref - meng):
    print(f"    {m[:100]}")
print("\nC19-CROSSCHECK-DONE")
