#!/usr/bin/env python3
"""Verification trace for the alias-collision fix (2026-09-17).

Monkeypatches ``_Build._render_atom`` to log, for every rendered atom, its
rendered SQL predicate text alongside the ORIGINAL (pre-render) producer
identity of each ColRef side. Same methodology used (as inline heredocs, not
saved at the time) to first prove the pre-fix collision and then to show the
initial partial fix (hint applied only to the two-query-cap call site) was
incomplete. Saved here, post-fix (hint now applied unconditionally in
``inline_producer``/``_fresh_alias``), as the confirming re-run — and so this
methodology is reproducible/inspectable rather than living only in transcript
history.

A "collision" is a rendered predicate TEXT that maps to more than one
distinct (lhs_producer, rhs_producer) pair across the sample: same corpus
predicate string, different real-world identity underneath it. That is
exactly the situation :func:`pcs.irrelevant_predicates` cannot distinguish
from "sometimes present, sometimes absent" -- so a nonzero collision count
here 1:1 predicts wrongly-pruned predicates downstream.
"""
from __future__ import annotations

import glob
import os
import random
import sys
from collections import defaultdict

sys.path.insert(0, "/home/dev/project/src")
APP_CONFIG = "/home/dev/project/reports/diaspora/queries_config/app.json"
os.environ.setdefault("QFR_APP_CONFIG", APP_CONFIG)

from queries_from_runs import dump as dump_mod                      # noqa: E402
from queries_from_runs import app_config as app_config_mod          # noqa: E402
from queries_from_runs import transform as transform_mod            # noqa: E402
from queries_from_runs.pcs import ColRef                            # noqa: E402
from queries_from_runs.endpoint_params import discover_param_pool   # noqa: E402

DUMPDIR = "/home/dev/project/reports/diaspora/results3/comments_index"
N_SAMPLE = 3000
SEED = 7
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(HERE, "_verify_alias_fix_20260917.out")

atom_log = []  # (rendered_sql, lhs_producer_or_None, rhs_producer_or_None)

_orig_render_atom = transform_mod._Build._render_atom


def _patched_render_atom(self, atom):
    node = _orig_render_atom(self, atom)
    if node is not None:
        lhs_p = atom.lhs.producer if isinstance(atom.lhs, ColRef) else None
        rhs_p = atom.rhs.producer if isinstance(atom.rhs, ColRef) else None
        atom_log.append((node.sql(dialect="mysql"), lhs_p, rhs_p))
    return node


def main():
    transform_mod._Build._render_atom = _patched_render_atom

    all_paths = sorted(glob.glob(os.path.join(DUMPDIR, "dump_*.json")))
    random.seed(SEED)
    sample = random.sample(all_paths, min(N_SAMPLE, len(all_paths)))
    print(f"corpus size: {len(all_paths)}, sample: {len(sample)}", flush=True)

    param_pool = discover_param_pool(sample)
    cfg = app_config_mod.load_cached(APP_CONFIG)
    extraction = dump_mod.extract_statements(
        sample, param_pool=param_pool, app_config=cfg,
        exclude_rejected=True, two_query_cap=2,
        mark_unreliable_witnesses=True,
    )

    lines = []
    lines.append(f"n runs {extraction.n_runs} n_errors {extraction.n_rejected}")
    lines.append(f"atom_log len {len(atom_log)}")

    by_text = defaultdict(set)
    for text, lp, rp in atom_log:
        if "people" not in text:
            continue
        by_text[text].add((lp, rp))

    n_colliding = sum(1 for pairs in by_text.values() if len(pairs) > 1)
    lines.append(f"distinct people-related preds: {len(by_text)}")
    lines.append(
        f"colliding (>1 distinct lhs/rhs producer pair for same text): "
        f"{n_colliding}"
    )
    for text, pairs in sorted(by_text.items(), key=lambda kv: -len(kv[1])):
        if len(pairs) <= 1:
            continue
        lines.append(f"PRED: {text}  ({len(pairs)} distinct producer pairs)")
        for lp, rp in sorted(pairs, key=lambda p: (p[0] or "", p[1] or "")):
            lines.append(f"    ({lp}, {rp})")

    out = "\n".join(lines)
    print(out, flush=True)
    with open(OUT_PATH, "w") as f:
        f.write(out + "\n")
    print(f"\nwrote {OUT_PATH}", flush=True)


if __name__ == "__main__":
    main()
