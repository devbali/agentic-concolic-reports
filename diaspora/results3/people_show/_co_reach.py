#!/usr/bin/env python3
"""Check whether the composed corpus reached the target co-conjunctions.

Targets (from the 64 missing items' constraint shapes):
  1. via_user dot-T  x  posts rows>0   (format-exclusive join probe)
  2. first_1 blank-T x  via_user dot-T  (blank x dot)
  3. guid=='' x via_user dot-T
  4. deep stream: >=6 stream-row exprs co-recorded in ONE run
"""
import json
import os
import re

HERE = "/home/dev/project/reports/diaspora/results3/people_show"
files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))

PAT = {
    "via_user_dot": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_PERSON_via_user_diaspora_handle, 0, [12]\)\)"),
    "via_user_blen": re.compile(r"\(SubString\(SYM_PERSON_via_user_diaspora_handle, 0, (?:Length\(SYM_PERSON_via_user_diaspora_handle\) - 0|1)\) == ''\)"),
    "via_user_guid_empty": re.compile(r"\(SYM_PERSON_via_user_guid == ''\)"),
    "first1_blank": re.compile(r"\(SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, (?:Length\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle\) - 0|1)\) == ''\)"),
    "first1_dot": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, [12]\)\)"),
    "rows_gt0": re.compile(r"\(len\(SYM_RESULT_ActiveRecord__Relation_(?:records_\d+_rows|to_a_\d+_rows)\) [>!]=? 0\)"),
}

counts = {k: 0 for k in PAT}
co = {}
for f in files:
    try:
        d = json.load(open(os.path.join(HERE, f)))
    except Exception:
        continue
    exprs = set()
    for pc in d.get("events", []):
        if pc.get("type") != "path_condition":
            continue
        e = pc.get("expr", "")
        exprs.add(e)
        for k, pat in PAT.items():
            if pat.search(e):
                counts[k] += 1
    # per-run flags
    flags = {k: any(pat.search(e) for e in exprs) for k, pat in PAT.items()}
    for a in PAT:
        for b in PAT:
            if a < b and flags[a] and flags[b]:
                co[(a, b)] = co.get((a, b), 0) + 1

print("total dumps:", len(files))
for k in PAT:
    print(f"  {k}: {counts[k]} PC occurrences")
print("\nco-occurrence (runs with BOTH):")
for (a, b), n in sorted(co.items()):
    if n:
        print(f"  {a} x {b}: {n}")