#!/usr/bin/env python3
"""Gap-set delta between two coverage checkpoints, keyed by the DEMAND SET.

  usage: _c16_gapdelta.py <before.ckpt.jsonl> <after.ckpt.jsonl>

A set has a gap iff its record carries a witness. Both checkpoints must be
written by passes over the SAME demand universe (the key sets are printed and
compared, so a universe that moved is visible rather than assumed).
"""
import json, sys


def load(p):
    sets, gaps, wit = set(), set(), {}
    for i, line in enumerate(open(p)):
        if i == 0:
            continue
        r = json.loads(line); v = r.get("v") or {}
        sets.add(r["k"])
        if v.get("combos"):
            gaps.add(r["k"])
            wit[r["k"]] = [tuple(sorted((e, bool(o)) for e, o in c))
                           for c in v["combos"]]
    return sets, gaps, wit


(sa, ga, wa), (sb, gb, wb) = load(sys.argv[1]), load(sys.argv[2])
print(f"BEFORE {sys.argv[1]}: demand sets {len(sa)}  gap-sets {len(ga)}")
print(f"AFTER  {sys.argv[2]}: demand sets {len(sb)}  gap-sets {len(gb)}")
print(f"demand universe: shared {len(sa & sb)}  only-before {len(sa - sb)}  "
      f"only-after {len(sb - sa)}")
closed = ga - gb
newly = gb - ga
still = ga & gb
print(f"CLOSED {len(closed)}   NEWLY GAPPED {len(newly)}   STILL GAPPED {len(still)}")
same = sum(1 for k in still if wa.get(k) == wb.get(k))
print(f"  of the still-gapped, witness leaf UNCHANGED {same}, "
      f"replaced by a different leaf {len(still) - same}")
wla = {c for v in wa.values() for c in v}
wlb = {c for v in wb.values() for c in v}
print(f"distinct witness leaves: before {len(wla)}  after {len(wlb)}  "
      f"shared {len(wla & wlb)}")
