#!/usr/bin/env python3
"""C16 — append the CHECKER's own §16e witnesses to the enumerated batch.

Same rule as `_c14_add_witnesses.py` (§27.3): the exact enumerator and the
coverage checker are two instruments over one corpus and their residues are
NOT the same object — the enumerator's covered test is "a run's evaluated
members are EXACTLY the leaf's survivors", the checker's is "a run blocks a
closed prefix" — so the batch is the UNION, stated as such. The verdict line
COMPLETE/MISSING is the CHECKER's, so its own witnesses must be driven too.

The witnesses read here come from a pass run WITH `FORECLOSURE_CONJUNCTIONS=1`,
so each cube is already §16e-coarsened: the members its gate conjunction
forecloses are not in it.

A checker witness has no separate gate prefix to hand (§25.2: the combo is one
gates-first object), so its `pre` is the whole cube and the base rule falls
back to C13's whole-cube match for exactly those.
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
CKPT = os.environ.get("C16_CKPT", os.path.join(HERE, "_cov_c15_C15R2.ckpt.jsonl"))
GAPS = os.environ.get("C14_GAPS", os.path.join(HERE, "_c16_gaps.json"))

gaps = json.load(open(GAPS))
have = {tuple(sorted((e, bool(o)) for e, o in g["cube"])) for g in gaps}
maxg = max(g["group"] for g in gaps) if gaps else -1
f = open(CKPT); json.loads(f.readline())
seen, added, dup = set(), 0, 0
gapsets = set()
for line in f:
    r = json.loads(line); v = r["v"]
    combos = v.get("combos") or []
    if combos:
        gapsets.add(r["k"])
    for c in combos:
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
            "id": f"w{added:05d}", "set": r["k"], "sdig": r["k"], "group": maxg,
            "set_capped": True, "width": len(cube), "surv": None,
            "reachable": None, "checker_witness": True,
            "a": -1, "cf": [], "unmatched": False,
            "pre": {e: o for e, o in cube},
            "cube": [[e, o] for e, o in cube], "model": {},
        })
        added += 1
print(f"checker gap-sets in {os.path.basename(CKPT)} : {len(gapsets)}")
print(f"checker witnesses distinct : {len(seen)}")
print(f"  already in the enumerated batch : {dup}")
print(f"  APPENDED                        : {added}")
print(f"batch total cubes                 : {len(gaps)}  groups {maxg+1}")
json.dump(gaps, open(GAPS, "w"))
print(f"C16-ADD-WITNESSES-DONE {GAPS} ({os.path.getsize(GAPS)/1e6:.1f} MB)")
