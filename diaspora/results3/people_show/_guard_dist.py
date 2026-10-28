#!/usr/bin/env python3
"""Which positive guard vars appear in ground-truth missing items, distribution."""
import json, re
from collections import Counter

GUARD_VAR_SUFFIX = ("_not_found", "_closed_account")

def split_top_and(expr):
    parts = []; depth = 0; cur = ""; i = 0; n = len(expr)
    while i < n:
        c = expr[i]
        if c == "(": depth += 1
        elif c == ")": depth = max(0, depth - 1)
        if depth == 0 and expr[i:i+5] == " AND ":
            parts.append(cur.strip()); cur = ""; i += 5; continue
        cur += c; i += 1
    if cur.strip(): parts.append(cur.strip())
    return parts

def pos_guard_vars(conj):
    s = conj.strip()
    if s.startswith("Not("): return []
    inner = s
    if inner.startswith("(") and inner.endswith(")") and inner.count("(")==inner.count(")"):
        inner = inner[1:-1].strip()
    if "==" not in inner: return []
    lhs, rhs = inner.split("==",1); lhs=lhs.strip(); rhs=rhs.strip()
    if rhs not in ("True",): return []
    lhs = lhs.strip("()").strip()
    if not lhs.endswith(GUARD_VAR_SUFFIX): return []
    return [lhs]

cs = json.load(open("coverage_summary.json"))
cnt = Counter()
per_item = {}
for m in cs["missing"]:
    nc = m["node_constraint"]
    guards = []
    for c in split_top_and(nc):
        guards.extend(pos_guard_vars(c))
    per_item[m.get("node","?")+"|"+nc[:60]] = guards
    for g in set(guards): cnt[g]+=1

print("guard var -> #items (positive, ground truth)")
for g,c in cnt.most_common():
    print(f"  {c:3d}  {g}")

# characterize each item: single guard family?
import collections
fam = Counter()
for guards in per_item.values():
    gs=set(guards)
    if not gs: fam["none"]+=1
    elif len(gs)==1: fam["single:"+list(gs)[0]]+=1
    else: fam["multi:"+",".join(sorted(gs))]+=1
print("\nitem composition:")
for k,c in fam.most_common(): print(f"  {c:3d}  {k}")

# unique guard families across all 64
allg = sorted({g for gs in per_item.values() for g in gs})
print("\nall distinct guard vars:", allg)
