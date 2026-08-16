#!/usr/bin/env python3
"""likes batch — per-ENTRYPOINT coverage check.

Coverage is checked per entrypoint, never merged across the batch (README
"Output structure"). For each <entrypoint>/ subdir this loads every dump_*.json,
runs the engine's CoverageChecker, and writes <entrypoint>/coverage_summary.json.

It also records the honesty numbers the batch report needs: total path
conditions across the entrypoint's dumps, and whether the entrypoint is
GENUINE (>=1 PC) or VACUOUS (0 PCs -> not covered, whatever the checker says).

Usage:
    cd /home/dev/project && PYTHONPATH=src python3 \
        reports/diaspora/results/likes/coverage_check.py [entrypoint ...]
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                   # noqa: E402
from concolic_engine.coverage import CoverageChecker  # noqa: E402

ENTRYPOINTS = ["likes_create", "likes_destroy", "likes_index"]


def check(ep):
    d = os.path.join(HERE, ep)
    dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
    if not dumps:
        print(f"{ep}: NO_DUMPS")
        return None

    runs, skipped, pcs, errors = [], [], 0, {}
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"unparseable JSON: {type(e).__name__}: {e}"})
            continue
        pcs += sum(1 for e in raw.get("events", []) if e.get("type") == "path_condition")
        err = raw.get("error")
        if err:
            errors[err["type"]] = errors.get(err["type"], 0) + 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"{type(e).__name__}: {e}"})

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    expl = {}
    ep_expl = os.path.join(d, "exploration_summary.json")
    if os.path.exists(ep_expl):
        expl = json.load(open(ep_expl))

    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "dumps_loaded": len(runs),
        "dumps_on_disk": len(dumps),
        "dumps_unparseable": skipped,
        # --- honesty fields (BATCH_BRIEFING) ---
        "total_path_conditions": pcs,
        "genuine": pcs > 0,
        "vacuous": pcs == 0,
        "dump_errors_by_type": errors,
        "worklist_exhausted": expl.get("worklist_exhausted"),
        "exploration_stop_reason": expl.get("stop_reason"),
        "runs_executed": expl.get("runs_executed"),
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

    print(f"{ep}: complete={result.complete} nodes={result.total_nodes} "
          f"missing={len(result.missing)} blocking={len(blocking)} dumps={len(runs)} "
          f"PCs={pcs} {'GENUINE' if pcs else 'VACUOUS'} "
          f"drained={expl.get('worklist_exhausted')} errors={errors} ({wall:.1f}s)")
    return summary


def main():
    eps = sys.argv[1:] or ENTRYPOINTS
    out = [s for s in (check(ep) for ep in eps) if s]
    with open(os.path.join(HERE, "coverage_index.json"), "w") as fh:
        json.dump(out, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
