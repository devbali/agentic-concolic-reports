#!/usr/bin/env python3
"""Is the PRUNED list equivalent to the full list, for the §16b verdict?

Not a verdict comparison on a sample — a direct check that THE CHECKER'S INPUTS
are identical, which is stronger and costs one load instead of two Z3 phases.

Under DISCIPLINE §16b the checker reads exactly one thing off a run: the map
`expr -> {outcomes taken}`. Everything it then computes is a function of the
MULTISET of those maps:
    * the demand universe          = maximal_sets over the per-run expr SETS
    * foreclosure                  = infer_foreclosures over the same maps
    * covering cubes / blocking    = built from the same maps
    * tree_missing                 = the union of the sides they contain
    * this batch's assumption set  = coverage_assumptions.build(runs), which
      touches the runs ONLY through the distinct exprs and the per-run expr set
So two corpora with the same SET of distinct profiles are interchangeable for
every verdict field. This checks exactly that, plus the three derived objects,
on real data.

usage: _prune_equiv.py --full <list> --pruned <list>
"""
import hashlib, json, os, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402
from concolic_engine.coverage import maximal_sets  # noqa: E402


def opt(n):
    return sys.argv[sys.argv.index(n) + 1]


def load(listfile):
    paths = sorted(l.strip() for l in open(listfile) if l.strip())
    paths = [p if os.path.isabs(p) else os.path.join(HERE, p) for p in paths]
    profiles, exprsets, allexprs, sides = set(), set(), set(), set()
    for p in paths:
        try:
            d = json.load(open(p))
            canonicalize_ordinals(d)
            d = fix_len_names(d)
        except Exception:
            continue
        acc = {}
        for e in d.get("events") or ():
            if e.get("type") == "path_condition":
                acc.setdefault(e["expr"], set()).add(bool(e.get("taken")))
        if not acc:
            continue
        key = ";".join(f"{k}:{''.join('1' if v else '0' for v in sorted(acc[k]))}"
                       for k in sorted(acc))
        profiles.add(hashlib.blake2b(key.encode(), digest_size=16).hexdigest())
        exprsets.add(frozenset(acc))
        allexprs |= set(acc)
        for k, vs in acc.items():
            for v in vs:
                sides.add((k, v))
    return {"n": len(paths), "profiles": profiles, "exprsets": exprsets,
            "exprs": allexprs, "sides": sides,
            "maximal": {frozenset(s) for s in maximal_sets(exprsets)}}


A = load(opt("--full"))
B = load(opt("--pruned"))
print(f"full   {A['n']:6d} dumps -> {len(A['profiles']):6d} distinct profiles")
print(f"pruned {B['n']:6d} dumps -> {len(B['profiles']):6d} distinct profiles")
rows = [
    ("distinct outcome profiles", A["profiles"], B["profiles"]),
    ("per-run evaluation SETS   ", A["exprsets"], B["exprsets"]),
    ("MAXIMAL sets (the demand universe)", A["maximal"], B["maximal"]),
    ("distinct tracked exprs    ", A["exprs"], B["exprs"]),
    ("observed (expr, side) pairs (the tree layer)", A["sides"], B["sides"]),
]
ok = True
for name, a, b in rows:
    same = (a == b)
    ok &= same
    print(f"  {'IDENTICAL' if same else 'DIFFERENT'}  {name:46s} "
          f"full={len(a):6d} pruned={len(b):6d} "
          f"only-in-full={len(a - b)} only-in-pruned={len(b - a)}")
print("PRUNE_EQUIVALENT=" + str(bool(ok)))
sys.exit(0 if ok else 1)
