#!/usr/bin/env python3
"""Inspect raw node_constraint strings of the 64 missing items.

Goal: understand exact display format before writing a depth-aware guard
counter. Prints a few full strings + a census of guard-ish substrings with and
without surrounding 'Not(' scope.
"""
import json
from collections import Counter

SRC = "/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"
summary = json.load(open(SRC))
items = summary.get("missing", [])
print(f"total missing items: {len(items)}")

# --- census of guard-ish substrings ---
markers = ["_not_found == True", "_closed_account == True"]
c_sub = Counter()
c_negated = Counter()   # appears inside a Not(...) scope somewhere
c_name = Counter()

for it in items:
    nc = it["node_constraint"]
    for m in markers:
        idx = nc.find(m)
        while idx != -1:
            # walk back from idx to find if the nearest enclosing ( before
            # idx is preceded by 'Not' (i.e., 'Not(' at some depth before it)
            # find all '(' positions before idx
            negated = False
            # find the '(' that opens the enclosing group of this marker's
            # '==' region: scan backwards for matching paren
            depth = 0
            j = idx
            # scan backwards counting ')' as closing and '(' as opening
            open_pos = None
            for k in range(idx, -1, -1):
                if nc[k] == ')':
                    depth += 1
                elif nc[k] == '(':
                    if depth == 0:
                        open_pos = k
                        break
                    else:
                        depth -= 1
            # check if immediately before open_pos is 'Not'
            if open_pos is not None:
                before = nc[max(0, open_pos-3):open_pos]
                negated = (before == 'Not')
            c_sub[m] += 1
            if negated:
                c_negated[m] += 1
            idx = nc.find(m, idx+1)

print("\ncensus of guard substrings (may repeat within one item):")
for m in markers:
    print(f"  {m}: total={c_sub[m]}  inside_Not_scope={c_negated[m]}")

print("\n--- full node_constraint of first 3 items (truncated display) ---")
for i in range(min(3, len(items))):
    print(f"\n=== item {i} (nc len {len(items[i]['node_constraint'])}) ===")
    print(items[i]["node_constraint"][:2000])
