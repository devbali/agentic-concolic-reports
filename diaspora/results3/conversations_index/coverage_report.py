#!/usr/bin/env python3
"""conversations_index — per-entrypoint coverage check (results3 discipline rebuild).

Ported from results3/notifications_index/coverage_report.py (itself ported
from results2/notifications_index/coverage_report.py), unchanged except for
this docstring, the endpoint name, and (fix_len_names below) the
IterableSymbolicList/SampledList `len(X)` name-mangling fix.

Loads every dump in this directory (all four html/json x plain/withcid
variants write into the SAME directory per results3/README.md), runs the
engine's CoverageChecker, and writes coverage_summary.json in the documented
per-entrypoint format (reports/diaspora/README.md "Reading the summary").

2026-08-18 completion pass: `build_assumptions` now takes `runs` (posts_show's
coverage_report.py pattern) so coverage_assumptions.py's Tier 0 can group
exprs by variant label (html_plain/html_withcid/json_plain/json_withcid).

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results3/conversations_index/coverage_report.py
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

# PERF (batch-local, does not touch src/): ported from results3/posts_show --
# concolic_engine.solver.check_satisfiability re-execs every merged Z3
# declaration on EVERY call; with a large universe and max_missing_per_clique
# enumeration issuing many solver calls, repeated warning I/O measurably
# dominates wall time. Silencing the solver's logger changes no result.
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

sys.path.insert(0, HERE)
from coverage_assumptions import build as build_assumptions  # noqa: E402


# --- 2026-08-31 heartbeat instrumentation (A6-11, coordinator directive) ---
# A 15h32m silent per-clique enumeration under MMPC=2000 was invisible in the
# log ("loaded ... runs" then nothing). Two batch-local layers, no src/ edit:
#   (1) count every Z3 query by rebinding the COVERAGE MODULE's reference to
#       check_satisfiability (coverage.py does `from .solver import
#       check_satisfiability`, so the module global is the call-time lookup);
#   (2) a daemon thread prints phase/elapsed/solver-call/RSS at least every
#       10 minutes, so a stall is visible as non-advancing counters and a
#       hard hang as missing heartbeats (the outer wall-clock watcher fires
#       on stale log mtime).
import threading  # noqa: E402
import concolic_engine.coverage as _covmod  # noqa: E402

_PROGRESS = {"phase": "load", "solver_calls": 0, "t0": time.time()}
_orig_sat = _covmod.check_satisfiability


def _counted_sat(*a, **kw):
    _PROGRESS["solver_calls"] += 1
    return _orig_sat(*a, **kw)


_covmod.check_satisfiability = _counted_sat


def _heartbeat():
    import resource as _r
    while True:
        time.sleep(600)
        print(f"[hb] {time.strftime('%H:%M:%S')} phase={_PROGRESS['phase']} "
              f"elapsed={int(time.time() - _PROGRESS['t0']) // 60}m "
              f"solver_calls={_PROGRESS['solver_calls']} "
              f"rss={_r.getrusage(_r.RUSAGE_SELF).ru_maxrss // 1024}MB",
              flush=True)


threading.Thread(target=_heartbeat, daemon=True).start()


_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    """`src/ruby_runtime/list.rb` names SymbolicList length vars literally
    `len(X)`, a valid Z3 identifier but not a valid Python one — coverage.py's
    declaration builder generates `len(X) = Int('len(X)')`, a SyntaxError, and
    the checker (correctly, by design) drops the expr into
    `unevaluable_exprs`, forcing `truncated=True`. Rename `len(X)` ->
    `SYM_LEN_X` (a normal identifier, same underlying variable).

    2026-08-27 (OOM repair, coordinator directive): walk the parsed structure
    IN PLACE. The old version round-tripped every dump through
    json.dumps/json.loads, which doubled peak memory per dump and, at 22k
    dumps, is what OOM-killed the report. Only the fields the rename can
    appear in are touched (`symbolic_vars[].name`, `events[].expr`), and the
    fields the CoverageChecker never reads are DROPPED here (notes are large
    SQL strings; the note check and the SQL audits read the dump FILES, not
    these Run objects).
    """
    for sv in dump.get("symbolic_vars") or ():
        n = sv.get("name")
        if n and "len(" in n:
            sv["name"] = _LEN_RE.sub(r"SYM_LEN_\1", n)
        sv.pop("note", None)
    for ev in dump.get("events") or ():
        e = ev.get("expr")
        if e and "len(" in e:
            ev["expr"] = _LEN_RE.sub(r"SYM_LEN_\1", e)
        # fields the coverage tree does not read
        ev.pop("note", None)
        ev.pop("args", None)
        ev.pop("traceback", None)
    cv = dump.get("concrete_values")
    if isinstance(cv, dict):
        for k in [k for k in cv if "len(" in k]:
            cv[_LEN_RE.sub(r"SYM_LEN_\1", k)] = cv.pop(k)
    return dump


_EV_CACHE: dict = {}
_SV_CACHE: dict = {}


def apply_len_bounds(run):
    """A list length is a concrete row count (list.rb): declare the DOMAIN of
    every `len(...)` (renamed SYM_LEN_*) SymbolicVar as variable bounds so
    the checker's Z3 bounds carry it — not a SymbolicConstraintAssumption
    (coordinator directive 2026-08-26). low = 0 (never negative); high = 1
    because this batch's SampledList is a ONE-representative-row list
    (targets.rb: concrete_length is 0 or 1 — Gate 1b sampled content), so
    {0, 1, many} IS the variable's domain in this model after B-7 (2 stands
    for "many": content is still one representative row, but the CARDINALITY
    decides the preload's predicate shape and the app's multi-row branches).
    (coverage.py applies a bound only when both ends are given.)"""
    import dataclasses
    def bound(sv):
        if not sv.name.startswith("SYM_LEN_") or sv.low is not None:
            return sv
        # a beyond-the-last-page row list is empty by construction: domain {0}
        # B-7 (coordinator, 2026-08-28): every OTHER list's domain is
        # 0 / 1 / MANY, not {0, 1}. "many" is represented by 2 — the smallest
        # value that satisfies the app's own multi-row predicates
        # (`other_participants.count > 1`) and that makes a preload's
        # predicate an IN-list rather than an equality. Declaring high = 1 was
        # what made `(len(...) > 1)` unsatisfiable, so the multi-row branch
        # family was not merely unexplored — it was DECLARED impossible.
        hi = 0 if sv.name.endswith("_rows_beyond") else 2
        return dataclasses.replace(sv, low=0, high=hi)
    run.symbolic_vars = [bound(sv) for sv in run.symbolic_vars]
    return run


def share_run_objects(run):
    """Flyweight-dedupe a Run's events and symbolic_vars across runs.

    2026-08-18: the corpus-wide load OOM-killed the coordinator (python3 at
    3.3GB RSS on a swapless 7.8GB box). Events and vars repeat massively
    across runs; PathCondition/CallEvent/SymbolicCallEvent are frozen
    dataclasses and the engine never reads the per-run `idx` stamp, so
    sharing one instance across runs is safe and cuts resident memory ~10x.
    Keyed on to_dict() JSON (idx excluded from PathCondition/CallEvent dicts).
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
            with open(p) as fh:
                raw = json.load(fh)
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            dump_errors[raw["error"].get("type", "Unknown")] += 1
        try:
            runs.append(share_run_objects(apply_len_bounds(Run.from_dict(fix_len_names(raw)))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
        # free as we go: the parsed dump is dead once its Run exists
        # (2026-08-27 OOM repair)
        del raw

    import gc, resource
    gc.collect()
    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable); "
          f"peak RSS {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB", flush=True)
    if skipped:
        print(f"skipped={skipped}")

    _PROGRESS["phase"] = "assumptions"
    assumptions = build_assumptions(runs)

    _PROGRESS["phase"] = "check_coverage"
    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions,
        max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4"))
    ).check_coverage()
    wall = time.time() - t0
    _PROGRESS["phase"] = "post"

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (matches every other results2/results3 endpoint's
    # coverage_summary.json key set exactly — coordinator directive).
    summary = {
        "endpoint": "conversations_index",
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

    # Completion section (concolic_engine.completion, 2026-08-25): the
    # engine's "are the mocks complete?" verdict lives in the SAME final
    # report as "is exploration complete?". Runs when the batch carries a
    # completion_config.json; overall `complete` = both.
    cc_path = os.path.join(HERE, "completion_config.json")
    # SKIP_COMPLETION=1: coverage-only pass for the corpus-generation loop
    # (demand rounds); the FINAL report is always run without it.
    if os.path.exists(cc_path) and not os.environ.get("SKIP_COMPLETION"):
        from concolic_engine.completion import attach_to_summary
        with open(cc_path) as fh:
            attach_to_summary(summary, json.load(fh))
    else:
        # A coverage-only pass must NEVER leave a summary that claims
        # completeness (2026-08-27: a killed report left `complete: true`
        # with no completion section, and that file was read as a result).
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate did not run "
                                              "(coverage-only pass / SKIP_COMPLETION)"]}
        summary["complete"] = False

    out = os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"OVERALL_COMPLETE={summary['complete']};COMPLETION={'n/a' if summary['completion'] is None else summary['completion']['complete']}")
    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"dump_errors={dict(dump_errors)}")
    import resource as _res
    print(f"wrote {out} in {wall:.1f}s; peak RSS "
          f"{_res.getrusage(_res.RUSAGE_SELF).ru_maxrss // 1024} MB")
    return 0 if summary['complete'] else 1


if __name__ == "__main__":
    sys.exit(main())
