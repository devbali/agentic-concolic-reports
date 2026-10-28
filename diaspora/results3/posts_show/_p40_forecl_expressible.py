#!/usr/bin/env python3
"""P40c — can the engine EXPRESS the declared foreclosures at all?

Lead 3 asks for an input channel (`assumptions.py` has no foreclosure kind).
Before building one, the question that decides whether it can pay: for each
declared class `(C, d)`, are **every literal of C** and `d` members of the SAME
demand set?  A foreclosure rung conditions inside a leaf, so a class whose `C`
reaches outside the set is inexpressible however the channel is built -- the
same wall §108.3 measured for §16g (161 of 281 blocks).

Reads `_p39_forecl_classes.json` + `_p39_forecl_gate_results.json` and the
demand-set membership dumped by `_p40_widthprobe2.py`.  Read-only.
Verdict line: `P40C-DONE`.
"""
import json, os, collections
B = os.path.dirname(os.path.abspath(__file__))
CL = json.load(open(f"{B}/_p39_forecl_classes.json"))
RS = {}
for r in json.load(open(f"{B}/_p39_forecl_gate_results.json")):
    key = (json.dumps(r.get("conditioning")), r.get("member"))
    RS[key] = r["verdict"]
S = json.load(open(f"{B}/_p40_sets.json"))
members_all = S["_members_all"]
rem_all = [int(x) for x in S["_rem_all"]]
widths = S["_all_widths"]
setsof = collections.defaultdict(list)
for i, ms in enumerate(members_all):
    for m in ms:
        setsof[m].append(i)

rows = []
for c in CL:
    C = [lit for lit, _o in c["conditioning"]]
    d = c["member"]
    v = RS.get((json.dumps(c["conditioning"]), d), "?")
    ds = set(setsof.get(d, []))
    joint = [i for i in ds if all(lit in members_all[i] for lit in C)]
    inleaf = sum(1 for lit in C if any(lit in members_all[i] for i in ds))
    rows.append({"verdict": v, "C_width": len(C), "d_in_sets": len(ds),
                 "sets_holding_C_and_d": len(joint),
                 "C_literals_reachable_from_d's_sets": inleaf,
                 "remaining_in_those_sets": sum(rem_all[i] for i in joint),
                 "widths_of_those_sets": sorted({widths[i] for i in joint})})
print("=== declared foreclosure classes: is (C,d) EXPRESSIBLE inside one demand set? ===")
agg = collections.Counter()
for r in rows:
    k = f"{r['verdict']:<14} expressible={r['sets_holding_C_and_d']>0}"
    agg[k] += 1
for k, v in sorted(agg.items()):
    print(f"  {v:>3}  {k}")
for v in ("PASS", "NOT-TESTABLE"):
    sub = [r for r in rows if r["verdict"] == v]
    exp = [r for r in sub if r["sets_holding_C_and_d"] > 0]
    print(f"\n  {v}: {len(sub)} classes, {len(exp)} expressible")
    if exp:
        print(f"    remaining in the sets that hold C and d: {sum(r['remaining_in_those_sets'] for r in exp)}")
        print(f"    widths: {sorted({w for r in exp for w in r['widths_of_those_sets']})}")
    part = collections.Counter(f"{r['C_literals_reachable_from_d\'s_sets']}/{r['C_width']}" for r in sub)
    print(f"    C literals present in d's sets (present/total): {dict(part)}")
json.dump(rows, open(f"{B}/_p40_forecl_expressible.json", "w"), indent=1)
print("\nP40C-DONE")
