#!/usr/bin/env python3
"""P44 — localise the control MISSES. For every miss, the demanded literal, the
seed keys the constructor wrote that could steer it, the value written, and the
value the driven dump actually produced."""
import json, os, re, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

rows = json.load(open(os.path.join(HERE, "_p44_hitrate_rows.json")))["rows"]
ctrl = {c["id"]: c for c in json.load(open(os.path.join(HERE, "_p44_ctrl_gaps_C1.json")))}
man = {m["gap"]: m for m in json.load(open(os.path.join(HERE, "_p15_manifest_CTRL1.json")))}
ex = json.load(open(os.path.join(HERE, "_p44_explain_CTRL1.json")))["per_gap"]
seeds_cache = {}
def seeds_for(m):
    f = m["seed_file"]
    if f not in seeds_cache:
        seeds_cache[f] = json.load(open(os.path.join(HERE, f)))
    return seeds_cache[f][m["seed_index"]]

EXPR = Counter(); SHAPE = Counter(); DET = []
for r in rows:
    if r["cls"] == "HIT":
        continue
    gid = r["id"]; m = man[gid]; c = ctrl[gid]
    bad = r["first_bad"]
    EXPR[bad] += 1
    mm = re.match(r"^\((SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\)$", bad or "")
    L = mm.group(1) if mm else None
    sd = seeds_for(m)
    # every seed key that spells this length, raw ordinal or canonical
    keys = {k: v for k, v in sd.items() if L and k.startswith("len(")}
    # demanded polarity
    want = None
    for lit in c["node_constraint"].split(" AND "):
        s = lit.strip(); pol = True
        if s.startswith("Not(") and s.endswith(")"):
            s, pol = s[4:-1], False
        if s == bad:
            want = pol
    # the driven dump
    d = json.load(open(os.path.join(HERE, ex[gid]["dump"])))
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    got = defaultdict(set)
    for e in ev:
        if e.get("type") == "path_condition":
            got[fixlen(rn(str(e.get("expr", ""))))].add(bool(e.get("taken")))
    # raw ordinals that canonicalise to L
    raws = sorted(k for k in keys if fixlen(rn(k[4:-1])) == L) if L else []
    nonraw = sorted(k for k in keys if k not in raws)
    SHAPE[(L, want, tuple(sorted(keys[k] for k in raws)) if raws else None,
           "seeded" if raws else "NO SEED KEY canonicalises to the demanded length")] += 1
    DET.append({"gap": gid, "want": want, "expr": bad, "len": L,
                "seed_keys_for_L": {k: keys[k] for k in raws},
                "other_len_keys": len(nonraw),
                "dump_outcomes": sorted(got.get(bad, ())),
                "base": m["base"], "witness": c["ctrl_dump"],
                "values_written": m["values_written"],
                "governor_pins": m["governor_pins"],
                "governor_split_pins": m["governor_split_pins"]})

print("MISSES by failing expression")
for k, n in EXPR.most_common(15):
    print(f"   {n:5d}  {k}")
print()
print("MISSES by (length var, demanded, seeded raw-ordinal values, shape)")
for k, n in SHAPE.most_common(20):
    L = (k[0] or "")[len("SYM_LEN_SYM_RESULT_ActiveRecord__"):]
    print(f"   {n:5d}  want={str(k[1]):5s} raw_seeds={k[2]}  {k[3]:12s} {L[:52]}")
print()
nokey = sum(1 for d in DET if not d["seed_keys_for_L"])
print(f"misses where NO seed key spells the contradicted length : {nokey} / {len(DET)}")
print(f"misses where the seed DID write it and the run ignored it: {len(DET)-nokey}")
json.dump(DET, open(os.path.join(HERE, "_p44_missdiag.json"), "w"), indent=1)
print("P44-MISSDIAG-DONE")
