#!/usr/bin/env python3
"""Inspect assoc_author_guid in dumps: values, PC texts, taken."""
import glob
import json
import os

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

n = 0
vals = {}
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))[:300]:
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    # symbolic_vars with assoc_author_guid
    for sv in raw.get("symbolic_vars", []):
        name = sv.get("name", "")
        if "assoc_author_guid" in name:
            vals[name] = sv.get("value")
    # events with assoc_author_guid
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        if "assoc_author_guid" in expr:
            print(f"EVENT: taken={ev.get('taken')} expr={expr[:120]!r}")
            n += 1
            if n >= 8:
                break
    if n >= 8:
        break

print("\nassoc_author_guid symbolic var values (first 10):")
for k, v in list(vals.items())[:10]:
    print(f"  {k} = {v!r}")