#!/usr/bin/env python3
"""Extract event context (expr + taken + call note) for each rows/to_a ordinal."""
import glob
import json
import os
import re

HERE = '/home/dev/project/reports/diaspora/results3/people_show'

PATTERNS = {
    "rows_1": r"len\(SYM_RESULT_ActiveRecord__Relation_records_1_rows\)\s*(==|!=|>|<)\s*(\d+)",
    "rows_2": r"len\(SYM_RESULT_ActiveRecord__Relation_records_2_rows\)\s*(==|!=|>|<)\s*(\d+)",
    "rows_3": r"len\(SYM_RESULT_ActiveRecord__Relation_records_3_rows\)\s*(==|!=|>|<)\s*(\d+)",
    "rows_4": r"len\(SYM_RESULT_ActiveRecord__Relation_records_4_rows\)\s*(==|!=|>|<)\s*(\d+)",
    "rows_5": r"len\(SYM_RESULT_ActiveRecord__Relation_records_5_rows\)\s*(==|!=|>|<)\s*(\d+)",
    "to_a_1": r"len\(SYM_RESULT_ActiveRecord__Relation_to_a_1_rows\)\s*(==|!=|>|<)\s*(\d+)",
}

found = {k: [] for k in PATTERNS}

for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    for ev in raw.get("events", []):
        expr = str(ev.get("expr", ""))
        for k, pat in PATTERNS.items():
            if re.search(pat, expr):
                found[k].append((os.path.basename(p), expr[:110], ev.get("taken"), ev.get("note", "")))
    # stop early once we have a few examples each
    if all(len(v) >= 2 for v in found.values()):
        break

for k in PATTERNS:
    print(f"=== {k} ===")
    for fn, expr, taken, note in found[k][:3]:
        print(f"   {fn} taken={taken}")
        print(f"     expr: {expr}")
        if note:
            print(f"     note: {str(note)[:160]}")
    print()