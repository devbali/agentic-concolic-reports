#!/usr/bin/env python3
"""Gate 1b post-rerun coverage verification across all diaspora batches.

For each batch, loads all dump_*.json run dumps, runs the CoverageChecker,
and writes a coverage_summary.json next to the results dir. Prints a compact
honest per-batch table including how many runs crashed vs. completed.

Usage:
    python3 reports/diaspora/verify_gate1b.py [batch ...]

Batch name is the directory under reports/diaspora/results/. With no args,
all batch dirs are processed.
"""
import json
import glob
import os
import sys

SYS = os.path.join(os.path.dirname(__file__), "..", "..", "src")
sys.path.insert(0, SYS)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

RESULTS = os.path.join(os.path.dirname(__file__), "results")


def batch_names():
    """Batch dirs under RESULTS, excluding hidden backups/temp dirs."""
    return sorted(
        d for d in os.listdir(RESULTS)
        if os.path.isdir(os.path.join(RESULTS, d)) and not d.startswith(".")
    )


def main():
    args = sys.argv[1:]
    batches = args or batch_names()

    for b in batches:
        bdir = os.path.join(RESULTS, b)
        dumps = sorted(glob.glob(os.path.join(bdir, "**", "dump_*.json"), recursive=True))
        runs = []
        crashed = 0
        complete = 0
        crashed_types = {}
        for p in dumps:
            try:
                d = json.load(open(p))
            except Exception as e:  # noqa: BLE001
                print(f"  [skip] {p}: {e}")
                continue
            run = Run.from_dict(d)
            runs.append(run)
            if run.error:
                crashed += 1
                t = run.error.get("type", "?")
                crashed_types[t] = crashed_types.get(t, 0) + 1
            else:
                complete += 1

        if not runs:
            print(f"== {b}: NO RUNS ==")
            continue

        try:
            r = CoverageChecker(runs).check_coverage()
        except Exception as e:  # noqa: BLE001
            print(f"== {b}: checker error {e} ==")
            r = None

        summary = {
            "batch": b,
            "runs_loaded": len(runs),
            "runs_completed_noerror": complete,
            "runs_crashed": crashed,
            "crash_types": crashed_types,
        }
        if r is not None:
            summary.update({
                "coverage_complete": r.complete,
                "tree_nodes": r.total_nodes,
                "missing_branches": len(r.missing),
                "solver_lost": r.solver_lost,
                "solver_ms": r.elapsed_ms,
            })
            summary["missing"] = [
                {"at": m.node_constraint, "loc": m.source_location,
                 "branch": m.missing_branch, "values": m.concrete_values,
                 "untracked": m.untracked}
                for m in r.missing
            ]
            out_path = os.path.join(bdir, "coverage_summary.json")
            with open(out_path, "w") as f:
                json.dump(summary, f, indent=2)

            print(f"== {b}: {len(runs)} runs, {complete} ok, {crashed} crashed, "
                  f"complete={r.complete}, nodes={r.total_nodes}, "
                  f"missing={len(r.missing)}, lost={r.solver_lost}")
            if crashed_types:
                print(f"    crashed: {crashed_types}")
        else:
            print(f"== {b}: {len(runs)} runs, {complete} ok, {crashed} crashed (no coverage)")

    print("ALL_DONE")


if __name__ == "__main__":
    main()
