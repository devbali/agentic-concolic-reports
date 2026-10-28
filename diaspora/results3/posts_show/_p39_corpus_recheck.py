"""P39 — CORPUS-SIDE RE-CHECK of the 95 declared foreclosures.

Independent of the gate. §110's classes were exported from a 48 943-profile
snapshot; §112 then added 625 witness dumps and the engine's OWN §16f count
halved. This asks the same question of MY 95 classes on those 625 profiles: does
any of them realise a class's C and EVALUATE its member d? A hit is a
corpus-side refutation that owes nothing to the constructor.

Read-only. Uses the batch's own canonicalization (`gate_canon`), so the names
compared are the names the engine built its universe from (§94.0's name join).
"""
import json, os, sys
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gate_canon import canonicalize_for_gate

HERE = os.path.dirname(os.path.abspath(__file__))
cls = json.load(open(os.path.join(HERE, "_p39_forecl_classes.json")))
paths = [l.strip() for l in open(os.path.join(HERE, "_p39_new625.txt")) if l.strip()]
print(f"{len(cls)} classes vs {len(paths)} profiles", flush=True)

def outcomes(dump):
    """expr -> set of outcomes taken. EXACTLY `assumption_checker._outcomes_of_dump`
    (`:1086-1091`): the events list carries `type == "path_condition"` records,
    not a nested `path_conditions` array."""
    out = {}
    for ev in dump.get("events") or []:
        if ev.get("type") == "path_condition":
            out.setdefault(str(ev.get("expr", "")), set()).add(bool(ev.get("taken")))
    return out

hits, realised, seen = 0, 0, 0
per = {}
for i, p in enumerate(paths):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    canonicalize_for_gate(d)
    o = outcomes(d)
    if not o:
        continue
    seen += 1
    for k, c in enumerate(cls):
        if all(o.get(e) == {bool(v)} for e, v in c["conditioning"]):
            realised += 1
            if o.get(c["member"]):
                hits += 1
                per.setdefault(k, []).append(os.path.basename(p))
    if (i + 1) % 200 == 0:
        print(f"  {i+1}/{len(paths)}  C-realisations {realised}  refutations {hits}",
              flush=True)

print(f"\nRESULT: {seen} profiles parsed with path conditions")
print(f"  (profile, class) pairs realising C            : {realised}")
print(f"  ...of which the member d was EVALUATED (FAIL) : {hits}")
print(f"  classes refuted from the corpus               : {len(per)} of {len(cls)}")
for k, v in list(per.items())[:10]:
    print(f"    class {k}: {cls[k]['member'][:60]}  <- {v[:2]}")
