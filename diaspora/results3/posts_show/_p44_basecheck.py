#!/usr/bin/env python3
"""P44 BASE-CHECK (read-only). Pre-drive differential: of the bases a construct
run actually CHOSE, how many themselves EVALUATE the size-gate literal their
gap's cube demands?

A base that never evaluates the literal cannot produce a run that walks it, so
this predicts the walk rate without spending a 4111-seed drive. Baseline for
CLASSBV1 (73-expr index): expected ~0, since that index did not even carry the
expression.

  P44_MANIFEST=<manifest.json> [P44_INDEX=...] [P44_GAPS=...] python3 _p44_basecheck.py
"""
import json, os, pickle, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p44_index_UNION2.pkl"))
GAPS = os.environ.get("P44_GAPS", os.path.join(HERE, "_p44_gaps_CLASSBV1.json"))
MANIFEST = os.environ["P44_MANIFEST"]
SIZERE = re.compile(os.environ.get("P44_SIZERE", r"CollectionProxy_size_\d+_size"))


def cube_literals(nc):
    """Verbatim copy of _p31_construct.py:197."""
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur:
        out.append("".join(cur))
    res = []
    for t in out:
        t = t.strip()
        if not t:
            continue
        pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        res.append((t, pol))
    return res


idx = pickle.load(open(INDEX, "rb"))
eidx = {e: i for i, e in enumerate(idx["exprs"])}
# dumps tuple: (path, var, em, tm, ns, cm, dl0, dl1, dfm)
by_name = {os.path.basename(d[0]): (d[2], d[3]) for d in idx["dumps"]}

gaps = {g["id"]: g for g in json.load(open(GAPS))}
man = json.load(open(MANIFEST))

stat = Counter()
first_rank = {}
for row in man:
    g = gaps.get(row["gap"])
    if g is None:
        stat["manifest row whose gap is not in the gaps file"] += 1
        continue
    sg = [(e, o) for e, o in cube_literals(g["node_constraint"]) if SIZERE.search(e)]
    if not sg:
        stat["seed whose gap has NO size-gate literal"] += 1
        continue
    bits = [(eidx.get(e), o) for e, o in sg]
    if any(j is None for j, _ in bits):
        stat["seed whose size-gate expr is NOT in this index"] += 1
        continue
    em_tm = by_name.get(row["base"])
    if em_tm is None:
        stat["seed whose chosen base is not in this index"] += 1
        continue
    em, tm = em_tm
    ev = all((em >> j) & 1 for j, _ in bits)
    # also: does the base take the DEMANDED side already?
    side = all((((em & tm) >> j) & 1) == (1 if o else 0) for j, o in bits)
    stat["seed: base EVALUATES the size gate" if ev
         else "seed: base never evaluates the size gate"] += 1
    if ev:
        stat["  ...and already takes the demanded side" if side
             else "  ...but takes the other side (seedable)"] += 1
    # per-GAP (a gap has K seeds; count it as reached if ANY of its bases does)
    prev = first_rank.get(row["gap"], False)
    first_rank[row["gap"]] = prev or ev

print(f"index    {os.path.basename(INDEX)}")
print(f"manifest {os.path.basename(MANIFEST)}  ({len(man)} seeds)")
print(f"gaps     {os.path.basename(GAPS)}  ({len(gaps)} gaps)\n")
for k, v in stat.most_common():
    print(f"   {v:6d}  {k}")
n_ok = sum(1 for v in first_rank.values() if v)
print(f"\n== GAPS with >=1 chosen base that evaluates the size gate: "
      f"{n_ok}/{len(first_rank)} ==")
