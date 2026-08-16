#!/usr/bin/env python3
"""services_admin — per-ENTRYPOINT coverage check.

Coverage is checked per entrypoint directory, never merged across the batch
(README "Output structure"). Writes <entrypoint>/coverage_summary.json.

Usage:
    cd /home/dev/project && PYTHONPATH=src python3 \
        reports/diaspora/results/services_admin/coverage_report.py
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


def check(ep: str) -> dict:
    d = os.path.join(HERE, ep)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    runs, skipped = [], []
    for p in dumps:
        try:
            runs.append(Run.from_dict(json.load(open(p))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    if not runs:
        summary = {"endpoint": ep, "coverage_complete": False, "tree_nodes": 0,
                   "missing_branches": 0, "dumps_loaded": 0,
                   "dumps_unparseable": skipped, "note": "NO PARSEABLE DUMPS"}
        with open(os.path.join(d, "coverage_summary.json"), "w") as fh:
            json.dump(summary, fh, indent=2)
        return summary

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0

    total_pcs = sum(len(r.path_conditions) for r in runs)
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "genuine": total_pcs > 0,
        "vacuous_zero_path_conditions": total_pcs == 0,
        "total_path_conditions": total_pcs,
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "dumps_loaded": len(runs),
        "dumps_unparseable": skipped,
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
    eps = sorted(n for n in os.listdir(HERE)
                 if os.path.isdir(os.path.join(HERE, n)))
    rows = [check(ep) for ep in eps]
    print(f"{'entrypoint':22} {'dumps':>5} {'PCs':>4} {'nodes':>5} {'miss':>4} "
          f"{'complete':>8}  kind")
    for s in rows:
        kind = "GENUINE" if s.get("genuine") else "VACUOUS (0 PCs)"
        print(f"{s['endpoint']:22} {s.get('dumps_loaded',0):5d} "
              f"{s.get('total_path_conditions',0):4d} {s.get('tree_nodes',0):5d} "
              f"{s.get('missing_branches',0):4d} "
              f"{str(s['coverage_complete']):>8}  {kind}")
    with open(os.path.join(HERE, "batch_coverage.json"), "w") as fh:
        json.dump({"batch": "services_admin",
                   "entrypoints": [{k: v for k, v in s.items() if k != "missing"}
                                   for s in rows]}, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
