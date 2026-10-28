#!/usr/bin/env python3
"""Run the checker IN-PROCESS on the live corpus + current assumptions;
analyze the 16-family missing items via their raw prefix tuples (no
Node-text ambiguity)."""
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
print("MISSING=%d BLOCKING=%d TRUNCATED=%s SOLVER_LOST=%d NODES=%d ASSUMPTIONS=%d"
      % (len(result.missing),
         sum(1 for m in result.missing if not m.untracked),
         result.truncated, result.solver_lost,
         result.total_nodes, result.assumptions_used))

ROW_RE = re.compile(r"Relation_records_(\d+)_rows")
fam16 = [m for m in result.missing
         if set(int(g.group(1)) for g in ROW_RE.finditer(m.node_constraint)) == {4, 5}]
print("16-family items: %d" % len(fam16))

# global coverage from runs
run_exprs = []
for run in runs:
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

blocker_counts = collections.Counter()
all_blockers = collections.Counter()
for m in fam16:
    blk = []
    for pc in m.prefix:
        expr, want = pc.expr, bool(pc.taken)
        t, f = cov.get(expr, [0, 0])
        have = t if want else f
        if have == 0:
            blk.append((expr, want, t, f))
            all_blockers[expr[:150]] += 1
    n = fam16.index(m) + 1
    blocker_counts[len(blk)] += 1
    if blk:
        print("\nitem %d: %d blockers" % (n, len(blk)))
        for expr, want, t, f in blk:
            print("   want=%s raw T=%5d F=%5d  %s" % (
                'T' if want else 'F', t, f, expr[:120]))
    else:
        print("\nitem %d: NO BLOCKERS (witnessed)" % n)

print("\nblocker-count distribution: %s" % dict(sorted(blocker_counts.items())))
print("\n=== distinct blocker exprs (items) ===")
for expr, c in all_blockers.most_common():
    print("  %2d items  %s" % (c, expr))