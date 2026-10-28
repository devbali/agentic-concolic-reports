import json

d = json.load(open("reports/diaspora/results3/people_show/coverage_summary.json"))
miss = d.get("missing", [])
for i, m in enumerate(miss):
    print("=== item %d ===" % i)
    print(m.get("node_constraint", ""))
    print()