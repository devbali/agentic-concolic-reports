#!/usr/bin/env python3
"""Inspect the raw structure of a couple of dumps to find the right keys."""
import glob
import json
import os

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
dumps = sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))

for p in dumps[:3]:
    raw = json.load(open(p))
    print(f"=== {os.path.basename(p)} keys: {list(raw.keys())[:10]}")
    # find a list of path conditions
    for k, v in raw.items():
        if isinstance(v, list) and v:
            print(f"  {k}: list[{len(v)}] first item type {type(v[0]).__name__}")
            print(f"    first item: {str(v[0])[:300]}")
            break
    print()

# Now search full text for 'records' or 'len(' occurrences across a few dumps
import re
found = {}
for p in dumps:
    txt = open(p).read()
    for m in re.finditer(r"records_?\d*|to_a_?\d*", txt):
        s = txt[max(0, m.start()-40):m.end()+40]
        found.setdefault(m.group(0), set()).add(s)
    if len(found) > 8:
        break

print("=== records/to_a text shapes found in raw dumps ===")
for k, samples in list(found.items())[:10]:
    print(f"--- {k} ---")
    for s in list(samples)[:2]:
        print(f"   ...{s}...")