#!/usr/bin/env python3
"""Compare co-occurrence stats: baseline preserved corpus vs composed corpus."""
import json
import os
import re

BASELINE = "/tmp/pp_preserve"
NEW = "/home/dev/project/reports/diaspora/results3/people_show"

PAT = {
    "via_user_dot": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_PERSON_via_user_diaspora_handle, 0, [12]\)\)"),
    "via_user_blen": re.compile(r"\(SubString\(SYM_PERSON_via_user_diaspora_handle, 0, (?:Length\(SYM_PERSON_via_user_diaspora_handle\) - 0|1)\) == ''\)"),
    "via_user_guid_empty": re.compile(r"\(SYM_PERSON_via_user_guid == ''\)"),
    "first1_blank": re.compile(r"\(SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, (?:Length\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle\) - 0|1)\) == ''\)"),
    "first1_dot": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, [12]\)\)"),
    "rows_gt0": re.compile(r"\(len\(SYM_RESULT_ActiveRecord__Relation_(?:records_\d+_rows|to_a_\d+_rows)\) [>!]=? 0\)"),
}

def analyze(dirpath):
    files = sorted(f for f in os.listdir(dirpath) if f.startswith("dump_") and f.endswith(".json"))
    counts = {k: 0 for k in PAT}
    co = {}
    for f in files:
        try:
            d = json.load(open(os.path.join(dirpath, f)))
        except Exception:
            continue
        flags = {k: False for k in PAT}
        for pc in d.get("events", []):
            if pc.get("type") != "path_condition":
                continue
            e = pc.get("expr", "")
            for k, pat in PAT.items():
                if pat.search(e):
                    counts[k] += 1
                    flags[k] = True
        for a in PAT:
            for b in PAT:
                if a < b and flags[a] and flags[b]:
                    co[(a, b)] = co.get((a, b), 0) + 1
    return len(files), counts, co

for name, path in [("BASELINE(1781)", BASELINE), ("COMPOSED(1682)", NEW)]:
    n, counts, co = analyze(path)
    print(f"===== {name}: {n} dumps =====")
    for k in PAT:
        print(f"  {k}: {counts[k]}")
    print("  co-occurrences:")
    for (a, b), c in sorted(co.items()):
        print(f"    {a} x {b}: {c}")
    print()