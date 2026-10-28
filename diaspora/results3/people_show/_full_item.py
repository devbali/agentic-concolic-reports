#!/usr/bin/env python3
"""Dump the FULL node_constraint of one 48-family missing item."""
import json

data = json.load(open('/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json'))
missing = data['missing']

# find first item of the 48-family (has records_1/2 empty + rows_1..5 + to_a)
target = None
for it in missing:
    nc = it['node_constraint']
    if ('records_1' in nc and 'records_2' in nc and 'rows_1' in nc
            and 'rows_5' in nc and 'to_a_1' in nc):
        target = it
        break

if not target:
    print("NO MATCH")
else:
    print("=== FULL node_constraint of a 48-family item ===")
    print(target['node_constraint'])
    print()
    print("=== missing_branch ===")
    print(target.get('missing_branch'))
    print()
    print("=== source_location ===")
    print(target.get('source_location'))