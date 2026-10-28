#!/usr/bin/env python3
"""P26 — EMIT every remaining cube under the §16c OR-REFINED projection.

`_p23_enum.py` has NO §16c (§82.1); `_p25_confcensus.py` HAS it but emits with
`emit_max_per_set=1, emit_cap=1` (it was a census, not an emission). This is
the missing third tool: the SAME universe, the SAME OR-refined projection
(`project_confinement(..., strict=True, keying="coevaluated",
protect_gates=False, or_sharing=True)`), with the emit caps OPEN, so the
streamed `.jsonl` is the exact per-set remaining cube list §16c-OR demands.

Everything below the projection is `_p23_enum`'s own code — same disjoint
cover, same `_emit_item`, same streamed writes, same uncapped `region_pieces`
counter — so the census numbers this prints are comparable line-for-line with
`_p25_census_P24.json`'s `or` row by construction.

    DUMP_LIST=<list> EMIT_OUT=<f.jsonl> [MAX_CLIQUES=16384] [CUBE_CAP=20000]
    [EMIT_MAX_PER_SET=0] [EMIT_CAP=0] [WITHDRAWN_PAIRS=<json [[a,b],...]>]
    [OR_SHARING=1] [JSON_OUT=f] [PAIRS_OUT=f]
        python3 -u _p26_emit_or.py

Declares nothing; writes only where EMIT_OUT / JSON_OUT / PAIRS_OUT point.
Verdict line: `P26-EMIT-DONE`.
"""
import json
import os
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
EMIT_OUT = os.environ.get("EMIT_OUT") or None
EMIT_MAX_PER_SET = int(os.environ.get("EMIT_MAX_PER_SET", "0"))
EMIT_CAP = int(os.environ.get("EMIT_CAP", "0"))
OR_SHARING = os.environ.get("OR_SHARING", "1") != "0"

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, MAX_CLIQUES)
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s; 16b demand sets {len(U['cliques'])}",
      flush=True)

# ---- trace layer (verbatim from _p25_confcensus.py) ------------------------
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

P = project_confinement(
    U["active"], U["expr_order"], U["run_outcomes"], union, inter, side_seen,
    base_demands, U["by_gate"], U["bit"], MAX_CLIQUES,
    strict=True, keying="coevaluated", protect_gates=False,
    withdrawn=withdrawn, or_sharing=OR_SHARING)
cliques = [sorted(d, key=order.__getitem__) for d in P["demands"]]
decided = [e for e in U["active"] if P["ctxn"].get(e, 0)]
print(f"\n=== PROJECTION {'OR-refined' if OR_SHARING else 'STRICT'} ===")
print(f"  decisions {len(U['active'])} -> DECIDED {len(decided)} "
      f"({len(P['coevaluated'])} co-evaluated) / UNDECIDABLE "
      f"{len(U['active'])-len(decided)}; CONFINED "
      f"{len([e for e in decided if e not in P['disqualified']])} "
      f"DISQ {len(P['disqualified'])}")
print(f"  pairs: confined {len(P['confined'])} / OR-licensed {len(P.get('or_pairs',()))} "
      f"/ AND-refused {len(P.get('and_pairs',()))} / overlapping {len(P['overlapping'])} "
      f"/ undecidable {len(P['undecidable'])}; demand sets "
      f"{len(U['cliques'])} -> {len(cliques)} ({P['splits']} split)", flush=True)

# ---- THE §16b READING, for the same corpus ---------------------------------
# "covered is covered under every projection": a round must be booked under the
# reading it was built from (OR-refined) AND under the unconfined one, or the
# two numbers drift the way §82.1 caught them drifting. NO_EMIT — this is a
# count, the emission below is the OR-refined one.
known = EE.var_index(U["decls"])
vcache, memo = {}, {}
if os.environ.get("ALSO_16B", "1") != "0":
    print(f"\n=== CENSUS 16b (count only, no emit): {len(U['cliques'])} demand sets ===",
          flush=True)
    # NEVER under CENSUS_LEAF_ENUM: the §16b sets are the wide ones (REMAINING
    # 8.26e13) and the leaf enumeration is per LEAF. The §16b reading stays the
    # product census, which is exact for it and is the number every round is
    # booked under.
    _le = EE._LEAF_ENUM
    EE._LEAF_ENUM = False
    r16 = EE.census(U, U["cliques"], known, vcache, memo, CUBE_CAP, 0,
                    use_forecl=True, emit=None)
    EE._LEAF_ENUM = _le
    r16.pop("per_clique", None)
    print(f"  16b: sets={r16['cliques']} satisfiable={r16['satisfiable']} "
          f"covered={r16['covered']} REMAINING={r16['remaining']} "
          f"bounded_cliques={r16['bounded_cliques']}", flush=True)
else:
    r16 = None

# ---- THE EMISSION ----------------------------------------------------------
# CENSUS_MODES (P30, 2026-09-13) — run several readings of the SAME universe in
# ONE process, because the universe build is the expensive part and two runs of
# it are not comparable if anything on the box moved. Modes:
#   prod    the booked product census (CENSUS_LEAF_ENUM off) — the number of
#           record, unchanged since §86.1
#   enum    the LEAF ENUMERATION with §16e and §16f OFF — must reproduce `prod`
#           EXACTLY. That equality is the reproduction check: under §16b a leaf
#           IS a full assignment, so the two counting methods are the same
#           quantity computed two ways.
#   16e     leaf enumeration, §16e on
#   16f     leaf enumeration, §16e+§16f on (the corrected residue)
# The LAST mode in the list is the one that EMITS.
_MODES = [m for m in os.environ.get("CENSUS_MODES", "prod").split(",") if m]
_MODE_ENV = {"prod": (False, "0", "0"), "enum": (True, "0", "0"),
             "16e": (True, "1", "0"), "16f": (True, "1", "1")}
_results = {}
for _mi, _mode in enumerate(_MODES):
    _le, _c16e, _c16f = _MODE_ENV[_mode]
    EE._LEAF_ENUM = _le
    os.environ["FORECLOSURE_CONJUNCTIONS"] = _c16e
    os.environ["FORECLOSURE_SUBCONJUNCTIONS"] = _c16f
    _last = (_mi == len(_MODES) - 1)
    _out = EMIT_OUT if _last else None
    if _mode == "16f":
        os.environ.setdefault("SUBCONJ_CLASSES_OUT",
                              os.path.join(HERE, "_p30_subconj_classes.json"))
    else:
        os.environ.pop("SUBCONJ_CLASSES_OUT", None)
    print(f"\n=== CENSUS MODE {_mode}: {len(cliques)} demand sets, "
          f"leaf_enum={_le} 16e={_c16e} 16f={_c16f} emit_out={_out} "
          f"max_per_set={EMIT_MAX_PER_SET} cap={EMIT_CAP} ===", flush=True)
    r = EE.census(U, cliques, known, vcache, memo, CUBE_CAP, 0, use_forecl=True,
                  emit=_out, emit_max_per_set=EMIT_MAX_PER_SET, emit_cap=EMIT_CAP)
    _results[_mode] = {k: v for k, v in r.items() if k != "per_clique"}
    print(f"  MODE {_mode}: sets={r['cliques']} satisfiable={r['satisfiable']} "
          f"covered={r['covered']} REMAINING={r['remaining']}", flush=True)
if len(_MODES) > 1:
    print("\n=== CENSUS MODE COMPARISON (same universe, same projection) ===")
    for _mode in _MODES:
        _r = _results[_mode]
        print(f"  {_mode:>5}: satisfiable={_r['satisfiable']:>10} "
              f"covered={_r['covered']:>10} REMAINING={_r['remaining']:>10}")
    if "prod" in _results and "enum" in _results:
        _a, _b = _results["prod"], _results["enum"]
        _ok = all(_a[k] == _b[k] for k in ("satisfiable", "covered", "remaining"))
        print(f"  REPRODUCTION CHECK prod == enum (§16f flag OFF): "
              f"{'PASS' if _ok else '*** FAIL ***'}")

byw = {}
for p_ in r["per_clique"]:
    w = p_["width"]
    d = byw.setdefault(w, {"sets": 0, "remaining": 0, "pieces": 0, "emitted": 0})
    d["sets"] += 1
    d["remaining"] += int(p_["sat"]) - int(p_["covered"])
    d["pieces"] += p_.get("region_pieces", 0)
    d["emitted"] += p_.get("emitted", 0)
r["by_width"] = {str(w): {"sets": v["sets"], "remaining": str(v["remaining"]),
                          "pieces": v["pieces"], "emitted": v["emitted"]}
                 for w, v in sorted(byw.items())}
r["region_pieces"] = sum(v["pieces"] for v in byw.values())
r["emitted_cubes"] = sum(v["emitted"] for v in byw.values())
r.pop("per_clique", None)
print(f"\n  sets={r['cliques']} satisfiable={r['satisfiable']} covered={r['covered']} "
      f"REMAINING={r['remaining']} region_pieces={r['region_pieces']} "
      f"EMITTED_CUBES={r['emitted_cubes']} bounded_cliques={r['bounded_cliques']}",
      flush=True)
print("  width  sets      remaining        pieces   emitted", flush=True)
for w, v in sorted(byw.items()):
    print(f"  {w:>5} {v['sets']:>5}  {v['remaining']:>18}  {v['pieces']:>8}  {v['emitted']:>8}",
          flush=True)

if os.environ.get("PAIRS_OUT"):
    fp = P["footprint"]
    json.dump({
        "mode": "or" if OR_SHARING else "strict",
        "footprints": {e: [names[j] for j in range(len(names)) if fp[e] >> j & 1]
                       for e in fp},
        "confined_pairs": sorted(list(x) for x in P["confined"]),
        "or_pairs": sorted(list(x) for x in P.get("or_pairs", ())),
        "disqualified_decisions": sorted(P["disqualified"]),
        "undecidable_pairs": len(P["undecidable"]),
    }, open(os.environ["PAIRS_OUT"], "w"), indent=1)
    print(f"wrote pairs -> {os.environ['PAIRS_OUT']}", flush=True)

if os.environ.get("JSON_OUT"):
    _c = {"or" if OR_SHARING else "strict": r}
    _c["modes"] = _results
    if r16 is not None:
        _c["16b"] = r16
    json.dump({"census": _c,
               "shapes": len(shape_id),
               "projection": {
                   "sets": len(cliques),
                   "confined_pairs": len(P["confined"]),
                   "or_pairs": len(P.get("or_pairs", ())),
                   "and_pairs": len(P.get("and_pairs", ())),
                   "overlapping": len(P["overlapping"]),
                   "undecidable_pairs": len(P["undecidable"]),
                   "splits": P["splits"],
                   "decided": len(decided),
                   "disqualified": len(P["disqualified"]),
                   "coevaluated": len(P["coevaluated"])}},
              open(os.environ["JSON_OUT"], "w"), indent=1)
    print(f"wrote {os.environ['JSON_OUT']}", flush=True)
print(f"P26-EMIT-DONE in {time.time()-t0:.0f}s", flush=True)
