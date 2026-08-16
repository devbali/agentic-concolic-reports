#!/usr/bin/env python3
"""Per-entrypoint coverage check for the streams batch.

Usage: cd /home/dev/project && PYTHONPATH=src python3 <this> <batchdir>
Writes <batchdir>/<entrypoint>/coverage_summary.json for every entrypoint dir.
"""
import glob
import json
import os
import sys
import time

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.run import Run                    # noqa: E402
from concolic_engine.coverage import CoverageChecker   # noqa: E402


def check(ep_dir, ep):
    dumps = sorted(glob.glob(os.path.join(ep_dir, "dump_*.json")))
    runs, skipped = [], []
    npcs = 0
    # Solver-independent completeness signal. The engine cannot parse
    # `len(...)` constraints, so check_satisfiability() returns UNSAT for them
    # and coverage.py's `if not result.satisfiable: continue` SILENTLY DROPS
    # the missing side -> `complete` is not evidence for those nodes. Track,
    # per branch expression, which outcomes were actually observed.
    sides = {}
    errs = {}
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:
            skipped.append({"file": os.path.basename(p), "error": f"UNPARSEABLE {type(e).__name__}: {e}"})
            continue
        npcs += sum(1 for ev in raw.get("events", []) if ev.get("type") == "path_condition")
        for ev in raw.get("events", []):
            if ev.get("type") == "path_condition":
                sides.setdefault(ev.get("expr"), set()).add(bool(ev.get("taken")))
        err = raw.get("error")
        if err:
            errs[err.get("type")] = errs.get(err.get("type"), 0) + 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]
    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "genuine": npcs > 0,
        "total_path_conditions": npcs,
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
        "distinct_branch_exprs": len(sides),
        "both_sides_observed": sum(1 for v in sides.values() if len(v) == 2),
        "one_sided_exprs": sorted(e for e, v in sides.items() if len(v) == 1),
        "dump_errors": errs,
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
    with open(os.path.join(ep_dir, "coverage_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    print(f"{ep:24s} dumps={len(runs):3d} pcs={npcs:3d} nodes={result.total_nodes:3d} "
          f"missing={len(result.missing):3d} complete={result.complete} "
          f"genuine={npcs > 0} unparseable={len(skipped)} "
          f"exprs={len(sides)} both_sides={summary['both_sides_observed']} "
          f"errs={errs}")
    for e in summary["one_sided_exprs"]:
        print(f"    ONE-SIDED {e}")
    for m in result.missing[:8]:
        print(f"    MISSING {m.node_constraint} -> {m.missing_branch} @ {m.source_location}")
    return summary


def main():
    base = sys.argv[1]
    eps = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
    out = {}
    for ep in eps:
        out[ep] = check(os.path.join(base, ep), ep)
    with open(os.path.join(base, "coverage_index.json"), "w") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()
