#!/usr/bin/env python3
"""P44 — cut a seed set into disjoint SLICES so a width experiment drives real,
never-driven seeds at each width instead of re-driving the same ones.
  usage: _p44_slice_seeds.py <SRC_SET> <DST_SET_1,DST_SET_2,...>
"""
import json, os, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1]; DSTS = sys.argv[2].split(",")
V4 = ("auth_html", "anon_html", "auth_json", "anon_json")
man = json.load(open(os.path.join(HERE, f"_p15_manifest_{SRC}.json")))
by = {v: [] for v in V4}
for m in man:
    by[m["variant"]].append(m)
out = {d: [] for d in DSTS}
for v in V4:
    rows = sorted(by[v], key=lambda m: m["seed_index"])
    seeds = json.load(open(os.path.join(HERE, f"_p15_seeds{SRC}_{v}.json")))
    k = len(DSTS)
    parts = {d: [] for d in DSTS}
    for i, m in enumerate(rows):
        d = DSTS[i % k]
        m2 = dict(m); m2["seed_set"] = d
        m2["seed_file"] = f"_p15_seeds{d}_{v}.json"
        m2["seed_index"] = len(parts[d])
        parts[d].append(seeds[m["seed_index"]])
        out[d].append(m2)
    for d in DSTS:
        json.dump(parts[d], open(os.path.join(HERE, f"_p15_seeds{d}_{v}.json"), "w"))
        print(f"  {d} {v}: {len(parts[d])}")
for d in DSTS:
    json.dump(out[d], open(os.path.join(HERE, f"_p15_manifest_{d}.json"), "w"))
    print(f"{d}: {len(out[d])} seeds -> _p15_manifest_{d}.json")
print("P44-SLICE-DONE")
