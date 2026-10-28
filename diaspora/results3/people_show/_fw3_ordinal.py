#!/usr/bin/env python3
"""Verify the ordinal-lock hypothesis: is there ANY dump in the mixed corpus
that co-mints bare records_1 AND records_1_rows (same '1' ordinal, one from
html presenter leg, one from mobile stream leg) in a single run?

If NO dump has {records_1 AND records_1_rows} together, then the missing
conjunction Not(records_1 != 0) ∧ records_1_rows>0 is unwitnessable purely
from the interceptor's per-run call-ordinal naming — a structural wall that
the dual-format approach does NOT break (it just renames rows to
records_3/4/5_rows).
"""
import json, glob, re
from collections import Counter

rows_ordinal_locked = Counter()
co_mint_same_ordinal = Counter()
co_mint_any = 0
total = 0
ex_any = None

for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json"):
    try: d = json.load(open(f))
    except: continue
    total += 1
    names = set()
    for e in d.get("events",[]):
        if e.get("type")!="path_condition": continue
        s = e.get("expr","")
        # bare records_N (no _rows suffix) and records_N_rows
        for m in re.findall(r"SYM_RESULT_ActiveRecord__Relation_(records_[0-9]+)(?:_rows)?", s):
            names.add(m)
    bare = {n for n in names if re.fullmatch(r"records_[0-9]+", n)}
    rows = {n for n in names if re.fullmatch(r"records_[0-9]+_rows", n)}
    # any dump with BOTH a bare records_1 and records_1_rows (same ordinal)?
    same = bare & rows
    if same:
        co_mint_same_ordinal[len(same)] += 1
        if ex_any is None: ex_any = (f, sorted(same))
    if bare and rows:
        co_mint_any += 1
    # record ordinals seen for records (bare) and records_rows separately
    for n in bare: rows_ordinal_locked[("bare", n)] += 1
    for n in rows: rows_ordinal_locked[("rows", n)] += 1

print(f"total dumps: {total}")
print(f"dumps co-minting ANY bare+rows: {co_mint_any}")
print(f"dumps co-minting same-ordinal bare & rows (e.g. records_1 AND records_1_rows):")
for k,v in co_mint_same_ordinal.items():
    print(f"   {k} same-ordinal pairs: {v} dumps")
print("\nordinal usage across corpus:")
for (kind,n),c in sorted(rows_ordinal_locked.items()):
    print(f"   {kind:5s} {n:16s} {c}")
if ex_any:
    print("\nexample co-mint dump:", ex_any[0], ex_any[1])
else:
    print("\n*** NO dump co-mints same-ordinal bare records_N AND records_N_rows ***")