#!/usr/bin/env python3
"""Sets with a GAP, from a coverage checkpoint: one record per demand set,
a set has a gap iff its record carries a witness.  usage: _c15_gapcensus.py <ckpt...>"""
import json, sys
for p in sys.argv[1:]:
    n = g = w = 0
    for i, line in enumerate(open(p)):
        if i == 0:
            continue
        r = json.loads(line)
        v = r.get("v") or {}
        n += 1
        if v.get("combos"):
            g += 1
            w += len(v["combos"])
    print(f"{p}: demand sets recorded {n}   SETS WITH A GAP {g}   witnesses {w}")
