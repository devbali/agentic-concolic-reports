#!/usr/bin/env python3
"""Direct count: first_2_not_found / first_2_closed_account / find_by_2
events in the current 7673-dump corpus."""
import glob
import json
import os

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

targets = [
    "first_2_not_found",
    "first_2_closed_account",
    "find_by_2_not_found",
    "find_by_1_not_found",
    "first_1_not_found",
    "first_1_closed_account",
    "via_user_closed_account",
]
counts = {t: 0 for t in targets}
by_taken = {t: {"T": 0, "F": 0} for t in targets}
n = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    n += 1
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        for t in targets:
            if t in expr:
                counts[t] += 1
                by_taken[t]["T" if ev.get("taken") else "F"] += 1
print(f"dumps: {n}")
for t in targets:
    print(f"  {t}: total={counts[t]} T={by_taken[t]['T']} F={by_taken[t]['F']}")

# which dumps have first_2?
first2_dumps = []
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    txt = json.dumps(raw)
    if "first_2_not_found" in txt:
        first2_dumps.append(os.path.basename(p))
print(f"\ndumps containing first_2_not_found: {len(first2_dumps)}")
for d in first2_dumps[:10]:
    print("  ", d)