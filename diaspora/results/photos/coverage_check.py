#!/usr/bin/env python3
"""photos batch — per-entrypoint coverage check.

Runs the engine's CoverageChecker over EACH entrypoint's own dumps and writes
that entrypoint's coverage_summary.json (README "Reading the summary" format).

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 <this file> [entrypoint ...]
"""
import glob
import json
import os
import sys
import time

BATCH = "/home/dev/project/reports/diaspora/results/photos"
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402


def check(ep):
    d = os.path.join(BATCH, ep)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    if not dumps:
        print(f"{ep}: NO_DUMPS")
        return None

    runs, skipped, pcs, errors = [], [], 0, {}
    for p in dumps:
        raw = json.load(open(p))
        pcs += sum(1 for e in raw.get("events", []) if e.get("type") == "path_condition")
        if raw.get("error"):
            errors[raw["error"]["type"]] = errors.get(raw["error"]["type"], 0) + 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "genuine": pcs > 0,
        "vacuous": pcs == 0,
        "total_path_conditions": pcs,
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

    print(f"{ep}: dumps={len(runs)} pcs={pcs} nodes={result.total_nodes} "
          f"missing={len(result.missing)} complete={result.complete} "
          f"{'GENUINE' if pcs else 'VACUOUS'} errors={errors} ({wall:.1f}s)")
    return summary


def main():
    eps = sys.argv[1:] or sorted(
        n for n in os.listdir(BATCH) if os.path.isdir(os.path.join(BATCH, n)))
    out = {}
    for ep in eps:
        s = check(ep)
        if s:
            out[ep] = {k: s[k] for k in ("coverage_complete", "genuine", "total_path_conditions",
                                         "tree_nodes", "missing_branches", "dumps_loaded",
                                         "dump_errors")}
    with open(os.path.join(BATCH, "coverage_index.json"), "w") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()
