#!/usr/bin/env python3
"""posts_show — per-entrypoint coverage check (results2 rerun).

Loads every dump in this directory (both the "auth" and "anon" scenarios —
they write into the SAME directory per results2/README.md), runs the
engine's CoverageChecker, and writes coverage_summary.json in the documented
per-entrypoint format (reports/diaspora/README.md "Reading the summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results2/posts_show/coverage_report.py
"""
import glob
import json
import logging
import os
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

# PERF (batch-local, does not touch src/): concolic_engine.solver.check_satisfiability
# re-execs every merged Z3 declaration on EVERY call, including the
# permanently-broken `len(X) = Int(...)` pseudo-var decls this endpoint's
# dumps carry (invalid Python — assignment target is a call expression).
# Those fail every time and logger.warning() them, and with a
# max_missing_per_clique=256 enumeration issuing thousands of solver calls
# the repeated warning I/O measurably dominates wall time (a 252-dump corpus
# took >15 minutes to enumerate before this was added). Silencing the
# solver's logger changes no result, only the runtime.
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402
import coverage_assumptions                              # noqa: E402


def main() -> int:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped = [], []
    dump_errors = Counter()
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            dump_errors[raw["error"].get("type", "Unknown")] += 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)

    assumptions = coverage_assumptions.build(runs)

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=256, max_cliques=2048,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    summary = {
        "endpoint": "posts_show",
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
        "truncated": bool(result.truncated),
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "independent_folds": result.independent_folds,
        "assumptions": result.assumptions_to_dict(),
        "assumptions_used": result.assumptions_used,
        "checker_elapsed_seconds": round(wall, 1),
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "source_location": m.source_location,
                "untracked": bool(getattr(m, "untracked", False)),
                "concrete_values": m.concrete_values,
            }
            for m in result.missing[:400]
        ],
    }

    out = os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs};"
          f"TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={len(result.unevaluable_exprs)}")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
