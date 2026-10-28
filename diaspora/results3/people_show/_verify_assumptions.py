#!/usr/bin/env python3
"""Verify the modified coverage_assumptions.py: build + full checker run."""
import glob
import json
import os
import re
import sys

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

assumptions = ca.build()
print("assumptions built: %d" % len(assumptions.assumptions))

checker = CoverageChecker(runs=runs, assumptions=assumptions)
result = checker.check_coverage()
blocking = [m for m in result.missing if not m.untracked]
print("MISSING=%d BLOCKING=%d TRUNCATED=%s SOLVER_LOST=%d NODES=%d ASSUMPTIONS_USED=%d PCS=%s"
      % (len(result.missing), len(blocking), result.truncated, result.solver_lost,
         result.total_nodes, result.assumptions_used, result.wall_elapsed_ms if hasattr(result, 'wall_elapsed_ms') else '?'))
print("COMPLETE=%s" % bool(not blocking and not result.truncated and result.solver_lost == 0))
if result.missing:
    for m in result.missing[:10]:
        print("  [%s] %s" % ("untracked" if m.untracked else "blocking", m.node_constraint[:150]))