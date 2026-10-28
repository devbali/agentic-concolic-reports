#!/usr/bin/env python3
"""Verify FUTURE-WORK #3 dual-format dumps co-mint BOTH var families:
bare records_1/2 (block/contact, html leg) AND records_N_rows (posts stream,
mobile leg) in the SAME dump. Count dumps with each family and with both."""
import json, glob, sys, re
from collections import Counter

dumps = sorted(glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json"))
if not dumps:
    print("NO DUMPS FOUND"); sys.exit(1)

bare_re = re.compile(r"SYM_LEN_ActiveRecord__Relation_records_[12](?:_rows)?\b")
# careful: records_1_rows must NOT match the bare pattern alone; use exact names
def families(d):
    names = set()
    for e in d.get("events", []):
        if e.get("type") != "path_condition":
            continue
        s = e.get("expr", "")
        for m in re.findall(r"SYM_RESULT_ActiveRecord__Relation_(records_[0-9]+(?:_rows|_to_a_[0-9]+)?)", s):
            names.add(m)
    return names

both = 0; bare_only = 0; rows_only = 0; neither = 0
bare_total = 0; rows_total = 0
sample_both = None
for f in dumps:
    try:
        d = json.load(open(f))
    except Exception:
        continue
    n = families(d)
    has_bare = any(x == "records_1" or x == "records_2" for x in n)
    has_rows = any(x.endswith("_rows") or "_to_a_" in x for x in n)
    if has_bare: bare_total += 1
    if has_rows: rows_total += 1
    if has_bare and has_rows:
        both += 1; sample_both = sample_both or (f, sorted(n))
    elif has_bare: bare_only += 1
    elif has_rows: rows_only += 1
    else: neither += 1

print(f"dumps={len(dumps)}")
print(f"  bare records_1/2 present:   {bare_total}")
print(f"  rows/to_a family present:   {rows_total}")
print(f"  BOTH families co-minted:    {both}")
print(f"  bare-only: {bare_only}  rows-only: {rows_only}  neither: {neither}")
if sample_both:
    f, n = sample_both
    print("sample co-minted dump:", f)
    for x in sorted(n): print("   ", x)