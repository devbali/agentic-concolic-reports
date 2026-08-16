#!/usr/bin/env python3
"""search_links_reports_profiles — per-entrypoint coverage check.

Coverage is checked PER ENTRYPOINT (never merged across the batch): each
subdirectory's dump_*.json files are loaded on their own and written back as
that subdirectory's coverage_summary.json.

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results/search_links_reports_profiles/coverage_report.py [entrypoint ...]
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

ENTRYPOINTS = [
    "search_search", "links_resolve", "report_index", "report_create",
    "report_update", "report_destroy", "profiles_edit", "profiles_update",
    "profiles_show",
]


def pc_count(path):
    j = json.load(open(path))
    return sum(1 for e in j.get("events", []) if e.get("type") == "path_condition")


def check(ep):
    d = os.path.join(HERE, ep)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    if not dumps:
        print(f"{ep}: NO_DUMPS")
        return None

    runs, skipped, total_pcs = [], [], 0
    for p in dumps:
        try:
            runs.append(Run.from_dict(json.load(open(p))))
            total_pcs += pc_count(p)
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"{type(e).__name__}: {e}"})

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    errors = {}
    for p in dumps:
        j = json.load(open(p))
        if j.get("error"):
            errors.setdefault(j["error"]["type"], 0)
            errors[j["error"]["type"]] += 1

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

    print(f"{ep:16s} dumps={len(runs):3d} pcs={total_pcs:3d} nodes={result.total_nodes:3d} "
          f"missing={len(result.missing):3d} complete={result.complete} "
          f"{'GENUINE' if total_pcs else 'VACUOUS'} errors={errors}")
    return summary


def main():
    eps = sys.argv[1:] or ENTRYPOINTS
    out = {}
    for ep in eps:
        s = check(ep)
        if s:
            out[ep] = s
    with open(os.path.join(HERE, "batch_coverage_index.json"), "w") as fh:
        json.dump({k: {kk: v[kk] for kk in
                       ("coverage_complete", "genuine", "total_path_conditions",
                        "tree_nodes", "missing_branches", "dumps_loaded",
                        "dump_errors")}
                   for k, v in out.items()}, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
