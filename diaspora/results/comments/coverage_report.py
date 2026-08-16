#!/usr/bin/env python3
"""Per-entrypoint coverage check for the comments batch.

Coverage is checked PER ENTRYPOINT (never merged across the batch): each
entrypoint directory's dumps are loaded on their own and written back as
<entrypoint>/coverage_summary.json.

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results/comments/coverage_report.py [entrypoint ...]
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

ENTRYPOINTS = ["comments_create", "comments_index", "comments_new", "comments_destroy"]


def check(entry: str) -> dict:
    d = os.path.join(HERE, entry)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    runs, skipped = [], []
    total_pcs = 0
    errors = {}
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"unparseable JSON: {type(e).__name__}: {e}"})
            continue
        total_pcs += sum(1 for ev in raw.get("events", [])
                         if ev.get("type") == "path_condition")
        if raw.get("error"):
            errors[raw["error"]["type"]] = errors.get(raw["error"]["type"], 0) + 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"Run.from_dict: {type(e).__name__}: {e}"})

    if not runs:
        summary = {
            "endpoint": entry,
            "coverage_complete": False,
            "tree_nodes": 0,
            "missing_branches": 0,
            "total_path_conditions": total_pcs,
            "dumps_loaded": 0,
            "dumps_unparseable": skipped,
            "genuine": False,
            "note": "no loadable dumps",
        }
    else:
        t0 = time.time()
        result = CoverageChecker(runs).check_coverage()
        wall = time.time() - t0
        blocking = [m for m in result.missing if not getattr(m, "untracked", False)]
        summary = {
            "endpoint": entry,
            "coverage_complete": bool(result.complete),
            "tree_nodes": result.total_nodes,
            "missing_branches": len(result.missing),
            "blocking_missing_branches": len(blocking),
            "total_runs": result.total_runs,
            "total_path_conditions": total_pcs,
            # HONESTY: complete=true with zero path conditions is VACUOUS —
            # the run recorded no branch at all, so nothing was covered.
            "genuine": total_pcs > 0,
            "vacuous": total_pcs == 0,
            "dumps_loaded": len(runs),
            "dumps_unparseable": skipped,
            "dump_errors": errors,
            "solver_lost": result.solver_lost,
            "assumptions": [],
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
                for m in result.missing[:200]
            ],
        }

    with open(os.path.join(d, "coverage_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    return summary


def main() -> int:
    entries = sys.argv[1:] or ENTRYPOINTS
    rc = 0
    for e in entries:
        s = check(e)
        print(f"{e}: dumps={s.get('dumps_loaded')} pcs={s.get('total_path_conditions')} "
              f"nodes={s.get('tree_nodes')} missing={s.get('missing_branches')} "
              f"complete={s.get('coverage_complete')} "
              f"{'GENUINE' if s.get('genuine') else 'VACUOUS'}")
        if not s.get("coverage_complete") or not s.get("genuine"):
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
