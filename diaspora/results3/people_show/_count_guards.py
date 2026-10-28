#!/usr/bin/env python3
"""Count guard conjuncts in missing-item node_constraints (true split).

A "guard conjunct" is a top-level clause like
  (SYM_..._not_found == True)
  (SYM_..._closed_account == True)
appearing literally in the node_constraint display string.

Reads the FULL node_constraint from coverage_summary.json (source of truth),
not the truncated per_item_sat.json copies.
"""
import json
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "coverage_summary.json"

with open(PATH) as fh:
    summary = json.load(fh)
items = summary["missing"]
print("total missing items:", len(items))

GUARD_MARKERS = ("_not_found == True", "_closed_account == True")


def has_guard(node_constraint):
    return any(m in node_constraint for m in GUARD_MARKERS)


guard_idxs = [i for i, it in enumerate(items) if has_guard(it["node_constraint"])]
clean_idxs = [i for i, it in enumerate(items) if not has_guard(it["node_constraint"])]

print("WITH guard conjunct (not_found/closed_account == True):", len(guard_idxs))
print("    idxs:", guard_idxs)
print("WITHOUT guard conjunct (cross-format pure):           ", len(clean_idxs))
print("    idxs:", clean_idxs)
