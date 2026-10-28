#!/usr/bin/env python3
"""ASSUMPTION CHECKER — the main assumption verification driver
(plain name for what CHECKS.md Part II calls A1+A2; run at the END of a
generation, against the final evidence layer).

    python3 assumption_checker.py <manifest.json> [--scan-only] [--keep]

Manifest (JSON):
{
  "batch_dir": "reports/diaspora/results3/notifications_index",
  "runner":    "scripts/diaspora-concolic /abs/path/run_dse.rb",
  "workdir":   "/home/dev/project",
  "assumptions": [
    {"name": "persisted-foreclosure",
     "kind": "foreclosure",             // or "independence"
     "dimension": "SYM_RESULT_ActiveRecord__Relation_to_ary_1_row_persisted",
     "flip_to": false,                   // optional; booleans auto-flip
     "expect_pc_substring": "_persisted == False"}  // foreclosure only
  ]
}

Per assumption, the DIRECTED PROBE (the controlled experiment):
  1. pick a snapshot dump whose applied seed dict contains the dimension
     (richest dict wins), freeze its ENTIRE seed dict;
  2. write a probe seed file identical except the one flipped dimension,
     replay deterministically (SEEDS_ONLY=1);
  3. compare probe vs snapshot ON THE OTHER EVIDENCE — the PC set and
     SELECT-note set, excluding entries mentioning the dimension itself:
       independence: both diffs must be EMPTY (the flip influenced
         nothing else, under identical inputs);
       foreclosure: the diff must be NON-EMPTY (a silently-absorbed flip
         is a dead knob) AND expect_pc_substring must appear in the
         probe's recorded PCs (the forced state is labeled, not leaking).

Plus the CORPUS SCAN (the standing tripwire): every run whose seeds set
the dimension must show recorded PCs consistent with that seed — a
contradiction is a violation witness on one run.

Exit 1 on any failed assumption. On probe failure, diagnose with the
line-diff of the probe pair (coverage_probe) — see CHECKS.md A3.
"""
import array
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter

# AliasAssumption support (2026-09-08; loop keying 2026-09-09): the engine's
# alias helpers are the single source of the identity a result is given; the
# gate must compute the SAME map from the same dump, so it imports them rather
# than re-implementing them.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from concolic_engine import checkpoint as _ckpt  # noqa: E402
from concolic_engine.assumptions import (AliasAssumption, alias_keys_for,  # noqa: E402
                                         call_shape, renamer, shape_str,
                                         statement_key)
from concolic_engine.names import NameSpace, same_variable  # noqa: E402

# Set by main() from the manifest's "canonicalize" ("module:function", the
# module resolved on batch_dir) and from the declared Alias assumptions. When unset every dump is read exactly as before (inert).
_CANON_FN = None
_ALIASES = None
_ALIAS_INDEX = {}   # batch -> {dump path: ((ordinal, canonical, key, len_value), ...)}


# --- corpus index (2026-08-26, perf): a 10k-dump corpus made the per-
# assumption glob+load (O(assumptions x dumps)) unusable. One pass builds a
# light index (seeds, scenario, recorded PC exprs); only the CHOSEN snapshot
# is loaded in full (LRU). Selection semantics are unchanged.
_INDEX = {}
# Confinement (§16c, 2026-09-11): per dump, (outcome-profile digest, shape
# strings, recorded (expr, taken) pairs) — what the exhaustive flip over
# profiles selects its representatives by. Built in the same pass as _INDEX.
_TRACE_INDEX = {}
_SYMLEN_RE = re.compile(r"SYM_LEN_([A-Za-z0-9_]+)")


# --- progress heartbeat (owner rule, 2026-09-12) ---------------------------
# The gate's PRE-PROBE work -- building the corpus index, then deriving the
# probes every declaration needs -- is minutes to hours on a real corpus, and
# it used to print NOTHING until it was over: posts_show's 2026-09-12 run
# spent 5 h 59 m in it and left four lines in the log, so a slow phase and a
# hung one looked exactly the same. Every phase now names itself on a timer.
#: Seconds between heartbeat lines. 0 (or an unparsable value) disables them.
HEARTBEAT_ENV = "ACHK_HEARTBEAT_S"
HEARTBEAT_DEFAULT_S = 60.0


def _rss_mb():
    """This process's resident set size in MiB (0.0 where unavailable)."""
    try:
        import resource
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    except Exception:  # noqa: BLE001 - a progress line must never fail a job
        return 0.0
    return rss / 1048576.0 if sys.platform == "darwin" else rss / 1024.0


class _Progress:
    """``[phase] done/total elapsed rate eta rss`` on a timer.

    SILENT for a phase that finishes inside one interval, so a small corpus
    (and the test suite) produces exactly the output it did before; a phase
    that has heartbeated once also prints a closing line.
    """

    def __init__(self, phase, total, every=None, out=None):
        self.phase, self.total = phase, total
        self.out = out if out is not None else (lambda line: print(line, flush=True))
        if every is None:
            try:
                every = float(os.environ.get(HEARTBEAT_ENV) or HEARTBEAT_DEFAULT_S)
            except ValueError:
                every = HEARTBEAT_DEFAULT_S
        self.every = every
        self.t0 = self.last = time.monotonic()
        self.n = 0
        self.beats = 0

    def _line(self, tag, note):
        el = time.monotonic() - self.t0
        rate = (self.n / el) if el > 0 else 0.0
        eta = ((self.total - self.n) / rate) if (rate > 0 and self.total) else 0.0
        return (f"  [{self.phase}] {tag} {self.n}/{self.total} "
                f"elapsed {el:.0f}s rate {rate:.1f}/s"
                + (f" eta {eta:.0f}s" if eta > 0 else "")
                + f" rss {_rss_mb():.0f}MB" + (f" {note}" if note else ""))

    def tick(self, n=1, note=""):
        self.n += n
        if self.every <= 0:
            return
        now = time.monotonic()
        if now - self.last < self.every:
            return
        self.last = now
        self.beats += 1
        self.out(self._line("...", note))

    def done(self, note=""):
        if self.every > 0 and self.beats:
            self.out(self._line("done", note))


# --- corpus-index checkpoint (owner rule, 2026-09-12) ----------------------
#: Env var enabling it. `corpus_index` is ONE full parse of every dump in the
#: batch -- 54 s per 2 000 dumps measured, ~50 min on posts_show's 194 262 --
#: and it was redone from zero on every relaunch of the gate. Unset = the
#: behaviour the gate has always had, byte for byte.
#:
#: INCREMENTAL since 2026-09-14. It used to be keyed, whole, on a digest of
#: the corpus, so ANY drive round -- which is to say every round, a drive
#: round is how dumps come to exist -- moved the key and rebuilt all of it
#: from zero: notifications declined to run its engine section at all rather
#: than spend 2 h 20 m re-indexing 130k dumps for 422 new ones. That was
#: always wrong in principle: a row is computed from ONE dump (`_index_row`)
#: and recorded per dump, so a corpus that only gained dumps owes only the
#: new ones. The key now carries the IDENTITY of the computation (see
#: `_phase_keys`) and each row carries the size of the dump it came from
#: (`_ROW_STAMP`), which is the same evidence the whole-corpus digest was
#: built out of -- applied per row instead of over the set. Rows whose dump
#: is gone are dropped and the log is compacted (`_compact_index_log`).
INDEX_CKPT_ENV = "ACHK_INDEX_CHECKPOINT"

#: Field under which a recorded row carries its dump's own validity stamp.
#: See `_row_stamp`.
_ROW_STAMP = "z"

#: Digest of the DECLARED assumption set, set by `run_declared`. It is part of
#: the DERIVE checkpoint's key (a representative set is corpus- and
#: declaration-dependent) but NOT of the index's: the declared set reaches an
#: index row only through `_ALIASES`, and `_canon_key` digests those exactly.
_DECLARED_DIGEST = ""


_CORPUS_DIGEST = {}


def _corpus_digest(paths, batch=None):
    """Digest of the corpus AS THE INDEX READS IT: the name and size of every
    dump, in order. A dump is written once and never edited, so this changes
    exactly when the corpus does."""
    if batch is not None and batch in _CORPUS_DIGEST:
        return _CORPUS_DIGEST[batch]
    h = hashlib.blake2b(digest_size=16)
    for p in paths:
        try:
            size = os.path.getsize(p)
        except OSError:
            size = -1
        h.update(f"{os.path.basename(p)}:{size}\n".encode())
    if batch is not None:
        _CORPUS_DIGEST[batch] = h.hexdigest()
    return h.hexdigest()


def _phase_keys(batch, phase, corpus=True):
    """The header of any checkpoint over this corpus: what the phase reads.

    Two parts, and the split is the whole of the 2026-09-14 change:

    * the IDENTITY part -- how a unit is COMPUTED. The engine's own source
      (this module AND `concolic_engine.assumptions`, which supplies
      `call_shape`/`shape_str`/`alias_keys_for`, i.e. half of what a row
      says), the phase, the batch directory, and `_canon_key` (the load
      hook's identity and source plus the alias declarations that steer it).
      A change to any of these changes what the SAME dump would index to, so
      it invalidates everything and must.
    * the CORPUS part -- WHICH units exist. `corpus=False` leaves it out, for
      a phase whose records are per-dump and self-validating: see
      `corpus_index`, where each row carries its own dump's stamp and a
      corpus that grew costs only the dumps it grew by.

    `corpus=True` (the default, and what `profile_representatives` keeps) is
    the old, all-or-nothing behaviour: a derivation reads the corpus AS A
    WHOLE -- one representative per outcome profile, ranked against every
    other candidate, plus the profile COUNT that decides testability -- so a
    dump added anywhere can legitimately change it, and it is not sound to
    keep a record that was computed before that dump existed.
    """
    keys = {"engine": _ckpt.source_hash(
                sys.modules[__name__],
                sys.modules.get(AliasAssumption.__module__)),
            "phase": f"assumption_checker:{phase}",
            "batch": os.path.realpath(batch),
            "canonicalize": _canon_key()}
    if corpus:
        keys["corpus"] = _corpus_digest(
            sorted(glob.glob(os.path.join(batch, "dump_*.json"))), batch)
        keys["declared"] = _DECLARED_DIGEST
    return keys


def _row_stamp(path):
    """The validity stamp of ONE dump: ``[size, mtime_ns]``.

    This is the per-row replacement for the whole-corpus digest, and it is
    strictly stronger than the atom that digest was built out of (name +
    size; the name is the record's own key). `mtime_ns` costs nothing -- the
    same `stat` -- and catches the one thing size alone cannot, a same-length
    rewrite in place; dumps are written once and never edited, but `mv` (and
    a re-generated dump under a name that was used before) preserves neither
    claim, and a silently-wrong row poisons every verdict derived from it.

    The obvious objection to mtime -- that copying or restoring a corpus
    re-stamps every dump and forces a full rebuild -- does not arise for a
    COPY, because `_phase_keys` carries the batch's realpath and a copy
    therefore invalidates the whole checkpoint already; for an in-place
    restore it degrades to exactly today's behaviour, a rebuild.
    """
    try:
        st = os.stat(path)
    except OSError:
        return [-1, -1]
    return [st.st_size, st.st_mtime_ns]


def _lock_index_log(path, log=None):
    """Take the index log's writer lock, or None if someone else holds it.

    The log's string table makes ids POSITIONS in the file, so two processes
    appending to one log would each number their new strings from their own
    view of it and every later reader would decode the wrong string for half
    the rows -- silently. That was already possible (two gates on one batch
    with the same key and the same path), and it gets likelier now that the
    key no longer moves when the corpus or the declared set does, which is
    exactly when a second round runs beside the first. So: one writer at a
    time, and a process that cannot have the lock indexes WITHOUT the
    checkpoint -- correct, merely uncached, which is what every gate did
    before the variable existed.

    The lock is `flock` on a sidecar, so it dies with the process that holds
    it (a killed gate never leaves the log locked).
    """
    log = log or (lambda m: print(m, flush=True))
    try:
        import fcntl
    except ImportError:                         # pragma: no cover - not POSIX
        return None
    try:
        d = os.path.dirname(os.path.abspath(path)) or "."
        os.makedirs(d, exist_ok=True)
        fh = open(path + ".lock", "a+", encoding="utf-8")
    except OSError as exc:
        log(f"  [corpus-index] no checkpoint ({path}.lock: {exc})")
        return None
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        log(f"  [corpus-index] another process is writing {path}; "
            "indexing WITHOUT the checkpoint (one writer at a time)")
        return None
    return fh


def _compact_index_log(path, drop, log=None):
    """Rewrite an index checkpoint without the rows whose dump is gone.

    An append log cannot forget a record (`Checkpoint.pop` forgets only in
    memory), so a corpus that LOSES dumps would otherwise carry their rows
    for ever -- 350 MB of them on posts_show. The rewrite is purely
    syntactic: it never decodes a row. The one thing it must preserve is the
    `_RowCodec` string table, whose ids are positions in the sequence of
    FIRST mentions across the file, so the strings a dropped record
    introduced are hoisted onto the next surviving record's ``+`` list. The
    sequence of first mentions is then unchanged and every id in the file
    still means what it meant. (Strings only the dropped rows used stay in
    the table: dead, bounded by the corpus's own history, and not worth a
    decode/re-encode pass over the whole log to reclaim.)

    A dump that was RE-indexed (its stamp moved) has two records in the log,
    of which only the last counts; the rewrite keeps that one. So the log
    holds exactly one record per dump of the corpus, as a fresh one would.

    Atomic: written beside the log and `os.replace`d, so a kill leaves the
    original. Returns the number of records dropped.
    """
    log = log or (lambda m: print(m, flush=True))
    tmp = f"{path}.compact-{os.getpid()}"
    dropped, pending = 0, []
    left = Counter()
    try:
        with open(path, "r", encoding="utf-8") as src:
            for lineno, line in enumerate(src):
                if lineno == 0 or not line.endswith("\n") or not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    break
                if isinstance(obj, dict) and "k" in obj:
                    left[obj["k"]] += 1
    except OSError as exc:
        log(f"  [corpus-index] could not compact {path}: {exc}")
        return 0
    try:
        with open(path, "r", encoding="utf-8") as src, \
                open(tmp, "w", encoding="utf-8") as out:
            for lineno, line in enumerate(src):
                if not line.endswith("\n"):
                    break                       # a torn tail is dropped
                if lineno == 0:
                    out.write(line)             # the header, verbatim
                    continue
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    break
                if not isinstance(obj, dict) or "k" not in obj:
                    continue
                left[obj["k"]] -= 1
                # a superseded record (the dump was re-indexed) is dropped
                # like a gone one: only the LAST record of a key counts.
                if obj["k"] not in drop and not left[obj["k"]]:
                    if not pending:
                        out.write(line)         # unchanged, byte for byte
                        continue
                    rec = obj.get("v")
                    if isinstance(rec, dict):
                        rec["+"] = pending + list(rec.get("+") or ())
                        pending = []
                    out.write(json.dumps(obj, default=str) + "\n")
                else:
                    dropped += 1
                    rec = obj.get("v")
                    if isinstance(rec, dict):
                        pending.extend(rec.get("+") or ())
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    except OSError as exc:                      # never fail a job over a cache
        log(f"  [corpus-index] could not compact {path}: {exc}")
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return 0
    return dropped


def _canon_key():
    """Identity of the load-time canonicalization -- the only other thing
    that decides what an index row says about a dump."""
    if _CANON_FN is None:
        return "none"
    mod = sys.modules.get(getattr(_CANON_FN, "__module__", "") or "")
    return _ckpt.digest(getattr(_CANON_FN, "__qualname__", str(_CANON_FN)),
                        _ckpt.source_hash(mod) if mod is not None else "?",
                        [(x.result_pattern, x.key, x.k) for x in (_ALIASES or [])])


class _RowCodec:
    """String-interning codec for index-checkpoint rows.

    A raw row is ~14 KB of JSON (117 seed keys, 33 PC expressions, 24 call
    shapes on posts_show) and almost all of it is strings that repeat in
    every dump of the corpus -- 2.6 GB of log, and the same again in memory
    on a resume. So the log carries a STRING TABLE: the first record that
    mentions a string emits it in ``+`` and every later reference is its
    integer id. The table is rebuilt by replaying the records IN FILE ORDER
    (`Checkpoint.items`), which is the order they were appended, so ids mean
    the same thing to the writer and to every later reader.
    """

    def __init__(self):
        self.ids = {}
        self.strs = []

    def _sid(self, value, new):
        i = self.ids.get(value)
        if i is None:
            i = self.ids[value] = len(self.strs)
            self.strs.append(value)
            new.append(value)
        return i

    def register(self, rec):
        """Take only the new strings of `rec` -- the file-order table pass."""
        for value in rec.get("+") or ():
            if value not in self.ids:
                self.ids[value] = len(self.strs)
                self.strs.append(value)

    def encode(self, row):
        new = []
        rec = {"p": [[self._sid(e, new), 1 if t else 0] for e, t in row["p"]],
               "h": [self._sid(z, new) for z in row["h"]],
               "k": [self._sid(k, new) for k in row["s"]],
               "v": list(row["s"].values()),
               "n": None if row["n"] is None else self._sid(row["n"], new)}
        if row.get("a"):
            rec["a"] = [[self._sid(o, new), self._sid(c, new),
                         None if k is None else self._sid(k, new), lv]
                        for o, c, k, lv in row["a"]]
        rec["+"] = new
        return rec

    def decode(self, rec):
        t = self.strs
        row = {"p": [[t[i], bool(x)] for i, x in rec["p"]],
               "h": [t[i] for i in rec["h"]],
               "s": dict(zip((t[i] for i in rec["k"]), rec["v"])),
               "n": None if rec["n"] is None else t[rec["n"]]}
        if rec.get("a"):
            row["a"] = [[t[o], t[c], None if k is None else t[k], lv]
                        for o, c, k, lv in rec["a"]]
        return row


def _index_row(path):
    """The JSON-able index row for one dump -- the expensive part of
    `corpus_index` (a full parse plus the load hook), and the unit the index
    checkpoint records."""
    d = _load_dump_uncached(path)
    row = {"s": dict(d.get("concolic_seeds") or {}),
           "n": (d.get("concolic_scenario") or {}).get("name"),
           "p": sorted({(canon(ev.get("expr", "")), bool(ev.get("taken")))
                        for ev in d.get("events") or []
                        if ev.get("type") == "path_condition"}),
           "h": sorted({shape_str(x) for x in access_trace(d)})}
    if d.get("_alias_map"):
        row["a"] = [[o, c, d["_alias_key"].get(o), d["_alias_len"].get(o)]
                    for o, c in d["_alias_map"].items()]
    del d
    return row


def _absorb_index_row(batch, path, row, idx, pool):
    """One index row -> its entries in `_INDEX` / `_TRACE_INDEX` /
    `_ALIAS_INDEX`. Everything that repeats across the corpus is interned in
    `pool`: at 22k dumps the un-interned index alone OOMs a 2.5 GB unit
    (2026-08-27)."""
    def _i(x):
        return pool.setdefault(x, x)

    pcs = frozenset(_i((_i(e), bool(t))) for e, t in row["p"])
    idx.append((path, {_i(k): v for k, v in (row.get("s") or {}).items()},
                _i(row.get("n")), frozenset(_i(e) for e, _t in row["p"])))
    digest = hashlib.blake2b(";".join(sorted(f"{e}:{int(t)}" for e, t in pcs)).encode(),
                             digest_size=8).hexdigest()
    _TRACE_INDEX.setdefault(batch, {})[path] = (
        digest, frozenset(_i(z) for z in row.get("h") or ()), pcs)
    if row.get("a"):
        _ALIAS_INDEX.setdefault(batch, {})[path] = tuple(
            (o, c, _i(k), lv) for o, c, k, lv in row["a"])


def canon(expr):
    """Canonical expr text for corpus matching: the coverage report's Z3
    rename `SYM_LEN_X` is mapped back to the runtime's `len(X)` (2026-08-26:
    without this, every declared expr over a list length silently never
    matched a dump and independences over it PASSed as "mutually exclusive")."""
    return _SYMLEN_RE.sub(r"len(\1)", str(expr))


def load_dump(path):
    return _load_dump_cached(path)


try:
    from functools import lru_cache
except ImportError:  # pragma: no cover
    lru_cache = None


#: Key under which `_load_dump_uncached` keeps a dump's `concolic_seeds`
#: EXACTLY as they were on disk, before the batch's `canonicalize` hook ran.
RAW_SEEDS_KEY = "_raw_concolic_seeds"


def seeds_as_written(dump):
    """The seed dict a dump carried ON DISK — what the runner was handed.

    A batch `canonicalize` hook is free to rewrite seed KEYS (the recorded
    case: `len(X)` -> `SYM_LEN_X`, because `len(X)` is not a Python
    identifier and the coverage universe is built on the renamed form). A
    probe seed file, though, is written in the RUNTIME's spelling and echoed
    back verbatim, so a probe may only be matched to its launch in that same
    spelling. Identity when no hook is installed."""
    raw = (dump or {}).get(RAW_SEEDS_KEY)
    return raw if raw is not None else ((dump or {}).get("concolic_seeds") or {})


def _load_dump_uncached(path):
    d = json.load(open(path))
    if _CANON_FN is not None:
        raw_seeds = dict(d.get("concolic_seeds") or {})
        # Alias bookkeeping BEFORE the rewrite: the statement keys are taken
        # over the raw notes (with earlier results already chain-identified,
        # see concolic_engine.assumptions._alias_core) and the length values
        # are read under the runtime's ordinal names.
        evs = [(ev.get("result_name"), ev.get("note"))
               for ev in d.get("events") or () if ev.get("type") == "symbolic_call"]
        # NAME BOUNDARY (2026-09-14): both sides are RAW here only because
        # this runs BEFORE `_CANON_FN`. One reordering and the table would be
        # built from `SYM_LEN_`-spelled vars while still read as `len(...)`,
        # producing an all-None `_alias_len` silently. NameSpace makes that
        # reordering raise instead of lying. See RUNBOOK Phase 2.
        lens = NameSpace({sv.get("name"): sv.get("value")
                          for sv in d.get("symbolic_vars") or ()
                          if str(sv.get("name", "")).startswith(("len(", "SYM_LEN_"))},
                         name="_alias_len source (pre-hook symbolic_vars)")
        # Ground-truth identity for the alias TEST: the statement WITH BINDS,
        # whatever key mode the declaration chose — a declaration that merges
        # different statements must be seen to do so.
        strict = [AliasAssumption(result_pattern=x.result_pattern, key="statement")
                  for x in (_ALIASES or [])]
        keys = alias_keys_for(evs, strict)
        amap = _CANON_FN(d, _ALIASES) if _ALIASES else _CANON_FN(d)
        d["_alias_map"] = dict(amap or {})
        d["_alias_key"] = {o: keys.get(o) for o in d["_alias_map"]}
        d["_alias_len"] = {o: lens.get(f"len({o}_rows)") for o in d["_alias_map"]}
        # AFTER the hook: `_CANON_FN` may replace the dict wholesale
        # (clear()+update()), so the pre-hook seeds are re-attached here.
        d[RAW_SEEDS_KEY] = raw_seeds
    return d


def _runtime_key(sd, key):
    """A seed key stated on CANONICAL names -> the key the RUNTIME seeds by
    (this snapshot's own ordinal names). Identity when nothing is aliased."""
    amap = sd.get("_alias_map") or {}
    if not amap or not key:
        return key
    return renamer({c: o for o, c in amap.items()})(key)


def _reading_changed(sd, probe, expr):
    """True iff an ordinal that carried one of `expr`'s results in the
    snapshot resolved to a DIFFERENT statement in the probe run: the flip
    changed the call sequence, so the probe's evidence is about another
    decision and the two runs are NOT COMPARABLE. An ordinal ABSENT from the
    probe (foreclosed) is not a changed reading."""
    amap = sd.get("_alias_map") or {}
    pm = (probe or {}).get("amap") or {}
    for o, c in amap.items():
        if c in str(expr) and o in pm and pm[o] != c:
            return f"{o.rsplit('_', 1)[1]} read as {c.rsplit('_', 2)[-2]}/{c[-8:]} in the snapshot, "\
                   f"{pm[o].rsplit('_', 2)[-2]}/{pm[o][-8:]} in the probe"
    return None


_load_dump_cached = lru_cache(maxsize=64)(_load_dump_uncached) if lru_cache else _load_dump_uncached


def corpus_index(batch):
    """[(path, seeds, scenario, {expr,...})] for every dump_*.json, built once.

    2026-09-12: unchanged in what it produces; it now reports progress
    (`_Progress`) and can RESUME from an index checkpoint
    (``$ACHK_INDEX_CHECKPOINT``, opt-in) instead of re-parsing the corpus.

    2026-09-14: still unchanged in what it produces, and the resume is now
    INCREMENTAL. The checkpoint's key holds only the identity of the
    computation (`_phase_keys(corpus=False)`); membership is settled row by
    row, because `_index_row` reads one dump and nothing else. A recorded row
    is replayed iff its dump is still there with the same stamp
    (`_row_stamp`), a dump with no valid row is indexed, and a row whose dump
    is gone is dropped from the index and, at the end, from the log. So a
    corpus that gained 400 dumps costs 400 dumps, not 130 000.
    """
    if batch in _INDEX:
        return _INDEX[batch]
    paths = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
    # a rebuild means the corpus may have changed under us: never key a
    # checkpoint on a digest taken before it.
    _CORPUS_DIGEST.pop(batch, None)
    ck, codec, lock = None, None, None
    ckpt_path = os.environ.get(INDEX_CKPT_ENV)
    if ckpt_path:
        _corpus_digest(paths, batch)          # cached for the derive checkpoint
        lock = _lock_index_log(ckpt_path)
        if lock is not None:
            ck = _ckpt.open_checkpoint(
                ckpt_path, _phase_keys(batch, "corpus_index", corpus=False),
                env_var=INDEX_CKPT_ENV)
    if ck is not None:
        codec = _RowCodec()
        # the string table is rebuilt in FILE order, once, before anything is
        # consumed -- see `_RowCodec`.
        for _k, rec in ck.items():
            codec.register(rec)
    prog = _Progress("corpus-index", len(paths))
    idx, pool, replayed, restamped = [], {}, 0, 0
    for p in paths:
        row = None
        name = os.path.basename(p)
        if ck is not None:
            # POPPED, not read: holding the whole log AND the index it builds
            # is what a 194k-dump corpus cannot afford.
            rec = ck.pop(name)
            if rec is not None:
                if rec.get(_ROW_STAMP) == _row_stamp(p):
                    row = codec.decode(rec)
                    replayed += 1
                else:
                    # the dump behind this row changed (or the row predates
                    # the stamp): re-index it, and the fresh record appended
                    # below supersedes the old one -- last occurrence wins.
                    restamped += 1
        if row is None:
            # the stamp is taken BEFORE the read, never after: a dump still
            # being written then records a stamp older than the file ends up
            # with, and is re-indexed next time rather than trusted.
            stamp = _row_stamp(p)
            row = _index_row(p)
            if ck is not None:
                rec = codec.encode(row)
                rec[_ROW_STAMP] = stamp
                ck.put(name, rec)
                ck.pop(name)                         # streamed: never retained
        _absorb_index_row(batch, p, row, idx, pool)
        prog.tick()
    note = ""
    if ck is not None:
        # whatever was never popped is a row whose dump is no longer there.
        gone = {k for k, _v in ck.items()}
        note = (f"({replayed} row(s) replayed from the checkpoint, "
                f"{len(paths) - replayed} indexed"
                + (f", {restamped} re-indexed (the dump changed)" if restamped else "")
                + (f", {len(gone)} dropped (the dump is gone)" if gone else "") + ")")
    prog.done(note)
    if ck is not None:
        ck.close()
        if gone or restamped:
            # an append log cannot forget, so the log is rewritten: without
            # the gone rows, and with one record per dump.
            _compact_index_log(ck.path, gone)
    if lock is not None:
        lock.close()                          # releases the writer lock
    _INDEX[batch] = idx
    # Everything derived from the index is invalidated by a rebuild (the
    # tests clear `_INDEX` to force one; so does a corpus that grew).
    _POSTINGS.pop(batch, None)
    for derived in (_PSW_CACHE, _PBW_CACHE, _PROFILE_REPS, _ROUTE_CACHE):
        for k in [k for k in derived if k[0] == batch]:
            del derived[k]
    _ROUTE_BASES.clear()
    _Z3_DECLS.clear()
    _SEEDS_BY_PATH.pop(batch, None)
    return idx


def evidence(dump, dimension):
    pcs = set()
    notes = set()
    for ev in dump.get("events") or []:
        if ev.get("type") == "path_condition":
            expr = str(ev.get("expr", ""))
            if dimension not in expr:
                pcs.add((expr, bool(ev.get("taken"))))
        elif ev.get("type") == "symbolic_call":
            n = str(ev.get("note") or "")
            if re.match(r"\s*SELECT", n, re.I) and dimension not in n:
                notes.add(re.sub(r"\s+", " ", n))
    for sv in dump.get("symbolic_vars") or []:
        n = str(sv.get("note") or "")
        if re.match(r"\s*SELECT", n, re.I) and dimension not in n:
            notes.add(re.sub(r"\s+", " ", n))
    return pcs, notes


def pick_snapshot(batch, dimension, scenario=None):
    """Richest seed dict wins; `scenario` restricts to snapshots from that
    scenario — for assumptions whose expr ordinals are only valid in the
    context they were declared for (ordinal instability across scenarios is
    itself a finding the probe surfaces as a dead knob)."""
    best = None
    for p, seeds, scen, _exprs in corpus_index(batch):
        if scenario and scen != scenario:
            continue
        # NAME BOUNDARY (2026-09-14). `dimension` is `len(X)` (expr_dimension
        # emits the RUNTIME spelling); `seeds` is the index row, i.e. the
        # POST-hook dict, so on any batch whose canonicalize hook runs
        # `fix_len_names` it is `SYM_LEN_`-keyed and this membership test
        # missed every length dimension -- read by the caller as
        # "PROBE: SKIP - no dump seeds this dimension". `keys_for` resolves
        # spelling and ordinal/canonical; [] is still a genuine absence.
        # (CLI `--assumptions` path only: `_test_confinement` uses
        # `pick_snapshot_with`, which does not require the dim to be seeded.)
        if NameSpace(seeds, name="index row seeds").keys_for(dimension):
            if best is None or len(seeds) > len(best[1]):
                best = (p, seeds)
    return (best[0], load_dump(best[0])) if best else None


def _live_seed_key(dimension, rows):
    """The seed key the RUNTIME reads for `dimension` on a snapshot whose
    alias rows are `rows` ((ordinal, canonical, key, len) as `_ALIAS_INDEX`
    holds them), or None when the dimension is a DEAD KNOB there.

    X10 class (2026-09-12): `canonicalize_ordinals` deliberately leaves
    `concolic_seeds` ORDINAL-named, while the run constructors ALSO write
    CANONICAL-named keys into the seed dicts they build. The runtime never
    reads those, so a canonical key that this snapshot's own alias map does
    not rename controls nothing here, however plainly it sits in the seed
    dict. Live means one of three things, in order: the run canonicalizes
    nothing (the key is the runtime's own); the key names a canonical THIS
    run mints, so it maps to this run's ordinal; or the key already names one
    of this run's ordinals."""
    if not rows:
        return dimension                       # this run canonicalizes nothing
    # cheap substring pre-filter first: building a renamer per dump over a
    # 10**5-dump corpus is the expensive part, and it is needed only on a hit.
    pairs = {c: o for o, c, _k, _l in rows if c and c in dimension}
    if pairs:
        rk = renamer(pairs)(dimension)
        if rk != dimension:
            return rk                          # canonical -> THIS run's ordinal
    if any(o and o in dimension for o, _c, _k, _l in rows):
        return dimension                       # already one of this run's ordinals
    return None                                # dead knob


def pick_live_snapshot(batch, dimension, scenario=None):
    """(path, dump, runtime_key) for the richest snapshot on which `dimension`
    resolves to a LIVE seed key -- the key the runner actually reads -- or
    None when no snapshot has one.

    `pick_snapshot` selects on `dimension in seeds`, which matches the
    CANONICAL-named dead knobs described in `_live_seed_key` and so can hand
    a probe a snapshot where seeding the dimension changes nothing. Selection
    here is on the key the runtime reads. Snapshots that already seed that key
    win over ones that do not, then the richest seed dict -- so on a corpus
    that does not canonicalize this picks exactly what
    `pick_snapshot(...) or the richest dump` picked."""
    idx_rows = corpus_index(batch)                 # also fills _ALIAS_INDEX
    idx = _ALIAS_INDEX.get(batch) or {}
    best = None
    for p, seeds, scen, _exprs in idx_rows:
        if scenario and scen != scenario:
            continue
        rk = _live_seed_key(dimension, idx.get(p) or ())
        if rk is None:
            continue
        # NAME BOUNDARY: `rk` is a RUNTIME key (`len(<ordinal>_rows)`) while
        # `seeds` is the post-hook index row; a bare `in` collapsed this
        # preference tier to 0 for every length dimension.
        rank = (1 if NameSpace(seeds, name="index row seeds").keys_for(rk) else 0,
                len(seeds))
        if best is None or rank > best[0]:
            best = (rank, p, rk)
    return (best[1], load_dump(best[1]), best[2]) if best else None


def pick_live_snapshots(batch, dimension, scenario=None, k=None):
    """``[(path, dump, runtime_key), ...]`` — `pick_live_snapshot`'s answer
    FIRST, then up to `k-1` further snapshots on which `dimension` resolves to
    a live seed key, scenario-diverse (X12, 2026-09-14).

    Same defect, same fix: the symbolic-constraint test seeded the violating
    value on ONE snapshot, and "the run did not take the seed" / "no value
    recorded" is a fact about that snapshot's context. `pick_live_snapshot`'s
    own ranking (a snapshot that already seeds the runtime key beats one that
    does not, then richest) is kept for the first pick, so `k=1` is the
    shipped selection exactly."""
    idx_rows = corpus_index(batch)                 # also fills _ALIAS_INDEX
    idx = _ALIAS_INDEX.get(batch) or {}
    hits = []
    for p, seeds, scen, _exprs in idx_rows:
        if scenario and scen != scenario:
            continue
        rk = _live_seed_key(dimension, idx.get(p) or ())
        if rk is None:
            continue
        rank = (1 if NameSpace(seeds, name="index row seeds").keys_for(rk) else 0,
                len(seeds))
        hits.append((rank, p, rk, scen))
    if not hits:
        return []
    hits.sort(key=lambda t: (-t[0][0], -t[0][1], t[1]))
    ordered, by_scen = [hits[0]], {}
    for h in hits[1:]:
        by_scen.setdefault(h[3], []).append(h)
    while any(by_scen.values()):
        for sc in sorted(by_scen):
            if by_scen[sc]:
                ordered.append(by_scen[sc].pop(0))
    k = _BASE_BUDGET if k is None else k
    return [(p, load_dump(p), rk) for _r, p, rk, _s in ordered[:k]]


def flip_value(v, flip_to):
    if flip_to is not None:
        return flip_to
    if isinstance(v, bool):
        return not v
    if isinstance(v, int):
        return v + 1
    if isinstance(v, str):
        return "" if v else "x"
    raise ValueError(f"cannot auto-flip {v!r}; set flip_to in the manifest")


_LABEL_TOKEN = os.environ.get("ACHK_LABEL_TOKEN") or f"{os.getpid():x}"


def _dump_dirs(cfg):
    """Every directory a probe's dumps may land in, de-duplicated by real path.

    `batch_dir` is where the checker READS the corpus; the runner writes
    wherever IT chooses (`run_dse.rb` writes next to itself, `File.join(HERE,
    ...)`). With `batch_dir` pointing at a SYMLINK FARM over a pruned corpus
    those are different directories, so a glob over `batch_dir` alone finds
    nothing -- which used to be scored as "the violating value is
    unrealizable" (2026-09-12). Follow the runner instead of assuming."""
    dirs = [cfg["batch_dir"]]
    dirs += [os.path.dirname(t) for t in (cfg.get("runner") or "").split()
             if t.endswith(".rb") and os.path.dirname(t)]
    dirs.append(cfg.get("workdir") or ".")
    seen, out = set(), []
    for d in dirs:
        rp = os.path.realpath(d)
        if rp not in seen and os.path.isdir(rp):
            seen.add(rp)
            out.append(d)
    return out


def run_probe(cfg, name, seeds, keep, scenario=None):
    """Replay `seeds` (one dict, or a list of dicts = many worklist roots in
    ONE runner launch) in `scenario`; returns {dump-basename: dump}."""
    batch = cfg["batch_dir"]
    # The suffix must name THIS invocation: probe dumps live in the batch dir
    # until they are drained, and a stale one from a crashed gate run would
    # otherwise be globbed back in as this launch's evidence.
    suffix = f"_achk{_LABEL_TOKEN}_{re.sub('[^A-Za-z0-9]', '', name)[:24]}"
    # The SEED FILE must name this invocation too (2026-09-13). Chunk names
    # are `batch<n>` counted from 1 per run, so two gates over one batch dir
    # write the same `_achk_batch1.json` — and the runner re-reads it once per
    # scenario, minutes apart, so a clobber mid-launch replays another gate's
    # roots under this one's labels. `_LABEL_TOKEN` (this process, or
    # $ACHK_LABEL_TOKEN) is the same namespace the dumps already carry.
    seed_path = os.path.join(batch, f"_achk{_LABEL_TOKEN}_{name}.json")
    json.dump(seeds if isinstance(seeds, list) else [seeds], open(seed_path, "w"))
    env = dict(os.environ, SEEDS_ONLY="1",
               EXTRA_SEEDS_JSON=os.path.abspath(seed_path),
               LABEL_SUFFIX=suffix)
    env.update(cfg.get("env") or {})     # host quirks belong to the batch config
    # scenario-specific env (e.g. {"auth": {"AUTH": "1"}}) so the probe
    # replays in the SAME scenario as its snapshot
    env.update(cfg.get("env_by_scenario", {}).get(scenario or "", {}))
    # Per-LAUNCH slot lock (2026-08-27): the checker must not hold the
    # machine-wide JRuby slot for its whole run — only while a runner is up.
    # The runner string is whatever the batch says it is — if a deployment
    # needs serialisation (a machine-wide lock, a queue, a scheduler), it
    # expresses that IN the runner, not here: the engine knows nothing about
    # how a host chooses to serialise its runs.
    argv = cfg["runner"].split()
    subprocess.run(argv, cwd=cfg.get("workdir", "."),
                   env=env, capture_output=True, timeout=900, check=False)
    # The same dump reachable through two of those directories (a symlink
    # farm over the real batch) is ONE dump: de-duplicate by real path.
    found = {}
    for d in _dump_dirs(cfg):
        for p in glob.glob(os.path.join(d, f"dump_*{suffix}*.json")):
            found.setdefault(os.path.realpath(p), p)
    dumps = [found[k] for k in sorted(found)]
    result = {os.path.basename(p): _load_dump_uncached(p) for p in dumps}
    if not keep:
        for p in dumps:
            for q in {p, os.path.realpath(p)}:   # the link AND the file it names
                try:
                    os.remove(q)
                except OSError:
                    pass
        os.remove(seed_path)
    return result


def scan(cfg, dimension):
    """Corpus tripwire: recorded PCs must agree with the applied seed."""
    bad = []
    pat = re.compile(rf"\({re.escape(dimension)} == (\S+?)\)")
    for p in glob.glob(os.path.join(cfg["batch_dir"], "dump_*.json")):
        d = load_dump(p)
        seeds = d.get("concolic_seeds") or {}
        if dimension not in seeds:
            continue
        seeded = seeds[dimension]
        for ev in d.get("events") or []:
            if ev.get("type") != "path_condition":
                continue
            m = pat.match(str(ev.get("expr", "")))
            if not m:
                continue
            lit = m.group(1).strip("'\")")
            if str(lit) == str(seeded) and not ev.get("taken"):
                bad.append((os.path.basename(p), ev["expr"], "seed contradicted"))
                break
    return bad


# ---------------------------------------------------------------------------
# DERIVED TESTS (Bali, 2026-08-26): the coverage checker already hands the
# engine every declared assumption with its TYPE and exprs; the test is
# derived from the type's own claim (concolic_engine/assumptions.py) — no
# hand-labelled manifest kinds. Currency: the ACCESS TRACE — the sequence
# of target-function calls with argument shapes — exactly what the
# independence docstring's "practical test" is about.
# ---------------------------------------------------------------------------
_VAR_RE = re.compile(r"\(\s*(?:Length\(\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\)?\s*(==|!=|<|>|<=|>=)")
_LENVAR_RE = re.compile(r"\(\s*len\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*(==|!=|<|>|<=|>=)")


# `((- VAR) op N)` — the runtime records a negated int operand (e.g.
# `-unread == 0`). Seedable dimension is VAR; the test flips VAR by the
# mirrored relation on -N (2026-08-26, conversations_index).
_NEG_RE = re.compile(r"\(\s*\(\s*-\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*(==|!=|<=|>=|<|>)\s*(-?\d+)\s*\)\s*$")
_MIRROR = {"<": ">", ">": "<", "<=": ">=", ">=": "<=", "==": "==", "!=": "!="}


def _unnegate(expr):
    """`((- VAR) op N)` -> (`(VAR op' -N)`, True); otherwise (expr, False)."""
    m = _NEG_RE.match(str(expr).strip())
    if not m:
        return expr, False
    var, op, n = m.group(1), m.group(2), int(m.group(3))
    return f"({var} {_MIRROR[op]} {-n})", True


def expr_dimension(expr):
    """The seedable variable an expr decides on (its left operand;
    `Length(VAR) op N` decides on VAR's string length)."""
    expr, _ = _unnegate(canon(expr))
    ml = _LENVAR_RE.match(str(expr).strip())
    if ml:
        return f"len({ml.group(1)})"      # the seed key of a list's length
    m = _VAR_RE.match(str(expr).strip())
    return m.group(1) if m else None


def access_trace(dump):
    """Multiset of target-call SHAPES: (target, normalized note, arg shapes).
    The normalisation is the engine's ``call_shape`` (2026-09-11) — the same
    function the coverage checker measures a decision's FOOTPRINT with, so
    the gate's ConfinementAssumption test and the engine's confined pairs
    speak of the same shapes."""
    shapes = []
    for ev in dump.get("events") or []:
        if ev.get("type") != "symbolic_call" or not ev.get("result_name"):
            continue
        shapes.append(call_shape(ev.get("target"), ev.get("note"), ev.get("args")))
    return shapes


def access_trace_binds(dump):
    """Multiset of target-call statements with BINDS KEPT (modulo the alias:
    the dump's notes are canonical when a hook is configured) — the currency
    of the Alias test, where two reads keyed on different owners must
    stay different."""
    shapes = []
    for ev in dump.get("events") or []:
        if ev.get("type") != "symbolic_call" or not ev.get("result_name"):
            continue
        shapes.append((str(ev.get("target") or ""), statement_key(ev.get("note") or "")))
    return shapes


def has_expr(dump, expr):
    want = canon(expr)
    return any(canon(ev.get("expr", "")) == want for ev in dump.get("events") or []
               if ev.get("type") == "path_condition")


def probe_record(dump):
    """All a verdict needs from a probe replay: its access trace and the set
    of PC exprs it recorded. Keeping ~3k FULL dumps in the cache is what OOMs
    a large batch (2026-08-27); this is ~1 KB each."""
    if dump is None:
        return None
    return {"trace": tuple(access_trace(dump)),
            "trace_b": tuple(access_trace_binds(dump)),
            "amap": dict(dump.get("_alias_map") or {}),
            "exprs": frozenset(canon(ev.get("expr", "")) for ev in dump.get("events") or []
                               if ev.get("type") == "path_condition"),
            # per recorded expr, the outcome set (2026-09-11: the Confinement
            # test needs to see that a flip TOOK and that the partner decision
            # kept its outcome — presence alone cannot say either).
            "outcomes": _outcomes_of_dump(dump),
            # the concrete scalars the run MINTED, by symbolic-var name
            # (2026-09-12). A seed is a REQUEST: a mock that clamps its
            # argument runs a different value than the one seeded, and no
            # verdict about a seeded value is worth anything until the run is
            # seen to have realised it. Numbers and booleans only — the
            # derived tests compare against INT literals, and carrying the
            # string values too tripled the record.
            "values": {str(sv.get("name")): sv.get("value")
                       for sv in dump.get("symbolic_vars") or ()
                       if isinstance(sv.get("value"), (int, float))}}


#: `realised_value` found no value for the dimension — distinct from a
#: recorded ``None``.
ABSENT = object()


def realised_value(record, dimension, seed_key=None):
    """``(name, value)`` the probe run actually MINTED on `dimension`, or
    ``(name, ABSENT)`` when the record carries no value for it.

    Naming is the whole difficulty, and the two sides of a dump disagree by
    design: `canonicalize_ordinals` leaves ``concolic_seeds`` ORDINAL-named
    (which is why a seed key is resolved by `_live_seed_key`) while it
    REWRITES ``symbolic_vars`` to canonical names. So the minted value is
    looked up, in order, under

    1. the probe's own name for the variable the runtime actually seeded --
       ``seed_key`` (an ordinal in the probe's namespace) carried through the
       probe's OWN alias map. This is the bridge that holds when the probe
       run mints a different canonical for the statement than the snapshot
       did, which is the common case across scenarios;
    2. `dimension` itself -- a corpus that canonicalizes nothing, or a probe
       whose canonical is the declaration's;
    3. `_live_seed_key(dimension, ...)` against the probe's alias rows -- a
       dump left ordinal-named on both sides.

    A name that no candidate matches is ABSENT: which region the probe ran in
    is then unknown, and unknown is not evidence (2026-09-12)."""
    if record is None:
        return None, ABSENT
    amap = record.get("amap") or {}
    values = record.get("values") or {}
    rows = tuple((o, c, None, None) for o, c in amap.items())
    candidates = [renamer(amap)(seed_key) if seed_key else None,
                  dimension,
                  _live_seed_key(dimension, rows)]
    first = None
    for name in candidates:
        if name is None:
            continue
        first = first if first is not None else name
        if name in values:
            return name, values[name]
    return first, ABSENT


def _outcomes_of_dump(dump):
    out = {}
    for ev in dump.get("events") or []:
        if ev.get("type") == "path_condition":
            out.setdefault(canon(ev.get("expr", "")), set()).add(bool(ev.get("taken")))
    return {e: frozenset(v) for e, v in out.items()}


def outcomes_of(x, expr):
    """The recorded outcome set of `expr` in a probe record or a dump (empty
    frozenset when the run never evaluated it)."""
    want = canon(expr)
    if isinstance(x, dict) and "outcomes" in x:
        return x["outcomes"].get(want, frozenset())
    return _outcomes_of_dump(x).get(want, frozenset())


def trace_of(x):
    return list(x["trace"]) if isinstance(x, dict) and "trace" in x else access_trace(x)


def recorded(x, expr):
    want = canon(expr)
    if isinstance(x, dict) and "exprs" in x:
        return want in x["exprs"]
    return has_expr(x, expr)


#: Env var enabling the PROBE CHECKPOINT (owner rule, 2026-09-12). A probe is
#: one JRuby replay — the gate's whole cost (28 min for posts_show's 184
#: probes, ~112 min for notifications' 5 075) — and before this the cache was
#: per-process, so a killed gate re-launched every one of them. Unset = the
#: behaviour the gate has always had.
CKPT_ENV = "ACHK_CHECKPOINT"
#: Env var for an incremental verdict log (JSON Lines, one row per assumption
#: as it is decided). `--json-out` is written only in `main`'s `finally`, and
#: `results = []` there means a hard kill leaves it EMPTY; this leaves every
#: row that was actually produced.
RESULTS_JSONL_ENV = "ACHK_RESULTS_JSONL"


def _restore_tuples(x):
    """JSON turns every tuple into a list; the verdict tests compare traces
    (tuples of tuples, from `call_shape`) for equality, so they must come
    back as tuples or a replayed probe would never match a fresh one."""
    return tuple(_restore_tuples(v) for v in x) if isinstance(x, list) else x


def probe_record_to_json(r):
    """`probe_record`'s dict as JSON-able data (tuples -> lists, sets ->
    sorted lists). None — the probe produced no dump — is preserved."""
    if r is None:
        return None
    return {"trace": list(r["trace"]), "trace_b": list(r["trace_b"]),
            "amap": dict(r["amap"]), "exprs": sorted(r["exprs"]),
            "outcomes": {e: sorted(v) for e, v in r["outcomes"].items()},
            "values": dict(r.get("values") or {})}


def probe_record_from_json(d):
    """Inverse of `probe_record_to_json`, exact on every field a verdict
    reads: traces as tuples, `exprs` a frozenset, outcomes frozensets of
    bool. Pinned by test_assumption_checker.py."""
    if d is None:
        return None
    return {"trace": _restore_tuples(d["trace"]),
            "trace_b": _restore_tuples(d["trace_b"]),
            "amap": dict(d["amap"]), "exprs": frozenset(d["exprs"]),
            "outcomes": {e: frozenset(bool(b) for b in v)
                         for e, v in d["outcomes"].items()},
            "values": dict(d.get("values") or {})}


class ProbeCache:
    """Replay each distinct (scenario, seed-dict) at most once.

    Two modes: `planning=True` only RECORDS the wanted (scenario, seeds)
    keys and returns a placeholder; `execute()` then replays all wanted
    keys per scenario in batches of PROBE_BATCH roots per runner launch
    (a JRuby boot per probe was the wall on large corpora); afterwards
    `run` serves the cached result exactly as the one-launch-per-probe
    version did (dumps are matched back by their recorded concolic_seeds)."""
    PROBE_BATCH = int(os.environ.get("ACHK_PROBE_BATCH", "40"))

    def __init__(self, cfg, keep, checkpoint=None):
        self.cfg, self.keep, self.cache = cfg, keep, {}
        self.planning, self.wanted = False, {}
        # CHECKPOINT (owner rule, 2026-09-12): opt-in, keyed on the batch
        # config and this module's source, so a probe replayed under a
        # different runner / batch dir / scenario env is never reused. The
        # key is the SAME (scenario, seeds) pair the in-memory cache uses,
        # digested because a JSON object key must be a string.
        # SOUNDNESS (2026-09-14). The header carried `cfg`, `engine`, `keep`,
        # `phase` and NO canonicalize key, while `cfg` digests the manifest --
        # which names the hook as the STRING "gate_canon:canonicalize_for_gate",
        # not its source. So editing `gate_canon.py` or a driver's
        # `fix_len_names`/`canonicalize_ordinals` changed every record's
        # `amap`, its `values` spellings and its `outcomes`, and the stale bank
        # was SILENTLY REUSED. `_phase_keys` has always included `_canon_key()`;
        # the probe cache did not. It does now.
        #
        # ORDERING: `_canon_key()` returns "none" while `_CANON_FN` is unset,
        # so this key is only meaningful if the hook is installed BEFORE a
        # ProbeCache exists. main() does that (hook at "canonicalize", cache
        # built later inside run_declared) -- but that order is undocumented
        # and a future caller that warms the cache earlier would silently
        # degrade the key to a constant and REOPEN the hole with the fix
        # apparently in place. Assert it rather than rely on it.
        if cfg.get("canonicalize") and _CANON_FN is None:
            raise RuntimeError(
                "ProbeCache built before the canonicalize hook was installed: "
                f"manifest declares {cfg['canonicalize']!r} but _CANON_FN is None, "
                "so the probe checkpoint key would degrade to 'none' and a stale "
                "bank would be reused across DIFFERENT canonicalizations. "
                "Install the hook (main()'s 'canonicalize' block) before "
                "constructing a ProbeCache.")
        self.ckpt = _ckpt.open_checkpoint(
            checkpoint if checkpoint is not None else os.environ.get(CKPT_ENV),
            {"engine": _ckpt.source_hash(sys.modules[__name__]),
             "phase": "assumption_checker:ProbeCache",
             "cfg": _ckpt.digest(cfg),
             "canonicalize": _canon_key(),
             "keep": str(bool(keep))})
        # NOT bulk-preloaded into `self.cache`: that dict is keyed by the
        # live (scenario, seeds-json) tuple and the log by its digest. Every
        # read path below goes through `_recall`, so a recorded probe is
        # served the first time it is asked for and cached from then on.

    def _ck_key(self, key):
        return _ckpt.digest(list(key))

    def _remember(self, key, rec):
        """Persist one finished probe, if a checkpoint is open."""
        if self.ckpt is not None:
            self.ckpt.put(self._ck_key(key), probe_record_to_json(rec))

    def _recall(self, key):
        """(hit?, record) from the checkpoint — a recorded None is a HIT."""
        if self.ckpt is None:
            return False, None
        k = self._ck_key(key)
        if k not in self.ckpt:
            return False, None
        return True, probe_record_from_json(self.ckpt.get(k))

    def close(self):
        if self.ckpt is not None:
            self.ckpt.close()
            self.ckpt = None

    def run(self, seeds, scenario, tag):
        key = (scenario, json.dumps(seeds, sort_keys=True))
        if self.planning:
            self.wanted.setdefault(key, (scenario, dict(seeds)))
            return self.cache.get(key, {})
        if key not in self.cache:
            hit, rec = self._recall(key)
            if hit:
                self.cache[key] = rec
                return rec
            probes = run_probe(self.cfg, tag, seeds, self.keep, scenario=scenario)
            self.cache[key] = probe_record(next((d for d in probes.values()
                                    if (d.get("concolic_scenario") or {}).get("name") == scenario), None))
            self._remember(key, self.cache[key])
        return self.cache[key]

    def execute(self):
        # A checkpointed probe is served before a single runner is launched:
        # this is what makes a killed gate resume instead of restart.
        for k, (sc, sd) in self.wanted.items():
            if k not in self.cache:
                hit, rec = self._recall(k)
                if hit:
                    self.cache[k] = rec
        if self.ckpt is not None:
            print(f"  [probe checkpoint: {sum(1 for k in self.wanted if k in self.cache)}"
                  f"/{len(self.wanted)} already recorded, skipped]", flush=True)
        todo = [(k, sc, sd) for k, (sc, sd) in self.wanted.items() if k not in self.cache]
        by_scen = {}
        for k, sc, sd in todo:
            by_scen.setdefault(sc, []).append((k, sd))
        # One chunk = one runner launch plus its single replays, start to
        # finish. Chunks share nothing (run_probe namespaces its seed file and
        # its dumps by probe NAME), so they may run concurrently: the host
        # decides how many runners it can afford by serialising them in the
        # RUNNER string (see run_probe). CONCOLIC_PROBE_WORKERS=1 by default,
        # so this is the previous sequential behaviour unless a host asks for
        # more. (2026-09-01)
        work = []
        n = 0
        for sc, items in by_scen.items():
            for i in range(0, len(items), self.PROBE_BATCH):
                n += 1
                work.append((n, sc, items[i:i + self.PROBE_BATCH]))
        workers = max(1, int(os.environ.get("CONCOLIC_PROBE_WORKERS", "1")))
        if workers > 1 and len(work) > 1:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=workers) as pool:
                list(pool.map(lambda w: self._run_chunk(*w), work))
        else:
            for w in work:
                self._run_chunk(*w)
        self.wanted.clear()

    def _run_chunk(self, n, sc, chunk):
        probes = run_probe(self.cfg, f"batch{n}", [sd for _k, sd in chunk],
                           self.keep, scenario=sc)
        found = [d for d in probes.values()
                 if (d.get("concolic_scenario") or {}).get("name") == sc]
        for k, sd in chunk:
            # `seeds_as_written`, not `concolic_seeds`: the seed file is
            # written in the runtime's spelling and a batch canonicalize hook
            # may rename seed keys on load (2026-09-13 — a `len(X)` dimension
            # was renamed `SYM_LEN_X`, so every root seeding a list length
            # missed and the batch degenerated to 40 single launches).
            self.cache[k] = probe_record(next((d for d in found
                                  if seeds_as_written(d) == sd), None))
            if self.cache[k] is not None:
                self._remember(k, self.cache[k])
        # The runner writes a dump only for a NEW path signature, so
        # two roots in one launch that follow the same path yield one
        # dump: replay the unmatched roots singly (old semantics).
        missing = [(k, sd) for k, sd in chunk if self.cache[k] is None]
        for j, (k, sd) in enumerate(missing):
            probes = run_probe(self.cfg, f"batch{n}_single{j}", sd, self.keep, scenario=sc)
            self.cache[k] = probe_record(next((d for d in probes.values()
                                  if (d.get("concolic_scenario") or {}).get("name") == sc), None))
            # a singly-replayed root is FINISHED whatever it produced, so the
            # None is recorded too — otherwise a rerun would replay it again
            self._remember(k, self.cache[k])
        print(f"  [probe batch {n}: {len(chunk)} roots in scenario {sc!r} -> "
              f"{len(found)} dumps, {len(missing)} replayed singly, "
              f"{sum(1 for k, _ in chunk if self.cache[k] is not None)} matched]",
              flush=True)


_CMP_RE = re.compile(r"\(\s*(Length\(\s*)?[A-Za-z_][A-Za-z0-9_]*\s*\)?\s*(==|!=|<=|>=|<|>)\s*(.+?)\s*\)\s*$")


def _parse_literal(txt):
    txt = txt.strip()
    m = re.match(r"StringVal\((.*)\)$", txt)
    if m:
        txt = m.group(1)
    if txt in ("True", "False"):
        return txt == "True"
    if re.fullmatch(r"-?\d+", txt):
        return int(txt)
    m = re.fullmatch(r"'(.*)'", txt)
    return m.group(1) if m else None


def _rhs_value(rhs_txt, dump):
    """Literal, or the recorded value of a variable-valued RHS (var-vs-var
    compares like `first_1_id == SYM_PERSON_NI_id`)."""
    lit = _parse_literal(rhs_txt)
    if lit is not None:
        return lit
    name = rhs_txt.strip()
    seeds = dump.get("concolic_seeds") or {}
    if name in seeds:
        return seeds[name]
    for sv in dump.get("symbolic_vars") or []:
        if sv.get("name") == name and "value" in sv:
            return sv["value"]
    return None


def flip_for(dump, expr):
    """Value for the expr's LEFT variable that flips this run's recorded
    decision. Handles ==, !=, <, <=, >, >= against literals or variables
    (the seed dict is a total assignment, so unseeded dims can be set)."""
    norm, _neg = _unnegate(expr)   # norm is already stated in terms of VAR
    return _flip_core(dump, norm, lookup=expr)


def _flip_core(dump, expr, lookup=None):
    expr = _LENVAR_RE.sub(lambda m: f"(LEN__{m.group(1)} {m.group(2)}", canon(expr).strip(), count=1)
    m = _CMP_RE.match(str(expr).strip())
    if not m:
        return None
    is_len, op, rhs = bool(m.group(1)), m.group(2), _rhs_value(m.group(3), dump)
    if rhs is None:
        return None
    taken = None
    want = canon(lookup or expr)
    for ev in dump.get("events") or []:
        if ev.get("type") == "path_condition" and canon(ev.get("expr")) == want:
            taken = bool(ev.get("taken"))
            break
    if taken is None:
        return None
    if is_len:
        # `Length(VAR) op N`: flip by supplying a string whose length is on
        # the other side of N (the guid-vs-id dispatch: `Length(post_id) < 16`)
        if not isinstance(rhs, int):
            return None
        holds_now = taken
        want_short = {"<": not holds_now, "<=": not holds_now, ">": holds_now, ">=": holds_now,
                      "==": not holds_now, "!=": holds_now}[op]
        n_short = max(rhs - 1, 1) if op in ("<", "<=", "==") else max(rhs - 1, 1)
        n_long = rhs + 1
        return ("x" * n_short) if want_short else ("g" * n_long)
    # currently-true relation -> pick a value making it false, and vice versa
    holds = {"==": True, "!=": False, "<": True, "<=": True, ">": True, ">=": True}[op]
    want_equal_side = (op in ("==",)) ^ (not taken)      # for ==/!=
    if op in ("==", "!="):
        currently_equal = (op == "==") == taken
        if currently_equal:
            return flip_value(rhs, None)                 # make it unequal
        return rhs                                       # make it equal
    if not isinstance(rhs, int):
        return None
    currently = {"<": lambda: taken, "<=": lambda: taken,
                 ">": lambda: taken, ">=": lambda: taken}[op]()
    # taken means the relation held; produce a value on the other side
    if op == "<":  return rhs if taken else rhs - 1
    if op == "<=": return rhs + 1 if taken else rhs
    if op == ">":  return rhs if taken else rhs + 1
    if op == ">=": return rhs - 1 if taken else rhs
    return None


# --- inverted index over the corpus (2026-09-12, perf) ---------------------
# Every derived test selects its snapshots by "which runs recorded THIS
# expression", and each selection used to be a full scan of the index: 2 315
# confined pairs x (1 pair snapshot + 2 exhaustive-flip scans + one scan per
# footprint shape with another producer) is ~120 000 scans of 194 262 rows.
# One posting list per expression turns each of them into a walk of the runs
# that actually recorded it. `array("i")` because a plain list of 7.8M row
# indices costs 218 MB in int objects alone.
_POSTINGS = {}      # batch -> {canon expr: (all rows, taken rows, not-taken rows)}
_PSW_CACHE = {}     # (batch, frozenset(canon exprs)) -> (path, seeds) | None
_PBW_CACHE = {}     # (batch, frozenset(canon exprs)) -> [(path, seeds), ...]

#: X12 (2026-09-14) -- HOW MANY BASES a derived test probes.
#: Every derived test used to build its probe from ONE base: the single
#: richest snapshot `pick_snapshot_with` returns. notifications_index §39
#: measured what that costs -- `_test_conjunction_foreclosure` reported
#: NOT-TESTABLE on 24 of 24 §16g classes while 4 to 6 OTHER bases in the same
#: corpus refuted 18 of them (78 refuting replays), and on §16f 12 single-base
#: PASSes became 6 FAIL + 6 PASS. So a single-base NOT-TESTABLE is not
#: evidence of untestability and a single-base PASS is not evidence of a
#: licence. 8 is §39's own K and is where its marginal return flattens (its
#: refutations were found at base ranks 1..5; see DISCIPLINE §17).
_BASES = max(1, int(os.environ.get("ACHK_BASES", "8") or 8))
#: The per-test budget for THIS pass. `run_declared` sets it to 1 for the
#: cheap first stage and to `_BASES` for the escalation stage, so a class the
#: first base already FAILs never pays for the other seven.
_BASE_BUDGET = _BASES
#: Verdict strength, strongest (most decisive) first. A FAIL from ANY base is
#: the class's verdict -- one run is the falsifier.
_BASE_RANK = {"FAIL": 0, "PASS": 1, "NOT-COMPARABLE": 2, "NOT-TESTABLE": 3,
              "ERROR": 4}
#: Verdicts that mean "this base did not realise the claim's premise", i.e.
#: the base contributed no evidence either way (the realised-value rule,
#: DISCIPLINE §16e "seeding is not realising").
_BASE_VACUOUS = ("NOT-TESTABLE", "ERROR")


def _postings(batch):
    """{canon expr: (rows recording it, rows with taken, rows with not-taken)},
    row = its position in `corpus_index(batch)`. Ascending in every list, so
    a walk visits the corpus in the same order a full scan did."""
    if batch not in _POSTINGS:
        rows = corpus_index(batch)
        tidx = _TRACE_INDEX.get(batch) or {}
        post = {}
        for i, (p, _seeds, _scen, _exprs) in enumerate(rows):
            _digest, _shapes, pcs = tidx[p]
            for e, taken in pcs:
                cell = post.get(e)
                if cell is None:
                    cell = post[e] = (array.array("i"), array.array("i"),
                                      array.array("i"))
                if not cell[0] or cell[0][-1] != i:
                    cell[0].append(i)
                cell[1 if taken else 2].append(i)
        _POSTINGS[batch] = post
    return _POSTINGS[batch]


def pick_snapshot_with(batch, exprs, dims):
    """Richest-seed dump that RECORDED every expr (dims need not be
    seeded — unseeded ones are inferred from the recorded PC).

    2026-09-12: same answer, found through the posting list of the RAREST
    expr rather than a scan of the whole index, and memoized — the derived
    tests ask the same question thousands of times (once per footprint shape
    per confined pair)."""
    rows = corpus_index(batch)          # before the memo: a rebuild purges it
    exprs = [canon(e) for e in exprs]
    key = (batch, frozenset(exprs))
    if key not in _PSW_CACHE:
        best = None
        if exprs:
            post = _postings(batch)
            empty = array.array("i")
            walk = min(((post.get(e) or (empty,))[0] for e in exprs), key=len)
            for i in walk:
                p, seeds, _scen, recorded = rows[i]
                if not all(e in recorded for e in exprs):
                    continue
                if best is None or len(seeds) > len(best[1]):
                    best = (p, seeds)
        else:
            for p, seeds, _scen, _recorded in rows:
                if best is None or len(seeds) > len(best[1]):
                    best = (p, seeds)
        _PSW_CACHE[key] = best
    best = _PSW_CACHE[key]
    return (best[0], load_dump(best[0])) if best else None


def pick_bases_with(batch, exprs, k=None):
    """``[(path, dump), ...]`` -- up to `k` snapshots that RECORDED every expr,
    ORDERED: the richest-seed snapshot FIRST (byte-identically
    `pick_snapshot_with`'s answer, so `k=1` reproduces the single-base test
    exactly), then round-robin over the remaining SCENARIOS, richest-seed
    first within each.

    X12 (2026-09-14). Why more than one, and why THAT order.

    * More than one, because one is demonstrably not enough: a derived test's
      probe is derived FROM its base (which literals need flipping, which
      seeds are there to flip), so "the flip did not take" / "the probe did
      not realise `C`" / "the snapshot records the member both ways" are
      statements about the BASE, not about the claim. §39 enumerated every
      dump recording the claim's exprs (1 030 - 1 807 candidates per class),
      probed 8, and refuted 18 of 24 classes the single-base test had called
      NOT-TESTABLE.
    * Richest FIRST, because the richest seed dict is the one with the most
      knobs that can actually be turned -- the shipped selection, kept so that
      a budget of 1 is the old behaviour and so the escalation stage can
      recall the first base's probes from the ProbeCache instead of re-running
      them.
    * SCENARIO-DIVERSE after that (`_c27_fals.py`'s ordering), because
      scenario is the corpus's own partition of context: two dumps from one
      scenario differ in seeds, dumps from different scenarios differ in which
      code the request reaches at all, and it is the second kind of difference
      that decides whether a flip is realisable. §39's refuting bases were
      spread across scenarios.

    Memoized like `pick_snapshot_with`; a corpus rebuild purges it."""
    rows = corpus_index(batch)          # before the memo: a rebuild purges it
    ce = [canon(e) for e in exprs]
    key = (batch, frozenset(ce))
    hits = _PBW_CACHE.get(key)
    if hits is None:
        hits = []
        if ce:
            post = _postings(batch)
            empty = array.array("i")
            walk = min(((post.get(e) or (empty,))[0] for e in ce), key=len)
            for i in walk:
                p, seeds, scen, recorded = rows[i]
                if all(e in recorded for e in ce):
                    hits.append((len(seeds), p, scen))
        else:
            hits = [(len(seeds), p, scen) for p, seeds, scen, _r in rows]
        hits.sort(key=lambda t: (-t[0], t[1]))
        ordered = list(hits[:1])                 # the shipped base, first
        by_scen = {}
        for h in hits[1:]:
            by_scen.setdefault(h[2], []).append(h)
        while any(by_scen.values()):
            for sc in sorted(by_scen):
                if by_scen[sc]:
                    ordered.append(by_scen[sc].pop(0))
        hits = [p for _n, p, _s in ordered]
        _PBW_CACHE[key] = hits
    k = _BASE_BUDGET if k is None else k
    return [(p, load_dump(p)) for p in hits[:k]]


def _combine_bases(per_base, out, what="claim"):
    """X12 -- ONE class verdict from the per-base verdicts, and the record of
    how the evidence was gathered.

    * **A refutation from ANY base is a FAIL.** One run that matches the
      claim's premise and contradicts its conclusion is the falsifier; it does
      not matter that seven other bases could not build such a run.
    * A **PASS** requires that no probed base refuted AND that at least one
      base REALISED the premise. `bases_realising` is written into the row:
      a PASS from 1 realising base is materially weaker evidence than a PASS
      from 8, and the row says which.
    * **NOT-TESTABLE only when NO probed base realised** the conjunction /
      the flip (the realised-value rule is unchanged: a base that did not
      realise the premise vouches for nothing).
    * Anything else keeps the strongest non-vouching verdict any base reached
      (NOT-COMPARABLE before NOT-TESTABLE), so a reading that changed under an
      alias is still reported as that and not laundered into "untestable"."""
    per_base = [p for p in per_base if p.get("verdict")]
    if not per_base:
        out.update(verdict="NOT-TESTABLE",
                   detail=f"no run in the CURRENT corpus is a base for this {what}")
        out.update(bases_probed=0, bases_realising=0, bases_passing=0,
                   bases_failing=0, base_verdicts=[])
        return out
    best = min(per_base, key=lambda p: _BASE_RANK.get(p["verdict"], 5))
    realising = [p for p in per_base if p["verdict"] not in _BASE_VACUOUS]
    out.update(verdict=best["verdict"], detail=best.get("detail", ""))
    out["bases_probed"] = len(per_base)
    out["bases_realising"] = len(realising)
    out["bases_failing"] = sum(1 for p in per_base if p["verdict"] == "FAIL")
    out["bases_passing"] = sum(1 for p in per_base if p["verdict"] == "PASS")
    out["base_verdicts"] = [{"base": p.get("base"), "verdict": p["verdict"],
                             "detail": (p.get("detail") or "")[:200]}
                            for p in per_base]
    tally = ", ".join(f"{v}={n}" for v, n in sorted(
        Counter(p["verdict"] for p in per_base).items()))
    out["detail"] = (f"[{len(per_base)} base(s) probed, {len(realising)} realising; "
                     f"{tally}] " + (out["detail"] or ""))
    return out


def flipped_seeds(sd, seeds, expr, dim):
    """Copy of `seeds` with `dim` flipped relative to this run (always via
    the recorded PC, so the flip is meaningful for the expr's operator)."""
    out = dict(seeds)
    rdim = _runtime_key(sd, dim)     # the runtime seeds by ORDINAL name
    v = flip_for(sd, expr)
    if v is None:
        # NAME BOUNDARY (2026-09-14): `rdim` is `len(<ordinal>_rows)` while
        # `seeds` may be `SYM_LEN_`-keyed, so this fallback missed on every
        # length dimension and returned None -> "cannot infer a flip value
        # from the recorded PC". Reachable only when `flip_for` fails (it
        # reads the recorded PC, not the seeds); measured 0/21 on posts_show.
        have = NameSpace(seeds, name="snapshot seeds").keys_for(rdim)
        if have:
            v = flip_value(seeds[have[0]], None)
        else:
            return None
    out[rdim] = v
    return out


def _combined_flip(sd, fa, fb, db):
    """The flip-BOTH seed dict: flip-A's dict with B's flip applied at the key
    the runtime seeds by. X10 (2026-09-11): `flipped_seeds` WRITES its flip at
    the RUNTIME (ordinal) key -- `rdim = _runtime_key(sd, dim)` -- because
    that is what the runner seeds by. Reading it back at the CANONICAL key
    `db` is the identity only when nothing is aliased, so on any endpoint
    that canonicalizes ordinals this raised KeyError and NO independence pair
    could ever be probed there. Read at the same key it was written at. A
    dimension can also be flipped by DELETING its key -- a decision
    controlled by a seed's ABSENCE -- and combining the flips must then
    delete it too, not read a key that is not there. Shared by the
    Independence and the Confinement tests (the latter added 2026-09-11)."""
    rdb = _runtime_key(sd, db)
    fab = dict(fa)
    if rdb in fb:
        fab[rdb] = fb[rdb]
    else:
        fab.pop(rdb, None)
    return fab


# (vi) probes EVERY profile by default (0 = unlimited). A cap is a budget
# knob for exploration only: a run it truncates is NOT-TESTABLE, never PASS —
# a pass must rest on the gate's own replays over every context it knows.
_CONF_PROFILES = int(os.environ.get("ACHK_CONF_PROFILES", "0"))


def _side_of(pcs, expr):
    """Recorded outcome set of `expr` in an index entry's (expr, taken) pairs.

    (2026-09-12: `_profile_representatives` reads the same thing off the
    posting lists instead of re-scanning every dump's pairs; this stays as
    the definition of what those lists mean.)"""
    want = canon(expr)
    return frozenset(t for e, t in pcs if e == want)


def _explained(z, r, producers):
    """True iff another producer of shape `z` is recorded ON its producing
    side in replay `r` — an OR-shared shape surviving a flip is explained."""
    for d, side in (producers.get(z) or []):
        got = outcomes_of(r, d)
        if got and (side == "both" or got == frozenset([side == "taken"])):
            return True
    return False


#: (2026-09-12, perf) memo for `_profile_representatives`. A confined
#: DECISION appears in every pair it is confined against — posts_show's 2 315
#: pairs are 112 distinct decisions — and its representative profiles, and
#: the flipped seed dict of each, are a function of the decision and the
#: corpus alone, not of the pair. Deriving them per pair re-scanned the index
#: and re-parsed thousands of dumps 41 times over.
_PROFILE_REPS = {}

#: Env var enabling the PROBE-DERIVATION checkpoint (owner rule, 2026-09-12).
#: Selecting a decision's profile representatives means PARSING each of them
#: (`flipped_seeds` needs the dump), and there are ~3 000 per decision on a
#: 194 262-dump corpus: ~46 min of the pre-probe phase, and lost entirely to
#: a kill. One record per DECISION; the flipped seed dict is stored as the
#: single-key delta it is against the index's own seed dict for that dump, so
#: a resume rebuilds it without opening one file. Unset = as before.
DERIVE_CKPT_ENV = "ACHK_DERIVE_CHECKPOINT"
_DERIVE_CK = None
_SEEDS_BY_PATH = {}


def _seeds_by_path(batch):
    if batch not in _SEEDS_BY_PATH:
        _SEEDS_BY_PATH[batch] = {p: seeds for p, seeds, _s, _e in corpus_index(batch)}
    return _SEEDS_BY_PATH[batch]


def _reps_to_json(batch, reps, n_cands):
    by_path = _seeds_by_path(batch)
    out = []
    for p, scen, carried, side, fl in reps:
        base = by_path.get(p) or {}
        out.append([os.path.basename(p), scen, sorted(carried), side,
                    None if fl is None else
                    [{k: v for k, v in fl.items() if k not in base or base[k] != v},
                     [k for k in base if k not in fl]]])
    return {"n": n_cands, "r": out}


def _reps_from_json(batch, rec):
    by_path = _seeds_by_path(batch)
    reps = []
    for name, scen, carried, side, delta in rec["r"]:
        p = os.path.join(batch, name)
        fl = None
        if delta is not None:
            fl = dict(by_path.get(p) or {})
            fl.update(delta[0])
            for k in delta[1]:
                fl.pop(k, None)
        reps.append((p, scen, frozenset(carried), side, fl))
    return reps, rec["n"]


def _profile_representatives(batch, expr, fp, enabling):
    """``([(path, scenario, carried shapes, side, flipped seeds)], n_profiles)``
    for `_exhaustive_flip` — the profile representatives of one decision and
    the flip each one needs, selected exactly as the inline loop did:
    one per outcome-profile digest, richest seed dict, ranked by shapes
    carried then seed count then path, truncated to ACHK_CONF_PROFILES."""
    rows = corpus_index(batch)          # before the memo: a rebuild purges it
    key = (batch, canon(expr), frozenset(fp),
           tuple(sorted((k, v) for k, v in (enabling or {}).items())),
           _CONF_PROFILES)
    hit = _PROFILE_REPS.get(key)
    if hit is not None:
        return hit
    ck_key = _ckpt.digest(list(key[1:]))
    if _DERIVE_CK is not None and ck_key in _DERIVE_CK:
        _PROFILE_REPS[key] = _reps_from_json(batch, _DERIVE_CK.get(ck_key))
        return _PROFILE_REPS[key]
    tidx = _TRACE_INDEX.get(batch) or {}
    dim = expr_dimension(expr)
    want = canon(expr)
    cell = _postings(batch).get(want)
    cands = {}
    if cell is not None:
        # single-sided in this run = recorded on exactly one side; the rows
        # are ascending in both lists, so this visits the corpus in the same
        # order the full scan did and breaks ties the same way.
        taken, nottaken = set(cell[1]), set(cell[2])
        for i in cell[0]:
            t_, f_ = i in taken, i in nottaken
            if t_ == f_:
                continue
            s = "taken" if t_ else "not_taken"
            p, seeds, scen, _exprs = rows[i]
            digest, shapes, _pcs = tidx[p]
            carried = frozenset(z for z in shapes if z in fp and enabling.get(z) == s)
            if not carried:
                continue
            best = cands.get(digest)
            if best is None or len(seeds) > len(best[1]):
                cands[digest] = (p, seeds, scen, carried, s)
    ranked = sorted(cands.values(), key=lambda c: (-len(c[3]), -len(c[1]), c[0]))
    if _CONF_PROFILES:
        ranked = ranked[:_CONF_PROFILES]
    out = []
    for p, seeds, scen, carried, s in ranked:
        sd = load_dump(p)
        out.append((p, scen, carried, s, flipped_seeds(sd, dict(seeds), expr, dim)))
    _PROFILE_REPS[key] = (out, len(cands))
    if _DERIVE_CK is not None:
        _DERIVE_CK.put(ck_key, _reps_to_json(batch, out, len(cands)))
    return _PROFILE_REPS[key]


def _exhaustive_flip(cfg, a, cache, who, expr, fp, enabling, notes, producers=None):
    """(vi) EXHAUSTIVE FLIP OVER PROFILES — criterion (v) made complete over the
    corpus's own contexts. For decision `expr` with footprint `fp` (shape ->
    enabling side), take EVERY distinct outcome profile in the corpus whose
    representative run has the decision single-sided on a shape's enabling
    side and carries that shape; flip the decision on the representative,
    replay, and FAIL if any such shape is still present — or if the decision
    is unevaluated in the replay while the shape is present (a route around
    it). A surviving shape is allowed when another PRODUCER of it (a
    decision whose footprint holds it) is recorded on its producing side in
    the replay — OR-sharing, round 5; unexplained survival is the FAIL.
    Representatives: one per profile digest, richest seed dict; capped at
    ACHK_CONF_PROFILES (default 0 = ALL), most-shapes-carried first; a cap
    that truncates makes the verdict NOT-TESTABLE (the count probed/available
    is reported), and so does a representative whose flip did not take —
    a PASS means every profile was flipped and every flip took. Returns
    ``(verdict or None, detail)`` where verdict is "FAIL" / "NOT-TESTABLE"."""
    batch = cfg["batch_dir"]
    ranked, n_cands = _profile_representatives(batch, expr, fp, enabling)
    probed = dead = unevald = 0
    dead_ex = None
    for p, scen, carried, s, fl in ranked:
        if fl is None:
            dead += 1
            dead_ex = dead_ex or f"{os.path.basename(p)}: no flip value"
            continue
        r = cache.run(fl, scen, f"conf_prof_{who}")
        if cache.planning:
            continue
        probed += 1
        if r is None:
            dead += 1
            dead_ex = dead_ex or f"{os.path.basename(p)}: no run"
            continue
        tr = {shape_str(x) for x in trace_of(r)}
        got = outcomes_of(r, expr)
        leaked = sorted(z for z in (carried & tr) if not _explained(z, r, producers or {}))
        if not got:
            unevald += 1
            if leaked:
                return (f"(vi) route AROUND {who}: {leaked[0][:70]} present with {who} "
                        f"UNEVALUATED after flipping it on profile {p and os.path.basename(p)}",
                        "")
            continue
        if got == frozenset([s == "taken"]):
            dead += 1
            dead_ex = dead_ex or f"{os.path.basename(p)}: same outcome"
            continue
        if leaked:
            return ("FAIL",
                    f"(vi) {leaked[0][:70]} present after flipping {who} to its non-enabling "
                    f"side on profile {os.path.basename(p)} ({len(leaked)} shape(s))")
    if cache.planning:
        return None, ""
    if dead:
        return ("NOT-TESTABLE",
                f"(vi) {who}: {dead} of {len(ranked)} profile flip(s) did not take "
                f"({dead_ex}) — unverified on those contexts, no evidence")
    if n_cands > len(ranked):
        return ("NOT-TESTABLE",
                f"(vi) {who}: probe budget truncated ({len(ranked)}/{n_cands} profiles, "
                f"ACHK_CONF_PROFILES={_CONF_PROFILES}) — a PASS needs every profile")
    notes.append(f"(vi) {who}: {probed}/{n_cands} profile(s) flipped"
                 + (f", {unevald} left {who} unevaluated" if unevald else ""))
    return None, ""


#: (2026-09-12, perf) memo for `_route_construction`. The construction of a
#: route is a function of the DECISION, the other producers of the shape and
#: their gates — never of the pair the decision happens to be declared in —
#: and it is the most expensive derivation in the gate: a snapshot selection,
#: an outcome read per wanted literal over a whole dump, and a Z3 call. On
#: posts_show it was run 60 014 times for 112 decisions.
#: A route is cached as (base path, scenario, keys ADDED/CHANGED, keys
#: REMOVED) against `_ROUTE_BASES[base path]`, never as a whole seed dict: a
#: seed dict is ~117 keys and there are up to 60 000 routes on posts_show.
_ROUTE_CACHE = {}
_ROUTE_BASES = {}
#: Z3 declarations of one base dump, by path: `Run.from_dict` parses the
#: whole dump and the same base serves every shape of a decision.
_Z3_DECLS = {}


def _route_seeds(sp, delta, removed):
    seeds = dict(_ROUTE_BASES[sp])
    seeds.update(delta)
    for k in removed:
        seeds.pop(k, None)
    return seeds


def _route_construction(batch, expr, prods, enabling_z, gates):
    """The (vii) construction for one footprint shape, without the replay.

    Returns ``(status, payload)``: ``("no-base", None)``,
    ``("unconstructible", "(reason)")``, ``("unsat", None)`` or
    ``("ok", (base path, scenario, seed dict))`` — exactly the four outcomes
    the inline code produced, with the same messages built by the caller."""
    corpus_index(batch)                 # before the memo: a rebuild purges it
    key = (batch, canon(expr), tuple(prods), enabling_z,
           tuple(sorted((k, tuple(tuple(x) for x in v))
                        for k, v in (gates or {}).items()
                        if k == expr or k in {d for d, _s in prods})))
    hit = _ROUTE_CACHE.get(key)
    if hit is not None:
        if hit[0] != "ok":
            return hit
        sp_, scen_, delta_, removed_ = hit[1]
        return ("ok", (sp_, scen_, _route_seeds(sp_, delta_, removed_)))
    needed = [expr] + [d for d, _s in prods]
    snap = pick_snapshot_with(batch, needed, []) or pick_snapshot_with(batch, [expr], [])
    if snap is None:
        _ROUTE_CACHE[key] = ("no-base", None)
        return _ROUTE_CACHE[key]
    sp, sd = snap
    scen = (sd.get("concolic_scenario") or {}).get("name")
    # NAME BOUNDARY (2026-09-14): the adversarial route's base seeds are a
    # probe seed dict too -- same hazard as the five above. `seeds_as_written`
    # is the PRE-hook dict the runner actually reads.
    base_seeds = _ROUTE_BASES.setdefault(sp, dict(seeds_as_written(sd)))
    seeds = dict(base_seeds)
    # literals wanted: the decision OFF its enabling side; each producer ON; gates open
    want = [(expr, enabling_z != "taken")]                # outcome wanted for expr
    for d, side in prods:
        want.append((d, side != "taken" if side != "both" else False))   # producer OFF
        for g, o in gates.get(d, []):
            want.append((g, o != "taken"))                # g != o
    for g, o in gates.get(expr, []):
        want.append((g, o != "taken"))
    # one outcome map per base dump, not one full event scan per wanted literal
    outs = _outcomes_of_dump(sd)
    unresolved = []
    for e_, o_ in want:
        got = outs.get(canon(e_), frozenset())
        d_ = expr_dimension(e_)
        if not d_:
            unresolved.append(e_)
            continue
        if got == frozenset([o_]):
            continue                                      # already as wanted
        if got:
            fl = flipped_seeds(sd, seeds, e_, d_)
            if fl is None:
                unresolved.append(e_)
            else:
                seeds = fl
        else:
            unresolved.append(e_)
    if unresolved:
        # SOLVER ROUTE for literals the base never recorded
        try:
            from concolic_engine.run import Run
            from concolic_engine.solver import check_satisfiability
            if sp not in _Z3_DECLS:
                _Z3_DECLS[sp] = Run.from_dict(sd).z3_declarations()
            decls = _Z3_DECLS[sp]
            cons = [e_ if o_ else f"Not({e_})" for e_, o_ in want]
            res = check_satisfiability([canon(c) for c in cons], decls, 5000)
        except Exception as exc:                          # noqa: BLE001
            _ROUTE_CACHE[key] = ("unconstructible",
                                 f"({type(exc).__name__}: {exc})")
            return _ROUTE_CACHE[key]
        if not res.satisfiable:
            _ROUTE_CACHE[key] = ("unsat", None)
            return _ROUTE_CACHE[key]
        model = res.model or {}
        missing = []
        for e_ in unresolved:
            d_ = expr_dimension(e_)
            if d_ in model:
                seeds[_runtime_key(sd, d_)] = model[d_]
            else:
                missing.append(e_)
        if missing:
            _ROUTE_CACHE[key] = ("unconstructible", f"(no seed for {missing[0][:40]})")
            return _ROUTE_CACHE[key]
    _ROUTE_CACHE[key] = ("ok", (sp, scen,
                                {k: v for k, v in seeds.items()
                                 if k not in base_seeds or base_seeds[k] != v},
                                tuple(k for k in base_seeds if k not in seeds)))
    return ("ok", (sp, scen, seeds))


def _constructed_route(cfg, a, cache, who, expr, fp, enabling, producers, gates, notes):
    """(vii) ADVERSARIAL CONSTRUCTED PROBE — the gate actively searching for
    the route the corpus never walked. Per shape Z in the footprint that has
    OTHER producers: a run whose seeds put the decision on its NON-enabling
    side AND every other producer of Z OFF its producing side, with each of
    their foreclosing gates held open (`g != o`) — the (off, off, ...) cell.
    Z present there is a route around every known producer: FAIL. (Round 5:
    producers ON with the decision off is OR-sharing, explained by
    definition, so it is no longer the route probed.) Base = the richest run recording the decision and all the
    producers; a literal the base does not record is obtained from a Z3
    model over the base's declared variables (`concolic_engine.solver`) —
    UNSAT is recorded as evidence: "no route to Z exists with the decision
    off under the inferred structure". Replay; FAIL if Z appears (or if the
    decision is unevaluated and Z appears — a route around it). One probe per
    distinct constructed seed dict (identical constructions dedupe in the
    cache). Shapes with no other producer need no construction: flipping the
    decision alone is (vi)'s job. A route that could not be constructed
    (no base, no seed for a literal, or no run produced) makes the verdict
    NOT-TESTABLE: the gate could not try it, so it cannot vouch. Returns
    ``(verdict or None, detail)``."""
    batch = cfg["batch_dir"]
    dim = expr_dimension(expr)
    tried = unsat = unconstructible = 0
    for z in sorted(fp):
        prods = [(d, sd_) for d, sd_ in (producers.get(z) or []) if d != expr]
        if not prods:
            continue
        status, payload = _route_construction(batch, expr, prods, enabling.get(z),
                                              gates)
        if status == "no-base":
            return ("NOT-TESTABLE", f"(vii) {who}/{z[:40]}: no run records {who} — route unconstructible")
        if status == "unconstructible":
            return ("NOT-TESTABLE",
                    f"(vii) {who}/{z[:40]}: route unconstructible {payload}"[:220])
        if status == "unsat":
            unsat += 1
            notes.append(f"(vii) {who}/{z[:40]}: UNSAT — no route to the shape with {who} "
                         f"off under the inferred structure")
            continue
        sp, scen, seeds = payload
        r = cache.run(seeds, scen, f"conf_route_{who}")
        if cache.planning:
            continue
        tried += 1
        if r is None:
            return ("NOT-TESTABLE", f"(vii) {who}/{z[:40]}: constructed route produced no run")
        tr = {shape_str(x) for x in trace_of(r)}
        got = outcomes_of(r, expr)
        if z in tr:
            how = "UNEVALUATED" if not got else ("on its non-enabling side"
                                                 if got != frozenset([enabling.get(z) == "taken"])
                                                 else "still on its enabling side (construction did not take)")
            if got == frozenset([enabling.get(z) == "taken"]):
                return ("NOT-TESTABLE",
                        f"(vii) {who}/{z[:40]}: construction did not flip {who} — unverified")
            if _explained(z, r, producers):
                return ("NOT-TESTABLE",
                        f"(vii) {who}/{z[:40]}: a producer stayed ON in the all-off construction — unverified")
            return ("FAIL",
                    f"(vii) route around every known producer: {z[:70]} present with {who} {how} "
                    f"and producers OFF ({', '.join(d.split('__')[-1][:30] for d, _s in prods)}; "
                    f"base {os.path.basename(sp)})")
    if cache.planning:
        return None, ""
    if tried or unsat:
        notes.append(f"(vii) {who}: {tried} constructed route(s) replayed"
                     + (f", {unsat} UNSAT (no route exists)" if unsat else ""))
    return None, ""


def _test_confinement(cfg, a, cache, out):
    """Derived test for a CONFINED PAIR (DISCIPLINE §16c, inferred by the
    coverage checker, handed to the gate as type ``ConfinementAssumption``
    with ``footprint_a`` / ``footprint_b`` — the shapes each decision's
    outcome was measured to control).

    The claim: A's outcome and B's outcome control DISJOINT sets of
    target-call shapes, so no shape needs both and the cross product is not
    demanded. The test is a COMPOSITION BY REPLAY on one snapshot that
    recorded both: flip A alone, flip B alone, flip both. PASS iff

      (i)   flip-A changes only shapes in footprint(A);
      (ii)  flip-B changes only shapes in footprint(B);
      (iii) trace(flip-both) == (base - removed_A - removed_B)
                                 | added_A | added_B  — the two deltas compose;
      (iv)  each single flip leaves the PARTNER decision evaluated with its
            base outcome, and the double flip records both flipped. This is
            what makes the test see REMOVAL-shaped dependence (X11): a flip
            that deletes the partner from the path makes "A's delta" include
            B's disappearance — foreclosure, not confinement;
      (v)   STRICT one-sidedness observed by replay (owner's refinement,
            2026-09-11): no shape of footprint(A) present in the base
            SURVIVES flipping A (in flip-A or in flip-both); likewise for B.
            A footprint shape that is still issued with the decision on its
            other side is not the decision's to control;
      (vi)  (v) made complete over the corpus: EVERY distinct outcome profile
            carrying a footprint shape is flipped and replayed
            (`_exhaustive_flip`, capped per decision, count reported);
      (vii) an ADVERSARIAL CONSTRUCTED route per footprint shape that has
            other producers: the decision off AND every other producer off
            (the all-off cell) with its gates held open — from a base run or
            a Z3 model; UNSAT is recorded as evidence (`_constructed_route`);
      (viii) (round 5, OR-sharing) a shape in BOTH footprints is judged on
            the four replays as a 2x2: OR / A-only / B-only / ALWAYS pass,
            AND or a non-monotone cell is interaction and FAILs; (iii) and (v)
            then apply to the unshared shapes only, and a surviving shape is
            allowed where another producer of it is on in that replay.

    Cost model, per confined DECISION (shared across the pairs it is in —
    identical seed dicts dedupe in the ProbeCache): 3 composition replays
    per pair + min(ACHK_CONF_PROFILES, profiles carrying a footprint shape)
    for (vi) + one constructed replay per footprint shape with another
    producer for (vii).

    Any deviation is FAIL (the pair is withdrawn). A flip that did not take
    (the flipped decision records its base outcome, or is not recorded) is
    NOT-TESTABLE — a dead knob is no evidence either way. NOT-COMPARABLE
    when a flip changed what an aliased ordinal resolved to. Shapes compare
    as SETS (presence), exactly as the footprint is defined."""
    batch = cfg["batch_dir"]
    ea, eb = a.get("expr_a", ""), a.get("expr_b", "")
    if a.get("footprint_a") is None or a.get("footprint_b") is None:
        out.update(verdict="NOT-TESTABLE",
                   detail="a member's footprint is UNDECIDABLE — no confinement claim exists to test")
        return out
    fpa, fpb = set(a["footprint_a"]), set(a["footprint_b"])
    # (round 5) shared footprint shapes are legitimate when OR-shared; they
    # are judged by REPLAY in (viii) below, never passed on the corpus alone
    da, db = expr_dimension(ea), expr_dimension(eb)
    if not da or not db:
        out.update(verdict="NOT-TESTABLE", detail="cannot derive seed dimensions from exprs")
        return out
    # X12 (2026-09-14): the COMPOSITION -- criteria (i)-(v) and (viii) -- is
    # judged on a base, and the shipped test judged it on ONE. (vi) and (vii)
    # are functions of the DECISION and the corpus, never of the composition
    # base, so they stay where they are: run ONCE, after the composition has
    # been shown to hold on at least one base. The loop stops at the first
    # FAIL, so a FAILing pair still costs the shipped 3 replays.
    bases = pick_bases_with(batch, [ea, eb])
    if not bases:
        out.update(verdict="NOT-TESTABLE",
                   detail="no run in the CURRENT corpus records both — the pair is inert, nothing to test")
        return out
    per_base, held = [], None
    for sp, sd in bases:
        o = _confinement_composition(cfg, a, cache, {}, ea, eb, da, db, fpa, fpb, sp, sd)
        if cache.planning:
            continue
        o["base"] = os.path.basename(sp)
        per_base.append(o)
        if o["verdict"] == "FAIL":
            break
        if o["verdict"] == "PASS" and held is None:
            held = o
    if not cache.planning:
        if held is None:
            return _combine_bases(per_base, out, "confined pair")
        # (vi) / (vii): the ACTIVE search — every profile, then constructed
        # routes. Base-INDEPENDENT, so once, not once per base.
        notes = []
        producers = a.get("producers") or {}
        en_a, en_b = a.get("enabling_a") or {}, a.get("enabling_b") or {}
        gates = a.get("gates") or {}
        for who, e_, fp_, en_ in (("A", ea, fpa, en_a), ("B", eb, fpb, en_b)):
            for probe in (_exhaustive_flip, _constructed_route):
                if probe is _exhaustive_flip:
                    verdict_, detail_ = probe(cfg, a, cache, who, e_, fp_, en_, notes, producers)
                else:
                    verdict_, detail_ = probe(cfg, a, cache, who, e_, fp_, en_,
                                              producers, gates, notes)
                if verdict_:
                    out.update(verdict=verdict_, detail=detail_)
                    out.update(
                        bases_probed=len(per_base),
                        bases_realising=sum(1 for p in per_base
                                            if p["verdict"] not in _BASE_VACUOUS),
                        bases_passing=sum(1 for p in per_base if p["verdict"] == "PASS"),
                        bases_failing=sum(1 for p in per_base if p["verdict"] == "FAIL"),
                        base_verdicts=[{"base": p.get("base"), "verdict": p["verdict"],
                                        "detail": (p.get("detail") or "")[:200]}
                                       for p in per_base])
                    return out
        held["detail"] = held.get("detail", "") + "; " + "; ".join(notes)
        return _combine_bases(per_base, out, "confined pair")

    # planning pass: enqueue the active probes' replays too
    notes = []
    for who, e_, fp_, en_ in (("A", ea, fpa, a.get("enabling_a") or {}),
                              ("B", eb, fpb, a.get("enabling_b") or {})):
        _exhaustive_flip(cfg, a, cache, who, e_, fp_, en_, notes, a.get("producers") or {})
        _constructed_route(cfg, a, cache, who, e_, fp_, en_,
                           a.get("producers") or {}, a.get("gates") or {}, notes)
    return out


def _confinement_composition(cfg, a, cache, out, ea, eb, da, db, fpa, fpb, sp, sd):
    """ONE base's verdict for `_test_confinement` criteria (i)-(v) and (viii)
    — the shipped COMPOSITION BY REPLAY, verbatim, with the base handed in
    instead of picked (X12). Criteria (vi)/(vii) are base-independent and are
    run once by the caller."""
    scen = (sd.get("concolic_scenario") or {}).get("name")
    # NAME BOUNDARY (2026-09-14): `sd` is a LOADED dump, so on a batch with a
    # `fix_len_names` canonicalize hook its `concolic_seeds` keys have been
    # rewritten to `SYM_LEN_X` -- which the Ruby runtime never reads. Launching
    # a probe from them silently drops the snapshot's whole length context.
    # `seeds_as_written` is the PRE-hook dict, i.e. what the runner was actually
    # handed. Identity when no canonicalize hook is installed.
    seeds = dict(seeds_as_written(sd))
    fa = flipped_seeds(sd, seeds, ea, da)
    fb = flipped_seeds(sd, seeds, eb, db)
    if fa is None or fb is None:
        out.update(verdict="NOT-TESTABLE", detail="cannot infer a flip value from the recorded PC")
        return out
    fab = _combined_flip(sd, fa, fb, db)
    ra, rb, rab = (cache.run(x, scen, f"conf_{i}") for i, x in enumerate((fa, fb, fab)))
    if cache.planning:
        return out
    if None in (ra, rb, rab):
        out.update(verdict="FAIL", detail="a flip probe produced no dump in the snapshot's scenario")
        return out
    for tag_, r_ in (("flip-A", ra), ("flip-B", rb), ("flip-both", rab)):
        for e_ in (ea, eb):
            why = _reading_changed(sd, r_, e_)
            if why:
                out.update(verdict="NOT-COMPARABLE", detail=f"{tag_}: {why}")
                return out
    oa, ob = outcomes_of(sd, ea), outcomes_of(sd, eb)
    if len(oa) != 1 or len(ob) != 1:
        out.update(verdict="NOT-TESTABLE", detail="snapshot records a member both ways — no single base outcome to flip")
        return out
    # did each flip take? A flip that leaves the decision UNEVALUATED while a
    # footprint shape it enabled in the base is still issued is a ROUTE
    # AROUND the decision — FAIL, not a dead knob.
    base = {shape_str(x) for x in access_trace(sd)}
    for tag_, r_, e_, o_, fp_, who in (("flip-A", ra, ea, oa, fpa, "A"),
                                       ("flip-B", rb, eb, ob, fpb, "B")):
        got = outcomes_of(r_, e_)
        if not got:
            around = sorted(fp_ & base & {shape_str(x) for x in trace_of(r_)})
            if around:
                out.update(verdict="FAIL",
                           detail=f"(v) route AROUND {who}: {around[0][:70]} still issued with {who} "
                                  f"UNEVALUATED after {tag_} ({len(around)} shape(s))")
                return out
        if not got or got == o_:
            out.update(verdict="NOT-TESTABLE",
                       detail=f"{tag_} did not flip {who} "
                              f"({'unevaluated' if not got else 'same outcome'}): dead knob, no evidence")
            return out
    # (iv) the partner stays evaluated, with its base outcome; both flipped in flip-both
    for tag_, r_, e_, o_, who in (("flip-A", ra, eb, ob, "B"), ("flip-B", rb, ea, oa, "A")):
        got = outcomes_of(r_, e_)
        if not got:
            out.update(verdict="FAIL",
                       detail=f"(iv) {tag_} leaves {who} UNEVALUATED — removal-shaped dependence "
                              f"(foreclosure, X11), not a confined pair")
            return out
        if got != o_:
            out.update(verdict="FAIL",
                       detail=f"(iv) {tag_} changed {who}'s outcome — {who} is downstream of the flipped decision")
            return out
    for e_, o_, who in ((ea, oa, "A"), (eb, ob, "B")):
        got = outcomes_of(rab, e_)
        if not got or got == o_:
            out.update(verdict="FAIL",
                       detail=f"(iv) flip-both does not record {who} flipped "
                              f"({'unevaluated' if not got else 'base outcome'})")
            return out
    ta = {shape_str(x) for x in trace_of(ra)}
    tb = {shape_str(x) for x in trace_of(rb)}
    tab = {shape_str(x) for x in trace_of(rab)}
    producers = a.get("producers") or {}
    shared = fpa & fpb
    for who, fp_, flips in (("A", fpa - shared, (("flip-A", ra, ta), ("flip-both", rab, tab))),
                            ("B", fpb - shared, (("flip-B", rb, tb), ("flip-both", rab, tab)))):
        for tag_, r_, tr_ in flips:
            # a surviving shape is allowed only when ANOTHER producer of it is
            # recorded on its producing side in that replay (OR-sharing)
            surv = sorted(z for z in (fp_ & base & tr_) if not _explained(z, r_, producers))
            if surv:
                out.update(verdict="FAIL",
                           detail=f"(v) {len(surv)} shape(s) in footprint({who}) SURVIVE {tag_} — "
                                  f"not strictly one-sided: " + "; ".join(surv[:3]))
                return out
    # (viii) SHARED shapes (OR-sharing, round 5): the four replays ARE the
    # 2x2 of this snapshot's context — base (sa, sb), flip-A, flip-B, both.
    # A shared shape must be OR-monotone in it: present only with both on
    # (AND) or a non-monotone cell is INTERACTION, FAIL.
    if shared:
        from concolic_engine.coverage import classify_cells, _BENIGN
        sa, sb = next(iter(oa)), next(iter(ob))
        for z in sorted(shared):
            cells = {(sa, sb): 1 if z in base else 0, (not sa, sb): 1 if z in ta else 0,
                     (sa, not sb): 1 if z in tb else 0, (not sa, not sb): 1 if z in tab else 0}
            cls = classify_cells(cells)
            if cls not in _BENIGN and cls != "OR-family":
                out.update(verdict="FAIL",
                           detail=f"(viii) shared shape is {cls} by replay — interaction: {z[:70]} "
                                  f"(base={cells[(sa, sb)]} flipA={cells[(not sa, sb)]} "
                                  f"flipB={cells[(sa, not sb)]} both={cells[(not sa, not sb)]})")
                return out
    d_a, d_b = ta ^ base, tb ^ base
    leak_a, leak_b = d_a - fpa, d_b - fpb
    if leak_a:
        out.update(verdict="FAIL",
                   detail=f"(i) flip-A changed {len(leak_a)} shape(s) OUTSIDE footprint(A): "
                          + "; ".join(sorted(leak_a)[:3]))
        return out
    if leak_b:
        out.update(verdict="FAIL",
                   detail=f"(ii) flip-B changed {len(leak_b)} shape(s) OUTSIDE footprint(B): "
                          + "; ".join(sorted(leak_b)[:3]))
        return out
    # (iii) over the UNSHARED shapes: the additive law is the no-interaction
    # law for a shape one decision controls; an OR-shared shape obeys the
    # monotone law instead (present under either, absent only with both off
    # — it survives each single flip and vanishes only in the double one),
    # which (viii) has already checked on all four cells.
    predicted = ((base - (base - ta) - (base - tb)) | (ta - base) | (tb - base)) - shared
    if (tab - shared) != predicted:
        dev = (tab - shared) ^ predicted
        out.update(verdict="FAIL",
                   detail=f"(iii) flip-both deviates from base+ΔA+ΔB on {len(dev)} shape(s) "
                          f"({len(tab - predicted)} unexpected, {len(predicted - tab)} missing): "
                          + "; ".join(sorted(dev)[:3]))
        return out
    out.update(verdict="PASS",
               detail=f"(i) ΔA={len(d_a)} ⊆ footprint(A) (ii) ΔB={len(d_b)} ⊆ footprint(B) "
                      f"(iii) composition exact (iv) partners stayed evaluated "
                      f"(v) no unshared footprint shape survived its flip "
                      f"(viii) {len(shared)} shared shape(s) OR-monotone by replay"
                      f" (snapshot {os.path.basename(sp)})")
    return out


def _test_subconjunction_foreclosure(cfg, a, cache, out):
    """Derived test for a SUB-CONJUNCTION FORECLOSURE (DISCIPLINE §16f,
    inferred by the coverage checker, handed to the gate as type
    ``SubconjunctionForeclosureAssumption``).

    IDENTICAL probe to ``_test_conjunction_foreclosure`` — the claim has the
    same shape ("no run matching this conjunction evaluates this member") and
    the same single-run falsifier — with two differences that are about the
    CLAIM, not the machinery:

      * the literals of ``C`` need not be gates (``conditioning`` is the
        honest key; ``gates`` carries the same list so one probe serves both),
        so a flip may be applied to an ordinary member;
      * ``C`` is a SUB-conjunction, so it is short by construction — the
        width cap ``foreclosure_conjunction_width`` bounds the number of
        literals that can need flipping, and with it the cost.

    DISCIPLINE §16g (2026-09-14) rides on this test unchanged. A well-founded
    drop is the same claim with ``C`` drawn from anywhere in the leaf rather
    than from the member's walk prefix, so the base ("the richest snapshot
    that records ``d`` together with every literal of ``C``") and the probe
    (flip the literals whose recorded outcome differs) are identical. Rows
    carry ``wellfounded: True`` / ``section: "16g"`` for the report only.

    The realised-value rule is unchanged: a probe that does not REALISE every
    literal of ``C`` is NOT-TESTABLE, never a PASS.
    """
    return _test_conjunction_foreclosure(cfg, a, cache, out, kind="subconj")


def _test_conjunction_foreclosure(cfg, a, cache, out, kind="conj"):
    """Derived test for a CONJUNCTION FORECLOSURE (DISCIPLINE §16e, inferred
    by the coverage checker, handed to the gate as type
    ``ConjunctionForeclosureAssumption`` with ``gates`` — the leaf group's
    gate prefix ``P`` — and ``expr`` — the member ``d`` the corpus never
    evaluates under it).

    Shared with §16f's ``SubconjunctionForeclosureAssumption`` (``kind`` is
    the probe label only): there, ``gates`` is the conditioning set ``C``,
    whose literals need not be gates.

    The claim: no run that matches ``P`` evaluates ``d``, so ``d`` is not
    part of that leaf and the leaf's assignments over it are not demanded.
    The falsifier is a single run: one that matches ``P`` AND evaluates
    ``d``. The test therefore tries to BUILD that run, on the same machinery
    the §16b/OneSideUntracked tests use.

      base   the richest snapshot that recorded ``d`` together with every
             gate of ``P`` — so the base is already a run in which ``d`` IS
             evaluated, which is exactly "``d``'s inputs seeded to force its
             evaluation"; nothing else is touched, so any change is the
             gates';
      probe  that snapshot's seeds with every gate whose recorded outcome
             differs from ``P``'s FLIPPED, each at the runtime (ordinal) key
             the runner seeds by (X10, 2026-09-11), replayed in the
             snapshot's own scenario.

      FAIL           the probe realises ``P`` and RECORDS ``d`` — the
                     universal is refuted and the foreclosure is withdrawn.
      PASS           the probe realises ``P`` and does not record ``d``.
      NOT-TESTABLE   the probe does not realise ``P`` (today's realised-value
                     rule: a seed is a request the app may clamp, snap or
                     ignore, and a run that is not under ``P`` says nothing
                     about what happens under it), no snapshot records the
                     member with the gates, no flip value can be inferred, or
                     the replay produced no dump at all. Never a PASS.
      NOT-COMPARABLE a flip changed what an aliased ordinal RESOLVED TO, so
                     the probe's evidence is about a different decision.

    Cost: ONE replay per foreclosure class (the ProbeCache dedupes identical
    seed dicts, so classes sharing a prefix share their probe)."""
    batch = cfg["batch_dir"]
    d = a.get("expr", "")
    gates = [(g, side == "taken")
             for g, side in (a.get("conditioning") or a.get("gates") or [])]
    if not d or not gates:
        out.update(verdict="NOT-TESTABLE",
                   detail="no member or no gate prefix — nothing was inferred to test")
        return out
    # X12 (2026-09-14): MANY bases, not one. §39 measured the single-base
    # version reporting NOT-TESTABLE on 24 of 24 §16g classes while other
    # bases in the same corpus refuted 18 of them. The loop stops at the first
    # FAIL (a refutation is decisive and needs no second opinion), so a FAIL
    # still costs one probe; only a PASS or a NOT-TESTABLE pays for K bases.
    bases = pick_bases_with(batch, [d] + [g for g, _o in gates])
    if not bases:
        out.update(verdict="NOT-TESTABLE",
                   detail="no run in the CURRENT corpus records the member together with "
                          "every gate of the prefix — no base to seed the probe from")
        return out
    per_base = []
    for sp, sd in bases:
        o = _conjunction_foreclosure_once(cfg, a, cache, {}, d, gates, sp, sd, kind)
        if cache.planning:
            continue
        o["base"] = os.path.basename(sp)
        per_base.append(o)
        if o["verdict"] == "FAIL":
            break
    if cache.planning:
        return out
    return _combine_bases(per_base, out, "foreclosure")


def _conjunction_foreclosure_once(cfg, a, cache, out, d, gates, sp, sd, kind):
    """ONE base's verdict for `_test_conjunction_foreclosure` — the shipped
    probe, verbatim, with the base handed in instead of picked (X12)."""
    batch = cfg["batch_dir"]
    scen = (sd.get("concolic_scenario") or {}).get("name")
    # NAME BOUNDARY (2026-09-14): `sd` is a LOADED dump, so on a batch with a
    # `fix_len_names` canonicalize hook its `concolic_seeds` keys have been
    # rewritten to `SYM_LEN_X` -- which the Ruby runtime never reads. Launching
    # a probe from them silently drops the snapshot's whole length context.
    # `seeds_as_written` is the PRE-hook dict, i.e. what the runner was actually
    # handed. Identity when no canonicalize hook is installed.
    seeds = dict(seeds_as_written(sd))
    # Flip only the gates the base does not already take P's way. A gate the
    # base records BOTH ways already matches P per-literal (the same reading
    # the inference used), so it is left alone.
    to_flip = [(g, o) for g, o in gates if o not in outcomes_of(sd, g)]
    for g, _o in to_flip:
        dim = expr_dimension(g)
        if not dim:
            out.update(verdict="NOT-TESTABLE",
                       detail=f"cannot derive a seed dimension for gate {g[:80]}")
            return out
        nxt = flipped_seeds(sd, seeds, g, dim)
        if nxt is None:
            out.update(verdict="NOT-TESTABLE",
                       detail=f"cannot infer a flip value from the recorded PC of gate {g[:80]}")
            return out
        seeds = nxt
    r = cache.run(seeds, scen, "conjf" if kind == "conj" else "subconjf")
    if cache.planning:
        return out
    if r is None:
        out.update(verdict="NOT-TESTABLE",
                   detail=f"the probe produced no dump in scenario {scen!r}: the gate "
                          "conjunction was not shown to be walked, so this is untested, "
                          "not held")
        return out
    for e_ in [d] + [g for g, _o in gates]:
        why = _reading_changed(sd, r, e_)
        if why:
            out.update(verdict="NOT-COMPARABLE", detail=why)
            return out
    unmet = [f"{g}={'T' if o else 'F'}" for g, o in gates if o not in outcomes_of(r, g)]
    if unmet:
        out.update(verdict="NOT-TESTABLE",
                   detail=("the probe did not REALISE the gate conjunction "
                           f"({len(unmet)} of {len(gates)} literal(s) unmet: "
                           + "; ".join(x[:60] for x in unmet[:3]) +
                           ") — seeding is not realising, so it cannot vouch"))
        return out
    if recorded(r, d):
        out.update(verdict="FAIL",
                   detail=("REFUTED: a run matching the whole gate conjunction "
                           f"EVALUATES {d[:80]} (snapshot {os.path.basename(sp)}, "
                           f"{len(to_flip)} gate(s) flipped) — the foreclosure is "
                           "withdrawn and the leaf's assignments over it are demanded"))
    else:
        out.update(verdict="PASS",
                   detail=(f"a run realising the conjunction ({len(to_flip)} gate(s) "
                           f"flipped from {os.path.basename(sp)}, which DOES record the "
                           "member) leaves the member unevaluated"))
    return out


def test_declared(cfg, a, cache):
    """Derive and run the test for one declared assumption dict
    (keys: type, expr / expr_a, expr_b, tracked_side...). Returns a
    verdict dict."""
    typ = a.get("type", "")
    batch = cfg["batch_dir"]
    # X12 (2026-09-14): the EVIDENCE GRADE is part of every row, not only of
    # the rows a multi-base loop produced. A verdict reached without probing
    # any base (a claim with no derivable dimension, an alias claim, an
    # ERROR) says so with zeros; a verdict from ONE realising base says so
    # with ones. Six of people_stream's 30 PASSes have exactly one realising
    # base in the whole corpus, and that has to be legible in the record
    # rather than re-measurable only by running the gate again.
    out = {"type": typ, "expr": a.get("expr") or a.get("expr_a"),
           "expr_b": a.get("expr_b"), "verdict": "?", "detail": "",
           "bases_probed": 0, "bases_realising": 0, "bases_passing": 0,
           "bases_failing": 0, "base_verdicts": []}
    # DISCIPLINE §16g (2026-09-14): a well-founded drop reaches the gate as a
    # `SubconjunctionForeclosureAssumption` because the PROBE is the same one
    # (<= W literals to flip from a base that records the member). Carry the
    # provenance into the row so a report can separate the two claims; the
    # test itself is unchanged.
    if a.get("wellfounded"):
        out["section"] = a.get("section") or "16g"
        out["wellfounded"] = True

    if typ == "IndependenceAssumption":
        ea, eb = a.get("expr_a", ""), a.get("expr_b", "")
        da, db = expr_dimension(ea), expr_dimension(eb)
        if not da or not db:
            out.update(verdict="NOT-TESTABLE", detail="cannot derive seed dimensions from exprs")
            return out
        # X12 (2026-09-14): MANY bases, not one. The flip-both probe is
        # derived from its base, so "no novel shape" is a statement about that
        # base's context; another base may put the pair in a context where the
        # combination DOES produce one. Stops at the first FAIL.
        bases = pick_bases_with(batch, [ea, eb])
        if not bases:
            missing = [e for e in (ea, eb) if pick_snapshot_with(batch, [e], []) is None]
            if missing:
                out.update(verdict="NOT-TESTABLE",
                           detail="expr never recorded in the CURRENT corpus (stale or renamed): " + missing[0][:80])
                return out
            out.update(verdict="PASS",
                       detail="[0 base(s) probed, 0 realising; corpus fact, not a replay] "
                              "mutually exclusive: both recorded, never co-evaluated in any run")
            return out
        per_base = []
        for sp, sd in bases:
            o = _independence_once(cfg, a, cache, {}, ea, eb, da, db, sp, sd)
            if cache.planning:
                continue
            o["base"] = os.path.basename(sp)
            per_base.append(o)
            if o["verdict"] == "FAIL":
                break
        if cache.planning:
            return out
        return _combine_bases(per_base, out, "independence pair")

    if typ in ("UntrackedPathAssumption", "OneSideUntrackedPathAssumption"):
        e = a.get("expr", "")
        d = expr_dimension(e)
        if not d:
            out.update(verdict="NOT-TESTABLE", detail="cannot derive seed dimension from expr")
            return out
        # X12 (2026-09-14): MANY bases, not one — same reasoning.
        bases = pick_bases_with(batch, [e])
        if not bases:
            out.update(verdict="NOT-TESTABLE",
                       detail="expr never recorded in the CURRENT corpus (stale assumption? it carries no coverage now)")
            return out
        per_base = []
        for sp, sd in bases:
            o = _untracked_once(cfg, a, cache, {}, typ, e, d, sp, sd)
            if cache.planning:
                continue
            o["base"] = os.path.basename(sp)
            per_base.append(o)
            if o["verdict"] == "FAIL":
                break
        if cache.planning:
            return out
        return _combine_bases(per_base, out, "untracked-path claim")

    if typ == "ConfinementAssumption":
        return _test_confinement(cfg, a, cache, out)

    if typ == "ConjunctionForeclosureAssumption":
        return _test_conjunction_foreclosure(cfg, a, cache, out)
    if typ == "SubconjunctionForeclosureAssumption":
        return _test_subconjunction_foreclosure(cfg, a, cache, out)

    return _test_declared_rest(cfg, a, cache, out, typ, batch)


def _independence_once(cfg, a, cache, out, ea, eb, da, db, sp, sd):
    """ONE base's verdict for an `IndependenceAssumption` — the shipped
    flip-A / flip-B / flip-both probe, verbatim, with the base handed in
    instead of picked (X12)."""
    if True:
        scen = (sd.get("concolic_scenario") or {}).get("name")
        # NAME BOUNDARY (2026-09-14): `sd` is a LOADED dump, so on a batch with a
        # `fix_len_names` canonicalize hook its `concolic_seeds` keys have been
        # rewritten to `SYM_LEN_X` -- which the Ruby runtime never reads. Launching
        # a probe from them silently drops the snapshot's whole length context.
        # `seeds_as_written` is the PRE-hook dict, i.e. what the runner was actually
        # handed. Identity when no canonicalize hook is installed.
        seeds = dict(seeds_as_written(sd))
        base = set(access_trace(sd))
        fa = flipped_seeds(sd, seeds, ea, da)
        fb = flipped_seeds(sd, seeds, eb, db)
        if fa is None or fb is None:
            out.update(verdict="NOT-TESTABLE", detail="cannot infer a flip value from the recorded PC")
            return out
        # X10 (2026-09-11): `flipped_seeds` WRITES its flip at the RUNTIME
        # (ordinal) key -- `rdim = _runtime_key(sd, dim)` -- because that is what
        # the runner seeds by. Reading it back at the CANONICAL key `db` is the
        # identity only when nothing is aliased, so on any endpoint that
        # canonicalizes ordinals this raised KeyError and NO independence pair
        # could ever be probed there. Read at the same key it was written at.
        fab = _combined_flip(sd, fa, fb, db)        # (shared helper, same lines)
        ra, rb, rab = (cache.run(x, scen, f"ind_{i}") for i, x in enumerate((fa, fb, fab)))
        if None in (ra, rb, rab):
            out.update(verdict="FAIL", detail="a flip probe produced no dump in the snapshot's scenario")
            return out
        # A flip that changed what an aliased ordinal RESOLVED TO makes the
        # probe's evidence about a different decision: NOT-COMPARABLE, never
        # PASS (2026-09-08; this is how 9 of 14 C7-A pairs once carried a PASS
        # earned on another reading).
        for tag_, r_ in (("flip-A", ra), ("flip-B", rb), ("flip-both", rab)):
            for e_ in (ea, eb):
                why = _reading_changed(sd, r_, e_)
                if why:
                    out.update(verdict="NOT-COMPARABLE", detail=f"{tag_}: {why}")
                    return out
        covered = base | set(trace_of(ra)) | set(trace_of(rb))
        novel = set(trace_of(rab)) - covered
        if novel:
            out.update(verdict="FAIL",
                       detail=f"combination (flip both) produced {len(novel)} target-call shape(s) "
                              f"absent from base/flip-A/flip-B: " +
                              "; ".join(f"{t} {n[:60]}" for t, n, _ in sorted(novel)[:3]))
        else:
            out.update(verdict="PASS", detail=f"no combination-only access shapes (snapshot {os.path.basename(sp)})")
        return out


def _untracked_once(cfg, a, cache, out, typ, e, d, sp, sd):
    """ONE base's verdict for an `UntrackedPathAssumption` /
    `OneSideUntrackedPathAssumption` — the shipped single-flip probe,
    verbatim, with the base handed in instead of picked (X12)."""
    if True:
        scen = (sd.get("concolic_scenario") or {}).get("name")
        # NAME BOUNDARY (2026-09-14): `sd` is a LOADED dump, so on a batch with a
        # `fix_len_names` canonicalize hook its `concolic_seeds` keys have been
        # rewritten to `SYM_LEN_X` -- which the Ruby runtime never reads. Launching
        # a probe from them silently drops the snapshot's whole length context.
        # `seeds_as_written` is the PRE-hook dict, i.e. what the runner was actually
        # handed. Identity when no canonicalize hook is installed.
        seeds = dict(seeds_as_written(sd))
        flipped = flipped_seeds(sd, seeds, e, d)
        if flipped is None:
            out.update(verdict="NOT-TESTABLE", detail="cannot infer a flip value from the recorded PC")
            return out
        r = cache.run(flipped, scen, "unt")
        if r is None:
            out.update(verdict="FAIL", detail="flip probe produced no dump in the snapshot's scenario")
            return out
        why = _reading_changed(sd, r, e)
        if why:
            out.update(verdict="NOT-COMPARABLE", detail=why)
            return out
        base, other = set(access_trace(sd)), set(trace_of(r))
        # Flipping the VARIABLE may route the run into a different region
        # where this PC is never evaluated (value-forced one-sided sites).
        # The claim is about THIS PC's other side: if the flipped run does
        # not record the expr at all, that side is unreachable — the
        # assumption holds by construction (PASS, annotated), and the
        # other region's shapes are not this assumption's business.
        if not recorded(r, e):
            out.update(verdict="PASS",
                       detail="flipping the variable leaves the PC unevaluated — the other side is unreachable by construction")
            return out
        if typ == "UntrackedPathAssumption":
            delta = base ^ other
            if delta:
                out.update(verdict="FAIL",
                           detail=f"flipping the branch changed {len(delta)} target-call shape(s) — "
                                  "the branch is NOT irrelevant to the access pattern")
            else:
                out.update(verdict="PASS", detail="access trace identical on both sides")
        else:
            # untracked side must add nothing beyond the tracked side. Which
            # side is the snapshot on? tracked_side names the outcome; the
            # snapshot's recorded polarity of expr tells us.
            taken = next((bool(ev.get("taken")) for ev in sd.get("events") or []
                          if ev.get("type") == "path_condition" and canon(ev.get("expr")) == canon(e)), None)
            tracked_taken = (a.get("tracked_side", "taken") == "taken")
            tracked, untracked = (base, other) if taken == tracked_taken else (other, base)
            novel = untracked - tracked
            if novel:
                out.update(verdict="FAIL",
                           detail=f"untracked side adds {len(novel)} target-call shape(s) the tracked side lacks")
            else:
                out.update(verdict="PASS", detail="untracked side adds no access shapes")
        return out


def _test_declared_rest(cfg, a, cache, out, typ, batch):
    """The derived tests X12 did not make multi-base: the alias test (which
    already reads the WHOLE corpus per canonical name) and the symbolic
    constraint test (whose base is picked by `pick_live_snapshot`, on the
    seed key the runtime reads, not by `pick_snapshot_with`)."""
    if typ in ("AliasAssumption", "DecisionAliasAssumption"):
        # the pre-rename type string is still accepted so the gate can be run
        # against a summary written before 2026-09-09.
        return _test_alias(cfg, a, cache, out)

    if typ == "SymbolicConstraintAssumption":
        # Claim: the region where z3_expr is FALSE does not exist (the
        # checker treats paths needing it as UNSAT). Test: seed the
        # constrained variable to a VIOLATING value, at the key the RUNTIME
        # reads, on the richest snapshot that HAS one, and replay. PASS if
        # the run adds no target-call shape beyond the snapshot's; FAIL if
        # the excluded region issues shapes of its own (the constraint hides
        # behaviour). No dump is ERROR, not PASS, and no live key is
        # NOT-TESTABLE (both 2026-09-12).
        z = canon(a.get("z3_expr", "")).strip()
        zz = _LENVAR_RE.sub(lambda mm: f"(LEN__{mm.group(1)} {mm.group(2)}", f"({z})", count=1)
        m = _CMP_RE.match(zz) if z else None
        dim = expr_dimension(f"({z})") if z else None
        lit = _parse_literal(m.group(3)) if m else None
        if not (m and dim and isinstance(lit, int) and not isinstance(lit, bool)):
            out.update(verdict="NOT-TESTABLE", detail=f"constraint not of the form VAR op INT: {z[:80]}")
            return out
        op = m.group(2)
        violating = {">=": lit - 1, ">": lit, "<=": lit + 1, "<": lit, "==": lit + 1, "!=": lit}[op]
        # Implied by the variable's DOMAIN? A list length is a concrete row
        # count (list.rb): low = 0 by construction; any dump may also declare
        # low/high on the var (engine SymbolicVar bounds). A violating value
        # outside the domain is not a run the app can make — PASS, and the
        # batch should state it as a variable bound rather than a constraint.
        # NAME BOUNDARY: `dim` may arrive in either spelling; `startswith`
        # on one of them silently dropped the implicit low=0 for the other.
        low, high = (0, None) if str(dim).startswith(("len(", "SYM_LEN_")) else (None, None)
        for p_, _sd, _s, _e in corpus_index(batch)[:50]:
            for sv in load_dump(p_).get("symbolic_vars") or []:
                # ...and `sv["name"]` is POST-hook (`SYM_LEN_`) while `dim` is
                # `len(`-spelled, so the declared low/high were never found.
                if same_variable(sv.get("name"), dim):
                    low = sv.get("low", low) if sv.get("low") is not None else low
                    high = sv.get("high", high) if sv.get("high") is not None else high
        if (low is not None and violating < low) or (high is not None and violating > high):
            out.update(verdict="PASS", detail=f"implied by the variable domain of {dim} (low={low}, high={high}); "
                       f"violating value {violating!r} is outside it — prefer declaring the bound over a constraint")
            return out
        # The probe must write the violating value at the key the RUNTIME
        # READS. Picking on `dim in seeds` matched CANONICAL-named dead knobs
        # and certified runs whose live length was never the violating value
        # (X10 class, 2026-09-12): no live key, no test.
        # X12 (2026-09-14): MANY bases, not one. "the run did not take the
        # seed" is a fact about the snapshot the probe was launched from.
        snaps = pick_live_snapshots(batch, dim)
        if not snaps:
            out.update(verdict="NOT-TESTABLE",
                       detail=("empty corpus" if not corpus_index(batch) else
                               f"no snapshot resolves {dim} to a seed key the runtime reads "
                               "(canonical-named dead knobs only) — seeding the violating value "
                               "there would change nothing, so this is untested, not held"))
            return out
        per_base = []
        for sp, sd, rkey in snaps:
            o = _symbolic_constraint_once(cfg, a, cache, {}, dim, violating, sp, sd, rkey)
            if cache.planning:
                continue
            o["base"] = os.path.basename(sp)
            per_base.append(o)
            if o["verdict"] == "FAIL":
                break
        if cache.planning:
            return out
        return _combine_bases(per_base, out, "symbolic constraint")

    out.update(verdict="NOT-TESTABLE", detail=f"no derived test for type {typ}")
    return out


def _symbolic_constraint_once(cfg, a, cache, out, dim, violating, sp, sd, rkey):
    """ONE base's verdict for a `SymbolicConstraintAssumption` — the shipped
    probe, verbatim, with the base handed in instead of picked (X12)."""
    if True:
        scen = (sd.get("concolic_scenario") or {}).get("name")
        # NAME BOUNDARY (2026-09-14): `sd` is a LOADED dump, so on a batch with a
        # `fix_len_names` canonicalize hook its `concolic_seeds` keys have been
        # rewritten to `SYM_LEN_X` -- which the Ruby runtime never reads. Launching
        # a probe from them silently drops the snapshot's whole length context.
        # `seeds_as_written` is the PRE-hook dict, i.e. what the runner was actually
        # handed. Identity when no canonicalize hook is installed.
        # `rkey` is already a RUNTIME key (`pick_live_snapshot` resolves it
        # through `_live_seed_key`), so it lands in the same namespace.
        seeds = dict(seeds_as_written(sd)); seeds[rkey] = violating
        r = cache.run(seeds, scen, "sc")
        if r is None:
            # NEVER a PASS. The runner writes a dump only for a NEW path
            # signature, and a dump written outside the directories we look
            # in is not found at all (see `_dump_dirs`) — in both cases the
            # violating value was not shown to be unrealizable, it was not
            # observed. Absent evidence is not evidence (2026-09-12).
            out.update(verdict="ERROR",
                       detail=f"probe for {dim}={violating!r} (runtime key {rkey}) produced no dump "
                              f"in scenario {scen!r}: no evidence either way — not a licence")
            return out
        # SEEDING IS NOT REALISING (2026-09-12). The seed is a request the
        # app may clamp, snap or ignore: under a mock that reads
        # `n = 0 if n.negative?; n = 4 if n > 1` a probe seeded 2 RUNS as a 4,
        # and the comparison below then turns on whether the snapshot happened
        # to be a 4 as well. Both outcomes are vacuous — a PASS certifies a
        # region the probe never entered, and a FAIL cites shapes the ALLOWED
        # value issues too. Decide nothing unless the run realised the value.
        rkey_p, minted = realised_value(r, dim, seed_key=rkey)
        if minted is ABSENT:
            out.update(verdict="NOT-TESTABLE",
                       detail=f"value not realised: seeded {violating!r}, minted <no value recorded> — "
                              f"the probe dump records no minted value for {dim} "
                              f"(runtime key {rkey_p!r}), so which region it ran in is unknown")
            return out
        if minted != violating:
            out.update(verdict="NOT-TESTABLE",
                       detail=f"value not realised: seeded {violating!r}, minted {minted!r} — the run did "
                              f"not take the seed on {dim} (clamped, snapped or ignored), so it never "
                              f"entered the excluded region; its shapes are evidence about "
                              f"{dim}={minted!r}, a value the constraint ALLOWS")
            return out
        novel = set(trace_of(r)) - set(access_trace(sd))
        if novel:
            out.update(verdict="FAIL", detail=f"the excluded region ({dim}={violating!r}) issues {len(novel)} target-call shape(s) the constraint hides: "
                       + "; ".join(f"{t} {n[:60]}" for t, n, _ in sorted(novel)[:3]))
        else:
            out.update(verdict="PASS", detail=f"excluded region ({dim}={violating!r}) adds no access shapes (snapshot {os.path.basename(sp)})")
        return out


def _alias_members(batch, canonical):
    """{(ordinal, statement key): [(path, seeds, scenario, len_value), ...]}
    — every (ordinal, statement) the corpus ever gave this canonical name."""
    members = {}
    seeds_of = {p: (sd, sc) for p, sd, sc, _e in corpus_index(batch)}
    for p, entries in (_ALIAS_INDEX.get(batch) or {}).items():
        for (o, c, key, lv) in entries:
            if c == canonical:
                sd, sc = seeds_of[p]
                members.setdefault((o, key), []).append((p, sd, sc, lv))
    return members


def _short(c):
    return c.split("__")[-1] if c else c


def _test_alias(cfg, a, cache, out):
    """Derived test for AliasAssumption, per CANONICAL name.

    Claim: every (ordinal, statement) the corpus mapped to this name is ONE
    decision. Two decisions are the same decision iff

    (i) they are the same STATEMENT — one statement key across all members.
        A ``key="loop"`` declaration says the opposite on purpose: the
        variants of one loop ARE several statements, so for that mode the
        key census is REPORTED (which statements were merged) and the weight
        of the test moves to (ii) and (iii);

    (ii) INTERVENING on them has the same effect: from a snapshot of each
        member at the same base length, setting the length to each other
        observed value adds the same statements, removes the same
        statements, with the same multiplicities, binds kept modulo the
        alias.  For a loop alias the members include the list's VARIANTS, so
        this is where "the same decision whichever variant produced the row"
        is actually tested;

    (iii) running the loop ONE MORE TIME makes the same decisions (a
        ``key="loop"`` claim only — a statement/shape declaration says nothing
        about iterations and is tested exactly as it was before this arm
        existed): a replay
        at ``k + 1`` rows must add and remove no target-call SHAPE (binds and
        literals wildcarded — the shape the policy consumer folds; see
        ``access_trace``). Multiplicity may change; the shape SET may not.
        When it does change but a replay at ``k + 2`` reproduces exactly the
        same delta, the identity holds from the second iteration on and the
        detail says NEEDS k=2 — still a FAIL for a declaration that claims
        k=1.

    PASS only on that evidence (a single-member name makes no cross-ordinal
    claim and says so, but still faces (iii)); FAIL when a key, an effect or
    a k+1 shape differs; NOT-TESTABLE when a member has no snapshot at the
    base length; NOT-COMPARABLE when a flip produced no run, or changed what
    the member's ordinal resolved to. A missing snapshot is never a PASS."""
    batch = cfg["batch_dir"]
    C = a.get("canonical") or ""
    mode = a.get("key", "statement")
    kk = max(1, int(a.get("k", 1)))
    out["expr"] = _short(C)
    members = _alias_members(batch, C)
    if not members:
        out.update(verdict="NOT-TESTABLE", detail="canonical name never produced by the CURRENT corpus")
        return out
    keys = {k for (_o, k) in members}
    ords = sorted({o.rsplit("_", 1)[1] for (o, _k) in members}, key=lambda x: int(x) if x.isdigit() else 0)
    part1 = merged = None
    if len(keys) > 1:
        census = " | ".join(sorted(k[:90] for k in keys))
        if mode == "loop":
            # declared on purpose: these are the variants of one loop.
            merged = f"(i) {len(keys)} statements merged as variants of one loop: {census}"
        else:
            part1 = f"(i) STATEMENT IDENTITY FAILS: {len(keys)} distinct statements under one name: {census}"
    if len(members) == 1 and mode != "loop":
        out.update(verdict="FAIL" if part1 else "PASS",
                   detail=part1 or f"single member (ordinal {ords[0]}): identity by statement key, "
                                   "no cross-ordinal claim to intervene on")
        return out
    # (ii) intervention effects per member; (iii) one more row than k
    lens = Counter(lv for cands in members.values() for (_p, _s, _sc, lv) in cands if lv is not None)
    if not lens:
        out.update(verdict="NOT-TESTABLE", detail=(part1 + "; " if part1 else "") + "no recorded length value")
        return out
    base = lens.most_common(1)[0][0]
    krow, krow2 = kk + 1, kk + 2
    flips = sorted(({v for v in lens} | {krow, krow2}) - {base})
    effects, kshapes, not_testable, not_comparable = {}, {}, [], []
    for (o, key), cands in sorted(members.items()):
        snaps = [c for c in cands if c[3] == base]
        tag = f"ord {o.rsplit('_', 1)[1]}"
        if not snaps:
            not_testable.append(f"{tag}: no snapshot at length {base}")
            continue
        p, seeds, scen, _lv = max(snaps, key=lambda c: len(c[1]))
        sd = load_dump(p)
        base_tr = Counter(access_trace_binds(sd))
        base_sh = set(access_trace(sd))
        eff, sh = {}, {}
        for v in flips:
            s2 = dict(seeds); s2[f"len({o}_rows)"] = v
            r = cache.run(s2, scen, f"alias_{v}")
            if cache.planning:
                continue
            if r is None:
                not_comparable.append(f"{tag} -> {v}: no run"); continue
            if r["amap"].get(o) != C:
                got = r["amap"].get(o)
                not_comparable.append(f"{tag} -> {v}: reading changed to "
                                      f"{_short(got) if got else 'absent'}"); continue
            pt = Counter(r["trace_b"])
            eff[v] = (tuple(sorted((pt - base_tr).items())), tuple(sorted((base_tr - pt).items())))
            rs = set(r["trace"])
            sh[v] = (tuple(sorted(rs - base_sh)), tuple(sorted(base_sh - rs)))
        effects[(o, key)] = (eff, os.path.basename(p))
        kshapes[(o, key)] = sh
    if cache.planning:
        return out
    detail = [x for x in (part1, merged) if x]
    distinct = {}
    for (o, key), (eff, snap) in effects.items():
        distinct.setdefault(json.dumps(eff, sort_keys=True, default=str), []).append((o.rsplit("_", 1)[1], snap))
    if len(distinct) > 1:
        groups = "; ".join(f"ordinals {[o for o, _ in v]}" for v in distinct.values())
        # name one differing shape
        effs = list(distinct)
        e0, e1 = json.loads(effs[0]), json.loads(effs[1])
        sample = ""
        for v in set(e0) | set(e1):
            a0, a1 = e0.get(v, [[], []]), e1.get(v, [[], []])
            if a0 != a1:
                s0 = {json.dumps(x) for x in a0[0] + a0[1]}; s1 = {json.dumps(x) for x in a1[0] + a1[1]}
                diff = sorted(s0 ^ s1)
                sample = f" e.g. length {v}: {diff[0][:140]}" if diff else ""
                break
        detail.append(f"(ii) INTERVENTION EFFECTS DIFFER across members: {groups}{sample}")
        out.update(verdict="FAIL", detail="; ".join(detail))
        return out
    if part1:
        out.update(verdict="FAIL", detail=part1 + f"; (ii) effects identical across {len(effects)} tested members")
        return out
    # (iii) one more row than k: the loop's extra iteration must add and
    # remove no target-call SHAPE. A delta that REPRODUCES itself at k+2 is
    # an identity that holds from iteration k+1 on — reported as NEEDS k=2,
    # and still a FAIL for a declaration that claims this k.
    moved = {o.rsplit("_", 1)[1]: sh[krow] for (o, _k), sh in kshapes.items()
             if mode == "loop" and krow in sh and any(sh[krow])}
    if moved:
        stable = all(kshapes[(o, k_)].get(krow2) == kshapes[(o, k_)].get(krow)
                     for (o, k_) in kshapes if o.rsplit("_", 1)[1] in moved)
        tag = f"NEEDS k={krow}" if stable else "FAILS"
        first = sorted(moved.items())[0]
        add, rem = first[1]
        detail.append(f"(iii) {tag}: at {krow} rows {len(moved)} member(s) change the target-call shape set"
                      f" (ord {first[0]}: +{len(add)} -{len(rem)}"
                      + (f", e.g. {str(add[0] if add else rem[0])[:120]}" if (add or rem) else "") + ")")
        out.update(verdict="FAIL", detail="; ".join(detail))
        return out
    if not_testable:
        out.update(verdict="NOT-TESTABLE", detail="; ".join(not_testable) + f" (base length {base})")
        return out
    if not_comparable:
        out.update(verdict="NOT-COMPARABLE", detail="; ".join(not_comparable))
        return out
    detail.append(f"(ii) {len(effects)} member(s) (ordinals {ords}) x flips {flips} from length {base}: "
                  "identical added/removed statement multisets")
    if mode == "loop":
        detail.append(f"(iii) pass at k={kk}: {krow} rows add and remove no target-call shape")
    if not merged:
        detail.insert(0, "(i) one statement")
    out.update(verdict="PASS", detail="; ".join(detail))
    return out


def run_declared(cfg, declared, keep=False, results_jsonl=None):
    """Test every declared assumption; dedupe identical (type, exprs).

    2026-09-12 (owner's checkpoint rule): the probe replays — the whole cost
    of this function — are checkpointed by ``ProbeCache`` when
    ``$ACHK_CHECKPOINT`` is set, and each verdict row is appended to
    ``results_jsonl`` (``$ACHK_RESULTS_JSONL``) as it is produced. Both are
    opt-in; with neither set this behaves exactly as before.
    """
    global _DECLARED_DIGEST
    # the index checkpoint's key: the declared set decides `_ALIASES`, which
    # decides how every dump is canonicalized at load.
    _DECLARED_DIGEST = _ckpt.digest(declared)
    global _DERIVE_CK
    if os.environ.get(DERIVE_CKPT_ENV):
        _DERIVE_CK = _ckpt.open_checkpoint(
            None, _phase_keys(cfg["batch_dir"], "profile_representatives"),
            env_var=DERIVE_CKPT_ENV)
    cache = ProbeCache(cfg, keep)
    rows_fh = None
    results_jsonl = results_jsonl or os.environ.get(RESULTS_JSONL_ENV)
    if results_jsonl:
        rows_fh = open(results_jsonl, "a", encoding="utf-8")
    # An Alias declaration is one claim per CANONICAL name the corpus
    # produced under it: expand so every name gets its own verdict row.
    expanded = []
    for a in declared:
        if a.get("type") in ("AliasAssumption", "DecisionAliasAssumption"):
            pat = re.compile(a.get("result_pattern") or "$^")
            corpus_index(cfg["batch_dir"])
            names = sorted({c for entries in (_ALIAS_INDEX.get(cfg["batch_dir"]) or {}).values()
                            for (o, c, _k, _l) in entries if pat.fullmatch(o or "")})
            if not names:
                expanded.append(dict(a, canonical=""))
            expanded.extend(dict(a, canonical=c) for c in names)
        else:
            expanded.append(a)
    declared = expanded
    seen, distinct = set(), []
    for a in declared:
        key = (a.get("type"), a.get("expr"), a.get("expr_a"), a.get("expr_b"), a.get("tracked_side"),
               a.get("z3_expr"), a.get("canonical"),
               # §16e: one class per (gate prefix, member) — two foreclosures
               # of the SAME member under different conjunctions are two
               # claims and must not collapse into one verdict row.
               a.get("prefix"))
        if key in seen:
            continue
        seen.add(key)
        distinct.append(a)
    # X12 (2026-09-14) — TWO STAGES, so multi-base costs what it has to and
    # no more. Stage 1 probes ONE base per assumption (the shipped cost) and
    # settles every FAIL: a refutation from the richest base is decisive and
    # needs no second opinion. Stage 2 escalates only the assumptions stage 1
    # could not refute — the PASSes, the NOT-TESTABLEs and the
    # NOT-COMPARABLEs — to `ACHK_BASES` bases, which is exactly where the
    # single-base blindness lives (§39: NOT-TESTABLE 24/24 -> FAIL 18).
    # Stage 2 re-derives base 1 as well; its probes are recalled from the
    # ProbeCache, so the repeat costs nothing.
    global _BASE_BUDGET
    stages = [1, _BASES] if _BASES > 1 else [1]
    pending, final = list(distinct), {}
    for si, budget in enumerate(stages):
        last = (si == len(stages) - 1)
        if not pending:
            break
        _BASE_BUDGET = budget
        label = f"stage {si + 1}/{len(stages)} ({budget} base(s))"
        # pass 1 (no runner launches): derive every probe the verdicts need
        cache.planning = True
        prog = _Progress(f"derive-probes {label}", len(pending))
        for a in pending:
            # X10: planning must never be ended by one assumption. A probe that
            # cannot even be DERIVED simply contributes no wanted key; its verdict
            # row is produced (as ERROR) by the verdict pass below.
            try:
                test_declared(cfg, a, cache)
            except Exception:
                pass
            prog.tick(note=f"{len(cache.wanted)} probe(s) wanted")
        prog.done(f"{len(cache.wanted)} probe(s) wanted")
        cache.planning = False
        print(f"  [{label}: {len(cache.wanted)} distinct probes needed "
              f"for {len(pending)} assumptions]", flush=True)
        cache.execute()
        prog = _Progress(f"verdicts {label}", len(pending))
        nxt = []
        for a in pending:
            # X10 (2026-09-11): one probe's exception is THAT probe's verdict, never
            # the end of the run. Before this, a single KeyError in one pair ended
            # all 83 of posts_show's and no results file was written at all -- the
            # suite reported nothing rather than reporting one bad row.
            try:
                r = test_declared(cfg, a, cache)
            except Exception as exc:
                r = {"type": a.get("type", ""), "expr": a.get("expr") or a.get("expr_a"),
                     "expr_b": a.get("expr_b"), "verdict": "ERROR",
                     "detail": f"{type(exc).__name__}: {exc}"[:300],
                     "bases_probed": 0, "bases_realising": 0, "bases_passing": 0,
                     "bases_failing": 0, "base_verdicts": []}
            r["bases_budget"] = budget
            final[id(a)] = r
            settled = last or r["verdict"] == "FAIL"
            if not settled:
                nxt.append(a)
            if settled and rows_fh is not None:
                rows_fh.write(json.dumps(r, default=str) + "\n")
                rows_fh.flush()
            if settled:
                print(f"  {r['verdict']:<13} {r['type']:<32} {str(r['expr'])[:70]}"
                      + (f" || {str(r['expr_b'])[:50]}" if r.get("expr_b") else ""))
                if r["detail"]:
                    print(f"      {r['detail'][:160]}")
            prog.tick()
        prog.done()
        pending = nxt
    _BASE_BUDGET = _BASES
    results = [final[id(a)] for a in distinct]
    cache.close()
    if _DERIVE_CK is not None:
        _DERIVE_CK.close()
        _DERIVE_CK = None
    if rows_fh is not None:
        rows_fh.close()
    return results


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: assumption_checker.py <manifest.json> [--scan-only] [--keep]")
    cfg = json.load(open(args[0]))
    scan_only = "--scan-only" in args
    keep = "--keep" in args
    declared = []
    if "--declared" in args:
        declared = json.load(open(args[args.index("--declared") + 1]))
        if isinstance(declared, dict):
            declared = declared.get("assumptions", [])
    global _CANON_FN, _ALIASES
    if cfg.get("canonicalize"):
        # "module:function" on batch_dir: rewrites a raw dump to canonical
        # (statement-identified) result names and returns the alias map —
        # the SAME rewrite the coverage report applied, so declared exprs
        # match dumps. Aliases come from the declared set (so a deliberately
        # different alias can be probed), else from the module's ALIASES.
        import importlib
        mod_name, fn_name = cfg["canonicalize"].split(":")
        sys.path.insert(0, cfg["batch_dir"])
        mod = importlib.import_module(mod_name)
        _CANON_FN = getattr(mod, fn_name)
        _ALIASES = [AliasAssumption(result_pattern=a.get("result_pattern", ""),
                                    key=a.get("key", "statement"),
                                    k=int(a.get("k", 1)))
                    for a in declared
                    if a.get("type") in ("AliasAssumption", "DecisionAliasAssumption")] \
            or list(getattr(mod, "ALIASES", []) or [])
        print(f"[canonicalize] {cfg['canonicalize']} with {len(_ALIASES)} alias(es): "
              + "; ".join(f"{x.result_pattern[:50]} by {x.key} (k={x.k})" for x in _ALIASES), flush=True)
    if "--declared" in args:
        # DERIVED mode: assumptions come from the coverage checker's
        # declared set (coverage_summary.json "assumptions" list); tests
        # derived per type — no manifest kinds.
        if "--limit" in args:
            declared = declared[:int(args[args.index("--limit") + 1])]
        print(f"== derived assumption tests: {len(declared)} declared ==")
        # X10: write the results file even if the run dies, so a crash leaves
        # evidence instead of nothing.
        results = []
        try:
            results = run_declared(cfg, declared, keep)
        finally:
            if "--json-out" in args:
                json.dump(results, open(args[args.index("--json-out") + 1], "w"), indent=2)
        bad = [r for r in results if r["verdict"] in ("FAIL", "ERROR")]
        nt = [r for r in results if r["verdict"] == "NOT-TESTABLE"]
        nc = [r for r in results if r["verdict"] == "NOT-COMPARABLE"]
        err = [r for r in results if r["verdict"] == "ERROR"]
        print(f"\nRESULT: {len(results)} distinct tested — PASS {len(results)-len(bad)-len(nt)-len(nc)}, "
              f"FAIL {len(bad)-len(err)}, ERROR {len(err)}, NOT-TESTABLE {len(nt)}, "
              f"NOT-COMPARABLE {len(nc)}")
        sys.exit(1 if bad else 0)

    failed = []
    for a in cfg["assumptions"]:
        name, dim, kind = a["name"], a["dimension"], a.get("kind", "independence")
        print(f"== {name} ({kind}) — dimension {dim} ==")

        bad = scan(cfg, dim)
        if bad:
            print(f"  SCAN: {len(bad)} corpus runs contradict the seeded dimension:")
            for b, expr, why in bad[:5]:
                print(f"    {b}: {expr} ({why})")
            failed.append(name)
        else:
            print("  SCAN: corpus consistent (tripwire clean)")
        if scan_only:
            print()
            continue

        snap = pick_snapshot(cfg["batch_dir"], dim, a.get("snapshot_scenario"))
        if snap is None:
            print("  PROBE: SKIP — no dump seeds this dimension")
            print()
            continue
        snap_path, snap_dump = snap
        seeds = dict(snap_dump["concolic_seeds"])
        seeds[dim] = flip_value(seeds[dim], a.get("flip_to"))
        scen = (snap_dump.get("concolic_scenario") or {}).get("name")
        print(f"  snapshot: {os.path.basename(snap_path)} (scenario {scen}); "
              f"flip {dim} -> {seeds[dim]!r}")

        probes = run_probe(cfg, name, seeds, keep, scenario=scen)
        probe = next((d for d in probes.values()
                      if (d.get("concolic_scenario") or {}).get("name") == scen), None)
        if probe is None:
            print(f"  PROBE: FAIL — no probe dump for scenario {scen} "
                  f"({len(probes)} dumps produced)")
            failed.append(name)
            print()
            continue

        s_pcs, s_notes = evidence(snap_dump, dim)
        p_pcs, p_notes = evidence(probe, dim)
        pc_diff = s_pcs ^ p_pcs
        note_diff = s_notes ^ p_notes

        if kind == "independence":
            ok = not pc_diff and not note_diff
            print(f"  PROBE: {'PASS' if ok else 'FAIL'} — evidence diff: "
                  f"{len(pc_diff)} PCs, {len(note_diff)} notes (must be 0/0)")
            if not ok:
                for e, t in sorted(pc_diff)[:5]:
                    print(f"    PC {'+' if (e, t) in p_pcs else '-'} {e[:100]} taken={t}")
                for n in sorted(note_diff)[:3]:
                    print(f"    NOTE ± {n[:100]}")
                failed.append(name)
        else:  # foreclosure
            diverged = bool(pc_diff or note_diff)
            expect = a.get("expect_pc_substring", "")
            all_probe_pcs = [str(ev.get("expr", "")) for ev in probe.get("events") or []
                             if ev.get("type") == "path_condition"]
            labeled = any(expect in e for e in all_probe_pcs) if expect else True
            ok = diverged and labeled
            print(f"  PROBE: {'PASS' if ok else 'FAIL'} — "
                  f"diverged={diverged} (dead knob if False), "
                  f"labeled={'yes' if labeled else 'NO — forced state leaks unlabeled'}")
            if not ok:
                failed.append(name)
        print()

    if failed:
        print(f"RESULT: RED — failed assumptions: {', '.join(dict.fromkeys(failed))}")
        print("(diagnose failed probes with the line-diff of the probe pair — CHECKS.md A3)")
    else:
        print("RESULT: all assumptions pass at the current evidence layer.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
