#!/usr/bin/env python3
"""Dump the INFERRED foreclosure relation (and the solver's declaration set)
for the current corpus, WITHOUT the expensive clique projection.

Why it exists (2026-09-10, §14, owner direction): the enabling-constraint
seeder needs, per demanded decision `d`, every `(g, o)` that forecloses it —
so it can add `g != o` to the solver query and get back a model that carries
the whole WALKABLE path, not just the cube. `_exact_enum.py` computes exactly
this inside `build_universe`, but pays ~580 s for the maximal-clique
projection that the seeder does not need. This tool runs only the steps the
relation depends on:

    load -> alias -> profiles (digest key, src/coverage.py) -> parseable
    -> assumption filter -> infer_foreclosures

i.e. steps 1, 3, 4 of `CoverageChecker.check_coverage` plus §16b's inference.
It is the SAME code (`infer_foreclosures` is imported from the engine), so the
relation is the one the pass and the census use.

usage: DUMP_LIST=<snapshot> PYTHONPATH=/home/dev/project/src \
       python3 -u _forecl_dump.py --out _forecl.json
"""
from __future__ import annotations

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.coverage import (CoverageChecker, profile_key,  # noqa: E402
                                      infer_foreclosures, _outcome_constraint)
from concolic_engine.run import PathSource  # noqa: E402
from concolic_engine.solver import check_satisfiability  # noqa: E402

import _exact_enum as EE  # noqa: E402
from coverage_assumptions import build as build_assumptions  # noqa: E402

TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))


def _rss():
    import resource
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1048576.0


def main():
    args = sys.argv[1:]
    out = args[args.index("--out") + 1] if "--out" in args else os.path.join(HERE, "_forecl.json")
    t0 = time.time()
    runs = EE.load_runs()
    assumptions = build_assumptions(runs)
    ck = CoverageChecker(runs, assumptions=assumptions)
    runs = ck.runs
    print(f"[mem] aliased: peak RSS {_rss():.2f} GB", flush=True)

    expr_order, expr_source, profiles = [], {}, {}
    for run in runs:
        outcomes = {}
        for pc in run.path_conditions:
            if pc.expr not in expr_source:
                expr_order.append(pc.expr)
                expr_source[pc.expr] = (pc.source if isinstance(pc.source, PathSource) else None)
            outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
        if outcomes:
            profiles.setdefault(profile_key(outcomes), outcomes)
    run_outcomes = list(profiles.values())
    del profiles
    print(f"[mem] profiles={len(run_outcomes)} distinct; peak RSS {_rss():.2f} GB", flush=True)

    decls = ck._merged_declarations()
    fixed_base = list(assumptions.symbolic_constraints()) + ck._merged_bounds()
    parseable = [e for e in expr_order
                 if check_satisfiability([f"Or({e}, Not({e}))"], decls, TIMEOUT).satisfiable]
    untracked, pinned, active = [], {}, []
    for e in parseable:
        src = expr_source[e]
        if assumptions.is_untracked(src, e):
            untracked.append(e)
            continue
        for side, outcome in (("taken", True), ("not_taken", False)):
            if assumptions.is_one_side_untracked(src, side, e):
                pinned[e] = not outcome
        active.append(e)
    print(f"active={len(active)} untracked={len(untracked)} pinned={len(pinned)}", flush=True)

    forecl, bit, masks = infer_foreclosures(active, run_outcomes)
    inv = {i: e for e, i in bit.items()}
    gates = {}
    npairs = 0
    for (g, o), fm in forecl.items():
        ds = []
        m, j = fm, 0
        while m:
            if m & 1:
                ds.append(inv[j])
            m >>= 1
            j += 1
        npairs += len(ds)
        gates.setdefault(g, {})["1" if o else "0"] = ds
    print(f"foreclosures inferred: {npairs} (gate,outcome)->decision pairs "
          f"over {len(gates)} gates", flush=True)

    # Also record, per active expr, which OUTCOMES the corpus ever showed —
    # a seeder must not demand an arm the tree layer never had.
    seen = {}
    for o in run_outcomes:
        for e, v in o.items():
            if e in bit:
                seen.setdefault(e, set()).update(v)

    json.dump({
        "dump_list": os.environ.get("DUMP_LIST"),
        "profiles": len(run_outcomes),
        "active": active,
        "untracked": untracked,
        "pinned": {k: bool(v) for k, v in pinned.items()},
        "decls": list(decls),
        "fixed_base": list(fixed_base),
        "gates": gates,
        "pairs": npairs,
        "seen": {e: sorted(list(v)) for e, v in seen.items()},
    }, open(out, "w"))
    print(f"wrote {out} in {time.time()-t0:.0f}s; peak RSS {_rss():.2f} GB", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
