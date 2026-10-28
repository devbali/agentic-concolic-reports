#!/usr/bin/env python3
"""WHY posts_show's demand universe is 4.85e13 — the shape of its demand sets.

The p5 census (`_enum_p5_cost.log`) is EXACT and cheap (5m31s, 3.2 GB peak,
bounded_cliques=0) and it returns satisfiable=48 548 318 047 288 over 1805
demand sets. This tool answers the only question that matters next: is that
product forced by the SOLVER (expressions genuinely coupled through shared Z3
variables) or by the ASSUMPTION LAYER (expressions the dependence graph joins
although no Z3 variable connects them)?

The census already factorises each set by VARIABLE-CONNECTED COMPONENT — the
product over components is what makes the bignum exact. So a set whose
components are all singletons is a set of w mutually variable-DISJOINT
decisions that the graph nevertheless demands as a 2^w product.

Prints, per set and in total:
  * width, component count, component-size histogram, satisfiable, covered
  * ADJACENT-BUT-DISJOINT pairs: (a, b) with an edge in `adj` and no shared
    Z3 variable. Every such pair is a candidate independence DECLARATION;
    each one that lands halves (at least) the set's demand.
"""
import json, os, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                      # noqa: E402
from coverage_assumptions import build as build_assumptions   # noqa: E402

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
assert U is not None, "PROJECTION CAP HIT"
known = EE.var_index(U["decls"]); vcache = {}; memo = {}
cliques = U["cliques"]
print(f"universe built in {time.time()-t0:.0f}s", flush=True)

adj = U["adj"]
# --- 1. every ADJACENT pair, split by whether Z3 actually couples it --------
pairs_adj = 0; pairs_disjoint = 0
for a, nbrs in adj.items():
    for b in nbrs:
        if a >= b:
            continue
        pairs_adj += 1
        if not (EE.vars_of(a, known, vcache) & EE.vars_of(b, known, vcache)):
            pairs_disjoint += 1
print(f"\nDEPENDENCE EDGES: {pairs_adj} adjacent pairs over {len(adj)} active exprs")
print(f"   of those sharing NO Z3 variable: {pairs_disjoint} "
      f"({100.0*pairs_disjoint/max(pairs_adj,1):.1f}%)")

# --- 2. per-set shape -------------------------------------------------------
comp_hist = Counter(); widths = Counter(); singleton_sets = 0
tot_sat = 0; rows = []
for ci, cl in enumerate(cliques):
    comps = EE.components(list(cl), known, vcache)
    sizes = sorted((len(c) for c in comps), reverse=True)
    cm = [EE.comp_models(c, U["fixed_base"], U["decls"], U["pinned"], memo) for c in comps]
    sat = EE.cube_count(cm, {})
    tot_sat += sat
    widths[len(cl)] += 1
    for s in sizes:
        comp_hist[s] += 1
    if sizes and sizes[0] == 1:
        singleton_sets += 1
    rows.append((sat, len(cl), len(comps), sizes[:6], ci))
    if ci % 300 == 0:
        print(f"  [{ci}/{len(cliques)}] w={len(cl)} comps={len(comps)} sat={sat}", flush=True)

rows.sort(reverse=True)
print(f"\nSET-LEVEL satisfiable (no foreclosure prune) total={tot_sat}")
print(f"sets whose components are ALL SINGLETONS (fully variable-disjoint): "
      f"{singleton_sets}/{len(cliques)}")
print("component-size histogram (size x count): " +
      ", ".join(f"{s}x{n}" for s, n in sorted(comp_hist.items())))
print("\nTOP-10 sets by satisfiable:")
for sat, w, nc, sizes, ci in rows[:10]:
    print(f"  set#{ci:5d} width={w:3d} components={nc:3d} sizes={sizes} sat={sat}")

# --- 3. name the widest set's members --------------------------------------
wid = max(range(len(cliques)), key=lambda i: len(cliques[i]))
print(f"\nWIDEST SET #{wid} (width {len(cliques[wid])}) — its members:")
for e in cliques[wid]:
    print(f"   {e}")
json.dump({"pairs_adj": pairs_adj, "pairs_disjoint": pairs_disjoint,
           "singleton_sets": singleton_sets, "cliques": len(cliques),
           "set_sat_total": str(tot_sat),
           "comp_hist": {str(k): v for k, v in comp_hist.items()},
           "widths": {str(k): v for k, v in widths.items()}},
          open(os.path.join(HERE, "_setshape_p5.json"), "w"), indent=1)
print(f"\nDONE in {time.time()-t0:.0f}s")
