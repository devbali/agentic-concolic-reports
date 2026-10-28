#!/usr/bin/env python3
"""ROOTED seeds for the two person-identity tree branches X7 opened.

`shareable.rb:72` — `return owned_by_user(user) if person == user.person` — is
now a REAL path condition (it was a decision the mock made silently before X7).
Its expression is a VAR==VAR compare:

    (SYM_PERSON_PS_id == SYM_RESULT_ActiveRecord__FinderMethods_first_1_id)
    (SYM_PERSON_PS_id == SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id)

run_dse.rb's `flip_any` can only flip a var-vs-LITERAL compare, so base
exploration reports both as `unflippable` and the FALSE side — the side on which
`Post.from_person_visible_by_user` builds the DISTINCT share_visibilities join,
i.e. the whole point of X7-iii — is never driven. This is exactly the
rooted-seed case (RUNBOOK Phase 2): take a REAL dump's own seeds (a run that
provably evaluated the expression, on the TRUE side) and move EXACTLY one
dimension — the viewer's person id — to a value the other side cannot equal.

writes _x7_identity_roots.json
"""
import glob, json, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TARGETS = [
    "(SYM_PERSON_PS_id == SYM_RESULT_ActiveRecord__FinderMethods_first_1_id)",
    "(SYM_PERSON_PS_id == SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id)",
]
NB = int(sys.argv[sys.argv.index("--bases") + 1]) if "--bases" in sys.argv else 40
FLIP = 424242   # no id var in this corpus ever seeds to this

bases = defaultdict(list)
n = 0
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    n += 1
    seeds = d.get("concolic_seeds") or {}
    if not seeds:
        continue
    for e in d.get("events") or ():
        if e.get("type") == "path_condition" and e["expr"] in TARGETS and e.get("taken"):
            bases[e["expr"]].append(seeds)
            break

roots, seen = [], set()
for t in TARGETS:
    picked = 0
    for s in bases[t]:
        root = dict(s)
        root["SYM_PERSON_PS_id"] = FLIP
        key = json.dumps(root, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        roots.append(root)
        picked += 1
        if picked >= NB:
            break
    print("%-70s bases=%5d picked=%d" % (t[:70], len(bases[t]), picked))

out = os.path.join(HERE, "_x7_identity_roots.json")
json.dump(roots, open(out, "w"))
print("scanned %d dumps -> %d distinct rooted seeds -> %s" % (n, len(roots), out))
