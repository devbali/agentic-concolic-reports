#!/usr/bin/env python3
"""posts_show — per-entrypoint coverage check (results3 discipline rebuild).

Ported from results2/posts_show/coverage_report.py, with the fix_len_names
IterableSymbolicList `len(X)` name-mangling fix (ported verbatim from
results3/people_stream / results3/notifications_index — same defect,
independently hit here: this endpoint's targets.rb mints many `len(...)`-
named vars via IterableSymbolicList/rows_mock/pluck/ids, now used far more
heavily than in results2 since the render family executes for real), and the
fixed coverage_summary.json schema (main README.md "Reading the summary" —
coordinator directive, matches every other results2/results3 endpoint's key
set exactly, dropping results2's extra non-standard fields).

Loads every dump in this directory (all 4 scenarios — auth_html, anon_html,
auth_json, anon_json — write into the SAME directory per results3/README.md
layout), runs the engine's CoverageChecker, and writes coverage_summary.json.

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results3/posts_show/coverage_report.py
"""
import glob
import json
import logging
import os
import re
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

# PERF (batch-local, does not touch src/): concolic_engine.solver.check_satisfiability
# re-execs every merged Z3 declaration on EVERY call. With a large universe and
# max_missing_per_clique enumeration issuing many solver calls, repeated
# warning I/O measurably dominates wall time. Silencing the solver's logger
# changes no result, only the runtime (ported from results2/posts_show).
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

sys.path.insert(0, HERE)
from coverage_assumptions import build as build_assumptions  # noqa: E402


_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    """Ported verbatim from results3/people_stream + results3/notifications_index
    coverage_report.py (results2 dirs are read-only reference now — this copy
    is results3's own). `src/ruby_runtime/list.rb` names SymbolicList length
    vars literally `len(X)`, a valid Z3 identifier but not a valid Python
    one — coverage.py's declaration builder generates `len(X) = Int('len(X)')`,
    a SyntaxError, and the checker (correctly, by design) drops the expr into
    `unevaluable_exprs`, forcing `truncated=True`. This endpoint's targets.rb
    mints many such names (IterableSymbolicList's `len(...)_rows` vars on the
    Relation/CollectionProxy/pluck/ids mocks, now firing far more since the
    render family runs for real) — same defect. Renames `len(X)` -> `SYM_LEN_X`
    (a normal identifier, same underlying variable) everywhere in a dump's
    `symbolic_vars[].name` / `events[].expr` before `Run.from_dict`. Pure
    surface-syntax; does not touch src/, the app, or any concolic_targets.rb.
    """
    s = json.dumps(dump)
    s2 = _LEN_RE.sub(r"SYM_LEN_\1", s)
    return json.loads(s2)


_EV_CACHE: dict = {}
_SV_CACHE: dict = {}


def share_run_objects(run):
    """Flyweight-dedupe a Run's events and symbolic_vars across runs.

    2026-08-18: the corpus-wide load OOM-killed the coordinator (python3 at
    3.3GB RSS on a swapless 7.8GB box; this endpoint's ~17k dumps are the
    largest corpus). Events and vars repeat massively across runs;
    PathCondition/CallEvent/SymbolicCallEvent are frozen dataclasses and the
    engine never reads the per-run `idx` stamp, so sharing one instance
    across runs is safe and cuts resident memory ~20x (conversations_index:
    3,009 dumps loaded+checked in 150MB peak RSS with this in place).
    """
    run.events = [
        _EV_CACHE.setdefault(
            (type(ev).__name__, json.dumps(ev.to_dict(), sort_keys=True, default=str)),
            ev,
        )
        for ev in run.events
    ]
    run.symbolic_vars = [
        _SV_CACHE.setdefault(
            json.dumps(sv.to_dict(), sort_keys=True, default=str), sv
        )
        for sv in run.symbolic_vars
    ]
    run.concrete_values = {
        sys.intern(k): (sys.intern(v) if isinstance(v, str) else v)
        for k, v in run.concrete_values.items()
    }
    run.script = None
    return run


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
            runs.append(share_run_objects(Run.from_dict(fix_len_names(raw))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)
    if skipped:
        print(f"skipped(sample)={skipped[:10]}")

    assumptions = build_assumptions(runs)

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions,
        max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4")),
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (main README.md "Reading the summary" — matches every
    # other results2/results3 endpoint's key set exactly).
    summary = {
        "endpoint": "posts_show",
        "coverage_complete": bool(result.complete),
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "truncated": bool(result.truncated),
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
            for m in result.missing[:400]
        ],
    }

    out = os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"dumps_loaded={len(runs)};dumps_unparseable={len(skipped)}")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
