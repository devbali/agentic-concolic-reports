#!/usr/bin/env python3
"""posts_show extraction with INCREMENTAL dedup, PARALLEL scan (results3-local driver).

P35 2026-09-15: ported from `_c30_extract_par.py` (notifications' parallel
extractor, validated there at 4.3x) by substituting the endpoint name, paths
and header source, and restoring the OUT_SQL/OUT_SUMMARY overrides that
`_extract_posts_show_streaming.py` carried. The scan body, the E1
AssocFoldingTransformer, the E11 RED check on unparseable notes and the
patched fold are UNCHANGED. src/ untouched.

Ported from `_extract_comments_index_streaming.py` (2026-09-10) — the most
recent extractor, and the one that already carries the E1 fix
(`AssocFoldingTransformer`, not `assoc_fold.install()` alone) and the E11 RED
check on unparseable notes. Only the endpoint name, the paths, the header
source and the DUMP_LIST knob differ. src/ untouched.

DUMP_LIST (new here): this corpus is 150 000+ dumps and a drive may be adding
to it, so the extraction takes the SAME fixed snapshot list the coverage pass
measured. Without it the glob is used, exactly as before.

Why this exists: `queries_from_runs.dump.build_endpoint_file` accumulates
every TransformedQuery from every run before deduping (689,601 objects for
conversations_index's 18,688 dumps at the time) — that list blew the 4.5G MemoryMax cap on
the 2026-08-19 re-run (and is the same load pattern behind the 2026-08-18
kernel OOM kills). This driver replicates build_endpoint_file exactly, but
dedups by SQL string as it streams, so memory stays at the per-dump scale.
Output (.sql file + summary JSON) is byte-identical in content to dump.py's:
dedup keeps the FIRST TransformedQuery per SQL string in both versions, and
flag/placeholder/skipped-PC counters are accumulated pre-dedup in both.
src/ is untouched (source-code discipline).
"""
import dataclasses
import glob
import json
import os
import sys
import time
from collections import Counter
from multiprocessing import Pool

sys.path.insert(0, "/home/dev/project/src")
# App-specific input for src/queries_from_runs (E12, 2026-09-11): the
# package is app-agnostic and REQUIRES an app config (schema, FKs,
# principal/identity conventions, symbol-name shapes, inflections).
# Set before ANY queries_from_runs import that reads it at module level.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
# 2026-09-08: OPT-IN blockaid-consumable output (BLOCKAID_NORMALISE=1) — results3-local
# normaliser _blockaid_fold.py (E1-E11), src/ untouched.  When the variable is unset this
# driver behaves exactly as before and writes the canonical <endpoint>.sql; when set it
# writes _rewritten/<endpoint>.blockaid.sql instead and NEVER touches the canonical file.
BLOCKAID_NORMALISE = os.environ.get("BLOCKAID_NORMALISE") == "1"
if BLOCKAID_NORMALISE:
    sys.path.insert(0, "/home/dev/project/reports/diaspora/results3/_experiment/variant_d")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import _blockaid_fold as BF                                  # noqa: E402
    BF.install()

# THE PATCHED FOLD IS MANDATORY (RUNBOOK 2026-09-01: run skipped_pcs_audit
# BOTH ways before any extraction; if they differ the extractor MUST install
# variant_d's assoc_fold). Measured on comments_index's cycle-12 corpus:
#     vanilla src/ fold      -> parsed 575447 | DROPPED 73461  -> RED
#     variant_d assoc_fold   -> parsed 575447 | dropped 0      -> pass
# posts_show records the same PC shape (violation 8, the
# `StringVal('...')` string-equality family, incl. the STI `type` decision),
# so the same fold is installed here and `_c7_audits.sh` runs the audit both
# ways on THIS corpus.
# The dropped shape is `(VAR == VAR(_))` — the StringVal equality branches,
# i.e. every `users.language == 'pl'` / `posts.type == 'Photo'` decision this
# endpoint records. Extracting without the patch would silently drop 73 461
# recorded constraints from the policy, so the fold is installed here exactly
# as `skipped_pcs_audit --patched` installs it. (RUNBOOK gap 3: the patches are
# not upstreamed into src/.)
sys.path.insert(0, "/home/dev/project/reports/diaspora/results3/_experiment/variant_d")
import assoc_fold                                               # noqa: E402
assoc_fold.install()
# E1 (2026-09-09): install() ONLY monkeypatches _Build._bind_value and
# pcs.parse_pc — it does NOT swap the transformer. Using the base
# RunTransformer left every `assoc_*` bind UNRESOLVED as a placeholder
# (measured on people_show: 6 placeholder families vs 3, and the 3 that
# disappear are assoc_author_id / assoc_person_id / assoc_profile_id, folded
# into real joins). Those placeholders are also why blockaid quarantined most
# of the views. The folding transformer is the one to use.
from assoc_fold import AssocFoldingTransformer                   # noqa: E402

from queries_from_runs import subsume as subsume_mod            # noqa: E402
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
from queries_from_runs.dump import (                            # noqa: E402
    EndpointSummary, _load_run, _pc_shape, discover_param_pool,
)
from queries_from_runs.transform import RunTransformer          # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP_DIR = os.path.join(os.path.dirname(HERE), "posts_show")
OUT_PATH = os.environ.get("OUT_SQL") or os.path.join(HERE, "posts_show.sql")
SUMMARY_PATH = os.environ.get("OUT_SUMMARY") or os.path.join(HERE, "_summary_posts_show.json")
if BLOCKAID_NORMALISE:
    OUT_PATH = os.path.join(HERE, "_rewritten", "posts_show.blockaid.sql")
    SUMMARY_PATH = os.path.join(HERE, "_rewritten", "_summary_posts_show.blockaid.json")


class _Q:
    """The four fields of a TransformedQuery that survive the process
    boundary — the only four anything downstream of the scan reads."""
    __slots__ = ("sql", "flags", "placeholders", "n_tables")

    def __init__(self, sql, flags, placeholders, n_tables):
        self.sql = sql
        self.flags = flags
        self.placeholders = placeholders
        self.n_tables = n_tables


_PARAM_POOL = None


def _init_worker(pp):
    global _PARAM_POOL
    _PARAM_POOL = pp


def _scan_chunk(paths):
    """One shard of the dump scan. Returns exactly what the serial loop would
    have accumulated over these paths, first-seen-within-chunk for `seen`."""
    seen = {}
    n_raw = n_runs = 0
    errors = []
    flags = Counter()
    skipped = Counter()
    ph = set()
    for path in paths:
        run = _load_run(path)
        if run is None:
            continue
        n_runs += 1
        try:
            rt = (BF.Transformer if BLOCKAID_NORMALISE
                  else AssocFoldingTransformer)(run, param_pool=_PARAM_POOL)
            rq = rt.transform_all()
        except Exception as e:  # noqa: BLE001
            errors.append(f"{os.path.basename(path)}: {type(e).__name__}: {e}")
            continue
        errors.extend(f"{os.path.basename(path)}: {m}" for m in rq.errors)
        for expr in rq.skipped_pcs:
            skipped[_pc_shape(expr)] += 1
        for q in ([q2 for q0 in rq.queries for q2 in BF.finalize(q0)]
                  if BLOCKAID_NORMALISE else rq.queries):
            n_raw += 1
            for f in q.flags:
                flags[f] += 1
            ph.update(q.placeholders)
            if q.sql not in seen:
                seen[q.sql] = (tuple(q.flags), tuple(q.placeholders), q.n_tables)
    return n_runs, n_raw, seen, flags, skipped, ph, errors


def main() -> int:
    _dl = os.environ.get("DUMP_LIST")
    if _dl:
        json_paths = sorted(l.strip() for l in open(_dl) if l.strip())
        json_paths = [p if os.path.isabs(p) else os.path.join(DUMP_DIR, p)
                      for p in json_paths]
        print(f"DUMP_LIST {_dl}: {len(json_paths)} dumps (fixed snapshot)", flush=True)
    else:
        json_paths = sorted(glob.glob(os.path.join(DUMP_DIR, "dump_*.json")))
    endpoint = "posts_show"
    param_pool = discover_param_pool(list(json_paths))

    errors = []
    flags = Counter()
    skipped_pcs = Counter()
    placeholders = set()

    # ---- PARALLEL SCAN (C30, 2026-09-15) --------------------------------
    # The serial loop measured 2 h 58 m over 138 912 dumps at 96 % of ONE
    # core on a 16-core box, and the solver stage needs the WHOLE deduped
    # list with its flags, so a second extraction would have paid it again.
    # The loop is per-dump and shares nothing but the param pool, so it is
    # sharded HERE, at the driver — no threading or batching is added to
    # `src/`, which is a standing rule.
    #
    # DETERMINISM, checked rather than hoped for: the serial version keeps
    # the FIRST-seen TransformedQuery per distinct SQL, and `flags` /
    # `placeholders` are per-instance, so "first" has to mean the same thing.
    # Chunks are consumed with `imap` IN ORDER and merged in order, and a
    # chunk's own dict is first-seen within the chunk, so the surviving
    # record for every SQL is the globally first one — byte-identically the
    # serial answer. `errors` is likewise appended in chunk order.
    #
    # Only four fields of the query survive the process boundary because
    # only four are ever read downstream (sql, flags, placeholders,
    # n_tables): emission uses sql/flags/placeholders, the sort uses
    # n_tables, and eligible/can_subsume use flags/placeholders.
    workers = int(os.environ.get("EXTRACT_WORKERS", "6"))
    chunk = int(os.environ.get("EXTRACT_CHUNK", "500"))
    chunks = [json_paths[i:i + chunk] for i in range(0, len(json_paths), chunk)]
    print(f"[parallel] {workers} workers over {len(chunks)} chunks of {chunk} "
          f"(EXTRACT_WORKERS / EXTRACT_CHUNK)", flush=True)
    seen = {}           # sql -> _Q, first occurrence in json_paths order
    n_raw = 0
    n_runs = 0
    done = 0
    t0 = time.time()
    with Pool(workers, initializer=_init_worker, initargs=(param_pool,)) as pool:
        for (c_runs, c_raw, c_seen, c_flags, c_skipped,
             c_ph, c_errors) in pool.imap(_scan_chunk, chunks):
            n_runs += c_runs
            n_raw += c_raw
            flags.update(c_flags)
            skipped_pcs.update(c_skipped)
            placeholders.update(c_ph)
            errors.extend(c_errors)
            for sql, rec in c_seen.items():
                if sql not in seen:
                    seen[sql] = _Q(sql, rec[0], rec[1], rec[2])
            done += 1
            if done % 40 == 0:
                print(f"  {min(done * chunk, len(json_paths))}/{len(json_paths)} "
                      f"dumps, {len(seen)} distinct, {time.time() - t0:.0f}s",
                      flush=True)
    print(f"[parallel] scan done in {time.time() - t0:.0f}s: {n_runs} runs, "
          f"{n_raw} raw queries, {len(seen)} distinct", flush=True)

    deduped = sorted(seen.values(), key=lambda q: (-q.n_tables, q.sql))
    if os.environ.get("QUERIES_OUT"):
        with open(os.environ["QUERIES_OUT"], "w") as f:
            json.dump([{"sql": q.sql, "flags": list(q.flags),
                        "placeholders": list(q.placeholders),
                        "n_tables": q.n_tables} for q in deduped], f)
        print(f"[parallel] wrote {os.environ['QUERIES_OUT']} "
              f"({len(deduped)} deduped queries with their flags)", flush=True)

    # -- subsumption prune (verbatim from build_endpoint_file) ----------
    n_dropped = 0
    subsume_errors = {}
    subsume_ran = False
    final = deduped
    if len(deduped) > 1:
        sqls = [q.sql for q in deduped]
        eligible = [
            not q.placeholders and "type-mismatched-join" not in q.flags
            for q in deduped
        ]
        can_subsume = [
            "finder-without-where" not in q.flags and "unscoped" not in q.flags
            and not any(f.startswith("broadened-") for f in q.flags)
            for q in deduped
        ]
        try:
            # SKIP_SUBSUME=1 (2026-09-11, coordinator): the solver stage forks a
            # blockaid JVM, and while the box is short of memory no JVM may run
            # except through the caged, `free -g`-gated wrapper, ONE at a time.
            # With the knob set, the FREE SYNTACTIC stage still runs in-process
            # (it is a conjunct-subset test, no solver), and the summary records
            # that the solver stage did NOT run, so the two are never conflated.
            if os.environ.get("SKIP_SUBSUME") == "1":
                # P35 2026-09-15: the inherited notifications driver runs the
                # FREE syntactic stage here even under SKIP_SUBSUME=1, and it
                # DROPS statements (2 on a 6 000-dump posts_show sample).
                # posts_show's own serial extractor does not. That is a POLICY
                # difference, and it must not ride along with a performance
                # port -- the parallel scan is supposed to be a speed change and
                # nothing else. SYNTACTIC_UNDER_SKIP=1 restores the inherited
                # behaviour; the DEFAULT reproduces the serial extractor, which
                # is what the serial-vs-parallel differential is compared on.
                if os.environ.get("SYNTACTIC_UNDER_SKIP") == "1":
                    syn_pairs = subsume_mod.syntactic_subsumed_pairs(sqls, can_subsume)
                    dropped = subsume_mod._drop_from_pairs(syn_pairs, set())
                    survivors = [i for i in range(len(sqls)) if i not in dropped]
                    subsume_errors = {}
                    final = [deduped[i] for i in survivors]
                    n_dropped = len(deduped) - len(final)
                    subsume_ran = False
                    print(f"SKIP_SUBSUME=1: syntactic stage only — {len(syn_pairs)} "
                          f"syntactic pairs, {n_dropped} dropped, solver stage NOT run",
                          flush=True)
                else:
                    final = list(deduped)
                    survivors = list(range(len(sqls)))
                    subsume_errors = {}
                    n_dropped = 0
                    subsume_ran = False
                    print("SKIP_SUBSUME=1: scan only — syntactic stage SUPPRESSED "
                          "to match the serial extractor (SYNTACTIC_UNDER_SKIP=1 "
                          "restores it); solver stage NOT run", flush=True)
            else:
                survivors, _pairs, subsume_errors = subsume_mod.prune_subsumed(
                    sqls, eligible=eligible, can_subsume=can_subsume,
                    checker=subsume_mod.DEFAULT_CHECKER,
                )
                final = [deduped[i] for i in survivors]
                n_dropped = len(deduped) - len(final)
                subsume_ran = True
        except Exception as e:  # noqa: BLE001
            errors.append(f"subsumption check failed: {type(e).__name__}: {e}")

    # -- emit (verbatim from build_endpoint_file) -----------------------
    lines = []
    for q in final:
        if "finder-without-where" in q.flags:
            lines.append(
                "-- NOTE: finder mock rendered without its WHERE conditions; "
                "query is broader than the app's real query"
            )
        if "type-mismatched-join" in q.flags:
            lines.append(
                "-- NOTE: join compares columns of different types, as recorded "
                "by the runtime (known result-var naming bug)"
            )
        _bf_notes = {
            "count-as-pk": "COUNT(*) rendered as the pk of every FROM table (blockaid StripCountStar convention)",
            "sum-as-pk-col": "SUM(col) rendered as pk + col (blockaid convention)",
            "left-join-split": "LEFT OUTER JOIN with an OR arm split into its two arms (set semantics)",
            "left-as-inner": "LEFT OUTER JOIN rendered INNER (FK-backed)",
            "literal-principal": "concrete principal id of this corpus read as _MY_UID (POLICY_HEADER F6)",
        }
        for f in sorted(q.flags):
            if f.startswith("broadened-bind:"):
                lines.append("-- NOTE: bind " + f.split(":", 1)[1] + " has no SQL form; its predicate is BROADENED away (statement is wider than the app's)")
            elif f.startswith("broadened-param:"):
                lines.append("-- NOTE: request-param bind " + f.split(":", 1)[1] + " broadened away")
            elif f in _bf_notes:
                lines.append("-- NOTE: " + _bf_notes[f])
        if q.placeholders:
            lines.append(
                "-- NOTE: unresolved symbolic binds kept as placeholders: "
                + ", ".join("_" + p for p in q.placeholders)
            )
        lines.append(q.sql.rstrip(";") + ";")
        lines.append("")
    if not final:
        lines = ["-- no SELECT queries recorded for this endpoint", ""]

    # The canonical header is maintained by the batch and re-applied verbatim
    # by every extraction (M-17: under resolution (b) the declaration IS the
    # safeguard, so it must live in the artifact, not in a report).
    HEADER_SRC = os.path.join(os.path.dirname(HERE), "posts_show",
                              "POLICY_HEADER.txt")
    header = open(HEADER_SRC).read().rstrip("\n").split("\n")
    header += [
        "--",
        "-- EXTRACTION PROVENANCE",
        f"--   corpus  : results3/posts_show, {len(json_paths)} dumps, {n_runs} runs loaded",
        f"--   queries : {n_raw} raw -> {len(deduped)} distinct -> {n_dropped} subsumed -> {len(final)} views",
        *(["--   normalised : _blockaid_fold E1-E11 (2026-09-08) — every statement is blockaid-consumable;",
           "--                this file is the NORMALISED variant, not the canonical policy"] if BLOCKAID_NORMALISE else []),
        "--   fold    : _experiment/variant_d AssocFoldingTransformer (mandatory —",
        "--             the vanilla src/ fold drops every `(VAR == VAR(_))` /",
        "--             StringVal equality PC; measured by skipped_pcs_audit BOTH",
        "--             ways on this corpus, see _c7_audits.log)",
        "--",
        "",
    ]
    with open(OUT_PATH, "w") as f:
        f.write("\n".join(header + lines))

    summary = EndpointSummary(
        endpoint=endpoint,
        out_path=OUT_PATH,
        n_dumps=len(json_paths),
        n_runs_loaded=n_runs,
        n_queries_raw=n_raw,
        n_queries_deduped=len(deduped),
        n_queries_final=len(final),
        n_subsumed_dropped=n_dropped,
        placeholders=tuple(sorted(placeholders)),
        flags=dict(flags),
        skipped_pc_shapes=dict(skipped_pcs.most_common()),
        errors=errors,
        subsume_errors=subsume_errors,
        subsume_ran=subsume_ran,
    )
    with open(SUMMARY_PATH, "w") as f:
        json.dump({endpoint: dataclasses.asdict(summary)}, f, indent=1)
    # CHECK (E11, 2026-09-09): an unparseable note means a statement the app
    # REALLY ISSUED was dropped from this policy. That must be RED, not a
    # summary field — E11 hid will_paginate's pagination COUNT behind 21,037
    # such errors on conversations_index, and nothing failed. RUNBOOK rule P:
    # residue found later means the CHECK was missing too.
    _unparseable = [e for e in errors if "unparseable note" in e]
    if _unparseable:
        import collections as _c
        _by = _c.Counter(e.split("unparseable note on ", 1)[-1].split(":", 1)[0]
                         for e in _unparseable)
        print(f"\n*** RED: {len(_unparseable)} UNPARSEABLE NOTES — statements the app "
              f"issued are MISSING from this policy ***")
        for _name, _n in _by.most_common(8):
            print(f"      {_n:7d}  {_name}")
        print("      Fix the note parser (src/queries_from_runs/transform.py "
              "_primary_table / _split_limit) before trusting this file.\n")

    print(f"{endpoint}: {summary.n_queries_final} queries "
          f"({summary.n_queries_deduped} distinct, {n_dropped} subsumed) "
          f"from {n_runs}/{len(json_paths)} dumps; subsume_ran={subsume_ran}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
