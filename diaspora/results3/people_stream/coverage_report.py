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



# ---------------------------------------------------------------------------
# Alias canonicalization at LOAD (ported from notifications_index,
# 2026-09-09). Rewrites ordinal-named list reads to `<stem>_<table>_<hash of
# the statement key>` — binds kept verbatim, literals wildcarded — so the same
# fact is the same variable on every path. Applied to symbolic_vars, PC exprs,
# result names, notes and concrete_values BEFORE fix_len_names (which drops
# notes). `concolic_seeds` is left ordinal-named: it is what the RUNTIME
# consumes, and the demand seeder maps back through this map.
# ---------------------------------------------------------------------------
from concolic_engine.assumptions import alias_map_for, renamer  # noqa: E402
from coverage_assumptions import ALIASES  # noqa: E402


def alias_map(dump: dict, aliases=None) -> dict:
    events = [(ev.get("result_name"), ev.get("note"))
              for ev in dump.get("events") or () if ev.get("type") == "symbolic_call"]
    return alias_map_for(events, aliases or ALIASES)


def canonicalize_ordinals(dump: dict, aliases=None) -> dict:
    amap = alias_map(dump, aliases)
    if not amap:
        return amap
    rn = renamer(amap)
    for sv in dump.get("symbolic_vars") or ():
        sv["name"] = rn(sv.get("name"))
        if sv.get("note"):
            sv["note"] = rn(sv["note"])
    for ev in dump.get("events") or ():
        for k in ("expr", "result_name", "note"):
            if ev.get(k):
                ev[k] = rn(ev[k])
    cv = dump.get("concrete_values")
    if isinstance(cv, dict):
        dump["concrete_values"] = {rn(k): v for k, v in cv.items()}
    for sr in dump.get("symbolic_results") or ():
        if sr.get("name"):
            sr["name"] = rn(sr["name"])
    return amap


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
            canonicalize_ordinals(raw)
            runs.append(Run.from_dict(fix_len_names(raw)))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)
    if skipped:
        print(f"skipped={skipped}")

    assumptions = build_assumptions(runs)

    # -----------------------------------------------------------------------
    # CONFINEMENT FEEDBACK (§16c, wired 2026-09-23). Confined pairs are
    # INFERRED by the engine, never declared here — `coverage_assumptions.py`
    # declares 30 and the checker appends whatever pairs this corpus licenses.
    # The engine's own protocol (coverage.py, "The gate, end to end"): a pair
    # the assumption gate FAILs is withdrawn, blocks `complete`, "and is fed
    # back as `withdrawn_pairs` so the next pass never licenses it again."
    # That feedback leg was NEVER wired in this batch's driver, so a FAILed
    # inferred pair could not clear: every pass re-inferred it, the gate
    # re-refuted it, and `complete` stayed False with the coverage numbers
    # marked STALE (the 2026-09-19 fullgate).
    #
    # `confinement_withdrawn.json` is that feedback file: the pairs this
    # endpoint's gate has REFUTED BY REPLAY. Replay evidence outranks corpus
    # inference (coverage.py's own wording), so they are never licensed again
    # and the demand they used to prune is restored — which is the
    # CONSERVATIVE direction (demand grows, never shrinks). Each pair is
    # justified in CONFINEMENT_WITHDRAWN.md with the gate's refutation class.
    # -----------------------------------------------------------------------
    wpath = os.environ.get("WITHDRAWN_PAIRS") or os.path.join(
        HERE, "confinement_withdrawn.json")
    withdrawn_pairs = []
    if os.path.exists(wpath):
        with open(wpath) as fh:
            # Two accepted shapes: a bare `[[a, b], ...]`, or the RECORD form
            # `[{"pair": [a, b], "withdrawn_by": ..., "refutation": ...}, ...]`
            # — the record form is the one this batch ships, so the gate's own
            # refutation text travels WITH the withdrawal and the file is a
            # cited argument rather than a bare list of strings.
            withdrawn_pairs = [
                tuple(p["pair"] if isinstance(p, dict) else p)
                for p in json.load(fh)]
        print(f"[confinement] {len(withdrawn_pairs)} pair(s) WITHDRAWN by prior "
              f"gate replay; never licensed again ({os.path.basename(wpath)})",
              flush=True)

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=4,
        withdrawn_pairs=withdrawn_pairs,
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
        # 2026-09-10 (DISCIPLINE §16): the demand universe is now the maximal
        # OBSERVED EVALUATION SETS, and the combination claim is CONDITIONAL on
        # the tree layer being complete. Both are reported so a summary says
        # what its `coverage_complete` was a claim about.
        "demand_sets": getattr(result, "demand_sets", None),
        "tree_complete": getattr(result, "tree_complete", None),
        "tree_missing": list(getattr(result, "tree_missing", ()))[:200],
        # 2026-09-10 (DISCIPLINE §16b): foreclosure is INFERRED from the
        # corpus, never declared. Reported so a pass says what demand universe
        # its numbers were computed over.
        "foreclosures": getattr(result, "foreclosures", None),
        "foreclosures_ignored": getattr(result, "foreclosures_ignored", None),
        "foreclosures_provisional": getattr(result, "foreclosures_provisional", None),
        "foreclosure_gates": [list(g) for g in getattr(result, "foreclosure_gates", ())][:20],
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

    # -----------------------------------------------------------------------
    # Completion section (concolic_engine.completion) — PORTED VERBATIM from
    # results3/comments_index/coverage_report.py (2026-09-10 closure drive).
    # The engine's "are the mocks complete?" verdict lives in the SAME final
    # report as "is exploration complete?"; overall `complete` = both.
    # people_stream had NO completion wiring at all until this drive (declared
    # gap X5), so `SKIP_COMPLETION` was a no-op and no OVERALL_COMPLETE= line
    # existed on this endpoint.
    #
    # ONE endpoint-specific addition to the ported block: a counterfactual pass
    # (`NO_PINS=1`, which REQUIRES `SUMMARY_OUT`) must never run the completion
    # gate — it would re-run the shim tests, the note check and the assumption
    # driver only to write them into a scratch file, and worse, the gate writes
    # `_assumption_results.json` / `_shim_results.json` into the batch, so the
    # counterfactual would clobber the shipped run's evidence. A summary that
    # skipped the gate is marked NOT complete either way, which is the honest
    # direction (comments_index 2026-08-27: a killed report left
    # `complete: true` with no completion section and was read as a result).
    # -----------------------------------------------------------------------
    cc_path = os.path.join(HERE, "completion_config.json")
    _counterfactual = bool(os.environ.get("NO_PINS") or os.environ.get("SUMMARY_OUT"))
    if os.environ.get("SKIP_COMPLETION") == "1":
        # demand-round iteration: exploration verdict only (the FINAL report
        # is always produced without this switch — completion gate included)
        summary["completion"] = None
        summary["complete"] = False
        print("[coverage_report] SKIP_COMPLETION=1: completion section not run; complete forced False")
    elif _counterfactual:
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate not run: this is a "
                                              "COUNTERFACTUAL pass (NO_PINS/SUMMARY_OUT), "
                                              "which must not overwrite the shipped run's "
                                              "shim/assumption evidence"]}
        summary["complete"] = False
        print("[coverage_report] counterfactual pass: completion section not run; complete forced False")
    elif os.path.exists(cc_path):
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

    # SUMMARY_OUT (2026-09-10) — the COUNTERFACTUAL half of the overnight pin
    # (Argument 5b in coverage_assumptions.py) must be measurable without
    # clobbering the shipped summary, so `NO_PINS=1` REQUIRES it.
    if os.environ.get("NO_PINS") and not os.environ.get("SUMMARY_OUT"):
        print("NO_PINS requires SUMMARY_OUT (it must not overwrite the "
              "shipped coverage_summary.json)", file=sys.stderr)
        return 2
    out = os.environ.get("SUMMARY_OUT") or os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"OVERALL_COMPLETE={summary['complete']};"
          f"COMPLETION={'n/a' if summary['completion'] is None else summary['completion']['complete']}")
    if summary.get("completion"):
        for _a in summary["completion"].get("audits", ()):
            print(f"   AUDIT {'green' if _a['green'] else 'RED  '}    {_a['name']}")
        for _v in summary["completion"].get("shims", ()):
            print(f"   SHIM  {_v['verdict']:<20} {_v['key']}")
        if summary["completion"].get("note_check") is not None:
            print(f"   NOTE-CHECK   {'green' if summary['completion']['note_check']['green'] else 'RED'}")
        if summary["completion"].get("assumptions") is not None:
            _ac = summary["completion"]["assumptions"]
            print(f"   ASSUMPTIONS  {'green' if _ac['green'] else 'RED'} "
                  f"(declared {_ac['declared']}, distinct tested {_ac['distinct_tested']}, "
                  f"{_ac['verdict_counts']})")
        for _b in summary["completion"].get("blocking", ()):
            print(f"   BLOCKING  {_b}")
    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"DEMAND_SETS={getattr(result, 'demand_sets', None)};"
          f"TREE_COMPLETE={getattr(result, 'tree_complete', None)};"
          f"TREE_MISSING={len(getattr(result, 'tree_missing', ()))};"
          f"FORECLOSURES={getattr(result, 'foreclosures', None)};"
          f"FORECL_IGNORED={getattr(result, 'foreclosures_ignored', None)};"
          f"FORECL_PROVISIONAL={getattr(result, 'foreclosures_provisional', None)}")
    for _tm in getattr(result, "tree_missing", ()):
        print(f"   TREE-MISSING {_tm}")
    for _g, _n in list(getattr(result, "foreclosure_gates", ()))[:10]:
        print(f"   FORECLOSURE-GATE {_n:5d}  {_g}")
    import resource as _res
    print(f"peak RSS {_res.getrusage(_res.RUSAGE_SELF).ru_maxrss // 1024} MB")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if summary["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
