#!/usr/bin/env python3
"""Trace source_location of the '!= StringVal('')' and '== '''' events for
assoc_author_guid / first_2_guid — find the app code recording them."""
import glob
import json
import os
import collections

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

loc_neq = collections.Counter()
loc_eq = collections.Counter()
n = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    n += 1
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        if "guid" not in expr and "== ''" not in expr and "!= StringVal('')" not in expr:
            continue
        src = ev.get("source_location", "")
        if "assoc_author_guid" in expr:
            if "!= StringVal('')" in expr:
                loc_neq[("%s | %s" % (src, ev.get("taken")))] += 1
            elif "== ''" in expr:
                loc_eq[("%s | %s" % (src, ev.get("taken")))] += 1

print("runs: %d" % n)
print("\n=== assoc_author_guid != '' events by source_location ===")
for k, c in loc_neq.most_common(15):
    print("  %6d  %s" % (c, k))
print("\n=== assoc_author_guid == '' events by source_location ===")
for k, c in loc_eq.most_common(15):
    print("  %6d  %s" % (c, k))