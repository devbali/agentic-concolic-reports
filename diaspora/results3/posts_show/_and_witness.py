#!/usr/bin/env python3
"""Is the one CONFINED pair AND-shared? The 2x2, straight from the corpus.

A = findpublic_like_1_text_empty == True
B = findpublic_reshare_1_text_empty == True

AND-shared means: a shape present ONLY in the both-on cell — absent when either
is on alone and absent when neither is. That would be interaction, and
confinement would be licensing it: a BUG. OR-monotone means every shared shape
also appears under at least one single, which is what the refinement permits.
"""
import json, os, sys
from collections import defaultdict
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, ".")
from concolic_engine.assumptions import call_shape, shape_str
from coverage_report import canonicalize_ordinals

A, B = json.load(open("_and_suspect.json"))
files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
cell = defaultdict(set); n = defaultdict(int)
for p in files:
    try: d = json.load(open(p))
    except Exception: continue
    canonicalize_ordinals(d)
    out = defaultdict(set)
    shapes = set()
    for ev in d.get("events") or ():
        t = ev.get("type")
        if t == "path_condition":
            out[str(ev.get("expr",""))].add(bool(ev.get("taken")))
        elif t == "symbolic_call" and ev.get("result_name"):
            shapes.add(shape_str(call_shape(ev.get("target"), ev.get("note"), ev.get("args") or {})))
    oa, ob = out.get(A), out.get(B)
    if not oa or not ob or len(oa) != 1 or len(ob) != 1:
        continue
    k = (next(iter(oa)), next(iter(ob)))
    cell[k] |= shapes; n[k] += 1
    del d
print(f"A = {A}")
print(f"B = {B}\n")
for k in ((False,False),(True,False),(False,True),(True,True)):
    print(f"  cell A={int(k[0])} B={int(k[1])}: runs={n[k]:6d} shapes={len(cell[k])}")
both = cell[(True,True)]
singles = cell[(True,False)] | cell[(False,True)] | cell[(False,False)]
only_both = both - singles
print(f"\nshapes present ONLY with BOTH on (AND-shared): {len(only_both)}")
for s in sorted(only_both)[:10]:
    print(f"    {s[:110]}")
print("\nVERDICT:", "AND-SHARED -> confinement is a BUG here" if only_both
      else "no AND-shared shape -> OR-monotone, confinement is CORRECT")
