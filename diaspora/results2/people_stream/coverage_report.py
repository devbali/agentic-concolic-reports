#!/usr/bin/env python3
"""people_stream — per-entrypoint coverage check (results2 rerun).

Loads every dump in this directory (all three scenarios — anon_all,
anon_json, auth_json — write into the SAME directory per
results2/README.md), runs the engine's CoverageChecker, and writes
coverage_summary.json in the documented per-entrypoint format
(reports/diaspora/README.md "Reading the summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results2/people_stream/coverage_report.py
"""
import glob
import json
import os
import re
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

sys.path.insert(0, HERE)
from coverage_assumptions import build as build_assumptions  # noqa: E402


_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    """Batch-local dump fix (not a src/ change), ported VERBATIM from
    results2/people_show/coverage_report.py: `src/ruby_runtime/list.rb`
    names SymbolicList length vars literally `len(X)`. That is a valid Z3
    identifier request but not a valid Python identifier, and coverage.py's
    declaration builder generates Python source from the name (`f"{vn} =
    Int('{vn}')"`), so `len(X) = Int('len(X)')` is a SyntaxError -- the
    solver reports "cannot assign to function call here" and the checker
    (correctly, per its documented design) drops the expr into
    `unevaluable_exprs`, forcing `truncated=True`. Hit here by
    IterableSymbolicList's own length var (`§5b`,
    `SYM_RESULT_ActiveRecord__Relation_records_1_rows` /
    `SYM_RESULT_Stream__Base_post_ids_1` / the rendering content-type
    representative) in every json-format dump, regardless of the diaspora_id?
    fix -- unrelated to this completion pass's own change, pre-existing in
    every dump this endpoint has ever produced.

    COMPLETION_BRIEF.md is explicit that resting completeness on an
    exclusion is not done -- "fix the dumps so the expression becomes
    checkable" -- so this renames `len(X)` -> `SYM_LEN_X` (a normal
    identifier, same underlying variable, no semantic change) everywhere it
    appears in a dump's `symbolic_vars[].name` and `events[].expr` before the
    dump is fed to `Run.from_dict`. Pure surface-syntax, scoped to this
    endpoint's own copies of its own dumps; does not touch `src/`, the app,
    or the shared `concolic_targets.rb`.
    """
    s = json.dumps(dump)
    s2 = _LEN_RE.sub(r"SYM_LEN_\1", s)
    return json.loads(s2)


def main() -> int:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped = [], []
    dump_errors = Counter()
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            dump_errors[raw["error"].get("type", "Unknown")] += 1
        try:
            runs.append(Run.from_dict(fix_len_names(raw)))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)

    assumptions = build_assumptions()

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=256,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    summary = {
        "endpoint": "people_stream",
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "blocking_missing_branches": len(blocking),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "genuine": genuine,
        "vacuous": not genuine,
        "dumps_loaded": len(runs),
        "dumps_unparseable": skipped,
        "dump_errors": dict(dump_errors),
        "solver_lost": result.solver_lost,
        "truncated": bool(result.truncated),
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "assumptions": result.assumptions_to_dict(),
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

    out = os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs};"
          f"TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"ASSUMPTIONS_USED={result.assumptions_used}")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
