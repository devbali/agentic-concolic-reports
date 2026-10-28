#!/usr/bin/env python3
"""RECONCILE: the confinement agent finds 602 ANY-AND pairs on this snapshot;
my engine census reports `overlapping 0`. Where did the 602 go?

Three possible homes, and only one of them is a bug:
  DISQUALIFIED — the AND shape made one member TWO-SIDED, so the pair never
                 reached the OR test. Sound.
  UNDECIDABLE  — a member has no measured footprint. Sound.
  CONFINED     — licensed despite an AND shape. THAT IS A BUG and stops the drive.

Uses the engine's own `project_confinement` — the same call the census and the
checker make — so this classifies pairs by the shipped rule, not a copy of it.
"""
import importlib, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
EE = importlib.import_module("_exact_enum_emit")
from coverage_assumptions import build as build_assumptions
from concolic_engine.assumptions import call_shape, shape_str
from concolic_engine.coverage import project_confinement

runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
assert U is not None
pkey = getattr(EE, "_pkey", None)
if pkey is None:
    from concolic_engine.coverage import profile_key as pkey
idx, union, inter, shape_id = {}, [], [], {}
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
    k = pkey(outcomes)
    i = idx.get(k)
    if i is None:
        idx[k] = len(union); union.append(tr); inter.append(tr)
    else:
        union[i] |= tr; inter[i] &= tr
side_seen = {}
for run in U["runs"]:
    outcomes = {}
    for pc in run.path_conditions:
        outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
    tr = 0
    for ev in run.symbolic_call_events:
        if ev.result_name:
            j = shape_id.get(call_shape(ev.target_name, ev.note, ev.args))
            if j is not None:
                tr |= 1 << j
    if not tr:
        continue
    for e, os_ in outcomes.items():
        k = 2 if len(os_) > 1 else (1 if True in os_ else 0)
        side_seen.setdefault(e, [0, 0, 0])[k] |= tr
pj = project_confinement(U["active"], U["expr_order"], U["run_outcomes"], union, inter,
                         side_seen, [frozenset(c) for c in U["cliques"]], U["by_gate"],
                         U["bit"], int(os.environ.get("MAX_CLIQUES", "16384")))
fp, ctxn, disq = pj["footprint"], pj["ctxn"], pj["disqualified"]
decided = {e for e in U["active"] if ctxn.get(e, 0)}
print(f"active {len(U['active'])} | decided {len(decided)} | disqualified {len(disq)}")

def klass(a, b):
    if a not in decided or b not in decided:
        return "UNDECIDABLE"
    if a in disq or b in disq:
        return "DISQUALIFIED"
    return "CONFINED"

# every co-evaluated non-gate pair, classified
from collections import Counter
co = Counter()
pairs_by_class = {}
act = sorted(U["active"])
prof = U["run_outcomes"]
coev = set()
for o in prof:
    es = sorted(e for e in o if e in set(act))
    for i, a in enumerate(es):
        for b in es[i+1:]:
            coev.add((a, b))
for a, b in coev:
    k = klass(a, b)
    co[k] += 1
    pairs_by_class.setdefault(k, []).append((a, b))
print("co-evaluated pair classes:", dict(co))

NAMED = [
    ("findpublic_like", "findpublic_reshare"),
    ("Person", "name"),
    ("photos", "mentions"),
]
print("\n=== the three named AND examples, classified under MY census ===")
for pat in NAMED:
    hits = [(a, b) for (a, b) in coev
            if all(any(p in x for x in (a, b)) for p in pat)]
    print(f"\n  pattern {pat}: {len(hits)} co-evaluated pairs")
    seen = Counter(klass(a, b) for a, b in hits)
    print(f"    classes: {dict(seen)}")
    for a, b in hits[:3]:
        print(f"      [{klass(a,b)}] {a[:78]}\n                   {b[:78]}")
bad = [(a, b) for (a, b) in coev if klass(a, b) == "CONFINED"]
json.dump({"classes": dict(co),
           "confined_sample": [[a, b] for a, b in bad[:200]],
           "disqualified_decisions": sorted(disq)[:200],
           "undecidable_decisions": sorted(e for e in U["active"] if not ctxn.get(e, 0))},
          open(os.path.join(HERE, "_and_reconcile.json"), "w"), indent=1)
print("\nwrote _and_reconcile.json")
