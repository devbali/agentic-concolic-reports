#!/usr/bin/env python3
"""P44 — THE ADMISSIBILITY FILTER. Drop cubes that demand a condition the corpus
says forecloses one of their own members. Measured cost of not having it: 762 of
3 000 runs (25.4 %) in round P44S, 732 of them on ONE pair.

The table is one-sided reach conditions over decisions AND lengths, recomputed
from the index (MIN_RUNS, default 200) so table and filter cannot drift apart.

A dropped cube is NOT declared foreclosed -- it is carried as UNREACHED and
written to <out>.dropped.json with the pair that dropped it, so the ruling stays
the owner's.

  usage: _p44_admissible.py <gaps.json> <out_gaps.json>
"""
import json, os, pickle, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
MIN = int(os.environ.get("P44_MIN_RUNS", "200"))
SRC, DST = sys.argv[1], sys.argv[2]

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; LENS = idx["lens"]; dumps = idx["dumps"]
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
N = len(dumps)
ev = [sum(1 for i in range(N) if (EM[i] >> j) & 1) for j in range(len(exprs))]
COND = defaultdict(list)
for e in range(len(exprs)):
    if ev[e] < MIN:
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
print(f"reach conditions: {sum(len(v) for v in COND.values())} over {len(COND)} exprs",
      flush=True)

def demands(nc):
    d = {}
    for part in (nc or "").split(" AND "):
        s = part.strip(); pol = True
        while s.startswith("Not(") and s.endswith(")"):
            s = s[4:-1].strip(); pol = not pol
        d[s] = pol
    return d

gaps = json.load(open(SRC))
keep, drop = [], []
why = Counter()
for g in gaps:
    dem = demands(g["node_constraint"])
    bad = None
    for e in dem:
        for f, o in COND.get(e, ()):
            if dem.get(f) == o:
                bad = (e, f, o); break
        if bad:
            break
    if bad:
        why[(bad[0][:64], f"{bad[1][:58]}={bad[2]}")] += 1
        g2 = dict(g); g2["dropped_by"] = list(bad)
        drop.append(g2)
    else:
        keep.append(g)
for i, g in enumerate(keep):
    g["id"] = f"a{i:06d}"
json.dump(keep, open(DST, "w"))
json.dump(drop, open(DST + ".dropped.json", "w"))
print(f"  gaps {len(gaps)} -> ADMISSIBLE {len(keep)} ({100.0*len(keep)/max(len(gaps),1):.1f} %), "
      f"dropped {len(drop)} as UNREACHED (not foreclosed)")
for k, n in why.most_common(6):
    print(f"   {n:5d}  {k[0]}\n            with  {k[1]}")
print("P44-ADMISSIBLE-DONE")
