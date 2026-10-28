#!/usr/bin/env python3
"""Variant of _p44_missreason.py that ALSO dumps the gid lists per class, so a
validation drive can be targeted at exactly the Class-B misses. Classification
logic is copy-identical to _p44_missreason.py (post-relevance-filter, 2026-09-17);
this file only adds JSON id-list output. Read-only measurement, no src/ touch.

usage: _p44_missreason_dump.py <gaps.json> <explain.json> <out_prefix>
writes <out_prefix>_A.json / _B.json / _C.json  (lists of gap ids)
"""
import json, os, pickle, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
MIN = int(os.environ.get("P44_MIN_RUNS", "200"))

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
dumps = idx["dumps"]
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
N = len(dumps)

ev = [0]*len(exprs)
for i in range(N):
    em = EM[i]
    for j in range(len(exprs)):
        if (em >> j) & 1:
            ev[j] += 1
COND = defaultdict(list)
for e in range(len(exprs)):
    if ev[e] < MIN:
        continue
    for f in range(len(exprs)):
        if f == e:
            continue
        zero = []
        for o, M in ((0, DFM), (1, TM)):
            sel = [i for i in range(N) if (M[i] >> f) & 1]
            if len(sel) < MIN:
                continue
            if not any((EM[i] >> e) & 1 for i in sel):
                zero.append(o)
        if len(zero) == 1:
            COND[exprs[e]].append(("expr", exprs[f], bool(zero[0])))
    for j in range(len(LENS)):
        zero = []
        for o, M in ((0, DL0), (1, DL1)):
            sel = [i for i in range(N) if (M[i] >> j) & 1]
            if len(sel) < MIN:
                continue
            if not any((EM[i] >> e) & 1 for i in sel):
                zero.append(o)
        if len(zero) == 1:
            COND[exprs[e]].append(("len", LENS[j], bool(zero[0])))
print(f"reach conditions (one-sided, MIN_RUNS={MIN}): "
      f"{sum(len(v) for v in COND.values())} over {len(COND)} expressions", flush=True)

gaps = {g["id"]: g for g in json.load(open(sys.argv[1]))}
ex = json.load(open(sys.argv[2]))["per_gap"]
OUT_PREFIX = sys.argv[3]

def demands(nc):
    d = {}
    for part in (nc or "").split(" AND "):
        s = part.strip(); pol = True
        while s.startswith("Not(") and s.endswith(")"):
            s = s[4:-1].strip(); pol = not pol
        d[s] = pol
    return d

V = Counter(); IDS = defaultdict(list)
for gid, r in ex.items():
    if r["walked"]:
        continue
    tgt = r["first_bad"]
    dem = demands(gaps[gid]["node_constraint"])
    cs = COND.get(tgt) or []
    hit = None
    for kind, name, out in cs:
        if kind == "expr":
            if dem.get(name) == out:
                hit = (kind, name, out); break
        else:
            lexpr = f"({name} != 0)"
            if dem.get(lexpr) is not None and dem[lexpr] == out:
                hit = (kind, name, out); break
    def cond_var(kind, name):
        return f"({name} != 0)" if kind == "len" else name
    relevant = [c for c in cs if cond_var(c[0], c[1]) in dem]
    if hit:
        V["A"] += 1; IDS["A"].append(gid)
    elif relevant:
        V["B"] += 1; IDS["B"].append(gid)
    else:
        V["C"] += 1; IDS["C"].append(gid)
tot = sum(V.values())
print(f"\nMISSES CLASSIFIED ({tot})")
for k in ("A", "B", "C"):
    n = V.get(k, 0)
    print(f"   {k}  {n:6d}  {100.0*n/max(tot,1):5.1f} %")
for k in ("A", "B", "C"):
    with open(f"{OUT_PREFIX}_{k}.json", "w") as f:
        json.dump(IDS.get(k, []), f)
    print(f"wrote {OUT_PREFIX}_{k}.json  ({len(IDS.get(k, []))} ids)")
print("P44-MISSREASON-DUMP-DONE")
