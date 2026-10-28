import json

new = json.load(open('coverage_summary.json'))
print("NEW missing:", len(new['missing']))
for i, m in enumerate(new['missing']):
    nc = m['node_constraint']
    print(f"--- item {i} ---")
    print(nc[:300])
    print()