#!/usr/bin/env python3
"""Debug: show how split_top_and / is_positive_guard handle item 0."""
import json, re, sys
sys.path.insert(0, "/home/dev/project/reports/diaspora/results3/people_show")

def split_top_and(expr):
    parts = []
    depth = 0
    cur = []
    i = 0
    n = len(expr)
    while i < n:
        c = expr[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth = max(0, depth - 1)
        if depth == 0 and expr[i:i+5] == ' AND ':
            parts.append(''.join(cur).strip())
            cur = []
            i += 5
            continue
        cur.append(c)
        i += 1
    if cur:
        parts.append(''.join(cur).strip())
    return [p for p in parts if p]

d = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))
nc = d["missing"][0]["node_constraint"]
parts = split_top_and(nc)
print("num parts:", len(parts))
for i, p in enumerate(parts[:6]):
    print(f"[{i}] {p!r}")