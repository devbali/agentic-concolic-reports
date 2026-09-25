#!/usr/bin/env python3
"""_conf_precision_* part 4 (2026-09-13) — the FOUR-WAY CONFUSION MATRIX.

Scores each of the four criteria of `docs/CONFINEMENT_PRECISION_20260913.md`
§5.1 against the assumption gate's own verdicts, on one endpoint's corpus:

  A  today      coarse currency (the batch loader pops note/args),
                unobserved="withhold", the co-evaluated fallback LICENSES
  B  C1         fine currency (note/args kept), otherwise A
  C  C1+C2      + unobserved="attribute"  (fp | (reach & ~span))
  D  C1+C2+C3   + the fallback measures but does not licence (fp = reach)
  E  C1+C3      the report's row F, for comparison

Positive = "the criterion licenses the pair"; TP = licensed and the gate
PASSed, FP = licensed and the gate FAILed (a FALSE LICENCE — the column that
must be zero), FN = refused although the gate PASSed, TN = refused and the
gate FAILed.

The licensing logic is the engine's own, called through the engine's own
helpers (`infer_footprints`, `infer_footprints_coevaluated`,
`infer_pair_tables`, `classify_cells`) with the same knobs
`project_confinement` now takes, so a difference here is a difference in the
engine and not in a reimplementation.

Read-only. Writes only where --out points.
"""
import argparse
import json
import random
import re
import sys

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import call_shape, alias_map_for, renamer, shape_str  # noqa
from concolic_engine.coverage import (infer_footprints, infer_footprints_coevaluated,  # noqa
                                      infer_pair_tables, classify_cells, _BENIGN)

# name -> (currency, unobserved, fallback mode)
#   fallback "licence"  the co-evaluated fallback footprint LICENSES (today)
#   fallback "reach"    C3 as `docs/CONFINEMENT_PRECISION_20260913.md` §5
#                       writes it: fp = reach for a fallback-decided decision
#   fallback "refuse"   the stricter reading of the same sentence ("the
#                       fallback is not a licence"): a pair with a
#                       fallback-only MEMBER is refused outright, whatever
#                       reach says and whatever the 2x2 says
#   fallback "exact"    the fallback is not COMPUTED at all -- the engine's
#                       existing `confinement_keying="exact"`. Licensing-
#                       equivalent to "refuse" (a decision with no exact
#                       context is then UNDECIDABLE, so it is in no pair and
#                       `infer_pair_tables` never sees it), and this run
#                       CHECKS that equivalence rather than assuming it.
CRITERIA = {
    "A_today":        ("coarse", "withhold",  "licence"),
    "B_C1":           ("fine",   "withhold",  "licence"),
    "C_C1C2":         ("fine",   "attribute", "licence"),
    "D_C1C2C3reach":  ("fine",   "attribute", "reach"),
    "D2_C1C2C3ref":   ("fine",   "attribute", "refuse"),
    "D3_C1C2C3exact": ("fine",   "attribute", "exact"),
    "E_C1C3reach":    ("fine",   "withhold",  "reach"),
    "E2_C1C3ref":     ("fine",   "withhold",  "refuse"),
    "E3_C1C3exact":   ("fine",   "withhold",  "exact"),
}

ap = argparse.ArgumentParser()
ap.add_argument("--batch", required=True)
ap.add_argument("--snapshot", required=True)
ap.add_argument("--verdicts", required=True)
ap.add_argument("--n", type=int, default=20000)
ap.add_argument("--seed", type=int, default=20260913)
ap.add_argument("--out", required=True)
ap.add_argument("--criteria", default="", help="comma-separated subset of CRITERIA")
ap.add_argument("--all-pairs", action="store_true",
                help="also count the licence over EVERY co-evaluated decided "
                     "pair, not only the probed ones -- the demand-cost number")
a = ap.parse_args()
if a.criteria:
    keep = set(a.criteria.split(","))
    CRITERIA = {k: v for k, v in CRITERIA.items() if k in keep}
sys.path.insert(0, a.batch)
try:
    from coverage_assumptions import ALIASES        # noqa
except Exception:
    ALIASES = []

# ---------------------------------------------------------------- the corpus
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
                             ("fine", call_shape(e.get("target"), e.get("note"),
                                                 e.get("args")))):
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
            side[kind].setdefault(e_, [0, 0, 0])[k] |= masks[kind]
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

# ------------------------------------------------------------- gate verdicts
rows = json.load(open(a.verdicts))
verdict = {}
for r in rows:
    if r.get("type") != "ConfinementAssumption":
        continue
    verdict[tuple(sorted((r["expr"], r["expr_b"])))] = r["verdict"]
probed = set(verdict)

# ------------------------------------------------------------- the criteria
def licence_sets(currency, unobserved, fallback):
    """The engine's own licensing, exactly as `project_confinement` does it."""
    fp, ctx = infer_footprints(expr_order, expr_order, run_outcomes,
                               pu[currency], pi[currency], unobserved=unobserved)
    coeval = set()
    rest = [] if fallback == "exact" else [e for e in expr_order if not ctx.get(e)]
    if rest:
        reach2 = {} if fallback == "reach" else None
        fp2, ctx2 = infer_footprints_coevaluated(
            rest, expr_order, run_outcomes, pu[currency], pi[currency],
            unobserved=unobserved, reach_out=reach2)
        for e, m in fp2.items():
            fp[e] = m if reach2 is None else (m | reach2[e])
            ctx[e] = ctx2[e]
            coeval.add(e)
    disq = set()
    for e, m in fp.items():
        sl = side[currency].get(e, [0, 0, 0])
        if m & ((sl[0] & sl[1]) | sl[2]):
            disq.add(e)
    if a.all_pairs:
        tables = infer_pair_tables(sorted(fp), run_outcomes, pu[currency])
    else:
        names = sorted({e for q in probed for e in q} & set(fp))
        tables = infer_pair_tables(names, run_outcomes, pu[currency])
        tables = {k: v for k, v in tables.items() if tuple(sorted(k)) in probed}
    ok = {e for e in fp if e not in disq}
    strict, orlic = set(), set()
    for (x, y), cells in tables.items():
        if fallback == "refuse" and (x in coeval or y in coeval):
            continue                       # a fallback-only member: no licence
        fx, fy = fp[x], fp[y]
        if x in ok and y in ok and not (fx & fy):
            strict.add(tuple(sorted((x, y))))
            continue
        bad = False
        z = fx | fy
        while z:
            b = z & -z; j = b.bit_length() - 1; z ^= b
            cls = classify_cells({k2: (1 if v[0] >> j & 1 else 0)
                                  for k2, v in cells.items()})
            if cls not in _BENIGN and cls != "OR-family":
                bad = True
                break
        if not bad:
            orlic.add(tuple(sorted((x, y))))
    return (strict | orlic), set(tables), fp, ctx, coeval, disq, strict, orlic


res = {"batch": a.batch, "sampled": len(paths), "errors": nerr,
       "profiles": len(run_outcomes), "exprs": len(expr_order),
       "shapes": {k: len(v) for k, v in sid.items()},
       "probed_pairs": len(probed),
       "gate": {"PASS": sum(1 for v in verdict.values() if v == "PASS"),
                "FAIL": sum(1 for v in verdict.values() if v == "FAIL"),
                "other": sum(1 for v in verdict.values()
                             if v not in ("PASS", "FAIL"))},
       "criteria": {}}

for name, (cur, unobs, fbk) in CRITERIA.items():
    lic, scorable, fp, ctx, coeval, disq, strict, orlic = licence_sets(cur, unobs, fbk)
    tp = fp_ = fn = tn = 0
    fps = []
    for pair, v in verdict.items():
        if pair not in scorable:
            continue
        # (with --all-pairs `scorable` is every co-evaluated decided pair, so
        # the probed ones are a subset of it and the matrix is unchanged)
        L = pair in lic
        if v == "PASS":
            tp += L; fn += (not L)
        elif v == "FAIL":
            if L:
                fp_ += 1; fps.append(pair)
            else:
                tn += 1
    prec = tp / (tp + fp_) if (tp + fp_) else None
    rec = tp / (tp + fn) if (tp + fn) else None
    res["criteria"][name] = {
        "currency": cur, "unobserved": unobs, "fallback": fbk,
        "strict_licensed": len(strict), "or_licensed": len(orlic),
        "probed_with_coeval_member": sum(
            1 for q in scorable if q[0] in coeval or q[1] in coeval),
        "scorable": len(scorable), "licensed_of_scorable": len(lic),
        "TP": tp, "FP": fp_, "FN": fn, "TN": tn,
        "precision": prec, "recall": rec,
        "decided": len(fp), "coeval_only": len(coeval), "disqualified": len(disq),
        "false_licences": ["\t".join(q) for q in sorted(fps)],
        "licensed": ([] if a.all_pairs else ["\t".join(q) for q in sorted(lic)]),
        "all_pairs_seen": len(scorable) if a.all_pairs else None,
        "all_pairs_licensed": len(lic) if a.all_pairs else None,
    }
    print(f"{name:15s} cur={cur:6s} unobs={unobs:9s} fb={fbk:7s} "
          f"scorable={len(scorable):4d} lic={len(lic):4d}"
          f"(s{len(strict)}/o{len(orlic)}) coevmem="
          f"{sum(1 for q in scorable if q[0] in coeval or q[1] in coeval):3d} "
          f"TP={tp:3d} FP={fp_:3d} FN={fn:3d} TN={tn:3d} "
          f"prec={prec if prec is None else round(prec,3)} "
          f"rec={rec if rec is None else round(rec,3)}")

json.dump(res, open(a.out, "w"))
print(f"shapes coarse={len(sid['coarse'])} fine={len(sid['fine'])} "
      f"profiles={len(run_outcomes)} exprs={len(expr_order)}")
