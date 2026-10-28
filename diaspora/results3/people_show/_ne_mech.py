#!/usr/bin/env python3
"""Why is '(X != StringVal(''))' never taken TRUE while '(X == '')' has both
sides? Trace the dual text forms across the corpus for assoc_author_guid and
first_2_guid: same runs, same values?"""
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

# Per-run: which guid exprs appear, with what taken
per_run_eq = collections.Counter()   # (eq_expr, ne_expr, eq_taken, ne_taken)
n = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    n += 1
    # collect guid-family PCs for the two vars
    eq = {}
    ne = {}
    for pc in run.path_conditions:
        if pc.expr == "(assoc_author_guid == '')":
            eq['a'] = bool(pc.taken)
        if pc.expr == "(assoc_author_guid != StringVal(''))":
            ne['a'] = bool(pc.taken)
        if pc.expr == "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_guid == '')":
            eq['f'] = bool(pc.taken)
        if pc.expr == "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_guid != StringVal(''))":
            ne['f'] = bool(pc.taken)
    if eq or ne:
        key = (tuple(sorted(eq.items())), tuple(sorted(ne.items())))
        per_run_eq[key] += 1

print("runs scanned: %d" % n)
print("distinct (eq-taken, ne-taken) combos per run:")
for (eqk, nek), c in sorted(per_run_eq.items(), key=lambda kv: -kv[1])[:25]:
    print("  %6d  eq=%s  ne=%s" % (c, eqk, nek))

# Find a run where eq false but ne absent (value non-empty, != never evaluated)
count_eqF_no_ne = 0
count_eqT_no_ne = 0
count_neT = 0
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json')))[:2000]:
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    eqT = eqF = neT = neF = False
    for pc in run.path_conditions:
        if pc.expr == "(assoc_author_guid == '')":
            if pc.taken:
                eqT = True
            else:
                eqF = True
        if pc.expr == "(assoc_author_guid != StringVal(''))":
            if pc.taken:
                neT = True
            else:
                neF = True
    if neT:
        count_neT += 1
    if eqF and not (neT or neF):
        count_eqF_no_ne += 1
    if eqT and not (neT or neF):
        count_eqT_no_ne += 1
print("\n(sample 2000) runs with assoc_author_guid == '' taken:F but NO != event: %d" % count_eqF_no_ne)
print("(sample 2000) runs with assoc_author_guid == '' taken:T but NO != event: %d" % count_eqT_no_ne)
print("(sample 2000) runs with assoc_author_guid != '' taken:T (any): %d" % count_neT)