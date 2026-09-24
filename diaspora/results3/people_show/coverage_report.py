#!/usr/bin/env python3
"""people_show — per-entrypoint coverage check (results3 discipline rebuild).

Ported from results3/people_stream/coverage_report.py (itself from
results2/people_stream), unchanged except for this docstring and the
endpoint name below. The IterableSymbolicList `len(X)` name-mangling fix
(fix_len_names) is kept — people_show's CollectionProxy/pluck mocks
(targets.rb) mint the same `len(...)`-named vars.

Loads every dump in this directory (the "anon_handle"/"anon_json" scenarios
both write into the SAME directory per results3/README.md), runs the
engine's CoverageChecker, and writes coverage_summary.json in the documented
per-entrypoint format (reports/diaspora/README.md "Reading the summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results3/people_show/coverage_report.py
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

    # -----------------------------------------------------------------------
    # WITHDRAWN CONFINED PAIRS (§16c, coverage.py:298-299). Confinement is
    # INFERRED by the checker, not declared by a person, so an inferred pair
    # that the assumption gate FAILS — or that the gate could not VERIFY
    # (NOT-TESTABLE/NOT-COMPARABLE/ERROR) — is withdrawn by replay evidence:
    #
    #   "anything else on an INFERRED pair (FAIL, or a probe the gate could not
    #    run) withdraws it, blocks `complete` and is fed back as
    #    `withdrawn_pairs` so the next pass never licenses it again."
    #
    # THIS LEDGER IS THE FEED-BACK. It is a persistent batch-local file, not a
    # per-run value, because the contract is "never licenses it AGAIN".
    # Withdrawing a pair EXPANDS demand (the pair no longer removes edges from
    # evaluation sets), so this can only make MISSING larger — it is the
    # opposite of closing the endpoint by assumption.
    #
    # 2026-09-19: the first real gate run on people_show withdrew 8 of the 9
    # inferred pairs (4 FAIL + 4 NOT-TESTABLE); the coverage numbers of that
    # pass were computed with them licensed and the engine marked them STALE.
    # -----------------------------------------------------------------------
    wp_path = os.path.join(HERE, "_withdrawn_pairs.json")
    withdrawn = []
    if os.path.exists(wp_path):
        with open(wp_path) as fh:
            withdrawn = [tuple(x) for x in json.load(fh)]
        print(f"[coverage_report] withdrawn confined pairs fed back: {len(withdrawn)}")

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=4,
        withdrawn_pairs=withdrawn,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (matches every other results2/results3 endpoint's
    # coverage_summary.json key set exactly — coordinator directive).
    summary = {
        "endpoint": "people_show",
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
        "withdrawn_pairs_fed_back": len(withdrawn),
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
    # COMPLETION SECTION (concolic_engine.completion) — added 2026-09-19.
    # people_show had NO completion wiring of any kind until this build: no
    # `completion_config.json`, no shim tests, no concrete run, no assumption
    # manifest, and this file was an older port with no hook at all, so its
    # summaries carried neither `completion` nor `complete`. Ported from
    # results3/people_stream/coverage_report.py:183-240.
    #
    # A counterfactual pass (`NO_PINS=1`, which REQUIRES `SUMMARY_OUT`) must
    # never run the gate: it would re-run the shim tests, the note check and
    # the assumption driver only to write them into a scratch file, and the
    # gate writes `_assumption_results.json` / `_shim_results.json` INTO the
    # batch, so the counterfactual would clobber the shipped run's evidence.
    # A summary that skipped the gate is marked NOT complete either way, which
    # is the honest direction.
    # -----------------------------------------------------------------------
    cc_path = os.path.join(HERE, "completion_config.json")
    _counterfactual = bool(os.environ.get("NO_PINS") or os.environ.get("SUMMARY_OUT"))
    if os.environ.get("SKIP_COMPLETION") == "1":
        summary["completion"] = None
        summary["complete"] = False
        print("[coverage_report] SKIP_COMPLETION=1: completion section not run; "
              "complete forced False")
    elif _counterfactual:
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate not run: this is a "
                                              "COUNTERFACTUAL pass (NO_PINS/SUMMARY_OUT), "
                                              "which must not overwrite the shipped run's "
                                              "shim/assumption evidence"]}
        summary["complete"] = False
        print("[coverage_report] counterfactual pass: completion section not run; "
              "complete forced False")
    elif os.path.exists(cc_path):
        from concolic_engine.completion import attach_to_summary
        with open(cc_path) as fh:
            attach_to_summary(summary, json.load(fh))
        # Persist any pair this pass withdrew, so the NEXT pass starts with it
        # already un-licensed (the "never again" half of the contract above).
        _new = [tuple(x) for x in
                ((summary.get("completion", {}).get("assumptions") or {})
                 .get("confinement_withdrawn") or ())]
        if _new:
            _merged = sorted({tuple(x) for x in withdrawn} | set(_new))
            with open(wp_path, "w") as fh:
                json.dump([list(x) for x in _merged], fh, indent=1)
            print(f"[coverage_report] withdrawn-pair ledger now holds {len(_merged)} "
                  f"pair(s) ({len(_new)} reported by this pass)")
    else:
        # A coverage-only pass must NEVER leave a summary that claims
        # completeness (2026-08-27: a killed report left `complete: true`
        # with no completion section, and that file was read as a result).
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate did not run "
                                              "(coverage-only pass / no "
                                              "completion_config.json)"]}
        summary["complete"] = False

    if os.environ.get("NO_PINS") and not os.environ.get("SUMMARY_OUT"):
        print("NO_PINS requires SUMMARY_OUT (it must not overwrite the "
              "shipped coverage_summary.json)", file=sys.stderr)
        return 2
    out = os.environ.get("SUMMARY_OUT") or os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False, default=str)

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
          f"FORECLOSURES={getattr(result, 'foreclosures', None)}")
    for _tm in getattr(result, "tree_missing", ()):
        print(f"   TREE-MISSING {_tm}")
    import resource as _res
    print(f"peak RSS {_res.getrusage(_res.RUSAGE_SELF).ru_maxrss // 1024} MB")
    print(f"dump_errors={dict(dump_errors)}")
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if summary["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
