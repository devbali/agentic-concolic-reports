#!/usr/bin/env python3
"""Probe: how do guard tokens appear in missing[] node_constraints (positive vs negated)."""
import json

cs = json.load(open("coverage_summary.json"))
print("num missing:", len(cs["missing"]))

SUFFIX = ("_not_found == True", "_closed_account == True")

for idx, m in enumerate(cs["missing"][:6]):
    nc = m["node_constraint"]
    print("")
    print("===== item", idx, "len", len(nc), "====")
    found = False
    for suf in SUFFIX:
        start = 0
        while True:
            j = nc.find(suf, start)
            if j < 0:
                break
            found = True
            lo = max(0, j - 70)
            hi = min(len(nc), j + len(suf) + 40)
            print("  ..." + nc[lo:hi] + "...")
            start = j + 1
    if not found:
        print("  (no guard token in this constraint)")
