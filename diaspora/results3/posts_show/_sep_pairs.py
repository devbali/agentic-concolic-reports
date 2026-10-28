#!/usr/bin/env python3
"""Separable / overlapping / undecidable, over the 1 733 tier-2 candidates AND
over every co-evaluated pair — with named examples of the OVERLAPPING ones,
which are real dependence the flip-both probe was blind to."""
import json, os, re
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
F = json.load(open(os.path.join(HERE, "_footprints.json")))
FP = {e: int(m) for e, m in zip(F["exprs"], F["footprint"])}
CTX = {e: c for e, c in zip(F["exprs"], F["contexts"])}
dec = {e for e in FP if CTX.get(e, 0) > 0}

cand = [tuple(x[:2]) for x in json.load(open(os.path.join(HERE, "_tier2_after_wf.json")))["kept"]]
FAM = [(re.compile(r"_[0-9a-f]{8}(?![0-9a-f])"), "_<hash>"), (re.compile(r"_[0-9]+(?![0-9])"), "_<n>")]
def fam(k):
    for rx, r in FAM:
        k = rx.sub(r, k)
    return k

def verdict(a, b):
    if a not in dec or b not in dec:
        return "undecidable"
    return "overlapping" if (FP[a] & FP[b]) else "separable"

c = Counter(); overlaps = []
for a, b in cand:
    v = verdict(a, b)
    c[v] += 1
    if v == "overlapping":
        overlaps.append((a, b, (FP[a] & FP[b]).bit_count()))
print("=== TIER-2 CANDIDATES (1733) UNDER SEPARABILITY ===")
for k, v in c.most_common():
    print(f"  {k:<14}{v}")
print(f"\nOVERLAPPING pairs — real dependence the flip-both probe passed "
      f"({len(overlaps)}); top by shared-shape count:")
overlaps.sort(key=lambda x: -x[2])
for a, b, n in overlaps[:12]:
    print(f"  shared_shapes={n:>3}")
    print(f"     A: {a[:100]}")
    print(f"     B: {b[:100]}")
oc = Counter(tuple(sorted((fam(a), fam(b)))) for a, b, _ in overlaps)
print(f"\noverlapping by rep-family pair ({len(oc)} classes):")
for (fa, fb), n in oc.most_common(10):
    print(f"  {n:5d}  {fa.split('__')[-1][:44]}  x  {fb.split('__')[-1][:44]}")
json.dump({"counts": dict(c),
           "overlapping": [[a, b, n] for a, b, n in overlaps[:400]],
           "overlap_classes": [[list(k), v] for k, v in oc.most_common()]},
          open(os.path.join(HERE, "_sep_pairs.json"), "w"), indent=1)
print("\nwrote _sep_pairs.json")
