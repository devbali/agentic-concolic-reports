#!/usr/bin/env python3
"""DECISIVE MEASUREMENT (2026-09-10) — are the seeded dimensions FREE?

The campaign's Step-1 question is whether DIVERSE seeding (`_diverse_seeds2.py`,
every length input assigned over {0,1,2,4}) actually varies the outcomes of the
wide demand sets, or whether the app's control flow pins them.

The 68 231-dump corpus ALREADY CONTAINS 16 569 diverse-v2 runs (LABEL_SUFFIX
`_DV2028*`, 2026-09-09) and 4 000 diverse-v1 runs (`_DIV1`). So the experiment
does not need a new drive to be decided: it needs the corpus SPLIT. This tool
computes, per demand set, the distinct observed outcome cubes and the covered
count restricted to
  * DIV  — the 20 569 diverse-seeded runs
  * PLAIN— the 47 662 non-diverse runs
  * ALL
and reports the per-run yield of each arm. If diverse seeding frees the wide
sets, the DIV arm must produce dramatically more distinct cubes per run than
the PLAIN arm on the width>=13 sets. If both arms plateau at the same handful
of cubes, the dimensions are pinned by control flow and driving cannot move
them.

It also reports (Step 0 confirmation) every demand set whose OWN observed
cubes are UNSAT under the declared model (`zero_covered_detail`), and the
tree-completeness residue.

usage: _decisive.py [--sample N] [--json-out f]
"""
from __future__ import annotations
import glob, json, os, random, re, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import logging
logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

from concolic_engine.coverage import (CoverageChecker, _maximal_cliques,
                                      maximal_sets, _combo_constraint)
from concolic_engine.run import Run, PathSource
from concolic_engine.solver import check_satisfiability
import coverage_report as CR
import coverage_assumptions as CA
from coverage_assumptions import build as build_assumptions
import _exact_enum as EE

# ---------------------------------------------------------------------------
# COUNTERFACTUAL (2026-09-10): what does the demand look like if the two
# CLASS-WIDE gate withdrawals that produce the width-20 sets are narrowed?
#
#   W-C  dispatch x *_not_found          (3 gate FAILs, withdrawn as a CLASS)
#   W-F  *_not_found x *_not_found, and  (3 gate FAILs, withdrawn as a CLASS)
#        *_not_found x var-var identity
#
# `_tier0c_dispatch_independence` already DECLARES dispatch-independence for
# every non-dispatch decision, and the batch declares finder foreclosure; both
# declarations are then thrown away for these classes by
# `_withdrawn_independence`. This run keeps every other withdrawal and only
# skips those two clauses, to price the artefact. It writes no summary and
# declares nothing -- it is a measurement of a counterfactual declaration set,
# NOT a claim that the narrowing is sound. Set NARROW=0 to reproduce the
# shipped declarations exactly.
# ---------------------------------------------------------------------------
_ORIG_WI = CA._withdrawn_independence
_NARROW = os.environ.get("NARROW", "1") != "0"


def _narrowed(ia):
    if not _NARROW:
        return _ORIG_WI(ia)
    a, b = ia.expr_a, ia.expr_b
    va, vb = (CA._leftvar(a) or ""), (CA._leftvar(b) or "")
    nf_a, nf_b = va.endswith("_not_found"), vb.endswith("_not_found")
    disp = bool(CA._DISPATCH_RE.match(a)) or bool(CA._DISPATCH_RE.match(b))
    if disp and (nf_a or nf_b):
        return False                       # W-C suspended
    if nf_a and nf_b:
        return False                       # W-F (not_found x not_found) suspended
    return _ORIG_WI(ia)


CA._withdrawn_independence = _narrowed

TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))
DIVERSE = re.compile(r"_(DV\d+|DIV\d+)")     # diverse-seed LABEL_SUFFIXes

args = sys.argv[1:]
def opt(f, d=None): return args[args.index(f) + 1] if f in args else d
SAMPLE = int(opt("--sample", 0)) or None
OUT = opt("--json-out", os.path.join(HERE, "_counterfactual.json"))
CUBE_CAP = int(opt("--cube-cap", "20000"))

t0 = time.time()
_LIST = os.environ.get("DUMP_LIST")
if _LIST:
    dumps = [l.strip() for l in open(_LIST) if l.strip()]
    print(f"DUMP_LIST {_LIST}: {len(dumps)} dump files (fixed snapshot)", flush=True)
    SAMPLE = None
else:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    print(f"corpus POPULATION: {len(dumps)} dump files", flush=True)
if SAMPLE:
    random.seed(20260910); dumps = sorted(random.sample(dumps, SAMPLE))
    print(f"SAMPLED {len(dumps)}", flush=True)
runs = []
for p in dumps:
    tag = "DIV" if DIVERSE.search(os.path.basename(p)) else "PLAIN"
    try:
        raw = json.load(open(p))
        CR.canonicalize_ordinals(raw)
        r = CR.share_run_objects(CR.apply_len_bounds(Run.from_dict(CR.fix_len_names(raw))))
        object.__setattr__(r, "label", tag)
        runs.append(r)
    except Exception:
        pass
    del raw
n_div = sum(1 for r in runs if r.label == "DIV")
print(f"loaded {len(runs)} runs: DIV={n_div} PLAIN={len(runs)-n_div} "
      f"({time.time()-t0:.0f}s)", flush=True)

A = build_assumptions(runs)
ck = CoverageChecker(runs, assumptions=A, max_cliques=int(os.environ.get("MAX_CLIQUES", "16384")))
rr = ck.runs
assert sum(1 for r in rr if r.label == "DIV") == n_div, "alias pass lost the DIV label"

expr_order, src = [], {}
prof = {}   # key -> [outcomes, div_seen, plain_seen, div_n, plain_n]
for r in rr:
    o = {}
    for pc in r.path_conditions:
        if pc.expr not in src:
            expr_order.append(pc.expr)
            src[pc.expr] = pc.source if isinstance(pc.source, PathSource) else None
        o.setdefault(pc.expr, set()).add(bool(pc.taken))
    if not o:
        continue
    k = frozenset((e, frozenset(v)) for e, v in o.items())
    rec = prof.get(k)
    if rec is None:
        rec = prof[k] = [o, False, False, 0, 0]
    if r.label == "DIV":
        rec[1] = True; rec[3] += 1
    else:
        rec[2] = True; rec[4] += 1
P = list(prof.values())
print(f"distinct profiles {len(P)} "
      f"(DIV-only {sum(1 for x in P if x[1] and not x[2])}, "
      f"PLAIN-only {sum(1 for x in P if x[2] and not x[1])}, "
      f"both {sum(1 for x in P if x[1] and x[2])})", flush=True)

decls = ck._merged_declarations()
fixed_base = list(A.symbolic_constraints()) + ck._merged_bounds()
parse = [e for e in expr_order
         if check_satisfiability([f"Or({e}, Not({e}))"], decls, TIMEOUT).satisfiable]
unt, pin, act = [], {}, []
for e in parse:
    s = src[e]
    if A.is_untracked(s, e):
        unt.append(e); continue
    for side, oc in (("taken", True), ("not_taken", False)):
        if A.is_one_side_untracked(s, side, e):
            pin[e] = not oc
    act.append(e)
adj = {e: set() for e in act}
for i, a in enumerate(act):
    for b in act[i+1:]:
        if A.are_independent(src[a], src[b], a, b):
            continue
        adj[a].add(b); adj[b].add(a)
aset = set(act)
ev = maximal_sets(frozenset(e for e in o if e in aset) for o, *_ in P)
proj = []
for s in ev:
    if all(len(adj[v] & s) == len(s) - 1 for v in s):
        proj.append(s); continue
    proj.extend(frozenset(p) for p in _maximal_cliques(sorted(s), {v: adj[v] & s for v in s}, cap=16384))
G = [sorted(d) for d in maximal_sets(proj)]
print(f"nodes={len(expr_order)} active={len(act)} untracked={len(unt)} pinned={len(pin)} "
      f"eval sets={len(ev)} demand sets={len(G)} ({time.time()-t0:.0f}s)", flush=True)

known = EE.var_index(decls); vcache, memo = {}, {}

# ---- tree completeness, split by arm -------------------------------------
sides_all, sides_div = {}, {}
for o, dv, pl, _dn, _pn in P:
    for e, v in o.items():
        if e not in aset: continue
        sides_all.setdefault(e, set()).update(v)
        if dv: sides_div.setdefault(e, set()).update(v)
tree_missing, tree_missing_div_only = [], []
for e in act:
    for oc in (True, False):
        if pin.get(e, oc) != oc: continue
        if oc in sides_all.get(e, ()): 
            if oc not in sides_div.get(e, ()): tree_missing_div_only.append(f"{e} :: {'taken' if oc else 'not_taken'}")
            continue
        if check_satisfiability(list(fixed_base) + ([e] if oc else [f"Not({e})"]), decls, TIMEOUT).satisfiable:
            tree_missing.append(f"{e} :: {'taken' if oc else 'not_taken'}")
print(f"TREE_COMPLETE={not tree_missing} tree_missing={len(tree_missing)}", flush=True)
for x in tree_missing: print("   MISSING-BRANCH", x, flush=True)

# ---- per demand set -------------------------------------------------------
def covered_of(cubes, cm):
    cov, disj, bound = 0, [], False
    for cube in sorted(cubes, key=len):
        d = dict(cube); pieces = [d]
        for prev in disj:
            nxt = []
            for p in pieces:
                s = EE.subtract([p], prev, CUBE_CAP)
                if s is None: return cov, True
                nxt.extend(s)
            pieces = nxt
            if len(pieces) > CUBE_CAP: return cov, True
        for p in pieces: cov += EE.cube_count(cm, p)
        disj.append(d)
    return cov, bound

tot = dict(sat=0, cov=0, cov_div=0, cov_plain=0)
per, zero_detail, bounded = [], [], 0
for gi, g in enumerate(G):
    comps = EE.components(g, known, vcache)
    cm = [EE.comp_models(c, fixed_base, decls, pin, memo) for c in comps]
    sat = 1
    for _k, ms in cm: sat *= len(ms)
    cs = set(g)
    cubes_all, cubes_div, cubes_plain = set(), set(), set()
    walk_div = walk_plain = 0        # RUNS (not profiles) that walk this set
    for o, dv, pl, _dn, _pn in P:
        if not all(o.get(e) for e in cs): continue
        cube = tuple(sorted((e, next(iter(o[e]))) for e in g if len(o[e]) == 1))
        cubes_all.add(cube)
        walk_div += _dn; walk_plain += _pn
        if dv: cubes_div.add(cube)
        if pl: cubes_plain.add(cube)
    cov, b = covered_of(cubes_all, cm)
    cov_d, _ = covered_of(cubes_div, cm)
    cov_p, _ = covered_of(cubes_plain, cm)
    if b: bounded += 1
    tot["sat"] += sat; tot["cov"] += cov; tot["cov_div"] += cov_d; tot["cov_plain"] += cov_p
    per.append(dict(i=gi, width=len(g), comps=len(comps), sat=sat, covered=cov,
                    covered_div=cov_d, covered_plain=cov_p, bound=b,
                    cubes=len(cubes_all), cubes_div=len(cubes_div),
                    cubes_plain=len(cubes_plain),
                    walk_div=walk_div, walk_plain=walk_plain))
    if cov == 0 and cubes_all:
        zero_detail.append(dict(i=gi, width=len(g), sat=str(sat),
                                exprs=list(g), cubes=[list(x) for x in sorted(cubes_all)]))
    # PIN DIAGNOSIS (only for the wide sets — this is what a STOP verdict has
    # to name): within THIS set's observed cubes, which member decisions were
    # never seen both ways, in the whole corpus and in the diverse arm alone.
    if len(g) >= 13:
        def _sides(cubes):
            d = {}
            for cb in cubes:
                for e, v in cb:
                    d.setdefault(e, set()).add(v)
            return d
        sa, sd = _sides(cubes_all), _sides(cubes_div)
        per[-1]["pinned_all"] = sorted(e for e in g if len(sa.get(e, ())) < 2)
        per[-1]["pinned_div"] = sorted(e for e in g if len(sd.get(e, ())) < 2)
        per[-1]["free_all"] = len(g) - len(per[-1]["pinned_all"])
        per[-1]["free_div"] = len(g) - len(per[-1]["pinned_div"])
    if gi % 200 == 0:
        print(f"  [{gi}/{len(G)}] w={len(g)} sat={sat} cov={cov} "
              f"cubes {len(cubes_all)} (div {len(cubes_div)} / plain {len(cubes_plain)}) "
              f"[{time.time()-t0:.0f}s]", flush=True)

wide = sorted(per, key=lambda p: (-p["width"], -p["sat"]))[:12]
print("\n=== WIDEST DEMAND SETS — the decisive rows ===", flush=True)
print(f"{'w':>3} {'sat':>8} {'cov':>7} {'cubesALL':>8} {'cubesDIV':>8} {'cubesPLAIN':>10} "
      f"{'covDIV':>7} {'covPLAIN':>8}", flush=True)
for p in wide:
    print(f"{p['width']:>3} {p['sat']:>8} {p['covered']:>7} {p['cubes']:>8} "
          f"{p['cubes_div']:>8} {p['cubes_plain']:>10} {p['covered_div']:>7} "
          f"{p['covered_plain']:>8}  walkDIV={p.get('walk_div')} "
          f"walkPLAIN={p.get('walk_plain')}  free_all={p.get('free_all')} "
          f"free_div={p.get('free_div')}", flush=True)
print("\n=== PIN DIAGNOSIS — decisions NEVER seen both ways inside the widest sets ===", flush=True)
for p in wide[:4]:
    print(f"  set#{p['i']} width={p['width']} sat={p['sat']} cubes={p['cubes']}: "
          f"{len(p.get('pinned_all', []))} of {p['width']} decisions are PINNED "
          f"(corpus-wide, inside this set)", flush=True)
    for e in p.get("pinned_all", []):
        print("      PINNED:", e, flush=True)

w13 = [p for p in per if p["width"] >= 13]
print(f"\nwidth>=13 sets: {len(w13)}; sat={sum(p['sat'] for p in w13)} "
      f"cov={sum(p['covered'] for p in w13)} "
      f"cubesALL={sum(p['cubes'] for p in w13)} "
      f"cubesDIV={sum(p['cubes_div'] for p in w13)} "
      f"cubesPLAIN={sum(p['cubes_plain'] for p in w13)}", flush=True)
print(f"\nEXACT: nodes={len(act)} demand_sets={len(G)} satisfiable={tot['sat']} "
      f"covered={tot['cov']} remaining={tot['sat']-tot['cov']} "
      f"uncovered={100.0*(tot['sat']-tot['cov'])/max(1,tot['sat']):.2f}% "
      f"covered_DIVonly={tot['cov_div']} covered_PLAINonly={tot['cov_plain']} "
      f"zero_covered={len(zero_detail)} bounded={bounded} wall={time.time()-t0:.0f}s", flush=True)
if zero_detail:
    print("\n=== ZERO-COVERED (observed cubes UNSAT under the declared model) ===", flush=True)
    for z in zero_detail:
        print(f"  set#{z['i']} width={z['width']} sat={z['sat']}", flush=True)
        for e in z["exprs"]: print("      expr:", e, flush=True)
        for c in z["cubes"]: print("      cube:", c, flush=True)

json.dump({"runs": len(rr), "runs_div": n_div, "nodes": len(act),
           "demand_sets": len(G), "satisfiable": str(tot["sat"]),
           "covered": str(tot["cov"]), "covered_div": str(tot["cov_div"]),
           "covered_plain": str(tot["cov_plain"]),
           "remaining": str(tot["sat"] - tot["cov"]),
           "zero_covered": len(zero_detail), "zero_covered_detail": zero_detail,
           "tree_complete": not tree_missing, "tree_missing": tree_missing,
           "bounded": bounded,
           "per_set": [dict(p, sat=str(p["sat"]), covered=str(p["covered"]),
                            covered_div=str(p["covered_div"]),
                            covered_plain=str(p["covered_plain"])) for p in per]},
          open(OUT, "w"), indent=1)
print("wrote", OUT, flush=True)
