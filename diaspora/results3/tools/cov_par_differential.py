#!/usr/bin/env python3
"""Run a batch's coverage_report.py against a CHOSEN concolic_engine copy.

The batch report scripts do `sys.path.insert(0, "/home/dev/project/src")`, which
would beat any PYTHONPATH.  So this driver imports the engine FIRST, from the
tree named by $ENGINE_SRC, which binds it in `sys.modules`; the report's own
`from concolic_engine... import ...` then reuses the already-imported modules.

  ENGINE_SRC=<dir>   engine tree to import (default /home/dev/project/src)
  COVERAGE_PAR=...   step-6 pool width, read by the patched engine only

Usage: cov_par_differential.py <path to coverage_report.py>
All other env (SUMMARY_OUT, DUMP_LIST, COVERAGE_CHECKPOINT, ...) passes through.
"""
import os
import runpy
import sys
import time

engine_src = os.environ.get("ENGINE_SRC", "/home/dev/project/src")
sys.path.insert(0, engine_src)

import concolic_engine                      # noqa: E402
import concolic_engine.coverage             # noqa: E402
import concolic_engine.solver               # noqa: E402
import concolic_engine.assumptions          # noqa: E402
import concolic_engine.run                  # noqa: E402
import concolic_engine.checkpoint           # noqa: E402

loaded = os.path.dirname(concolic_engine.coverage.__file__)
print(f"[differential] engine = {loaded}", flush=True)
print(f"[differential] COVERAGE_PAR = {os.environ.get('COVERAGE_PAR', '<unset>')}",
      flush=True)
assert os.path.realpath(loaded).startswith(os.path.realpath(engine_src)), \
    f"engine came from {loaded}, not {engine_src}"

# Phase timing, driver-local: the report prints none, and the sweep needs the
# COVERAGE phase separated from the ~load. Wrapping the bound method here
# instruments without touching src/.
_orig_check = concolic_engine.coverage.CoverageChecker.check_coverage


def _timed_check(self):
    t = time.time()
    try:
        return _orig_check(self)
    finally:
        print(f"[differential] COVERAGE_PHASE_SECONDS={time.time() - t:.1f}",
              flush=True)


concolic_engine.coverage.CoverageChecker.check_coverage = _timed_check

report = sys.argv[1]
sys.argv = [report] + sys.argv[2:]
t0 = time.time()
try:
    runpy.run_path(report, run_name="__main__")
except SystemExit as e:
    print(f"[differential] report exit={e.code}", flush=True)
print(f"[differential] WALL_SECONDS={time.time() - t0:.1f}", flush=True)
