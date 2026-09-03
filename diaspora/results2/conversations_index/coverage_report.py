#!/usr/bin/env python3
"""conversations_index — per-entrypoint coverage check (results2 rerun).

Loads every dump in this directory, runs the engine's CoverageChecker, and
writes coverage_summary.json in the documented per-entrypoint format
(reports/diaspora/README.md "Reading the summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results2/conversations_index/coverage_report.py
"""
import collections
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                              # noqa: E402
from concolic_engine.coverage import CoverageChecker             # noqa: E402
from concolic_engine.assumptions import (                        # noqa: E402
    AssumptionSet,
    UntrackedPathAssumption,
    IndependenceAssumption,
)
import coverage_assumptions                                      # noqa: E402

# ---------------------------------------------------------------------------
# Declared assumptions — see coverage_assumptions.py (module docstring +
# per-assumption agent_notes) for the argument behind each one, and
# REPORT.md "Assumptions" for the summary. Keyed by EXPRESSION per README
# "Declaring assumptions" (path conditions here are overwhelmingly recorded
# at mock boundaries shared by many decisions).
# ---------------------------------------------------------------------------
ASSUMPTIONS = coverage_assumptions.build().assumptions


def main() -> int:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped = [], []
    for p in dumps:
        try:
            runs.append(Run.from_dict(json.load(open(p))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)

    dump_errors = collections.Counter()
    for r in runs:
        if r.error:
            dump_errors[r.error.get("type", "Unknown")] += 1

    aset = AssumptionSet()
    for a in ASSUMPTIONS:
        aset.add(a)

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=aset, max_missing_per_clique=256,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    summary = {
        "endpoint": "conversations_index",
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "genuine": genuine,
        "vacuous": not genuine,
        "dumps_loaded": len(runs),
        "dumps_unparseable": skipped,
        "dump_errors": dict(dump_errors),
        "solver_lost": result.solver_lost,
        "truncated": result.truncated,
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "assumptions": result.assumptions_to_dict(),
        "assumptions_used": result.assumptions_used,
        "independent_folds": result.independent_folds,
        "checker_elapsed_seconds": round(wall, 1),
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "source_location": m.source_location,
                "untracked": bool(getattr(m, "untracked", False)),
                "concrete_values": m.concrete_values,
            }
            for m in result.missing[:200]
        ],
    }

    out = os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
