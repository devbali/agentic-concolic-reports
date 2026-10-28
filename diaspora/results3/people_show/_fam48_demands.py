#!/usr/bin/env python3
"""Analyze the 48-family (5-ordinal) missing items: raw prefix demands,
grouped by the row-ordinal pattern, to design the foreclosure."""
import glob
import json
import os
import re
import sys
import collections

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.coverage import CoverageChecker
from concolic_engine.run import Run
import coverage_assumptions as ca

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump):
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


runs = []
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    runs.append(run)
print("runs loaded: %d" % len(runs))

checker = CoverageChecker(runs=runs, assumptions=ca.build())
result = checker.check_coverage()
print("MISSING=%d" % len(result.missing))

ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
BARE_RE = re.compile(r"Relation_records_(\d+) ")
fam48 = [m for m in result.missing
         if len(set(int(g.group(1)) for g in ROW_RE.finditer(m.node_constraint))) >= 4]
print("48-family items: %d" % len(fam48))

# Distinct ordinal-demand signatures
sigs = collections.Counter()
for m in fam48:
    rows = tuple(sorted(set(int(g.group(1)) for g in ROW_RE.finditer(m.node_constraint))))
    sigs[rows] += 1
print("\nrow-ordinal demand signatures:")
for sig, c in sigs.most_common():
    print("  %2d items  rows=%s" % (c, sig))

# What row-conjunct OUTCOMES do they demand? Group by (var_base, op, target)
row_demands = collections.Counter()
for m in fam48:
    for pc in m.prefix:
        e = pc.expr
        if "_rows" in e:
            row_demands[(e, bool(pc.taken))] += 1
print("\ndistinct row-conjunct demands (expr, want):")
for (e, w), c in row_demands.most_common(20):
    print("  %2d  want=%s  %s" % (c, 'T' if w else 'F', e[:100]))

# Bare records demands
bare_demands = collections.Counter()
for m in fam48:
    for pc in m.prefix:
        e = pc.expr
        if re.match(r"\(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_\d+ [!=]= 0\)", e):
            bare_demands[(e, bool(pc.taken))] += 1
print("\ndistinct bare-records demands:")
for (e, w), c in bare_demands.most_common():
    print("  %2d  want=%s  %s" % (c, 'T' if w else 'F', e[:100]))

# Full prefix of item 0
print("\n=== item 0 (48-family) full prefix ===")
for pc in fam48[0].prefix:
    print("  want=%s  %s" % ('T' if pc.taken else 'F', pc.expr[:130]))