#!/usr/bin/env python3
"""P42 — DOES THE B-4 BOUNDARY DEFECT DISTORT THE DEMAND STRUCTURE?

`call_shape(target, note, args)` builds the trace layer's SHAPE from the
NOTE.  When `sql_for` rescued and stored the exception text, every Reshare
relation collapsed into ONE shape string instead of its own statement, so the
shape space the CONFINEMENT footprints are measured in is COARSENED exactly
there.  Coarsening makes footprints share shapes they would not otherwise
share, which (a) refuses OR-licences and (b) under `strict` can DISQUALIFY a
decision outright, and both INFLATE demand.

This prices that.  Arm `KEEP` is the shipped trace layer.  Arm `DROP` removes
the captured-exception shapes from the trace layer entirely -- the OPTIMISTIC
bound (had the boundary worked, those calls would have carried their own
distinct statements; dropping them is the most favourable thing that could
happen to confinement).  The gap between the arms is the blast radius of the
defect on the residue.

FALSIFIER: if DROP leaves REMAINING within 5 % of KEEP, the defect does not
materially distort the demand structure and the width work stands on this
corpus.

(derived from _p40_widthprobe2.py; the census machinery is unchanged)

OLD DOCSTRING — MULTI-ARM confinement-restoration census + demand-set anatomy.

ONE universe build (the expensive part, ~15 min), then the SAME `prod` census
run under SEVERAL withdrawal sets, so the arms are comparable by construction
(§103.5's rule: the only input that changes is the withdrawn set).

It answers two questions the brief puts first:

  Q1  how much of the 965 224 residue is attributable to the 86 UNEVIDENCED
      withdrawn pairs (60 N-T + 26 N-C) versus the 478 FAIL ones?
        arm W564  = the shipped withdrawal          -> must reproduce 998 /
                    1 039 416 / 74 192 / 965 224   (REPRODUCTION CHECK)
        arm W478  = FAIL + FAIL-PINNED only         -> the CEILING of lead 1
        arm W000  = nothing withdrawn               -> the ceiling of the whole
                    confinement-gate question (round 10's universe)
  Q2  what the widest demand sets actually CONTAIN — members dumped per set.

Derived from `_p26_emit_or.py` verbatim down to the projection; nothing in
`src/` is touched and nothing is declared.  Writes only where the OUT_* env
vars point.  Verdict line: `P40-WIDTHPROBE-DONE`.
"""
import json, os, sys, time, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

import _p23_enum as EE                                              # noqa: E402
from coverage_assumptions import build as build_assumptions         # noqa: E402
from concolic_engine.assumptions import call_shape, shape_str       # noqa: E402
from concolic_engine.coverage import project_confinement            # noqa: E402

MAX_CLIQUES = int(os.environ.get("MAX_CLIQUES", "16384"))
CUBE_CAP    = int(os.environ.get("CUBE_CAP", "20000"))
OUT_JSON    = os.environ.get("OUT_JSON", os.path.join(HERE, "_p40_widthprobe.json"))
OUT_SETS    = os.environ.get("OUT_SETS", os.path.join(HERE, "_p40_sets.json"))
ARMS        = [a for a in os.environ.get("ARMS", "W564").split(",") if a]

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, MAX_CLIQUES)
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s; 16b demand sets {len(U['cliques'])}", flush=True)

# ---- trace layer (verbatim from _p26_emit_or.py) --------------------------
pkey = getattr(EE, "_pkey", None)
if pkey is None:
    from concolic_engine.coverage import profile_key as pkey
idx, union, inter, shape_id, side_seen = {}, [], [], {}, {}
for run in U["runs"]:
    outcomes = {}
    for pc in run.path_conditions:
        outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
    if not outcomes:
        continue
    tr = 0
    for ev in run.symbolic_call_events:
        if not ev.result_name:
            continue
        sh = call_shape(ev.target_name, ev.note, ev.args)
        j = shape_id.get(sh)
        if j is None:
            j = shape_id[sh] = len(shape_id)
        tr |= 1 << j
    if tr:
        for e, os_ in outcomes.items():
            k = 2 if len(os_) > 1 else (1 if True in os_ else 0)
            side_seen.setdefault(e, [0, 0, 0])[k] |= tr
    k2 = pkey(outcomes)
    i = idx.get(k2)
    if i is None:
        idx[k2] = len(union); union.append(tr); inter.append(tr)
    else:
        union[i] |= tr; inter[i] &= tr
EXC_SHAPE = __import__("re").compile(r"render[_ ]relation[_ ]sql failed|undefined method [`']|NoMethodError")
_bad_ids = [j for sh, j in shape_id.items() if EXC_SHAPE.search(shape_str(sh))]
_bad_mask = 0
for j in _bad_ids:
    _bad_mask |= 1 << j
print(f"captured-exception call shapes in the trace layer: {len(_bad_ids)} of {len(shape_id)}", flush=True)
for sh, j in shape_id.items():
    if j in _bad_ids:
        print("   *", shape_str(sh)[:150], flush=True)
if os.environ.get("DROP_EXC_SHAPES") == "1":
    keep = ~_bad_mask
    union = [u & keep for u in union]
    inter = [u & keep for u in inter]
    for e, sl in side_seen.items():
        side_seen[e] = [v & keep for v in sl]
    print("DROP_EXC_SHAPES=1 — those shapes are removed from every trace mask", flush=True)

assert len(union) == len(U["run_outcomes"]), "profile index does not match the enumerator's"
print(f"trace layer: {len(shape_id)} distinct call shapes over {len(union)} profiles "
      f"({time.time()-t0:.0f}s)", flush=True)

# ---- the withdrawal arms --------------------------------------------------
# the pair -> gate-verdict map is precomputed by `_p40_pairsplit.py` (it needs
# the 369 MB summary; keeping that out of this process keeps the peak down).
W_ALL = [tuple(sorted(p)) for p in json.load(open(os.path.join(HERE, "_confinement_withdrawn.json")))]
PR = json.load(open(os.path.join(HERE, "_p40_pair_reasons.json")))
pair_row = {tuple(k.split("\x00")): v for k, v in PR.items()}
split = collections.Counter(pair_row.get(p, {}).get("verdict", "??") for p in W_ALL)
shape = collections.Counter(pair_row.get(p, {}).get("shape", "??") for p in W_ALL)
print("withdrawn-564 by gate verdict:", dict(split), flush=True)
print("withdrawn-564 by refutation shape:", dict(shape), flush=True)
assert split.get("??", 0) == 0, "some withdrawn pair has no gate verdict"

def sel(*shapes):
    return [p for p in W_ALL if pair_row[p]["shape"] in shapes]

ARMSETS = {
    # the shipped withdrawal -- REPRODUCTION CHECK against 998/1039416/74192/965224
    "W564":  W_ALL,
    # FAIL only: the 57 UNEVIDENCED pairs restored. The ceiling of lead 1.
    "WFAIL": sel("DOWNSTREAM", "LEAK", "REMOVAL", "OTHER"),
    # additive only: the 75 REMOVAL-shaped refutations restored too. X11 says a
    # removal-shaped dependence is FORECLOSURE, not a confinement refutation --
    # this arm is the SIZE of that modelling gap, not a licence.
    "WADD":  sel("DOWNSTREAM", "LEAK", "OTHER"),
    # only the refutations that hit §16c's OWN premise (a shape outside the
    # measured footprint moved).
    "WLEAK": sel("LEAK"),
    # nothing withdrawn: round 10's universe; the ceiling of the whole
    # confinement-gate question.
    "W000":  [],
}

known = EE.var_index(U["decls"])
vcache, memo = {}, {}
EE._LEAF_ENUM = False
os.environ["FORECLOSURE_CONJUNCTIONS"] = "0"
os.environ["FORECLOSURE_SUBCONJUNCTIONS"] = "0"
os.environ["FORECLOSURE_WELLFOUNDED_DROPS"] = "0"
EE._WF_ON = False
order = {e: i for i, e in enumerate(U["expr_order"])}
base_demands = [frozenset(c) for c in U["cliques"]]
names = [None] * len(shape_id)
for sh, j in shape_id.items():
    names[j] = shape_str(sh)

out = {"arms": {}, "split_564": dict(split)}
sets_dump = {}
for arm in ARMS:
    w = [tuple(sorted(p)) for p in ARMSETS[arm]]
    P = project_confinement(U["active"], U["expr_order"], U["run_outcomes"], union, inter,
                            side_seen, base_demands, U["by_gate"], U["bit"], MAX_CLIQUES,
                            strict=True, keying="coevaluated", protect_gates=False,
                            withdrawn=w, or_sharing=True)
    cliques = [sorted(d, key=order.__getitem__) for d in P["demands"]]
    r = EE.census(U, cliques, known, vcache, memo, CUBE_CAP, 0, use_forecl=True, emit=None)
    per = r.pop("per_clique")
    byw = {}
    for i, p_ in enumerate(per):
        d = byw.setdefault(p_["width"], {"sets": 0, "remaining": 0})
        d["sets"] += 1
        d["remaining"] += int(p_["sat"]) - int(p_["covered"])
    wide = sum(v["sets"] for k, v in byw.items() if k >= 13)
    wide_rem = sum(v["remaining"] for k, v in byw.items() if k >= 13)
    row = {"withdrawn": len(w), "sets": len(cliques), "confined_pairs": len(P["confined"]),
           "satisfiable": int(r["satisfiable"]), "covered": int(r["covered"]),
           "remaining": int(r["remaining"]),
           "wide_sets_ge13": wide, "wide_remaining": int(wide_rem),
           "by_width": {str(k): {"sets": v["sets"], "remaining": str(v["remaining"])}
                        for k, v in sorted(byw.items())}}
    out["arms"][arm] = row
    print(f"\n### ARM {arm}: withdrawn={len(w)} sets={len(cliques)} "
          f"confined={len(P['confined'])} satisfiable={r['satisfiable']} "
          f"covered={r['covered']} REMAINING={r['remaining']} "
          f"wide(>=13)={wide} holding {wide_rem}", flush=True)
    print("   width sets remaining:", {k: (v['sets'], str(v['remaining'])) for k, v in sorted(byw.items())}, flush=True)
    # ---- Q2: the anatomy of the widest sets, for the SHIPPED arm only -----
    if arm == "W564":
        rank = sorted(range(len(cliques)), key=lambda i: -(int(per[i]["sat"]) - int(per[i]["covered"])))
        for i in rank[:40]:
            sets_dump[str(i)] = {"width": per[i]["width"], "sat": str(per[i]["sat"]),
                                 "covered": str(per[i]["covered"]),
                                 "remaining": str(int(per[i]["sat"]) - int(per[i]["covered"])),
                                 "leaf_groups": per[i].get("leaf_groups"),
                                 "members": list(cliques[i])}
        sets_dump["_all_widths"] = [per[i]["width"] for i in range(len(cliques))]
        # every set's members, compactly, for offline family analysis
        sets_dump["_members_all"] = [list(c) for c in cliques]
        sets_dump["_rem_all"] = [str(int(per[i]["sat"]) - int(per[i]["covered"])) for i in range(len(cliques))]

json.dump(out, open(OUT_JSON, "w"), indent=1)
json.dump(sets_dump, open(OUT_SETS, "w"), indent=1)
print(f"\nwrote {OUT_JSON} and {OUT_SETS}")
print(f"P40-WIDTHPROBE-DONE in {time.time()-t0:.0f}s", flush=True)
