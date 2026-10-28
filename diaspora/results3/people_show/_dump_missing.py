import json

d = json.load(open("reports/diaspora/results3/people_show/coverage_summary.json"))
miss = d.get("missing", [])
print("n missing:", len(miss))
for i, m in enumerate(miss):
    print("\n--- item %d ---" % i)
    print("constraint:", m.get("missing_constraint", "")[:220])
    print("node:", m.get("node_constraint", "")[:180])
    src = m.get("source_location", "")
    if src:
        print("src:", src[:100])