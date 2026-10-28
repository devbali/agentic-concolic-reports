#!/usr/bin/env python3
"""people_stream — per-entrypoint coverage check (results3 discipline rebuild).

Ported from results2/people_stream/coverage_report.py, unchanged except
for this docstring and (see fix_len_names note below, ported from
results2/people_stream) the IterableSymbolicList `len(X)` name-mangling fix,
needed here now that the type-dispatch representative/CollectionProxy mocks
add more `len(...)`-named vars to the universe.

Loads every dump in this directory (the "plain"/"typed"/"unread_only"
request scenarios all write into the SAME directory per results3/README.md),
runs the engine's CoverageChecker, and writes coverage_summary.json in the
documented per-entrypoint format (reports/diaspora/README.md "Reading the
summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results3/people_stream/coverage_report.py
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
    """Ported VERBATIM from results2/people_stream/coverage_report.py (that
    directory is read-only reference now, per the results2-frozen-record
    directive — this copy is results3's own). `src/ruby_runtime/list.rb`
    names SymbolicList length vars literally `len(X)`, a valid Z3 identifier
    but not a valid Python one — coverage.py's declaration builder generates
    `len(X) = Int('len(X)')`, a SyntaxError, and the checker (correctly, by
    design) drops the expr into `unevaluable_exprs`, forcing `truncated=True`.
    results3/people_stream's own `targets.rb` mints several such names
    (IterableSymbolicList's `len(...)_rows` vars, now also on the
    CollectionProxy #records/#load_target mocks) — same defect, hit here
    independently. Renames `len(X)` -> `SYM_LEN_X` (a normal identifier, same
    underlying variable) everywhere in a dump's `symbolic_vars[].name` /
    `events[].expr` before `Run.from_dict`. Pure surface-syntax; does not
    touch src/, the app, or any concolic_targets.rb.
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
    if skipped:
        print(f"skipped={skipped}")

    assumptions = build_assumptions()

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=4
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (matches every other results2/results3 endpoint's
    # coverage_summary.json key set exactly — coordinator directive).
    summary = {
        "endpoint": "people_stream",
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "truncated": result.truncated,
        "solver_lost": result.solver_lost,
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "dump_errors": dict(dump_errors),
        "assumptions": result.assumptions_to_dict(),
        "assumptions_used": result.assumptions_used,
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
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
