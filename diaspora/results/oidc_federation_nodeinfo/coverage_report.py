#!/usr/bin/env python3
"""Per-entrypoint coverage check for the oidc_federation_nodeinfo batch.

Same shape as reference/coverage_report.py, but iterates every entrypoint
subdir and writes each one's own coverage_summary.json. Coverage is NEVER
merged across the batch.

    cd /home/dev/project && PYTHONPATH=src python3 <this file>
"""
import glob
import json
import os
import sys
import time

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

BATCH = "/home/dev/project/reports/diaspora/results/oidc_federation_nodeinfo"


def pc_count(path):
    j = json.load(open(path))
    return sum(1 for e in (j.get("events") or []) if e.get("type") == "path_condition")


def main():
    rows = []
    for ep in sorted(os.listdir(BATCH)):
        d = os.path.join(BATCH, ep)
        if not os.path.isdir(d):
            continue
        dumps = sorted(glob.glob(os.path.join(d, "dump_*.json")))
        if not dumps:
            print(f"{ep}: NO_DUMPS")
            continue

        runs, skipped, total_pcs = [], [], 0
        for p in dumps:
            try:
                total_pcs += pc_count(p)
                runs.append(Run.from_dict(json.load(open(p))))
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
            "vacuous_zero_path_conditions": total_pcs == 0,
            "total_path_conditions": total_pcs,
            "tree_nodes": result.total_nodes,
            "missing_branches": len(result.missing),
            "blocking_missing_branches": len(blocking),
            "total_runs": result.total_runs,
            "dumps_loaded": len(runs),
            "dumps_unparseable": skipped,
            "dump_errors": errors,
            "solver_lost": result.solver_lost,
            # Serialized from the engine itself (each assumption with its
            # source file/line) rather than hard-coded, so this field cannot
            # silently disagree with what the checker actually applied.
            # This batch declares NONE: every complete=true below is strict
            # per-node observation.
            "assumptions": result.assumptions_to_dict(),
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

        rows.append((ep, len(runs), total_pcs, result.total_nodes,
                     len(result.missing), result.complete, total_pcs > 0))
        print(f"{ep}: dumps={len(runs)} pcs={total_pcs} nodes={result.total_nodes} "
              f"missing={len(result.missing)} complete={result.complete} "
              f"{'GENUINE' if total_pcs else 'VACUOUS'} unparseable={len(skipped)} "
              f"errors={errors}")

    print("\n| entrypoint | dumps | PCs | nodes | missing | complete | kind |")
    print("|---|---|---|---|---|---|---|")
    for ep, n, pcs, nodes, miss, comp, gen in rows:
        print(f"| `{ep}` | {n} | {pcs} | {nodes} | {miss} | {comp} | "
              f"{'genuine' if gen else 'VACUOUS'} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
