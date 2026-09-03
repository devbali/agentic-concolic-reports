#!/usr/bin/env python3
"""comments_index — per-entrypoint coverage check (results2 rerun).

Loads every dump in this directory, runs the engine's CoverageChecker under
the new COMBINATION-COVERAGE semantics (src/concolic_engine/coverage.py,
decision 2026-08-18) with this directory's coverage_assumptions.py, and
writes coverage_summary.json in the documented per-entrypoint format
(reports/diaspora/README.md "Reading the summary"), extended with the
combination-coverage fields (truncated, unevaluable_exprs, assumptions).

CoverageChecker is constructed with max_missing_per_clique=256 so
completeness is PROVEN (full enumeration), not cap-sampled.

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results2/comments_index/coverage_report.py
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402
import coverage_assumptions                               # noqa: E402


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

    assumptions = coverage_assumptions.build()

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=256,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    dump_errors = {}
    for p, r in zip(dumps, runs):
        err = getattr(r, "error", None)
        if err:
            dump_errors[os.path.basename(p)] = err

    summary = {
        "endpoint": "comments_index",
        "coverage_complete": bool(result.complete),
        "truncated": bool(result.truncated),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "genuine": genuine,
        "vacuous": not genuine,
        "dumps_loaded": len(runs),
        "dumps_unparseable": skipped,
        "dump_errors": dump_errors,
        "solver_lost": result.solver_lost,
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
