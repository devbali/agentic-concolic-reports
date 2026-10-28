#!/usr/bin/env python3
"""C14 — append the CHECKER's own remaining witnesses to the enumerated batch.

Why both. The exact enumerator and the coverage checker are two instruments
over the same corpus and their remaining sets are largely DISJOINT here: of the
159 distinct witness leaves the M1 pass still reports over its 184 gap-sets,
only 16 appear among the enumerator's 10 319 remaining assignments. The
enumerator is the one that removes the one-witness-per-set ceiling; the checker
is the one that writes COMPLETE/MISSING. Driving only one of them would leave
the other's backlog untouched, so the batch is the UNION, stated as such.

A checker witness has no separate gate prefix to hand (§25.2: the combo is
built gates-first, gates and members interleaved in one object), so its `pre`
is the whole cube — which makes the base rule fall back to exactly C13's
whole-cube match for these, and the enumerator's leaf groups keep the
gate-prefix rule.
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
CKPT = os.environ.get("C14_CKPT", os.path.join(HERE, "_cov_c13_M1.ckpt.jsonl"))
GAPS = os.environ.get("C14_GAPS", os.path.join(HERE, "_c14_gaps.json"))

gaps = json.load(open(GAPS))
have = {tuple(sorted((e, bool(o)) for e, o in g["cube"])) for g in gaps}
maxg = max(g["group"] for g in gaps)
f = open(CKPT); json.loads(f.readline())
seen, added, dup, nsets = set(), 0, 0, 0
for line in f:
    r = json.loads(line); v = r["v"]
    for c in (v.get("combos") or []):
        cube = sorted({(e, bool(t)) for e, t in c})
        key = tuple(cube)
        if key in seen:
            continue
        seen.add(key)
        if key in have:
            dup += 1
            continue
        maxg += 1
        gaps.append({
            "id": f"w{added:05d}", "set": r["k"], "group": maxg,
            "set_capped": True, "width": len(cube), "surv": None,
            "reachable": None, "checker_witness": True,
            "pre": {e: o for e, o in cube},
            "cube": [[e, o] for e, o in cube], "model": {},
        })
        added += 1
print(f"checker witnesses distinct : {len(seen)}")
print(f"  already in the enumerated batch : {dup}")
print(f"  APPENDED                        : {added}")
print(f"batch total cubes                 : {len(gaps)}  groups {maxg+1}")
json.dump(gaps, open(GAPS, "w"))
print(f"C14-ADD-WITNESSES-DONE {GAPS} ({os.path.getsize(GAPS)/1e6:.1f} MB)")
