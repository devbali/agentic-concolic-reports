#!/usr/bin/env python3
"""people batch — per-entrypoint coverage check (engine CoverageChecker).

Writes coverage_summary.json into each entrypoint dir, in the documented
per-entrypoint format (README "Reading the summary").

Usage:  cd /home/dev/project && PYTHONPATH=src python3 <this file> [entrypoint...]
"""
import glob
import json
import os
import sys
import time

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                   # noqa: E402
from concolic_engine.coverage import CoverageChecker  # noqa: E402

BATCH = "/home/dev/project/reports/diaspora/results/people"
ENTRYPOINTS = [
    "people_index", "people_show", "people_stream",
    "people_hovercard", "people_refresh_search", "people_retrieve_remote",
]


def check(ep):
    d = os.path.join(BATCH, ep)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    if not dumps:
        print(f"{ep}: NO_DUMPS")
        return
    runs, skipped, total_pcs = [], [], 0
    for p in dumps:
        raw = json.load(open(p))
        total_pcs += sum(1 for e in raw.get("events", [])
                         if e.get("type") == "path_condition")
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"{type(e).__name__}: {e}"})

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    errors = {}
    for p in dumps:
        raw = json.load(open(p))
        if raw.get("error"):
            errors[raw["error"]["type"]] = errors.get(raw["error"]["type"], 0) + 1

    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "genuine": total_pcs > 0,
        "total_path_conditions": total_pcs,
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
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
    print(f"{ep}: dumps={len(runs)} pcs={total_pcs} nodes={result.total_nodes} "
          f"missing={len(result.missing)} blocking={len(blocking)} "
          f"complete={result.complete} genuine={total_pcs > 0} "
          f"errors={errors} ({wall:.1f}s)")
    for m in result.missing[:12]:
        print(f"    MISSING {m.node_constraint} -> {m.missing_branch} "
              f"vals={m.concrete_values}")


if __name__ == "__main__":
    eps = sys.argv[1:] or ENTRYPOINTS
    for ep in eps:
        check(ep)
