#!/usr/bin/env python3
"""Parallelise step 6 (per-demand-set enumeration) of concolic_engine/coverage.py.

WHAT IT CHANGES
---------------
Step 6 solved one demand set at a time.  The sets are independent: each produces
its own missing-leaf verdict and witness, and the only cross-set state the
expensive part touches is the `reported` output dedup -- which influences
nothing that feeds back into the solver (it gates `missing.append` only, after
the blocking clause and the per-set record have already been built).

The loop is therefore split into three phases:

  6a PRELUDE  (parent, canonical order) -- `restrict_foreclosures` per set and
     its `foreclosures_applied` / `foreclosures_ignored` / `gate_counts` fold.
     Unchanged code, just hoisted.
  6b ENUMERATE -- the expensive body, now a pure function of one set that
     RETURNS the checkpoint record and touches no shared state.  Run serially
     or across a fork pool.
  6c FOLD (parent, canonical order) -- every set's record is folded through
     EXACTLY the existing checkpoint-REPLAY branch, then written to the
     checkpoint by the parent.

DETERMINISM
-----------
* The fold is in the sets' canonical order, never completion order: results are
  collected by index (`imap`, which preserves order) and folded in a second
  pass over `demands`.
* Z3: `solve_and_evaluate` already builds a private `z3.Context()` per query
  (solver.py, the DISCIPLINE §16d change), so no model choice depends on
  context state carried between queries, in this process or another.
* The two caches the body shares across sets -- `conj_pmask` (via `_pmask`) and
  `subconj_memo` (via `_subconj`) -- are pure memos: the value is a function of
  the key alone, so a worker that misses simply recomputes the same answer.
  Per-worker copies change timing, never results.
* `_record_conj` / `_record_subconj` / `_record_wf` are removed from the body
  and driven entirely from the record's `conj` / `subconj` / `wf` cut lists by
  the parent.  They are idempotent on their dedup keys, so this is what the
  replay branch has always done.

CHECKPOINTS
-----------
Written by the PARENT from completed results, never by a worker.  That is the
safer of the two options the brief allowed and it is not just about locking:
`Checkpoint` owns an append-mode fd, an `atexit` hook and SIGINT/SIGTERM
handlers (checkpoint.py), all of which a forked child inherits -- a child that
wrote through that fd, or exited through that atexit hook, would duplicate or
truncate the parent's file.  Workers never see the object.  The parent writes
records in canonical set order, so the on-disk file is byte-comparable with a
serial run's.

The width is NOT folded into the checkpoint key: it changes nothing step 6
reads, and keying on it would invalidate every checkpoint on a box with a
different core count.  (The engine SOURCE HASH is in the key, so this edit does
invalidate existing coverage checkpoints -- unavoidable and accepted.)

KNOB
----
`COVERAGE_PAR` (environment only -- the CoverageChecker signature is
untouched, so nothing in the test suite or any driver has to change):
  unset / "0" / "1"  -> serial, the differential baseline
  "auto"             -> min(cpu_count, (MemAvailable - 4G) / 2.5G, len(todo))
  "<n>"              -> that many workers
"""
import hashlib
import re
import shutil
import sys
import time
from pathlib import Path

# --------------------------------------------------------------------------
# 1. module-level helpers (inserted before _EMPTY_SET_RECORD)
# --------------------------------------------------------------------------
ANCHOR_EMPTY = "_EMPTY_SET_RECORD: t.Dict[str, t.Any] = {"

MODULE_HELPERS = '''# -- step-6 process pool (2026-09-14) ---------------------------------------
# The per-demand-set enumeration is embarrassingly parallel (see
# `check_coverage`, phase 6b).  The worker body is a CLOSURE over the whole of
# `check_coverage`'s state -- the corpus, the profile bitsets, the memos -- and
# none of that is picklable or cheap to send, so the pool is a FORK pool and
# the closure is handed to the children through this module global, which they
# inherit across the fork.  Only an integer index goes down the pipe and only
# one record dict comes back.
_PAR_BODY: t.Optional[t.Callable[[int], t.Dict[str, t.Any]]] = None


def _par_enumerate(i: int) -> t.Dict[str, t.Any]:
    """Pool entry point: module-level (so picklable), closure inherited."""
    if _PAR_BODY is None:  # pragma: no cover - defensive
        raise RuntimeError("step-6 worker started without a body")
    return _PAR_BODY(i)


def _par_child_init() -> None:
    """Detach a forked worker from the parent's interrupt handling.

    The parent's ``Checkpoint`` installs SIGINT/SIGTERM handlers that flush and
    close ITS append-mode fd; a child that inherited them and was signalled
    would write the parent's buffer a second time.  Workers never touch the
    checkpoint, so they ignore both signals and let the pool tear them down.
    """
    import signal as _sig
    try:
        _sig.signal(_sig.SIGINT, _sig.SIG_IGN)
        _sig.signal(_sig.SIGTERM, _sig.SIG_DFL)
    except Exception:  # pragma: no cover - not all platforms
        pass


def _par_width(requested: t.Optional[str], n_jobs: int) -> int:
    """Worker count: 1 (serial) unless explicitly opted in.

    ``auto`` is capped by MEMORY as well as cores.  A forked worker shares the
    parent's corpus copy-on-write, but CPython's refcounts dirty the pages it
    walks, so the steady state is closer to a private copy than to a shared
    one; budget ~2.5 GB per worker on top of the parent and keep 4 GB spare.
    """
    if not requested or requested in ("0", "1"):
        return 1
    if requested != "auto":
        try:
            w = int(requested)
        except ValueError:
            return 1
        return max(1, min(w, n_jobs))
    import os as _os
    cpu = _os.cpu_count() or 1
    mem_w = cpu
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                if line.startswith("MemAvailable:"):
                    kb = int(line.split()[1])
                    mem_w = int((kb - 4 * 1024 * 1024) / (2.5 * 1024 * 1024))
                    break
    except Exception:  # pragma: no cover - non-Linux
        pass
    return max(1, min(cpu, mem_w, n_jobs))


'''

# --------------------------------------------------------------------------
# 3. the loop rewrite
# --------------------------------------------------------------------------
ANCHOR_LOOP_HEAD = """        for demand in demands:
            group = sorted(demand, key=order.__getitem__)
            dmask = 0
            for e in group:
                dmask |= 1 << bit[e]

            # This set's own foreclosures: the global relation restricted to
            # its members, then ordered so every gate precedes what it
            # forecloses (backward/cyclic edges are dropped, see the helper).
            group, local, ign = restrict_foreclosures(group, forecl_by_gate, bit)
            foreclosures_ignored += ign
            for (g, o), m in local.items():
                n = bin(m).count("1")
                foreclosures_applied += n
                key = f"{g} :: {'taken' if o else 'not_taken'}"
                gate_counts[key] = gate_counts.get(key, 0) + n
"""

NEW_LOOP_HEAD = '''        # -- 6a. PRELUDE, one pass over the sets in CANONICAL order. Exactly
        # the code that always ran at the top of the loop; hoisted so the
        # foreclosure counters are folded once, in set order, whether the
        # set's verdict is then computed here, in a worker, or replayed.
        prelude: t.List[t.Tuple[
            t.FrozenSet[str], t.List[str],
            t.Dict[t.Tuple[str, bool], int], int, str]] = []
        for demand in demands:
            group = sorted(demand, key=order.__getitem__)
            dmask = 0
            for e in group:
                dmask |= 1 << bit[e]

            # This set's own foreclosures: the global relation restricted to
            # its members, then ordered so every gate precedes what it
            # forecloses (backward/cyclic edges are dropped, see the helper).
            group, local, ign = restrict_foreclosures(group, forecl_by_gate, bit)
            foreclosures_ignored += ign
            for (g, o), m in local.items():
                n = bin(m).count("1")
                foreclosures_applied += n
                key = f"{g} :: {'taken' if o else 'not_taken'}"
                gate_counts[key] = gate_counts.get(key, 0) + n
            dkey = _checkpoint.digest(group) if ckpt is not None else ""
            prelude.append((demand, group, local, dmask, dkey))

        # -- 6b. ENUMERATE. One demand set, start to finish, as a PURE
        # function: it returns the checkpoint record and touches no state any
        # other set can see. `reported`/`missing`, the `_record_*` counters
        # and the checkpoint itself are all folded by the parent in 6c, which
        # is why this can run in a worker at all.
        def _enumerate_set(_idx: int) -> t.Dict[str, t.Any]:
            demand, group, local, dmask, dkey = prelude[_idx]
'''

# the old replay branch head: `dkey`/`rec`/`if rec is not None:` ... through the
# terminating `continue`.  Replaced by nothing here (the body follows); the
# replay text is re-used verbatim in phase 6c.
ANCHOR_REPLAY_HEAD = """            # A recorded set is REPLAYED, not recomputed: the cube census and
            # every Z3 call below are skipped and the set's contribution to
            # the globals is re-applied in the same order, so the result is
            # the one the uninterrupted pass would have produced. The
            # cross-set `reported` dedup is re-evaluated here (not stored),
            # because it depends on the sets processed BEFORE this one and
            # those are replayed in the same deterministic order.
            dkey = _checkpoint.digest(group) if ckpt is not None else ""
            rec = ckpt.get(dkey) if ckpt is not None else None
            if rec is not None:
"""

ANCHOR_RECORD_CONJ_CENSUS = """                                    _record_conj(pt, fm, a_cnt)
"""
ANCHOR_RECORD_SUBCONJ_CENSUS = """                                    for cond_, e_, a_c2 in subq:
                                        _cut(cond_, e_, a_c2)
                                        _record_subconj(cond_, e_, a_c2)
                                    del subq[:]
"""
NEW_RECORD_SUBCONJ_CENSUS = """                                    for cond_, e_, a_c2 in subq:
                                        _cut(cond_, e_, a_c2)
                                    del subq[:]
"""
ANCHOR_RECORD_WF_CENSUS = """                                        _cut_wf(cond_, e_, a_c2)
                                        _record_wf(cond_, e_, a_c2)
"""
NEW_RECORD_WF_CENSUS = """                                        _cut_wf(cond_, e_, a_c2)
"""

ANCHOR_SPACE_COVERED = """            if space_covered:
                if ckpt is not None:
                    if conj_cuts or sub_cuts or wf_cuts:
                        rec_e = dict(_EMPTY_SET_RECORD,
                                     conj=conj_cuts, subconj=sub_cuts)
                        if wf_cuts:
                            rec_e["wf"] = wf_cuts
                        ckpt.put(dkey, rec_e)
                    else:
                        ckpt.put(dkey, _EMPTY_SET_RECORD)
                continue
"""
NEW_SPACE_COVERED = """            if space_covered:
                # The record for a set whose space the corpus already covers.
                # `dict(...)` COPIES `_EMPTY_SET_RECORD` in both arms: it is a
                # module-level dict and `Checkpoint.put` stores what it is
                # handed, so returning the shared object would let one set's
                # record alias every other's.
                if conj_cuts or sub_cuts or wf_cuts:
                    rec_e = dict(_EMPTY_SET_RECORD,
                                 conj=conj_cuts, subconj=sub_cuts)
                    if wf_cuts:
                        rec_e["wf"] = wf_cuts
                    return rec_e
                return dict(_EMPTY_SET_RECORD)
"""

ANCHOR_RECORD_CONJ_EMIT = """                    _record_conj(pfx, forecl_m, a_count)
                    if forecl_m:
"""
NEW_RECORD_CONJ_EMIT = """                    if forecl_m:
"""
ANCHOR_RECORD_SUBCONJ_EMIT = """                            cond, a_c = hit
                            _record_subconj(cond, e, a_c)
                            _cut(cond, e, a_c)
"""
NEW_RECORD_SUBCONJ_EMIT = """                            cond, a_c = hit
                            _cut(cond, e, a_c)
"""
ANCHOR_RECORD_WF_EMIT = """                            _record_wf(got[0], e, got[1])
                            _cut_wf(got[0], e, got[1])
"""
NEW_RECORD_WF_EMIT = """                            _cut_wf(got[0], e, got[1])
"""

ANCHOR_EMIT_TAIL = '''                seen_here.add(key)
                blocks.append(_block_constraint(combo))
                found += 1
                set_combos.append(list(combo))
                set_models.append(model)
                if key in reported:
                    # ACROSS sets a repeat is legitimate under §16b: a
                    # foreclosure-truncated leaf (e.g. the gate arm alone) is a
                    # cube of several sets at once. Block it and count it, but
                    # do not print the same witness twice. NOTE: `len(missing)`
                    # is therefore no longer exactly "sets with a gap" — the
                    # per-set census is the number to quote.
                    continue
                reported.add(key)
                missing.append(
                    MissingCoverage(
                        node_constraint=" AND ".join(
                            _outcome_constraint(e, o) for e, o in combo
                        ),
                        source_location=(
                            expr_location[group[0]] if len(group) == 1 else ""
                        ),
                        missing_branch="combination",
                        missing_constraint=_combo_constraint(combo),
                        prefix=tuple(
                            PathCondition(expr=e, taken=o) for e, o in combo
                        ),
                        concrete_values=model or {},
                    )
                )
            else:
                set_trunc = True  # cap reached with combos still being found
            # fold this set's contribution into the globals (nothing in the
            # loop above reads them) and record it, so a rerun skips the set
            total_elapsed += set_elapsed
            solver_lost += set_lost
            truncated = truncated or set_trunc
            if ckpt is not None:
                rec_out: t.Dict[str, t.Any] = {
                    "elapsed_ms": set_elapsed,
                    "solver_lost": set_lost,
                    "truncated": set_trunc,
                    "combos": set_combos,
                    "models": set_models}
                if conj_cuts:
                    rec_out["conj"] = conj_cuts
                if sub_cuts:
                    rec_out["subconj"] = sub_cuts
                if wf_cuts:
                    rec_out["wf"] = wf_cuts
                ckpt.put(dkey, rec_out)
        if ckpt is not None:
            ckpt.close()
'''

NEW_EMIT_TAIL = '''                seen_here.add(key)
                blocks.append(_block_constraint(combo))
                found += 1
                set_combos.append(list(combo))
                set_models.append(model)
                # The cross-set `reported` dedup and the `missing` emission
                # that used to sit here are the parent's job (6c): they are
                # the only cross-set state this body ever touched, and they
                # gate nothing the solver or the blocking clauses read -- the
                # clause, `found` and the record are all already updated
                # above. That is exactly what the REPLAY branch has always
                # re-derived, which is why moving it changes no answer.
            else:
                set_trunc = True  # cap reached with combos still being found
            rec_out: t.Dict[str, t.Any] = {
                "elapsed_ms": set_elapsed,
                "solver_lost": set_lost,
                "truncated": set_trunc,
                "combos": set_combos,
                "models": set_models}
            if conj_cuts:
                rec_out["conj"] = conj_cuts
            if sub_cuts:
                rec_out["subconj"] = sub_cuts
            if wf_cuts:
                rec_out["wf"] = wf_cuts
            return rec_out

        # -- 6b'. which sets still need computing, and at what width.
        todo = [i for i, (_d, _g, _l, _dm, _dk) in enumerate(prelude)
                if ckpt is None or ckpt.get(_dk) is None]
        todo_set = set(todo)

        # -- 6c. FOLD, in the sets' CANONICAL order, never completion order.
        # Every record -- computed here, computed in a worker, or read from the
        # checkpoint -- goes through the SAME path, which is the replay branch
        # this loop has always had. `fresh` is consumed STREAMING, in step with
        # the walk over `demands`, so the checkpoint is still written set by set
        # as work completes and an interrupted pass loses only what it had not
        # folded -- exactly the old guarantee.
        def _fold(fresh_recs: t.Iterator[t.Dict[str, t.Any]]) -> None:
            nonlocal total_elapsed, solver_lost, truncated
            for _i, (demand, group, local, dmask, dkey) in enumerate(prelude):
                if _i in todo_set:
                    rec = next(fresh_recs)
                    fresh = True
                else:
                    rec = ckpt.get(dkey) if ckpt is not None else None
                    fresh = False
                if rec is None:  # pragma: no cover - defensive
                    raise RuntimeError(f"step 6: no record for demand set {_i}")
                total_elapsed += rec.get("elapsed_ms", 0.0)
                solver_lost += rec.get("solver_lost", 0)
                for _pfx, _mem, _a in rec.get("conj", ()):
                    _record_conj(tuple((e, bool(o)) for e, o in _pfx),
                                 tuple(_mem), _a)
                for _cnd, _mem, _a in rec.get("subconj", ()):
                    _record_subconj(tuple((e, bool(o)) for e, o in _cnd),
                                    _mem, _a)
                for _cnd, _mem, _a in rec.get("wf", ()):
                    _record_wf(tuple((e, bool(o)) for e, o in _cnd),
                               _mem, _a)
                if rec.get("truncated"):
                    truncated = True
                for combo_l, model in zip(rec.get("combos", ()),
                                          rec.get("models", ())):
                    combo = [(e, bool(o)) for e, o in combo_l]
                    ckey = tuple(combo)
                    if ckey in reported:
                        continue
                    reported.add(ckey)
                    missing.append(
                        MissingCoverage(
                            node_constraint=" AND ".join(
                                _outcome_constraint(e, o) for e, o in combo
                            ),
                            source_location=(
                                expr_location[group[0]] if len(group) == 1 else ""
                            ),
                            missing_branch="combination",
                            missing_constraint=_combo_constraint(combo),
                            prefix=tuple(
                                PathCondition(expr=e, taken=o) for e, o in combo
                            ),
                            concrete_values=model or {},
                        )
                    )
                # The PARENT is the only writer of the checkpoint. `Checkpoint`
                # owns an append fd, an atexit hook and SIGINT/SIGTERM handlers
                # that a forked child inherits; a child writing through that fd,
                # or exiting through that hook, would duplicate or truncate the
                # parent's file. Records are written in canonical set order, so
                # the file is byte-comparable with a serial run's.
                if ckpt is not None and fresh:
                    ckpt.put(dkey, rec)

        width = _par_width(os.environ.get("COVERAGE_PAR"), len(todo))
        if width > 1:
            # FORK, not spawn: the worker body closes over the whole corpus and
            # the profile bitsets, which are neither picklable nor cheap to
            # send. `gc.freeze()` moves everything already allocated out of the
            # collector's generations before the fork, so a collection in a
            # child does not walk -- and copy-on-write -- the parent's whole
            # heap. Only an index goes down the pipe; only a record comes back.
            import gc as _gc
            import multiprocessing as _mp
            global _PAR_BODY
            _PAR_BODY = _enumerate_set
            _gc.collect()
            _gc.freeze()
            try:
                _ctx = _mp.get_context("fork")
                with _ctx.Pool(width, initializer=_par_child_init) as _pool:
                    # `imap` with chunksize=1: set costs are wildly uneven, and
                    # imap PRESERVES ORDER, so records arrive in canonical set
                    # order however the workers finished.
                    _fold(_pool.imap(_par_enumerate, todo, chunksize=1))
            finally:
                _PAR_BODY = None
                _gc.unfreeze()
        else:
            _fold(_enumerate_set(_i) for _i in todo)
        if ckpt is not None:
            ckpt.close()
'''


def splice(src: str, old: str, new: str, label: str) -> str:
    n = src.count(old)
    assert n == 1, f"anchor {label!r} matched {n} times, expected exactly 1"
    return src.replace(old, new)


def patch(path: Path) -> None:
    src = path.read_text()
    assert "_PAR_BODY" not in src, f"{path}: already patched"

    src = splice(src, ANCHOR_EMPTY, MODULE_HELPERS + ANCHOR_EMPTY, "module-helpers")
    src = splice(src, ANCHOR_LOOP_HEAD, NEW_LOOP_HEAD, "loop-head")

    # the old replay branch: delete it from the loop (re-used verbatim in 6c)
    i = src.index(ANCHOR_REPLAY_HEAD)
    assert src.count(ANCHOR_REPLAY_HEAD) == 1, "replay-head not unique"
    j = src.index("            # per-set accumulators: what the checkpoint record holds\n", i)
    src = src[:i] + src[j:]

    src = splice(src, ANCHOR_RECORD_CONJ_CENSUS, "", "record-conj-census")
    src = splice(src, ANCHOR_RECORD_SUBCONJ_CENSUS, NEW_RECORD_SUBCONJ_CENSUS,
                 "record-subconj-census")
    src = splice(src, ANCHOR_RECORD_WF_CENSUS, NEW_RECORD_WF_CENSUS,
                 "record-wf-census")
    src = splice(src, ANCHOR_SPACE_COVERED, NEW_SPACE_COVERED, "space-covered")
    src = splice(src, ANCHOR_RECORD_CONJ_EMIT, NEW_RECORD_CONJ_EMIT,
                 "record-conj-emit")
    src = splice(src, ANCHOR_RECORD_SUBCONJ_EMIT, NEW_RECORD_SUBCONJ_EMIT,
                 "record-subconj-emit")
    src = splice(src, ANCHOR_RECORD_WF_EMIT, NEW_RECORD_WF_EMIT, "record-wf-emit")
    src = splice(src, ANCHOR_EMIT_TAIL, NEW_EMIT_TAIL, "emit-tail")

    # -- post-conditions --------------------------------------------------
    assert "_record_conj(pt, fm, a_cnt)" not in src, "a census _record_conj survived"
    assert src.count("def _enumerate_set") == 1
    assert src.count("_pool.imap(_par_enumerate") == 1
    assert "ckpt.close()" in src
    compile(src, str(path), "exec")   # syntax gate before anything is written

    bak = path.with_name(path.name + f".seq_{time.strftime('%Y%m%d_%H%M%S')}")
    shutil.copy2(path, bak)
    path.write_text(src)
    print(f"patched {path}\n  backup {bak}\n  md5 {hashlib.md5(src.encode()).hexdigest()[:8]}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(Path(p))
