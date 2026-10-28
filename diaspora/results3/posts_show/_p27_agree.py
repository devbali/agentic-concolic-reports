#!/usr/bin/env python3
"""P27 phase 3 — per-set agreement between the CHECKER and the CENSUS.

The checker pass of record for the SAME dump list (`_snapshot_pruned_P26D2.txt`,
48 300 profiles) is `_cov_FINAL_P26D2_20260913.json`: OR-refined, 836 demand
sets, MAX_MISSING_PER_CLIQUE=1, MISSING=189. Each missing entry's
`prefix` is a leaf of exactly one demand set, so the 189 entries name the sets
the checker's own §16d one-query path found a satisfiable, unobserved
assignment in.

This maps each of them onto the census's demand sets and compares, set by set:
   checker MISSING  vs  census remaining>0  vs  exact remaining>0.

  MISSING_JSON=<f>  STATE=_p27_state.jsonl  RECOUNT=_p27_recount.json
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.environ.get("STATE", os.path.join(HERE, "_p27_state.jsonl"))
RECOUNT = os.environ.get("RECOUNT", os.path.join(HERE, "_p27_recount.json"))
MISS = os.environ.get("MISSING_JSON")

fh = open(STATE)
json.loads(fh.readline())
sets = {}
for line in fh:
    r = json.loads(line)
    sets[r["ci"]] = r
print(f"census sets: {len(sets)}")

rec = {d["ci"]: d for d in json.load(open(RECOUNT))} if os.path.exists(RECOUNT) else {}

miss = json.load(open(MISS))
print(f"checker missing entries: {len(miss)}")
hit = {}
unmatched = 0
for m in miss:
    exprs = {e for e, _o in m["lits"]}
    cands = [ci for ci, r in sets.items() if exprs <= set(r["clique"])]
    if not cands:
        unmatched += 1
        continue
    # the leaf may be a foreclosure-truncated prefix of several sets (§16b);
    # attribute it to every set that contains it, as the checker's note says.
    for ci in cands:
        hit[ci] = hit.get(ci, 0) + 1
print(f"  entries matched to >=1 demand set: {len(miss)-unmatched}; unmatched {unmatched}")
print(f"  distinct demand sets named by the checker's missing list: {len(hit)}")

cens = {ci for ci, r in sets.items() if r["sat"] - r["covered"] > 0}
exact = {ci for ci, d in rec.items() if d["sat_x"] - d["cov_x"] > 0} if rec else set()
chk = set(hit)
print(f"\n  sets with remaining>0, CENSUS (component product): {len(cens)}")
if rec:
    print(f"  sets with remaining>0, EXACT (full conjunction) : {len(exact)}")
print(f"  sets named MISSING by the checker                : {len(chk)}")
print(f"\n  checker \\ census  (checker says missing, census says covered): "
      f"{len(chk - cens)}  {sorted(chk - cens)[:10]}")
print(f"  census \\ checker  (census says remaining, checker says covered): "
      f"{len(cens - chk)}")
if rec:
    print(f"  exact \\ checker   : {len(exact - chk)}  {sorted(exact - chk)[:10]}")
    print(f"  checker \\ exact   : {len(chk - exact)}  {sorted(chk - exact)[:10]}")
    print(f"  exact == checker  : {exact == chk}")
    # SAT-count agreement per set, on the sets the checker examined
    dis = [(ci, sets[ci]["sat"], rec[ci]["sat_x"]) for ci in sorted(sets)
           if ci in rec and sets[ci]["sat"] != rec[ci]["sat_x"]]
    print(f"\n  sets whose SAT count differs (product vs conjunction): "
          f"{len(dis)} of {len(rec)}")
    for ci, a, b in dis[:15]:
        print(f"    set#{ci:>4} w={sets[ci]['width']:>2}  sat product={a:>5} "
              f"exact={b:>5}  (-{a-b})")
print("P27-AGREE-DONE")
