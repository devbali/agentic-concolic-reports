#!/usr/bin/env python3
"""Post-process the Class-C gid list against the 3 genuine 2-way conjunction
preconditions found by _p44_reachnec_conj.py (2026-09-17), WITHOUT re-running
the expensive O(exprs^2 * N) COND scan. Cheap: only re-examines the already-
classified C gids' own demand sets against the known conjunction pairs.

Does not declare anything unreachable. A cube whose demand set matches BOTH
conjunct atoms at the CO-FORECLOSING polarity is flagged "A2-CONJ-PROVISIONAL"
(candidate self-foreclosure via a conjunction the single-condition COND table
could not see) -- explicitly NOT run through the §16b/independence falsifier
here, so it stays provisional, per standing discipline. A cube whose demand
set mentions at least one conjunct variable but does NOT match the
co-foreclosing combination is "B2-CONJ" -- a new constructor pin candidate.

usage: _p44_conj_reclassify.py <gaps.json> <explain.json> <C_ids.json>
"""
import json, sys

TARGETS = {
    "(assoc_status_message_text_has_mention == True)",
    "(assoc_status_message_text_empty == True)",
}
PAIRS = [
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_9930492e_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_evilq_like_public_1_not_found == True)", True)),
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_9930492e_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_evilq_reshare_public_1_not_found == True)", True)),
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_e035b5b3_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_findpublic_reshare_1_public == True)", False)),
]

def cond_var(kind, name):
    return f"({name} != 0)" if kind == "len" else name

def demands(nc):
    d = {}
    for part in (nc or "").split(" AND "):
        s = part.strip(); pol = True
        while s.startswith("Not(") and s.endswith(")"):
            s = s[4:-1].strip(); pol = not pol
        d[s] = pol
    return d

gaps = {g["id"]: g for g in json.load(open(sys.argv[1]))}
ex = json.load(open(sys.argv[2]))["per_gap"]
cids = json.load(open(sys.argv[3]))

a2 = []; b2 = []; untouched = 0; not_target = 0
for gid in cids:
    r = ex[gid]
    tgt = r["first_bad"]
    if tgt not in TARGETS:
        not_target += 1
        continue
    dem = demands(gaps[gid]["node_constraint"])
    hit_full = False
    hit_partial = False
    for (k1, n1, o1), (k2, n2, o2) in PAIRS:
        v1, v2 = cond_var(k1, n1), cond_var(k2, n2)
        d1_ok = dem.get(v1) == o1
        d2_ok = dem.get(v2) == o2
        if d1_ok and d2_ok:
            hit_full = True
        elif (v1 in dem) or (v2 in dem):
            hit_partial = True
    if hit_full:
        a2.append(gid)
    elif hit_partial:
        b2.append(gid)
    else:
        untouched += 1

print(f"C gids examined: {len(cids)}")
print(f"  targeting the 2 conjunction-guarded exprs: {len(cids) - not_target}")
print(f"  NOT one of the 2 targets (untouched, still C): {not_target}")
print(f"  A2-CONJ-PROVISIONAL (matches co-foreclosing pair, NOT falsifier-tested): {len(a2)}")
print(f"  B2-CONJ (mentions a conjunct var, not the foreclosing combo -- new pin candidate): {len(b2)}")
print(f"  still fully unexplained (targets the exprs but neither pair matches): {untouched}")
json.dump(a2, open(sys.argv[3].replace('.json', '_A2CONJ.json'), 'w'))
json.dump(b2, open(sys.argv[3].replace('.json', '_B2CONJ.json'), 'w'))
print("P44-CONJ-RECLASSIFY-DONE")
