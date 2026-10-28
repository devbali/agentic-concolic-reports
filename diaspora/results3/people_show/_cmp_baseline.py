#!/usr/bin/env python3
"""Compare baseline (git HEAD) missing items vs current run."""
import json
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))

# Baseline from git HEAD
blob = subprocess.run(
    ["git", "-C", "/home/dev/project/reports", "show",
     "06d1019:diaspora/results3/people_show/coverage_summary.json"],
    capture_output=True, text=True
)
baseline = json.loads(blob.stdout)
bm = baseline.get("missing", [])
print("BASELINE HEAD missing:", len(bm))

rows_pat = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_(records|to_a)_\d+_rows")
bare_pat = re.compile(r"SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_\d+(?!_rows)")

# Classify baseline items
cat = {"has_rows_only": 0, "has_bare_only": 0, "has_both": 0, "no_len": 0}
for m in bm:
    nc = m.get("node_constraint", "")
    has_rows = bool(rows_pat.search(nc))
    has_bare = bool(bare_pat.search(nc))
    if has_rows and has_bare:
        cat["has_both"] += 1
    elif has_rows:
        cat["has_rows_only"] += 1
    elif has_bare:
        cat["has_bare_only"] += 1
    else:
        cat["no_len"] += 1
print("baseline categories:", cat)

for i in range(3):
    print(f"\n--- baseline missing[{i}] ---")
    print(bm[i].get("node_constraint", "")[:500])

# Current categories
with open(os.path.join(HERE, "coverage_summary.json")) as f:
    cur = json.load(f)
cm = cur.get("missing", [])
cat2 = {"has_rows_only": 0, "has_bare_only": 0, "has_both": 0, "no_len": 0}
for m in cm:
    nc = m.get("node_constraint", "")
    has_rows = bool(rows_pat.search(nc))
    has_bare = bool(bare_pat.search(nc))
    if has_rows and has_bare:
        cat2["has_both"] += 1
    elif has_rows:
        cat2["has_rows_only"] += 1
    elif has_bare:
        cat2["has_bare_only"] += 1
    else:
        cat2["no_len"] += 1
print("\nCURRENT categories:", cat2)