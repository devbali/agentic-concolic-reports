#!/usr/bin/env python3
"""_conf_precision_* scratch tool (2026-09-13, read-only analysis) -- part 2.

Same uniform sample as `_conf_precision_sample.py`, but it also runs the
engine's OWN pairing (strict counterexample search + infer_pair_tables /
classify_cells OR licence) over ALL co-evaluated pairs of decided decisions,
in BOTH shape currencies:

  coarse = call_shape(target, None, None)  -- what the batch loader's
           `fix_len_names` (it pops `note` and `args`) actually feeds the
           engine today: the target method name alone.
  fine   = call_shape(target, note, args)  -- §16c's stated currency, and the
           one the assumption gate's `access_trace` measures in.

and under an optional NON-VACUOUS rule (an empty decided footprint is not a
licence). Writes nothing into any endpoint directory.
"""
import json, os, sys, random, re, argparse

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import call_shape, alias_map_for, renamer   # noqa
from concolic_engine.coverage import (infer_footprints, infer_footprints_coevaluated,
                                      infer_pair_tables, classify_cells, _BENIGN)  # noqa

SEP = "\t"

ap = argparse.ArgumentParser()
ap.add_argument("--batch", required=True)
ap.add_argument("--snapshot", required=True)
ap.add_argument("--n", type=int, default=20000)
ap.add_argument("--out", required=True)
ap.add_argument("--seed", type=int, default=20260913)
ap.add_argument("--pairs", default="")
a = ap.parse_args()
sys.path.insert(0, a.batch)
try:
    from coverage_assumptions import ALIASES  # noqa
except Exception:
    ALIASES = []   # this batch declares no alias layer

paths = [l.strip() for l in open(a.snapshot) if l.strip()]
random.Random(a.seed).shuffle(paths)
paths = paths[: a.n]
_LEN_RE = re.compile(r"len\(([^()]+)\)")

profiles, run_outcomes = {}, []
pu = {"coarse": [], "fine": []}
pi = {"coarse": [], "fine": []}
sid = {"coarse": {}, "fine": {}}
side = {"coarse": {}, "fine": {}}
nerr = 0
for p in paths:
    try:
        with open(p) as fh:
            d = json.load(fh)
    except Exception:
        nerr += 1
        continue
    evs = [(e.get("result_name"), e.get("note"))
           for e in d.get("events") or () if e.get("type") == "symbolic_call"]
    amap = alias_map_for(evs, ALIASES)
    if amap:
        rn = renamer(amap)
        for e in d.get("events") or ():
            for k in ("expr", "result_name", "note"):
                if e.get(k):
                    e[k] = rn(e[k])
    out, masks = {}, {"coarse": 0, "fine": 0}
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
            for kind, sh in (("coarse", call_shape(e.get("target"), None, None)),
                             ("fine", call_shape(e.get("target"), e.get("note"), e.get("args")))):
                j = sid[kind].get(sh)
                if j is None:
                    j = sid[kind][sh] = len(sid[kind])
                masks[kind] |= 1 << j
    if not out:
        continue
    for kind in ("coarse", "fine"):
        if not masks[kind]:
            continue
        for e_, os_ in out.items():
            k = 2 if len(os_) > 1 else (1 if True in os_ else 0)
            sl = side[kind].setdefault(e_, [0, 0, 0])
            sl[k] |= masks[kind]
    key = tuple(sorted((e_, tuple(sorted(v))) for e_, v in out.items()))
    k = profiles.get(key)
    if k is None:
        profiles[key] = len(run_outcomes)
        run_outcomes.append(out)
        for kind in ("coarse", "fine"):
            pu[kind].append(masks[kind]); pi[kind].append(masks[kind])
    else:
        for kind in ("coarse", "fine"):
            pu[kind][k] |= masks[kind]; pi[kind][k] &= masks[kind]

expr_order, seen = [], set()
for o in run_outcomes:
    for e in o:
        if e not in seen:
            seen.add(e); expr_order.append(e)

res = {"sampled": len(paths), "errors": nerr, "profiles": len(run_outcomes),
       "exprs": len(expr_order), "shapes": {k: len(v) for k, v in sid.items()},
       "modes": {}, "fp": {}, "ctxn": {}, "licensed": {}, "licensed_nv": {}}
for kind in ("coarse", "fine"):
    fp, ctx = infer_footprints(expr_order, expr_order, run_outcomes, pu[kind], pi[kind])
    rest = [e for e in expr_order if not ctx.get(e)]
    if rest:
        fp2, ctx2 = infer_footprints_coevaluated(rest, expr_order, run_outcomes,
                                                 pu[kind], pi[kind])
        for e, m in fp2.items():
            fp[e] = m; ctx[e] = ctx2[e]
    disq = set()
    for e, m in fp.items():
        sl = side[kind].get(e, [0, 0, 0])
        if m & ((sl[0] & sl[1]) | sl[2]):
            disq.add(e)
    if a.pairs:
        want_pairs = {tuple(sorted(q)) for q in json.load(open(a.pairs))}
        nm2 = sorted({e for q in want_pairs for e in q} & set(fp))
        tables = infer_pair_tables(nm2, run_outcomes, pu[kind])
        tables = {k2: v for k2, v in tables.items() if tuple(sorted(k2)) in want_pairs}
    else:
        tables = infer_pair_tables(list(fp), run_outcomes, pu[kind])
    ok = {e for e in fp if e not in disq}
    strict, orlic = set(), set()
    for (x, y), cells in tables.items():
        fx, fy = fp[x], fp[y]
        if x in ok and y in ok and not (fx & fy):
            strict.add((x, y)); continue
        bad = False
        z = fx | fy
        while z:
            b = z & -z; j = b.bit_length() - 1; z ^= b
            cls = classify_cells({k2: (1 if v[0] >> j & 1 else 0) for k2, v in cells.items()})
            if cls not in _BENIGN and cls != "OR-family":
                bad = True; break
        if not bad:
            orlic.add((x, y))
        else:
            res.setdefault("refused", {}).setdefault(kind, []).append(SEP.join((x, y)))
    allp = strict | orlic
    nonvac = {(x, y) for (x, y) in allp if fp.get(x) and fp.get(y)}
    res["modes"][kind] = {
        "decided": len(fp), "undecidable": len(expr_order) - len(fp),
        "empty_fp": sum(1 for m in fp.values() if m == 0),
        "disqualified": len(disq), "coeval_pairs_seen": len(tables),
        "strict_pairs": len(strict), "or_pairs": len(orlic),
        "licensed_pairs": len(allp), "licensed_nonvacuous": len(nonvac)}
    res["fp"][kind] = {e: bin(m).count("1") for e, m in fp.items()}
    if kind == "fine":
        from concolic_engine.assumptions import shape_str as _ss
        _nm = {v: k for k, v in sid["fine"].items()}
        res["fp_shapes_fine"] = {e: [_ss(_nm[j]) for j in range(len(_nm)) if m >> j & 1]
                                 for e, m in fp.items()}
    res["ctxn"][kind] = ctx
    res["licensed"][kind] = sorted(SEP.join(q) for q in allp)
    res["licensed_nv"][kind] = sorted(SEP.join(q) for q in nonvac)
json.dump(res, open(a.out, "w"))
for k, v in res["modes"].items():
    print(k, v)
