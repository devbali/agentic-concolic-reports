#!/usr/bin/env python3
"""Find the TRUE blocking conjuncts for all 16-family items.

Reuse the raw pc.expr corpus; for each item, list conjuncts whose RAW form
is never witnessed with the demanded side, treating NOTC/Index families as
distinct exprs (not inversions of Contains/IndexOf).
"""
import glob
import json
import os
import re
import sys
import collections

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run  # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


data = json.load(open(os.path.join(HERE, 'coverage_summary_live.json')))
missing = data['missing']
ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
fam16 = [it for it in missing
         if set(int(m.group(1)) for m in ROW_RE.finditer(it['node_constraint'])) == {4, 5}]

run_exprs = []
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    outs = {}
    for pc in run.path_conditions:
        outs.setdefault(pc.expr, set()).add(bool(pc.taken))
    run_exprs.append(outs)

cov = collections.defaultdict(lambda: [0, 0])
for ro in run_exprs:
    for e, ts in ro.items():
        if True in ts:
            cov[e][0] += 1
        if False in ts:
            cov[e][1] += 1

# The item conjuncts are ALREADY in raw pc.expr form (the checker's
# node_constraint == " AND ".join(_outcome_constraint(e, o)) where
# _outcome_constraint returns the expr text possibly Not()-wrapped).
# So: conjunct bare -> demand True on that expr text.
#     conjunct Not(X) -> demand False on X... BUT the checker's exprs X in
#     the universe are the FULL expr texts (which may themselves be Not(...)).
#     _outcome_constraint(e, True) = e  (e.g. "Not(Contains(...))")
#     _outcome_constraint(e, False) = Not(e)
# So a conjunct 'Not(Contains(...))' bare = demand True on expr
# 'Not(Contains(...))' — which is IN the corpus as its own expr.
# A conjunct 'Not((X == Y))' = _outcome_constraint(X==Y text, False) —
# demand False on '(X == Y)'. So the inversion applies ONLY when the inner
# is NOT itself a Not(...) expression.
def demand(conj):
    """Return (expr_text, wanted_bool) per checker semantics."""
    if conj.startswith("Not(") and conj.endswith(")"):
        inner = conj[4:-1]
        if inner.startswith("Not(") and inner.endswith(")"):
            # Not(Not(X)) — demand True on Not(X)? Can't occur here.
            return conj, True
        return inner, False
    return conj, True


print(f"16-family items: {len(fam16)}")
blockers_total = collections.Counter()
for it in fam16:
    blockers = []
    for conj in it['node_constraint'].split(" AND "):
        conj = conj.strip()
        expr, want = demand(conj)
        t, f = cov.get(expr, [0, 0])
        have = t if want else f
        if have == 0:
            blockers.append((expr, want, t, f))
    if blockers:
        blockers_total[len(blockers)] += 1
        print(f"\nitem {fam16.index(it)+1}: {len(blockers)} blockers")
        for expr, want, t, f in blockers:
            print(f"   want={'T' if want else 'F'} raw T={t:5d} F={f:5d}  {expr[:100]}")
    else:
        print(f"\nitem {fam16.index(it)+1}: NO BLOCKERS (witnessed per raw-expr check)")

print(f"\nblocker-count distribution: {dict(sorted(blockers_total.items()))}")