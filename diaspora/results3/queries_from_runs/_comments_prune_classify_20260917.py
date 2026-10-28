#!/usr/bin/env python3
"""comments_index prune-collapse re-derivation (2026-09-17).

Re-derives the 844 -> 50 PC-predicate collapse for comments_index directly
from the vanilla src/queries_from_runs pipeline (no results3-local patches),
sharded like _pcfold3_parallel.py so the full 26,528-dump corpus finishes in
a few minutes. Prints, per shape, which predicates the corpus renders and
which pcs.irrelevant_predicates drops -- the ground truth for the (a)/(b)/(c)
classification done by hand afterwards in
_COMMENTS_PRECISION_FIX_20260917.md.
"""
from __future__ import annotations

import dataclasses
import glob
import json
import os
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.path.insert(0, "/home/dev/project/src")
APP_CONFIG = "/home/dev/project/reports/diaspora/queries_config/app.json"
os.environ.setdefault("QFR_APP_CONFIG", APP_CONFIG)

from queries_from_runs import dump as dump_mod                      # noqa: E402
from queries_from_runs import app_config as app_config_mod          # noqa: E402
from queries_from_runs import pcs as pcs_mod                        # noqa: E402
from queries_from_runs.endpoint_params import discover_param_pool   # noqa: E402
from queries_from_runs.transform import TransformedQuery            # noqa: E402

DUMPDIR = "/home/dev/project/reports/diaspora/results3/comments_index"
CAP = 2
SHARDS = 8
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_JSON = os.path.join(HERE, "_comments_prune_classify_20260917.json")


def _shard_worker(args):
    paths, param_pool = args
    cfg = app_config_mod.load_cached(APP_CONFIG)
    extraction = dump_mod.extract_statements(
        paths, param_pool=param_pool, app_config=cfg,
        exclude_rejected=True, two_query_cap=CAP,
        mark_unreliable_witnesses=True,
    )
    return {
        "queries": [dataclasses.asdict(qy) for qy in extraction.queries],
        "n_runs": extraction.n_runs,
        "n_raw": extraction.n_raw,
        "n_rejected": extraction.n_rejected,
    }


def _chunks(seq, n):
    k = max(1, -(-len(seq) // n))
    return [seq[i:i + k] for i in range(0, len(seq), k)]


def main():
    all_paths = sorted(glob.glob(os.path.join(DUMPDIR, "dump_*.json")))
    print(f"corpus size: {len(all_paths)}", flush=True)
    param_pool = discover_param_pool(all_paths)
    shards = _chunks(all_paths, SHARDS)

    merged = {}
    n_runs = n_raw = n_rejected = 0
    with ProcessPoolExecutor(max_workers=SHARDS) as ex:
        futs = {ex.submit(_shard_worker, (shard, param_pool)): i
                for i, shard in enumerate(shards)}
        for fut in as_completed(futs):
            i = futs[fut]
            r = fut.result()
            n_runs += r["n_runs"]
            n_raw += r["n_raw"]
            n_rejected += r["n_rejected"]
            for qd in r["queries"]:
                qy = TransformedQuery(**{**qd, "pc_preds": tuple(qd["pc_preds"]),
                                          "flags": tuple(qd["flags"]),
                                          "placeholders": tuple(qd["placeholders"])})
                key = (qy.shape, qy.pc_preds)
                existing = merged.get(key)
                if existing is None:
                    merged[key] = qy
                elif qy.reliable_witness and not existing.reliable_witness:
                    merged[key] = dataclasses.replace(existing, reliable_witness=True)
            print(f"shard {i} done: {r['n_runs']} runs, "
                  f"{len(r['queries'])} raw queries -> {len(merged)} distinct so far",
                  flush=True)

    queries = list(merged.values())
    n_preds_before = sum(len(qy.pc_preds) for qy in queries)
    print(f"\nEXTRACTION DONE: {len(all_paths)} dumps, {n_runs} runs, {n_raw} raw, "
          f"{n_rejected} rejected, {len(queries)} distinct (shape,preds), "
          f"{n_preds_before} PC predicates rendered", flush=True)

    irrelevant = pcs_mod.irrelevant_predicates(
        (qy.shape, qy.pc_preds) for qy in queries)
    irrelevant_reliable = pcs_mod.irrelevant_predicates_reliable(
        (qy.shape, qy.pc_preds, qy.reliable_witness) for qy in queries)

    per_shape = {}
    for qy in queries:
        per_shape.setdefault(qy.shape, []).append(qy)

    n_preds_after_base = 0
    n_preds_after_fix = 0
    dropped_pred_shape_counts = Counter()
    dropped_detail = []   # (shape, pred, kept_reliable?)
    for shape, qys in per_shape.items():
        drop_base = irrelevant[shape]
        drop_fix = irrelevant_reliable[shape]
        for qy in qys:
            kept_base = set(qy.pc_preds) - drop_base
            kept_fix = set(qy.pc_preds) - drop_fix
            n_preds_after_base += len(kept_base)
            n_preds_after_fix += len(kept_fix)
            for p in set(qy.pc_preds) - kept_base:
                dropped_pred_shape_counts[dump_mod._pc_shape(p)] += 1
                dropped_detail.append({
                    "shape": shape, "pred": p,
                    "n_observations_of_shape": len(qys),
                    "reliable_witness_exists": any(q.reliable_witness for q in qys),
                    "recovered_by_reliable_fix": p in drop_base and p not in drop_fix,
                })

    print(f"\n=== dedup-by-SQL predicate totals (matches dump.py's n_preds_after) ===")
    seen_sql_base = {}
    for shape, qys in per_shape.items():
        drop = irrelevant[shape]
        for qy in qys:
            kept = tuple(sorted(set(qy.pc_preds) - drop))
            seen_sql_base.setdefault((shape, kept), kept)
    total_after_dedup = sum(len(v) for v in seen_sql_base.values())
    print(f"  base rule:    {n_preds_before} rendered -> {total_after_dedup} kept "
          f"(pre-sql-dedup sum was {n_preds_after_base})")

    n_single = sum(1 for v in per_shape.values() if len(v) == 1)
    n_multi = sum(1 for v in per_shape.values() if len(v) > 1)
    print(f"\n  distinct shapes: {len(per_shape)} ({n_single} observed once, "
          f"{n_multi} observed >1 time)")
    n_dropped_total = sum(dropped_pred_shape_counts.values())
    n_recovered_by_fix = sum(1 for d in dropped_detail if d["recovered_by_reliable_fix"])
    print(f"  dropped (shape,pred) instances: {n_dropped_total}")
    print(f"  of those, recovered by --reliable-pruning-witnesses: {n_recovered_by_fix}")

    print(f"\n=== top dropped predicate SHAPES (regex-normalized) ===")
    for shape_txt, n in dropped_pred_shape_counts.most_common(40):
        print(f"  {n:5d}  {shape_txt}")

    with open(OUT_JSON, "w") as f:
        json.dump({
            "n_dumps": len(all_paths), "n_runs": n_runs, "n_raw": n_raw,
            "n_rejected": n_rejected,
            "n_distinct_shape_preds": len(queries),
            "n_preds_before": n_preds_before,
            "n_preds_after_base": total_after_dedup,
            "n_shapes": len(per_shape),
            "n_shapes_single_obs": n_single,
            "n_shapes_multi_obs": n_multi,
            "n_dropped_total": n_dropped_total,
            "n_recovered_by_reliable_fix": n_recovered_by_fix,
            "dropped_pred_shape_counts": dropped_pred_shape_counts.most_common(),
            "dropped_detail_sample": dropped_detail[:500],
        }, f, indent=1)
    print(f"\nwrote {OUT_JSON}")


if __name__ == "__main__":
    main()
