#!/usr/bin/env python3
"""C16 — does the §16e ENUMERATOR's per-set remainder agree with the §16e
COVERAGE PASS's gap-sets?

Joined on the CHECKER's own per-set key (`checkpoint.digest(group)` after
`restrict_foreclosures`), which `_c16_enum.py` now records as `sdig`.

The two instruments are NOT the same test (§27.3): the enumerator's covered
test is "a run's evaluated members of the set are EXACTLY the leaf's
survivors", the pass's is "a run blocks a closed prefix". They also do not
build the same universe — the pass applies §16c confinement and the census
does not — so this prints the universe overlap too, and every disagreement is
counted rather than assumed away.

  usage: _c16_setcheck.py <enum.json> <pass.ckpt.jsonl>
"""
import json, sys
from collections import Counter

enum = json.load(open(sys.argv[1]))
enum = enum.get("1", enum.get("0")) if "1" in enum or "0" in enum else enum
per = enum["per_clique"]
erem = {}
for p in per:
    d = p.get("sdig")
    if d is None:
        continue
    r = int(p["sat"]) - int(p["covered"])
    erem[d] = erem.get(d, 0) + r

gaps, allsets = set(), set()
for i, line in enumerate(open(sys.argv[2])):
    if i == 0:
        continue
    r = json.loads(line); v = r.get("v") or {}
    allsets.add(r["k"])
    if v.get("combos"):
        gaps.add(r["k"])

eset = set(erem)
epos = {k for k, v in erem.items() if v > 0}
print(f"ENUMERATOR demand sets {len(eset)}   with remaining>0: {len(epos)}   "
      f"total remaining cubes {sum(erem.values())}")
print(f"PASS       demand sets {len(allsets)}  gap-sets {len(gaps)}")
print(f"universe overlap: shared {len(eset & allsets)}   "
      f"enum-only {len(eset - allsets)}   pass-only {len(allsets - eset)}")
print()
print(f"the pass's {len(gaps)} GAP-SETS, against the enumerator:")
print(f"   present in the enumerator's universe : {len(gaps & eset)}")
print(f"   ... of them with remaining > 0       : {len(gaps & epos)}")
print(f"   ... of them with remaining == 0      : {len((gaps & eset) - epos)}")
print(f"   NOT in the enumerator's universe     : {len(gaps - eset)}")
print()
print(f"the enumerator's {len(epos)} sets with remaining > 0, against the pass:")
print(f"   the pass calls GAPPED   : {len(epos & gaps)}")
print(f"   the pass calls COVERED  : {len((epos & allsets) - gaps)}")
print(f"   not in the pass's universe: {len(epos - allsets)}")
h = Counter()
for k in gaps & epos:
    h[erem[k]] += 1
print("cubes remaining, over the gap-sets the enumerator also holds: " +
      ", ".join(f"{k}:{v}" for k, v in sorted(h.items())[:20]))
print(f"   their total cubes: {sum(erem[k] for k in gaps & epos)}")
json.dump({"enum_remaining_by_set": erem,
           "pass_gapsets": sorted(gaps),
           "pass_sets": sorted(allsets)}, open("_c16_setcheck.json", "w"))
print("wrote _c16_setcheck.json")
