#!/usr/bin/env python3
"""C27 — MATERIALISE the refuting runs for the 18 refuted §16g classes.

`_c27_fals.py` established the refutations but drained its probe dumps
(keep=False, as the gate does). The engine re-derives §16g on every pass from
the corpus, so a refutation only takes effect once the refuting RUN is in the
dump list. This replays exactly the FAIL probes with keep=True, verifies each
kept dump against the shipped reading (realises every literal of C, records
the member), and writes the verified dump paths.

  usage: python3 _c27_refute_keep.py <fals.json> <out_list.txt> <out_json>
"""
import collections, json, os, sys
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from end_to_end_completion_checker.assumption import assumption_checker as A
import importlib

HERE = os.path.dirname(os.path.abspath(__file__))
FALS, OUT_LIST, OUT_JSON = sys.argv[1], sys.argv[2], sys.argv[3]

cfg = json.load(open(os.path.join(HERE, "assumption_manifest.json")))
mod_name, fn_name = cfg["canonicalize"].split(":")
mod = importlib.import_module(mod_name)
A._CANON_FN = getattr(mod, fn_name); A._ALIASES = list(getattr(mod, "ALIASES", []) or [])

fals = json.load(open(FALS))
refuted = [c for c in fals if c["verdict"] == "FAIL"]
print(f"[in] {len(refuted)} refuted class(es) of {len(fals)}", flush=True)

plans = []      # (class_idx, base_name, seeds, scen)
for c in fals:
    if c["verdict"] != "FAIL":
        continue
    gates = [(g, side == "taken") for g, side in c["conditioning"]]
    for b in c["per_base"]:
        if b["verdict"] != "FAIL":
            continue
        p = os.path.join(HERE, b["base"])
        sd = A.load_dump(p)
        scen = (sd.get("concolic_scenario") or {}).get("name")
        seeds = dict(A.seeds_as_written(sd))
        for g, o in gates:
            if o in A.outcomes_of(sd, g):
                continue
            seeds = A.flipped_seeds(sd, seeds, g, A.expr_dimension(g))
        plans.append((c["class"], b["base"], seeds, scen))

distinct = {}
for ci, bn, seeds, scen in plans:
    distinct.setdefault((scen, json.dumps(seeds, sort_keys=True)), []).append((ci, bn))
print(f"[plan] {len(plans)} FAIL replay(s) -> {len(distinct)} distinct (scenario, seeds) probe(s)",
      flush=True)

cache = A.ProbeCache(cfg, keep=True,
                     checkpoint=os.path.join(HERE, "_c27_achk_probes_keep.jsonl"))
cache.planning = True
for ci, bn, seeds, scen in plans:
    cache.run(seeds, scen, "c27keep")
cache.planning = False
cache.execute()

# The kept dumps are the ones this token wrote into the batch dir.
import glob
kept = sorted(glob.glob(os.path.join(HERE, f"dump_*_achk{A._LABEL_TOKEN}_*.json")))
print(f"[kept] {len(kept)} dump(s) written by this run", flush=True)

# VERIFY each refuted class against the kept dumps, by the shipped reading.
rows, covered = [], set()
for c in fals:
    if c["verdict"] != "FAIL":
        continue
    gates = [(g, side == "taken") for g, side in c["conditioning"]]
    wit = []
    for kp in kept:
        r = A._load_dump_uncached(kp)
        if all(o in A.outcomes_of(r, g) for g, o in gates) and A.recorded(r, c["expr"]):
            wit.append(os.path.basename(kp))
    if wit:
        covered.add(c["class"])
    rows.append({"class": c["class"], "expr": c["expr"],
                 "conditioning": c["conditioning"], "witnesses": wit,
                 "n_witnesses": len(wit)})
    print(f"  [{c['class']:02d}] {len(wit):>3} verified falsifier dump(s)  {c['expr'][:66]}",
          flush=True)

json.dump({"kept_dumps": [os.path.basename(k) for k in kept], "classes": rows},
          open(OUT_JSON, "w"), indent=1)
with open(OUT_LIST, "w") as fh:
    for k in kept:
        fh.write(k + "\n")
print()
print(f"C27-REFUTE-KEEP: {len(kept)} kept dump(s); "
      f"{len(covered)}/{len(refuted)} refuted class(es) have a VERIFIED falsifier in the corpus")
if len(covered) != len(refuted):
    print(f"  *** {len(refuted) - len(covered)} class(es) WITHOUT a kept falsifier: "
          f"{sorted(set(c['class'] for c in refuted) - covered)}")
print("C27-REFUTE-KEEP-DONE")
