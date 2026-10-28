#!/usr/bin/env python3
"""P44 — CUBES CLOSED BY A DRIVE, counted on the dumps themselves.

Under §16b a leaf IS a full assignment over its demand set's members, so a cube
is covered exactly when some run realises every literal of its
`node_constraint`. That is measurable on the dump with no Z3 and no coverage
pass, and it is what `_p15_explain.py` calls WALKED.

This widens it two ways:
  * CROSS coverage -- a cube counts as closed if ANY dump of the drive realises
    it, not only the dump built for it. A drive closes cubes it was not aiming
    at, and the per-seed number undercounts.
  * it reports cubes closed PER 1 000 RUNS, the convergence number.

  usage: python3 _p44_cubes_closed.py <gaps.json> <TAG>
"""
import glob, json, os, re, sys, time
from collections import defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

def literals(nc):
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(": depth += 1
        elif c == ")": depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur: out.append("".join(cur))
    r = []
    for t in out:
        t = t.strip(); pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        if t: r.append((t, pol))
    return r

GAPS = sys.argv[1]; TAG = sys.argv[2]
gaps = json.load(open(GAPS))
lits = {g["id"]: literals(g["node_constraint"]) for g in gaps}
files = sorted(glob.glob(os.path.join(HERE, f"dump_*{TAG}*.json")))
print(f"{len(gaps)} target cubes; {len(files)} dumps labelled *{TAG}*", flush=True)
closed = set(); t0 = time.time()
for i, p in enumerate(files):
    if i and i % 500 == 0:
        print(f"  {i}/{len(files)} closed={len(closed)} {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(p))
    except Exception:
        continue
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    taken = defaultdict(set)
    for e in ev:
        if e.get("type") == "path_condition":
            taken[fixlen(rn(str(e.get("expr", ""))))].add(bool(e.get("taken")))
    for gid, L in lits.items():
        if gid in closed:
            continue
        if all(pol in taken.get(x, ()) for x, pol in L):
            closed.add(gid)
    del d
n = len(files)
print()
print(f"  target cubes                 : {len(gaps)}")
print(f"  runs driven                  : {n}")
print(f"  cubes CLOSED (cross-counted) : {len(closed)}")
print(f"  cubes closed PER 1 000 RUNS  : {1000.0*len(closed)/max(n,1):.1f}")
print(f"  cubes closed per run         : {len(closed)/max(n,1):.4f}")
json.dump(sorted(closed), open(os.path.join(HERE, f"_p44_closed_{TAG}.json"), "w"))
print("P44-CUBES-CLOSED-DONE")
