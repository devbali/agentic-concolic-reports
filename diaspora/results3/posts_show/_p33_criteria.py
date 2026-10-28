#!/usr/bin/env python3
"""P33 — the CONFINEMENT CRITERION MATRIX on posts_show's booked corpus.

MEASUREMENT ONLY. Declares nothing, drives nothing, writes only where
JSON_OUT / OUT_DIR point (`_p33_*`). A read-only descendant of
`_p26_emit_or.py` (which is the tool that produced `_p30_census_P30C.json`,
the booked 4 093) with ONE addition: the same universe is projected under
EVERY reading of DISCIPLINE §16c the engine can express, and each projection
is priced three ways — licensed pairs, the assumption gate's CLASS list and
distinct-probe budget, and the exact census REMAINING.

The readings (`project_confinement` knobs, engine's own semantics — nothing
is re-derived here):

  A  today            keying=coevaluated  or_sharing=1  unobserved=withhold
  C3 exact keying     keying=exact        or_sharing=1  unobserved=withhold
  C2 span union       keying=coevaluated  or_sharing=1  unobserved=attribute
  C2+C3               keying=exact        or_sharing=1  unobserved=attribute
  S  strict only      keying=coevaluated  or_sharing=0  unobserved=withhold
  S+C3               keying=exact        or_sharing=0  unobserved=withhold
  S+C2               keying=coevaluated  or_sharing=0  unobserved=attribute
  S+C2+C3            keying=exact        or_sharing=0  unobserved=attribute
  OFF §16b            no confinement at all (the demand ceiling)

C1 (trace currency) is a NO-OP on this endpoint: `posts_show/coverage_report.py`
keeps `note`/`args`, so engine and gate already measure the same 69 shapes
(docs/CONFINEMENT_PRECISION_20260913.md §2, §8.5). It is not a knob here.

    DUMP_LIST=<list> [CRITERIA=A,C3,...] [JSON_OUT=f] [MAX_CLIQUES=16384]
    [CUBE_CAP=20000] [LEAF_MAX=300000] [SKIP_CENSUS=0]
        python3 -u _p33_criteria.py

Verdict line: `P33-CRITERIA-DONE`.
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

import _p23_enum as EE                                              # noqa: E402
from coverage_assumptions import build as build_assumptions         # noqa: E402
from concolic_engine.assumptions import call_shape, shape_str       # noqa: E402
from concolic_engine.coverage import project_confinement            # noqa: E402

MAX_CLIQUES = int(os.environ.get("MAX_CLIQUES", "16384"))
CUBE_CAP = int(os.environ.get("CUBE_CAP", "20000"))
LEAF_MAX = int(os.environ.get("LEAF_MAX", "300000"))
SKIP_CENSUS = os.environ.get("SKIP_CENSUS", "0") == "1"
JSON_OUT = os.environ.get("JSON_OUT") or os.path.join(HERE, "_p33_criteria.json")

# name -> (keying, or_sharing, footprint_unobserved)
CRIT = {
    "A_today":  ("coevaluated", True,  "withhold"),
    "C3":       ("exact",       True,  "withhold"),
    "C2":       ("coevaluated", True,  "attribute"),
    "C2C3":     ("exact",       True,  "attribute"),
    "S":        ("coevaluated", False, "withhold"),
    "SC3":      ("exact",       False, "withhold"),
    "SC2":      ("coevaluated", False, "attribute"),
    "SC2C3":    ("exact",       False, "attribute"),
}
WANT = [c.strip() for c in os.environ.get(
    "CRITERIA", "A_today,C3,C2,C2C3,SC2C3,SC3,SC2,S").split(",") if c.strip()]

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, MAX_CLIQUES)
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s; 16b demand sets {len(U['cliques'])}",
      flush=True)

# ---- trace layer (verbatim from _p26_emit_or.py) ---------------------------
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
NSH = len(shape_id)
names = [None] * NSH
for sh, j in shape_id.items():
    names[j] = shape_str(sh)
print(f"trace layer: {NSH} distinct call shapes over {len(union)} profiles "
      f"({time.time()-t0:.0f}s)", flush=True)

order = {e: i for i, e in enumerate(U["expr_order"])}
base_demands = [frozenset(c) for c in U["cliques"]]
RO = U["run_outcomes"]

# ---- the gate's ENABLING side per (decision, shape) ------------------------
# `CoverageResult.footprint_sides` verbatim: "both" when the shape is seen on
# both sides or in a both-sided run, else "taken"/"not_taken". A "both" shape
# can never be `carried` by `_exhaustive_flip`, which is why so many decisions
# cost the gate ZERO (vi) probes.
def side_of(e, j):
    sl = side_seen.get(e, [0, 0, 0])
    if (sl[2] >> j & 1) or ((sl[0] >> j & 1) and (sl[1] >> j & 1)):
        return "both"
    return "taken" if (sl[1] >> j & 1) else "not_taken"


# per-profile single-sided outcome index, for the (vi) representative count
PROF_SIDE = []          # list of {expr: bool} for single-sided decisions only
for outcomes in RO:
    PROF_SIDE.append({e: (True in os_) for e, os_ in outcomes.items() if len(os_) == 1})


def snap_reps(e, mask):
    """`_profile_representatives`' candidate count, computed on THIS snapshot:
    profiles where `e` is single-sided on side s and whose trace carries a
    footprint shape whose enabling side is s. (The gate runs the same rule
    over the WHOLE batch dir; the ratio between the two is the calibration.)"""
    if not mask:
        return 0
    en_t = 0
    en_f = 0
    x = mask
    while x:
        b = x & -x
        j = b.bit_length() - 1
        x ^= b
        s = side_of(e, j)
        if s == "taken":
            en_t |= b
        elif s == "not_taken":
            en_f |= b
    if not (en_t or en_f):
        return 0
    n = 0
    for i, ps in enumerate(PROF_SIDE):
        side = ps.get(e)
        if side is None:
            continue
        if union[i] & (en_t if side else en_f):
            n += 1
    return n


# ---- the gate's CLASS key (_c11_classes.py::class_of, verbatim) ------------
_TBL = re.compile(r"(?:records|to_ary)_([a-z_]+?)_[0-9a-f]{8}")


def side_key(expr, footprint):
    if footprint:
        return tuple(sorted(z[:60] for z in footprint))
    m = _TBL.search(expr)
    return (m.group(1),) if m else (expr[:60],)


known = EE.var_index(U["decls"])
vcache, memo = {}, {}
OUT = {"list": os.environ.get("DUMP_LIST"), "profiles": len(RO),
       "shapes": NSH, "sets_16b": len(U["cliques"]), "criteria": {}}


def save():
    json.dump(OUT, open(JSON_OUT, "w"), indent=1, default=str)


def _clean(d):
    """Keep only JSON scalars; huge ints go to str so the file stays valid."""
    out = {}
    for k, v in d.items():
        if isinstance(v, bool) or isinstance(v, (float, str)) or v is None:
            out[k] = v
        elif isinstance(v, int):
            out[k] = str(v) if abs(v) > 2**53 else v
    return out


def run_census(tag, cliques, leaf):
    """`prod` (product census, always) and, when the residue is small enough
    to enumerate, `16f` (leaf enumeration, §16e+§16f W=3) — the two readings
    `_p26_emit_or.py` books. Same code path, same caps."""
    out = {}
    EE._LEAF_ENUM = False
    os.environ["FORECLOSURE_CONJUNCTIONS"] = "0"
    os.environ["FORECLOSURE_SUBCONJUNCTIONS"] = "0"
    os.environ.pop("SUBCONJ_CLASSES_OUT", None)
    r = EE.census(U, cliques, known, vcache, memo, CUBE_CAP, 0, use_forecl=True,
                  emit=None)
    r.pop("per_clique", None)
    out["prod"] = _clean(r)
    print(f"  [{tag}] prod: sets={r['cliques']} sat={r['satisfiable']} "
          f"covered={r['covered']} REMAINING={r['remaining']} "
          f"bounded={r['bounded_cliques']}", flush=True)
    if leaf and int(r["remaining"]) <= LEAF_MAX:
        EE._LEAF_ENUM = True
        os.environ["FORECLOSURE_CONJUNCTIONS"] = "1"
        os.environ["FORECLOSURE_SUBCONJUNCTIONS"] = "1"
        os.environ["SUBCONJ_CLASSES_OUT"] = os.path.join(HERE, "_p33_subconj_scratch.json")
        r2 = EE.census(U, cliques, known, vcache, memo, CUBE_CAP, 0,
                       use_forecl=True, emit=None)
        r2.pop("per_clique", None)
        out["16f"] = _clean(r2)
        print(f"  [{tag}] 16f : sets={r2['cliques']} sat={r2['satisfiable']} "
              f"covered={r2['covered']} REMAINING={r2['remaining']}", flush=True)
        EE._LEAF_ENUM = False
        os.environ["FORECLOSURE_CONJUNCTIONS"] = "0"
        os.environ["FORECLOSURE_SUBCONJUNCTIONS"] = "0"
        os.environ.pop("SUBCONJ_CLASSES_OUT", None)
    else:
        out["16f"] = None
        print(f"  [{tag}] 16f : NOT ENUMERABLE (remaining > {LEAF_MAX})", flush=True)
    return out


# ---- the criteria ----------------------------------------------------------
for tag in WANT:
    keying, orsh, unobs = CRIT[tag]
    ts = time.time()
    print(f"\n=== CRITERION {tag}: keying={keying} or_sharing={orsh} "
          f"unobserved={unobs} ===", flush=True)
    P = project_confinement(
        U["active"], U["expr_order"], RO, union, inter, side_seen,
        base_demands, U["by_gate"], U["bit"], MAX_CLIQUES,
        strict=True, keying=keying, protect_gates=False, withdrawn=(),
        or_sharing=orsh, footprint_unobserved=unobs)
    fp = P["footprint"]
    decided = [e for e in U["active"] if P["ctxn"].get(e, 0)]
    pairs = sorted(P["confined"])
    cliques = [sorted(d, key=order.__getitem__) for d in P["demands"]]
    print(f"  decisions {len(U['active'])} -> DECIDED {len(decided)} "
          f"({len(P['coevaluated'])} co-evaluated) / UNDECIDABLE "
          f"{len(U['active'])-len(decided)}; CONFINED "
          f"{len([e for e in decided if e not in P['disqualified']])} "
          f"DISQ {len(P['disqualified'])}", flush=True)
    print(f"  pairs: confined {len(pairs)} / OR-licensed {len(P.get('or_pairs',()))} "
          f"/ AND-refused {len(P.get('and_pairs',()))} / overlapping "
          f"{len(P['overlapping'])} / undecidable {len(P['undecidable'])}; "
          f"demand sets {len(U['cliques'])} -> {len(cliques)} "
          f"({P['splits']} split)", flush=True)

    fps_cache = {}

    def fps(e):
        v = fps_cache.get(e)
        if v is None:
            m = fp.get(e, 0)
            v = fps_cache[e] = [names[j] for j in range(NSH) if m >> j & 1]
        return v

    classes = {}
    for a_, b_ in pairs:
        k = str(tuple(sorted((side_key(a_, fps(a_)), side_key(b_, fps(b_))))))
        classes.setdefault(k, []).append((a_, b_))
    rep_dec = set()
    for k in sorted(classes):
        a_, b_ = sorted(classes[k])[0]
        rep_dec.add(a_)
        rep_dec.add(b_)
    reps = {e: snap_reps(e, fp.get(e, 0)) for e in sorted(rep_dec)}
    fpsize = {e: bin(fp.get(e, 0)).count("1") for e in sorted(rep_dec)}
    nz = {e: n for e, n in reps.items() if n}
    print(f"  gate CLASSES {len(classes)} (largest "
          f"{max((len(v) for v in classes.values()), default=0)} pairs) over "
          f"{len(rep_dec)} representative decisions", flush=True)
    print(f"  (vi) snapshot representatives: {sum(reps.values())} over "
          f"{len(nz)} decision(s) with a one-sided footprint shape", flush=True)

    OUT["criteria"][tag] = {
        "keying": keying, "or_sharing": orsh, "unobserved": unobs,
        "decided": len(decided), "coevaluated": len(P["coevaluated"]),
        "disqualified": len(P["disqualified"]),
        "confined_decisions": len([e for e in decided if e not in P["disqualified"]]),
        "pairs": len(pairs), "or_pairs": len(P.get("or_pairs", ())),
        "and_pairs": len(P.get("and_pairs", ())),
        "undecidable_pairs": len(P["undecidable"]),
        "overlapping": len(P["overlapping"]),
        "splits": P["splits"], "demand_sets": len(cliques),
        "classes": len(classes),
        "rep_decisions": sorted(rep_dec),
        "snap_reps": reps, "fp_size": fpsize,
        "snap_reps_total": sum(reps.values()),
        "footprint_sizes_all": {e: bin(m).count("1") for e, m in fp.items()},
        "proj_secs": round(time.time() - ts, 1),
    }
    save()
    if not SKIP_CENSUS:
        OUT["criteria"][tag]["census"] = run_census(tag, cliques, True)
        save()
    del cliques, P, fp
    print(f"  {tag} done in {time.time()-ts:.0f}s", flush=True)

# ---- confinement OFF (§16b) ------------------------------------------------
if "OFF" in os.environ.get("CRITERIA", "OFF") or True:
    ts = time.time()
    print("\n=== CRITERION OFF (§16b, no confinement) ===", flush=True)
    OUT["criteria"]["OFF"] = {
        "keying": None, "or_sharing": None, "unobserved": None,
        "pairs": 0, "or_pairs": 0, "classes": 0, "rep_decisions": [],
        "snap_reps": {}, "snap_reps_total": 0,
        "demand_sets": len(U["cliques"]),
    }
    save()
    if not SKIP_CENSUS:
        OUT["criteria"]["OFF"]["census"] = run_census("OFF", U["cliques"], True)
        save()
    print(f"  OFF done in {time.time()-ts:.0f}s", flush=True)

save()
print(f"wrote {JSON_OUT}", flush=True)
print(f"P33-CRITERIA-DONE in {time.time()-t0:.0f}s", flush=True)
