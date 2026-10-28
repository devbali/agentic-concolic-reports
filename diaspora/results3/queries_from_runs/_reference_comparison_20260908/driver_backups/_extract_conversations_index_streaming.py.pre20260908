#!/usr/bin/env python3
"""conversations_index extraction with INCREMENTAL dedup (results3-local driver).

Ported verbatim from _extract_posts_show_streaming.py (same corpus scale:
18,623 dumps); only the endpoint name, paths, and the POST-AUTH SCOPE header
emitted into the .sql differ. src/ untouched.

Why this exists: `queries_from_runs.dump.build_endpoint_file` accumulates
every TransformedQuery from every run before deduping (689,601 objects for
conversations_index's 18,688 dumps) — that list blew the 4.5G MemoryMax cgroup cap on
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

from queries_from_runs import subsume as subsume_mod            # noqa: E402
from queries_from_runs.dump import (                            # noqa: E402
    EndpointSummary, _load_run, _pc_shape, discover_param_pool,
)
from queries_from_runs.transform import RunTransformer          # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP_DIR = os.path.join(os.path.dirname(HERE), "conversations_index")
OUT_PATH = os.path.join(HERE, "conversations_index.sql")
SUMMARY_PATH = os.path.join(HERE, "_summary_conversations_index.json")


def main() -> int:
    json_paths = sorted(glob.glob(os.path.join(DUMP_DIR, "dump_*.json")))
    endpoint = "conversations_index"
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
            rt = RunTransformer(run, param_pool=param_pool)
            rq = rt.transform_all()
        except Exception as e:  # noqa: BLE001
            errors.append(f"{os.path.basename(path)}: {type(e).__name__}: {e}")
            continue
        errors.extend(f"{os.path.basename(path)}: {m}" for m in rq.errors)
        for expr in rq.skipped_pcs:
            skipped_pcs[_pc_shape(expr)] += 1
        for q in rq.queries:
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
        if q.placeholders:
            lines.append(
                "-- NOTE: unresolved symbolic binds kept as placeholders: "
                + ", ".join("_" + p for p in q.placeholders)
            )
        lines.append(q.sql.rstrip(";") + ";")
        lines.append("")
    if not final:
        lines = ["-- no SELECT queries recorded for this endpoint", ""]

    header = [
        "-- conversations_index — ConversationsController#index",
        "-- Extracted from the concolic corpus (results3/conversations_index):",
        f"--   {len(json_paths)} dumps, {n_runs} runs loaded, {n_raw} raw queries,",
        f"--   {len(deduped)} distinct, {n_dropped} subsumed, {len(final)} views.",
        "--",
        "-- SCOPE (Bali decision, 2026-08-31; DISCIPLINE §15): this endpoint's",
        "-- entrypoint is the POST-AUTH action with a SYMBOLIC principal. The",
        "-- authentication stages (principal SELECT by session/token, and the",
        "-- trackable / lastseenable / rememberable / lockable decisions and",
        "-- writes) run ABOVE the entrypoint and are NOT part of this file.",
        "--",
        "-- THE ENDPOINT'S COMPLETE POLICY IS THIS FILE **UNION** THE SHARED",
        "-- AUTH-BOUNDARY POLICY:",
        "--   reports/diaspora/results3/_auth_boundary/BOUNDARY_POLICY.md",
        "-- Consumers that need the whole request (boundary + action) must take",
        "-- the union; this file alone covers the action only.",
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
    print(f"{endpoint}: {summary.n_queries_final} queries "
          f"({summary.n_queries_deduped} distinct, {n_dropped} subsumed) "
          f"from {n_runs}/{len(json_paths)} dumps; subsume_ran={subsume_ran}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
