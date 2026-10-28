#!/usr/bin/env python3
"""C14 — the RESIDUE, classified per key with CONSTRUCTION evidence.

Nothing below is called residue on the strength of "no run produced it": every
one of the checker's remaining witness leaves is joined to
  * whether a C14 seed was BUILT for that exact cube and DRIVEN (C14A / C14B),
  * the per-key verdict the classifier gave those replays
    (HONOURED / CONTRADICTED / NEVER-EVALUATED), and
  * the §19.2 falsifier for the member: does ANY run in the corpus match the
    cube's gate conjunction prefix and evaluate that member (B > 0)?

writes _c14_residue.json
"""
import json, os
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CK   = os.environ.get("C14_CKPT", os.path.join(HERE, "_cov_c14_C14R2.ckpt.jsonl"))
OUT  = os.path.join(HERE, "_c14_residue.json")

def witnesses(p):
    f = open(p); json.loads(f.readline())
    w = {}
    for line in f:
        r = json.loads(line)
        for c in (r["v"].get("combos") or []):
            w.setdefault(tuple(sorted({(e, bool(t)) for e, t in c})), set()).add(r["k"])
    return w

W = witnesses(CK)
print(f"{os.path.basename(CK)}: {len(W)} distinct witness leaves over "
      f"{len({k for s in W.values() for k in s})} gap-sets")

# --- what the C14 rounds built and drove, and what the classifier said
built = {}
for gapfile, clsfile, tag in (("_c14_gaps.json", "_c14_classify_C14A.json", "C14A"),
                              ("_c14_gaps_R2.json", "_c14_classify_C14B.json", "C14B")):
    gaps = json.load(open(os.path.join(HERE, gapfile)))
    cls = json.load(open(os.path.join(HERE, clsfile)))
    pg = cls["per_gap"]
    for g in gaps:
        key = tuple(sorted({(e, bool(o)) for e, o in g["cube"]}))
        built.setdefault(key, []).append((tag, pg.get(g["id"], "?")))

# --- the §19.2 falsifier, per (leaf group, member), from the R2 computation
fals = json.load(open(os.path.join(HERE, "_c14_falsifier_R2.json")))
B0 = set()
for gid, row in fals["groups"].items():
    for e, b in row["member_B"].items():
        if b == 0:
            B0.add(e)

# --- per-key verdicts from the two classifiers, aggregated over the expr
never = Counter(); contra = Counter()
for f in ("_c14_classify_C14A.json", "_c14_classify_C14B.json"):
    c = json.load(open(os.path.join(HERE, f)))
    for e, n in c["never_evaluated"]:
        never[e] += n
    for e, n in c["contradicted"]:
        contra[e] += n

rows, agg = [], Counter()
for cube, sets in sorted(W.items(), key=lambda kv: -len(kv[0])):
    b = built.get(cube, [])
    verd = [v for _t, v in b]
    keys = []
    for e, o in cube:
        keys.append({"expr": e, "outcome": o,
                     "b0_under_its_gate_conjunction": e in B0,
                     "never_evaluated_in_replays": never.get(e, 0),
                     "contradicted_in_replays": contra.get(e, 0)})
    cls = ("CONTRADICTED" if "CONTRADICTED" in verd else
           "REALISED-BY-CLASSIFIER" if "REALISED" in verd else
           "UNEVALUATED" if verd else "NOT-IN-ANY-C14-BATCH")
    agg[cls] += 1
    agg["sets:" + cls] += len(sets)
    rows.append({"width": len(cube), "sets": sorted(sets), "driven": b,
                 "verdict": cls,
                 "b0_members": sum(1 for k in keys if k["b0_under_its_gate_conjunction"]),
                 "keys": keys})

print("\n=== THE 103 GAP-SETS' WITNESS LEAVES, by CONSTRUCTION EVIDENCE ===")
for k in ("CONTRADICTED", "UNEVALUATED", "REALISED-BY-CLASSIFIER",
          "NOT-IN-ANY-C14-BATCH"):
    print(f"  {k:24s} leaves {agg.get(k,0):4d}   gap-sets {agg.get('sets:'+k,0):4d}")
nb = Counter(r["b0_members"] > 0 for r in rows)
print(f"\n  leaves with at least one member that is B=0 under its own gate "
      f"conjunction: {nb[True]} of {len(rows)}")
ex = Counter()
for r in rows:
    for k in r["keys"]:
        if k["b0_under_its_gate_conjunction"]:
            ex[k["expr"]] += 1
print("  the B=0 members, by how many remaining leaves demand them:")
for e, n in ex.most_common(20):
    print(f"    {n:4d}  {e[:105]}")
json.dump({"checkpoint": os.path.basename(CK), "aggregate": dict(agg),
           "leaves": rows}, open(OUT, "w"), indent=1)
print(f"\nC14-RESIDUE-DONE {OUT}")
