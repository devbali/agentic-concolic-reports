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
        # Each endpoint under the batch gets its OWN CoverageChecker.
        ep_dirs = sorted(
            d for d in os.listdir(bdir)
            if os.path.isdir(os.path.join(bdir, d)) and not d.startswith(".")
            and not d.startswith(".stale")
        )
        if not ep_dirs:
            print(f"== {b}: no endpoint dirs ==")
            continue

        for ep in ep_dirs:
            epdir = os.path.join(bdir, ep)
            dumps = sorted(glob.glob(os.path.join(epdir, "dump_*.json")))
            if not dumps:
                continue

            runs = []
            crashed_types = {}
            for p in dumps:
                try:
                    d = json.load(open(p))
                except Exception as e:  # noqa: BLE001
                    print(f"  [skip] {p}: {e}")
                    continue
                runs.append(Run.from_dict(d))
                if d.get("error"):
                    t = d["error"].get("type", "?")
                    crashed_types[t] = crashed_types.get(t, 0) + 1

            try:
                r = CoverageChecker(runs).check_coverage()
            except Exception as e:  # noqa: BLE001
                print(f"== {b}/{ep}: checker error {e} ==")
                continue

            n_ok = sum(1 for run in runs if not run.error)
            summary = {
                "endpoint": ep,
                "batch": b,
                "runs_loaded": len(runs),
                "runs_completed_noerror": n_ok,
                "runs_crashed": len(runs) - n_ok,
                "crash_types": crashed_types,
                "coverage_complete": r.complete,
                "tree_nodes": r.total_nodes,
                "missing_branches": len(r.missing),
                "solver_lost": r.solver_lost,
                "solver_ms": r.elapsed_ms,
                "assumptions_used": r.assumptions_used,
            }
            summary["assumptions"] = r.assumptions_to_dict()
            summary["missing"] = [
                {"at": m.node_constraint, "loc": m.source_location,
                 "branch": m.missing_branch, "values": m.concrete_values,
                 "untracked": m.untracked}
                for m in r.missing
            ]
            # Write to the endpoint's own dir (not the batch root).
            out_path = os.path.join(epdir, "coverage_summary.json")
            with open(out_path, "w") as f:
                json.dump(summary, f, indent=2)

            print(f"  {b}/{ep:36s} {len(runs):2d} runs, {n_ok:2d} ok, "
                  f"complete={r.complete}, nodes={r.total_nodes:2d}, "
                  f"missing={len(r.missing):2d}{'  ' if not crashed_types else ' crashed=' + str(crashed_types)}")
            if r.assumptions_used:
                print(f"    assumptions used: {r.assumptions_used}")

    print("ALL_DONE")


if __name__ == "__main__":
    main()
