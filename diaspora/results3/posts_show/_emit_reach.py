#!/usr/bin/env python3
"""§76.1 — THE EMITTER'S REACH, measured on p12's own artefacts.

Joins the p12 emit (`_enum_emit_ORDEMAND.json`, EMIT_MAX_PER_SET=8) to the
census it was emitted from (`_confinement_census_OR0911.json`, the same 1 677
OR-refined parts in the same order) and asks, per part: how much of that part's
remaining did the 8 cubes it was allowed actually carry?
Read-only; runs under a 900 M cap (below the 1 GB invariant threshold).
"""
import json, os
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
E = json.load(open(os.path.join(HERE, "_enum_emit_ORDEMAND.json")))
st = E["emit_stats"]
rem_total = int(E["remaining_total"])
cubes_of, mass_of = Counter(), Counter()
for it in E["missing"]:
    cubes_of[it["clique"]] += 1
del E
C = json.load(open(os.path.join(HERE, "_confinement_census_OR0911.json")))
per = C["census"]["16c"]["per_clique"]
print(f"census OR0911: sets={C['census']['16c']['cliques']} "
      f"remaining={C['census']['16c']['remaining']}")
print(f"emit: cubes={st['cubes']} mass={st['mass']} of remaining={rem_total} "
      f"({100.0*st['mass']/rem_total:.2f} %)")
print(f"emit stats: zero_pieces={st['zero']} capped_sets={st['capped_sets']} "
      f"region_bound={st['region_bound']} no_model={st['no_model']} "
      f"unreach_skipped={st['unreach_skipped']} mismatch={st['mismatch']}")
print(f"  -> EMIT_MAX_PER_SET was 8; {st['capped_sets']} of {len(per)} parts "
      f"({100.0*st['capped_sets']/len(per):.1f} %) hit that cap")
rows = []
for i, p in enumerate(per):
    rem = int(p["sat"]) - int(p["covered"])
    rows.append((rem, i, p["width"], cubes_of.get(i, 0), p["leaf_groups"]))
rows.sort(reverse=True)
tot = sum(r[0] for r in rows)
print(f"\nper-part remaining: total {tot} over {len(rows)} parts; "
      f"mean {tot//max(1,len(rows))}, median {sorted(r[0] for r in rows)[len(rows)//2]}")
for k in (1, 5, 10, 25, 50, 100, 250, 500, 1000):
    if k <= len(rows):
        s = sum(r[0] for r in rows[:k])
        print(f"  top {k:>5} parts: {s:>12}  {100.0*s/max(tot,1):6.2f} %")
print("\nTOP PARTS: remaining vs the cubes the cap allowed")
print(f"  {'part':>6} {'width':>5} {'remaining':>12} {'cubes':>6} {'leaf_groups':>11}")
for rem, i, w, nc, lg in rows[:15]:
    print(f"  {i:>6} {w:>5} {rem:>12} {nc:>6} {lg:>11}")
nz = sum(1 for r in rows if r[0] == 0)
print(f"\nparts with remaining==0: {nz}; parts that got NO cube: "
      f"{sum(1 for r in rows if r[3]==0)}")
wid = Counter()
widm = Counter()
for rem, i, w, nc, lg in rows:
    wid[w] += 1; widm[w] += rem
print("\nwidth: parts / remaining mass / share")
for w in sorted(wid, reverse=True):
    print(f"  {w:>3}: {wid[w]:>5} {widm[w]:>12}  {100.0*widm[w]/max(tot,1):6.2f} %")
print("\nEMIT REACH DONE")
