#!/usr/bin/env python3
"""comments_index extraction with INCREMENTAL dedup (results3-local driver).

Ported verbatim from _extract_posts_show_streaming.py (same corpus scale:
18,623 dumps); only the endpoint name, paths, and the POST-AUTH SCOPE header
emitted into the .sql differ. src/ untouched.

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
from collections import Counter

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

# THE PATCHED FOLD IS MANDATORY FOR THIS CORPUS (cycle 12, measured).
# `skipped_pcs_audit` on the cycle-12 corpus:
#     vanilla src/ fold      -> parsed 575447 | DROPPED 73461  -> RED
#     variant_d assoc_fold   -> parsed 575447 | dropped 0      -> pass
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
DUMP_DIR = os.path.join(os.path.dirname(HERE), "comments_index")
OUT_PATH = os.path.join(HERE, "comments_index.sql")
SUMMARY_PATH = os.path.join(HERE, "_summary_comments_index.json")
if BLOCKAID_NORMALISE:
    OUT_PATH = os.path.join(HERE, "_rewritten", "comments_index.blockaid.sql")
    SUMMARY_PATH = os.path.join(HERE, "_rewritten", "_summary_comments_index.blockaid.json")


def main() -> int:
    json_paths = sorted(glob.glob(os.path.join(DUMP_DIR, "dump_*.json")))
    endpoint = "comments_index"
    param_pool = discover_param_pool(list(json_paths))

    errors = []
    flags = Counter()
    skipped_pcs = Counter()
    placeholders = set()

    seen = {}           # sql -> first TransformedQuery (incremental dedup)
    n_raw = 0
    n_runs = 0
    for i, path in enumerate(json_paths):
        run = _load_run(path)
        if run is None:
            continue
        n_runs += 1
        try:
            rt = (BF.Transformer if BLOCKAID_NORMALISE else AssocFoldingTransformer)(run, param_pool=param_pool)
            rq = rt.transform_all()
        except Exception as e:  # noqa: BLE001
            errors.append(f"{os.path.basename(path)}: {type(e).__name__}: {e}")
            continue
        errors.extend(f"{os.path.basename(path)}: {m}" for m in rq.errors)
        for expr in rq.skipped_pcs:
            skipped_pcs[_pc_shape(expr)] += 1
        for q in ([q2 for q0 in rq.queries for q2 in BF.finalize(q0)] if BLOCKAID_NORMALISE else rq.queries):
            n_raw += 1
            for f in q.flags:
                flags[f] += 1
            placeholders.update(q.placeholders)
            if q.sql not in seen:
                seen[q.sql] = q
        if (i + 1) % 2000 == 0:
            print(f"  {i + 1}/{len(json_paths)} dumps, {len(seen)} distinct",
                  flush=True)

    deduped = sorted(seen.values(), key=lambda q: (-q.n_tables, q.sql))

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
    HEADER_SRC = os.path.join(os.path.dirname(HERE), "comments_index",
                              "POLICY_HEADER.txt")
    header = open(HEADER_SRC).read().rstrip("\n").split("\n")
    header += [
        "--",
        "-- EXTRACTION PROVENANCE",
        f"--   corpus  : results3/comments_index, {len(json_paths)} dumps, {n_runs} runs loaded",
        f"--   queries : {n_raw} raw -> {len(deduped)} distinct -> {n_dropped} subsumed -> {len(final)} views",
        *(["--   normalised : _blockaid_fold E1-E11 (2026-09-08) — every statement is blockaid-consumable;",
           "--                this file is the NORMALISED variant, not the canonical policy"] if BLOCKAID_NORMALISE else []),
        "--   fold    : _experiment/variant_d AssocFoldingTransformer (mandatory —",
        "--             the vanilla src/ fold drops 73 461 `(VAR == VAR(_))` PCs",
        "--             on this corpus; measured by skipped_pcs_audit both ways)",
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
