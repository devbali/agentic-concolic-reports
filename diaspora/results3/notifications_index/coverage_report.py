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


# ---------------------------------------------------------------------------
# P0 (2026-09-08) — LOAD-TIME CANONICALIZATION of ordinal-named results.
#
# The runtime names a symbolic result by WHEN it was called
# (`SYM_RESULT_..._CollectionProxy_records_<idx>`, call_interceptor.rb:142).
# Measured on this corpus: records_4 is the aspects read in 1 909 runs and the
# services read in 1 254; the same expression `(len(records_4_rows) > 1)`
# is therefore two different decisions, and the checker's maximal cliques
# over ordinal-named exprs were evaluated whole by NO run (945 of 945).
# Every `len(records_N)` PC sits on a REAL SELECT (aspects 7 989, services
# 7 989, tags 4 099, photos 4 214, aspect_memberships 652; a read answered
# from a loaded association mints no such PC), so the ambiguity is between
# statements, never between "statement" and "no statement".
#
# Rename, per run, every result matching a declared alias whose call recorded a
# statement, to `<stem>_<table>_<hash of the key>`. Which key is per
# declaration (coverage_assumptions.ALIASES, 2026-09-09):
#   * `Relation_records` / `Relation_to_ary` -> `statement_key`, BINDS kept
#     verbatim, literals wildcarded — so mentions keyed on three different
#     owner chains are THREE names and the paginated list's plain / typed /
#     unread / typed+unread variants are FOUR. They are NOT folded into one
#     loop: the gate refuted that (the typed variant's rows never reach the
#     photos chain).
#   * `CollectionProxy_records` -> `loop_key`, table + binds with the variant
#     text dropped — so photos' six statements (three owner guids x an
#     empty-scope variant) are THREE names, one per owner chain, and
#     aspects/services/tags/aspect_memberships are one name each either way.
# Applied to symbolic_vars, PC exprs, result
# names, notes and concrete_values BEFORE fix_len_names (which drops notes).
# The same map function (alias_map_for) is what the engine's
# AliasAssumption and the assumption gate compute, so the three agree
# by construction; the gate's derived test verifies the identity claim.
# ---------------------------------------------------------------------------
from concolic_engine.assumptions import alias_map_for, renamer  # noqa: E402
from coverage_assumptions import ALIASES  # noqa: E402  (declared there; applied here at load)


def alias_map(dump: dict, aliases=None) -> dict:
    """{ordinal result name: canonical name} for a RAW dump (notes intact)."""
    events = [(ev.get("result_name"), ev.get("note"))
              for ev in dump.get("events") or () if ev.get("type") == "symbolic_call"]
    return alias_map_for(events, aliases or ALIASES)


def canonicalize_ordinals(dump: dict, aliases=None) -> dict:
    """Rewrite a RAW dump in place; returns the alias map (empty when nothing
    matched). Seeds (`concolic_seeds`) are left ordinal-named: they are what
    the RUNTIME consumes, and the demand seeder maps back through this map."""
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
        if isinstance(sr, dict) and sr.get("name"):
            sr["name"] = rn(sr["name"])
    split_self_compare(dump)
    return amap


_SELFCMP_RE = re.compile(r"\((SYM_[A-Za-z0-9_]+) == \1\)")


def split_self_compare(dump: dict) -> dict:
    """CLASS-B FIX (2026-09-10) — a self-compare is NOT a tautology here.

    `gon_helper.rb:6` runs
    `Gon.preloads[:contacts].none? {|stored| stored[:person][:id] == contact.person_id}`:
    it compares a PREVIOUSLY STORED contact's person id against the CURRENT
    contact's. Those are two different rows of the same `Contact.find_by`
    family, and `call_interceptor.rb:142-144` names a result by WHEN it was
    called RELATIVE TO ITS PREFIX, so both operands are minted with the one
    name `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id`. The
    recorded expression is therefore literally `(V == V)`, which every Z3
    model makes TRUE -- while the corpus records it **not_taken 963 times**
    (and taken 1 052) across the 68 231 dumps. Any demand cube pinning it
    False is UNSAT under the declared model, and a demand set whose ONLY
    observed cubes pin it False reports `covered == 0`: exactly the two
    width-7 sets the 2026-09-10 census surfaced (_COEVAL_SEMANTICS §6.4).

    The declaration bug is the claim that the two operands are the same
    value. The fix is to name them apart: the RIGHT operand becomes
    `<V>__prior`, a free SymbolicVar of the same sort, so the expression
    models what the app actually decides ("is this contact already stored?")
    and both observed outcomes are satisfiable. The RIGHT side is chosen
    deliberately -- `coverage_assumptions._leftvar` and `_rep_key` both key
    on the LEFT variable (and `_is_principal` still sees `person_id` in the
    renamed right operand), so every declared tier keys exactly as before.

    Only `==` is split. `(V != V)` also occurs (1 168 times, the
    `to_ary_..._row_target_status_message_guid` compare) but is recorded
    **not_taken every single time**, which is precisely what the tautology
    model predicts -- there is no contradiction to repair, so repairing it
    would invent an unobserved True side and add a tree-completeness demand
    the corpus has never contradicted. If a `(V != V) :: taken` ever appears,
    it is the same defect and belongs here.

    Applied at load, inside the canonicalization, so EVERY tool that loads
    through `coverage_report` (the pass, `_exact_enum.py`, `_decisive.py`)
    sees the same universe.
    """
    renamed = {}
    for ev in dump.get("events") or ():
        e = ev.get("expr")
        if not e or "SYM_" not in e:
            continue
        m = _SELFCMP_RE.fullmatch(e.strip())
        if not m:
            continue
        v = m.group(1)
        nv = renamed.setdefault(v, v + "__prior")
        ev["expr"] = f"({v} == {nv})"
    if not renamed:
        return dump
    svs = dump.setdefault("symbolic_vars", [])
    have = {sv.get("name") for sv in svs}
    by = {sv.get("name"): sv for sv in svs}
    for v, nv in renamed.items():
        if nv in have:
            continue
        base = by.get(v)
        if base is None:
            # the operand has no var entry (should not happen); drop the
            # rewrite rather than declare a variable with no sort
            for ev in dump.get("events") or ():
                if ev.get("expr") == f"({v} == {nv})":
                    ev["expr"] = f"({v} == {v})"
            continue
        svs.append({"name": nv, "sort": base.get("sort"), "value": base.get("value")})
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
    # CLASS-B FIX (2026-09-10, _COMPLETION_CAMPAIGN_20260910.md §1). The old
    # bounds were (0,7) and (0,1) — the number of ENUMERATED cases — on the
    # claim that an out-of-range index "would make the all-compares-False
    # combination spuriously satisfiable". That claim is FALSE: both mints
    # carry an explicit out-of-range default in targets.rb
    # (`profile = NOTE_TYPE_PROFILES.first  # defensive default (idx out of
    # range)` at targets.rb:876, and `pchosen = 0` at targets.rb:1477), the
    # RUNTIME puts no bound on the seed, and the DSE solver -- negating
    # `idx == 7` / `pidx == 1` -- duly produced 8 and 2 and the runner
    # EXECUTED them: 61 dumps carry SYM_NOTE_TYPE_PROFILE == 8 with all eight
    # `== i` compares recorded not-taken, and 35 carry SYM_POST_STI == 2 with
    # both compares not-taken. Under the old bounds those observed cubes are
    # UNSAT. (It is NOT what produced the two `covered == 0` demand sets --
    # those are the self-compare collapse fixed in `split_self_compare` -- but
    # it is a declared domain that excludes something the runtime produced,
    # which is the same class of defect and is fixed here.)
    # The high bound is now ONE REPRESENTATIVE of the out-of-range class:
    # every value > 8 (and every negative) drives the same defensive default
    # and records the identical all-False cube, so {0..8} / {0..2} is a
    # complete set of representatives for the observable outcome space, and
    # `low = 0` excludes no outcome (a negative is behaviourally 8).
    BOUNDS = {"SYM_NOTE_TYPE_PROFILE": (0, 8), "SYM_POST_STI": (0, 2)}
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
    # DUMP_LIST (2026-09-10): a drive may be ADDING dumps while a pass runs, so
    # the glob is not reproducible. Point DUMP_LIST at a snapshot file (one
    # path per line, `find . -maxdepth 1 -name 'dump_*.json' | sort`) and the
    # pass measures exactly that list. Same knob `_exact_enum.py` already has.
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
    _alias_legend: dict = {}   # canonical name -> ordinals it replaced (P0)
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
            for _o, _c in canonicalize_ordinals(raw).items():
                _alias_legend.setdefault(_c, set()).add(_o.rsplit("_", 1)[1])
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

    # P0 legend: which ordinals each canonical name replaced, for humans and
    # for the demand seeder (it maps canonical seeds back per base dump).
    with open(os.path.join(HERE, "_canonical_legend.json"), "w") as fh:
        json.dump({c: sorted(o, key=int) for c, o in sorted(_alias_legend.items())}, fh, indent=1)
    print(f"[P0] canonicalized {len(_alias_legend)} statement identities "
          f"from {sum(len(o) for o in _alias_legend.values())} (name, ordinal) pairs; "
          f"legend in _canonical_legend.json", flush=True)

    assumptions = build_assumptions(runs)

    # NO_PINS=1 (2026-09-10) — the COUNTERFACTUAL half of the overnight-pin
    # decision. `coverage_assumptions._overnight_unreachable_pins` is now
    # DECLARED (owner-instructed); this knob strips that tier back out so the
    # report can always show what the endpoint looks like WITHOUT it. It
    # REQUIRES SUMMARY_OUT so it can never overwrite the shipped
    # `coverage_summary.json`, which always reports the endpoint AS DECLARED.
    if os.environ.get("NO_PINS"):
        if not os.environ.get("SUMMARY_OUT"):
            print("NO_PINS requires SUMMARY_OUT (it must not overwrite the "
                  "shipped coverage_summary.json)")
            return 2
        _before = len(assumptions.assumptions)
        assumptions.assumptions = [
            a for a in assumptions.assumptions
            if not str(getattr(a, "description", "")).startswith(
                "overnight unreachable pin")]
        print(f"NO_PINS: {_before - len(assumptions.assumptions)} overnight pins "
              f"REMOVED for this measurement; writing to SUMMARY_OUT",
              flush=True)

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
        # MAX_CLIQUES (2026-09-08): coverage.py falls back to SINGLETON
        # cliques — a per-expression check, not combination coverage — when
        # the graph has more maximal cliques than `max_cliques` (engine
        # default 1024), signalling it only through `truncated`. The
        # canonical universe has ~3 100 maximal cliques (was 945 before the
        # ordinal alias), so the default silently voided the first canonical
        # pass (88 "missing" in 134 s). Raise the cap here; the count of
        # cliques is reported by the batch's own graph measurement.
        # CONFINEMENT CROSS-PASS LOOP (_CONFINEMENT_20260911.md "Two optional
        # one-liners ... in each coverage_report.py where CoverageChecker( is
        # built"; never added here until now, 2026-09-11):
        #   withdrawn_pairs= — every inferred pair the ASSUMPTION GATE did not
        #     PASS. A gate verdict is replay evidence and outranks corpus
        #     inference, so a withdrawn pair is never licensed again, whatever
        #     this corpus says. The file is written from the class gate's own
        #     results (_gate_ALL_results.json -> _c11_withdraw_conf.json ->
        #     _confinement_withdrawn.json) and is CLASS-WHOLE: the gate tested
        #     one representative per (footprint-family) class and every pair in
        #     a non-PASS class is withdrawn with it, per the HARD RULE in
        #     coverage_assumptions.py.
        #   prior_footprints= — the corpus tripwire: a pair the earlier pass
        #     licensed that this corpus no longer confines is counted and
        #     printed as WITHDRAWN (licensing always uses THIS corpus).
        _wd_path = os.path.join(HERE, "_confinement_withdrawn.json")
        _pf_path = os.path.join(HERE, "_prior_footprints.json")
        _wd = _pf = None
        if os.path.exists(_wd_path) and not os.environ.get("NO_WITHDRAWN_PAIRS"):
            with open(_wd_path) as fh:
                _wd = [tuple(x) for x in json.load(fh)]
        if os.path.exists(_pf_path) and not os.environ.get("NO_PRIOR_FOOTPRINTS"):
            with open(_pf_path) as fh:
                _pf = json.load(fh)
        print(f"[confinement] withdrawn_pairs fed back: {len(_wd or ())}; "
              f"prior_footprints for {len(_pf or ())} expressions", flush=True)
        #   foreclosure_conjunctions= — DISCIPLINE §16e (2026-09-13): infer
        #     foreclosure over the gate CONJUNCTIONS the demand already
        #     contains, not only pairwise. Default OFF in the engine so every
        #     summary written before that date reproduces byte-for-byte; this
        #     endpoint turns it ON (env knob FORECLOSURE_CONJUNCTIONS=0 turns
        #     it back off for a differential). It is folded into the step-6
        #     checkpoint key, so a checkpoint written under one setting is
        #     rotated rather than replayed under the other.
        _conj = os.environ.get("FORECLOSURE_CONJUNCTIONS", "1") == "1"
        #   foreclosure_subconjunctions= — DISCIPLINE §16f (2026-09-13): the
        #     same relation over a SUB-conjunction of the leaf's own cube (a
        #     proper subset of §16e's gate prefix, and/or literals of NON-gate
        #     members), with GATES eligible as the foreclosed member. Default
        #     OFF here too, so a C18-shaped pass reproduces byte-for-byte;
        #     FORECLOSURE_SUBCONJUNCTIONS=1 turns it on and implies §16e.
        #     FORECLOSURE_CONJUNCTION_WIDTH caps |C| (engine default 3) and is
        #     the cost bound. Both are part of the step-6 checkpoint key.
        _subconj = os.environ.get("FORECLOSURE_SUBCONJUNCTIONS", "0") == "1"
        _cwidth = int(os.environ.get("FORECLOSURE_CONJUNCTION_WIDTH", "3"))
        #   foreclosure_wellfounded_drops= — DISCIPLINE §16g (2026-09-14):
        #     §16f's `C ⊆ acc` (walk-prefix) restriction replaced by a
        #     WELL-FOUNDEDNESS condition — `C` may be drawn from anywhere in
        #     the leaf's own cube provided every literal of it belongs to a
        #     member that is itself KEPT, resolved as a least fixed point.
        #     Default OFF here too, so every earlier pass reproduces
        #     byte-for-byte; FORECLOSURE_WELLFOUNDED_DROPS=1 turns it on and
        #     implies §16f (hence §16e). It is part of the step-6 checkpoint
        #     key ONLY when on, so an existing §16f checkpoint still replays.
        _wf = os.environ.get("FORECLOSURE_WELLFOUNDED_DROPS", "0") == "1"
        print(f"[foreclosure] conjunction foreclosure (§16e): "
              f"{'ON' if (_conj or _subconj or _wf) else 'OFF'}; "
              f"sub-conjunction (§16f): "
              f"{('ON, W=%d' % _cwidth) if (_subconj or _wf) else 'OFF'}; "
              f"well-founded drops (§16g): "
              f"{('ON, W=%d' % _cwidth) if _wf else 'OFF'}", flush=True)
        result = CoverageChecker(
            runs, assumptions=assumptions,
            max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4")),
            max_cliques=int(os.environ.get("MAX_CLIQUES", "16384")),
            withdrawn_pairs=_wd, prior_footprints=_pf,
            foreclosure_conjunctions=_conj,
            foreclosure_subconjunctions=_subconj,
            foreclosure_conjunction_width=_cwidth,
            foreclosure_conjunction_budget=int(
                os.environ.get("FORECLOSURE_CONJUNCTION_BUDGET", "20000")),
            foreclosure_wellfounded_drops=_wf,
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
        "total_path_conditions": total_pcs,
        "dump_errors": dict(dump_errors),
        "assumptions": result.assumptions_to_dict(),
        "assumptions_used": result.assumptions_used,
        # §16b / §16e (2026-09-13). The pairwise counts were never in this
        # endpoint's summary; they are here now because the conjunction
        # numbers are only readable next to them.
        "foreclosures": getattr(result, "foreclosures", None),
        "foreclosures_ignored": getattr(result, "foreclosures_ignored", None),
        "foreclosures_provisional": getattr(result, "foreclosures_provisional", None),
        "conjunction_foreclosures": getattr(result, "conjunction_foreclosures", None),
        "conjunction_foreclosure_groups": getattr(
            result, "conjunction_foreclosure_groups", None),
        "conjunction_foreclosures_provisional": getattr(
            result, "conjunction_foreclosures_provisional", None),
        "conjunction_foreclosure_list": [
            {"prefix": [[g, "taken" if o else "not_taken"] for g, o in pfx],
             "member": d}
            for pfx, d in getattr(result, "conjunction_foreclosure_list", ())],
        # A = 0: NOT an inference and NOT dropped from the demand — the
        # driver constructs these prefixes (DISCIPLINE §16e).
        "unmatched_gate_conjunctions": getattr(
            result, "unmatched_gate_conjunctions", None),
        # §16f (2026-09-13): the SUB-conjunction classes, structured — the
        # conditioning literals need not be gates and the member may be one.
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
        # §16g (2026-09-14): the WELL-FOUNDED drop classes, structured. Same
        # shape as §16f's — the conditioning literals may sit LATER in the
        # walk than the member, and every one of them belongs to a member the
        # leaf KEEPS.
        "wellfounded_drops": getattr(result, "wellfounded_drops", None),
        "wellfounded_drop_conditions": getattr(
            result, "wellfounded_drop_conditions", None),
        "wellfounded_drops_provisional": getattr(
            result, "wellfounded_drops_provisional", None),
        "wellfounded_drop_list": [
            {"conditioning": [[g, "taken" if o else "not_taken"] for g, o in cond],
             "member": d, "A": a}
            for cond, d, a in getattr(result, "wellfounded_drop_list", ())],
        "unmatched_gate_conjunction_prefixes": [
            [[g, "taken" if o else "not_taken"] for g, o in pfx]
            for pfx in getattr(result, "unmatched_gate_conjunction_prefixes", ())],
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
        # NEVER let the gate destroy the coverage result (2026-09-11: the full
        # pass computed 8 962 s of coverage, then `cardinality_consistency_audit`
        # hit completion.py's 1800 s audit timeout; the TimeoutExpired came out
        # of `attach_to_summary`, the process died at line 623 and NOTHING was
        # written — `coverage_summary.json` still had the previous day's mtime).
        # The summary dict is built at this point; a gate that raises now leaves
        # a summary that is honest about the gate and complete about coverage.
        # The PREFERRED shape is still the split (SKIP_COMPLETION=1 + SUMMARY_OUT
        # for the pass, then `_engine_section.py` for the gate) — this is the
        # backstop for a pass run without it.
        from concolic_engine.completion import attach_to_summary
        try:
            with open(cc_path) as fh:
                attach_to_summary(summary, json.load(fh))
        except Exception as exc:                      # noqa: BLE001
            import traceback
            traceback.print_exc()
            summary["completion"] = {
                "complete": False,
                "blocking": [f"completion gate RAISED: {type(exc).__name__}: "
                             f"{str(exc)[:400]} — the COVERAGE numbers in this "
                             f"file stand; re-run the gate alone with "
                             f"_engine_section.py (SUMMARY_IN=this file)"]}
            summary["complete"] = False
            print("[completion] gate raised; coverage numbers preserved, "
                  "summary written with the gate marked BLOCKING", flush=True)
    else:
        # A coverage-only pass must NEVER leave a summary that claims
        # completeness (2026-08-27: a killed report left `complete: true`
        # with no completion section, and that file was read as a result).
        summary["completion"] = {"complete": False,
                                 "blocking": ["completion gate did not run "
                                              "(coverage-only pass / SKIP_COMPLETION)"]}
        summary["complete"] = False

    out = os.environ.get("SUMMARY_OUT") or os.path.join(HERE, "coverage_summary.json")
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=False)

    print(f"OVERALL_COMPLETE={summary['complete']};COMPLETION={'n/a' if summary['completion'] is None else summary['completion']['complete']}")
    print(f"COMPLETE={result.complete};NODES={result.total_nodes};"
          f"MISSING={len(result.missing)};BLOCKING={len(blocking)};PCS={total_pcs}")
    print(f"GENUINE={genuine};TRUNCATED={result.truncated};SOLVER_LOST={result.solver_lost};"
          f"UNEVALUABLE={list(result.unevaluable_exprs)}")
    print(f"SUBCONJ_FORECLOSURES={summary['subconjunction_foreclosures']};"
          f"SUBCONJ_CONDS={summary['subconjunction_foreclosure_conditions']};"
          f"SUBCONJ_WIDTH={summary['subconjunction_foreclosure_width']};"
          f"SUBCONJ_PROVISIONAL={summary['subconjunction_foreclosures_provisional']}",
          flush=True)
    print(f"WF_DROPS={summary['wellfounded_drops']};"
          f"WF_CONDS={summary['wellfounded_drop_conditions']};"
          f"WF_PROVISIONAL={summary['wellfounded_drops_provisional']}",
          flush=True)
    print(f"CONJ_FORECLOSURES={summary['conjunction_foreclosures']};"
          f"CONJ_GROUPS={summary['conjunction_foreclosure_groups']};"
          f"CONJ_PROVISIONAL={summary['conjunction_foreclosures_provisional']};"
          f"UNMATCHED_CONJ={summary['unmatched_gate_conjunctions']};"
          f"FORECLOSURES={summary['foreclosures']}")
    print(f"dump_errors={dict(dump_errors)}")
    import resource as _res
    print(f"wrote {out} in {wall:.1f}s; peak RSS "
          f"{_res.getrusage(_res.RUSAGE_SELF).ru_maxrss // 1024} MB")
    return 0 if summary['complete'] else 1


if __name__ == "__main__":
    sys.exit(main())
