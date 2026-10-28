#!/usr/bin/env python3
"""conversations_index — COVERAGE-ONLY probe of the confinement layer (2026-09-26).

WHY THIS EXISTS
---------------
The 2026-09-19 -> 2026-09-26 full assumption gate left
`coverage_summary.json` with `coverage_numbers_stale` set and 71
`ConfinementAssumption` FAILs.  Before feeding those 71 back as
`withdrawn_pairs`, this script answers the cheaper and stronger question:

    does this endpoint's coverage verdict depend on the §16c confinement
    licence AT ALL?

If the tree/demand verdict is unchanged with confinement switched OFF
entirely (strictly more conservative than withdrawing any subset of pairs),
the 71 refutations — genuine or not — cannot change the verdict.

It also carries the C1 TRACE-CURRENCY repair
(`reports/diaspora/docs/CONFINEMENT_PRECISION_20260913.md` §2,
`reports/diaspora/tools/_c1_currency_patch.md`) as an OPTION, because this
endpoint's `coverage_report.py::fix_len_names` still pops `note` and `args`
off every event.  `concolic_engine.assumptions.call_shape` reads exactly
those two fields plus the target name, so with them popped the §16c footprint
is measured in BARE TARGET NAMES (22 distinct here) while the assumption
gate's `access_trace` is measured in FULL SHAPES (48 distinct here).  The two
sides of the confinement handshake are then not the same currency.

NON-DESTRUCTIVE: writes `_covonly_<tag>.json`, never `coverage_summary.json`.

Usage:
    PYTHONPATH=/home/dev/project/src python3 _c1_covonly.py --tag noconf --no-confinement
    PYTHONPATH=/home/dev/project/src python3 _c1_covonly.py --tag wd71 --withdraw _confinement_withdrawn.json
    PYTHONPATH=/home/dev/project/src python3 _c1_covonly.py --tag c1keep --keep-notes
"""
import argparse
import gc
import glob
import json
import os
import resource
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)

import logging  # noqa: E402
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402

import coverage_report as CR                             # noqa: E402
from coverage_assumptions import build as build_assumptions   # noqa: E402


def keep_notes_loader(raw):
    """`fix_len_names` with the C1 repair applied: the `note`/`args` pops are
    skipped so `call_shape` keeps its full currency.  Everything else is the
    batch's own loader, re-implemented here rather than edited in place so the
    gate's own script stays byte-identical to the one that produced the
    2026-09-26 summary."""
    for sv in raw.get("symbolic_vars") or ():
        n = sv.get("name")
        if n and "len(" in n:
            sv["name"] = CR._LEN_RE.sub(r"SYM_LEN_\1", n)
        sv.pop("note", None)          # call_shape never reads symbolic_vars' note
    for ev in raw.get("events") or ():
        e = ev.get("expr")
        if e and "len(" in e:
            ev["expr"] = CR._LEN_RE.sub(r"SYM_LEN_\1", e)
        ev.pop("traceback", None)     # C1: note/args deliberately KEPT
    cv = raw.get("concrete_values")
    if isinstance(cv, dict):
        for k in [k for k in cv if "len(" in k]:
            cv[CR._LEN_RE.sub(r"SYM_LEN_\1", k)] = cv.pop(k)
    return raw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--no-confinement", action="store_true",
                    help="CoverageChecker(confinement=False) — no §16c licence at all")
    ap.add_argument("--keep-notes", action="store_true",
                    help="C1 trace-currency repair: keep note/args on events")
    ap.add_argument("--withdraw", default=None,
                    help="path to a _confinement_withdrawn*.json to feed as withdrawn_pairs")
    ap.add_argument("--limit", type=int, default=0, help="debug: load only N dumps")
    args = ap.parse_args()

    loader = keep_notes_loader if args.keep_notes else CR.fix_len_names

    withdrawn = []
    if args.withdraw:
        with open(os.path.join(HERE, args.withdraw)) as fh:
            wd = json.load(fh)
        rows = wd["withdrawn"] if isinstance(wd, dict) else wd
        for r in rows:
            pair = r["pair"] if isinstance(r, dict) else r
            withdrawn.append(tuple(pair))

    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    if args.limit:
        dumps = dumps[:args.limit]
    if not dumps:
        print("NO_DUMPS")
        return 2

    runs, skipped = [], []
    for p in dumps:
        try:
            with open(p) as fh:
                raw = json.load(fh)
        except Exception as e:  # noqa: BLE001
            skipped.append(os.path.basename(p))
            continue
        try:
            runs.append(CR.share_run_objects(CR.apply_len_bounds(Run.from_dict(loader(raw)))))
        except Exception as e:  # noqa: BLE001
            skipped.append(f"{os.path.basename(p)}:{type(e).__name__}")
        del raw
    gc.collect()
    print(f"[{args.tag}] loaded {len(runs)} runs ({len(skipped)} unparseable); "
          f"peak RSS {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB",
          flush=True)

    assumptions = build_assumptions(runs)

    kw = dict(max_missing_per_clique=int(os.environ.get("MAX_MISSING_PER_CLIQUE", "4")))
    if args.no_confinement:
        kw["confinement"] = False
    if withdrawn:
        kw["withdrawn_pairs"] = withdrawn
    print(f"[{args.tag}] CoverageChecker kwargs: confinement="
          f"{kw.get('confinement', True)} withdrawn_pairs={len(withdrawn)}", flush=True)

    t0 = time.time()
    result = CoverageChecker(runs, assumptions=assumptions, **kw).check_coverage()
    wall = time.time() - t0

    total_pcs = sum(len(r.path_conditions) for r in runs)
    out = {
        "tag": args.tag,
        "endpoint": "conversations_index",
        "flags": {"no_confinement": args.no_confinement, "keep_notes": args.keep_notes,
                  "withdraw_file": args.withdraw, "withdrawn_pairs": len(withdrawn)},
        "coverage_complete": bool(result.complete),
        "tree_complete": getattr(result, "tree_complete", None),
        "tree_missing_n": len(getattr(result, "tree_missing", ()) or ()),
        "tree_missing": list(getattr(result, "tree_missing", ()))[:200],
        "tree_nodes": result.total_nodes,
        "missing_branches": len(result.missing),
        "demand_sets": getattr(result, "demand_sets", None),
        "truncated": result.truncated,
        "solver_lost": result.solver_lost,
        "unevaluable_exprs": list(result.unevaluable_exprs),
        "total_runs": result.total_runs,
        "total_path_conditions": total_pcs,
        "confined_pairs": len(getattr(result, "confined_pairs", ()) or ()),
        "confinement_splits": getattr(result, "confinement_splits", None),
        "confinement_withdrawn": len(getattr(result, "confinement_withdrawn", ()) or ()),
        "confinement_provisional": getattr(result, "confinement_provisional", None),
        "missing": [
            {"node_constraint": m.node_constraint, "missing_branch": m.missing_branch,
             "source_location": m.source_location,
             "untracked": bool(getattr(m, "untracked", False)),
             "concrete_values": m.concrete_values}
            for m in result.missing[:200]
        ],
        "wall_seconds": round(wall, 1),
        "peak_rss_mb": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024,
    }
    p = os.path.join(HERE, f"_covonly_{args.tag}.json")
    with open(p, "w") as fh:
        json.dump(out, fh, indent=2)

    print(f"[{args.tag}] COVERAGE_COMPLETE={out['coverage_complete']};"
          f"TREE_COMPLETE={out['tree_complete']};TREE_MISSING={out['tree_missing_n']};"
          f"MISSING={out['missing_branches']};NODES={out['tree_nodes']};"
          f"DEMAND_SETS={out['demand_sets']};CONFINED={out['confined_pairs']};"
          f"SPLITS={out['confinement_splits']}")
    print(f"[{args.tag}] wrote {p} in {wall:.1f}s; peak RSS {out['peak_rss_mb']} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
