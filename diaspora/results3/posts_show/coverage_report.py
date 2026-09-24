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



# --- Alias canonicalization at LOAD (ported 2026-09-09) ------------
from concolic_engine.assumptions import alias_map_for, renamer  # noqa: E402
from coverage_assumptions import ALIASES  # noqa: E402


def alias_map(dump: dict, aliases=None) -> dict:
    events = [(ev.get("result_name"), ev.get("note"))
              for ev in dump.get("events") or () if ev.get("type") == "symbolic_call"]
    return alias_map_for(events, aliases or ALIASES)


def canonicalize_ordinals(dump: dict, aliases=None) -> dict:
    """Rewrite a RAW dump in place. `concolic_seeds` is left ORDINAL-named: it
    is what the runtime consumes; the demand seeder maps back through this."""
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



def _conf_mode(on: bool, strict: bool, or_sharing: bool) -> str:
    """The three §16c readings this endpoint measures, named once.

    DISCIPLINE §16c nesting:  OR-refined  subset of  strict  subset of  §16b.
    """
    if not on:
        return "16b (confinement OFF)"
    if not strict:
        return "weak"
    return "OR-refined" if or_sharing else "STRICT"


def main() -> int:
    # DUMP_LIST / DUMP_SAMPLE / SUMMARY_OUT (ported VERBATIM from
    # notifications_index/coverage_report.py, 2026-09-10, preflight): a drive
    # may be ADDING dumps while a pass runs, so the glob is not reproducible;
    # and a 96 357-dump load does not fit a 3 GB cap (measured: OOM-killed at
    # 2.97 GiB, 8 min in), so a SAMPLED pass is the only way to price the
    # coverage phase on this box. Every sampled number prints as a sample.
    _dl = os.environ.get("DUMP_LIST")
    if _dl:
        dumps = sorted(l.strip() for l in open(_dl) if l.strip())
        dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
        print(f"DUMP_LIST {_dl}: {len(dumps)} dump files (fixed snapshot)", flush=True)
    else:
        dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if not dumps:
        print("NO_DUMPS")
        return 2
    print(f"corpus POPULATION: {len(dumps)} dump files", flush=True)
    _sample = int(os.environ.get("DUMP_SAMPLE", "0"))
    if _sample and _sample < len(dumps):
        import random as _rnd
        _rnd.seed(int(os.environ.get("DUMP_SAMPLE_SEED", "20260901")))
        dumps = sorted(_rnd.sample(dumps, _sample))
        print(f"SAMPLED PASS: {len(dumps)} of that population, random, "
              f"seed={os.environ.get('DUMP_SAMPLE_SEED', '20260901')} — "
              f"every number below is a SAMPLE statistic, not a corpus total",
              flush=True)

    runs, skipped = [], []
    dump_errors = Counter()
    _t_load = time.time()
    for _i, p in enumerate(dumps):
        try:
            raw = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
            continue
        if raw.get("error"):
            dump_errors[raw["error"].get("type", "Unknown")] += 1
        try:
            canonicalize_ordinals(raw)
            runs.append(share_run_objects(Run.from_dict(fix_len_names(raw))))
        except Exception as e:  # noqa: BLE001
            skipped.append({"file": os.path.basename(p), "error": f"{type(e).__name__}: {e}"})
        del raw
        if (_i + 1) % 5000 == 0:
            import resource as _r
            print(f"[load] {_i+1}/{len(dumps)} runs={len(runs)} "
                  f"RSS={_r.getrusage(_r.RUSAGE_SELF).ru_maxrss // 1024}MB "
                  f"{time.time()-_t_load:.0f}s", flush=True)

    print(f"loaded {len(runs)} runs ({len(skipped)} unparseable)", flush=True)
    if skipped:
        print(f"skipped(sample)={skipped[:10]}")

    assumptions = build_assumptions(runs)

    # -----------------------------------------------------------------------
    # C7 HEARTBEAT (ported from notifications_index/coverage_report.py). The
    # Z3/combination phase writes nothing for as long as it runs, so "alive
    # and busy" and "wedged" look identical from outside. The checker is in
    # src/ and is not ours to instrument; a daemon thread prints elapsed /
    # RSS / CPU from OUTSIDE it.
    # -----------------------------------------------------------------------
    import threading
    import resource as _res
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

    # -----------------------------------------------------------------------
    # CONFINEMENT (DISCIPLINE §16c), wired 2026-09-12 — PORTED from
    # notifications_index/coverage_report.py, which is the only driver copy
    # that had it. What was actually missing here, stated exactly:
    #
    #   * The engine has applied §16c on this endpoint SINCE IT LANDED — the
    #     `CoverageChecker` defaults are confinement=True, strict=True,
    #     keying="coevaluated", gates=True, or_sharing=True, and P14..P24 all
    #     ran on the engine that carries them (coverage.py md5
    #     270be964bc7de60bfb9390108938411f in every _p15_pass_P2*.log). So the
    #     PASS numbers were already OR-refined; what this file lacked was
    #     (a) the CROSS-PASS LOOP, (b) any REPORTING of the layer, and
    #     (c) max_cliques — the confinement projection of one demand set is
    #     capped by it and the engine default is 1024, while this endpoint's
    #     own enumerator has always run at 16384.
    #
    #   withdrawn_pairs= — every inferred pair the ASSUMPTION GATE did not
    #     PASS. A gate verdict is replay evidence and outranks corpus
    #     inference, so a withdrawn pair is never licensed again, whatever
    #     this corpus says. CLASS-WHOLE: the gate tests one representative per
    #     footprint-family class and every pair in a non-PASS class is
    #     withdrawn with it.
    #   prior_footprints= — the corpus tripwire: a pair an earlier pass
    #     licensed that this corpus no longer confines is counted and printed
    #     as WITHDRAWN (licensing itself always uses THIS corpus).
    #
    # CONFINEMENT / CONF_* are MEASUREMENT knobs (§16c "the weak reading
    # survives only as confinement_strict=False, so the nesting can be
    # tested"). They default to the engine's own defaults, so an unset
    # environment reproduces the shipped pass byte for byte; every one of them
    # is folded into the COVERAGE_CHECKPOINT header key by the engine
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
    print(f"[confinement] withdrawn_pairs fed back: {len(_wd or ())}; "
          f"prior_footprints for {len(_pf or ())} expressions", flush=True)
    print(f"[confinement] settings: confinement={_conf_on} strict={_conf_strict} "
          f"keying={_conf_keying} gates={_conf_gates} or_sharing={_conf_or} "
          f"(MODE={_conf_mode(_conf_on, _conf_strict, _conf_or)})", flush=True)

    # foreclosure_conjunctions= — DISCIPLINE §16e (2026-09-13): infer
    # foreclosure over the gate CONJUNCTIONS the demand already contains, not
    # only pairwise. Default OFF in the engine so every summary written before
    # that date reproduces byte-for-byte; DEFAULT OFF HERE TOO so every P15..P26
    # pass of this endpoint still reproduces, and P29 turns it on explicitly
    # (FORECLOSURE_CONJUNCTIONS=1). It is folded into the step-6 checkpoint key,
    # so a checkpoint written under one setting is rotated rather than replayed.
    _conj = os.environ.get("FORECLOSURE_CONJUNCTIONS", "0") == "1"
    # foreclosure_subconjunctions= — DISCIPLINE §16f (2026-09-13): the same
    # relation over a SUB-conjunction of the leaf's own cube (a proper subset
    # of §16e's gate prefix, and/or literals of NON-gate members), with GATES
    # eligible as the foreclosed member. DEFAULT OFF here too, so every
    # P15..P29 pass of this endpoint still reproduces byte-for-byte;
    # FORECLOSURE_SUBCONJUNCTIONS=1 turns it on and IMPLIES §16e.
    # FORECLOSURE_CONJUNCTION_WIDTH caps |C| (engine default 3) and is the
    # cost bound. Both are part of the step-6 checkpoint key, so a checkpoint
    # written under one setting is rotated rather than replayed under another.
    _subconj = os.environ.get("FORECLOSURE_SUBCONJUNCTIONS", "0") == "1"
    _cwidth = int(os.environ.get("FORECLOSURE_CONJUNCTION_WIDTH", "3"))
    print(f"[foreclosure] conjunction foreclosure (§16e): "
          f"{'ON' if (_conj or _subconj) else 'OFF'}; "
          f"sub-conjunction (§16f): "
          f"{('ON, W=%d' % _cwidth) if _subconj else 'OFF'}", flush=True)

    t0 = time.time()
    threading.Thread(target=_heartbeat, args=(t0,), daemon=True).start()
    try:
        result = CoverageChecker(
            runs, assumptions=assumptions,
            foreclosure_conjunctions=_conj,
            foreclosure_subconjunctions=_subconj,
            foreclosure_conjunction_width=_cwidth,
            foreclosure_conjunction_budget=int(
                os.environ.get("FORECLOSURE_CONJUNCTION_BUDGET", "20000")),
            max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4")),
            # MAX_CLIQUES: the cap on the independence projection of ONE
            # evaluation set AND on the confinement projection of one demand
            # set. The engine default is 1024; a hit is signalled only through
            # `truncated`, which §16d already forces True on any incomplete
            # pass — i.e. it is invisible here. This endpoint's own exact
            # enumerator has always run at 16384 (and `build_universe` returns
            # None rather than falling back, so 16384 is known NOT to be hit).
            max_cliques=int(os.environ.get("MAX_CLIQUES", "16384")),
            confinement=_conf_on,
            confinement_strict=_conf_strict,
            confinement_keying=_conf_keying,
            confinement_gates=_conf_gates,
            confinement_or_sharing=_conf_or,
            withdrawn_pairs=_wd, prior_footprints=_pf,
        ).check_coverage()
    finally:
        _hb_stop.set()
    wall = time.time() - t0
    print(f"[coverage] phase done in {wall:.0f}s", flush=True)

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
        # DISCIPLINE §16e (2026-09-13), INFERRED not declared; all None/0 when
        # FORECLOSURE_CONJUNCTIONS is off, so the pre-P29 schema is unchanged.
        "conjunction_foreclosures": getattr(result, "conjunction_foreclosures", None),
        "conjunction_foreclosure_groups": getattr(
            result, "conjunction_foreclosure_groups", None),
        "conjunction_foreclosures_provisional": getattr(
            result, "conjunction_foreclosures_provisional", None),
        "conjunction_foreclosure_list": [
            {"prefix": [[g, o] for g, o in pfx], "member": d}
            for pfx, d in getattr(result, "conjunction_foreclosure_list", ())][:200],
        "unmatched_gate_conjunctions": getattr(
            result, "unmatched_gate_conjunctions", None),
        # §16f (2026-09-13), INFERRED not declared; all None/0 when
        # FORECLOSURE_SUBCONJUNCTIONS is off, so the pre-P30 schema is
        # unchanged. The conditioning literals need not be gates and the
        # foreclosed member may itself be one.
        "subconjunction_foreclosures": getattr(
            result, "subconjunction_foreclosures", None),
        "subconjunction_foreclosure_conditions": getattr(
            result, "subconjunction_foreclosure_conditions", None),
        "subconjunction_foreclosures_provisional": getattr(
            result, "subconjunction_foreclosures_provisional", None),
        "subconjunction_foreclosure_width": getattr(
            result, "subconjunction_foreclosure_width", None),
        "subconjunction_foreclosure_list": [
            {"conditioning": [[g, "taken" if o else "not_taken"] for g, o in cond],
             "member": d, "A": a}
            for cond, d, a in getattr(
                result, "subconjunction_foreclosure_list", ())],
        "unmatched_gate_conjunction_prefixes": [
            [[g, o] for g, o in pfx]
            for pfx in getattr(result, "unmatched_gate_conjunction_prefixes", ())][:50],
        "foreclosures_ignored": getattr(result, "foreclosures_ignored", None),
        "foreclosures_provisional": getattr(result, "foreclosures_provisional", None),
        "foreclosure_gates": [list(g) for g in getattr(result, "foreclosure_gates", ())][:20],
        # 2026-09-12 (DISCIPLINE §16c): CONFINEMENT. The fixed schema was
        # settled before §16c existed and serialised NONE of it, so every
        # posts_show summary since the layer landed reported numbers computed
        # under a projection the file did not name. These keys are additive
        # (no existing key changes meaning) and they say exactly which of the
        # nested readings — OR-refined subset of strict subset of §16b — the
        # `demand_sets` above were counted under.
        "confinement": {
            "mode": _conf_mode(_conf_on, _conf_strict, _conf_or),
            "settings": {
                "confinement": _conf_on, "strict": _conf_strict,
                "keying": _conf_keying, "gates": _conf_gates,
                "or_sharing": _conf_or,
                "max_cliques": int(os.environ.get("MAX_CLIQUES", "16384")),
            },
            "decisions_decided": len(getattr(result, "footprints", ())),
            "decisions_confined": len(getattr(result, "confined_decisions", ())),
            "decisions_undecidable": len(getattr(result, "footprints_undecidable", ())),
            "decisions_coevaluated": len(getattr(result, "footprints_coevaluated", ())),
            "decisions_disqualified": len({
                e for e, _s, _a, _b in getattr(result, "confinement_disqualified", ())}),
            "pairs_confined": len(getattr(result, "confined_pairs", ())),
            "pairs_or_licensed": len(getattr(result, "confinement_or_pairs", ())),
            "pairs_and_refused": len(getattr(result, "confinement_and_pairs", ())),
            "pairs_overlapping": len(getattr(result, "confinement_overlapping", ())),
            "pairs_undecidable": getattr(result, "confinement_undecidable_pairs", 0),
            "splits": getattr(result, "confinement_splits", 0),
            "provisional": bool(getattr(result, "confinement_provisional", False)),
            "withdrawn_fed_back": len(_wd or ()),
            "withdrawn_by_tripwire": [
                list(p_) for p_ in getattr(result, "confinement_withdrawn", ())],
            "confined_pairs": [
                list(p_) for p_ in getattr(result, "confined_pairs", ())][:2000],
            "or_pairs": [
                list(p_) for p_ in getattr(result, "confinement_or_pairs", ())][:2000],
            "and_pairs": [
                list(p_) for p_ in getattr(result, "confinement_and_pairs", ())][:200],
            "overlapping_top": [
                list(p_) for p_ in getattr(result, "confinement_overlapping", ())][:200],
            "disqualified_top": [
                list(p_) for p_ in getattr(result, "confinement_disqualified", ())][:200],
        },
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
            # 400 -> 4000 (2026-09-10 drive). `_demand_root.py` roots ONLY
            # from the witnesses this file records, so the cap is the round's
            # harvest size: at 400, a corpus with thousands of missing
            # assignments converges at 400 per round no matter how high
            # MAX_MISSING_PER_CLIQUE is set. The cost is file size (~1 KB per
            # entry), not solver time — the witnesses are already computed.
            for m in result.missing[:4000]
        ],
    }

    # -----------------------------------------------------------------------
    # Completion section (concolic_engine.completion) — PORTED from
    # results3/people_stream/coverage_report.py (itself a verbatim port of
    # results3/comments_index's), 2026-09-10 completion drive. The engine's
    # "are the mocks complete?" verdict belongs in the SAME final report as
    # "is exploration complete?"; overall `complete` = both. posts_show had NO
    # completion wiring at all until this drive: it did not read
    # `SKIP_COMPLETION` (so the variable the preflight passed to the
    # OOM-killed pass was a NO-OP) and no `OVERALL_COMPLETE=` line has ever
    # existed on this endpoint.
    #
    # The endpoint-specific addition people_stream added is kept: a
    # counterfactual / scratch pass (`NO_PINS=1`, or any `SUMMARY_OUT`) must
    # never run the completion gate — the gate WRITES `_shim_results.json` and
    # `_assumption_results.json` into the batch, so a scratch pass would
    # clobber the shipped run's own evidence while writing its verdict
    # elsewhere. It is marked NOT complete instead, which is the honest
    # direction (comments_index 2026-08-27: a killed report left
    # `complete: true` with no completion section and that file was read as a
    # result).
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
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate did not run "
                                              "(coverage-only pass / SKIP_COMPLETION)"]}
        summary["complete"] = False

    # SUMMARY_OUT: the COUNTERFACTUAL half of the overnight pin tier
    # (coverage_assumptions.py) must be measurable without clobbering the
    # shipped summary, so `NO_PINS=1` REQUIRES it.
    if os.environ.get("NO_PINS") and not os.environ.get("SUMMARY_OUT"):
        print("NO_PINS requires SUMMARY_OUT (it must not overwrite the "
              "shipped coverage_summary.json)", file=sys.stderr)
        return 2
    # FOOTPRINTS_OUT — the footprints this pass licensed on, in the shape
    # `CoverageChecker(prior_footprints=...)` reads. Written on request only,
    # never over `_prior_footprints.json` unless asked: the tripwire compares
    # THIS corpus against an EARLIER pass, so the file it reads must be
    # promoted deliberately, not by whichever pass ran last.
    if os.environ.get("FOOTPRINTS_OUT"):
        with open(os.environ["FOOTPRINTS_OUT"], "w") as fh:
            json.dump({e: list(sh) for e, sh in getattr(result, "footprints", ())},
                      fh, indent=1)
        print(f"[confinement] wrote footprints for "
              f"{len(getattr(result, 'footprints', ()))} expressions -> "
              f"{os.environ['FOOTPRINTS_OUT']}", flush=True)

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
    print(f"dumps_loaded={len(runs)};dumps_unparseable={len(skipped)}")
    print(f"DEMAND_SETS={getattr(result, 'demand_sets', None)};"
          f"TREE_COMPLETE={getattr(result, 'tree_complete', None)};"
          f"TREE_MISSING={len(getattr(result, 'tree_missing', ()))};"
          f"FORECLOSURES={getattr(result, 'foreclosures', None)};"
          f"FORECL_IGNORED={getattr(result, 'foreclosures_ignored', None)};"
          f"FORECL_PROVISIONAL={getattr(result, 'foreclosures_provisional', None)}")
    print(f"SUBCONJ_FORECLOSURES={summary['subconjunction_foreclosures']};"
          f"SUBCONJ_CONDS={summary['subconjunction_foreclosure_conditions']};"
          f"SUBCONJ_WIDTH={summary['subconjunction_foreclosure_width']};"
          f"SUBCONJ_PROVISIONAL={summary['subconjunction_foreclosures_provisional']}",
          flush=True)
    print(f"CONJ_FORECLOSURES={summary['conjunction_foreclosures']};"
          f"CONJ_GROUPS={summary['conjunction_foreclosure_groups']};"
          f"CONJ_PROVISIONAL={summary['conjunction_foreclosures_provisional']};"
          f"UNMATCHED_CONJ={summary['unmatched_gate_conjunctions']}")
    _cs = summary["confinement"]
    print(f"CONFINEMENT={_cs['mode']};DECIDED={_cs['decisions_decided']};"
          f"CONFINED_DEC={_cs['decisions_confined']};"
          f"DISQ_DEC={_cs['decisions_disqualified']};"
          f"UNDECIDABLE_DEC={_cs['decisions_undecidable']};"
          f"COEVAL_DEC={_cs['decisions_coevaluated']};"
          f"PAIRS_CONFINED={_cs['pairs_confined']};"
          f"OR_PAIRS={_cs['pairs_or_licensed']};AND_REFUSED={_cs['pairs_and_refused']};"
          f"OVERLAPPING={_cs['pairs_overlapping']};"
          f"UNDECIDABLE_PAIRS={_cs['pairs_undecidable']};"
          f"SPLITS={_cs['splits']};PROVISIONAL={_cs['provisional']};"
          f"WITHDRAWN_FED={_cs['withdrawn_fed_back']};"
          f"WITHDRAWN_TRIPWIRE={len(_cs['withdrawn_by_tripwire'])}")
    for _a, _b in _cs["withdrawn_by_tripwire"][:10]:
        print(f"   CONF-WITHDRAWN {_a[:70]}  x  {_b[:70]}")
    for _e, _sh, _r1, _r2 in _cs["disqualified_top"][:5]:
        print(f"   CONF-DISQUALIFIED {_e[:70]}  shape={_sh[:60]}  runs={_r1}/{_r2}")
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
