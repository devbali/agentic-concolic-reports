#!/usr/bin/env python3
"""P25 — the EXACT enumerator under the three nested readings of the demand.

A batch-local descendant of `reports/diaspora/tools/confinement_census.py`
(which is shared and is NOT edited) with three additions this round needs:

  1. `_p23_enum` as the enumerator — the STREAMED census with the uncapped
     per-set `region_pieces` counter and the ascending-width order. The shared
     tool hard-codes `_exact_enum_emit`.
  2. MODES. The shared tool runs §16b and ONE confinement projection (the
     engine defaults, i.e. OR-refined). DISCIPLINE §16c's nesting claim is
     `OR-refined subset of strict subset of §16b subset of §16`, and only a
     run of all three on ONE universe can exhibit it. `CONF_OR_SHARING=0`
     gives strict, and the projections are computed from the SAME footprints.
  3. The per-WIDTH remaining distribution (§81.2's table) for every mode, the
     structural nesting check on the demand sets themselves, and a footprint /
     pair export in the shape the assumption gate and `prior_footprints=`
     read.

    DUMP_LIST=<list> MODES=16b,strict,or [MAX_CLIQUES=16384] [CUBE_CAP=20000]
    [WITHDRAWN_PAIRS=<json list of [a,b]>] [JSON_OUT=f] [PAIRS_OUT=f]
        python3 -u _p25_confcensus.py

Declares nothing. Writes only where JSON_OUT / PAIRS_OUT point.
Verdict line: `P25-CENSUS-DONE` (or the process died).
"""
import json
import os
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

import _p23_enum as EE                                              # noqa: E402
from coverage_assumptions import build as build_assumptions         # noqa: E402
from concolic_engine.assumptions import call_shape, shape_str       # noqa: E402
from concolic_engine.coverage import project_confinement            # noqa: E402

MAX_CLIQUES = int(os.environ.get("MAX_CLIQUES", "16384"))
CUBE_CAP = int(os.environ.get("CUBE_CAP", "20000"))
MODES = [m.strip() for m in os.environ.get("MODES", "16b,strict,or").split(",") if m.strip()]

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, MAX_CLIQUES)
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s", flush=True)

# ---- the trace layer, in the enumerator's own profile order ----------------
# One pass over the alias-applied runs builds BOTH the per-profile trace
# union/intersection (the pairwise footprint definition is exact only with
# both) and `side_seen` (the strict counterexample search's index, which is
# over EVERY run, not per profile). The shared tool walks the runs twice.
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
        idx[k2] = len(union)
        union.append(tr)
        inter.append(tr)
    else:
        union[i] |= tr
        inter[i] &= tr
assert len(union) == len(U["run_outcomes"]), "profile index does not match the enumerator's"
print(f"trace layer: {len(shape_id)} distinct call shapes over {len(union)} profiles "
      f"({time.time()-t0:.0f}s)", flush=True)

withdrawn = ()
if os.environ.get("WITHDRAWN_PAIRS"):
    withdrawn = [tuple(sorted(p)) for p in json.load(open(os.environ["WITHDRAWN_PAIRS"]))]
    print(f"WITHDRAWN_PAIRS: {len(withdrawn)} gate-withdrawn pair(s) fed back", flush=True)

names = [None] * len(shape_id)
for sh, j in shape_id.items():
    names[j] = shape_str(sh)
order = {e: i for i, e in enumerate(U["expr_order"])}
base_demands = [frozenset(c) for c in U["cliques"]]


def project(or_sharing):
    return project_confinement(
        U["active"], U["expr_order"], U["run_outcomes"], union, inter, side_seen,
        base_demands, U["by_gate"], U["bit"], MAX_CLIQUES,
        strict=True, keying="coevaluated", protect_gates=False,
        withdrawn=withdrawn, or_sharing=or_sharing)


projections, cliques_by_mode = {}, {"16b": U["cliques"]}
nest = {}
for mode, orsh in (("strict", False), ("or", True)):
    if mode not in MODES:
        continue
    p_ = project(orsh)
    projections[mode] = p_
    cliques_by_mode[mode] = [sorted(d, key=order.__getitem__) for d in p_["demands"]]
    fp, ctxn, disq = p_["footprint"], p_["ctxn"], p_["disqualified"]
    decided = [e for e in U["active"] if ctxn.get(e, 0)]
    print(f"\n=== PROJECTION {mode} ===")
    print(f"  decisions {len(U['active'])} active -> DECIDED {len(decided)} "
          f"({len(p_['coevaluated'])} by the co-evaluated keying) / "
          f"UNDECIDABLE {len(U['active'])-len(decided)}; "
          f"strictly CONFINED {len([e for e in decided if e not in disq])}, "
          f"DISQUALIFIED {len(disq)}")
    print(f"  pairs: confined {len(p_['confined'])} / OR-licensed {len(p_.get('or_pairs',()))} "
          f"/ AND-refused {len(p_.get('and_pairs',()))} / overlapping {len(p_['overlapping'])} "
          f"/ undecidable {len(p_['undecidable'])}; "
          f"demand sets {len(U['cliques'])} -> {len(cliques_by_mode[mode])} "
          f"({p_['splits']} set(s) split)", flush=True)

# ---- GATE PROJECTION (DISCIPLINE §16c check 2, criteria (i)-(viii)) --------
# The inferred pairs are NOT licensed until the assumption gate has replayed
# them, so before anything is claimed the gate's own COST is measured on this
# corpus. `assumption_checker.py::_test_confinement`'s cost model, quoted:
#
#   "3 composition replays per pair + min(ACHK_CONF_PROFILES, profiles
#    carrying a footprint shape) for (vi) + one constructed replay per
#    footprint shape with another producer for (vii)"
#
# and the gate tests ONE REPRESENTATIVE PER CLASS (the footprint-family key
# `_c11_classes.py::class_of` reproduces; every pair in a non-PASS class is
# withdrawn with it). (vi) is the term that decides the wall: it is
# `_profile_representatives`, one replay per distinct OUTCOME-PROFILE DIGEST
# in which the decision is single-sided on a shape's ENABLING side and the
# representative carries that shape. That count is computable from exactly
# the data this tool already holds, so the projection is MEASURED, not
# guessed.
if os.environ.get("GATE_PROJECTION", "1") != "0" and projections:
    gm = "or" if "or" in projections else next(iter(projections))
    gp = projections[gm]
    gfp = gp["footprint"]
    confined_pairs = sorted(gp["confined"])
    # enabling side per (decision, shape): strictness makes it unique — the
    # shape is present only with the decision on one side.
    enabling = {}
    for e, m in gfp.items():
        sl = side_seen.get(e, [0, 0, 0])
        x = m
        while x:
            b = x & -x
            j = b.bit_length() - 1
            x ^= b
            if sl[1] >> j & 1:
                enabling[(e, j)] = True
            elif sl[0] >> j & 1:
                enabling[(e, j)] = False
    # (vi): profiles per decision. One pass over the runs, grouped by the
    # profile digest the gate itself dedups on.
    per_profile = []          # (digest -> (single-sided outcome per expr, trace))
    seen_dig = {}
    for run in U["runs"]:
        outc = {}
        for pc in run.path_conditions:
            outc.setdefault(pc.expr, set()).add(bool(pc.taken))
        if not outc:
            continue
        tr = 0
        for ev in run.symbolic_call_events:
            if ev.result_name:
                j = shape_id.get(call_shape(ev.target_name, ev.note, ev.args))
                if j is not None:
                    tr |= 1 << j
        d = pkey(outc)
        cur = seen_dig.get(d)
        if cur is None:
            seen_dig[d] = [outc, tr]
        else:
            cur[1] |= tr
    vi_counts = {}
    for e in gfp:
        m = gfp[e]
        if not m:
            vi_counts[e] = 0
            continue
        n = 0
        for outc, tr in seen_dig.values():
            os_ = outc.get(e)
            if not os_ or len(os_) > 1:
                continue
            side = True in os_
            x = m & tr
            hit = False
            while x:
                b = x & -x
                j = b.bit_length() - 1
                x ^= b
                if enabling.get((e, j)) == side:
                    hit = True
                    break
            if hit:
                n += 1
        vi_counts[e] = n

    # the gate's CLASS key (footprint-family), reproduced from
    # results3/notifications_index/_c11_classes.py::class_of / side_key
    import re as _re
    _TBL = _re.compile(r"(?:records|to_ary)_([a-z_]+?)_[0-9a-f]{8}")

    def _side_key(expr, footprint):
        if footprint:
            return tuple(sorted(z[:60] for z in footprint))
        m_ = _TBL.search(expr)
        return (m_.group(1),) if m_ else (expr[:60],)

    def _fps(e):
        m = gfp.get(e, 0)
        return [names[j] for j in range(len(names)) if m >> j & 1]

    classes = {}
    for a_, b_ in confined_pairs:
        k = str(tuple(sorted((_side_key(a_, _fps(a_)), _side_key(b_, _fps(b_))))))
        classes.setdefault(k, []).append((a_, b_))
    # per class, the gate's replay budget for its REPRESENTATIVE pair
    budget = {}
    for k, members in classes.items():
        a_, b_ = members[0]
        nsh = bin(gfp.get(a_, 0)).count("1") + bin(gfp.get(b_, 0)).count("1")
        budget[k] = 3 + vi_counts.get(a_, 0) + vi_counts.get(b_, 0) + nsh
    tot_replays = sum(budget.values())
    dec_conf = sorted({e for p_ in confined_pairs for e in p_})
    print("\n=== GATE PROJECTION (§16c check 2) ===")
    print(f"  mode measured: {gm}")
    print(f"  confined PAIRS {len(confined_pairs)} over {len(dec_conf)} distinct decisions")
    print(f"  gate CLASSES (footprint-family key) {len(classes)}; "
          f"largest class {max((len(v) for v in classes.values()), default=0)} pairs")
    print(f"  (vi) profile representatives per decision: "
          f"min {min(vi_counts.values(), default=0)} / "
          f"median {sorted(vi_counts.values())[len(vi_counts)//2] if vi_counts else 0} / "
          f"max {max(vi_counts.values(), default=0)}; "
          f"total over confined decisions {sum(vi_counts.get(e, 0) for e in dec_conf)}")
    print(f"  REPLAYS the gate must run, one representative per class: {tot_replays}")
    for _r in (0.30, 0.61, 1.0):
        print(f"     at {_r:.2f} s/replay (CONCOLIC_SLOTS=1): "
              f"{tot_replays*_r/3600:.1f} h")
    nest["gate"] = {"pairs": len(confined_pairs), "decisions": len(dec_conf),
                    "classes": len(classes), "replays": tot_replays,
                    "vi_total": sum(vi_counts.get(e, 0) for e in dec_conf),
                    "vi_max": max(vi_counts.values(), default=0)}
    if os.environ.get("GATE_OUT"):
        json.dump({"mode": gm, "classes": {k: v for k, v in classes.items()},
                   "budget": budget, "vi_counts": vi_counts,
                   "replays": tot_replays,
                   "footprints": {e: _fps(e) for e in gfp}},
                  open(os.environ["GATE_OUT"], "w"), indent=1)
        print(f"  wrote gate projection -> {os.environ['GATE_OUT']}", flush=True)

# ---- structural nesting on the SETS ---------------------------------------
# DISCIPLINE §16c Rule T: every sub-set of the finer reading is a subset of a
# set of the coarser one. Checked, not assumed.
def nested(fine, coarse, ftag, ctag):
    cs = [frozenset(c) for c in coarse]
    bad = 0
    for d in fine:
        d = frozenset(d)
        if not any(d <= c for c in cs):
            bad += 1
    print(f"  NESTING {ftag} in {ctag}: {len(fine)-bad}/{len(fine)} sets contained"
          f"{'' if not bad else f'  *** {bad} NOT CONTAINED ***'}", flush=True)
    return bad


print("\n=== NESTING CHECK (demand sets) ===")
if "or" in cliques_by_mode and "strict" in cliques_by_mode:
    nest["or_in_strict"] = nested(cliques_by_mode["or"], cliques_by_mode["strict"], "OR-refined", "strict")
for m in ("strict", "or"):
    if m in cliques_by_mode:
        nest[f"{m}_in_16b"] = nested(cliques_by_mode[m], cliques_by_mode["16b"], m, "16b")

# ---- the exact census, per mode -------------------------------------------
known = EE.var_index(U["decls"])
vcache, memo = {}, {}
res = {}
for mode in MODES:
    cl = cliques_by_mode.get(mode)
    if cl is None:
        continue
    print(f"\n=== CENSUS {mode}: {len(cl)} demand sets ===", flush=True)
    # EMIT with a cap of ONE cube: the per-set `region_pieces` counter is
    # UNCAPPED and only runs on the emit path (`_p23_enum.py` line ~650), while
    # emit_max_per_set/emit_cap bound only how many cubes are BUILT (a Z3 model
    # each). Cap 1 therefore buys §81.2's exact piece distribution and the
    # region-mass cross-check for the price of the disjointification alone.
    _em = os.path.join(os.environ.get("EMIT_DIR", "/tmp"), f"_p25_emit_{mode}.json")
    r = EE.census(U, cl, known, vcache, memo, CUBE_CAP, 0, use_forecl=True,
                  emit=(_em if os.environ.get("NO_EMIT") != "1" else None),
                  emit_max_per_set=1, emit_cap=1)
    # per-width remaining distribution (§81.2's table)
    byw = {}
    for p_ in r["per_clique"]:
        w = p_["width"]
        d = byw.setdefault(w, {"sets": 0, "remaining": 0, "pieces": 0})
        d["sets"] += 1
        d["remaining"] += int(p_["sat"]) - int(p_["covered"])
        d["pieces"] += p_.get("region_pieces", 0)
    r["by_width"] = {str(w): {"sets": v["sets"], "remaining": str(v["remaining"]),
                              "pieces": v["pieces"]} for w, v in sorted(byw.items())}
    r["region_pieces"] = sum(v["pieces"] for v in byw.values())
    r.pop("per_clique", None)
    res[mode] = r
    print(f"  {mode}: sets={r['cliques']} satisfiable={r['satisfiable']} "
          f"covered={r['covered']} REMAINING={r['remaining']} "
          f"wide(>=13)={r['wide']} wide_mass={r['wide_mass']} "
          f"region_pieces={r['region_pieces']} bounded={r['bounded_cliques']}", flush=True)
    print("  width  sets      remaining        pieces", flush=True)
    for w, v in sorted(byw.items()):
        print(f"  {w:>5} {v['sets']:>5}  {v['remaining']:>18}  {v['pieces']:>8}", flush=True)

print("\n=== DELTA (identical snapshot, identical assumptions, foreclosure ON) ===")
for mode in MODES:
    if mode in res:
        r = res[mode]
        print(f"  {mode:<7} sets={r['cliques']:<7} remaining={r['remaining']:<24} "
              f"pieces={r['region_pieces']:<9} wide={r['wide']}")

if os.environ.get("PAIRS_OUT") and projections:
    m = "or" if "or" in projections else next(iter(projections))
    p_ = projections[m]
    fp = p_["footprint"]
    json.dump({
        "mode": m,
        "footprints": {e: [names[j] for j in range(len(names)) if fp[e] >> j & 1]
                       for e in fp},
        "confined_pairs": sorted(list(x) for x in p_["confined"]),
        "or_pairs": sorted(list(x) for x in p_.get("or_pairs", ())),
        "disqualified_decisions": sorted(p_["disqualified"]),
        "undecidable_pairs": len(p_["undecidable"]),
        "overlapping": [[a, b, n] for (a, b), n in p_["overlapping"].items()],
    }, open(os.environ["PAIRS_OUT"], "w"), indent=1)
    print(f"wrote pairs/footprints -> {os.environ['PAIRS_OUT']}", flush=True)

if os.environ.get("JSON_OUT"):
    json.dump({"census": res, "nesting": nest,
               "shapes": len(shape_id),
               "modes": MODES,
               "projection": {m: {
                   "sets": len(cliques_by_mode[m]),
                   "confined_pairs": len(p_["confined"]),
                   "or_pairs": len(p_.get("or_pairs", ())),
                   "and_pairs": len(p_.get("and_pairs", ())),
                   "overlapping": len(p_["overlapping"]),
                   "undecidable_pairs": len(p_["undecidable"]),
                   "splits": p_["splits"],
                   "decided": len([e for e in U["active"] if p_["ctxn"].get(e, 0)]),
                   "disqualified": len(p_["disqualified"]),
                   "coevaluated": len(p_["coevaluated"]),
               } for m, p_ in projections.items()}},
              open(os.environ["JSON_OUT"], "w"), indent=1)
    print(f"wrote {os.environ['JSON_OUT']}", flush=True)
print(f"P25-CENSUS-DONE in {time.time()-t0:.0f}s", flush=True)
