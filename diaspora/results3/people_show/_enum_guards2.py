#!/usr/bin/env python3
"""Enumerate distinct positive guard z3 vars across missing[] items."""
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

def guard_var(conj):
    s = conj.strip()
    if s.startswith('Not('):
        return None
    m = re.fullmatch(r'\(([^()]+)\s*==\s*True\)', s)
    if not m:
        m = re.fullmatch(r'([^()]+)\s*==\s*True', s)
    if not m:
        return None
    var = m.group(1).strip()
    if var.endswith('_not_found') or var.endswith('_closed_account'):
        return var
    return None

d = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))
counts = {}
for m in d["missing"]:
    for conj in split_top_and(m["node_constraint"]):
        v = guard_var(conj)
        if v:
            counts[v] = counts.get(v, 0) + 1
print("distinct guard vars (var -> #missing-items containing it as positive)")
for v, c in sorted(counts.items()):
    print(f"  {c:3d}  {v}")