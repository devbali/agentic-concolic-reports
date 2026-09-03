#!/usr/bin/env python3
"""Clique-profile analysis for notifications_index C7 corpus (resume step 1).

Answers the PAUSED_C7 question: do the six new content dimensions ADD to the
125 cliques or MULTIPLY against the shared length variables?
"""
import json
import re
import sys
from collections import Counter

VAR_RE = re.compile(r"SYM_LEN_([A-Za-z0-9_]+)")


def main(path: str) -> None:
    d = json.load(open(path))
    missing = d["missing"]
    combo = [m for m in missing if m["missing_branch"] == "combination"]
    print(f"total missing entries : {len(missing)}")
    print(f"  combination         : {len(combo)}")
    print(f"  untracked (taken)   : {sum(1 for m in missing if m['untracked'])}")
    print()

    # signature = sorted var set of the node_constraint
    sig_texts: dict = {}
    for m in combo:
        vs = tuple(sorted(VAR_RE.findall(m["node_constraint"])))
        sig_texts.setdefault(vs, set()).add(m["node_constraint"])

    print(f"distinct clique signatures : {len(sig_texts)}")
    print(f"total entries              : {len(combo)}")
    totals = Counter()
    for vs, texts in sig_texts.items():
        totals[len(vs)] += 1
        totals[f"entries_nv{len(vs)}"] += len(texts)
    print()
    print(f"{'nvars':>6} {'sigs':>6} {'entries':>9} {'distinct_texts':>16}")
    for nv in sorted(set(totals.keys()) - {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}):
        pass
    by_nv: dict = {}
    for vs, texts in sig_texts.items():
        by_nv.setdefault(len(vs), []).append((vs, texts))
    for nv in sorted(by_nv):
        sigs = by_nv[nv]
        ents = sum(len(texts) for _, texts in sigs)
        print(f"{nv:6d} {len(sigs):6d} {ents:9d}")
    print()

    # consistency: are all texts in one signature the SAME var ordering (i.e. one clique)?
    print("dominant signature detail (13-var):")
    for vs, texts in by_nv.get(13, []):
        print(f"  entries={len(texts):6d}  distinct constraints={len(texts)}")
        # show 3 example constraints (truncated)
        for t in list(texts)[:2]:
            print(f"    e.g. {t[:150]}...")
            print(f"    e.g. {t[-150:]}")
    print()
    # bucket analysis over all combo entries
    cmp_re = re.compile(r"(SYM_LEN_\w+)\s*(==|!=|>|>=|<|<=)\s*([0-9]+)")
    buckets = Counter()
    for m in combo:
        for v, op, n in cmp_re.findall(m["node_constraint"]):
            buckets[(op, n)] += 1
    print("comparison ops used (bucket evidence):")
    for k, c in buckets.most_common():
        print(f"  {c:7d}  {k}")
    print()
    # per-var value-domain: do all 13 core vars actually range over 3 buckets?
    core_vars = set()
    for vs, texts in by_nv.get(13, []):
        core_vars |= set(vs)
    print(f"core 13-var clique var count: {len(core_vars)}")
    per_var_ops = Counter()
    for m in combo:
        for v, op, n in cmp_re.findall(m["node_constraint"]):
            per_var_ops[(v, op, n)] += 1
    # show var op coverage: does every var appear with >1, ==0, !=0?
    var_ops: dict = {}
    for (v, op, n), c in per_var_ops.items():
        var_ops.setdefault(v, []).append(f"{op}{n}:{c}")
    for v in sorted(core_vars):
        print(f"  {v[-60:]:60s} {', '.join(sorted(var_ops.get(v, [])))}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "coverage_summary.json")