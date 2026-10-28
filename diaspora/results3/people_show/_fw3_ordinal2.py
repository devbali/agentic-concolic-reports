#!/usr/bin/env python3
"""Verify the ordinal-lock hypothesis (fixed): is there ANY dump in the mixed
corpus that co-mints bare records_1 AND records_1_rows (same '1' ordinal) in a
single run? Uses the full var token incl. _rows suffix."""
import json, glob, re
from collections import Counter

full_re = re.compile(r"SYM_RESULT_ActiveRecord__Relation_(records_[0-9]+(?:_rows)?)\b")
co_same = 0
tot = 0
detail = Counter()
ex = None
for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json"):
    try: d = json.load(open(f))
    except: continue
    tot += 1
    names = set()
    for e in d.get("events",[]):
        if e.get("type")!="path_condition": continue
        for m in full_re.findall(e.get("expr","")):
            names.add(m)
    bare = {n for n in names if not n.endswith("_rows")}
    rows = {n for n in names if n.endswith("_rows")}
    same = bare & rows
    if same:
        co_same += 1
        detail[tuple(sorted(same))]+=1
        ex = ex or (f, sorted(same))

print(f"total dumps: {tot}")
print(f"dumps co-minting SAME-ordinal bare records_N AND records_N_rows: {co_same}")
# also show bare-only / rows-only ordinal overlap overall
bare_only = Counter(); rows_only = Counter()
for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json"):
    try: d=json.load(open(f))
    except: continue
    names=set()
    for e in d.get("events",[]):
        if e.get("type")!="path_condition": continue
        for m in full_re.findall(e.get("expr","")):
            names.add(m)
    for n in names:
        if n.endswith("_rows"): rows_only[n]+=1
        else: bare_only[n]+=1
print("\nbare records_N ordinal frequencies:")
for n,c in sorted(bare_only.items()): print(f"   {n}: {c}")
print("records_N_rows ordinal frequencies:")
for n,c in sorted(rows_only.items()): print(f"   {n}: {c}")
if ex:
    print("\nexample co-mint:", ex[0], ex[1])
else:
    print("\n*** NO dump co-mints same-ordinal bare records_N AND records_N_rows ***")