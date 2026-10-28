#!/usr/bin/env python3
"""Check co-occurrence of the 48-family demanded row conjuncts in current dumps.

Demanded per item (family 1): records_1==0 ∧ records_2==0 ∧ rows_1>0 ∧
rows_2==15 ∧ rows_3>0 ∧ rows_4==15 ∧ rows_5>0 ∧ to_a_1!=0 ∧ PD ∧ NOTC ∧ ....

Count how many dumps carry each individual conjunct, then how many carry the
full row-family conjunction (rows_1>0 ∧ rows_2==15 ∧ rows_3>0 ∧ rows_4==15 ∧
rows_5>0 ∧ to_a_1!=0), and how many ALSO have the empty-bare-records side.
"""
import glob
import json
import re
import os

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
_LEN_RE = re.compile(r"len\(([^()]+)\)")

CONJS = {
    "rows_1>0":      r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0",
    "rows_2==15":    r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15",
    "rows_3>0":      r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows > 0",
    "rows_4==15":    r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_4_rows == 15",
    "rows_5>0":      r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_5_rows > 0",
    "to_a_1!=0":     r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0",
    "records_1 empty": r"Not\(\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0\)\)",
    "records_2 empty": r"Not\(\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0\)\)",
}

counts = {k: 0 for k in CONJS}
full_row = 0
full_row_and_empty = 0

def has_conj(fixed, pat):
    return re.search(pat, fixed) is not None

for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    fixed = _LEN_RE.sub(r"SYM_LEN_\1", json.dumps(raw))
    for k, pat in CONJS.items():
        if has_conj(fixed, pat):
            counts[k] += 1
    row_ok = all(has_conj(fixed, CONJS[k]) for k in
                 ["rows_1>0", "rows_2==15", "rows_3>0", "rows_4==15", "rows_5>0", "to_a_1!=0"])
    if row_ok:
        full_row += 1
        if counts["records_1 empty"] and counts["records_2 empty"]:
            # per-dump check
            if has_conj(fixed, CONJS["records_1 empty"]) and has_conj(fixed, CONJS["records_2 empty"]):
                full_row_and_empty += 1

print("=== individual conjunct presence in corpus ===")
for k in CONJS:
    print(f"  [{counts[k]:5d}] {k}")
print(f"\nfull row-family conjunction (rows_1>0∧rows_2==15∧rows_3>0∧rows_4==15∧rows_5>0∧to_a_1!=0): {full_row}")
print(f"full row conjunction AND records_1/2 empty: {full_row_and_empty}")