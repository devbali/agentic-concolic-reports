#!/usr/bin/env python3
"""_conf_precision_* scratch tool (2026-09-13, read-only analysis).

Re-measures §16c footprints on a UNIFORM SAMPLE of one endpoint's corpus in
TWO shape currencies:

  coarse  = call_shape(target, None, None)      -- what the batch loader's
            `fix_len_names` (which pops `note` and `args`) actually feeds the
            engine today: the target method name alone.
  fine    = call_shape(target, note, args)      -- §16c's stated currency and
            the currency the assumption gate's `access_trace` measures in.

Emits per-decision footprint size + matched-context count (`ctxn`) in both,
so the gate's PASS/FAIL verdicts can be split by support.

Writes nothing into any endpoint directory.
"""
import json, os, sys, random, collections, argparse

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import call_shape, shape_str, alias_map_for, renamer  # noqa
from concolic_engine.coverage import infer_footprints, infer_footprints_coevaluated  # noqa

ap = argparse.ArgumentParser()
ap.add_argument("--batch", required=True)
ap.add_argument("--snapshot", required=True)
ap.add_argument("--n", type=int, default=10000)
ap.add_argument("--out", required=True)
ap.add_argument("--seed", type=int, default=20260913)
a = ap.parse_args()

sys.path.insert(0, a.batch)
from coverage_assumptions import ALIASES  # noqa

paths = [l.strip() for l in open(a.snapshot) if l.strip()]
random.Random(a.seed).shuffle(paths)
paths = paths[: a.n]

_LEN_RE = __import__("re").compile(r"len\(([^()]+)\)")

def load(p):
    with open(p) as fh:
        d = json.load(fh)
    evs = [(e.get("result_name"), e.get("note"))
           for e in d.get("events") or () if e.get("type") == "symbolic_call"]
    amap = alias_map_for(evs, ALIASES)
    if amap:
        rn = renamer(amap)
        for e in d.get("events") or ():
            for k in ("expr", "result_name", "note"):
                if e.get(k):
                    e[k] = rn(e[k])
    out, tr_c, tr_f = {}, [], []
    for e in d.get("events") or ():
        t = e.get("type")
        if t == "path_condition":
            x = e.get("expr")
            if not x:
                continue
            if "len(" in x:
                x = _LEN_RE.sub(r"SYM_LEN_\1", x)
            out.setdefault(x, set()).add(bool(e.get("taken")))
        elif t == "symbolic_call" and e.get("result_name"):
            tgt = e.get("target")
            tr_c.append(call_shape(tgt, None, None))
            tr_f.append(call_shape(tgt, e.get("note"), e.get("args")))
    return out, tr_c, tr_f

profiles, run_outcomes = {}, []
pu = {"coarse": [], "fine": []}
pi = {"coarse": [], "fine": []}
sid = {"coarse": {}, "fine": {}}
nerr = 0
for i, p in enumerate(paths):
    try:
        out, tc, tf = load(p)
    except Exception:
        nerr += 1
        continue
    if not out:
        continue
    masks = {}
    for kind, tr in (("coarse", tc), ("fine", tf)):
        m = 0
        for sh in tr:
            j = sid[kind].get(sh)
            if j is None:
                j = sid[kind][sh] = len(sid[kind])
            m |= 1 << j
        masks[kind] = m
    key = tuple(sorted((e, tuple(sorted(v))) for e, v in out.items()))
    k = profiles.get(key)
    if k is None:
        profiles[key] = len(run_outcomes)
        run_outcomes.append(out)
        for kind in ("coarse", "fine"):
            pu[kind].append(masks[kind]); pi[kind].append(masks[kind])
    else:
        for kind in ("coarse", "fine"):
            pu[kind][k] |= masks[kind]; pi[kind][k] &= masks[kind]

expr_order = []
seen = set()
for o in run_outcomes:
    for e in o:
        if e not in seen:
            seen.add(e); expr_order.append(e)

res = {"batch": a.batch, "sampled": len(paths), "errors": nerr,
       "profiles": len(run_outcomes), "exprs": len(expr_order),
       "shapes": {k: len(v) for k, v in sid.items()}, "decisions": {}}
for kind in ("coarse", "fine"):
    fp, ctx = infer_footprints(expr_order, expr_order, run_outcomes, pu[kind], pi[kind])
    rest = [e for e in expr_order if not ctx.get(e)]
    fp2, ctx2 = infer_footprints_coevaluated(rest, expr_order, run_outcomes,
                                             pu[kind], pi[kind]) if rest else ({}, {})
    coev = set()
    for e, m in fp2.items():
        fp[e] = m; ctx[e] = ctx2[e]; coev.add(e)
    for e in expr_order:
        d = res["decisions"].setdefault(e, {})
        d[kind] = {"ctxn": ctx.get(e, 0),
                   "fp": bin(fp[e]).count("1") if e in fp else None,
                   "coeval": e in coev}
json.dump(res, open(a.out, "w"))
print(f"sampled={len(paths)} errors={nerr} profiles={len(run_outcomes)} "
      f"exprs={len(expr_order)} coarse_shapes={len(sid['coarse'])} fine_shapes={len(sid['fine'])}")
