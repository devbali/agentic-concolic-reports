#!/usr/bin/env python3
"""notifications_index — per-entrypoint coverage check (results3 discipline rebuild).

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
    PYTHONPATH=src python3 reports/diaspora/results3/notifications_index/coverage_report.py
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


# RUNBOOK §4 (2026-08-27, revised by the coordinator): the HEAVY lock is held
# for the memory-heavy LOAD + Z3 COVERAGE pass only, and released before the
# completion section — the assumption gate is JRuby-bound and small, and
# holding heavy across a multi-hour gate starves every other batch. The gate's
# own probes still take the SLOT lock per launch (heavy -> slot ordering is
# preserved: this process never holds heavy while a probe runs).
import fcntl

_HEAVY_PATH = "/tmp/concolic-heavy.lock"


class HeavyLock:
    def __enter__(self):
        self._fh = open(_HEAVY_PATH, "w")
        t0 = time.time()
        fcntl.flock(self._fh, fcntl.LOCK_EX)
        waited = time.time() - t0
        if waited > 1:
            print(f"[heavy] acquired after {waited:.0f}s wait", flush=True)
        return self

    def __exit__(self, *exc):
        try:
            fcntl.flock(self._fh, fcntl.LOCK_UN)
            self._fh.close()
        except Exception:  # noqa: BLE001
            pass
        print("[heavy] released", flush=True)
        return False


_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump: dict) -> dict:
    """Ported VERBATIM from results2/people_stream/coverage_report.py (that
    directory is read-only reference now, per the results2-frozen-record
    directive — this copy is results3's own). `src/ruby_runtime/list.rb`
    names SymbolicList length vars literally `len(X)`, a valid Z3 identifier
    but not a valid Python one — coverage.py's declaration builder generates
    `len(X) = Int('len(X)')`, a SyntaxError, and the checker (correctly, by
    design) drops the expr into `unevaluable_exprs`, forcing `truncated=True`.
    results3/notifications_index's own `targets.rb` mints several such names
    (IterableSymbolicList's `len(...)_rows` vars, now also on the
    CollectionProxy #records/#load_target mocks) — same defect, hit here
    independently. Renames `len(X)` -> `SYM_LEN_X` (a normal identifier, same
    underlying variable) everywhere in a dump's `symbolic_vars[].name` /
    `events[].expr` before `Run.from_dict`. Pure surface-syntax; does not
    touch src/, the app, or any concolic_targets.rb.

    2026-08-27 (coordinator directive, ported from conversations_index): walk
    the parsed structure IN PLACE. The old version round-tripped every dump
    through json.dumps/json.loads, doubling peak memory per dump — at 22k
    dumps that OOM-killed the report (6.3 GB -> 608 MB after the port). Only
    the fields the rename can appear in are touched, and the fields the
    CoverageChecker never reads are DROPPED here (notes are large SQL strings;
    the note check and the SQL audits read the dump FILES, not these Runs).
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
    {0, 1} IS the variable's domain in this model. (coverage.py applies a
    bound only when both ends are given.)"""
    import dataclasses
    # Seeded int dispatch dimensions have a CLOSED domain (list.rb sampled
    # list length {0,1}; the STI type/post-STI seeds enumerate a fixed set of
    # subclasses) — declare it as SymbolicVar bounds so the checker never
    # demands an out-of-range value (e.g. SYM_NOTE_TYPE_PROFILE == 8, which
    # would make the "all 8 type compares False" combination spuriously
    # satisfiable). coverage.py applies a bound only when both ends are given.
    BOUNDS = {"SYM_NOTE_TYPE_PROFILE": (0, 7), "SYM_POST_STI": (0, 1)}
    # cycle 2: two length dimensions are no longer {0,1} — a list length is a
    # DECISION now (Rule T4 / adversary N1). `@notifications` (the paginated
    # to_ary list) has domain {0,1,3} and a preloaded association's row count
    # {0,1,4} (the `< 4` actors branch), so their high bound is the largest
    # value the runner can seed. Every other sampled list is still {0,1}.
    def _b(sv):
        if sv.name.startswith("SYM_LEN_") and sv.low is None:
            # B-7 (2026-08-28): EVERY sampled DB-relation list has the domain
            # {0, 1, 3} — "many" is a real state and the statement shape (`= ?`
            # vs `IN (…)`) depends on it. A PRELOADED association carries the
            # extra `>= 4` arm (notifications_helper.rb:63 `number_of_actors < 4`).
            # Non-relation `len(...)` vars (a pluck's projection, the render
            # probes) keep {0, 1}.
            hi = 1
            if sv.name.endswith("_row_rows") or "_row_actors_" in sv.name:
                hi = 4
            elif sv.name.endswith("_rows"):
                hi = 3
            return dataclasses.replace(sv, low=0, high=hi)
        if sv.name in BOUNDS and sv.low is None:
            lo, hi = BOUNDS[sv.name]
            return dataclasses.replace(sv, low=lo, high=hi)
        return sv
    run.symbolic_vars = [_b(sv) for sv in run.symbolic_vars]
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
    # C7 (2026-09-01): DUMP_SAMPLE=N runs the pass over a RANDOM sample of N
    # dumps. Random, not `sorted(...)[:N]` — a prefix of the sorted list is
    # biased by FILENAME, which is how an 8 000-dump "sample" of a 26 528-dump
    # corpus turned out to be almost purely one scenario (DISCIPLINE 14).
    # The population and the sample size are printed so no number from a
    # sampled pass can be quoted as a whole-corpus number by accident.
    _sample = int(os.environ.get("DUMP_SAMPLE", "0"))
    print(f"corpus POPULATION: {len(dumps)} dump files", flush=True)
    if _sample and _sample < len(dumps):
        import random as _rnd
        _rnd.seed(int(os.environ.get("DUMP_SAMPLE_SEED", "20260901")))
        dumps = sorted(_rnd.sample(dumps, _sample))
        print(f"SAMPLED PASS: {len(dumps)} of that population, random, "
              f"seed={os.environ.get('DUMP_SAMPLE_SEED', '20260901')} — "
              f"every number below is a SAMPLE statistic, not a corpus total",
              flush=True)

    heavy = HeavyLock()
    heavy.__enter__()
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
            runs.append(share_run_objects(apply_len_bounds(Run.from_dict(fix_len_names(raw)))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
        # free as we go: the parsed dump is dead once its Run exists
        del raw

    import gc, resource
    gc.collect()
    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable); "
          f"peak RSS {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB", flush=True)
    if skipped:
        print(f"skipped={skipped}")

    assumptions = build_assumptions(runs)

    # C7 (2026-09-01) — HEARTBEAT. The Z3/combination phase writes nothing for
    # as long as it runs, so "alive and busy" and "wedged" look identical from
    # outside; a 49-minute silent pass had to be diagnosed from /proc. The
    # checker itself is in src/ and is not ours to instrument, so a daemon
    # thread prints elapsed / RSS / CPU from OUTSIDE it. Silence now means
    # something.
    import threading, resource as _res
    _hb_stop = threading.Event()

    def _heartbeat(started):
        n = 0
        while not _hb_stop.wait(float(os.environ.get("HEARTBEAT_SECS", "300"))):
            n += 1
            ru = _res.getrusage(_res.RUSAGE_SELF)
            print(f"[heartbeat {n}] coverage phase alive: "
                  f"elapsed {time.time() - started:.0f}s, "
                  f"RSS {ru.ru_maxrss // 1024} MB, "
                  f"CPU {ru.ru_utime + ru.ru_stime:.0f}s "
                  f"({len(runs)} runs, {len(assumptions)} assumptions, "
                  f"max_missing_per_clique="
                  f"{os.environ.get('MAX_MISSING_PER_CLIQUE', '4')})", flush=True)

    t0 = time.time()
    threading.Thread(target=_heartbeat, args=(t0,), daemon=True).start()
    try:
        result = CoverageChecker(
            runs, assumptions=assumptions,
            max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4"))
        ).check_coverage()
    finally:
        _hb_stop.set()
    wall = time.time() - t0
    print(f"[coverage] phase done in {wall:.0f}s", flush=True)
    # coverage/Z3 done — the rest (completion: shims, note check, assumption
    # gate) is not memory-heavy, so release heavy before it.
    heavy.__exit__()

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (matches every other results2/results3 endpoint's
    # coverage_summary.json key set exactly — coordinator directive).
    summary = {
        "endpoint": "notifications_index",
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
        # MISSING_CAP (cycle 6): the demand loop can only aim at the entries
        # that reach the JSON, so the convergence rounds raise the cap; the
        # final report keeps the documented 200 for file size.
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "source_location": m.source_location,
                "untracked": bool(getattr(m, "untracked", False)),
                "concrete_values": m.concrete_values,
            }
            for m in result.missing[:int(os.environ.get("MISSING_CAP", "200"))]
        ],
    }

    # Completion section (concolic_engine.completion, 2026-08-25): the
    # engine's "are the mocks complete?" verdict lives in the SAME final
    # report as "is exploration complete?". Runs when the batch carries a
    # completion_config.json; overall `complete` = both.
    # MEMORY (cycle 6, 2026-08-29): the COMPLETION section spawns JRuby (shim
    # tests, the assumption gate's probes) INSIDE this process's cgroup, while
    # this process still held every parsed Run — at 43 519 runs that put the
    # unit over MemoryMax=6G and the report was OOM-killed after the coverage
    # phase had already succeeded. Nothing below reads the Runs (the note check
    # and the audits read the dump FILES), so free them first.
    runs = None
    _EV_CACHE.clear()
    _SV_CACHE.clear()
    gc.collect()
    print(f"[mem] runs released before completion; RSS "
          f"{resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB peak", flush=True)

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
