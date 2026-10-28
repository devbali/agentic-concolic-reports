#!/usr/bin/env python3
"""Debug is_positive_guard directly."""
import json, re

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

GUARD = ('_not_found', '_closed_account')

def is_positive_guard(conj):
    s = conj.strip()
    if s.startswith('Not('):
        return False
    m = re.fullmatch(r'\(([^()]+)\s*==\s*True\)', s)
    if not m:
        m = re.fullmatch(r'([^()]+)\s*==\s*True', s)
    if not m:
        return False
    var = m.group(1).strip()
    return var.endswith(GUARD)

d = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))
nc = d["missing"][0]["node_constraint"]
parts = split_top_and(nc)
p0 = parts[0]
print("p0:", repr(p0))
print("startswith Not(:", p0.startswith('Not('))
m = re.fullmatch(r'\(([^()]+)\s*==\s*True\)', p0)
print("fullmatch:", m)
if m:
    print("group1:", repr(m.group(1).strip()))
    print("endswith guard:", m.group(1).strip().endswith(GUARD))
print("is_positive_guard:", is_positive_guard(p0))