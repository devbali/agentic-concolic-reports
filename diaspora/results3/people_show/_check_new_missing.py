#!/usr/bin/env python3
"""Classify the NEW missing[] (post 6c-corrected) — do the 16 guard-carrying
items remain, or only the 48 clean cross-format ones?"""
import json, re

cs = json.load(open("coverage_summary.json"))
miss = cs["missing"]
print("num missing (sample):", len(miss))

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

def pos_guard_vars(nc):
    out=[]
    for c in split_top_and(nc):
        s=c.strip()
        if s.startswith("Not("): continue
        inner=s
        if inner.startswith("(") and inner.endswith(")") and inner.count("(")==inner.count(")"):
            inner=inner[1:-1].strip()
        if "==" not in inner: continue
        lhs,rhs=inner.split("==",1); lhs=lhs.strip(); rhs=rhs.strip()
        if rhs not in ("True",): continue
        lhs=lhs.strip("()").strip()
        if lhs.endswith(GUARD_SUFFIX): out.append(lhs)
    return out

pos=0; clean=0
pos_vars={}
for m in miss:
    gv=pos_guard_vars(m["node_constraint"])
    if gv:
        pos+=1
        for g in gv: pos_vars[g]=pos_vars.get(g,0)+1
    else:
        clean+=1
print(f"POSITIVE-guard items in NEW sample: {pos}")
print(f"clean (no pos guard): {clean}")
print("pos guard var counts:", pos_vars)
print("=> if 16 all cleared, pos should be ~0")