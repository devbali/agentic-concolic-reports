#!/usr/bin/env python3
"""Compare the committed coverage_summary (saved to /tmp) vs the fresh
re-run: are the missing[] ITEM SETS identical (ordering aside)?"""
import json

old = json.load(open("/tmp/committed_coverage_summary.json"))
new = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))

old_missing = old["missing"]
new_missing = new["missing"]

def key(m):
    return (m["node_constraint"], m["missing_branch"], m["source_location"])

old_keys = {key(m) for m in old_missing}
new_keys = {key(m) for m in new_missing}

print(f"committed missing: {len(old_missing)} items")
print(f"fresh missing:     {len(new_missing)} items")
print(f"in committed only: {len(old_keys - new_keys)}")
print(f"in fresh only:     {len(new_keys - old_keys)}")

# also compare scalar fields
for f in ("coverage_complete", "tree_nodes", "missing_branches", "truncated",
          "solver_lost", "total_runs", "total_path_conditions", "assumptions_used"):
    if old.get(f) != new.get(f):
        print(f"FIELD DIFF {f}: committed={old.get(f)!r} fresh={new.get(f)!r}")

# ordering difference check
same_order = [key(m) for m in old_missing] == [key(m) for m in new_missing]
print("same order:", same_order)