#!/usr/bin/env python3
"""comments_index — per-entrypoint coverage check (results3 discipline rebuild).

Ported from results3/notifications_index/coverage_report.py (itself ported
from results2/notifications_index/coverage_report.py), including the
`fix_len_names` helper: this endpoint's ./targets.rb also mints IterableSymbolicList
`len(X)`-named vars (the design-#4 Relation/CollectionProxy row-count mocks),
which are a valid Z3 identifier but not a valid Python one — coverage.py's
declaration builder would otherwise SyntaxError building `len(X) = Int(...)`
and silently drop the expr into unevaluable_exprs. Renames `len(X)` ->
`SYM_LEN_X` (same underlying variable, normal identifier) before Run.from_dict.

Loads every dump in this directory, runs the engine's CoverageChecker under
combination-coverage semantics (src/concolic_engine/coverage.py) with this
directory's coverage_assumptions.py, and writes coverage_summary.json in the
documented FIXED-SCHEMA per-entrypoint format (reports/diaspora/README.md
"Reading the summary").

Usage:
    cd /home/dev/project
    PYTHONPATH=src python3 reports/diaspora/results3/comments_index/coverage_report.py
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
    """Rename `len(X)` -> `SYM_LEN_X` (list.rb names length vars literally
    `len(X)`: a valid Z3 identifier, not a valid Python one, so coverage.py's
    declaration builder SyntaxErrors and drops the expr into unevaluable_exprs).

    2026-08-27 LEAN LOADER (coordinator directive, ported from
    conversations_index after this batch's report was OOM-killed at 21,623
    dumps): walk the parsed structure IN PLACE — the old json.dumps/json.loads
    round-trip doubled peak memory per dump — and DROP the fields the coverage
    tree never reads (`note` is a large SQL string, plus `args`/`traceback`).
    The note check, the note-fidelity audit, the assumption gate and the SQL
    audits all read the dump FILES, not these Run objects, so nothing is lost.
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
        # C1 — TRACE CURRENCY (2026-09-13, docs/CONFINEMENT_PRECISION_20260913.md
        # §2, tools/_c1_currency_patch.md). `note` and `args` are the OTHER TWO
        # THIRDS of `concolic_engine.assumptions.call_shape`, which is the only
        # thing the engine reads them for (coverage.py, one call site). Popping
        # them made the §16c footprint currency the bare TARGET NAME while the
        # assumption gate's `access_trace` stayed on the full shape: 13 distinct
        # shapes here against the gate's 22, so `WHERE guid = ?` and
        # `WHERE id = ?` at one target were ONE shape and a real effect was
        # invisible to the differential. Measured cost of keeping them on this
        # batch's 26 528 dumps, with `share_run_objects` already deduplicating:
        # peak RSS 1 413 -> 1 451 MB (+2.7 %), load 177 -> 181 s. The 2026-08-27
        # OOM this optimisation answered was the json.dumps/loads round trip,
        # which is still gone; only the two pops are.
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
    every `len(...)` (renamed SYM_LEN_*) SymbolicVar as variable bounds so the
    checker's Z3 bounds carry it — not a SymbolicConstraintAssumption
    (coordinator directive 2026-08-26). low = 0; high = 2 since adversary round
    4 (N4-3): the IterableSymbolicList still carries ONE representative row —
    the Gate-1b limit on row CONTENT is unchanged — but its CARDINALITY is now
    modelled as 0 / 1 / MANY, because the real Preloader emits `col = ?` for
    one owner row and `col IN (…)` for two or more, and the corpus has to be
    able to say which. 2 IS "two or more", so {0, 1, 2} is the domain."""
    import dataclasses
    run.symbolic_vars = [
        dataclasses.replace(sv, low=0, high=2) if sv.name.startswith("SYM_LEN_") and sv.low is None else sv
        for sv in run.symbolic_vars
    ]
    return run


def share_run_objects(run):
    """Flyweight-dedupe events/symbolic_vars across runs (frozen dataclasses;
    the engine never reads the per-run idx) — the four-variant corpus would
    otherwise not fit the swapless box (ported from conversations_index)."""
    run.events = [
        _EV_CACHE.setdefault((type(ev).__name__, json.dumps(ev.to_dict(), sort_keys=True, default=str)), ev)
        for ev in run.events
    ]
    run.symbolic_vars = [
        _SV_CACHE.setdefault(json.dumps(sv.to_dict(), sort_keys=True, default=str), sv)
        for sv in run.symbolic_vars
    ]
    return run


def main() -> int:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped = [], []
    dump_errors = Counter()
    # OUTCOME-MAP DEDUPE (cycle 3, 2026-08-27): CoverageChecker consumes each
    # run as its map expr -> {polarities observed} (coverage.py step 1: it
    # builds `run_outcomes` and one blocking clause per run); two runs with
    # the SAME map are interchangeable for every verdict it makes. The
    # demand rounds produce many runs that share an outcome map (different
    # seeds, same decisions), and holding them all OOM-killed the 6.2G unit
    # at 16k dumps on this shared box. Signature is computed from the RAW
    # json (no Run object built for a duplicate), so peak memory is the
    # distinct-map count, not the dump count. Sound: nothing the checker
    # reads is dropped — the FULL corpus is still what the note check,
    # assumption gate, audits and hardening lint read from disk.
    seen_sigs = set()
    duplicates = 0
    for p in dumps:
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            dump_errors[raw["error"].get("type", "Unknown")] += 1
        sig = {}
        for ev in raw.get("events") or []:
            if ev.get("type") == "path_condition":
                sig.setdefault(ev["expr"], set()).add(bool(ev.get("taken")))
        sig = frozenset((e, frozenset(v)) for e, v in sig.items())
        if sig in seen_sigs:
            duplicates += 1
            continue
        seen_sigs.add(sig)
        try:
            runs.append(share_run_objects(apply_len_bounds(Run.from_dict(fix_len_names(raw)))))
            del raw
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})

    print(f"loaded {len(runs)} runs ({duplicates} duplicate outcome-maps skipped, "
          f"{len(skipped)} unparseable)", flush=True)
    if skipped:
        print(f"skipped={skipped}")

    assumptions = build_assumptions(runs)  # cycle 3: tier-derived from the corpus (see coverage_assumptions.py)

    # -----------------------------------------------------------------------
    # CONFINEMENT CROSS-PASS LOOP (DISCIPLINE §16c), wired 2026-09-13 —
    # PORTED from posts_show/coverage_report.py (itself ported from
    # notifications_index's, the first copy that had it). What was missing
    # HERE, stated exactly:
    #
    #   * The engine has applied §16c on this endpoint since it landed —
    #     `CoverageChecker`'s defaults are confinement=True, strict=True,
    #     keying="coevaluated", gates=True, or_sharing=True — so the
    #     2026-09-13 restoring pass was already OR-refined. What this file
    #     lacked was (a) the CROSS-PASS LOOP, so the 15 pairs the assumption
    #     gate FAILed could never be fed back, and (b) the measurement knobs
    #     the three-way verification of that FAIL needs.
    #
    #   withdrawn_pairs= — every inferred pair the ASSUMPTION GATE did not
    #     PASS (`summary["confinement_withdrawn_by_gate"]` /
    #     `completion.assumptions.confinement_withdrawn`). A gate verdict is
    #     replay evidence and outranks corpus inference, so a withdrawn pair
    #     is never licensed again, whatever this corpus says.
    #   prior_footprints= — the corpus tripwire: a pair an earlier pass
    #     licensed that this corpus no longer confines is counted and printed
    #     as WITHDRAWN (licensing itself always uses THIS corpus).
    #
    # CONFINEMENT / CONF_* are MEASUREMENT knobs (§16c "the weak reading
    # survives only as confinement_strict=False, so the nesting can be
    # tested"). They default to the engine's own defaults, so an unset
    # environment reproduces the shipped pass byte for byte; every one of
    # them is folded into the COVERAGE_CHECKPOINT header key by the engine
    # (coverage.py `_checkpoint_header_keys`, "params"), so a checkpoint
    # written under one setting is never reused under another.
    # -----------------------------------------------------------------------
    _wd_path = os.environ.get("WITHDRAWN_PAIRS_FILE") or os.path.join(
        HERE, "_confinement_withdrawn.json")
    _pf_path = os.environ.get("PRIOR_FOOTPRINTS_FILE") or os.path.join(
        HERE, "_prior_footprints.json")
    _wd = _pf = None
    if os.path.exists(_wd_path) and not os.environ.get("NO_WITHDRAWN_PAIRS"):
        with open(_wd_path) as fh:
            _wd = [tuple(x) for x in json.load(fh)]
    if os.path.exists(_pf_path) and not os.environ.get("NO_PRIOR_FOOTPRINTS"):
        with open(_pf_path) as fh:
            _pf = json.load(fh)
    _conf_on = os.environ.get("CONFINEMENT", "1") != "0"
    _conf_strict = os.environ.get("CONF_STRICT", "1") != "0"
    _conf_keying = os.environ.get("CONF_KEYING", "coevaluated")
    _conf_gates = os.environ.get("CONF_GATES", "1") != "0"
    _conf_or = os.environ.get("CONF_OR_SHARING", "1") != "0"
    # §16c C2 / C3 (2026-09-13, docs/CONFINEMENT_PRECISION_20260913.md §5).
    # Both default to the engine's own default, i.e. the shipped reading, and
    # both are folded into the step-6 checkpoint key by the engine when set.
    #   CONF_SPAN_UNION=1     C2: a shape the decision REACHES but that no
    #                         matched context SPANS goes IN the footprint
    #   CONF_FALLBACK_LICENCE=0  C3 as the note WRITES it (fp = reach). Note
    #                         the note's own §5.1 numbers price the STRICTER
    #                         reading, which is CONF_KEYING=exact.
    _conf_span = os.environ.get("CONF_SPAN_UNION", "0") == "1"
    _conf_fbk = os.environ.get("CONF_FALLBACK_LICENCE", "1") != "0"
    print(f"[confinement] withdrawn_pairs fed back: {len(_wd or ())}; "
          f"prior_footprints for {len(_pf or ())} expressions", flush=True)
    print(f"[confinement] settings: confinement={_conf_on} strict={_conf_strict} "
          f"keying={_conf_keying} gates={_conf_gates} or_sharing={_conf_or} "
          f"span_union={_conf_span} fallback_licence={_conf_fbk}",
          flush=True)

    t0 = time.time()
    result = CoverageChecker(
        runs, assumptions=assumptions, max_missing_per_clique=256,
        confinement=_conf_on,
        confinement_strict=_conf_strict,
        confinement_keying=_conf_keying,
        confinement_gates=_conf_gates,
        confinement_or_sharing=_conf_or,
        confinement_span_union=_conf_span,
        confinement_fallback_licence=_conf_fbk,
        withdrawn_pairs=_wd, prior_footprints=_pf,
    ).check_coverage()
    wall = time.time() - t0

    blocking = [m for m in result.missing if not getattr(m, "untracked", False)]

    total_pcs = sum(len(r.path_conditions) for r in runs) if runs else 0
    genuine = total_pcs >= 1

    # Fixed schema (matches every other results2/results3 endpoint's
    # coverage_summary.json key set exactly — coordinator directive).
    summary = {
        "endpoint": "comments_index",
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
        "truncated": result.truncated,
        "solver_lost": result.solver_lost,
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "total_runs": result.total_runs,
        "corpus_dumps": len(dumps),
        "duplicate_outcome_maps": duplicates,
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
    #
    # ONE addition, 2026-09-13 (ported from people_stream's / posts_show's
    # copies): a counterfactual / scratch pass — any pass with `SUMMARY_OUT`
    # set — must never run the completion gate. The gate WRITES
    # `_shim_results.json` and `_assumption_results.json` INTO this batch, so
    # a scratch pass would clobber the shipped run's own evidence while
    # writing its verdict elsewhere. It is marked NOT complete instead, which
    # is the honest direction.
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
                                              "COUNTERFACTUAL/scratch pass "
                                              "(NO_PINS/SUMMARY_OUT), which must not "
                                              "overwrite the shipped run's "
                                              "shim/assumption evidence"]}
        summary["complete"] = False
        print("[coverage_report] counterfactual pass: completion section not run; "
              "complete forced False")
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

    # SUMMARY_OUT — THE DEFECT REPAIRED 2026-09-13 (notifications_index
    # `_COMPLETION_CAMPAIGN_20260910.md` §28.6): this line used to be an
    # unconditional `os.path.join(HERE, "coverage_summary.json")`, so a
    # differential harness that ran this report with `SKIP_COMPLETION=1
    # SUMMARY_OUT=<scratch>` — the shape every other batch's report honours —
    # wrote its probe passes straight over this CLOSED endpoint's summary and
    # destroyed its completion section. There was no backup. The variable is
    # now honoured exactly as people_stream's and posts_show's copies honour
    # it, and (above) a `SUMMARY_OUT` pass no longer runs the completion gate
    # at all, so a differential can never touch the shipped record again.
    if os.environ.get("NO_PINS") and not os.environ.get("SUMMARY_OUT"):
        print("NO_PINS requires SUMMARY_OUT (it must not overwrite the "
              "shipped coverage_summary.json)", file=sys.stderr)
        return 2
    out = os.environ.get("SUMMARY_OUT") or os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"OVERALL_COMPLETE={summary['complete']};COMPLETION={'n/a' if summary['completion'] is None else summary['completion']['complete']}")
    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    # One stdout line for the §16c layer (the summary schema is unchanged —
    # this batch's fixed key set is the one every other endpoint has).
    print(f"DEMAND_SETS={getattr(result, 'demand_sets', None)};"
          f"TREE_COMPLETE={getattr(result, 'tree_complete', None)};"
          f"TREE_MISSING={len(getattr(result, 'tree_missing', ()))}")
    print(f"CONF confined_pairs={len(getattr(result, 'confined_pairs', ()))};"
          f"or_pairs={len(getattr(result, 'confinement_or_pairs', ()))};"
          f"and_pairs={len(getattr(result, 'confinement_and_pairs', ()))};"
          f"overlapping={len(getattr(result, 'confinement_overlapping', ()))};"
          f"undecidable_pairs={getattr(result, 'confinement_undecidable_pairs', 0)};"
          f"splits={getattr(result, 'confinement_splits', 0)};"
          f"withdrawn={len(getattr(result, 'confinement_withdrawn', ()))};"
          f"disqualified_decisions="
          f"{len({e for e, _s, _a, _b in getattr(result, 'confinement_disqualified', ())})};"
          f"provisional={bool(getattr(result, 'confinement_provisional', False))}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"dump_errors={dict(dump_errors)}")
    try:
        import resource
        print(f"peak RSS {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024:.0f} MB")
    except Exception:  # noqa: BLE001
        pass
    print(f"wrote {out} in {wall:.1f}s")
    return 0 if result.complete else 1


if __name__ == "__main__":
    sys.exit(main())
