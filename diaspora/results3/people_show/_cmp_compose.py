#!/usr/bin/env python3
"""Compare new composed-run missing list vs committed baseline (a68c5fe).

Also counts how many baseline-missing items are still missing, and whether
the deep multi-var conjunctions (dot x guid x stream x branch-B) show any
new witnesses in the composed corpus.
"""
import json
import os
import subprocess
import sys

HERE = "/home/dev/project/reports/diaspora/results3/people_show"

# baseline missing from git (a68c5fe)
blob = subprocess.run(
    ["git", "-C", "/home/dev/project/reports", "show",
     "a68c5fe:diaspora/results3/people_show/coverage_summary.json"],
    capture_output=True, text=True)
base = json.loads(blob.stdout)
base_missing = base.get("missing", [])
print("baseline missing items:", len(base_missing))

with open(os.path.join(HERE, "coverage_summary.json")) as f:
    new = json.load(f)
new_missing = new.get("missing", [])
print("new (composition) missing items:", len(new_missing))

def sig(m):
    nc = m.get("node_constraint", "")
    return tuple(sorted(nc.split(" AND ")))

base_sigs = {sig(m) for m in base_missing}
new_sigs = {sig(m) for m in new_missing}

print("baseline sigs not in new (CLEARED):", len(base_sigs - new_sigs))
print("new sigs not in baseline (NEW):", len(new_sigs - base_sigs))
print("common:", len(base_sigs & new_sigs))

# Show one cleared item sample if any
if base_sigs - new_sigs:
    print("\n--- CLEARED sample (was missing, now witnessed/UNSAT) ---")
    sample = next(iter(base_sigs - new_sigs))
    print(" AND\n".join(sample)[:800])
if new_sigs - base_sigs:
    print("\n--- NEW sample (was covered, now missing) ---")
    sample = next(iter(new_sigs - base_sigs))
    print(" AND\n".join(sample)[:800])