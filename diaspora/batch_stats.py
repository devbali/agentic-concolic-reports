#!/usr/bin/env python3
"""Solver-independent per-entrypoint statistics for a diaspora results batch.

Rebuilt from the dumps, NOT from the engine's verdict — see COMPLETENESS_AUDIT.md
for why `coverage_complete` alone is not evidence. The headline column is
`both/total`: a branch expression counts as covered only when BOTH `taken: true`
and `taken: false` were observed somewhere in that entrypoint's runs.

Branch expressions are keyed by (expr, file, lineno) — the source SITE, not the
expression string, since the same expression can legitimately come from
different call sites.

No deduplication is performed anywhere: the ordered PC sequence is load-bearing
for the execution tree.

Usage:
    PYTHONPATH=src python3 reports/diaspora/batch_stats.py <batch> [<batch> ...]
    PYTHONPATH=src python3 reports/diaspora/batch_stats.py --all
"""
import collections
import glob
import json
import os
import sys

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")


def entrypoint_stats(ep_dir):
    """Read every dump_*.json in one entrypoint dir; return a stats dict."""
    st = {
        "entrypoint": os.path.basename(ep_dir),
        "dumps": 0,
        "unparseable": [],
        "pcs": 0,
        "clean_dumps": 0,
        "vacuous_dumps": 0,
        "errors": collections.Counter(),
        "sites": collections.defaultdict(set),   # (expr,file,line) -> {True,False}
        "symbolic_calls": 0,
    }
    for path in sorted(glob.glob(os.path.join(ep_dir, "dump_*.json"))):
        try:
            d = json.load(open(path))
        except Exception as exc:
            st["unparseable"].append((os.path.basename(path), str(exc)))
            continue
        st["dumps"] += 1
        n_pc = 0
        for e in d.get("events", []):
            t = e.get("type")
            if t == "path_condition":
                n_pc += 1
                key = (e.get("expr"), e.get("file"), e.get("lineno"))
                st["sites"][key].add(bool(e.get("taken")))
            elif t == "symbolic_call":
                st["symbolic_calls"] += 1
        st["pcs"] += n_pc
        if n_pc == 0:
            st["vacuous_dumps"] += 1
        err = d.get("error")
        if err:
            kind = err.get("type") if isinstance(err, dict) else str(err)
            st["errors"][kind] += 1
        else:
            st["clean_dumps"] += 1

    st["total_sites"] = len(st["sites"])
    st["both_sites"] = sum(1 for v in st["sites"].values() if len(v) == 2)
    st["one_sided"] = [k for k, v in st["sites"].items() if len(v) != 2]

    # Engine verdict + exploration state, read alongside but reported separately.
    for name, keys in (
        ("coverage_summary.json",
         ("coverage_complete", "tree_nodes", "missing_branches",
          "blocking_missing_branches", "genuine", "vacuous", "solver_lost",
          "total_runs", "assumptions_used")),
        ("exploration_summary.json",
         ("runs_executed", "worklist_exhausted", "stop_reason",
          "distinct_paths", "elapsed_seconds", "unflippable_pcs")),
    ):
        p = os.path.join(ep_dir, name)
        if os.path.exists(p):
            try:
                d = json.load(open(p))
            except Exception:
                continue
            for k in keys:
                if k in d:
                    st[k] = d[k]
    return st


def batch_stats(batch):
    bdir = os.path.join(RESULTS, batch)
    eps = [d for d in sorted(glob.glob(os.path.join(bdir, "*")))
           if os.path.isdir(d) and glob.glob(os.path.join(d, "dump_*.json"))]
    return [entrypoint_stats(d) for d in eps]


def render(batch, rows):
    print("=" * 78)
    print(batch)
    print("=" * 78)
    hdr = ("entrypoint", "dumps", "PCs", "nodes", "miss", "cmpl", "gen",
           "both/tot", "clean", "runs", "drained")
    print("%-34s %5s %6s %5s %4s %5s %4s %8s %6s %7s %7s" % hdr)
    tot = collections.Counter()
    for r in rows:
        print("%-34s %5d %6d %5s %4s %5s %4s %8s %6s %7s %7s" % (
            r["entrypoint"], r["dumps"], r["pcs"],
            r.get("tree_nodes", "-"), r.get("missing_branches", "-"),
            r.get("coverage_complete", "-"),
            "gen" if r.get("genuine") else ("VAC" if r["pcs"] == 0 else "?"),
            "%d/%d" % (r["both_sites"], r["total_sites"]),
            "%d/%d" % (r["clean_dumps"], r["dumps"]),
            r.get("runs_executed", "-"),
            r.get("worklist_exhausted", "-"),
        ))
        for k in ("dumps", "pcs", "both_sites", "total_sites",
                  "clean_dumps", "vacuous_dumps"):
            tot[k] += r[k]
        tot["runs"] += r.get("runs_executed", 0) or 0
    print("-" * 78)
    print("%-34s %5d %6d %5s %4s %5s %4s %8s %6s %7d" % (
        "TOTAL", tot["dumps"], tot["pcs"], "", "", "", "",
        "%d/%d" % (tot["both_sites"], tot["total_sites"]),
        "%d/%d" % (tot["clean_dumps"], tot["dumps"]), tot["runs"]))
    errs = collections.Counter()
    for r in rows:
        errs.update(r["errors"])
    if errs:
        print("\nerrors across dumps:")
        for k, v in errs.most_common():
            print("  %4d  %s" % (v, k))
    one = [(r["entrypoint"], k) for r in rows for k in r["one_sided"]]
    if one:
        print("\none-sided branch expressions (%d):" % len(one))
        for ep, (expr, f, ln) in one:
            print("  %-30s %s" % (ep, expr))
            print("  %-30s   at %s:%s" % ("", f, ln))
    unp = [(r["entrypoint"], u) for r in rows for u in r["unparseable"]]
    if unp:
        print("\nUNPARSEABLE dumps (%d):" % len(unp))
        for ep, (name, exc) in unp:
            print("  %-30s %s: %s" % (ep, name, exc))
    print()
    return tot


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    if args == ["--all"]:
        args = sorted(d for d in os.listdir(RESULTS)
                      if os.path.isdir(os.path.join(RESULTS, d)))
    grand = collections.Counter()
    for b in args:
        grand.update(render(b, batch_stats(b)))
    if len(args) > 1:
        print("GRAND TOTAL: %d dumps, %d PCs, %d/%d branch expressions two-sided,"
              " %d clean" % (grand["dumps"], grand["pcs"], grand["both_sites"],
                             grand["total_sites"], grand["clean_dumps"]))
