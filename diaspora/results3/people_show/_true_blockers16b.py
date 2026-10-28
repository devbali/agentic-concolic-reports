#!/usr/bin/env python3
"""Corrected true-blocker analysis for the 16-family items.

Correct conjunct semantics:
- _outcome_constraint(e, True)  = e                      (bare expr text)
- _outcome_constraint(e, False) = "Not((e))"  -- DOUBLE parens
So a conjunct starting with 'Not((' is a False-side demand on the inner
expr; anything else is a True-side demand on the bare text (which may
itself be an expr that STARTS with 'Not(' -- e.g. NOTC1 = "Not(Contains(...))",
demanded True -- witnessed as its own expr).

Also: global census of '(X != StringVal(''))' taken:true across ALL vars.
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


def fix_len_names(dump):
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


def demand(conj):
    """Return (expr_text, wanted_bool) per checker semantics."""
    if conj.startswith("Not((") and conj.endswith("))"):
        # False-side demand on inner expr text (includes outer parens)
        return conj[4:-1], False
    return conj, True


print("16-family items: %d" % len(fam16))
blockers_total = collections.Counter()
for it in fam16:
    blockrs = []
    for conj in it['node_constraint'].split(" AND "):
        conj = conj.strip()
        expr, want = demand(conj)
        t, f = cov.get(expr, [0, 0])
        have = t if want else f
        if have == 0:
            blockrs.append((expr, want, t, f))
    n = fam16.index(it) + 1
    if blockrs:
        blockers_total[len(blockrs)] += 1
        print("\nitem %d: %d blockers" % (n, len(blockrs)))
        for expr, want, t, f in blockrs:
            print("   want=%s raw T=%5d F=%5d  %s" % (
                'T' if want else 'F', t, f, expr[:110]))
    else:
        print("\nitem %d: NO BLOCKERS" % n)

print("\nblocker-count distribution: %s" % dict(sorted(blockers_total.items())))

# Global census: any '(X != StringVal(''))' taken:true for ANY X?
ne_exprs = [(e, t, f) for e, (t, f) in cov.items() if "!= StringVal('')" in e]
ne_true = [x for x in ne_exprs if x[1] > 0]
print("\n=== global '!= StringVal('')' census ===")
print("exprs with the form: %d" % len(ne_exprs))
print("with taken:TRUE witnesses: %d" % len(ne_true))
for e, t, f in ne_exprs[:15]:
    print("   T=%5d F=%5d  %s" % (t, f, e[:110]))