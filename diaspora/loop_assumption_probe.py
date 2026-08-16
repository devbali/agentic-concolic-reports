#!/usr/bin/env python3
"""Prototype: RecurrentPathAssumption ("loop assumption") — measured, not shipped.

Strict-per-node treats every occurrence of a PC as its own node, because its
prefix differs. When a predicate is re-evaluated per element (87% of paths in
this experiment repeat some expression >=3x), that multiplies the frontier
without adding distinct decisions.

Proposed semantics: for a PathSource declared RECURRENT, require both-sides
coverage at its FIRST occurrence along a path; deeper occurrences inherit it.

This script measures the effect WITHOUT touching src/: it folds recurrences by
collapsing each path to its first occurrence of any repeated (expr) and rebuilds
the tree independently of the engine, so nothing in the runtime or the dumps
changes.

SOUNDNESS NOTE: this is a relaxation and CAN mask an iteration-dependent bug
(one that only manifests on the 3rd pass). It is sound only where the loop body
is iteration-independent. That is why it must be a DECLARED assumption with a
justification, never a default.
"""
import json, glob, sys, collections

def paths_for(d):
    out = []
    for p in sorted(glob.glob(d + "/dump_*.json")):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        out.append([(e["expr"], bool(e["taken"]))
                    for e in (raw.get("events") or [])
                    if e.get("type") == "path_condition"])
    return out

def tree_stats(paths):
    kids = {}
    for p in paths:
        for i, (ex, t) in enumerate(p):
            kids.setdefault((tuple(p[:i]), ex), set()).add(t)
    nodes = len(kids)
    one_sided = sum(1 for s in kids.values() if len(s) != 2)
    return nodes, one_sided

def fold_recurrent(p):
    """Keep only the FIRST occurrence of each expression along the path."""
    seen, out = set(), []
    for ex, t in p:
        if ex in seen:
            continue
        seen.add(ex)
        out.append((ex, t))
    return out

def main():
    root = "/home/dev/project/reports/diaspora/results"
    rows = []
    for d in sorted(glob.glob(root + "/*/*")):
        paths = paths_for(d)
        if not paths or not any(paths):
            continue
        n0, o0 = tree_stats(paths)
        n1, o1 = tree_stats([fold_recurrent(p) for p in paths])
        if n0 != n1:
            rows.append((d.split("results/")[1], len(paths), n0, o0, n1, o1))
    rows.sort(key=lambda r: r[2] - r[4], reverse=True)
    print(f"{'entrypoint':<46}{'paths':>6}{'strict':>8}{'1sided':>7}{'folded':>8}{'1sided':>7}")
    print("-" * 82)
    for name, np_, n0, o0, n1, o1 in rows[:14]:
        print(f"{name:<46}{np_:>6}{n0:>8}{o0:>7}{n1:>8}{o1:>7}")
    print("-" * 82)
    tot0 = sum(r[2] for r in rows); tot1 = sum(r[4] for r in rows)
    print(f"{'TOTAL (entrypoints where folding changes anything)':<46}"
          f"{'':>6}{tot0:>8}{'':>7}{tot1:>8}")
    print(f"\nentrypoints affected: {len(rows)}   node reduction: {tot0}->{tot1} "
          f"({100*(tot0-tot1)/tot0:.0f}% fewer)")

if __name__ == "__main__":
    sys.exit(main())
