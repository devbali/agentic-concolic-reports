#!/usr/bin/env python3
"""P44 — why did the constructed run not REACH `assoc_status_message_*`?
Compares, for each failing gap: did the BASE evaluate it, did the DRIVEN run,
and which seed keys changed between base and driven that plausibly suppress it."""
import json, os, re, sys
from collections import Counter, defaultdict
HERE = "/home/dev/project/reports/diaspora/results3/posts_show"
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

ex = json.load(open(f"{HERE}/_p44_explain_P39D.json"))["per_gap"]
man = {m["gap"]: m for m in json.load(open(f"{HERE}/_p15_manifest_P39D.json"))}
gaps = {g["id"]: g for g in json.load(open(f"{HERE}/_p31_gaps_P35C.json"))}
sc = {}
def seed_of(m):
    f = m["seed_file"]
    if f not in sc:
        sc[f] = json.load(open(os.path.join(HERE, f)))
    return sc[f][m["seed_index"]]
def outcomes(p):
    d = json.load(open(os.path.join(HERE, p)))
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    t = defaultdict(set)
    for e in ev:
        if e.get("type") == "path_condition":
            t[fixlen(rn(str(e.get("expr", ""))))].add(bool(e.get("taken")))
    sd = {}
    for sv in (d.get("symbolic_vars") or ()):
        sd[fixlen(rn(str(sv.get("name"))))] = sv.get("value")
    return t, sd, (d.get("concolic_seeds") or {})

BASE_HAS = Counter(); SEEDDIFF = Counter()
rows = []
for gid, r in ex.items():
    if r["walked"] or r["first_bad_v"] != "never_evaluated":
        continue
    tgt = r["first_bad"]
    m = man[gid]
    bt, bs, bseed = outcomes(m["base"])
    dt, ds, dseed = outcomes(r["dump"])
    BASE_HAS[(tgt[:60], "base evaluated it" if tgt in bt else "base did NOT evaluate it",
              "driven evaluated it" if tgt in dt else "driven did NOT")] += 1
    if tgt in bt and tgt not in dt:
        for k in sorted(set(bseed) | set(dseed)):
            if bseed.get(k) != dseed.get(k):
                SEEDDIFF[(tgt[:44], k[:60], repr(bseed.get(k)), repr(dseed.get(k)))] += 1
    rows.append({"gap": gid, "target": tgt, "base_eval": tgt in bt,
                 "driven_eval": tgt in dt, "base": m["base"], "dump": r["dump"]})
print("REACH of the first never-evaluated literal: base vs driven")
for k, n in BASE_HAS.most_common():
    print(f"   {n:4d}  {k[1]:26s} {k[2]:22s} {k[0]}")
print()
print("SEED KEYS that DIFFER between base and driven where the BASE reached it "
      "and the driven run did not (top 25)")
for k, n in SEEDDIFF.most_common(25):
    print(f"   {n:4d}  {k[1]:58s} {k[2]:>6s} -> {k[3]:<6s}  [{k[0]}]")
json.dump(rows, open(f"{HERE}/_p44_assocdiag.json", "w"), indent=1)
print("P44-ASSOCDIAG-DONE")
