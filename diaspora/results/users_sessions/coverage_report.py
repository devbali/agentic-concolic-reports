#!/usr/bin/env python3
"""users_sessions — per-entrypoint coverage check.

For EVERY entrypoint subdirectory: load its dumps, run the engine's
CoverageChecker over that entrypoint's runs ONLY, and write its own
coverage_summary.json in the documented format (README "Reading the summary"),
plus the honesty fields this batch is required to report:

  path_conditions   total PC events across the entrypoint's dumps
  genuine           path_conditions > 0   (a 0-PC entrypoint is NOT covered,
                                           whatever `complete` says)
  errors            {error type: count} across the dumps

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results/users_sessions/coverage_report.py
"""
import glob
import json
import os
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402


def check(ep_dir):
    ep = os.path.basename(ep_dir)
    dumps = sorted(glob.glob(os.path.join(ep_dir, "dump_*.json")))
    existing = os.path.join(ep_dir, "coverage_summary.json")

    if not dumps:
        # Absent-from-app markers are written by run_dse.rb; keep them.
        if os.path.exists(existing):
            with open(existing) as fh:
                prev = json.load(fh)
            if prev.get("endpoint_absent_from_app"):
                return prev
        return None

    runs, skipped, pcs, errors = [], [], 0, Counter()
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"unparseable JSON: {type(e).__name__}: {e}"})
            continue
        pcs += sum(1 for ev in raw.get("events", []) if ev.get("type") == "path_condition")
        if raw.get("error"):
            errors[raw["error"]["type"]] += 1
        try:
            runs.append(Run.from_dict(raw))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p),
                            "error": f"{type(e).__name__}: {e}"})

    t0 = time.time()
    result = CoverageChecker(runs).check_coverage()
    wall = time.time() - t0
    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    explo = {}
    ep_summary = os.path.join(ep_dir, "exploration_summary.json")
    if os.path.exists(ep_summary):
        with open(ep_summary) as fh:
            explo = json.load(fh)

    summary = {
        "endpoint": ep,
        "coverage_complete": bool(result.complete),
        "genuine": pcs > 0,
        "path_conditions": pcs,
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "dumps_loaded": len(runs),
        "dumps_unparseable": skipped,
        "dump_errors": dict(errors),
        "solver_lost": result.solver_lost,
        "assumptions": [],
        "assumptions_used": result.assumptions_used,
        "checker_elapsed_seconds": round(wall, 1),
        "dse_worklist_exhausted": explo.get("worklist_exhausted"),
        "dse_stop_reason": explo.get("stop_reason"),
        "dse_runs_executed": explo.get("runs_executed"),
        "dse_unflippable_pcs": explo.get("unflippable_pcs", {}),
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
    return summary


def main():
    rows = []
    for name in sorted(os.listdir(HERE)):
        d = os.path.join(HERE, name)
        if not os.path.isdir(d) or name.startswith("."):
            continue
        s = check(d)
        if s is None:
            print(f"{name:34s} NO DUMPS")
            continue
        rows.append(s)

    print(f"\n{'entrypoint':34s} {'dumps':>5s} {'PCs':>5s} {'nodes':>5s} "
          f"{'miss':>5s} {'compl':>5s} {'genuine':>7s}  stop_reason / errors")
    for s in rows:
        if s.get("endpoint_absent_from_app"):
            print(f"{s['endpoint']:34s} {'-':>5s} {'-':>5s} {'-':>5s} {'-':>5s} "
                  f"{'-':>5s} {'ABSENT':>7s}  action does not exist in this app")
            continue
        print(f"{s['endpoint']:34s} {s['dumps_loaded']:5d} {s['path_conditions']:5d} "
              f"{s['tree_nodes']:5d} {s['missing_branches']:5d} "
              f"{str(s['coverage_complete']):>5s} {str(s['genuine']):>7s}  "
              f"{s.get('dse_stop_reason')} {s.get('dump_errors') or ''}")

    real = [s for s in rows if not s.get("endpoint_absent_from_app")]
    genuine = [s for s in real if s["genuine"]]
    print(f"\nentrypoints: {len(rows)} ({len(real)} present, {len(rows) - len(real)} absent)")
    print(f"genuine (>=1 PC): {len(genuine)}   vacuous (0 PC): {len(real) - len(genuine)}")
    print(f"complete=true: {sum(1 for s in real if s['coverage_complete'])}")
    print(f"complete AND genuine: {sum(1 for s in genuine if s['coverage_complete'])}")
    with open(os.path.join(HERE, "batch_coverage_summary.json"), "w") as fh:
        json.dump(rows, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
