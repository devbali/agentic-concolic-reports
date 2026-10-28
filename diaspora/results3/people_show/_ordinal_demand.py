#!/usr/bin/env python3
"""Analyze the CURRENT missing[] items: what ordinal pairs do they demand?

For each of the 64 missing items, extract the demanded conjuncts:
- records_N (bare, e.g. len(SYM_RESULT_ActiveRecord__Relation_records_2) == 0 / != 0)
- rows_N (e.g. SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows > 0)
- to_a (SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)
- presence/absence per ordinal family, and the sign (==0 / >0 / !=0).
"""
import json
import re

data = json.load(open('/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json'))
missing = data['missing']

BARE_RE = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)\s*(==|!=)\s*(\d+)")
ROWS_RE = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_(\d+)_rows\s*(>|==|!=)\s*(\d+)")
TOA_RE  = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_(\d+)_rows\s*(>|==|!=)\s*(\d+)")
GUID_RE = re.compile(r"SYM_RESULT_ActiveRecord__Relation_to_a_(\d+)_row_guid\s*(==|!=)\s*(''|StringVal\(''\))")

from collections import Counter
fam_counter = Counter()
examples = {}

for it in missing:
    nc = it['node_constraint']
    bare = [(int(m.group(1)), m.group(2), m.group(3)) for m in BARE_RE.finditer(nc)]
    rows = [(int(m.group(1)), m.group(2), m.group(3)) for m in ROWS_RE.finditer(nc)]
    toa = [(int(m.group(1)), m.group(2), m.group(3)) for m in TOA_RE.finditer(nc)]
    fam = []
    for n, op, v in bare:
        fam.append(f"records_{n}{op}{v}")
    for n, op, v in rows:
        fam.append(f"rows_{n}{op}{v}")
    for n, op, v in toa:
        fam.append(f"to_a_{n}{op}{v}")
    if not fam:
        fam = ["NO-ORDINAL-CONJUNCT"]
    key = ";".join(sorted(fam))
    fam_counter[key] += 1
    if key not in examples:
        examples[key] = it['node_constraint'][:200]

print(f"total missing: {len(missing)}")
print(f"distinct ordinal-demand families: {len(fam_counter)}\n")
for key, cnt in fam_counter.most_common():
    print(f"  [{cnt:3d}] {key}")
    print(f"         e.g. {examples[key]}\n")