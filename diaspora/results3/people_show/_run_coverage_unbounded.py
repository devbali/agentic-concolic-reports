#!/usr/bin/env python3
"""UNBOUNDED coverage check for people_show (results3) — Bali directive
2026-09-04 03:32/04:02: remove the truncation (max_missing_per_clique /
max_cliques) so the solver runs to TRUE completion and either finds the
SAT runs it wants or proves UNSAT. Hard timeout is applied OUTSIDE
(timeout 3600 in the wrapper). Writes the FULL missing list with
concrete_values (the z3 model) so each missing item can be replayed as
a concrete seed run.

Usage: python3 _run_coverage_unbounded.py
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402
import coverage_assumptions  # noqa: E402


_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    """Same len(X)->SYM_LEN_X rename as coverage_report.py (see there)."""
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


def main() -> int:
    dumps = sorted(os.path.join(HERE, f) for f in os.listdir(HERE)
                   if f.startswith("dump_") and f.endswith(".json"))
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped, dump_errors = [], [], {}
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            err = raw["error"].get("type", "Unknown") if isinstance(raw["error"], dict) else "Unknown"
            dump_errors[err] = dump_errors.get(err, 0) + 1
        try:
            runs.append(Run.from_dict(fix_len_names(raw)))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)

    assumptions = coverage_assumptions.build()
    print(f"assumptions: {len(assumptions.assumptions)} total", flush=True)

    t0 = time.time()
    # UNBOUNDED: raise both caps to 10**9; hard timeout applied outside.
    result = CoverageChecker(
        runs, assumptions=assumptions,
        max_missing_per_clique=10**9,
        max_cliques=10**9,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]
    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0

    summary = {
        "endpoint": "people_show",
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "truncated": result.truncated,
        "solver_lost": result.solver_lost,
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "dump_errors": dump_errors,
        "assumptions": result.assumptions_to_dict(),
        "assumptions_used": result.assumptions_used,
        "wall_seconds": round(wall, 1),
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "source_location": m.source_location,
                "untracked": bool(getattr(m, "untracked", False)),
                "concrete_values": m.concrete_values,
            }
            for m in result.missing
        ],
    }
    out = os.path.join(HERE, "coverage_summary_unbounded.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(
        f"COMPLETE={result.complete};NODES={result.total_nodes};"
        f"MISSING={len(result.missing)};BLOCKING={len(blocking)};"
        f"PCS={total_pcs};TRUNCATED={result.truncated};"
        f"SOLVER_LOST={result.solver_lost};"
        f"ASSUMPTIONS_USED={result.assumptions_used};WALL={wall:.1f}s",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())