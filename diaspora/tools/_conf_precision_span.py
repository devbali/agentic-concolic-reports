#!/usr/bin/env python3
"""_conf_precision_* scratch tool (2026-09-13, read-only analysis) -- part 3.

CONTEXT SPAN. `infer_footprints` measures a decision's footprint as a
differential over MATCHED CONTEXTS (profile pairs that agree on every other
evaluated expression and differ only in D). This tool measures, per decision
and in the FINE currency:

  reach(D) = union of the trace masks of every profile that evaluates D
             single-sided
  span(D)  = union of the trace masks of the profiles that actually sit in one
             of D's matched contexts (the only runs the differential can see)
  blind(D) = reach(D) \\ span(D)  -- shapes D co-occurs with that NO matched
             context contains, so the differential is structurally unable to
             put them in, or keep them out of, the footprint.

A footprint measured with blind(D) non-empty is measured on a sub-region of the
decision's own corpus. Writes nothing into any endpoint directory.
"""
import json, sys, random, re, argparse

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import call_shape, alias_map_for, renamer, shape_str  # noqa

ap = argparse.ArgumentParser()
ap.add_argument("--batch", required=True)
ap.add_argument("--snapshot", required=True)
ap.add_argument("--n", type=int, default=20000)
ap.add_argument("--out", required=True)
ap.add_argument("--seed", type=int, default=20260913)
a = ap.parse_args()
sys.path.insert(0, a.batch)
try:
    from coverage_assumptions import ALIASES  # noqa
except Exception:
    ALIASES = []

paths = [l.strip() for l in open(a.snapshot) if l.strip()]
random.Random(a.seed).shuffle(paths)
paths = paths[: a.n]
_LEN_RE = re.compile(r"len\(([^()]+)\)")

profiles, run_outcomes, pu, pi, sid = {}, [], [], [], {}
for p in paths:
    try:
        with open(p) as fh:
            d = json.load(fh)
    except Exception:
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
    out, m = {}, 0
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
            sh = call_shape(e.get("target"), e.get("note"), e.get("args"))
            j = sid.get(sh)
            if j is None:
                j = sid[sh] = len(sid)
            m |= 1 << j
    if not out:
        continue
    key = tuple(sorted((e_, tuple(sorted(v))) for e_, v in out.items()))
    k = profiles.get(key)
    if k is None:
        profiles[key] = len(run_outcomes)
        run_outcomes.append(out); pu.append(m); pi.append(m)
    else:
        pu[k] |= m; pi[k] &= m

universe, seen = [], set()
for o in run_outcomes:
    for e in o:
        if e not in seen:
            seen.add(e); universe.append(e)
ubit = {e: i for i, e in enumerate(universe)}
pev, ptk, pbo = [], [], []
for outcomes in run_outcomes:
    ev = tk = bo = 0
    for e, os_ in outcomes.items():
        b = 1 << ubit[e]
        ev |= b
        if len(os_) > 1:
            bo |= b
        elif True in os_:
            tk |= b
    pev.append(ev); ptk.append(tk); pbo.append(bo)

names = {v: k for k, v in sid.items()}
res = {"profiles": len(run_outcomes), "shapes": len(sid), "decisions": {}}
for dexp in universe:
    b = 1 << ubit[dexp]
    buckets, reach = {}, 0
    for i, ev in enumerate(pev):
        if not (ev & b) or (pbo[i] & b):
            continue
        reach |= pu[i]
        key = (ev & ~b, ptk[i] & ~b, pbo[i])
        sl = buckets.setdefault(key, [-1, -1])
        sl[1 if ptk[i] & b else 0] = i
    span, nctx, fpm = 0, 0, 0
    for it, if_ in buckets.values():
        if it < 0 or if_ < 0:
            continue
        nctx += 1
        span |= pu[it] | pu[if_]
        fpm |= (pu[it] & ~pi[if_]) | (pu[if_] & ~pi[it])
    blind = reach & ~span
    res["decisions"][dexp] = {
        "ctxn": nctx, "reach": bin(reach).count("1"), "span": bin(span).count("1"),
        "blind": bin(blind).count("1"), "fp": bin(fpm).count("1"),
        "blind_shapes": [shape_str(names[j]) for j in range(len(names)) if blind >> j & 1][:40],
        # shapes the decision reaches, are NOT in its footprint, and the
        # contexts DID span -- genuinely measured absent
        "measured_absent": bin(span & ~fpm & reach).count("1"),
        "fp_hex": "%x" % fpm, "fpprime_hex": "%x" % (fpm | blind), "reach_hex": "%x" % reach,
    }
json.dump(res, open(a.out, "w"))
dec = [v for v in res["decisions"].values() if v["ctxn"]]
print(f"profiles={res['profiles']} shapes={res['shapes']} decided={len(dec)} "
      f"blind>0: {sum(1 for v in dec if v['blind'])}/{len(dec)}")
