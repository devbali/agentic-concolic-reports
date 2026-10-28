#!/usr/bin/env python3
"""Print 5 FULL node_constraints from the mixed-corpus missing list (untruncated)
to see exactly which conjuncts block witnessing."""
import json

d = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))
m = d.get("missing", [])
print("total missing:", len(m))
# print every 8th one fully as a sample
for i in [0,1,8,20,40,63]:
    if i < len(m):
        x = m[i]
        print(f"\n===== missing[{i}] =====")
        print(str(x.get("node_constraint","?")))
        for k,v in x.items():
            if k != "node_constraint":
                print(f"  {k}: {str(v)[:100]}")