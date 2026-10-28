#!/usr/bin/env python3
"""P44 — THE REACH NECESSITY TABLE OVER DECISION OUTCOMES.

The index's `necess` conditions ONLY on LENGTH variables, so a member whose
reach is governed by another DECISION gets no pin and the constructor cannot
target it. Measured here from the index bitmasks: for demand expression `e` and
every other expression `f` at outcome `o`, if over >= MIN_RUNS runs that took
`f=o` the run NEVER evaluated `e`, then `f != o` is a measured precondition of
`e`'s reach.  Read-only; writes one json.
"""
import json, os, pickle, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
MIN_RUNS = int(os.environ.get("P44_MIN_RUNS", "200"))
OUT = os.environ.get("P44_OUT", os.path.join(HERE, "_p44_reachnec.json"))

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; dumps = idx["dumps"]
n = len(exprs)
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
print(f"{len(dumps)} dumps, {n} exprs, MIN_RUNS={MIN_RUNS}", flush=True)

ev = [0]*n                    # runs evaluating e
tk = [[0, 0] for _ in range(n)]   # runs taking f False/True
co = [[Counter(), Counter()] for _ in range(n)]   # co[f][o][e] = runs with f=o AND e evaluated
for i in range(len(dumps)):
    em, tm, fm = EM[i], TM[i], DFM[i]
    evs = [j for j in range(n) if (em >> j) & 1]
    for j in evs:
        ev[j] += 1
    for j in evs:
        for o in (0, 1):
            if (tm >> j) & 1 if o else (fm >> j) & 1:
                tk[j][o] += 1
                c = co[j][o]
                for k in evs:
                    c[k] += 1

res = {}
for e in range(n):
    if ev[e] < MIN_RUNS:
        continue
    bad = []
    for f in range(n):
        if f == e:
            continue
        for o in (0, 1):
            if tk[f][o] >= MIN_RUNS and co[f][o].get(e, 0) == 0:
                bad.append([exprs[f], bool(o)])
    if bad:
        res[exprs[e]] = bad
print(f"expressions with >=1 DECISION-outcome reach precondition: {len(res)} of {n}")
tot = sum(len(v) for v in res.values())
print(f"total conditions: {tot}")
for e, v in sorted(res.items(), key=lambda kv: -len(kv[1]))[:12]:
    print(f"  {len(v):3d}  {e[:96]}")
    for f, o in v[:4]:
        print(f"        forbids  {f[:86]} = {o}")
json.dump({"min_runs": MIN_RUNS, "eval_counts": {exprs[i]: ev[i] for i in range(n)},
           "conditions": res}, open(OUT, "w"), indent=1)
print("P44-REACHNEC-DONE")
