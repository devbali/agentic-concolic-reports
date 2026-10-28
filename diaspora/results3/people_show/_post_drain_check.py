#!/usr/bin/env python3
"""Post-drain-campaign analysis: did the ==15 side get witnessed?

1. Any dump with `records_2_rows == 15` or `records_4_rows == 15` taken:true?
2. What are the co-minted data vars in such dumps (PD/NSFW/guid/handles)?
3. Reconstruct the Q2==15 witness coverage vs the 64 missing demands.
"""
import glob
import json
import os
import re

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

REC2_15 = re.compile(r"len\(SYM_RESULT_ActiveRecord__Relation_records_2_rows\) == 15")
REC4_15 = re.compile(r"len\(SYM_RESULT_ActiveRecord__Relation_records_4_rows\) == 15")

witnesses = []
n_dumps = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    n_dumps += 1
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        taken = ev.get("taken")
        if (REC2_15.search(expr) or REC4_15.search(expr)) and taken:
            witnesses.append((os.path.basename(p), expr[:100]))

print(f"dumps: {n_dumps}")
print(f"==15 TAKEN:TRUE witnesses: {len(witnesses)}")
for w in witnesses[:20]:
    print("  ", w)
if not witnesses:
    # report the taken:false sighting count (the !=15 side)
    f2 = f4 = 0
    for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        for ev in raw.get("events", []):
            expr = str(ev.get("expr", ""))
            if REC2_15.search(expr):
                f2 += 1
            if REC4_15.search(expr):
                f4 += 1
    print(f"records_2_rows==15 expr sightings (taken:false side): {f2}")
    print(f"records_4_rows==15 expr sightings (taken:false side): {f4}")

# also: max stream ordinals per run in the new corpus
ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
maxo = 0
dist = {}
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    ords = set(int(m.group(1)) for m in ROW_RE.finditer(json.dumps(raw)))
    dist[len(ords)] = dist.get(len(ords), 0) + 1
    maxo = max(maxo, len(ords))
print(f"\nmax stream ordinals per run: {maxo}; distribution: {dist}")