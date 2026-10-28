#!/usr/bin/env python3
"""P44 — WHICH MEMBERS ARE CLASS C, and what does the corpus say governs them?
Class C = the miss is `never_evaluated`, the cube contradicts no known reach
condition, and no one-sided condition exists at all. This lists the members by
volume and, for each, the single best PREDICTOR of being evaluated (positive and
negative) so the shape of the missing layer is visible."""
import json, os, pickle, re, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
idx = pickle.load(open(os.path.join(HERE, "_p31_index_P35C.pkl"), "rb"))
exprs = idx["exprs"]; LENS = idx["lens"]; dumps = idx["dumps"]
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
N = len(dumps)
ex = json.load(open(os.path.join(HERE, sys.argv[1])))["per_gap"]
gaps = {g["id"]: g for g in json.load(open(os.path.join(HERE, sys.argv[2])))}

# recompute one-sided conditions to split A/B/C exactly as _p44_missreason did
MIN = 200
evc = [sum(1 for i in range(N) if (EM[i] >> j) & 1) for j in range(len(exprs))]
COND = defaultdict(list)
for e in range(len(exprs)):
    if evc[e] < MIN:
        continue
    for f in range(len(exprs)):
        if f == e:
            continue
        z = [o for o, M in ((0, DFM), (1, TM))
             if sum(1 for i in range(N) if (M[i] >> f) & 1) >= MIN
             and not any((EM[i] >> e) & 1 for i in range(N) if (M[i] >> f) & 1)]
        if len(z) == 1:
            COND[exprs[e]].append((exprs[f], bool(z[0])))
    for j in range(len(LENS)):
        z = [o for o, M in ((0, DL0), (1, DL1))
             if sum(1 for i in range(N) if (M[i] >> j) & 1) >= MIN
             and not any((EM[i] >> e) & 1 for i in range(N) if (M[i] >> j) & 1)]
        if len(z) == 1:
            COND[exprs[e]].append((f"({LENS[j]} != 0)", bool(z[0])))

C = Counter()
for gid, r in ex.items():
    if r["walked"] or r["first_bad_v"] != "never_evaluated":
        continue
    if not COND.get(r["first_bad"]):
        C[r["first_bad"]] += 1
print("CLASS C MEMBERS BY VOLUME (no one-sided reach condition exists at all)")
for e, n in C.most_common(10):
    j = exprs.index(e) if e in exprs else None
    print(f"\n  {n:5d}  {e[:96]}")
    if j is None:
        print("        NOT IN THE INDEX EXPRESSION UNIVERSE"); continue
    print(f"        evaluated in {evc[j]}/{N} runs ({100.0*evc[j]/N:.1f} %)")
    rows = []
    for f in range(len(exprs)):
        if f == j:
            continue
        for o, M in ((0, DFM), (1, TM)):
            sel = [i for i in range(N) if (M[i] >> f) & 1]
            if len(sel) < MIN:
                continue
            rows.append((sum(1 for i in sel if (EM[i] >> j) & 1)/len(sel), len(sel),
                         exprs[f], bool(o)))
    for k in range(len(LENS)):
        for o, M in ((0, DL0), (1, DL1)):
            sel = [i for i in range(N) if (M[i] >> k) & 1]
            if len(sel) < MIN:
                continue
            rows.append((sum(1 for i in sel if (EM[i] >> j) & 1)/len(sel), len(sel),
                         "LEN " + LENS[k], "nonzero" if o else "zero"))
    rows.sort()
    print("        strongest NEGATIVE predictors of reach:")
    for p, ns, f, o in rows[:3]:
        print(f"           P(eval)={p*100:5.1f}%  n={ns:6d}  {f[:70]} = {o}")
    print("        strongest POSITIVE:")
    for p, ns, f, o in rows[-2:]:
        print(f"           P(eval)={p*100:5.1f}%  n={ns:6d}  {f[:70]} = {o}")
print("\nP44-CLASSC-DONE")
