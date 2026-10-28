#!/usr/bin/env python3
"""pcfold3 — full-corpus regeneration with --reliable-pruning-witnesses,
sharded across processes so a 300k-dump endpoint finishes in reasonable time.

src/ is UNCHANGED by this script: it only calls the public pipeline functions
(extract_statements / prune_conditions / drop_subsumed / render_policy) that
_PRUNE_DIAGNOSIS_20260916.md's fix already added, behind the SAME flag the
CLI exposes as --reliable-pruning-witnesses. This driver exists only because
dump_all_endpoints's extraction loop is single-process and two of the six
corpora (notifications_index 313,977 dumps, posts_show 288,325 dumps) do not
finish in reasonable wall time single-threaded under this box's load.

Design (mirrors "Batch at the driver level" — parallel EXTRACTION, one
CENTRAL pruning/render pass, never split the pruning rule itself across
shards, since it is a corpus-wide measurement):

  1. discover_param_pool ONCE (cheap: reads exploration_summary.json / the
     batch runner script next to the dumps, not the dumps themselves).
  2. Split the sorted dump list into N shards; each worker process calls
     extract_statements(shard, mark_unreliable_witnesses=True) — the same
     function build_endpoint_file calls, just given a slice of the corpus.
  3. MERGE every shard's distinct (shape, pc_preds) TransformedQuery set
     exactly as extract_statements's own `seen` dict would if run serially
     (dedup by (shape, pc_preds); reliable_witness is OR-combined: one
     trustworthy witness anywhere in the corpus is enough).
  4. ONE central prune_conditions pass over the merged set — run TWICE
     against the SAME merged extraction (arm "base": reliable_only=False,
     the flag's default; arm "fix": reliable_only=True) so both arms are
     measured on an IDENTICAL extracted statement population and differ only
     in the pruning decision, per the ground-truth-differential discipline.
  5. drop_subsumed(solver=False) (syntactic only — matches --no-subsume in
     the original pcfold2 recipe) and render_policy, per arm.

Usage:
    _pcfold3_parallel.py --endpoint E --dumpdir D --out-dir O [--shards N]
        [--cap 2] [--sample N] [--sample-seed S]
"""
from __future__ import annotations

import argparse
import dataclasses
import glob
import json
import os
import sys
import time
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import Dict, List, Tuple

sys.path.insert(0, "/home/dev/project/src")
APP_CONFIG = "/home/dev/project/reports/diaspora/queries_config/app.json"
os.environ.setdefault("QFR_APP_CONFIG", APP_CONFIG)

from queries_from_runs import dump as dump_mod                     # noqa: E402
from queries_from_runs import app_config as app_config_mod         # noqa: E402
from queries_from_runs.endpoint_params import discover_param_pool  # noqa: E402
from queries_from_runs.transform import TransformedQuery           # noqa: E402


def _shard_worker(args) -> dict:
    paths, param_pool, cap = args
    cfg = app_config_mod.load_cached(APP_CONFIG)
    t0 = time.time()
    extraction = dump_mod.extract_statements(
        paths, param_pool=param_pool, app_config=cfg,
        exclude_rejected=True, two_query_cap=cap,
        mark_unreliable_witnesses=True,
    )
    return {
        "queries": [dataclasses.asdict(qy) for qy in extraction.queries],
        "n_runs": extraction.n_runs,
        "n_raw": extraction.n_raw,
        "n_rejected": extraction.n_rejected,
        "flags": extraction.flags,
        "placeholders": list(extraction.placeholders),
        "skipped_pcs": extraction.skipped_pcs,
        "n_errors": len(extraction.errors),
        "sample_errors": extraction.errors[:10],
        "n_dumps": len(paths),
        "seconds": time.time() - t0,
    }


def _chunks(seq, n):
    k = max(1, -(-len(seq) // n))  # ceil div -> n roughly-equal chunks
    return [seq[i:i + k] for i in range(0, len(seq), k)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--dumpdir", required=True)
    ap.add_argument("--out-dir", required=True,
                    help="MUST be results3/queries_from_runs (or similar) — "
                         "never a results3/<endpoint> dump directory")
    ap.add_argument("--shards", type=int, default=8)
    ap.add_argument("--cap", type=int, default=2)
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--sample-seed", type=int, default=20260915)
    ap.add_argument("--suffix", default="_pcfold3")
    args = ap.parse_args()

    assert "results3/queries_from_runs" in os.path.abspath(args.out_dir) or \
        "scratchpad" in os.path.abspath(args.out_dir), \
        "refusing to write outside the queries_from_runs output dir"

    t_start = time.time()
    all_paths = sorted(glob.glob(os.path.join(args.dumpdir, "dump_*.json")))
    print(f"[{args.endpoint}] corpus size: {len(all_paths)}", flush=True)
    if args.sample:
        import random
        picked = list(all_paths)
        random.Random(args.sample_seed).shuffle(picked)
        all_paths = sorted(picked[:args.sample])
        print(f"[{args.endpoint}] sampled: {len(all_paths)}", flush=True)

    param_pool = discover_param_pool(all_paths)
    shards = _chunks(all_paths, args.shards)
    print(f"[{args.endpoint}] {len(shards)} shards, sizes="
          f"{[len(s) for s in shards]}", flush=True)

    merged: Dict[Tuple[str, Tuple[str, ...]], dict] = {}
    n_runs = n_raw = n_rejected = 0
    flags: Counter = Counter()
    placeholders: set = set()
    skipped: Counter = Counter()
    n_errors = 0
    sample_errors: List[str] = []

    with ProcessPoolExecutor(max_workers=args.shards) as ex:
        futs = {ex.submit(_shard_worker, (shard, param_pool, args.cap)): i
                for i, shard in enumerate(shards)}
        for fut in as_completed(futs):
            i = futs[fut]
            r = fut.result()
            n_runs += r["n_runs"]
            n_raw += r["n_raw"]
            n_rejected += r["n_rejected"]
            flags.update(r["flags"])
            placeholders.update(r["placeholders"])
            skipped.update(r["skipped_pcs"])
            n_errors += r["n_errors"]
            sample_errors.extend(r["sample_errors"][:3])
            rate = r["n_dumps"] / r["seconds"] if r["seconds"] else 0
            print(f"[{args.endpoint}] shard {i} done: {r['n_dumps']} dumps in "
                  f"{r['seconds']:.0f}s ({rate:.1f} dumps/s), "
                  f"{len(r['queries'])} distinct (shape,preds)", flush=True)
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

    queries = list(merged.values())
    elapsed = time.time() - t_start
    print(f"[{args.endpoint}] EXTRACTION DONE: {len(all_paths)} dumps, "
          f"{n_runs} runs, {n_raw} raw queries, {len(queries)} distinct "
          f"(shape,preds), {n_errors} errors, elapsed={elapsed:.0f}s", flush=True)
    print(f"[{args.endpoint}] SKIPPED PCs (never rendered into any query, "
          f"by reason): total={sum(skipped.values())} "
          f"top20={skipped.most_common(20)}", flush=True)

    header = dump_mod._header_for(os.path.dirname(args.dumpdir.rstrip("/")),
                                  args.endpoint)

    results = {}
    for arm_name, reliable_only in (("base", False), ("fix", True)):
        n_preds_before = sum(len(qy.pc_preds) for qy in queries)
        deduped = dump_mod.prune_conditions(queries, reliable_only=reliable_only)
        n_preds_after = sum(len(qy.pc_preds) for qy in deduped)
        sub = dump_mod.drop_subsumed(deduped, solver=False)
        out_path = os.path.join(
            args.out_dir, f"{args.endpoint}{args.suffix}_{arm_name}.sql")
        provenance = [
            "--",
            f"-- Extracted from {len(all_paths)} dumps, {n_runs} runs loaded,"
            f" {n_raw} raw queries,",
            f"--   {len(queries)} distinct (query, conditions) pairs,"
            f" {len(deduped)} distinct statements,",
            f"--   {sub.n_dropped} subsumed, {len(sub.queries)} views."
            f"  subsume_ran={sub.ran}",
            f"--   PC predicates: {n_preds_before} rendered, {n_preds_after}"
            " kept.",
            f"--   two_query_cap={args.cap}; exclude_rejected=True;"
            f" reliable_pruning_witnesses={reliable_only}",
            f"--   sharded extraction ({args.shards} shards,"
            f" _pcfold3_parallel.py); fold: src/queries_from_runs (no patches)",
            "",
        ]
        os.makedirs(args.out_dir, exist_ok=True)
        with open(out_path, "w") as f:
            f.write(dump_mod.render_policy(sub.queries, header + provenance))
        results[arm_name] = {
            "out_path": out_path,
            "n_dumps": len(all_paths),
            "n_runs": n_runs,
            "n_raw": n_raw,
            "n_rejected": n_rejected,
            "n_queries_observed": len(queries),
            "n_queries_deduped": len(deduped),
            "n_queries_final": len(sub.queries),
            "n_subsumed_dropped": sub.n_dropped,
            "n_pc_predicates_before_prune": n_preds_before,
            "n_pc_predicates_after_prune": n_preds_after,
            "placeholders": sorted(placeholders),
            "flags": dict(flags),
            "skipped_pcs": dict(skipped),
        }
        print(f"[{args.endpoint}] arm={arm_name} -> {out_path}: "
              f"{len(sub.queries)} statements, PC {n_preds_before} -> "
              f"{n_preds_after} kept", flush=True)

    summary_path = os.path.join(
        args.out_dir, f"_summary_{args.endpoint}{args.suffix}.json")
    with open(summary_path, "w") as f:
        json.dump(results, f, indent=1)
    print(f"VERDICT_PCFOLD3 endpoint={args.endpoint} elapsed={elapsed:.0f}s "
          f"summary={summary_path}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
