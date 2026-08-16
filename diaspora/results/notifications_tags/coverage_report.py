#!/usr/bin/env python3
"""notifications_tags — per-entrypoint coverage check (reference checker,
one CoverageChecker per entrypoint directory, never merged across the batch).

Usage: cd /home/dev/project && PYTHONPATH=src python3 <this file>
"""
import glob
import json
import os
import sys
import time

BATCH = "/home/dev/project/reports/diaspora/results/notifications_tags"
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                   # noqa: E402
from concolic_engine.coverage import CoverageChecker  # noqa: E402


def pc_count(d):
    return sum(1 for e in d.get("events", []) if e.get("type") == "path_condition")


def main() -> int:
    eps = sorted(p for p in os.listdir(BATCH) if os.path.isdir(os.path.join(BATCH, p)))
    overall = []
    for ep in eps:
        d = os.path.join(BATCH, ep)
        dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
        runs, raw, skipped = [], [], []
        for p in dumps:
            j = json.load(open(p))
            raw.append(j)
            try:
                runs.append(Run.from_dict(j))
            except Exception as e:  # noqa: BLE001
                skipped.append({"file": os.path.basename(p),
                                "error": f"{type(e).__name__}: {e}"})
        total_pcs = sum(pc_count(j) for j in raw)
        errs = {}
        for j in raw:
            if j.get("error"):
                errs[j["error"]["type"]] = errs.get(j["error"]["type"], 0) + 1

        t0 = time.time()
        result = CoverageChecker(runs).check_coverage()
        wall = time.time() - t0
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
            "dumps_with_error": errs,
            "solver_lost": result.solver_lost,
            "assumptions": [],
            "assumptions_used": result.assumptions_used,
            "checker_elapsed_seconds": round(wall, 2),
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
        print(f"{ep:26s} dumps={len(runs):2d} pcs={total_pcs:2d} nodes={result.total_nodes:2d} "
              f"missing={len(result.missing):2d} complete={result.complete} "
              f"{'GENUINE' if total_pcs else 'VACUOUS'} errors={errs}")
        overall.append(summary)

    with open(os.path.join(BATCH, "coverage_summary.json"), "w") as fh:
        json.dump({"batch": "notifications_tags",
                   "note": "per-entrypoint results; coverage is never merged across the batch",
                   "entrypoints": overall}, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
