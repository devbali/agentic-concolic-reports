#!/usr/bin/env python3
"""Print item 0's FULL node_constraint (raw, unprocessed)."""
import json

data = json.load(open('/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json'))
missing = data['missing']

for idx in (0, 1, 47):
    if idx >= len(missing):
        continue
    it = missing[idx]
    print(f"===== ITEM {idx} (len={len(it['node_constraint'])}) =====")
    print(it['node_constraint'])
    print()
    print("branch:", it.get('missing_branch'))
    print("loc:", it.get('source_location'))
    print()