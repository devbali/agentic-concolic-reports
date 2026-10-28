#!/usr/bin/env python3
"""P27 — WHY 48 % OF OR-REFINED REGION PIECES HAVE NO Z3 MODEL.

Phase 1 (this file): rebuild the EXACT universe and OR-refined projection
`_p26_emit_or.py` builds, re-run the census inner loop VERBATIM (copied from
`_p23_enum.census`, with capture added and nothing removed), and STREAM every
leaf group's full state to `_p27_state.jsonl` — the decls, the fixed base, the
pins, each set's components and their model lists, each leaf group's observed
cubes, and each region piece with its `cube_count` and whether `_emit_item`
found a model for it.

The census totals it prints are the SELF-CHECK: they must equal the published
numbers for the same DUMP_LIST (P26R5: sat 32555, covered 22212, remaining
10343, pieces 2522, emitted 764, no_model 1758). If they do, the copy is the
census; if they do not, nothing below it may be believed.

Phase 2 (`_p27_diag.py`) reads the state file WITHOUT the corpus.

  DUMP_LIST=<list> OUT=_p27_state.jsonl python3 -u _p27_probe.py

Read-only on the corpus. Writes only OUT and OUT.summary.json.
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
from concolic_engine.coverage import (project_confinement,          # noqa: E402
                                      restrict_foreclosures)

MAX_CLIQUES = int(os.environ.get("MAX_CLIQUES", "16384"))
CUBE_CAP = int(os.environ.get("CUBE_CAP", "20000"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_p27_state.jsonl"))

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, MAX_CLIQUES)
if U is None:
    sys.exit("PROJECTION CAP HIT")
print(f"universe built in {time.time()-t0:.0f}s; 16b demand sets {len(U['cliques'])}",
      flush=True)

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
        idx[k2] = len(union)
        union.append(tr)
        inter.append(tr)
    else:
        union[i] |= tr
        inter[i] &= tr
assert len(union) == len(U["run_outcomes"]), "profile index does not match"
print(f"trace layer: {len(shape_id)} shapes over {len(union)} profiles "
      f"({time.time()-t0:.0f}s)", flush=True)

order = {e: i for i, e in enumerate(U["expr_order"])}
base_demands = [frozenset(c) for c in U["cliques"]]
P = project_confinement(
    U["active"], U["expr_order"], U["run_outcomes"], union, inter, side_seen,
    base_demands, U["by_gate"], U["bit"], MAX_CLIQUES,
    strict=True, keying="coevaluated", protect_gates=False,
    withdrawn=(), or_sharing=True)
cliques = [sorted(d, key=order.__getitem__) for d in P["demands"]]
print(f"OR-refined demand sets {len(cliques)}", flush=True)
del runs, idx, union, inter, side_seen

# ---- the census inner loop, COPIED from _p23_enum.census, with capture -----
known = EE.var_index(U["decls"])
vcache, memo = {}, {}
bit = U["bit"]
prof_masks = U["prof_masks"]
by_gate = U["by_gate"]
fixed_base = list(U["fixed_base"])
decls = list(U["decls"])
pinned = dict(U["pinned"])

fh = open(OUT, "w")
fh.write(json.dumps({"_hdr": 1, "decls": decls, "fixed_base": fixed_base,
                     "pinned": pinned, "n_sets": len(cliques)}) + "\n")

tot_sat = tot_cov = 0
st = dict(pieces=0, zero=0, emitted=0, no_model=0, mass=0, region_bound=0,
          mismatch=0, bounded=0)
_order = sorted(enumerate(cliques), key=lambda t: len(t[1]))
for _pos, (ci, clique) in enumerate(_order):
    group, local, _ign = restrict_foreclosures(clique, by_gate, bit)
    cm_full = [EE.comp_models(c, fixed_base, decls, pinned, memo)
               for c in EE.components(list(group), known, vcache)]
    lg = EE.leaves(group, local, bit,
                   feasible=lambda a: EE.cube_count(cm_full, dict(a)) > 0)
    if lg is None:
        st["bounded"] += 1
        continue
    dmask = 0
    for e in group:
        dmask |= 1 << bit[e]
    bymask = {}
    for pi, pm in enumerate(prof_masks):
        k = pm & dmask
        if k:
            bymask.setdefault(k, []).append(pi)
    sat = covered = 0
    is_bound = False
    rec_groups = []
    set_rem_seen = 0
    for pre, surv in lg:
        comps = EE.components(list(surv), known, vcache)
        cm = [EE.comp_models(c, fixed_base, decls, pinned, memo) for c in comps]
        sat += EE.cube_count(cm, pre)
        smask = 0
        for e in surv:
            smask |= 1 << bit[e]
        cubes = set()
        for pi in bymask.get(smask, ()):
            outcomes = U["run_outcomes"][pi]
            cube = {}
            bad = False
            for e in surv:
                o = outcomes[e]
                if len(o) == 1:
                    v = next(iter(o))
                    if e in pre and pre[e] != v:
                        bad = True
                        break
                    cube[e] = v
            if bad:
                continue
            cubes.add(tuple(sorted(cube.items())))
        disjoint = []
        for cube in sorted(cubes, key=len):
            d = dict(cube)
            d.update(pre)
            pieces = [d]
            for prev in disjoint:
                nxt = []
                for p in pieces:
                    sres = EE.subtract([p], prev, CUBE_CAP)
                    if sres is None:
                        nxt = None
                        break
                    nxt.extend(sres)
                if nxt is None:
                    is_bound = True
                    break
                pieces = nxt
                if len(pieces) > CUBE_CAP:
                    is_bound = True
                    break
            if is_bound:
                break
            for p in pieces:
                covered += EE.cube_count(cm, p)
            disjoint.append(d)
        if is_bound:
            break
        region = [dict(pre)]
        for d in disjoint:
            nxt = []
            for r in region:
                sres = EE.subtract([r], d, CUBE_CAP)
                if sres is None:
                    nxt = None
                    break
                nxt.extend(sres)
            if nxt is None or len(nxt) > CUBE_CAP:
                region = None
                break
            region = nxt
        pcs = []
        if region is None:
            st["region_bound"] += 1
        else:
            for r in region:
                n = EE.cube_count(cm, r)
                if n == 0:
                    st["zero"] += 1
                    continue
                set_rem_seen += n
                st["pieces"] += 1
                item = EE._emit_item(U, ci, clique, group, pre, surv, r, n)
                if item is None:
                    st["no_model"] += 1
                    ok = 0
                else:
                    st["emitted"] += 1
                    st["mass"] += n
                    ok = 1
                pcs.append({"cube": r, "n": n, "ok": ok})
        rec_groups.append({
            "pre": pre, "surv": list(surv),
            "comps": [[list(k), m] for k, m in cm],
            "obs": [dict(c) for c in sorted(cubes)],
            "pieces": pcs})
    if is_bound:
        st["bounded"] += 1
    if not is_bound and set_rem_seen != sat - covered:
        st["mismatch"] += 1
    tot_sat += sat
    tot_cov += covered
    fh.write(json.dumps({"ci": ci, "width": len(clique), "clique": clique,
                         "group": list(group),
                         "local": [[list(k), v] for k, v in local.items()],
                         "sat": sat, "covered": covered,
                         "bound": is_bound, "groups": rec_groups}) + "\n")
    if _pos % 100 == 0:
        fh.flush()
        print(f"  [{_pos}/{len(cliques)}] set#{ci} w={len(clique)} "
              f"pieces={st['pieces']} no_model={st['no_model']} "
              f"rem={tot_sat-tot_cov} wall={time.time()-t0:.0f}s", flush=True)
fh.close()

summ = dict(sets=len(cliques), satisfiable=tot_sat, covered=tot_cov,
            remaining=tot_sat - tot_cov, **st)
print("\nP27 CENSUS SELF-CHECK: " + json.dumps(summ), flush=True)
json.dump(summ, open(OUT + ".summary.json", "w"), indent=1)
print(f"P27-PROBE-DONE in {time.time()-t0:.0f}s", flush=True)
