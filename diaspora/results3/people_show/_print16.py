#!/usr/bin/env python3
"""Print the 16-family missing items (rows 4,5 only) in full."""
import json

data = json.load(open('/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json'))
missing = data['missing']

n = 0
for it in missing:
    nc = it['node_constraint']
    if "'records_1_rows'" in nc or "'records_2_rows'" in nc or "'records_3_rows'" in nc:
        continue
    if 'records_4_rows' in nc and 'records_5_rows' in nc:
        n += 1
        print(f"===== {n} (len={len(nc)}) =====")
        print(nc)
        print()