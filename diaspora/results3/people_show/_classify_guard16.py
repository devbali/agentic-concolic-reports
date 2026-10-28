#!/usr/bin/env python3
"""Classify all 64 SAT missing items by which guard vars they demand True.
Each demanded guard conjunct fires in find_person/show and forecloses the
downstream data vars (404 render or redirect_back), so the cross-format
data combos conjoined with a fired guard are geniunely unreachable.

Categories:
  MIXED       -> demands BOTH a firing guard (first_*/find_by_2/in-via) AND
                 downstream data vars (rows/records) in the same combo
  GUARD_ONLY  -> demands only guard True, no downstream data vars
  CLEAN       -> no guard=True; cross-format data demand only
We count how many carry a POSITIVE guard conjunct (user's '16' hypothesis) and
how many of THOSE also carry downstream data demand, etc.
"""
import json, re

sat = json.load(open("/tmp/per_item_sat.json"))
rows = sat["rows"]

GUARD_SUFFIX = ("_not_found", "_closed_account")

def split_top_and(expr):
    parts=[]; depth=0; cur=""; i=0; n=len(expr)
    while i<n:
        c=expr[i]
        if c=="(": depth+=1
        elif c==")": depth=max(0,depth-1)
        if depth==0 and expr[i:i+5]==" AND ":
            parts.append(cur.strip()); cur=""; i+=5; continue
        cur+=c; i+=1
    if cur.strip(): parts.append(cur.strip())
    return parts

def conj_info(conj):
    """return (kind, var_or_None): kind in {pos_guard, neg_guard, pos_data, neg_data}"""
    s=conj.strip()
    neg = s.startswith("Not(")
    inner = s[4:-1] if neg else s
    inner = inner.strip()
    # normalize len(...) reprs
    m = re.match(r"\(?([^()]*?)\s*==\s*(True)\s*\)?$", inner)
    # broader: find a var
    var_m = re.search(r"(SYM_[A-Za-z0-9_]+|[A-Za-z_][A-Za-z0-9_]*)", inner)
    var = var_m.group(1) if var_m else ""
    is_guard = var.endswith(GUARD_SUFFIX)
    if is_guard:
        return ("neg_guard" if neg else "pos_guard"), var
    return ("neg_data" if neg else "pos_data"), var

guard_vars = []
for r in rows:
    nc = r["node_constraint"]
    conjs = split_top_and(nc)
    gv=set(); has_downstream=False; neg_guard=False
    for c in conjs:
        kind, var = conj_info(c)
        if kind=="pos_guard": gv.add(var)
        elif kind=="neg_guard": neg_guard=True
        elif kind in ("pos_data","neg_data"):
            # a data var => downstream demand (rows/records/guid/author)
            if "rows" in var or "records" in var or "to_a" in var or "guid" in var or "author" in var or "profile" in var or "comment" in var or "handle" in var:
                has_downstream=True
    guard_vars.append({"idx": r["idx"], "guards": sorted(gv), "downstream": has_downstream, "neg_guard": neg_guard})

from collections import Counter
cat=Counter()
pos_with_down=0
pos_only=0
clean=0
for gv in guard_vars:
    n=len(gv["guards"])
    if n>0 and gv["downstream"]:
        cat["POS_GUARD+downstream"]+=1; pos_with_down+=1
    elif n>0:
        cat["POS_GUARD only"]+=1; pos_only+=1
    else:
        cat["clean (no pos guard)"]+=1; clean+=1

print("Total:", len(guard_vars))
for k,c in cat.most_common(): print(f"  {c:3d}  {k}")
print("POSITIVE-guard items total:", pos_with_down+pos_only)
print("  of which also carry downstream data demand:", pos_with_down)
print("  of which guard-only:", pos_only)
print("clean (no pos guard):", clean)

# distinct guard vars
gv_all=Counter()
for gv in guard_vars:
    for g in gv["guards"]: gv_all[g]+=1
print("\ndistinct positive guard vars:")
for g,c in sorted(gv_all.items()): print(f"  {c:3d}  {g}")