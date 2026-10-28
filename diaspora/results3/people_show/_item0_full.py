import json

new = json.load(open('coverage_summary.json'))
nc = new['missing'][0]['node_constraint']
print("item 0 full length:", len(nc))
print()
print(nc)
print()
# find all guard conjuncts anywhere in item 0
import re
for m in re.finditer(r'\(([A-Za-z0-9_]+?(?:not_found|closed_account))\s*==\s*(True|False)\)', nc):
    print("  guard conjunct:", m.group(1), "==", m.group(2))