"""P39 — build the DRIVE subset: the 124 admissible gaps of round 11.

Round 11 (§104) CONSTRUCTED seeds for all 525 gaps and was then stopped on
evidence before any of them was driven — `_p15_driven_seeds_P35C.txt` does not
exist. 124 of the 525 are admissible on BOTH the pins and the gates; the other
401 sit on a base that cannot walk the cube's enabling gates and driving them
is known-futile (§106.1). This writes a SEEDSET label `P39D` holding exactly
the 124, so the drive is the construction attempt those gaps are owed and
nothing else lands in the corpus.
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_SET = "P35C"
DST_SET = os.environ.get("P39_DRIVE_SET", "P39D")
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")

man = json.load(open(os.path.join(HERE, f"_p15_manifest_{SRC_SET}.json")))
keep = [m for m in man
        if m["pins_realised_on_base"]
        and m["gates_walked_on_base"][0] == m["gates_walked_on_base"][1]]
print(f"manifest {len(man)} -> admissible on pins AND gates: {len(keep)}")
print("  by admissibility:", dict(Counter(m["admissibility"] for m in keep)))
print("  by variant:      ", dict(Counter(m["variant"] for m in keep)))

out_man = []
for V in VARIANTS:
    seeds = json.load(open(os.path.join(HERE, f"_p15_seeds{SRC_SET}_{V}.json")))
    mine = [m for m in keep if m["variant"] == V]
    mine.sort(key=lambda m: m["seed_index"])
    sub = []
    for m in mine:
        m2 = dict(m)
        m2["seed_index"] = len(sub)
        m2["seed_set"] = DST_SET
        m2["seed_file"] = f"_p15_seeds{DST_SET}_{V}.json"
        out_man.append(m2)
        sub.append(seeds[m["seed_index"]])
    json.dump(sub, open(os.path.join(HERE, f"_p15_seeds{DST_SET}_{V}.json"), "w"))
    print(f"  {V}: {len(seeds)} -> {len(sub)}")
json.dump(out_man, open(os.path.join(HERE, f"_p15_manifest_{DST_SET}.json"), "w"), indent=1)
print(f"wrote _p15_manifest_{DST_SET}.json with {len(out_man)} seed(s)")
